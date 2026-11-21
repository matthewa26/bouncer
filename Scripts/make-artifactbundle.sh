#!/usr/bin/env sh
# Assembles bouncer.artifactbundle.zip, the SwiftPM binary artifact the bouncer-plugin package's
# binaryTarget downloads, from already-built release binaries, then prints its checksum.
#
# Usage: Scripts/make-artifactbundle.sh <version> <macos-universal> <linux-x86_64> <linux-arm64> <out.zip>
#
# Each binary argument is a path to an executable `bouncer`. Pass "-" to leave a variant out, which is
# only meant for local testing: a published bundle must carry all three so every platform resolves.
# The zip is deterministic (sorted entries, fixed timestamps and modes, no extra attributes), so the
# same binaries always give the same checksum.
set -eu

[ "$#" -eq 5 ] || { echo "usage: $0 <version> <macos-universal> <linux-x86_64> <linux-arm64> <out.zip>" >&2; exit 2; }
version=$1
macos=$2
linux_x86_64=$3
linux_arm64=$4
out=$5

case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bundle="$work/bouncer.artifactbundle"
mkdir -p "$bundle"
variants=""

# Copies one binary into the bundle and appends its info.json variant entry.
# Arguments: the binary (or "-" to skip), the variant directory name, then its triples as a JSON list.
add_variant() {
  [ "$1" = "-" ] && return 0
  [ -x "$1" ] || { echo "not an executable: $1" >&2; exit 1; }
  mkdir -p "$bundle/$2/bin"
  cp "$1" "$bundle/$2/bin/bouncer"
  entry="{\"path\": \"$2/bin/bouncer\", \"supportedTriples\": $3}"
  if [ -n "$variants" ]; then variants="$variants,
        $entry"; else variants="$entry"; fi
}

add_variant "$macos" "bouncer-macos" '["x86_64-apple-macosx", "arm64-apple-macosx"]'
add_variant "$linux_x86_64" "bouncer-linux-x86_64" '["x86_64-unknown-linux-gnu"]'
add_variant "$linux_arm64" "bouncer-linux-arm64" '["aarch64-unknown-linux-gnu"]'
[ -n "$variants" ] || { echo "no binaries given" >&2; exit 1; }

cat > "$bundle/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "bouncer": {
      "version": "$version",
      "type": "executable",
      "variants": [
        $variants
      ]
    }
  }
}
EOF

# Fixed modes and timestamps, then entries added in sorted order, keep the zip byte-for-byte stable.
find "$bundle" -type d -exec chmod 755 {} +
find "$bundle" -type f -exec chmod 644 {} +
find "$bundle" -type f -path '*/bin/bouncer' -exec chmod 755 {} +
find "$bundle" -exec env TZ=UTC touch -h -t 198001010000 {} +
rm -f "$out"
(cd "$work" && find bouncer.artifactbundle | LC_ALL=C sort | TZ=UTC zip -q -X -@ "$out")

if command -v swift >/dev/null 2>&1 && checksum=$(swift package compute-checksum "$out" 2>/dev/null); then :
elif command -v sha256sum >/dev/null 2>&1; then checksum=$(sha256sum "$out" | cut -d ' ' -f 1)
else checksum=$(shasum -a 256 "$out" | cut -d ' ' -f 1)
fi
echo "$out"
echo "checksum: $checksum"
