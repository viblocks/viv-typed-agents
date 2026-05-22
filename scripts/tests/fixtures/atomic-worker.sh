#!/usr/bin/env bash
# Reference implementation of the Per-Item Atomicity Contract (SPEC.md §3.3,
# ADR-RD-013, docs/per-item-atomicity-contract.md).
#
# This is a BEHAVIORAL fixture for scripts/tests/per-item-atomicity.test.sh.
# Real typed agents are LLM prompts, not bash. The fixture exists to let us
# regression-test the contract's invariants under simulated abrupt termination
# and validation failure modes.
#
# Usage:
#   atomic-worker.sh --out <dir> --n <N> [--die-after-tmp K] [--die-after-validate K]
#                    [--validate-fail K] [--policy abort|skip|retry]
#                    [--retry-succeed]
#
# Flags:
#   --out DIR            Output directory for items (must exist).
#   --n N                Total number of items to produce (1..N).
#   --die-after-tmp K    Exit 137 immediately AFTER writing item K's .tmp, BEFORE rename.
#                        Simulates worker SIGKILL mid-item. Items 1..K-1 already committed;
#                        item K leaves only a .tmp leftover, never appears at the final path.
#   --die-after-validate K  Exit 137 immediately AFTER validating item K, BEFORE rename/commit.
#                           Same observable invariant: K not committed.
#   --validate-fail K    Make validation of item K fail (file content includes BAD_CONTENT).
#                        Triggers the declared --policy.
#   --policy POLICY      One of: abort | skip | retry. Default: abort.
#   --retry-succeed      With --policy retry: make the retry succeed (else falls back to abort).
#
# Exit codes:
#   0   normal completion of all N items, or skip-policy completed with some skips
#   1   abort policy triggered by validation failure
#   137 simulated abrupt termination (set by --die-after-* flags)

set -uo pipefail

OUT=""
N=0
DIE_AFTER_TMP=-1
DIE_AFTER_VALIDATE=-1
VALIDATE_FAIL=-1
POLICY="abort"
RETRY_SUCCEED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --n) N="$2"; shift 2 ;;
    --die-after-tmp) DIE_AFTER_TMP="$2"; shift 2 ;;
    --die-after-validate) DIE_AFTER_VALIDATE="$2"; shift 2 ;;
    --validate-fail) VALIDATE_FAIL="$2"; shift 2 ;;
    --policy) POLICY="$2"; shift 2 ;;
    --retry-succeed) RETRY_SUCCEED=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[ -z "$OUT" ] && { echo "--out required" >&2; exit 2; }
[ ! -d "$OUT" ] && { echo "--out dir does not exist: $OUT" >&2; exit 2; }
[ "$N" -lt 1 ] && { echo "--n must be >= 1" >&2; exit 2; }

# Evidence file — written incrementally so a killed dispatch still shows what
# the worker accomplished. The orchestrator's audit reads this on return.
EVIDENCE="$OUT/.evidence.txt"
: > "$EVIDENCE"
echo "policy=$POLICY n=$N" >> "$EVIDENCE"

completed=0
skipped=()
retried=()

# produce <i>: writes the .tmp file with content. If --validate-fail==i,
# content is BAD_CONTENT (triggers validator failure).
produce() {
  local i="$1"
  local target="$OUT/item-$i.txt"
  if [ "$VALIDATE_FAIL" = "$i" ]; then
    printf 'BAD_CONTENT\n' > "$target.tmp"
  else
    printf 'item-%s OK\n' "$i" > "$target.tmp"
  fi
}

# validate <i>: returns 0 if item i's .tmp content is valid, 1 otherwise.
validate() {
  local i="$1"
  local target="$OUT/item-$i.txt.tmp"
  grep -q '^BAD_CONTENT$' "$target" && return 1
  grep -q "^item-$i OK$" "$target" && return 0
  return 1
}

# rollback <i>: remove the in-flight .tmp for item i.
rollback() {
  local i="$1"
  rm -f "$OUT/item-$i.txt.tmp"
}

# commit <i>: atomic rename of .tmp → final.
commit() {
  local i="$1"
  local target="$OUT/item-$i.txt"
  mv "$target.tmp" "$target"
}

for i in $(seq 1 "$N"); do
  # Step 1: PRODUCE
  produce "$i"

  # Simulated abrupt termination after tmp write, before validate/rename.
  if [ "$DIE_AFTER_TMP" = "$i" ]; then
    echo "died_after_tmp=$i" >> "$EVIDENCE"
    exit 137
  fi

  # Step 2: VALIDATE (in-band)
  if validate "$i"; then
    validate_ok=1
  else
    validate_ok=0
  fi

  # Step 3: FAILURE POLICY if validation failed
  if [ "$validate_ok" = "0" ]; then
    case "$POLICY" in
      abort)
        rollback "$i"
        echo "completed=$completed" >> "$EVIDENCE"
        echo "aborted_at=$i" >> "$EVIDENCE"
        exit 1
        ;;
      skip)
        rollback "$i"
        skipped+=("$i")
        echo "skipped=$i" >> "$EVIDENCE"
        continue
        ;;
      retry)
        rollback "$i"
        retried+=("$i")
        echo "retrying=$i" >> "$EVIDENCE"
        # Re-attempt: if --retry-succeed, produce a valid item this time.
        if [ "$RETRY_SUCCEED" = "1" ]; then
          printf 'item-%s OK\n' "$i" > "$OUT/item-$i.txt.tmp"
          if ! validate "$i"; then
            rollback "$i"
            echo "completed=$completed" >> "$EVIDENCE"
            echo "aborted_at=$i (retry_failed)" >> "$EVIDENCE"
            exit 1
          fi
        else
          # Second attempt also fails → fall back to abort (never to skip).
          rollback "$i"
          echo "completed=$completed" >> "$EVIDENCE"
          echo "aborted_at=$i (retry_failed)" >> "$EVIDENCE"
          exit 1
        fi
        ;;
      *)
        echo "unknown policy: $POLICY" >&2
        exit 2
        ;;
    esac
  fi

  # Simulated abrupt termination after validate, before commit.
  if [ "$DIE_AFTER_VALIDATE" = "$i" ]; then
    echo "died_after_validate=$i" >> "$EVIDENCE"
    exit 137
  fi

  # Step 4: COMMIT (atomic rename)
  commit "$i"
  completed=$((completed + 1))
  echo "committed=$i" >> "$EVIDENCE"
done

# Final evidence summary
{
  echo "completed=$completed"
  echo "items_skipped=${skipped[*]:-none}"
  echo "items_retried=${retried[*]:-none}"
} >> "$EVIDENCE"

exit 0
