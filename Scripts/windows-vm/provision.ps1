# Provisions Bouncer's Windows test VM on first logon, then shuts it down so windows-vm.sh can
# tell provisioning finished. Runs from the config ISO beside authorized_keys and versions.txt.
# Progress is logged to C:\provision.log, readable over SSH once that step is done.
#
# A restart mid-way (Windows Update, a driver) would otherwise end provisioning for good, since
# first-logon commands run once. So the script copies itself to C:\provision and re-runs from the
# machine Run key at every logon until it succeeds; every step skips work that's already done.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Start-Transcript -Path C:\provision.log -Append
$mutex = New-Object System.Threading.Mutex($false, 'Global\BouncerProvision')
if (-not $mutex.WaitOne(0)) { exit 0 }
$source = 'C:\provision'
if ($PSScriptRoot -ne $source) { Copy-Item -Recurse -Force $PSScriptRoot $source -ErrorAction SilentlyContinue }
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$command = "powershell -NoProfile -ExecutionPolicy Bypass -File $source\provision.ps1"
New-ItemProperty -Path $runKey -Name BouncerProvision -Value $command -Force | Out-Null
$versions = Get-Content (Join-Path $source 'versions.txt') -Raw | ConvertFrom-StringData
$downloads = 'C:\provision-downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null

# Installs the virtio network driver from whichever attached drive holds the virtio-win ISO.
# Setup's offline driver injection can miss it, since drive letters differ between WinPE and Windows.
function Install-NetworkDriver {
    if (pnputil /enum-drivers | Select-String -SimpleMatch 'netkvm.inf') { return }
    $inf = Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root 'NetKVM\w11\ARM64\netkvm.inf' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $inf) { throw 'virtio-win drive with NetKVM\w11\ARM64 not found' }
    pnputil /add-driver $inf /install | Out-Host
}

# Waits until the internet is reachable, since every later step downloads something.
function Wait-Network {
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-NetConnection download.swift.org -Port 443 -InformationLevel Quiet) { return }
        Start-Sleep -Seconds 5
    }
    throw 'no network after 5 minutes'
}

# Downloads a URL into the downloads folder and returns the local path.
function Save-Download([string]$Url, [string]$Name) {
    $path = Join-Path $downloads $Name
    if (-not (Test-Path $path)) { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $path }
    return $path
}

# Runs an installer and fails unless it exits 0 or 3010 (success, reboot pending).
function Invoke-Installer([string]$Path, [string[]]$Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) { throw "$Path exited with $($process.ExitCode)" }
}

# Installs OpenSSH Server from Microsoft's Win32-OpenSSH MSI, unless it's already there. The MSI is
# used rather than the Windows capability, which downloads slowly through Windows Update.
function Install-OpenSshServer {
    if (Get-Service sshd -ErrorAction SilentlyContinue) { return }
    $release = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$($versions.openssh_tag)"
    $msi = Save-Download "$release/OpenSSH-ARM64-v$($versions.openssh).msi" 'openssh.msi'
    Invoke-Installer msiexec.exe @('/i', $msi, '/qn')
}

# Allows key-only login for administrators, with Windows PowerShell as the default shell.
function Set-SshAccess {
    New-Item -ItemType Directory -Force C:\ProgramData\ssh | Out-Null
    $keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
    Copy-Item (Join-Path $source 'authorized_keys') $keys -Force
    icacls $keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
    $shell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value $shell -Force | Out-Null
}

# Installs, configures, and starts the SSH server, and opens port 22.
function Install-Ssh {
    Install-OpenSshServer
    Set-SshAccess
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
    if (Get-NetFirewallRule -Name BouncerSsh -ErrorAction SilentlyContinue) { return }
    New-NetFirewallRule -Name BouncerSsh -DisplayName 'OpenSSH Server' -Protocol TCP -LocalPort 22 -Action Allow |
        Out-Null
}

# Installs PowerShell 7 from its ARM64 zip, since there's no ARM64 MSI, and puts it on the machine PATH.
function Install-Pwsh {
    $version = $versions.pwsh
    $url = "https://github.com/PowerShell/PowerShell/releases/download/v$version/PowerShell-$version-win-arm64.zip"
    $zip = Save-Download $url 'pwsh.zip'
    Expand-Archive -Path $zip -DestinationPath 'C:\Program Files\PowerShell\7' -Force
    Add-MachinePath 'C:\Program Files\PowerShell\7'
}

# Installs the MSVC (ARM64 and x64) compilers and Windows SDK that Swift on Windows links against.
function Install-BuildTools {
    $installer = Save-Download 'https://aka.ms/vs/17/release/vs_BuildTools.exe' 'vs_BuildTools.exe'
    Invoke-Installer $installer @(
        '--quiet', '--wait', '--norestart', '--nocache',
        '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22621',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.ARM64',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    )
}

# Installs Git for Windows, which SwiftPM needs to fetch package dependencies; the Swift installer
# doesn't include it.
function Install-Git {
    if (Test-Path 'C:\Program Files\Git\cmd\git.exe') { return }
    $release = "https://github.com/git-for-windows/git/releases/download/$($versions.git_tag)"
    $installer = Save-Download "$release/Git-$($versions.git)-arm64.exe" 'git.exe'
    Invoke-Installer $installer @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-')
}

# Installs the swift.org ARM64 toolchain pinned in versions.txt.
function Install-Swift {
    $version = $versions.swift
    $name = "swift-$version-RELEASE-windows10-arm64.exe"
    $url = "https://download.swift.org/swift-$version-release/windows10-arm64/swift-$version-RELEASE/$name"
    Invoke-Installer (Save-Download $url $name) @('/quiet', '/norestart')
}

# Appends a directory to the machine PATH if it isn't already there.
function Add-MachinePath([string]$Dir) {
    $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (($path -split ';') -contains $Dir) { return }
    [Environment]::SetEnvironmentVariable('Path', "$path;$Dir", 'Machine')
}

try {
    powercfg /change standby-timeout-ac 0
    powercfg /hibernate off
    Install-NetworkDriver
    Wait-Network
    Install-Ssh
    Install-Pwsh
    Install-BuildTools
    Install-Git
    Install-Swift
    Remove-ItemProperty -Path $runKey -Name BouncerProvision
    Set-Content C:\provision.done (Get-Date -Format o)
    Write-Host 'Provisioning finished.'
} catch {
    Write-Host "Provisioning failed: $_"
    Set-Content C:\provision.failed "$_"
} finally {
    Stop-Transcript
    shutdown /s /t 10
}
