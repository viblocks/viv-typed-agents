# `upgrade.sh --all` and `--check` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--all` (bump every drifted component to upstream `main`) and `--check` (read-only drift report) flags to `scripts/upgrade.sh`, with optional `--exit-code` for CI usage.

**Architecture:** Refactor the existing single-component upgrade logic into a reusable `resolve_component()` function. Add a top-level mode dispatcher that picks between three paths: existing single-component path, new `--check` reporter, and new `--all` bumper. Bumper uses temp-file + atomic rename to avoid mid-write corruption. First test in `scripts/tests/` establishes a `git ls-remote` shim pattern (PATH-prepended fake binary) so tests don't hit the network.

**Tech Stack:** bash, yq or python3+PyYAML, git. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-05-11-upgrade-all-and-check-design.md](../specs/2026-05-11-upgrade-all-and-check-design.md)

---

## File Structure

**Create:**
- `scripts/tests/upgrade.test.sh` — bash test runner for upgrade.sh
- `scripts/tests/fixtures/MANIFEST.test.yaml` — fixture manifest with deterministic SHAs
- `scripts/tests/fixtures/git-ls-remote-shim.sh` — fake git that returns fixture SHAs
- `scripts/tests/README.md` — one-paragraph note on running tests

**Modify:**
- `scripts/upgrade.sh` — refactor into functions, add `--check`, `--all`, `--exit-code`
- `README.md` — add "Keeping components current" subsection

---

## Task 1: Test infrastructure scaffolding

**Files:**
- Create: `scripts/tests/fixtures/MANIFEST.test.yaml`
- Create: `scripts/tests/fixtures/git-ls-remote-shim.sh`
- Create: `scripts/tests/upgrade.test.sh`
- Create: `scripts/tests/README.md`

- [ ] **Step 1: Create the fixture MANIFEST**

Create `scripts/tests/fixtures/MANIFEST.test.yaml` with this exact content:

```yaml
schema_version: "1.0"
strategy_version: "0.1.0"
released_at: "2026-01-01"

components:

  comp-current:
    repo: https://fake.test/comp-current
    commit: aaaaaaa
    role: fixture component already at upstream main
    target_path: .claude/comp-current/
    tiers: [5]

  comp-behind:
    repo: https://fake.test/comp-behind
    commit: bbbbbbb
    role: fixture component behind upstream main
    target_path: .claude/comp-behind/
    tiers: [5]

  comp-also-behind:
    repo: https://fake.test/comp-also-behind
    commit: ccccccc
    role: another fixture component behind upstream main
    target_path: .claude/comp-also-behind/
    tiers: [5]

  comp-self:
    repo: <self>
    commit: <self>
    role: self-hosted fixture component (should be skipped)
    target_path: .claude/comp-self/
    tiers: [5]
```

- [ ] **Step 2: Create the git ls-remote shim**

Create `scripts/tests/fixtures/git-ls-remote-shim.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Fake git for tests. Intercepts `git ls-remote <url> <ref>` and returns
# a fixture SHA based on (url, ref). All other git invocations delegate
# to the real git binary.
#
# Activate by prepending its directory to PATH and renaming/symlinking
# this file to `git` in that dir.

if [ "$1" = "ls-remote" ] && [ "$#" -ge 3 ]; then
  url="$2"
  ref="$3"
  case "$url:$ref" in
    "https://fake.test/comp-current:main")     echo "aaaaaaa1111111111111111111111111111111  refs/heads/main";;
    "https://fake.test/comp-behind:main")      echo "ddddddd2222222222222222222222222222222  refs/heads/main";;
    "https://fake.test/comp-also-behind:main") echo "eeeeeee3333333333333333333333333333333  refs/heads/main";;
    "https://fake.test/comp-behind:v1.0.0")    echo "fffffff4444444444444444444444444444444  refs/tags/v1.0.0";;
    *) exit 2;;
  esac
  exit 0
fi

# Delegate everything else to the real git, found by skipping our own PATH entry.
SHIM_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${SHIM_DIR}\$" | tr '\n' ':' | sed 's/:$//')
exec git "$@"
```

- [ ] **Step 3: Create the test runner skeleton**

Create `scripts/tests/upgrade.test.sh` with this exact content:

