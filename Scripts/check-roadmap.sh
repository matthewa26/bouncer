#!/usr/bin/env sh
# Checks that every row in ROADMAP.md's tables says when its feature ships: a shipped (✅) row needs a
# release version such as 1.2.0 in its last column, and an unshipped (⬜) row needs `planned <version>`
# or `backlog`. Used by CI; safe to run locally.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

awk '
  /^\| (✅|⬜) \|/ {
    n = split($0, cells, "|")
    since = cells[n - 1]
    gsub(/^ +| +$/, "", since)
    shipped = ($0 ~ /^\| ✅ \|/)
    if (shipped && since !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {
      printf "ROADMAP.md:%d: shipped row needs a release version, found \"%s\"\n", NR, since; bad = 1
    }
    if (!shipped && since !~ /^(planned [0-9]+\.[0-9]+(\.[0-9]+)?|backlog)$/) {
      printf "ROADMAP.md:%d: unshipped row needs \"planned <version>\" or \"backlog\", found \"%s\"\n", NR, since; bad = 1
    }
  }
  END { exit bad }
' "$root/ROADMAP.md"
