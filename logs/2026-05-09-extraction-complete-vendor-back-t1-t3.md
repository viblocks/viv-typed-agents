---
title: Typed-agents strategy — 6 repos extracted, smoke validated, vendor-back T1-T3
tags: [session-log, viv-typed-agents, viv-routing, viv-workflows, viv-orchestration-rules, viv-hooks, viblocks-ai]
created: 2026-05-09
updated: 2026-05-09
status: complete
type: log
---

# Session summary

Continuation of the SOLID redesign of the typed-agents strategy (started in [[2026-05-08-typed-agents-redesign]] context). This session: completed extraction of remaining 4 components, smoke-validated end-to-end, started vendor-back to viblocks-ai (T1-T3 of 7).

## What was done

### Phase A — Component extraction (4 of 4 remaining repos)

- Extracted [[viv-routing]] — single-file routing per ADR-RD-003, classifier folded per ADR-RD-004. 13 files, 3 local ADRs, schema validation via ajv. Repo: https://github.com/viblocks/viv-routing
- Post-extraction chain caught 2 regressions: test fixtures and safe env files would have regressed to Class A. Fixed in commit `f6a3e63` with explicit override routes.
- Extracted [[viv-workflows]] — 5 declarative gate rules (post-impl chain, evidence schema, fix-intent pattern, audit-trail pattern, implementer-reviewer pairings). 23 files in repo. Pre-push chain found 0 issues. Repo: https://github.com/viblocks/viv-workflows
- Extracted [[viv-orchestration-rules]] — 5 behavioral playbooks + CLAUDE.md template + viblocks-style example + 3 local ADRs. 13 files. Repo: https://github.com/viblocks/viv-orchestration-rules
- SPEC alignment review found 4 findings: tier mapping inconsistency (MED), hardcoded agent names violating Apéndice B invariant 7 (LOW), missing receiving-code-review skill (LOW), hook taxonomy not introduced (LOW). All fixed in commit `87eafba`.
- Extracted [[viv-hooks]] — Tier 4 structural enforcement, the only repo with executable code per ADR-RD-008. 27 files including 12 hooks (4 deny / 4 advisory / 1 refinement / 2 lifecycle / 1 commit), 6 lib helpers (2 NEW: routing-loader, workflow-loader), 4 ADRs, smoke test. 31/31 syntax+disabled-mode tests pass. Repo: https://github.com/viblocks/viv-hooks

### Phase B — Smoke validation at /tmp/vendor-smoke/

- Created throwaway project mimicking viblocks layout (services/api, packages/shared, scripts/)
- Vendored all 6 repos into `/tmp/vendor-smoke/.claude/`
- Ran 22 smoke tests covering loaders, deny hooks, advisory hooks, lifecycle, marker isolation
- 22/22 PASS — system works as a whole
- Two minor findings: marker-register requires git repo (documented in README), block message had viblocks-residual text (fixed in commit `99c56f8`)

### Phase C — Re-vendor to viblocks-ai (T1-T3 of 7)

