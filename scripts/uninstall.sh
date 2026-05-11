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

# (Subsequent tasks fill in resolution + execution.)
echo "(plan-building not yet implemented — TODO Task 14+)"
exit 0