```bash
#!/usr/bin/env bash
# scripts/tests/upgrade.test.sh — tests for scripts/upgrade.sh.
#
# Each test runs upgrade.sh against a fresh copy of fixtures/MANIFEST.test.yaml
# with PATH prepended to shim git ls-remote (no network).

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
UPGRADE="$REPO_ROOT/upgrade.sh"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Run upgrade.sh in an isolated tempdir, with git shimmed.
# Sets RUN_OUT, RUN_ERR, RUN_RC, RUN_MANIFEST (post-run manifest contents).
run_upgrade() {
  RUN_TMP=$(mktemp -d)
  mkdir -p "$RUN_TMP/scripts"
  cp "$UPGRADE" "$RUN_TMP/scripts/upgrade.sh"
  cp "$FIXTURES/MANIFEST.test.yaml" "$RUN_TMP/MANIFEST.yaml"

  # Build a shim PATH entry containing a `git` symlink to the shim script.
  SHIM_BIN="$RUN_TMP/shimbin"
  mkdir -p "$SHIM_BIN"
  cp "$FIXTURES/git-ls-remote-shim.sh" "$SHIM_BIN/git"
  chmod +x "$SHIM_BIN/git"

  RUN_OUT=$(PATH="$SHIM_BIN:$PATH" bash "$RUN_TMP/scripts/upgrade.sh" "$@" 2>"$RUN_TMP/err")
  RUN_RC=$?
  RUN_ERR=$(cat "$RUN_TMP/err")
  RUN_MANIFEST=$(cat "$RUN_TMP/MANIFEST.yaml")
}

# ----- tests start here (filled in by later tasks) -----

echo
echo "--- summary ---"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 4: Create the README**

Create `scripts/tests/README.md` with this exact content:

```markdown
# scripts/tests

Bash tests for scripts in `scripts/`. Run from repo root:

    bash scripts/tests/upgrade.test.sh

Tests use a `git` shim (`fixtures/git-ls-remote-shim.sh`) prepended to `PATH`
so `git ls-remote` returns fixture SHAs without hitting the network. All other
git operations delegate to the real binary.

Each test runs `upgrade.sh` in a fresh tempdir against a copy of
`fixtures/MANIFEST.test.yaml`.
```

- [ ] **Step 5: Run the empty test runner to validate scaffolding**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected output:
```
--- summary ---
  PASS: 0
  FAIL: 0
```
Expected exit code: 0

- [ ] **Step 6: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/tests/
git commit -m "test(upgrade): scaffold test infrastructure with git ls-remote shim

Establishes pattern for testing scripts/ without network. The shim PATH-overrides
\`git\` to return fixture SHAs for known URLs, delegating other git commands to
the real binary."
```

---

## Task 2: Refactor existing single-component logic into functions (no behavior change)

The current script is a top-to-bottom imperative flow. Refactor into:
- `load_yaml_reader()` — picks `yq` or `python+PyYAML`
- `resolve_component(comp, ref)` — returns SHA mapping via stdout, sets globals or echoes a structured line
- `bump_component(comp, new_sha)` — calls `yq_set` for one component
- `update_released_at()` — bumps the top-level date
- Top-level `main()` that parses args and dispatches

**Files:**
- Modify: `scripts/upgrade.sh` (full refactor, keep semantics identical)

- [ ] **Step 1: Write a regression test for single-component path**

In `scripts/tests/upgrade.test.sh`, replace the `# ----- tests start here -----` marker section with this test, before the `--- summary ---` block:

```bash
echo "--- regression: single component bump (existing behavior) ---"

run_upgrade comp-behind
[ "$RUN_RC" -eq 0 ] && ok "exit 0" || ko "expected exit 0, got $RUN_RC"
echo "$RUN_OUT" | grep -q "Bumped comp-behind: bbbbbbb → ddddddd" \
  && ok "bumped comp-behind to expected SHA" \
  || ko "expected bump message, got: $RUN_OUT"
echo "$RUN_MANIFEST" | grep -q "commit: ddddddd" \
  && ok "MANIFEST contains new SHA" \
  || ko "MANIFEST missing new SHA"

echo
echo "--- regression: single component already current ---"

run_upgrade comp-current
[ "$RUN_RC" -eq 0 ] && ok "exit 0" || ko "expected exit 0"
echo "$RUN_OUT" | grep -q "comp-current already at aaaaaaa" \
  && ok "reports already-current" \
  || ko "expected already-current message, got: $RUN_OUT"

echo
echo "--- regression: self-hosted rejection (single component) ---"

run_upgrade comp-self
[ "$RUN_RC" -eq 2 ] && ok "exit 2" || ko "expected exit 2, got $RUN_RC"
echo "$RUN_ERR" | grep -q "cannot upgrade self-hosted" \
  && ok "rejects self-hosted" \
  || ko "expected self-hosted rejection, got: $RUN_ERR"
```