- Created Linear issue [VI-234](https://linear.app/vi-blocks/issue/VI-234/re-vendor-solid-redesigned-typed-agents-components-into-viblocks-ai)
- Per project Issue-Driven flow: CROSS-DOMAIN supervised path
- T1 vendor `.claude/routing/` → commit `b107922` (3 files, ajv-validated)
  - Reviewer found 1 LOW (L01): `$schema` ref pointed at upstream-repo layout
  - Fixed in commit `ba0f88d`
- T2 vendor `.claude/workflows/` (10 files) + T3 vendor `.claude/orchestration/playbooks/` (5 files) dispatched in parallel
  - Race condition on shared `.gitignore` edit → both tasks merged into commit `684a105`
  - Both implementers correctly refused destructive history rewrite
- 3 commits pushed to `origin/claude/amazing-raman-51ede3`

## Decisions

- **Save the strategy as redesign, not extraction** — preserves viblocks objectives but rebuilds architecture on SOLID principles. See [[ADR-RD-009-preserve-objectives]].
- **5-tier composition model with viv-orchestration-rules as T5** — adopting OR is the T5 step; playbooks describe behavior at that tier. Documented in [[viv-typed-agents/composition/tiers]].
- **Pre-push Post-Extraction Chain** — apply chain BEFORE push, not after. Discovered after viv-routing required a follow-up commit; viv-workflows and subsequent extractions ran clean in single commits because of this discipline.
- **Smoke validate D before re-vendor B** — a throwaway sandbox validates the system holistically before touching the brownfield project. 22/22 pass gave confidence to start re-vendor. See [[vendor-smoke-22-tests-pass]].
- **Sequential dispatch for tasks sharing config files** — parallel T2+T3 produced a race condition on `.gitignore`. Lesson: tasks touching the same shared meta-config must run sequentially. Documented in this log under "Pending" for next session.
- **Implementers refuse destructive history rewrite by default** — both T2 and T3 implementers, when discovering they had inadvertently been swept into one commit, escalated rather than amend. Correct per project rules.

## Pending

### T4-T7 of vendor-back (next session)

| Task | Scope | Notes |
|---|---|---|
| T4 | Replace root `CLAUDE.md` from `viv-orchestration-rules/CLAUDE.template.md`; preserve 6 viblocks-specific sections (Worktree Bootstrap, Worktree Hygiene, SOLID rule, Deploy↔App rule, Issue-Driven Flow, docs/Notion exception, AI-DLC adaptive workflow) | ALTO — current CLAUDE.md is ~600 lines; needs careful section-by-section migration |
| T5 | Vendor `.claude/hooks/` SRP-reorg + `.claude/lib/`; replace inline rules in `settings.json` with hook entries | ALTO — 12 hooks dismount, 12 mount, settings.json delicate |
| T6 | Delete `.claude/context/artifact-classifier.json` and `scripts/query-classifier.sh` (replaced by routing-loader) | BAJO — mechanical deletion |
| T7 | Smoke E2E in viblocks-ai: dispatch real implementer, run full chain, verify Audit-Trail commit | MEDIO — depends on T5 working |

### Next-session checklist

- [ ] Branch already exists: `claude/amazing-raman-51ede3` pushed to origin
- [ ] Sources staged in `.vendor-stage/{viv-routing,viv-workflows,viv-orchestration-rules}/` (gitignored, persists across sessions)
- [ ] Need to also stage `viv-hooks` sources for T5: `cp -r /Users/viv/AI/vault/viv-hooks/{hooks,lib,settings.json.fragment} .vendor-stage/viv-hooks/`
- [ ] Dispatch T4-T7 sequentially (not parallel) to avoid `.gitignore` and `settings.json` race conditions
- [ ] Use `git commit -F-` HEREDOC always; avoid `-m "..."` with `$` or backticks (SEC-M3 fail-closed)
- [ ] After T7 smoke pass: open PR with VI-234 in title

### Open questions

- Should `.vendor-stage/` be promoted to a long-lived staging convention (e.g. `.claude-vendor-staging/`) or removed after the re-vendor completes? Currently gitignored.
- Does viblocks-ai's existing `__tests__/*.bats` test suite need updates after T5? Hooks paths change from `.claude/hooks/*.sh` flat layout to `.claude/hooks/<type>/*.sh` nested layout — fixture path strings will break.

## Files touched

### Vault repos (extracted + pushed)

- [[viv-routing]] — https://github.com/viblocks/viv-routing — commits `843e954`, `f6a3e63`
- [[viv-workflows]] — https://github.com/viblocks/viv-workflows — commit `281842d`
- [[viv-orchestration-rules]] — https://github.com/viblocks/viv-orchestration-rules — commits `45a87a1`, `87eafba`
- [[viv-hooks]] — https://github.com/viblocks/viv-hooks — commits `72c9f62`, `99c56f8`
- [[viv-typed-agents]] migration plan updated (uncommitted local edits at `/Users/viv/AI/vault/viv-typed-agents/migration/from-viblocks.md`)

### viblocks-ai worktree (vendor-back T1-T3)

- `.claude/routing/routing-table.json` (b107922 + ba0f88d L01 fix)
- `.claude/routing/routing-table.schema.json`
- `.claude/routing/NAMING.md`
- `.claude/workflows/{audit-trail-pattern,evidence-schema,fix-intent-pattern,implementer-reviewer-pairings,post-implementation-chain}.json` (684a105)
- `.claude/workflows/schemas/*.schema.json` (5 files)
- `.claude/orchestration/playbooks/{ai-dlc-integration,dispatch-protocol,issue-driven-flow,post-implementation-chain,superpowers-integration}.md` (684a105)
- `.gitignore` (+3 allowlist entries)
- `.vendor-stage/` (gitignored sources for T4-T7)

### Smoke test artifact

- `/tmp/vendor-smoke/` — 22-test sandbox, can be discarded or kept as reference

## Related

- [[ADR-RD-001-no-inline-hooks]] through [[ADR-RD-009-preserve-objectives]]
- [[viv-typed-agents]] umbrella SPEC
- Linear: [VI-234](https://linear.app/vi-blocks/issue/VI-234/re-vendor-solid-redesigned-typed-agents-components-into-viblocks-ai)
- Previous session log: [[2026-05-08-typed-agents-redesign]] (if present in vault)
