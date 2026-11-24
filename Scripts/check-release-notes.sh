#!/usr/bin/env sh
# Checks that ReleaseNotes/<version>.md exists and isn't empty, so a release can't publish without notes. The
# release workflow runs it before building and publishes that file as the release's description; run it locally
# before tagging.
set -eu

VERSION="${1:?usage: check-release-notes.sh <version, e.g. 1.3.1>}"
NOTES="$(cd "$(dirname "$0")/.." && pwd)/ReleaseNotes/${VERSION}.md"

if ! grep -q '[^[:space:]]' "$NOTES" 2>/dev/null; then
  echo "Missing release notes: write ReleaseNotes/${VERSION}.md before tagging v${VERSION}." >&2
  exit 1
fi
echo "Found ${NOTES}"
