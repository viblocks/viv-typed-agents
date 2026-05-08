# ADR-RD-001 — All hooks are external files; settings.json is glue only

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-hooks)

## Context

viblocks-ai's `.claude/settings.json` contains **5 hooks inline** (semantic-token gate, evidence gate, debugging gate, post-implementation advisory, blacklist-domain detector). Each hook is a multi-line shell command embedded directly in the JSON.

This violates SRP at the file level: `settings.json` mixes:
- Permissions configuration (allow/deny lists)
- Hook registration (matchers and command references)
- Hook implementation (multi-line bash logic)

It also violates ISP: the consumer reading `settings.json` to understand permissions cannot avoid loading the hook implementations.

## Decision

All enforcement hooks are **external files** in `viv-hooks/hooks/`. Each hook has Single Responsibility — one file, one concern. `settings.json` is a **glue file** that registers hooks by file reference only.

```json
"PreToolUse": [{
  "matcher": "Edit|Write",
  "hooks": [{
    "type": "command",
    "command": "bash ./.claude/hooks/enforce-routing.sh"
  }]
}]
```

No multi-line bash inside the JSON. No grep/awk/sed inside the JSON. Only file references.

## Rationale

| Principle | How this satisfies |
|---|---|
| SRP | Each hook file has one responsibility; `settings.json` has one responsibility (registration) |
| OCP | Adding a new hook means adding a new file plus a JSON entry — no modification of existing hooks |
| ISP | `settings.json` consumers (permissions reviewers) read only the configuration without inheriting hook code |
| Maintainability | Diffs on hook logic are visible in real shell files, not buried in escaped JSON strings |
| Testability | Each hook can be unit-tested independently (bash test runner per file) |

## Consequences

- viblocks-ai migration must extract its 5 inline hooks into separate files in `viv-hooks/hooks/`
- The `settings.json` template provided by `viv-hooks` is short and readable
- Some hooks that today contain viblocks-specific patterns (e.g. semantic-token gate hardcodes `services/ui/src/index.css`) become parameterized via `viv-workflows` rule data

## Alternatives considered

- **Status quo (inline hooks):** rejected — SRP violation; hooks become invisible to file-based tooling
- **Single mega-hook file with case statement:** rejected — defers SRP violation from JSON to bash; same problem
- **Hooks as binary executables (Go/Rust):** rejected — overengineering; bash is sufficient and matches Claude Code conventions
