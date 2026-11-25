echo --% >/dev/null;: ' | out-null
<#'
# Bouncer installer: one file that runs under both POSIX sh and PowerShell.
#
#   macOS, Linux, WSL:   curl -fsSL https://matthewa26.github.io/bouncer/install.ps1 | sh
#   Windows PowerShell:  irm https://matthewa26.github.io/bouncer/install.ps1 | iex
#
# How the polyglot works: sh runs `echo` into /dev/null, then the `:` no-op swallows the quoted
# text up to `<#'`, runs the sh half below, and exits before reaching PowerShell syntax.
# PowerShell treats `--%` as stop-parsing, discards that line's output, and reads the rest of
# the sh half as one block comment, so only the PowerShell half runs. Never write the block
# comment's closing token (a hash followed by a greater-than sign) anywhere in the sh half.
#
# Environment variables (both halves):
#   BOUNCER_VERSION       Version to install, such as 0.2.0, from its GitHub release. Default: the
#                         latest release, from the documentation site's download/latest folder.
#   BOUNCER_INSTALL_DIR   Where to put the binary. Default: ~/.local/bin, or
#                         %LOCALAPPDATA%\Programs\bouncer on Windows.
#   BOUNCER_REPO          GitHub owner/repo to download from. Default: matthewa26/bouncer.
#   BOUNCER_DOWNLOAD_URL  Base URL holding the release assets, overriding both of the above
#                         (for mirrors and for testing unreleased builds).
#   BOUNCER_NO_MODIFY_PATH  Windows only: set to 1 to skip adding the install dir to PATH.

set -eu

# Prints an error naming the installer and exits.
fail() { echo "bouncer install: $*" >&2; exit 1; }

# Prints the release asset name for this OS and CPU.
asset_name() {
  os=$(uname -s)
  arch=$(uname -m)
  case "$arch" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) fail "unsupported CPU architecture: $arch" ;;
  esac
  case "$os" in
    Darwin) echo "bouncer-macos-universal.tar.gz" ;;
    Linux) echo "bouncer-linux-$arch.tar.gz" ;;
    MINGW* | MSYS* | CYGWIN*) fail "on Windows, run this installer from PowerShell instead" ;;
    *) fail "unsupported operating system: $os" ;;
  esac
}

# Downloads URL $1 to file $2 with curl or wget.
download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1" || fail "download failed: $1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1" || fail "download failed: $1"
  else
    fail "curl or wget is required"
  fi
}

# Prints the SHA-256 of file $1.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    fail "sha256sum or shasum is required to verify the download"
  fi
}

repo=${BOUNCER_REPO:-matthewa26/bouncer}
if [ -n "${BOUNCER_DOWNLOAD_URL:-}" ]; then
  base=$BOUNCER_DOWNLOAD_URL
elif [ -n "${BOUNCER_VERSION:-}" ]; then
  base="https://github.com/$repo/releases/download/v${BOUNCER_VERSION#v}"
else
  base="https://${repo%%/*}.github.io/${repo#*/}/download/latest"
fi
install_dir=${BOUNCER_INSTALL_DIR:-$HOME/.local/bin}
asset=$(asset_name)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $asset from $base"
download "$base/$asset" "$tmp/$asset"
download "$base/SHA256SUMS" "$tmp/SHA256SUMS"

expected=$(awk -v name="$asset" '$2 == name || $2 == "*" name { print $1 }' "$tmp/SHA256SUMS")
[ -n "$expected" ] || fail "SHA256SUMS has no entry for $asset"
[ "$(sha256_of "$tmp/$asset")" = "$expected" ] || fail "checksum mismatch for $asset"

tar -xzf "$tmp/$asset" -C "$tmp"
mkdir -p "$install_dir"
cp "$tmp/bouncer" "$install_dir/bouncer"
chmod 755 "$install_dir/bouncer"
if [ -f "$tmp/bouncer.1" ]; then
  # man looks for pages in the share/man beside each bin directory on PATH.
  man_dir="$(dirname "$install_dir")/share/man/man1"
  mkdir -p "$man_dir" && cp "$tmp/bouncer.1" "$man_dir/bouncer.1"
