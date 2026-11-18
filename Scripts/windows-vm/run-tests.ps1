# Runs Bouncer's Windows tests inside the test VM, from a checkout copied in by windows-vm.sh.
# Exits non-zero if any step fails, after running every step so one failure doesn't hide others.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$failures = @()

# Runs one named step, recording a failure instead of stopping the run.
function Invoke-Step([string]$Name, [scriptblock]$Body) {
    Write-Host "`n=== $Name"
    try {
        $global:LASTEXITCODE = 0
        & $Body
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
        Write-Host "=== PASS: $Name"
    } catch { Write-Host "=== FAIL: $Name - $_"; $script:failures += $Name }
}

# Writes a TypeScript file that should produce explicit-any and non-null-assertion findings.
function New-Sample {
    $sample = Join-Path $root '.build\vm-sample'
    New-Item -ItemType Directory -Force $sample | Out-Null
    Set-Content (Join-Path $sample 'a.ts') "export const f = (a: any) => a!;"
    return $sample
}

# Installs the packaged zip with install.ps1 from file:// assets, then analyzes a TypeScript file with it.
function Test-RealInstall([string]$Shell) {
    $dir = Join-Path $root ".build\vm-install-$Shell"
    $env:BOUNCER_DOWNLOAD_URL = ([Uri](Join-Path $root '.build\vm-assets')).AbsoluteUri
    $env:BOUNCER_INSTALL_DIR = $dir; $env:BOUNCER_NO_MODIFY_PATH = '1'
    & $Shell -NoProfile -Command 'Get-Content -Raw install.ps1 | Invoke-Expression'
    $output = & (Join-Path $dir 'bouncer.exe') review (New-Sample) | Out-String
    Write-Host $output
    foreach ($rule in 'explicit-any', 'non-null-assertion') {
        if ($output -notmatch $rule) { throw "missing the expected $rule finding" }
    }
}

Invoke-Step 'swift build' { swift build }
Invoke-Step 'swift test' { swift test }
Invoke-Step 'package (release script)' {
    $zip = Join-Path $root '.build\vm-assets\bouncer-windows-x86_64.zip'
    & (Join-Path $root 'Scripts\package-windows.ps1') -Output $zip
    $hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    Set-Content (Join-Path (Split-Path $zip) 'SHA256SUMS') "$hash  bouncer-windows-x86_64.zip"
}
Invoke-Step 'installer test, Windows PowerShell 5.1' { powershell -NoProfile -File Scripts\test-installer.ps1 }
Invoke-Step 'installer test, PowerShell 7' { pwsh -NoProfile -File Scripts\test-installer.ps1 }
Invoke-Step 'real install and review, Windows PowerShell 5.1' { Test-RealInstall powershell }
Invoke-Step 'real install and review, PowerShell 7' { Test-RealInstall pwsh }

if ($failures.Count -gt 0) {
    Write-Host "`nFAILED: $($failures -join ', ')"
    exit 1
}
Write-Host "`nAll Windows tests passed."
