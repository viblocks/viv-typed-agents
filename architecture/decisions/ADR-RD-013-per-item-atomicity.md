# ADR-RD-013 — Per-item atomicity contract for typed agents (`commit_item(i)` + `validate_item(i)`)

**Status:** Accepted
**Date:** 2026-05-22
**Category:** Cross-component (binds viv-typed-agents SPEC + viv-agents implementations)

## Context

Workers in this network are **ephemeral**: each `Agent()` dispatch runs in a subprocess with a runtime-imposed TTL (currently 600s). When TTL expires, the worker is terminated abruptly regardless of in-flight state.

A dispatch carrying `N > 1` items leaves the system in one of three states (per [`viv-orchestration-rules ttl-batch-sizing.md`](https://github.com/viblocks/viv-orchestration-rules/blob/main/rules/common/ttl-batch-sizing.md)):

1. **Clean termination between items** — recoverable.
2. **Mid-item truncation** — partial file write or partial transaction. **Not recoverable** without manual remediation.
3. **Validation interrupted** — all items written, none verified. Indeterminate.

The policy rule (cap at `floor(ceiling × 0.8)`) reduces frequency of state-1 truncations. It does NOT eliminate the structural risk of state-2 and state-3, because:

- Cost variance across items means a single oversized item can still consume the entire TTL after items 1..K-1 succeeded.
- A global validation pass at end-of-batch can be cut off mid-validation, leaving everything written but nothing verified.

The fix has to live **at the agent level**, not at the orchestrator level. Specifically, in the contract every typed agent honors when iterating over a multi-item brief.

## Decision

Adopt a **per-item atomicity contract** required of every typed agent dispatched with `N > 1`. The contract has two mandatory phases:

1. **`commit_item(i)`** — persist item `i` to durable state before item `i+1` begins. Atomicity at the item granularity, not the batch.
2. **`validate_item(i)`** — run item `i`'s verification inside the same dispatch, immediately after production. No deferral to end-of-batch.

When `validate_item(i)` fails, the agent applies one of three named policies — `abort`, `skip`, or `retry` — declared per-agent in its system prompt. The orchestrator inspects evidence to confirm the contract was honored.

The contract is documented in [SPEC.md Section 3.3](../../SPEC.md). A reference prompt fragment lives at [`docs/per-item-atomicity-contract.md`](../../docs/per-item-atomicity-contract.md). A bash regression test exercises the pattern under simulated abrupt termination at [`scripts/tests/per-item-atomicity.test.sh`](../../scripts/tests/per-item-atomicity.test.sh).

### Why per-agent, not per-orchestrator

The orchestrator decides `N` and dispatches. The orchestrator does NOT control how the agent iterates internally. Atomicity of writes happens inside the agent's loop — the orchestrator can only verify after the fact via evidence. If the contract is not enforced at the agent layer, the orchestrator's cap-and-split discipline is insufficient: a slow item still leaves state-2 corruption.

### Why three failure policies, not one

- **`abort`** is the safe default. It preserves state-1 properties cleanly.
- **`skip`** is necessary for legitimately independent items where partial completion beats no completion.
- **`retry`** is for transient failures, but bounded to a single re-attempt to prevent retry loops from burning TTL.

A single one-size policy would either over-block (everything aborts on first failure) or under-block (silent skip masks real defects). Three named policies forces agent authors to declare intent.

## Rationale

| Principle | How this satisfies |
|---|---|
| State-2 elimination | Atomic commit at item granularity means mid-item failure rolls back exactly the in-flight item; previous items are independently valid. |
| State-3 elimination | In-band validation means the dispatch never returns "everything written, nothing verified." |
| Explicit policy | Named failure semantics (`abort`/`skip`/`retry`) are declared in the agent's prompt — no ambiguity at incident time. |
| Reviewer compatibility | Read-only agents (reviewers, Explore, spec-review general-purpose) are unaffected — they don't write, so per-item atomicity is trivially satisfied. |
| OCP at the agent level | Adding a new agent that batches doesn't require new orchestrator logic — the agent embeds the contract or fails review. |

## Consequences

### What changes

- SPEC.md Section 3.3 now defines the contract authoritatively for the typed-agents network.
- Appendix B gains invariant #8 (per-item atomicity).
- Glossary gains entries for `commit_item(i)`, `validate_item(i)`, and "per-item atomicity contract."
- `docs/per-item-atomicity-contract.md` provides the reference prompt fragment that agents in [viv-agents](https://github.com/viblocks/viv-agents) embed.
- `scripts/tests/per-item-atomicity.test.sh` provides a behavioral regression test that simulates abrupt termination.
- Per-agent updates in [viv-agents](https://github.com/viblocks/viv-agents) follow as a separate cross-repo task (to be tracked there).

### What does NOT change

- IRON LAW unchanged. Dispatch routing unchanged.
- The `[EVIDENCE REQUIRED]` block shape unchanged — extended fields are additive.
- Single-item dispatches (`N = 1`) are unaffected: the contract is trivially satisfied.
- Pure-descriptor invariant (ADR-RD-008) preserved — this repo gains prose + tests in bash that simulate behavior, not new runtime code.

### Trade-offs

- **Per-item commit costs more than batch commit** for some artifact categories (e.g., a single git commit for all N files vs N atomic file writes). Accepted: the cost of state-2 cleanup vastly exceeds the per-item overhead.
- **In-band validation costs more than global validation** because some checks (full typecheck, full lint pass) are inherently global. Mitigation: per-item validation runs **the local subset** of validators applicable to that item's path; global checks still run at end-of-batch but their failure no longer corrupts state.
- **Three named policies** put cognitive load on agent authors. Accepted: forcing the decision at design time prevents ad-hoc decisions at incident time.

## Alternatives considered

- **"Make the orchestrator atomic via transactional dispatch."** Rejected — the orchestrator cannot wrap an agent's internal loop in a transaction; the agent's writes are observable outside the dispatch boundary.
- **"Single failure policy: abort on any validation failure."** Rejected — over-restrictive for legitimately independent item batches (e.g., generating N unrelated stubs).
- **"Per-batch commit at end-of-batch."** Rejected — this IS the current default and IS exactly what causes state-2. The whole point of the ADR is to invert this.
- **"Defer entirely to viv-orchestration-rules; no agent-side contract."** Rejected — orchestrator cannot enforce atomicity inside the agent's loop. The agent must implement it.
- **"Add a fourth `defer` policy that queues failures for human review."** Rejected for v1 — premature without operational data; can be added later if `skip` proves too coarse.

## Related

- [`viv-orchestration-rules ADR-005`](https://github.com/viblocks/viv-orchestration-rules/blob/main/architecture/decisions/ADR-005-ttl-safety-batch-sizing.md) — policy parent.
- ADR-RD-008 (pure descriptors) — preserved: this repo gains prose + tests, not new runtime code.
- ADR-RD-006 (three hook types) — orthogonal; this contract is at the agent layer, hooks at the enforcement layer.
- [`viv-aidlc-orchestrator#12`](https://github.com/viblocks/viv-aidlc-orchestrator/issues/12) — pre-dispatch cap + telemetry consume this contract's evidence.
- [`viv-workflows#2`](https://github.com/viblocks/viv-workflows/issues/2) — workflow audit references this contract when refactoring N > cap batches.
