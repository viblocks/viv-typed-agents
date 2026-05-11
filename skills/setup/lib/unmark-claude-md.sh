#!/usr/bin/env bash
# unmark-claude-md.sh <claude-md-path> [--remove-if-empty]
# Remove the managed block between <!-- viv-typed-agents:BEGIN --> and
# <!-- viv-typed-agents:END --> (markers inclusive). Preserves all content
# outside the markers. Strips trailing blank lines left by removal.
# Idempotent. With --remove-if-empty, delete the file if it's only
# whitespace after removal.

set -euo pipefail
out="${1:?claude.md path required}"
remove_if_empty=0
[ "${2:-}" = "--remove-if-empty" ] && remove_if_empty=1

[ -f "$out" ] || { echo "not found: $out" >&2; exit 0; }

BEGIN='<!-- viv-typed-agents:BEGIN -->'
END='<!-- viv-typed-agents:END -->'

if ! grep -qF "$BEGIN" "$out"; then
  echo "no managed block in $out — nothing to remove" >&2
  exit 0
fi

tmp=$(mktemp)
awk -v begin="$BEGIN" -v end="$END" '
  BEGIN { in_block = 0 }
  $0 == begin { in_block = 1; next }
  $0 == end   { in_block = 0; next }
  !in_block   { print }
' "$out" > "$tmp"

awk 'NR==FNR { lines[NR]=$0; n=NR; next }
     END {
       last = n
       while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
       for (i = 1; i <= last; i++) print lines[i]
     }' "$tmp" "$tmp" > "$tmp.cleaned"
mv "$tmp.cleaned" "$out"
rm -f "$tmp"

if [ "$remove_if_empty" = "1" ] && [ -z "$(tr -d '[:space:]' < "$out")" ]; then
  rm -f "$out"
fi
