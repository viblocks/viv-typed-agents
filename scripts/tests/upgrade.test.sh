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

# ----- tests start here -----

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

# Filter to comp-current only — no drift expected.
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

# MANIFEST verification.
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

# released_at should be today.
TODAY=$(date -u +%Y-%m-%d)
echo "$RUN_MANIFEST" | grep -q "released_at: .*$TODAY" \
  && ok "released_at bumped to today" \
  || ko "released_at not updated to $TODAY (manifest: $RUN_MANIFEST)"

# Commit message line.
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

echo
echo "--- summary ---"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
