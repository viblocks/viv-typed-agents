#!/usr/bin/env bash
# scripts/install.sh — Deploy the typed-agents product to a consumer project.
#
# Per ADR-RD-010, viv-typed-agents is the installable product composed of
# 6 internal components pinned in MANIFEST.yaml. This script clones each
# component at its pinned SHA and copies its content to the target project's
# .claude/ directory.
#
# Usage:
#   ./install.sh <target-project-path> [options]
#
# Options:
#   --tier N                 Tier (1..5). Default: 5. Determines default component set.
#   --skills <list>          Override: only install named skills (comma-separated).
#                            Skill names are folder basenames under viv-skills/<area>/.
#   --agents <list>          Override: only install named agents.
#   --components <list>      Override: only install named components (comma-separated).
#   --exclude <list>         Skip named components even if tier includes them.
#   --dry-run                Print actions without executing.
#   --keep-vendor            Keep the .vendor/ working dir (for inspection).
#
# Examples:
#   ./install.sh ~/my-project --tier 5
#   ./install.sh ~/my-project --tier 1
#   ./install.sh ~/my-project --skills crypto-backend,nestjs-backend
#   ./install.sh ~/my-project --tier 4 --exclude viv-orchestration-rules
#
# Requirements: bash, git, yq, awk, sed.

set -euo pipefail

# ---------- arg parsing ----------
TARGET=""
TIER=5
SKILLS_FILTER=""
AGENTS_FILTER=""
COMPONENTS_FILTER=""
EXCLUDE_LIST=""
DRY_RUN=0
KEEP_VENDOR=0

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier)             TIER="$2"; shift 2 ;;
    --skills)           SKILLS_FILTER="$2"; shift 2 ;;
    --agents)           AGENTS_FILTER="$2"; shift 2 ;;
    --components)       COMPONENTS_FILTER="$2"; shift 2 ;;
    --exclude)          EXCLUDE_LIST="$2"; shift 2 ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --keep-vendor)      KEEP_VENDOR=1; shift ;;
    -h|--help)          usage 0 ;;
    -*)                 echo "Unknown flag: $1" >&2; usage 2 ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"; else
        echo "Multiple targets: $TARGET, $1" >&2; usage 2
      fi
      shift
      ;;
  esac
done

[ -z "$TARGET" ] && { echo "Missing <target-project-path>" >&2; usage 2; }

# Resolve target absolute path.
TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")" || {
  echo "FATAL: cannot resolve target $TARGET" >&2; exit 2;
}
[ ! -d "$TARGET" ] && { echo "FATAL: target $TARGET does not exist" >&2; exit 2; }

# ---------- locate manifest ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/MANIFEST.yaml"
[ -f "$MANIFEST" ] || { echo "FATAL: MANIFEST.yaml not found at $MANIFEST" >&2; exit 2; }

# ---------- runtime deps ----------
for dep in git awk sed; do
  command -v "$dep" >/dev/null 2>&1 || { echo "FATAL: $dep required" >&2; exit 2; }
done

# YAML reader: prefer yq; fallback to python3+yaml.
YAML_READER=""
if command -v yq >/dev/null 2>&1; then
  YAML_READER="yq"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  YAML_READER="python"
else
  echo "FATAL: need either yq OR python3 with PyYAML to parse MANIFEST.yaml" >&2
  echo "       brew install yq    # or:    pip3 install pyyaml" >&2
  exit 2
fi

# yq_get <yq-expr> — read from MANIFEST. Works whether YAML_READER is yq or python.
# yq expressions and jq expressions overlap for simple cases (.components, |, keys[]).
yq_get() {
  local expr="$1"
  if [ "$YAML_READER" = "yq" ]; then
    yq "$expr" "$MANIFEST"
  else
    # Convert YAML to JSON via python, then run jq.
    python3 -c 'import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$MANIFEST" | jq -r "$expr"
  fi
}

# ---------- helpers ----------
in_csv() {
  # in_csv <needle> <haystack-csv>  → 0 if needle in haystack
  local needle="$1" hay="$2" item
  IFS=, read -ra arr <<< "$hay"
  for item in "${arr[@]}"; do
    [ "$(echo "$item" | xargs)" = "$needle" ] && return 0
  done
  return 1
}

manifest_components() {
  yq_get '.components | keys[]'
}

component_field() {
  local comp="$1" field="$2"
  yq_get ".components.\"$comp\".$field"
}

component_tiers() {
  local comp="$1"
  yq_get ".components.\"$comp\".tiers[]"
}

# ---------- selection logic ----------
selected_components() {
  local comp tiers t included
  for comp in $(manifest_components); do
    # Component-level filters first.
    [ -n "$COMPONENTS_FILTER" ] && ! in_csv "$comp" "$COMPONENTS_FILTER" && continue
    [ -n "$EXCLUDE_LIST" ] && in_csv "$comp" "$EXCLUDE_LIST" && continue

    # Tier filter.
    included=0
    for t in $(component_tiers "$comp"); do
      if [ "$t" -le "$TIER" ]; then included=1; break; fi
    done
    [ "$included" -eq 1 ] && echo "$comp"
  done
}

