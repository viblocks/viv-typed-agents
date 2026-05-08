# ADR-RD-005 — Workflow gate rules as data; hooks consume the data

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-workflows and viv-hooks)

## Context

viblocks-ai implements three workflow-level gates as **bash logic embedded in hooks**:

1. **Issue-close evidence gate** (inline in settings.json): blocks `gh issue close` unless the comment includes 4 specific markdown headers (`**Verification**`, `**Code review**`, `**Security review**`, `**Commits**`)
2. **Fix-intent gate** (inline in settings.json): blocks `Agent` dispatch when prompt contains fix-related keywords without `Root cause:` or `Causa raíz:`
3. **Audit-trail trailer gate** (`pretooluse-bash-commit.sh`): blocks `git commit` of Class A files unless message contains `Audit-Trail: VI-XXX` or `Audit-Trail: adhoc-NNN`

In each case, the **rule** (what must be true) and the **enforcement** (how to block when rule is violated) are fused. Changing the evidence gate fields requires editing `settings.json`'s shell command. Changing the audit-trail format requires editing bash regex.

This violates SRP. The rule is workflow concern; the enforcement is hook concern.

## Decision

**Workflow rules live in `viv-workflows` as declarative data.** Hooks in `viv-hooks` are **rule consumers** that read the data and apply enforcement.

```
viv-workflows/
├── post-implementation-chain.json
├── evidence-schema.json
├── fix-intent-pattern.json
├── implementer-reviewer-pairings.json
└── audit-trail-pattern.json
```

Examples:

```json
// evidence-schema.json
{
  "trigger": "gh issue close",
  "required_fields": [
    { "marker": "**Verification**", "format": "PASS|FAIL — N/N tests" },
    { "marker": "**Code review**", "format": "agent — PASS|N issues" },
    { "marker": "**Security review**", "format": "PASS|FAIL|N/A — reason" },
    { "marker": "**Commits**", "format": "list of commit SHAs" }
  ]
}
```

```json
// audit-trail-pattern.json
{
  "trigger": "git commit",
  "applies_to": "class_a",
  "required_trailer": {
    "name": "Audit-Trail",
    "value_pattern": "<consumer-defined-regex>",
    "examples": ["VI-XXX", "adhoc-<id>"]
  }
}
```

Hooks read these files and enforce their rules. Changing a rule = editing the JSON. Hook code never changes.

## Rationale

| Principle | How this satisfies |
|---|---|
| SRP | Workflow rule = data (changes when policy changes); enforcement = hook code (changes when mechanism changes) |
| OCP | Adding a new gate rule = adding a new JSON file in viv-workflows + a hook that consumes it; existing rules untouched |
| DIP | Hooks depend on workflow rule contracts (JSON schemas), not on hardcoded regex |
| Reviewability | Policy changes show up as JSON diffs; reviewable by non-engineers (PMs, security) |

## Consequences

- `viv-workflows` is a new data-only repo with rule schemas + per-rule JSON files
- `viv-hooks` ships consumer hooks that load rules from a configurable location (default: `.claude/workflows/`)
- viblocks-ai migration: extract the 3 inline rules into `viv-workflows`, refactor hooks to consume them

## Alternatives considered

- **Keep rules in hooks; just generalize via env vars:** rejected — env var injection is brittle for complex rules (e.g. multi-field schema); doesn't solve reviewability
- **Single big rules.yaml file:** rejected — couples unrelated rules into one file; small focused files have better SRP
- **Rules as bash scripts viv-workflows ships:** rejected — defeats the point; rules should be data, not code

## Related

- ADR-RD-001 (no inline hooks — same theme; data-vs-code separation)
- ADR-RD-006 (hook types explicit — works with this; gate-evaluation hooks are typed)
