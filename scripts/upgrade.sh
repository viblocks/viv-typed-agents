#!/usr/bin/env bash
# scripts/upgrade.sh — Bump component SHAs in MANIFEST.yaml.
#
# Usage:
#   ./upgrade.sh <component-name> [--to <sha-or-branch>]
#   ./upgrade.sh --check [<component-name>] [--exit-code]
#   ./upgrade.sh --all
#
# Modes:
#   single (default): bump one component (current behavior)
#   --check:          read-only drift report (exit 0; --exit-code returns 1 on drift)
#   --all:            bump every non-self-hosted component to main HEAD
#
# Examples:
#   ./upgrade.sh viv-skills
#   ./upgrade.sh viv-hooks --to 99c56f8
#   ./upgrade.sh --check
#   ./upgrade.sh --check --exit-code
#   ./upgrade.sh --all

set -uo pipefail

# ---------- arg parsing ----------
COMP=""
TARGET_REF="main"
MODE="single"
EXIT_CODE_FLAG=0

usage_err() { echo "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --to)        TARGET_REF="$2"; shift 2 ;;
    --check)
      [ "$MODE" = "all" ] && usage_err "--check and --all are mutually exclusive"
      MODE="check"; shift ;;
    --all)
      [ "$MODE" = "check" ] && usage_err "--check and --all are mutually exclusive"
      MODE="all"; shift ;;
    --exit-code) EXIT_CODE_FLAG=1; shift ;;
    -h|--help)
      sed -n '2,/^set -uo/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    -*) usage_err "Unknown flag: $1" ;;
    *)
      if [ -z "$COMP" ]; then COMP="$1"; else
        usage_err "Multiple component names"
      fi
      shift
      ;;
  esac
done

# Flag-combination validation.
[ "$MODE" = "all" ] && [ -n "$COMP" ]               && usage_err "--all is mutually exclusive with a component name"
[ "$MODE" = "all" ] && [ "$TARGET_REF" != "main" ]  && usage_err "--all does not support --to (components release independently)"
[ "$EXIT_CODE_FLAG" -eq 1 ] && [ "$MODE" != "check" ] && usage_err "--exit-code is only valid with --check"
[ "$MODE" = "single" ] && [ -z "$COMP" ]            && usage_err "Missing component name (or use --check / --all)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/MANIFEST.yaml"

command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 2; }

# ---------- YAML reader ----------
YAML_READER=""
if command -v yq >/dev/null 2>&1; then
  YAML_READER="yq"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  command -v jq >/dev/null 2>&1 || {
    echo "FATAL: python+PyYAML path requires jq (install jq or use yq instead)" >&2; exit 2;
  }
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
  local expr="$1" value="$2"
  if [ "$YAML_READER" = "yq" ]; then
    yq -i "$expr = \"$value\"" "$MANIFEST"
  else
    python3 -c '
import sys, yaml
path = sys.argv[1]
key_path = sys.argv[2]
value = sys.argv[3]
data = yaml.safe_load(open(path))
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

list_components() {
  if [ "$YAML_READER" = "yq" ]; then
    yq '.components | keys | .[]' "$MANIFEST" | sed 's/^"//;s/"$//'
  else
    python3 -c 'import yaml,sys
data = yaml.safe_load(open(sys.argv[1]))
for k in data["components"].keys():
    print(k)
' "$MANIFEST"
  fi
}

# Echoes "old_sha new_sha_short" on stdout, or "SKIP <reason>" if cannot resolve.
# Returns 0 always (caller interprets stdout).
resolve_component() {
  local comp="$1" ref="$2"
  local repo old_sha new_sha new_sha_short
  repo=$(yq_get ".components.\"$comp\".repo" 2>/dev/null || true)
  if [ -z "$repo" ] || [ "$repo" = "null" ]; then
    echo "SKIP not-in-manifest"; return 0
  fi
  if [ "$repo" = "<self>" ]; then
    echo "SKIP self-hosted"; return 0
  fi
  old_sha=$(yq_get ".components.\"$comp\".commit")
  new_sha=$(git ls-remote "$repo" "$ref" 2>/dev/null | head -1 | awk '{print $1}')
  if [ -z "$new_sha" ]; then
    if echo "$ref" | grep -qE '^[0-9a-f]{7,40}$'; then
      new_sha="$ref"
    else
      echo "SKIP unresolvable-ref:$ref"; return 0
    fi
  fi
  new_sha_short=$(echo "$new_sha" | cut -c1-7)
  echo "$old_sha $new_sha_short"
}

bump_component() {
  local comp="$1" new_sha="$2"
  yq_set ".components.\"$comp\".commit" "$new_sha"
}

update_released_at() {
  yq_set ".released_at" "$(date -u +%Y-%m-%d)"
}

