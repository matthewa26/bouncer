#!/usr/bin/env sh
# Writes bouncer.1, the CLI's man page, into a directory, generated from the commands' own help text by
# swift-argument-parser's generate-manual plugin. The release workflow ships it in the macOS and Linux
# archives; the installer and the Homebrew formula put it where man finds it.
#
# Usage: generate-manual.sh <output directory>
set -eu
OUT="${1:?usage: generate-manual.sh <output directory>}"
mkdir -p "$OUT"
swift package plugin --allow-writing-to-package-directory generate-manual \
    --authors "Matthew Ayers" --output-directory "$OUT"
[ -s "$OUT/bouncer.1" ] || { echo "generate-manual wrote no bouncer.1" >&2; exit 1; }
