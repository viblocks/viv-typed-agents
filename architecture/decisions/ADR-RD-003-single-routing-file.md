# ADR-RD-003 — Single routing-table.json with field-level SRP

**Status:** Accepted
**Date:** 2026-05-08
**Category:** Cross-component (affects viv-routing)

## Context

The initial redesign proposal suggested **segregating routing into three separate files**:
- `path-to-domain.json` (classification)
- `domain-to-implementer.json` (implementer assignment)
- `domain-to-reviewer.json` (reviewer assignment)

The argument was SRP at the file level: each mapping has its own reason to change.

On deeper analysis, this was **overengineering**. The reasons-to-change overlap heavily — adding a new domain typically touches all three files at once. Splitting creates operational friction without delivering a real SRP benefit.

## Decision

Keep **one file** (`routing-table.json`) with explicit, nullable fields. Apply SRP at the **field level**, not the file level.

```json
{
  "routes": [
    {
      "domain": "backend",
      "paths": ["<backend-services>/**", "<shared-packages>/**"],
      "enforced": true,
      "implementer": "backend-crypto-implementer",
      "reviewer": "backend-crypto-reviewer",
      "note": "optional human-readable rationale"
    },
    {
      "domain": "testing",
      "paths": ["**/*.spec.ts", "**/*.test.ts"],
      "enforced": false,
      "implementer": null,
      "reviewer": "dev-testing-strategy-reviewer"
    }
  ]
}
```

Field rules:
- `domain` and `paths` are required
- `enforced` is required (defaults to `true` if omitted, but should be explicit)
- `implementer` and `reviewer` are nullable independently (one can be null without the other)
- `note` is optional, human-readable, ignored by tooling

## Rationale

| Principle | How this satisfies |
|---|---|
| SRP | Each field has one purpose. Changing `reviewer` of a domain is one diff line, doesn't touch other fields |
| OCP | New optional fields can be added (e.g. `priority`, `tags`) without breaking existing consumers |
| ISP | Consumers read only the fields they need: routing validators read `paths` + `enforced`; pairing logic reads `domain` + `implementer` + `reviewer`; documentation tools read `note` |
| Operational simplicity | One file, one schema, one validator. New domain = one entry edit |

## Consequences

- `viv-routing` ships a single `routing-table.json` template plus a JSON schema
- Tooling that consumes routing operates against this single file
- The `note` field is the only place that allows prose; tooling MUST ignore it

## Alternatives considered

- **Three separate files (initial proposal):** rejected — operational coupling exceeds SRP benefit; adding a domain = 3 file edits
- **Per-domain files:** rejected — explosion of files; harder to validate global invariants (e.g. no path covered by two routes)
- **Embedded domain definitions inside agent frontmatter:** rejected — couples agent identity to project-specific paths; ADR-RD-008 forbids this

## Related

- ADR-RD-004 (classifier folded into routing via `enforced` field)
- ADR-RD-007 (validation deferred to Edit/Write time using this file as ground truth)
