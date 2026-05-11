#!/usr/bin/env bash
# adapt-claude-md.sh <template-path> <output-path> <project-name>
# Copies template to output, substituting <PROJECT_NAME>. Skips if output exists.

set -euo pipefail

template="${1:?template required}"
out="${2:?output required}"
name="${3:?project-name required}"

[ -f "$template" ] || { echo "template not found: $template" >&2; exit 2; }

if [ -f "$out" ]; then
  echo "WARN: $out exists; not overwriting" >&2
  exit 0
fi

# Use awk for substitution (safer than sed with arbitrary names).
awk -v name="$name" '{ gsub("<PROJECT_NAME>", name); print }' "$template" > "$out"
