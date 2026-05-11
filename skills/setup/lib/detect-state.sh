#!/usr/bin/env bash
# detect-state.sh <project-path>
# Prints "greenfield" or "brownfield".
# Brownfield: contains source code outside .claude/.
# Greenfield: empty or only .claude/, .git/, README, LICENSE.

set -euo pipefail

target="${1:-}"
[ -n "$target" ] || { echo "usage: detect-state.sh <path>" >&2; exit 2; }
[ -d "$target" ] || { echo "not a directory: $target" >&2; exit 2; }

# Look for source files outside .claude/ and .git/.
found=$(find "$target" \
  -path "$target/.claude" -prune -o \
  -path "$target/.git" -prune -o \
  -type f \( \
    -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o \
    -name "*.vue" -o -name "*.svelte" -o \
    -name "*.go" -o -name "*.py" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" -o \
    -name "Dockerfile" -o -name "Dockerfile.*" -o -name "package.json" \
  \) -print -quit 2>/dev/null)

if [ -n "$found" ]; then
  echo "brownfield"
else
  echo "greenfield"
fi
