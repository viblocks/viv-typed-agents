# ADR-RD-002 — Marker registry retained as necessary tech debt; redesigned with SRP

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-hooks)

## Context

viblocks-ai uses a **marker registry** (`.claude/.subagent-active.json`) to track active subagent dispatches. Hooks read it to determine "is this Edit/Write coming from main session or from a subagent?". The marker has TTL, flock-based atomic writes, and a JSON schema with several fields per active subagent.

The marker exists because **Claude Code's hook payload does not include role context**. At Edit/Write/Bash time, the hook receives `cwd`, `tool_input`, and `tool_use_id` — but not "is this main session or a dispatched subagent". Only the Agent dispatch hook sees `subagent_type`. To bridge this information across hook boundaries, viblocks added the marker.

The initial redesign proposal asked: *can we eliminate the marker?* Investigation showed: **no**, the API constraint is real. The marker is **necessary tech debt** until Claude Code provides role context natively.

## Decision

Retain the marker registry. Redesign it with SRP at the schema level:

```json
{
  "subagents": [{
    "id": "<stable-id>",
    "agent_type": "<typed-agent-name>",
    "scope": "<absolute-path>",
    "dispatched_at": "<ISO-8601-UTC>",
    "ttl_seconds": 1800,
    "allow_self_mod": true|false
  }]
}
```

Each field has one purpose:
- `id` — identity (uniquely identifies a dispatch instance)
- `agent_type` — role (which typed agent is acting)
- `scope` — boundary (which path tree the subagent operates within)
- `dispatched_at` + `ttl_seconds` — lifecycle (when the entry expires)
- `allow_self_mod` — permission (whether this subagent may modify enforcement layer)

No field carries multiple responsibilities. No field embeds project-specific knowledge (e.g. no hardcoded agent names — `agent_type` is a string referencing whatever the consumer's `viv-agents` declares).

## Rationale

| Principle | How this satisfies |
|---|---|
| SRP | Each marker field has one purpose; the marker as a whole has one purpose (cross-hook role context) |
| OCP | Adding new permission fields (e.g. `allow_network`) doesn't break existing consumers |
| ISP | Consumers read only the field they need (`scope` for isolation, `agent_type` for routing validation, `allow_self_mod` for self-mod gate) |
| DIP | Hooks consume the marker schema (a contract), not a specific implementation. The marker library can be replaced without touching hooks |

## Consequences

- The marker library (`marker-registry.sh` + `role-detection.sh`) is part of `viv-hooks/lib/`
- The marker schema is documented in `viv-hooks/SCHEMA.md`
- TTL and locking are policies — owned by `viv-hooks`, not contracts that consumers depend on
- If Claude Code adds native role context in the future, the marker can be deprecated; consumers depending on the schema would migrate

## Alternatives considered

- **Eliminate marker; use cwd-based heuristic:** rejected — exact bug viblocks fixed (PR #358); main-session-in-worktree was misclassified as subagent
- **Eliminate marker; use process tree introspection:** rejected — fragile across OSes; hook execution model doesn't guarantee process ancestry preservation
- **Eliminate marker; require orchestrator to pass role in tool_input:** rejected — Claude Code doesn't allow arbitrary fields in `tool_input`
- **Split marker into two files (lifecycle vs. permissions):** rejected — operational coupling is real; both fields written/read in the same hook calls; SRP at field level is sufficient
