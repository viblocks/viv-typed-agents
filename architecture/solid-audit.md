# SOLID Audit — viblocks-ai's Current Implementation

This document is the audit that justifies the redesign decisions in this repo's ADRs. Each violation is paired with the ADR that addresses it.

The audit is honest about viblocks' implementation: it works, it solves real problems, and it evolved organically. The SOLID violations are the cost of organic growth, not signs of bad work. The redesign is the consolidation step that organic systems don't get for free.

## Methodology

For each SOLID principle, identify violations in viblocks-ai's `.claude/` setup. For each violation, classify:

- **Severity** — does it cause real bugs or just architectural debt?
- **Fix in redesign** — which ADR addresses it
- **Cost of inheriting** — what does a consumer pay if we extract without fixing?

---

## Single Responsibility (SRP)

### Violation S1 — `enforce-routing.sh` has 6 responsibilities

The hook does:
1. Role detection (main vs subagent via marker walk-up)
2. Path classification (Class A pattern matching against hardcoded array)
3. Bash command parsing (extract write targets)
4. Interpreter-as-editor detection (INFRA-H1: python -c, node -e, etc.)
5. Shell-substitution failover (SEC-M3: $, backtick, ~ in commands)
6. Block-message emission with consumer hints

**Severity:** High. Changing any one of these requires reading and reasoning about all six. Test coverage is correspondingly hard to maintain.

**Fix in redesign:** ADR-RD-001 (split into multiple files), ADR-RD-007 (move dispatch validation to Edit/Write hook). The redesigned hooks separate concerns: routing validation, path classification, bash parsing each become independent units in viv-hooks.

### Violation S2 — `pretooluse-agent.sh` mixes validation and lifecycle

The hook does:
1. Cross-domain validation (block nestjs agent for services/ui)
2. General-purpose-in-Class-A validation
3. Marker registration (lifecycle side effect)

**Severity:** Medium. The two concerns are coupled: if dispatch fails validation, marker is not registered (correct). But the file mixes "validate" with "side-effect on success" without explicit phase separation.

**Fix in redesign:** ADR-RD-006 (hook types). Validation lives in `deny/` hooks; marker registration is `lifecycle/`. The two are different file types with different responsibilities.

### Violation S3 — `routing-table.json` mixes 3 mappings

A route entry has:
- `paths` → `domain` (classification)
- `domain` → `implementer` (implementer assignment)
- `domain` → `reviewer` (reviewer assignment)
- `note` (human-readable rationale)

Changing the reviewer of a domain touches an entry that also defines the implementer. Conceptually distinct mappings share a row.

**Severity:** Low (was an early candidate for splitting into 3 files but rejected — see ADR-RD-003). Operational reality is that the mappings change together.

**Fix in redesign:** ADR-RD-003 — keep one file but apply SRP at field level (each field is independently nullable; consumers ISP-segment by reading only what they need).

### Violation S4 — `artifact-classifier.json` mixes inclusion and exclusion

