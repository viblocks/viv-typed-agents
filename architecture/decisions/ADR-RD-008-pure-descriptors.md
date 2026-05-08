# ADR-RD-008 — Pure descriptor pattern: only viv-hooks contains executable code

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (system-wide)

## Context

`viv-skills` and `viv-agents` established a pattern: **declarative repos contain only data**. No executable code, no scripts, no build steps. The repos are vendored by direct file copy. The pattern is:

- Easy to vendor (cp -r)
- Easy to audit (read the files)
- Easy to validate (JSON schema, frontmatter validation)
- No language coupling (consumer reads in any language)

`viv-routing`, `viv-workflows`, `viv-orchestration-rules` (the three remaining declarative components) should preserve this pattern.

`viv-hooks` is necessarily different — it ships executable bash + Python because hooks ARE code by definition. But it's the **only** code repo in the system.

## Decision

**Pure descriptor pattern is enforced for declarative repos**:

| Repo | Contains | Does NOT contain |
|---|---|---|
| viv-skills | `.md` files | Scripts, builders, validators |
| viv-agents | `.md` files with frontmatter | Scripts, validators |
| viv-routing | `.json` + JSON schemas | Query libraries, classifiers |
| viv-workflows | `.json` rule files + schemas | Rule evaluators |
| viv-orchestration-rules | `.md` template + playbook docs | Generators, validators |

**Executable code lives in `viv-hooks` only**:

| Repo | Contains |
|---|---|
| viv-hooks | bash hooks, Python helpers, lib code, tests |

If consumers want CI tools (validators, schema checkers, query libraries) they implement them themselves or use a separate tool repo (not part of this strategy).

## Rationale

| Principle | How this satisfies |
|---|---|
| SRP | Each repo's reason to change is its content domain, not language tooling |
| Vendoring simplicity | Declarative repos are `cp -r` — no installation, no version management |
| Language independence | Declarative content readable from any consumer language |
| Validation independence | Schemas can be validated by any JSON Schema validator; no specific tool required |

## Consequences

- A consumer that wants a CLI tool to query the routing-table writes one themselves (it's a JSON file)
- `viv-routing` does NOT ship a `query.sh` or `classify.py` library — those would be code-in-data-repo
- `viv-hooks` consumes the routing-table directly via shell + jq + Python; that's hook code, lives in the code repo

### What about glob matching for routing?

Path glob matching (e.g. `services/**/foo`) requires a non-trivial implementation. viblocks-ai uses `scripts/query-classifier.sh` (Python). In the redesigned system:

- `viv-hooks` contains the matcher implementation (it's hook code, lives in viv-hooks/lib/)
- A consumer that wants to query routing outside hooks (e.g. in a CI step) writes their own matcher OR uses the one in `viv-hooks/lib/` directly
- `viv-routing` ships only the data + schema; matching is downstream concern

## Alternatives considered

- **Each declarative repo ships a query CLI:** rejected — code-in-data-repo violates the pattern; languages couple consumer
- **Single tools repo (`viv-tools`):** rejected — premature; first need to see if consumers need shared tooling
- **Hooks repo absorbs all "active" components (routing+workflows+hooks):** rejected — couples data to enforcement; consumers wanting only data forced to vendor enforcement code

## Related

- ADR-RD-001 (no inline hooks — same theme)
- ADR-RD-005 (workflow gates as data — same theme)
- viv-skills ADR-002 (vendoring pattern established)