# ---------- main ----------
echo "============================================"
echo "viv-typed-agents installer"
echo "  target: $TARGET"
echo "  tier:   $TIER"
[ -n "$COMPONENTS_FILTER" ] && echo "  components filter: $COMPONENTS_FILTER"
[ -n "$EXCLUDE_LIST" ]      && echo "  exclude:           $EXCLUDE_LIST"
[ -n "$SKILLS_FILTER" ]     && echo "  skills filter:     $SKILLS_FILTER"
[ -n "$AGENTS_FILTER" ]     && echo "  agents filter:     $AGENTS_FILTER"
[ "$DRY_RUN" -eq 1 ]        && echo "  DRY RUN — no changes will be made"
echo "============================================"

VENDOR_DIR="$REPO_ROOT/.vendor"
mkdir -p "$VENDOR_DIR"

cleanup_vendor() {
  if [ "$KEEP_VENDOR" -eq 0 ] && [ -d "$VENDOR_DIR" ]; then
    rm -rf "$VENDOR_DIR"
  fi
}
trap cleanup_vendor EXIT

# ---------- per-component install ----------
for comp in $(selected_components); do
  REPO_URL=$(component_field "$comp" repo)
  COMMIT=$(component_field "$comp" commit)
  TARGET_PATH=$(component_field "$comp" target_path)
  ROLE=$(component_field "$comp" role)

  echo ""
  echo ">>> $comp ($COMMIT) — $ROLE"
  echo "    deploy → $TARGET/$TARGET_PATH"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    (dry-run; skipping)"
    continue
  fi

  # Clone or fetch.
  CLONE_DIR="$VENDOR_DIR/$comp"
  if [ ! -d "$CLONE_DIR/.git" ]; then
    git clone --quiet --depth 50 "$REPO_URL" "$CLONE_DIR"
  fi
  git -C "$CLONE_DIR" fetch --quiet --depth 50 origin "$COMMIT" 2>/dev/null || \
    git -C "$CLONE_DIR" fetch --quiet origin
  git -C "$CLONE_DIR" checkout --quiet "$COMMIT"

  # Prepare destination.
  DEST="$TARGET/$TARGET_PATH"
  mkdir -p "$DEST"

  # Per-component deploy logic.
  case "$comp" in
    viv-skills)
      if [ -n "$SKILLS_FILTER" ]; then
        # Granular skill selection.
        IFS=, read -ra skills <<< "$SKILLS_FILTER"
        for skill in "${skills[@]}"; do
          skill="$(echo "$skill" | xargs)"
          # Search the skill folder under any area subdir.
          found=$(find "$CLONE_DIR" -maxdepth 3 -type d -name "$skill" | head -1)
          if [ -n "$found" ]; then
            cp -r "$found" "$DEST/"
            echo "    + skill: $skill"
          else
            echo "    ! skill not found: $skill" >&2
          fi
        done
      else
        # Full skills tree (excluding repo metadata).
        find "$CLONE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.git' ! -name 'architecture' \
          -exec cp -r {} "$DEST/" \;
      fi
      ;;
    viv-agents)
      if [ -n "$AGENTS_FILTER" ]; then
        IFS=, read -ra agents <<< "$AGENTS_FILTER"
        for agent in "${agents[@]}"; do
          agent="$(echo "$agent" | xargs)"
          src="$CLONE_DIR/$agent.md"
          if [ -f "$src" ]; then
            cp "$src" "$DEST/"
            echo "    + agent: $agent"
          else
            # Try area-prefixed
            found=$(find "$CLONE_DIR" -name "${agent}.md" -type f | head -1)
            if [ -n "$found" ]; then
              cp "$found" "$DEST/"
              echo "    + agent: $agent"
            else
              echo "    ! agent not found: $agent" >&2
            fi
          fi
        done
      else
        find "$CLONE_DIR" -name '*.md' -type f -not -path "*/.git/*" -not -path "*/architecture/*" \
          -exec cp {} "$DEST/" \;
      fi
      ;;
    viv-routing|viv-workflows|viv-orchestration-rules)
      # Copy the data + schema content; skip repo metadata (architecture/, migration/, etc.)
      for sub in $(ls "$CLONE_DIR" 2>/dev/null); do
        case "$sub" in
          .git|architecture|migration|examples|README.md|NAMING.md) continue ;;
          *) cp -r "$CLONE_DIR/$sub" "$DEST/" ;;
        esac
      done
      ;;
    viv-hooks)
      # Copy hooks/ + lib/ + settings.json.fragment
      for sub in hooks lib settings.json.fragment; do
        if [ -e "$CLONE_DIR/$sub" ]; then
          cp -r "$CLONE_DIR/$sub" "$DEST/"
        fi
      done
      ;;
  esac
done

echo ""
echo "============================================"
echo "Install complete."
echo "Next steps:"
echo "  1. Configure routing: edit $TARGET/.claude/routing/routing-table.json"
echo "  2. Configure workflows: review $TARGET/.claude/workflows/"
echo "  3. (Tier 4+) Glue settings: merge $TARGET/.claude/hooks/settings.json.fragment into $TARGET/.claude/settings.json"
echo "  4. (Tier 5)  Adapt CLAUDE.md from $TARGET/.claude/orchestration/CLAUDE.template.md"
echo "============================================"