The file has `class_a_patterns` (inclusion list) and `class_b_exclusions` (exclusion list). The exclusions exist as an afterthought — services/**/README.md is technically under services/** but should be Class B.

**Severity:** Medium. The two lists change for different reasons (adding a new domain vs. discovering an exclusion).

**Fix in redesign:** ADR-RD-004. Eliminate `artifact-classifier.json` entirely. Fold classification into routing via `enforced` field. Exclusions handled by route specificity (longest path match wins).

### Violation S5 — `settings.json` contains 5 inline hooks

The file mixes:
- Permissions configuration (allow/deny)
- Hook registration (matchers + commands)
- Hook implementation (multi-line bash)

**Severity:** High. Hook implementations buried in JSON strings are unreviewable. Diffs are unreadable.

**Fix in redesign:** ADR-RD-001. All hooks become external files; settings.json is glue only.

---

## Open/Closed (OCP)

### Violation O1 — Adding a new domain requires editing 4 files

To add a new typed-agent domain (e.g. `mobile-implementer`):
1. Edit `routing-table.json` (add route entry)
2. Edit `artifact-classifier.json` (add Class A pattern)
3. Edit `enforce-routing.sh` (add to `CLASS_A_PATTERNS` array — duplicates classifier)
4. Edit `settings.json` (add to allow-list of inline hooks)

The system is **not closed** for modification when extending.

**Severity:** High. Inherent friction against adding domains; promotes hardcoding choices instead of declarative extension.

**Fix in redesign:** ADR-RD-004 (eliminate classifier — only routing-table needs editing) + ADR-RD-001 (no inline hooks). Adding a domain = edit `routing-table.json`. That's it.

### Violation O2 — `CLASS_A_PATTERNS` duplicated in `enforce-routing.sh`

The bash array hardcodes the patterns from `artifact-classifier.json`. Why? Because bash can't easily parse JSON, and parsing in every hook call would be slow.

**Severity:** Medium. Performance optimization that creates an explicit duplication invariant ("keep these in sync manually").

**Fix in redesign:** ADR-RD-004 (single source) + ADR-RD-008 (viv-hooks handles its own caching internally). The hook reads routing-table once at startup and caches; no duplication required.

### Violation O3 — Inline hooks hardcode agent names

The L3 advisory hook in settings.json contains:
```bash
if [ "$s" = 'nestjs-crypto-implementer' ]; then ...
elif [ "$s" = 'reactjs-crypto-implementer' ]; then ...
```

Renaming an agent (which we did during the viv-agents redesign — `nestjs-*` → `backend-*`) requires editing this hook. Not closed.

**Severity:** High. Couples inline hook to specific agent names; agent renames break the hook silently.

**Fix in redesign:** ADR-RD-005 (gate rules as data) + ADR-RD-001 (extract to file). The advisory reads agent-to-chain mapping from `viv-workflows`, not hardcoded.

---

## Liskov Substitution (LSP)

### Violation L1 — Marker schema embeds agent_type as opaque string

The marker has `agent_type: "nestjs-crypto-implementer"`. Hooks downstream may compare against literal strings:

```bash
if [ "$agent_type" = "nestjs-crypto-implementer" ]; then ...
```

If we substitute `nestjs-crypto-implementer` with `backend-crypto-implementer` (the redesigned name), every downstream comparison breaks.

**Severity:** Medium. Mostly affects naming migrations; tests would catch most cases.

**Fix in redesign:** ADR-RD-002 (marker redesigned) + ADR-RD-007 (Edit/Write hook reads agent_type and routing-table; comparison is structural — agent_type matches a route's `implementer` or `reviewer` field). No literal string comparisons in hook code.

### Violation L2 — L3 advisory hook hardcodes which agents trigger which chains

The L3 hook says:
- nestjs-crypto-implementer complete → run "verification + nestjs-crypto-reviewer + security-reviewer"
- reactjs-crypto-implementer complete → run "verification + reactjs-crypto-reviewer + security-reviewer"

This couples two unrelated naming choices. Rename either agent, the hook breaks.

**Severity:** Medium.

**Fix in redesign:** ADR-RD-005. The chain mapping lives in `viv-workflows/implementer-reviewer-pairings.json`. Hook reads pairings; substitute either agent → update pairings JSON, hook unchanged.

---

## Interface Segregation (ISP)

### Violation I1 — `routing-table.json` consumers forced to read all fields

A consumer that only needs "is this path enforced?" must parse a structure with `domain`, `paths`, `implementer`, `reviewer`, and `note`. The consumer pays cognitive load for fields it ignores.

**Severity:** Low. Easy to ignore in code, but JSON parsers don't segment.

**Fix in redesign:** ADR-RD-003. Document field-level SRP; tooling that exposes routing as a queryable service can offer filtered views (consumer asks "give me classification only").

### Violation I2 — Marker exposes 6 fields to all consumers

The marker has `id`, `agent_type`, `dispatched_at`, `ttl_seconds`, `allow_self_mod`, `scope`. Different hooks need different subsets:

- `enforce-routing.sh` needs `agent_type` and `scope`
- `enforce-self-mod.sh` needs `allow_self_mod`
- `enforce-isolation.sh` needs `scope`
- `lifecycle hooks` need `id` and `ttl_seconds`

Each hook reads the full marker and ignores fields. Not segregated.

**Severity:** Low. Performance-irrelevant; cognitive load only.

**Fix in redesign:** ADR-RD-002. The marker schema is documented per-field; the marker library exposes per-field accessors (`get_marker_scope()`, `get_marker_agent_type()`, etc.). Hooks read only what they need.

### Violation I3 — `settings.json` consumers can't separate config from hook implementation

A consumer reading `settings.json` to understand permissions cannot avoid loading the hook implementations. The 5 inline hooks force the reader through bash logic to find the structure.

**Severity:** High for reviewability. Mid for maintainability.

**Fix in redesign:** ADR-RD-001. settings.json shrinks to ~50 lines of pure declarative configuration; hook code is in separate files.

---

## Dependency Inversion (DIP)

### Violation D1 — `enforce-routing.sh` depends on hardcoded patterns, not classifier abstraction

The hook hardcodes `CLASS_A_PATTERNS` array. Conceptually it should depend on the **classification contract** (an abstraction: "given a path, is it class A?") and not the **implementation** (a specific list of patterns).

**Severity:** High. Same logical content lives in two places.

**Fix in redesign:** ADR-RD-004 + ADR-RD-008. The hook depends on `viv-routing/routing-table.json` (the contract: "every route entry with `enforced=true` is class A"). No duplication.

### Violation D2 — Hooks consume routing-table.json via direct grep

Several hooks (and `pretooluse-agent.sh` cross-domain check) parse routing-table by `grep`. This is implementation-coupled — any change to file format breaks every grep.

**Severity:** High. Schema migrations propagate to N hook files.

**Fix in redesign:** ADR-RD-008 says viv-hooks's lib provides the routing query function. Hook code calls `lib/route_for_path "$file"` instead of grepping. The contract is the function signature; the implementation can change.

### Violation D3 — Marker schema knowledge embedded in hook code

Hook scripts know the marker JSON structure: which keys to read, what type each value is, etc. If the marker schema evolves (e.g. add `network_allowed` field), every hook may be affected even if it doesn't use the new field.

**Severity:** Medium. JSON parsing is forgiving (unknown keys ignored), but the "knowledge" of the schema is scattered.

**Fix in redesign:** ADR-RD-002. The marker library exposes typed accessors. Hooks call accessors. Schema evolution affects only the library.

---

## Cross-cutting concerns surfaced by the audit

### CC1 — Mode policy is asymmetric and undocumented per-hook

`AIDLC_ENFORCEMENT_MODE` has 3 values (disabled, warn, hard). Some hooks honor `warn` (advisory ones), some don't (deny ones). The asymmetry is intentional but lives in implicit convention.

**Fix:** ADR-RD-006 — three explicit hook types make policy honoring per-type explicit.

### CC2 — Validation timing is heuristic

`pretooluse-agent.sh` validates dispatch by grep'ing the prompt — heuristic. Other points (Edit/Write) have concrete information (file_path) but defer validation.

**Fix:** ADR-RD-007 — defer all dispatch validation to Edit/Write time.

### CC3 — Layer model evolved organically

The doc references "Capa 1-8" but only 4 of those layers map to current hooks (Layer 1 deny + fast-lane refinement; Layer 2 Agent gate + post-impl; Layer 4 commit gate; Layer 7/8 consolidated into enforce-routing+isolation). The naming is historical and doesn't match the current implementation.

**Fix:** SPEC §3.2 — replace "Capa 1-8" with 4 hook types (deny / advisory / refinement / lifecycle) that match the actual implementation.

---

## Summary

| Severity | Count | Examples |
|---|---|---|
| High | 7 | god-object hook, inline hooks, hardcoded agent names, duplicated classifier, settings.json mixing concerns |
| Medium | 5 | mixed validation/lifecycle, mixed inclusion/exclusion, marker schema spread, marker fields exposed |
| Low | 3 | route-table field bundling, ISP minor cases |

The redesign addresses every High and most Medium violations. Lows are accepted as "fix only if discovered to cause real friction".

## Cost of inheriting without fixing

Without the redesign, a consumer adopting viblocks' typed-agents implementation inherits:

- Friction of editing 4 files to add a domain
- Inability to rename agents without editing inline hook strings
- Multi-responsibility hooks that are hard to test
- Documentation drift (Capa 1-8 vs. actual hooks)
- Hidden mode-policy asymmetry
- Heuristic dispatch validation that fails on edge cases

The redesign eliminates all of these. The cost is the redesign work itself, which this SPEC and the per-component repos document.

## Acknowledgment

viblocks-ai's implementation works in production and solves the dispatch quality problem that motivated it. This audit is not a critique of the team's choices — it's a necessary step to extract a reusable strategy from organic implementation. Every system that grows organically accumulates similar debt; the consolidation step is what produces a clean reusable strategy.