- [ ] **Step 2: Run regression tests against current upgrade.sh to confirm they pass**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: All 6 PASS, 0 FAIL, exit 0.

This confirms the test harness works and pins current behavior before refactor.

- [ ] **Step 3: Refactor upgrade.sh into functions**

Replace the entire contents of `scripts/upgrade.sh` with:

```bash
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
    --check)     MODE="check"; shift ;;
    --all)       MODE="all"; shift ;;
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
[ "$MODE" = "check" ] && [ "$MODE" = "all" ]        && usage_err "--check and --all are mutually exclusive"
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
```

- [ ] **Step 4: Run regression tests to confirm refactor preserves behavior**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: All 6 PASS, 0 FAIL, exit 0.

If any fail, fix the refactor before proceeding. The new code paths for `--check` and `--all` are now in place but untested — Tasks 3-6 add coverage.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/upgrade.sh scripts/tests/upgrade.test.sh
git commit -m "refactor(upgrade): extract resolve/bump into functions, add mode dispatcher

Introduces --check and --all dispatch paths alongside the existing single-component
path (currently the only one with test coverage; --check and --all tested in
follow-up commits). No behavior change for existing invocations."
```

---

## Task 3: Test and verify `--check` flag

The implementation is already in place from Task 2; this task adds test coverage to lock the behavior.

**Files:**
- Modify: `scripts/tests/upgrade.test.sh`

- [ ] **Step 1: Add tests for --check**

In `scripts/tests/upgrade.test.sh`, before the `--- summary ---` block, append:

```bash
echo
echo "--- --check: reports drift across all components ---"

run_upgrade --check
[ "$RUN_RC" -eq 0 ] && ok "exit 0 (default)" || ko "expected exit 0, got $RUN_RC"
echo "$RUN_OUT" | grep -q "comp-current.*aaaaaaa.*aaaaaaa.*current" \
  && ok "comp-current reported as current" \
  || ko "expected comp-current ✓ current, got: $RUN_OUT"
echo "$RUN_OUT" | grep -q "comp-behind.*bbbbbbb.*ddddddd.*behind" \
  && ok "comp-behind reported as behind" \
  || ko "expected comp-behind ⚠ behind, got: $RUN_OUT"
echo "$RUN_OUT" | grep -q "comp-also-behind.*ccccccc.*eeeeeee.*behind" \
  && ok "comp-also-behind reported as behind" \
  || ko "expected comp-also-behind ⚠ behind"
echo "$RUN_OUT" | grep -q "comp-self.*self-hosted" \
  && ok "comp-self reported as self-hosted" \
  || ko "expected comp-self ⊘ self-hosted"
echo "$RUN_OUT" | grep -q "2 component(s) behind" \
  && ok "summary counts drift" \
  || ko "expected '2 component(s) behind', got: $RUN_OUT"

# Manifest must NOT be modified by --check.
echo "$RUN_MANIFEST" | grep -q "commit: bbbbbbb" \
  && ok "comp-behind SHA unchanged in MANIFEST" \
  || ko "comp-behind SHA was modified by --check"

echo
echo "--- --check with all current ---"

# Manually create a no-drift fixture inline by running --all first then --check.
# Simpler approach: filter to comp-current only.
run_upgrade --check comp-current
[ "$RUN_RC" -eq 0 ] && ok "exit 0" || ko "expected exit 0"
echo "$RUN_OUT" | grep -q "All components current" \
  && ok "reports all-current when only current shown" \
  || ko "expected 'All components current', got: $RUN_OUT"

echo
echo "--- --check single component ---"

run_upgrade --check comp-behind
echo "$RUN_OUT" | grep -q "comp-behind.*behind" \
  && ok "filters to single component" \
  || ko "expected single-component check"
echo "$RUN_OUT" | grep -q "comp-current" \
  && ko "should not show other components" \
  || ok "other components filtered out"
```

- [ ] **Step 2: Run tests**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: All PASS (regression + new), 0 FAIL, exit 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/tests/upgrade.test.sh
git commit -m "test(upgrade): cover --check drift reporting"
```

---

## Task 4: Test `--exit-code` modifier

