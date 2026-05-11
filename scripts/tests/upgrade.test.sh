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
echo "--- summary ---"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
