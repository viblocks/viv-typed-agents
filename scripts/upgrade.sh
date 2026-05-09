#!/usr/bin/env bash
# scripts/upgrade.sh — Bump a component's pinned SHA in MANIFEST.yaml.
#
# Usage:
#   ./upgrade.sh <component-name> [--to <sha-or-branch>]
#
# Default: bumps to latest of the component's default branch (main).
#
# Examples:
#   ./upgrade.sh viv-skills
#   ./upgrade.sh viv-hooks --to 99c56f8
#   ./upgrade.sh viv-routing --to feat/new-domain

set -euo pipefail

COMP=""
TARGET_REF="main"

while [ $# -gt 0 ]; do
  case "$1" in
    --to) TARGET_REF="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)
      if [ -z "$COMP" ]; then COMP="$1"; else
        echo "Multiple component names" >&2; exit 2
      fi
      shift
      ;;
  esac
done

[ -z "$COMP" ] && { echo "Missing component name" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/MANIFEST.yaml"

for dep in git yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "FATAL: $dep required" >&2; exit 2; }
done

REPO_URL=$(yq ".components.\"$COMP\".repo" "$MANIFEST" 2>/dev/null || true)
[ -z "$REPO_URL" ] || [ "$REPO_URL" = "null" ] && {
  echo "FATAL: component $COMP not in MANIFEST" >&2; exit 2;
}

OLD_SHA=$(yq ".components.\"$COMP\".commit" "$MANIFEST")

# Resolve TARGET_REF to a commit SHA via remote.
NEW_SHA=$(git ls-remote "$REPO_URL" "$TARGET_REF" 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$NEW_SHA" ]; then
  # TARGET_REF might already be a SHA — use it directly.
  if echo "$TARGET_REF" | grep -qE '^[0-9a-f]{7,40}$'; then
    NEW_SHA="$TARGET_REF"
  else
    echo "FATAL: cannot resolve $TARGET_REF in $REPO_URL" >&2; exit 2;
  fi
fi

# Trim to short SHA (7 chars) for readability.
NEW_SHA_SHORT=$(echo "$NEW_SHA" | cut -c1-7)

if [ "$OLD_SHA" = "$NEW_SHA_SHORT" ]; then
  echo "$COMP already at $OLD_SHA — no change."
  exit 0
fi

# Update MANIFEST in place.
yq -i ".components.\"$COMP\".commit = \"$NEW_SHA_SHORT\"" "$MANIFEST"

# Update released_at.
TODAY=$(date -u +%Y-%m-%d)
yq -i ".released_at = \"$TODAY\"" "$MANIFEST"

echo "Bumped $COMP: $OLD_SHA → $NEW_SHA_SHORT"
echo "MANIFEST updated. Don't forget to:"
echo "  git add MANIFEST.yaml && git commit -m \"deps($COMP): bump to $NEW_SHA_SHORT\""
