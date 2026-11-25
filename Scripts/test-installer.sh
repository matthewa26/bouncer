#!/usr/bin/env sh
# Runs install.ps1's sh half against fake release assets served from file:// URLs, checking that it
# installs a verified download and refuses a corrupted one. Used by CI; safe to run locally.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/assets"
printf '#!/bin/sh\necho bouncer 0.0.0-test\n' > "$work/assets/bouncer"
chmod +x "$work/assets/bouncer"
printf '.TH BOUNCER 1\n' > "$work/assets/bouncer.1"
for asset in bouncer-macos-universal.tar.gz bouncer-linux-x86_64.tar.gz bouncer-linux-arm64.tar.gz; do
  tar -czf "$work/assets/$asset" -C "$work/assets" bouncer bouncer.1
done
(cd "$work/assets" && for f in bouncer-*.tar.gz; do
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f"; else shasum -a 256 "$f"; fi
done > SHA256SUMS)

BOUNCER_DOWNLOAD_URL="file://$work/assets" BOUNCER_INSTALL_DIR="$work/bin" sh "$root/install.ps1"
[ "$("$work/bin/bouncer" --version)" = "bouncer 0.0.0-test" ] || { echo "installed binary doesn't run"; exit 1; }
[ -f "$work/share/man/man1/bouncer.1" ] || { echo "installer didn't install the man page"; exit 1; }

for asset in "$work"/assets/bouncer-*.tar.gz; do echo corrupted >> "$asset"; done
if BOUNCER_DOWNLOAD_URL="file://$work/assets" BOUNCER_INSTALL_DIR="$work/bin2" sh "$root/install.ps1" 2>/dev/null; then
  echo "installer accepted a corrupted download"
  exit 1
fi
echo "installer test passed"
