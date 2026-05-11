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

command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 2; }

# YAML reader: prefer yq; fallback to python3+yaml.
YAML_READER=""
if command -v yq >/dev/null 2>&1; then
  YAML_READER="yq"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  YAML_READER="python"
else
  echo "FATAL: need either yq OR python3 with PyYAML" >&2; exit 2;
fi

yq_get() {
  if [ "$YAML_READER" = "yq" ]; then
    yq "$1" "$MANIFEST"
  else
    python3 -c 'import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$MANIFEST" | jq -r "$1"
  fi
}

yq_set() {
  # in-place YAML set via python (yq can do -i but python is the universal path).
  local expr="$1" value="$2"
  if [ "$YAML_READER" = "yq" ]; then
    yq -i "$expr = \"$value\"" "$MANIFEST"
  else
    python3 -c '
import sys, yaml
path = sys.argv[1]
key_path = sys.argv[2]   # e.g. ".components.\"viv-skills\".commit"  (yq syntax)
value = sys.argv[3]
data = yaml.safe_load(open(path))
# Naive parser for the shapes we use: .components."<name>".<field> or .released_at
parts = key_path.lstrip(".").split(".")
obj = data
for i, p in enumerate(parts[:-1]):
    p = p.strip().strip("\"")
    obj = obj[p]
last = parts[-1].strip().strip("\"")
obj[last] = value
with open(path, "w") as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
' "$MANIFEST" "$expr" "$value"
  fi
}

REPO_URL=$(yq_get ".components.\"$COMP\".repo" 2>/dev/null || true)
[ -z "$REPO_URL" ] || [ "$REPO_URL" = "null" ] && {
  echo "FATAL: component $COMP not in MANIFEST" >&2; exit 2;
}

if [ "$REPO_URL" = "<self>" ]; then
  echo "FATAL: cannot upgrade self-hosted components (repo: <self>)." >&2
  echo "  $COMP lives in this repo — manage it via git directly." >&2
  exit 2
fi

OLD_SHA=$(yq_get ".components.\"$COMP\".commit")

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
yq_set ".components.\"$COMP\".commit" "$NEW_SHA_SHORT"

# Update released_at.
TODAY=$(date -u +%Y-%m-%d)
yq_set ".released_at" "$TODAY"

echo "Bumped $COMP: $OLD_SHA → $NEW_SHA_SHORT"
echo "MANIFEST updated. Don't forget to:"
echo "  git add MANIFEST.yaml && git commit -m \"deps($COMP): bump to $NEW_SHA_SHORT\""
