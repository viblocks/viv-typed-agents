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
