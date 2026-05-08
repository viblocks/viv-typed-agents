# ADR-RD-007 — Defer dispatch validation from Agent dispatch to Edit/Write time

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-hooks)

## Context

viblocks-ai's `pretooluse-agent.sh` validates agent dispatches **at dispatch time**:

```bash
# Greps the prompt searching for path patterns
backend=$(echo "$PROMPT" | grep -cE 'services/(core|bot)/|packages/(shared|[a-z])')
frontend=$(echo "$PROMPT" | grep -cE 'services/ui/')

# If backend dispatched but prompt mentions frontend paths → block
if [ "$frontend" -gt 0 ] && echo "$AGENT" | grep -qE '^nestjs-'; then
  emit_block "CROSS-DOMAIN BLOCKED"
fi
```

This is **heuristic**: it parses prose to infer intent. Problems:

- **Brittle** — prompts that mention paths metaphorically or in examples trigger false positives
- **Over-restrictive** — a prompt that mentions UI for context but only edits backend is blocked
- **Under-restrictive** — a prompt that doesn't mention paths but the agent later operates on the wrong path is allowed
- **Couples to language** — keyword regex is English-centric; multilingual projects need multi-regex

## Decision

**Move dispatch validation from Agent-dispatch hook to Edit/Write hook**.

At Agent dispatch time: no validation. The orchestrator is trusted to consult `routing-table.json` when choosing the agent. Marker is registered.

At Edit/Write time: validation is **deterministic**.

```
1. Hook receives Edit/Write call with concrete file_path
2. Hook reads marker → who is dispatching this Edit (agent_type)
3. Hook reads routing-table → which agent owns this path (expected_agent)
4. If agent_type != expected_agent → block
5. Otherwise → allow
```

No prompt parsing. No grep heuristics. Only file_path comparison against routing-table — a deterministic boolean check.

## Rationale

| Principle | How this satisfies |
|---|---|
| Determinism | File path is concrete; routing-table answer is unambiguous |
| OCP | Adding a new domain doesn't require teaching the hook new keyword patterns; the routing-table is the source |
| Reduced coupling | Validation depends on routing contract, not on how the orchestrator phrases prompts |
| Multilingual | No regex over prose; validation is path-based, language-agnostic |

## Consequences

### Trade-off: late blocking

A misdispatched agent (e.g. `backend-implementer` dispatched for a frontend path) runs successfully **until it tries to write**. The agent has done thinking work that gets rejected at the write boundary. This wastes some agent compute and produces a less-targeted error message ("you tried to write a path you don't own") instead of a dispatch-time error ("you shouldn't have been dispatched for this").

**Mitigation:**
- Read-only agents (Explore, general-purpose for spec review, reviewers) are not affected — they don't write
- `viv-orchestration-rules` documents the IRON LAW: orchestrator MUST consult routing-table before dispatch. Following the rule means writes succeed.
- Late blocking is a fail-safe, not the primary signal. The primary signal is the orchestrator's correctness.

### Cross-domain dispatches in the prompt

The `pretooluse-agent.sh` viblocks hook also handles "general-purpose dispatched for Class A path" (block general-purpose from writing to enforced paths). This case is **also handled at Edit/Write time** in the redesign — if `general-purpose` is the dispatcher and Edit targets a path with `enforced: true`, the hook blocks.

## Alternatives considered

- **Keep prompt-grep validation:** rejected — heuristic; fails on edge cases; multilingual brittleness
- **Validate at Agent dispatch using path metadata in prompt:** rejected — requires structured metadata in prompt; Claude Code's API doesn't enforce structure
- **Hybrid: dispatch-time fast check + Edit/Write authoritative check:** rejected — duplicates logic; doubles maintenance; the dispatch-time check has all the heuristic problems we want to eliminate

## Related

- ADR-RD-002 (marker registry — required by this decision; without marker, Edit/Write hook can't know agent_type)
- ADR-RD-003 (single routing-table — the source of truth this decision relies on)
- ADR-RD-006 (hook types — the routing-validation hook is type `deny`)