**Files:**
- Modify: `scripts/tests/upgrade.test.sh`

- [ ] **Step 1: Add --exit-code tests**

Append to `scripts/tests/upgrade.test.sh` before the summary block:

```bash
echo
echo "--- --check --exit-code with drift ---"

run_upgrade --check --exit-code
[ "$RUN_RC" -eq 1 ] && ok "exit 1 on drift" || ko "expected exit 1, got $RUN_RC"

echo
echo "--- --check --exit-code without drift (single current component) ---"

run_upgrade --check comp-current --exit-code
[ "$RUN_RC" -eq 0 ] && ok "exit 0 when current" || ko "expected exit 0, got $RUN_RC"

echo
echo "--- --exit-code without --check is rejected ---"

run_upgrade comp-behind --exit-code
[ "$RUN_RC" -eq 2 ] && ok "exit 2 (usage error)" || ko "expected exit 2, got $RUN_RC"
echo "$RUN_ERR" | grep -q "only valid with --check" \
  && ok "rejects --exit-code without --check" \
  || ko "expected usage error message, got: $RUN_ERR"
```

- [ ] **Step 2: Run tests**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: All PASS, 0 FAIL.

- [ ] **Step 3: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/tests/upgrade.test.sh
git commit -m "test(upgrade): cover --exit-code modifier"
```

---

## Task 5: Test `--all` flag

**Files:**
- Modify: `scripts/tests/upgrade.test.sh`

- [ ] **Step 1: Add --all tests**

Append to `scripts/tests/upgrade.test.sh` before the summary block:

```bash
echo
echo "--- --all: bumps behind components, skips current and self-hosted ---"

run_upgrade --all
[ "$RUN_RC" -eq 0 ] && ok "exit 0" || ko "expected exit 0, got $RUN_RC"

echo "$RUN_OUT" | grep -q "comp-behind.*bbbbbbb.*ddddddd" \
  && ok "bumps comp-behind" \
  || ko "expected comp-behind bump, got: $RUN_OUT"
echo "$RUN_OUT" | grep -q "comp-also-behind.*ccccccc.*eeeeeee" \
  && ok "bumps comp-also-behind" \
  || ko "expected comp-also-behind bump"
echo "$RUN_OUT" | grep -q "comp-current: already at aaaaaaa" \
  && ok "leaves comp-current alone" \
  || ko "expected comp-current skip"
echo "$RUN_OUT" | grep -q "comp-self: self-hosted" \
  && ok "skips comp-self" \
  || ko "expected comp-self skip"
echo "$RUN_OUT" | grep -q "Bumped 2, already-current 1, skipped 1" \
  && ok "summary line correct" \
  || ko "expected summary 'Bumped 2, already-current 1, skipped 1', got: $RUN_OUT"

# MANIFEST verification: bumped components updated, self/current untouched.
echo "$RUN_MANIFEST" | grep -q "commit: ddddddd" \
  && ok "comp-behind SHA written to MANIFEST" \
  || ko "comp-behind SHA missing from MANIFEST"
echo "$RUN_MANIFEST" | grep -q "commit: eeeeeee" \
  && ok "comp-also-behind SHA written to MANIFEST" \
  || ko "comp-also-behind SHA missing from MANIFEST"
echo "$RUN_MANIFEST" | grep -q "commit: aaaaaaa" \
  && ok "comp-current SHA preserved" \
  || ko "comp-current SHA missing"
echo "$RUN_MANIFEST" | grep -qE "commit: <self>|commit: '<self>'" \
  && ok "comp-self left as <self>" \
  || ko "comp-self was modified"

# released_at should be updated to today's date.
TODAY=$(date -u +%Y-%m-%d)
echo "$RUN_MANIFEST" | grep -q "released_at: .*$TODAY" \
  && ok "released_at bumped to today" \
  || ko "released_at not updated to $TODAY"

# Commit message should be a multi-line suggestion.
echo "$RUN_OUT" | grep -q "bump 2 components to latest main" \
  && ok "commit message reflects 2 components" \
  || ko "expected multi-component commit message"

echo
echo "--- --all --to is rejected ---"

run_upgrade --all --to v1.0.0
[ "$RUN_RC" -eq 2 ] && ok "exit 2 (usage error)" || ko "expected exit 2"
echo "$RUN_ERR" | grep -q "does not support --to" \
  && ok "rejects --to with --all" \
  || ko "expected --to rejection, got: $RUN_ERR"