fi
echo "Installed $("$install_dir/bouncer" --version 2>/dev/null || echo bouncer) to $install_dir/bouncer"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) echo "Add $install_dir to your PATH, for example: export PATH=\"$install_dir:\$PATH\"" ;;
esac
exit 0
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Stops the install with a message naming the installer.
function Stop-Install([string]$Message) {
    throw "bouncer install: $Message"
}

# Picks the release asset for this machine; on Windows that's always the x86_64 zip for now.
function Get-AssetName {
    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        Stop-Install 'on macOS and Linux, run this installer with sh instead: curl -fsSL <url> | sh'
    }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') { Write-Host 'No native ARM64 build yet; installing x86_64, which runs under emulation.' }
    elseif ($arch -ne 'AMD64') { Stop-Install "unsupported CPU architecture: $arch" }
    return 'bouncer-windows-x86_64.zip'
}

# Resolves where to download from: an explicit mirror, a pinned release, or the latest release on
# the documentation site.
function Get-BaseUrl {
    $repo = if ($env:BOUNCER_REPO) { $env:BOUNCER_REPO } else { 'matthewa26/bouncer' }
    if ($env:BOUNCER_DOWNLOAD_URL) { return $env:BOUNCER_DOWNLOAD_URL }
    $owner, $name = $repo.Split('/', 2)
    if (-not $env:BOUNCER_VERSION) { return "https://$owner.github.io/$name/download/latest" }
    return "https://github.com/$repo/releases/download/v$($env:BOUNCER_VERSION.TrimStart('v'))"
}

# Downloads a URL to a file; a file:// URL is copied directly, since PowerShell 7 can't fetch one.
function Save-Url([string]$Url, [string]$OutFile) {
    $uri = [Uri]$Url
    if ($uri.IsFile) { Copy-Item -LiteralPath $uri.LocalPath -Destination $OutFile; return }
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile
}

# Verifies a download against its SHA256SUMS entry, stopping the install on any mismatch.
function Test-Checksum([string]$File, [string]$Sums, [string]$Name) {
    $line = Get-Content $Sums | Where-Object { ($_ -split '\s+')[1] -in @($Name, "*$Name") } | Select-Object -First 1
    if (-not $line) { Stop-Install "SHA256SUMS has no entry for $Name" }
    $expected = ($line -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 $File).Hash
    if ($actual -ne $expected) { Stop-Install "checksum mismatch for $Name" }
}

# Appends a directory to the user's persistent PATH, and to this session's, unless it's already there.
function Add-ToUserPath([string]$Dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = if ($current) { $current -split ';' } else { @() }
    if ($entries -contains $Dir) { return }
    [Environment]::SetEnvironmentVariable('Path', (($entries + $Dir) -join ';').TrimStart(';'), 'User')
    $env:Path = "$env:Path;$Dir"
    Write-Host "Added $Dir to your user PATH. Open a new terminal to pick it up."
}

$asset = Get-AssetName
$base = Get-BaseUrl
$installDir = $env:BOUNCER_INSTALL_DIR
if (-not $installDir) { $installDir = Join-Path $env:LOCALAPPDATA 'Programs\bouncer' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("bouncer-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Host "Downloading $asset from $base"
    Save-Url "$base/$asset" (Join-Path $tmp $asset)
    Save-Url "$base/SHA256SUMS" (Join-Path $tmp 'SHA256SUMS')
    Test-Checksum (Join-Path $tmp $asset) (Join-Path $tmp 'SHA256SUMS') $asset
    Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath (Join-Path $tmp 'out')
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item -Path (Join-Path $tmp 'out\*') -Destination $installDir -Recurse -Force
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$exe = Join-Path $installDir 'bouncer.exe'
$version = try { & $exe --version 2>$null } catch { $null }
if ($LASTEXITCODE -eq 0 -and $version) {
    Write-Host "Installed $version to $exe"
} else {
    Write-Warning "Installed $exe, but it didn't run. It needs the Microsoft Visual C++ Redistributable (x64)."
}
if ($env:BOUNCER_NO_MODIFY_PATH -ne '1') { Add-ToUserPath $installDir }
