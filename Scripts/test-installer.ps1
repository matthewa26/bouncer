# Runs install.ps1's PowerShell half against a fake release asset served from a file:// URL,
# checking that it installs a verified download and refuses a corrupted one. Used by CI on
# Windows, under both Windows PowerShell 5.1 and PowerShell 7.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ("bouncer-installer-test-" + [Guid]::NewGuid())
$assets = Join-Path $work 'assets'
New-Item -ItemType Directory -Force (Join-Path $assets 'pkg') | Out-Null

Copy-Item "$env:SystemRoot\System32\whoami.exe" (Join-Path $assets 'pkg\bouncer.exe')
$zip = Join-Path $assets 'bouncer-windows-x86_64.zip'
Compress-Archive -Path (Join-Path $assets 'pkg\*') -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Set-Content (Join-Path $assets 'SHA256SUMS') "$hash  bouncer-windows-x86_64.zip"

$env:BOUNCER_DOWNLOAD_URL = ([Uri]$assets).AbsoluteUri
$env:BOUNCER_NO_MODIFY_PATH = '1'
$installer = Get-Content -Raw (Join-Path $root 'install.ps1')

$env:BOUNCER_INSTALL_DIR = Join-Path $work 'bin'
Invoke-Expression $installer
if (-not (Test-Path (Join-Path $env:BOUNCER_INSTALL_DIR 'bouncer.exe'))) { throw 'bouncer.exe was not installed' }

Add-Content $zip 'corrupted'
$env:BOUNCER_INSTALL_DIR = Join-Path $work 'bin2'
$rejected = $false
try { Invoke-Expression $installer } catch { $rejected = $_.Exception.Message -like '*checksum mismatch*' }
if (-not $rejected) { throw 'installer accepted a corrupted download' }
Remove-Item -Recurse -Force $work
Write-Host 'installer test passed'
# The installer runs the fake bouncer.exe, which fails on purpose; don't let its exit code become ours.
exit 0
