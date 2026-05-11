#!/usr/bin/env bash
# discover-services.sh <project-path>
# Prints candidate service folders (one per line, relative to project-path).
# Looks under services/, apps/, packages/. Falls back to top-level folders
# with source code if no monorepo root exists.

set -euo pipefail

target="${1:-}"
[ -d "$target" ] || { echo "not a directory: $target" >&2; exit 2; }

SOURCE_GLOB='-name *.ts -o -name *.tsx -o -name *.js -o -name *.jsx -o -name *.vue -o -name *.svelte -o -name *.go -o -name *.py -o -name *.rs -o -name *.java -o -name *.rb'

has_source() {
  # $1: folder path. Returns 0 if folder contains any source file.
  find "$1" -type f \( $SOURCE_GLOB \) -print -quit 2>/dev/null | grep -q .
}

found_root=0
for root in services apps packages; do
  if [ -d "$target/$root" ]; then
    found_root=1
    for sub in "$target/$root"/*/; do
      [ -d "$sub" ] || continue
      if has_source "$sub"; then
        # Strip trailing slash and project-path prefix.
        rel="${sub%/}"
        rel="${rel#"$target/"}"
        echo "$rel"
      fi
    done
  fi
done

if [ "$found_root" = "0" ]; then
  # No monorepo root: scan top-level folders.
  for sub in "$target"/*/; do
    [ -d "$sub" ] || continue
    name=$(basename "$sub")
    case "$name" in .claude|.git|node_modules) continue;; esac
    if has_source "$sub"; then
      echo "$name"
    fi
  done
fi
