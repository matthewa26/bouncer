# Packages a release build of bouncer.exe with the Swift runtime DLLs it loads, so it runs on
# machines without Swift, then checks the zip's exe runs with the toolchain off PATH.
# Used by the release workflow and by the Windows VM tests (Scripts/windows-vm).
param(
    # The zip to write, such as dist/bouncer-windows-x86_64.zip.
    [Parameter(Mandatory)][string]$Output,
    # Extra `swift build` arguments, such as a cross-compilation triple.
    [string[]]$BuildArguments = @()
)
$ErrorActionPreference = 'Stop'

swift build -c release @BuildArguments
if ($LASTEXITCODE -ne 0) { throw 'swift build failed' }
$bin = swift build -c release @BuildArguments --show-bin-path
# The swift.org installer puts the runtime DLLs on PATH; ship them next to the exe.
$runtime = Split-Path (where.exe swiftCore.dll | Select-Object -First 1)

$work = Join-Path ([IO.Path]::GetTempPath()) ("bouncer-package-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Force (Join-Path $work 'package'), (Split-Path -Parent $Output) | Out-Null
Copy-Item (Join-Path $bin 'bouncer.exe') (Join-Path $work 'package')
Copy-Item (Join-Path $runtime '*.dll') (Join-Path $work 'package')
Compress-Archive -Force -Path (Join-Path $work 'package\*') -DestinationPath $Output

Expand-Archive $Output -DestinationPath (Join-Path $work 'check')
$savedPath = $env:Path
$env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
try { & (Join-Path $work 'check\bouncer.exe') --version } finally { $env:Path = $savedPath }
if ($LASTEXITCODE -ne 0) { throw 'the packaged bouncer.exe does not run without the toolchain on PATH' }
Remove-Item -Recurse -Force $work