echo
echo "--- --all <component> is rejected ---"

run_upgrade --all comp-behind
[ "$RUN_RC" -eq 2 ] && ok "exit 2 (usage error)" || ko "expected exit 2"
echo "$RUN_ERR" | grep -q "mutually exclusive with a component" \
  && ok "rejects positional component with --all" \
  || ko "expected mutual-exclusion error"
```

- [ ] **Step 2: Run tests**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: All PASS, 0 FAIL.

If the `released_at` test fails because the `python3 yaml.safe_dump` reformats the file, investigate the output of `run_upgrade --all`'s manifest and adjust the grep pattern (PyYAML may emit dates without quotes, e.g. `released_at: 2026-05-11`). Update the test grep to match whichever form is actually written.

- [ ] **Step 3: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/tests/upgrade.test.sh
git commit -m "test(upgrade): cover --all bump behavior"
```

---

## Task 6: Test `--check --all` mutual exclusion

**Files:**
- Modify: `scripts/tests/upgrade.test.sh`

- [ ] **Step 1: Add mutual exclusion test**

Append to `scripts/tests/upgrade.test.sh` before the summary block:

```bash
echo
echo "--- --check --all is rejected ---"

run_upgrade --check --all
[ "$RUN_RC" -eq 2 ] && ok "exit 2 (usage error)" || ko "expected exit 2"
```

