#!/usr/bin/env bash
# adapt-claude-md.sh <template-path> <output-path> <project-name>
#
# Renders <template-path> (substituting <PROJECT_NAME>) into <output-path>,
# wrapping the rendered content in managed markers. Three modes:
#
#   1. Fresh file       — output does not exist: write rendered template
#                         wrapped in markers.
#   2. Existing, no markers — append managed block to end, preserving
#                             existing content above byte-for-byte.
#   3. Existing with markers — replace content between markers with the
#                              freshly rendered template (idempotent).
#
# Markers (must match EXACTLY):
#   <!-- viv-typed-agents:BEGIN -->
#   <!-- viv-typed-agents:END -->

set -euo pipefail

template="${1:?template required}"
out="${2:?output required}"
name="${3:?project-name required}"

[ -f "$template" ] || { echo "template not found: $template" >&2; exit 2; }

BEGIN='<!-- viv-typed-agents:BEGIN -->'
END='<!-- viv-typed-agents:END -->'
ATTRIB='<!-- Managed by viv-typed-agents. Re-run /typedAgentSetup to refresh. -->'

# Render template into a temp file (substitute <PROJECT_NAME>).
rendered=$(mktemp)
trap 'rm -f "$rendered" "$block" "$newfile"' EXIT
awk -v name="$name" '{ gsub("<PROJECT_NAME>", name); print }' "$template" > "$rendered"

# Build managed block in a temp file.
block=$(mktemp)
{
  printf '%s\n' "$BEGIN"
  printf '%s\n' "$ATTRIB"
  printf '\n'
  cat "$rendered"
  # Ensure rendered content ends with newline before END marker.
  [ -s "$rendered" ] && [ "$(tail -c1 "$rendered" | wc -l)" -eq 0 ] && printf '\n'
  printf '\n'
  printf '%s\n' "$END"
} > "$block"

newfile=$(mktemp)

if [ ! -f "$out" ]; then
  # Mode 1: fresh file.
  cp "$block" "$newfile"
  mv "$newfile" "$out"
  exit 0
fi

has_begin=0
has_end=0
grep -qF "$BEGIN" "$out" && has_begin=1
grep -qF "$END" "$out" && has_end=1

if [ "$has_begin" = "1" ] && [ "$has_end" = "1" ]; then
  # Mode 3: replace content between markers. Preserve everything outside.
  awk -v begin="$BEGIN" -v end="$END" -v blockfile="$block" '
    BEGIN { in_block = 0; replaced = 0 }
    {
      if (!in_block && index($0, begin) > 0 && !replaced) {
        # Emit block contents verbatim in place of the BEGIN..END region.
        while ((getline bline < blockfile) > 0) print bline
        close(blockfile)
        in_block = 1
        replaced = 1
        next
      }
      if (in_block) {
        if (index($0, end) > 0) { in_block = 0 }
        next
      }
      print
    }
  ' "$out" > "$newfile"
  mv "$newfile" "$out"
  exit 0
fi

if [ "$has_begin" = "1" ] || [ "$has_end" = "1" ]; then
  echo "WARN: $out has corrupt managed markers (only one of BEGIN/END present); appending new managed block" >&2
fi

# Mode 2 (and corrupt-marker fallback): append managed block at end.
# Preserve existing content byte-for-byte; ensure separation by one newline
# if the existing file does not already end with a newline.
cp "$out" "$newfile"
if [ -s "$newfile" ] && [ "$(tail -c1 "$newfile" | wc -l)" -eq 0 ]; then
  printf '\n' >> "$newfile"
fi
printf '\n' >> "$newfile"
cat "$block" >> "$newfile"
mv "$newfile" "$out"
