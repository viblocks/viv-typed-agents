# Per-Item Atomicity Contract — Reference Prompt Fragment

This document provides the **reference prompt fragment** that a typed agent embeds in its system prompt when it accepts multi-item dispatches (`N > 1`). Canonical agent definitions live in [`viv-agents`](https://github.com/viblocks/viv-agents) — they SHOULD embed this fragment verbatim or an explicitly equivalent variant.

The contract is defined authoritatively in [SPEC.md Section 3.3](../SPEC.md). The decision rationale lives in [ADR-RD-013](../architecture/decisions/ADR-RD-013-per-item-atomicity.md). The behavioral regression test lives in [`scripts/tests/per-item-atomicity.test.sh`](../scripts/tests/per-item-atomicity.test.sh).

---

## When this fragment applies

Embed in any typed agent that:
- Receives briefs with `N > 1` items per dispatch (codegen of multiple files, migration of multiple statements, transformation of multiple records).
- Writes to durable state (filesystem, database, message bus).

**Do NOT embed in:**
- Read-only agents (reviewers, Explore, spec-review general-purpose). They don't write, contract is trivially satisfied.
- Single-item agents (one file per dispatch by design). Atomicity is bounded trivially.

---

## Reference fragment (embed verbatim or equivalent)

```
[PER-ITEM ATOMICITY CONTRACT]
Per viv-typed-agents SPEC §3.3 and ADR-RD-013. This contract is non-negotiable
when N > 1.

For each item i in the brief (i = 1..N):

  1. PRODUCE item i — write to durable state via a tmp path:
       - File create/modify    → write to `<path>.tmp`, never to `<path>` directly.
       - Multi-file per item   → write all files to `.tmp` siblings.
       - DB statement          → use SAVEPOINT before each item's statements.
       - Message production    → produce to a stage buffer, not the final topic.

  2. VALIDATE item i IN-BAND — run the validators applicable to item i's paths,
     immediately after step 1, in the same dispatch. Do NOT defer to end-of-batch.
       - File             → applicable lint/typecheck/syntax check for that file
       - DB statement     → constraint check / dry-run / RAISE
       - Message          → schema validation against the producer contract

  3. APPLY FAILURE POLICY if step 2 failed:
       - Policy = <abort | skip | retry>  ← declared by the agent (see below)
       - abort  → roll back item i, surface error, STOP. Do not proceed to item i+1.
       - skip   → roll back item i, log to evidence as skipped, proceed to item i+1.
       - retry  → re-attempt item i ONCE with the validation error as added context.
                  On second failure: fall back to abort. Never to skip.

  4. COMMIT item i atomically:
       - File             → `mv <path>.tmp <path>` (POSIX-atomic rename)
       - Multi-file       → mv each sibling; if any mv fails, surface and stop
       - DB statement     → RELEASE SAVEPOINT for item i
       - Message          → publish stage → final, ack on success

  5. ONLY THEN advance to item i+1.

INVARIANT — if this dispatch is terminated abruptly at any point:
  Items 1..K-1 (already past step 4) are independently valid.
  Item K (if in progress) is either entirely rolled back (steps 1-3) or
  fully committed (after step 4). Never partial.

EVIDENCE — extend the standard [EVIDENCE REQUIRED] block with:
  Items completed   : <K> of <N>
  Items skipped     : <list of i values, or "none">
  Items retried     : <list of i values, or "none">
  Failure policy    : <abort|skip|retry>  ← THIS agent's policy for this dispatch
```

---

## Policy selection per agent

When authoring a typed agent that embeds this contract, the agent's prompt MUST also declare which failure policy applies. The choice is part of the agent's definition, not decided at dispatch time.

| Agent category | Recommended policy | Rationale |
|---|---|---|
| Backend implementer iterating over `N` related files | **abort** | Files share contracts; one broken file invalidates downstream items. |
| Frontend implementer creating `N` independent components | **skip** | Components are independent; partial completion has value. |
| Migration agent processing `N` schema statements | **abort** | Statements may have dependencies; rollback preserves invariants. |
| Codegen agent producing `N` unrelated stubs | **skip** | Stubs are independent; partial scaffolding has value. |
| Test generator producing `N` test files | **skip** | Tests are independent; missing tests are visible. |
| Any agent against an external API with transient flakiness | **retry** (then abort) | Transient failures justify one re-attempt; loops do not. |

Authors choose by reasoning about item dependence, not by preference. If unsure: **abort** is the safe default.

---

## Validator scope per item

`validate_item(i)` runs **the local subset** of validators applicable to item `i`. It does NOT run the entire project's lint/test/build. The validator scope:

| Item type | Local validator |
|---|---|
| TS/JS file | `tsc --noEmit <file>` + `eslint <file>` (per-file mode) |
| Python file | `mypy <file>` + `ruff check <file>` |
| SQL statement | EXPLAIN (or driver-specific dry-run) |
| Markdown | optional: link check on `<file>` only |
| Config file (JSON/YAML) | schema validation against the declared schema |

Global validation (full typecheck across the project, full test suite) still runs at end-of-batch under the existing post-implementation chain. Per-item validation is **in addition to**, not a replacement for, the global pass.

---

## Antipatterns this contract forbids

| Antipattern | Why it's forbidden |
|---|---|
| Write all N files first, validate at the end | Validation can be cut off → state-3 indeterminate. |
| Batch-commit (e.g., one `git add . && git commit`) after the loop | Failure at item K corrupts state for items 1..K-1's "atomic" history. |
| "I'll mark as complete if no error was raised" | The absence of an error in a truncated dispatch ≠ validation passed. Evidence must reflect what was actually run. |
| Skip without logging | Silent skip masks real defects; evidence MUST list every skipped item. |
| Retry more than once | One retry justifies "transient"; more justifies "broken" and should abort. |
| Choose policy at dispatch time | The orchestrator can't audit a policy that wasn't declared up front. Policy is declared in the agent prompt. |

---

## How an orchestrator audits compliance

When the dispatch returns, the orchestrator's evidence verification (per [`viv-orchestration-rules subagent-dispatch-contract.md`](https://github.com/viblocks/viv-orchestration-rules/blob/main/rules/common/subagent-dispatch-contract.md)) checks the extended evidence fields:

1. `Items completed: K of N` is present.
2. If `K < N`, then `Items skipped` and/or the failure policy explains the gap.
3. `Failure policy` matches what the agent's prompt declared (cross-check is the orchestrator's responsibility).

If any extended field is missing → treat as FAIL, escalate to user.

---

## Related

- SPEC.md Section 3.3 — authoritative contract definition
- [ADR-RD-013](../architecture/decisions/ADR-RD-013-per-item-atomicity.md) — decision rationale
- [`scripts/tests/per-item-atomicity.test.sh`](../scripts/tests/per-item-atomicity.test.sh) — behavioral regression test
- [`viv-orchestration-rules ttl-batch-sizing.md`](https://github.com/viblocks/viv-orchestration-rules/blob/main/rules/common/ttl-batch-sizing.md) — policy parent
- [`viv-orchestration-rules subagent-dispatch-contract.md`](https://github.com/viblocks/viv-orchestration-rules/blob/main/rules/common/subagent-dispatch-contract.md) — orchestrator-side audit hook
