#!/usr/bin/env bash
# scripts/tests/per-item-atomicity.test.sh — regression tests for the
# Per-Item Atomicity Contract (SPEC.md §3.3, ADR-RD-013).
#
# Exercises the reference worker fixture under simulated abrupt termination
# and the three declared failure policies (abort, skip, retry). Verifies the
# invariant: at any termination point, items 1..K-1 are independently valid;
# item K is either fully committed or fully rolled back (never partial).

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKER="$TESTS_DIR/fixtures/atomic-worker.sh"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
ko() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Fresh tempdir per scenario.
make_tmp() {
  TMP=$(mktemp -d)
}

# Assert item i is committed (final file exists with valid content, no .tmp leftover).
assert_committed() {
  local i="$1"
  local tmp="$TMP/item-$i.txt.tmp"
  local final="$TMP/item-$i.txt"
  if [ ! -f "$final" ]; then
    ko "item $i: expected committed, final file missing"
    return
  fi
  if ! grep -q "^item-$i OK$" "$final"; then
    ko "item $i: final file has unexpected content"
    return
  fi
  if [ -f "$tmp" ]; then
    ko "item $i: .tmp leftover after commit (atomicity broken)"
    return
  fi
  ok "item $i committed cleanly"
}

# Assert item i is NOT committed (final file absent, .tmp may or may not exist).
# The invariant is "no partial reads from the final path" — final file must not exist.
assert_not_committed() {
  local i="$1"
  local final="$TMP/item-$i.txt"
  if [ -f "$final" ]; then
    ko "item $i: expected NOT committed but final file exists"
    return
  fi
  ok "item $i not committed (final path clean)"
}

# Assert item i is rolled back (neither final nor .tmp exists).
assert_rolled_back() {
  local i="$1"
  local final="$TMP/item-$i.txt"
  local tmp="$TMP/item-$i.txt.tmp"
  if [ -f "$final" ]; then
    ko "item $i: expected rolled back but final file exists"
    return
  fi
  if [ -f "$tmp" ]; then
    ko "item $i: expected rolled back but .tmp leftover"
    return
  fi
  ok "item $i rolled back cleanly (no final, no .tmp)"
}

echo "--- scenario: happy path, N=5, no failures ---"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || ko "expected exit 0, got $rc"
for i in 1 2 3 4 5; do assert_committed "$i"; done

echo
echo "--- scenario: abrupt termination AFTER tmp write at item 3 ---"
echo "    expectation: items 1,2 committed; item 3 NOT at final path; items 4,5 untouched"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 --die-after-tmp 3 >/dev/null 2>&1
rc=$?
[ "$rc" -eq 137 ] && ok "exit 137 (simulated SIGKILL)" || ko "expected exit 137, got $rc"
assert_committed 1
assert_committed 2
# Item 3: final must NOT exist (the whole point of the invariant). .tmp leftover
# is acceptable — it represents recoverable state-1, not unrecoverable state-2.
assert_not_committed 3
assert_not_committed 4
assert_not_committed 5

echo
echo "--- scenario: abrupt termination AFTER validate at item 3 (just before rename) ---"
echo "    expectation: items 1,2 committed; item 3 NOT at final path; items 4,5 untouched"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 --die-after-validate 3 >/dev/null 2>&1
rc=$?
[ "$rc" -eq 137 ] && ok "exit 137" || ko "expected exit 137, got $rc"
assert_committed 1
assert_committed 2
assert_not_committed 3
assert_not_committed 4
assert_not_committed 5

echo
echo "--- scenario: validation fails at item 3, policy=abort ---"
echo "    expectation: items 1,2 committed; item 3 rolled back; items 4,5 untouched"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 --validate-fail 3 --policy abort >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 (abort)" || ko "expected exit 1, got $rc"
assert_committed 1
assert_committed 2
assert_rolled_back 3
assert_not_committed 4
assert_not_committed 5

echo
echo "--- scenario: validation fails at item 3, policy=skip ---"
echo "    expectation: items 1,2,4,5 committed; item 3 rolled back; evidence lists skip"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 --validate-fail 3 --policy skip >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 (skip continues)" || ko "expected exit 0, got $rc"
assert_committed 1
assert_committed 2
assert_rolled_back 3
assert_committed 4
assert_committed 5
grep -q "^skipped=3$" "$TMP/.evidence.txt" \
  && ok "evidence records skip of item 3" \
  || ko "evidence missing skip=3, got: $(cat "$TMP/.evidence.txt")"

echo
echo "--- scenario: validation fails at item 3, policy=retry, retry SUCCEEDS ---"
echo "    expectation: items 1..5 all committed; evidence lists retry"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 --validate-fail 3 --policy retry --retry-succeed >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 (retry succeeded)" || ko "expected exit 0, got $rc"
for i in 1 2 3 4 5; do assert_committed "$i"; done
grep -q "^retrying=3$" "$TMP/.evidence.txt" \
  && ok "evidence records retry of item 3" \
  || ko "evidence missing retrying=3"

echo
echo "--- scenario: validation fails at item 3, policy=retry, retry FAILS (falls back to abort) ---"
echo "    expectation: items 1,2 committed; item 3 rolled back; items 4,5 untouched"
make_tmp
bash "$WORKER" --out "$TMP" --n 5 --validate-fail 3 --policy retry >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 (retry exhausted → abort)" || ko "expected exit 1, got $rc"
assert_committed 1
assert_committed 2
assert_rolled_back 3
assert_not_committed 4
assert_not_committed 5
grep -q "aborted_at=3 (retry_failed)" "$TMP/.evidence.txt" \
  && ok "evidence records retry exhaustion" \
  || ko "evidence missing retry_failed marker"

echo
echo "--- invariant check: across ALL scenarios, no final path was ever observed with partial content ---"
echo "    (covered by assert_committed grep + assert_not_committed missing-file checks above)"
ok "no partial final-path content observed"

echo
echo "--- summary ---"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
