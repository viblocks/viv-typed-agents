#!/usr/bin/env bash
# scripts/uninstall.sh — Remove a viv-typed-agents installation from a project.
#
# Reads <target>/.claude/.install-manifest.json (written by install.sh) to
# know exactly what to remove. Preserves any content not in the manifest
# (user customizations). Reverses wizard outputs (settings.json,
# CLAUDE.md managed block) ONLY on full uninstall.
#
# Usage:
#   ./uninstall.sh <target-project-path> [options]
#
# Options:
#   --components <list>    CSV of components to remove. Default: all.
#   --dry-run              Print the plan without removing anything.
#   --keep-config          On full uninstall, skip settings.json reverse-merge
#                          and CLAUDE.md unmark.
#   -h | --help            Show this usage.

set -euo pipefail

TARGET=""
COMPONENTS_FILTER=""
DRY_RUN=0
KEEP_CONFIG=0

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --components)  COMPONENTS_FILTER="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --keep-config) KEEP_CONFIG=1; shift ;;
    -h|--help)     usage 0 ;;
    -*)            echo "Unknown flag: $1" >&2; usage 2 ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"; else
        echo "Multiple targets: $TARGET, $1" >&2; usage 2
      fi
      shift
      ;;
  esac
done

[ -z "$TARGET" ] && { echo "Missing <target-project-path>" >&2; usage 2; }
[ -d "$TARGET" ] || { echo "FATAL: target $TARGET is not a directory" >&2; exit 2; }

TARGET="$(cd "$TARGET" && pwd)"
CLAUDE_DIR="$TARGET/.claude"
MANIFEST_PATH="$CLAUDE_DIR/.install-manifest.json"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "No .claude/ directory at $TARGET — nothing to uninstall."
  exit 0
fi

if [ ! -f "$MANIFEST_PATH" ]; then
  cat <<EOF >&2
No install manifest found at $MANIFEST_PATH.

This means viv-typed-agents was installed before manifest support
existed, or the file was deleted. To clean up manually:

  - If you're in git:        git rm -rf .claude/ && git restore CLAUDE.md
  - If not in git:           rm -rf .claude/ then manually revert CLAUDE.md
                             (remove block between viv-typed-agents:BEGIN/END markers)

Aborting.
EOF
  exit 2
fi

if ! jq empty "$MANIFEST_PATH" 2>/dev/null; then
  echo "FATAL: $MANIFEST_PATH is not valid JSON" >&2
  exit 1
fi

echo "============================================"
echo "viv-typed-agents uninstaller"
echo "  target:   $TARGET"
echo "  manifest: $MANIFEST_PATH"
[ "$DRY_RUN" -eq 1 ] && echo "  mode:     DRY RUN (no changes will be made)"
echo "============================================"
echo ""

# Resolve which components to remove.
ALL_COMPONENTS=$(jq -r '.components | keys[]' "$MANIFEST_PATH")
SELECTED_COMPONENTS=""

if [ -n "$COMPONENTS_FILTER" ]; then
  IFS=, read -ra requested <<< "$COMPONENTS_FILTER"
  for req in "${requested[@]}"; do
    req="$(echo "$req" | xargs)"
    if echo "$ALL_COMPONENTS" | grep -qx "$req"; then
      SELECTED_COMPONENTS+="$req"$'\n'
    else
      echo "  ! component '$req' not in install manifest — skipping" >&2
    fi
  done
else
  SELECTED_COMPONENTS="$ALL_COMPONENTS"
fi

SELECTED_COMPONENTS=$(echo "$SELECTED_COMPONENTS" | grep -v '^$' || true)

if [ -z "$SELECTED_COMPONENTS" ]; then
  echo "No components selected for removal."
  exit 0
fi

# Determine full vs. partial uninstall.
# "Full" = no --components given, OR --components covers every entry in
# the manifest (set equality). The wizard outputs (settings.json
# reverse-merge, CLAUDE.md unmark) only run on full uninstall.
SELECTED_SORTED=$(echo "$SELECTED_COMPONENTS" | sort)
ALL_SORTED=$(echo "$ALL_COMPONENTS" | sort)
if [ "$SELECTED_SORTED" = "$ALL_SORTED" ]; then
  UNINSTALL_MODE="full"
else
  UNINSTALL_MODE="partial"
fi

# Snapshot the settings.json.fragment (used by reverse-merge AFTER directory
# removal would have wiped it). Only relevant for full uninstall.
FRAGMENT_SRC="$CLAUDE_DIR/hooks/settings.json.fragment"
FRAGMENT_SNAPSHOT=""
if [ "$UNINSTALL_MODE" = "full" ] && [ "$KEEP_CONFIG" -eq 0 ] && [ -f "$FRAGMENT_SRC" ]; then
  FRAGMENT_SNAPSHOT=$(mktemp)
  cp "$FRAGMENT_SRC" "$FRAGMENT_SNAPSHOT"
fi

# Build and print the plan.
echo "Uninstall plan ($UNINSTALL_MODE):"
echo ""
echo "  Components and paths to remove:"
while IFS= read -r comp; do
  [ -n "$comp" ] || continue
  jq -r --arg c "$comp" '.components[$c].paths[] | "    ✗ \(.)"' "$MANIFEST_PATH"
done <<< "$SELECTED_COMPONENTS"

if [ "$UNINSTALL_MODE" = "full" ] && [ "$KEEP_CONFIG" -eq 0 ]; then
  echo ""
  echo "  Wizard outputs to reverse:"
  if [ -n "$FRAGMENT_SNAPSHOT" ] && [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo "    ⟲ .claude/settings.json (reverse-merge)"
  fi
  if [ -f "$TARGET/CLAUDE.md" ] && grep -qF "<!-- viv-typed-agents:BEGIN -->" "$TARGET/CLAUDE.md" 2>/dev/null; then
    echo "    ⟲ CLAUDE.md (remove managed block)"
  fi
fi

echo ""
echo "  Transient state to remove (if present):"
echo "    ✗ .claude/.subagent-active.json"
echo "    ✗ .claude/.subagent-active.json.lock"

echo ""
if [ "$UNINSTALL_MODE" = "full" ]; then
  echo "  Manifest:"
  echo "    ✗ .claude/.install-manifest.json (full uninstall)"
else
  echo "  Manifest:"
  echo "    ⟲ .claude/.install-manifest.json (rewrite — remove only selected components)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "Dry-run complete. No changes made."
  [ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
  exit 0
fi

# (Subsequent tasks fill in execution.)
echo ""
echo "(execution not yet implemented — TODO Task 16+)"
[ -n "$FRAGMENT_SNAPSHOT" ] && rm -f "$FRAGMENT_SNAPSHOT"
exit 0