# ---------- dispatcher ----------
case "$MODE" in
  single)
    result=$(resolve_component "$COMP" "$TARGET_REF")
    case "$result" in
      "SKIP not-in-manifest")
        echo "FATAL: component $COMP not in MANIFEST" >&2; exit 2 ;;
      "SKIP self-hosted")
        echo "FATAL: cannot upgrade self-hosted components (repo: <self>)." >&2
        echo "  $COMP lives in this repo — manage it via git directly." >&2
        exit 2 ;;
      "SKIP unresolvable-ref:"*)
        echo "FATAL: cannot resolve $TARGET_REF" >&2; exit 2 ;;
    esac
    OLD_SHA=$(echo "$result" | awk '{print $1}')
    NEW_SHA=$(echo "$result" | awk '{print $2}')
    if [ "$OLD_SHA" = "$NEW_SHA" ]; then
      echo "$COMP already at $OLD_SHA — no change."
      exit 0
    fi
    bump_component "$COMP" "$NEW_SHA"
    update_released_at
    echo "Bumped $COMP: $OLD_SHA → $NEW_SHA"
    echo "MANIFEST updated. Don't forget to:"
    echo "  git add MANIFEST.yaml && git commit -m \"deps($COMP): bump to $NEW_SHA\""
    ;;
  check)
    if [ -n "$COMP" ]; then
      repo_check=$(yq_get ".components.\"$COMP\".repo" 2>/dev/null || true)
      if [ -z "$repo_check" ] || [ "$repo_check" = "null" ]; then
        echo "FATAL: component $COMP not in MANIFEST" >&2
        exit 2
      fi
    fi
    echo "==> Checking components against upstream main..."
    echo
    printf "  %-28s %-10s %-10s %s\n" "COMPONENT" "PINNED" "UPSTREAM" "STATUS"
    drift=0
    while IFS= read -r comp; do
      [ -z "$comp" ] && continue
      if [ -n "$COMP" ] && [ "$comp" != "$COMP" ]; then continue; fi
      result=$(resolve_component "$comp" "main")
      case "$result" in
        "SKIP self-hosted")
          printf "  %-28s %-10s %-10s %s\n" "$comp" "-" "-" "⊘ self-hosted" ;;
        "SKIP "*)
          printf "  %-28s %-10s %-10s %s\n" "$comp" "?" "?" "⚠ ${result#SKIP }" ;;
        *)
          old=$(echo "$result" | awk '{print $1}')
          new=$(echo "$result" | awk '{print $2}')
          if [ "$old" = "$new" ]; then
            printf "  %-28s %-10s %-10s %s\n" "$comp" "$old" "$new" "✓ current"
          else
            printf "  %-28s %-10s %-10s %s\n" "$comp" "$old" "$new" "⚠ behind"
            drift=$((drift+1))
          fi ;;
      esac
    done < <(list_components)
    echo
    if [ "$drift" -gt 0 ]; then
      echo "$drift component(s) behind. Run './scripts/upgrade.sh --all' to bump."
      [ "$EXIT_CODE_FLAG" -eq 1 ] && exit 1
    else
      echo "All components current."
    fi
    exit 0
    ;;
  all)
    echo "==> Bumping all components to main HEAD..."
    echo
    # Stage changes in tempfile for atomic write.
    MANIFEST_TMP="$MANIFEST.tmp.$$"
    trap 'rm -f "$MANIFEST_TMP"' EXIT
    cp "$MANIFEST" "$MANIFEST_TMP"
    bumped=0; current=0; skipped=0
    commit_lines=""
    # Swap MANIFEST pointer so resolve_component/bump_component act on tmp file.
    MANIFEST_REAL="$MANIFEST"
    MANIFEST="$MANIFEST_TMP"
    while IFS= read -r comp; do
      [ -z "$comp" ] && continue
      result=$(resolve_component "$comp" "main")
      case "$result" in
        "SKIP self-hosted")
          echo "  $comp: self-hosted (skip)"
          skipped=$((skipped+1)) ;;
        "SKIP "*)
          echo "  $comp: ${result#SKIP } (skip)"
          skipped=$((skipped+1)) ;;
        *)
          old=$(echo "$result" | awk '{print $1}')
          new=$(echo "$result" | awk '{print $2}')
          if [ "$old" = "$new" ]; then
            echo "  $comp: already at $old (skip)"
            current=$((current+1))
          else
            bump_component "$comp" "$new"
            echo "  $comp: $old → $new ✓"
            commit_lines="${commit_lines}  - $comp: $old → $new
"
            bumped=$((bumped+1))
          fi ;;
      esac
    done < <(list_components)
    if [ "$bumped" -gt 0 ]; then
      update_released_at
      mv "$MANIFEST_TMP" "$MANIFEST_REAL"
    else
      rm -f "$MANIFEST_TMP"
    fi
    MANIFEST="$MANIFEST_REAL"
    echo
    echo "Bumped $bumped, already-current $current, skipped $skipped."
    if [ "$bumped" -gt 0 ]; then
      echo "MANIFEST updated. Don't forget to:"
      echo "  git add MANIFEST.yaml && git commit -m \"deps: bump $bumped components to latest main"
      echo
      printf '%s' "$commit_lines"
      echo "\""
    fi
    exit 0
    ;;
esac