Note: the current implementation in Task 2 has a buggy mutual-exclusion check (`[ "$MODE" = "check" ] && [ "$MODE" = "all" ]` can never be true because a variable can't equal two different values simultaneously). The second flag overwrites `MODE`, so this combination currently runs as `--all`. Fix during this task.

- [ ] **Step 2: Run test to confirm it fails**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: this test FAILs (exits 0, not 2) because the buggy check passes silently.

- [ ] **Step 3: Fix the mutual exclusion in upgrade.sh**

In `scripts/upgrade.sh`, replace the arg parsing block:

```bash
    --check)     MODE="check"; shift ;;
    --all)       MODE="all"; shift ;;
```

with:

```bash
    --check)
      [ "$MODE" = "all" ] && usage_err "--check and --all are mutually exclusive"
      MODE="check"; shift ;;
    --all)
      [ "$MODE" = "check" ] && usage_err "--check and --all are mutually exclusive"
      MODE="all"; shift ;;
```

And remove the now-redundant line from the validation block:

```bash
[ "$MODE" = "check" ] && [ "$MODE" = "all" ]        && usage_err "--check and --all are mutually exclusive"
```

- [ ] **Step 4: Run test to verify the fix**

Run: `bash /Users/viv/AI/vault/viv-typed-agents/scripts/tests/upgrade.test.sh`

Expected: all tests PASS, including the new mutual-exclusion test.

- [ ] **Step 5: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add scripts/upgrade.sh scripts/tests/upgrade.test.sh
git commit -m "fix(upgrade): detect --check/--all conflict at parse time

The previous AND-check was a tautology that never fired (a single variable cannot
equal two distinct values). Move the check into each flag's parser branch so the
second flag triggers a usage error against any prior mode."
```

---

## Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Find the right insertion point**

Read `README.md` and identify the section discussing `upgrade.sh` (look for "upgrade" or "MANIFEST" references). The new subsection should follow whatever existing operational doc structure is there.

Run: `grep -n -iE "upgrade|manifest" /Users/viv/AI/vault/viv-typed-agents/README.md`

- [ ] **Step 2: Add the new subsection**

Insert this content after the existing upgrade documentation (or at the end of the operations section if no dedicated upgrade doc exists). Use Edit, anchoring on an exact existing line for `old_string` once you've identified it:

```markdown
### Keeping components current

Component repos advance independently. To check for drift between `MANIFEST.yaml`
and each component's upstream `main`:

    ./scripts/upgrade.sh --check

To bump every drifted component to its `main` HEAD in one shot:

    ./scripts/upgrade.sh --all
    git diff MANIFEST.yaml
    # commit with the suggested message printed by the script

To bump a single component to a specific ref (e.g. a release tag), use the
existing single-component form:

    ./scripts/upgrade.sh viv-hooks --to v1.2.0

In CI, fail the build when the manifest is stale:

    ./scripts/upgrade.sh --check --exit-code
```

- [ ] **Step 3: Verify rendered Markdown**

Run: `head -120 /Users/viv/AI/vault/viv-typed-agents/README.md`

Confirm the new section reads cleanly and integrates with surrounding content.

- [ ] **Step 4: Commit**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add README.md
git commit -m "docs(readme): document --check, --all, and --exit-code on upgrade.sh"
```

---

## Task 8: End-to-end validation against real repos

This task runs the actual script against the real upstream repos (not the shim) to catch issues the fixture can't surface: real `git ls-remote` output, real `yq`/`python` YAML serialization, real MANIFEST roundtrip.

**Files:** None modified. This task only runs commands and confirms output.

- [ ] **Step 1: Confirm clean working tree**

Run: `cd /Users/viv/AI/vault/viv-typed-agents && git status`

Expected: working tree clean (all task commits done).

- [ ] **Step 2: Run --check against real repos**

Run: `cd /Users/viv/AI/vault/viv-typed-agents && ./scripts/upgrade.sh --check`

Expected: table listing all 7 components with their pinned SHA, upstream SHA, and status. At least 4 should show ⚠ behind (consistent with the drift observed during design).

- [ ] **Step 3: Run --check --exit-code and confirm exit 1**

Run: `cd /Users/viv/AI/vault/viv-typed-agents && ./scripts/upgrade.sh --check --exit-code; echo "rc=$?"`

Expected: `rc=1` (since drift exists).

- [ ] **Step 4: Run --all and inspect MANIFEST diff**

Run:
```bash
cd /Users/viv/AI/vault/viv-typed-agents
./scripts/upgrade.sh --all
git diff MANIFEST.yaml
```

Expected: `git diff` shows SHA bumps for each drifted component and `released_at` updated to today.

- [ ] **Step 5: Re-run --check to confirm zero drift**

Run: `cd /Users/viv/AI/vault/viv-typed-agents && ./scripts/upgrade.sh --check --exit-code; echo "rc=$?"`

Expected: `rc=0`, all components reported as ✓ current.

- [ ] **Step 6: Commit MANIFEST bump**

Use the suggested commit message from Step 4's output:

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git add MANIFEST.yaml
git commit -m "deps: bump N components to latest main

- viv-agents: <old> → <new>
- viv-hooks: <old> → <new>
- viv-routing: <old> → <new>
- viv-skills: <old> → <new>"
```

(Replace `N` and the per-component lines with the actual SHAs from the run.)

- [ ] **Step 7: Push branch and open PR**

```bash
cd /Users/viv/AI/vault/viv-typed-agents
git push -u origin feat/upgrade-all-and-check
gh pr create --title "feat(upgrade): --all and --check flags (#11)" --body "$(cat <<'EOF'
## Summary
- Adds `--check` flag for read-only drift reporting against upstream `main`
- Adds `--all` flag for bumping every drifted non-self-hosted component
- Adds `--exit-code` modifier for CI usage with `--check`
- Establishes test infrastructure for `scripts/` with `git ls-remote` shim
- Bumps MANIFEST.yaml to current upstream HEADs (4 components)

Closes #11.

## Test plan
- [x] Unit tests in `scripts/tests/upgrade.test.sh` pass
- [x] E2E: `--check` against real repos lists drift
- [x] E2E: `--all` updates MANIFEST.yaml; subsequent `--check` shows no drift
- [x] Regression: single-component `upgrade.sh <comp>` still works

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

---

## Self-Review

**1. Spec coverage:**
- ✓ `--check` (Tasks 2, 3)
- ✓ `--all` (Tasks 2, 5)
- ✓ `--exit-code` (Tasks 2, 4)
- ✓ Self-hosted skip (Tasks 2, 3, 5)
- ✓ Single-component regression (Task 2)
- ✓ Flag-combination matrix (Tasks 4, 5, 6)
- ✓ Atomic write via tempfile (Task 2)
- ✓ Multi-line commit message (Task 5)
- ✓ README update (Task 7)
- ✓ Test infrastructure pattern (Task 1)
- ✓ E2E validation (Task 8)

**2. Placeholder scan:** No TBDs, all code blocks are complete, all commands have expected outputs.

**3. Type consistency:** `resolve_component()`, `bump_component()`, `update_released_at()`, `list_components()` used consistently across tasks. `MANIFEST_TMP`/`MANIFEST_REAL` swap pattern explained in code comments.

**4. Risk note:** Task 5 Step 2 flags the PyYAML date-quoting variability — if PyYAML strips quotes from `released_at`, the test grep is adjustable. This is a known fragility, not a placeholder.
