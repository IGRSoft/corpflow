# igrsoft Plugin Memory

Repository-tracked memory note. The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; this file mirrors version-tracking + optimization history for in-repo discoverability and CI checks (e.g. release tooling that reads `version:` from this file).

## Version Tracking

- Plugin version: **3.8.2** (token + communication enhancement on branch `feature/hong-kong`; patch bump per SemVer — additive doc/metadata changes only)
- Claude Code latest known: 2.1.128 (2026-05-05)
- Claude Code min required: 2.1.114
- Location: `/Users/korich/Projects/igrsoft/company-workflow`

## Optimization History

- **2026-05-08**: v3.8.2 — Workflow orchestration token + communication enhancement. Branch: `feature/hong-kong`. **A3** dedupe model cost tier table: removed duplicate from `skills/cost-optimization/SKILL.md` (links to `skills/shared/model-selection.md` § Cost Tiers as single source of truth). **A4** added per-effort thinking-budget ceilings matrix (`low ≤4K`, `medium ≤16K`, `high ≤32K`, `xhigh ≤50K`, `max ≤64K`) to cost-optimization SKILL.md — justifies existing `effort: xhigh` on prompt-engineer/software-architector/security-reviewer. **B1** anchor pre-flight: documented PostToolUse hook on `Write|Edit` of `.context/*-N.md` artifacts (catches missing anchors at producing stage instead of DR-gate post-hoc) in `skills/workflow/references/handoff-protocol.md § Anchor Pre-Flight`. **B2** `metadata.skip_exploration` + `metadata.exploration_anchors` propagation: PL0 stamps both on every downstream task when `.context/exploration.md` exists; AR/TL agents short-circuit redundant Glob/Grep. Documented in `agents/product-manager.md § Downstream propagation`, `skills/agent-coordination/SKILL.md § metadata.skip_exploration Propagation`, and consumed by `agents/software-architector.md` + `agents/team-lead.md` Handoff Protocol § Required Inputs. **B3** F1 fallback telemetry: agents emit one line to `.context/logs/fallback-${run_index}.log` when state.json is absent — surfaces silent cache degradation; documented in `skills/shared/stage-contracts.md`. **B4** error-file lazy-create guard: orchestrator validation step 7 now treats missing `metadata.error_file` on disk as `retry_count = 0` (not failure); first-appending agent creates the file. **B5** mandatory plan-file anchor schema: `agents/product-manager.md § Mandatory Plan-File Anchor Schema` lists all seven required H2 anchors per `handoff-protocol.md#anchor-allow-list § PL`. **Skipped from original plan**: A1 (constraint preamble) — only developer.md has the elaborate preamble; no extractable duplication. A2 (workflow integration template) — sections are stage-specific content, not boilerplate. A5 (logging dedup) — agents already reference `logging-conventions` skill; no kind/scope tables to consolidate. Files modified: 7 (`skills/cost-optimization/SKILL.md`, `agents/product-manager.md`, `agents/software-architector.md`, `agents/team-lead.md`, `skills/agent-coordination/SKILL.md`, `skills/shared/stage-contracts.md`, `skills/workflow/references/handoff-protocol.md`) + version bump (`.claude-plugin/plugin.json`, `MEMORY.md`). No agent role changes; no breaking contract changes. Estimated impact: ~1-3K token savings per workflow (B2 short-circuit on AR/TL); fallback cost ↓ ~10× when anchors absent (B1 hook); cache hit rate target 65% (was ~60%).
- **2026-05-03**: v3.8.0 — Stage artifacts now numbered (`analyzing-N.md`, `coordination-N.md`, `development-N.md`, `developer-review-N.md`, `security-review-N.md`, `testing-N.md`, `documentation-N.md`, `release-N.md`, `complete-summary-N.md`, `retrospective-N.md`, `incident-N.md`, `ethics-review-N.md`) inheriting N from `planning-N.md` via `metadata.run_index` (integer stamped by PL0 on every downstream task). PL0 atomically resets `state.json` (`run_index`, `stages`, `facts`) on new run. Subdirs (`errors/`, `logs/`, `designs/`, `images/`) and `state.json` stay shared across runs. Legacy unnumbered names accepted as fallback for one release cycle. Four §4 renames applied: `release-prep.md`→`release.md`, `complete.md`→`complete-summary.md`, `incident-report.md`→`incident.md`, `approval.md`→`retrospective.md`. Branch: `feature/helsinki`.
- **2026-05-01**: v3.7.0 — handoff-protocol redesign: `state.json` ledger + `handoff:` YAML frontmatter schema + cache-friendly preamble layout `[1][2][3][4][5][6][7]` across 12 stage agents + 7 skills + 1 command + 4 new files. Branch: `feature/handoff-protocol`. (24 in-scope edits + 2 version-bump edits = 26 files: 4 NEW + 22 EDIT.)
  - **NEW** `skills/workflow/references/handoff-protocol.md` — canonical spec.
  - **NEW** `skills/workflow/references/cache-lint.sh` — Bash POSIX prefix-stability + anchor-lint with `--self-test` (passes).
  - **NEW** `skills/workflow/references/handoff-harness.sh` — Bash POSIX token-count harness (≥30% reduction confirmed on synthetic fixtures: DV 99%, DR 99%, QA 98%, DC 98%, FN 99%) + frontmatter/state.json schema validators + idempotency check.
  - **NEW** `.claude/hooks/state-merge.sh` — SubagentStop hook (idempotent atomic merge, exits 0 always, yq + awk fallback, `--self-test` passes).
  - **EDIT** `skills/shared/stage-contracts.md` + `skills/shared/task-system.md` — anchor-based Required Inputs, frontmatter mandate in Required Outputs, `metadata.context_refs` + `metadata.state_file` added with legacy `context_files` retained as F1 fallback.
  - **EDIT** `skills/workflow/SKILL.md` — Step 0 (read state.json), Step 6.5 (post-Task atomic merge), banner relocation prefix→suffix, cache-friendly layout documented.
  - **EDIT** `skills/workflow/references/initialization-patterns.md` — PL0 state.json init snippet, sample `context_refs` TaskCreate.
  - **EDIT** `skills/context-compression/SKILL.md` + `skills/cross-plugin-handoff/SKILL.md` + `skills/cost-optimization/SKILL.md` — state-ledger compression primitive, full-schema mandate for cross-plugin agents (with `## relaxed-profile` stub), `ENABLE_PROMPT_CACHING_1H=1` recommendation + state-merge.sh hook documentation.
  - **EDIT** 12 stage agents: `agents/{product-manager,software-architector,team-lead,developer,technical-lead,security-reviewer,qa-engineer,technical-writer,release-engineer,project-manager,stakeholder,incident-responder}.md` — `## Handoff Protocol` section appended (Snippet A verbatim, Frontmatter Template per stage, Snippet B with substituted placeholders). DR Checks 1/2/3/4 grep-pass: 12/12/1/1.
  - **EDIT** `commands/workflow.md` — Phase 1 step 3a inserts atomic state.json seed.
  - **EDIT** `.claude-plugin/plugin.json` — version `3.6.1` → `3.7.0`.
  - Backward-compat: paths F1 (state.json absent), F2 (agent ignores it), F3 (no frontmatter), F4 (corrupt state.json) all documented and exercised.
- **2026-05-01**: UI Test Gate — DV step D2 + QA step Q1 + QA Visual Comparison gated on `metadata.requires_ui_tests=true` in `<plan_file>`. Branch: feature/uitest-gate.
- 2026-05-03: FN-gate pre-seed fix — hoisted Pre-gate Conductor-attachments writer from pseudocode loop body into first-class SKILL.md H3; restructured conductor-attachments.md § When to write into Writer 1/Writer 2 subsections. Branch: feature/fn-gate-preseed-fix. No version bump (workflow doc restructuring).
- 2026-04-29: PL produces numbered `planning-N.md`.
- 2026-04-28: v3.6.1 — 2.1.115-121 integration.
- 2026-04-20: ST self-improvement skill + `/improve-yourself` manual command.
- 2026-04-20: `.context/logs/` canonical subfolder + `logging-conventions` skill.
- 2026-04-20: v3.6.0 — 2.1.102-114 integration.
- 2026-04-12: v3.5.0 — 2.1.92-101 integration.
- 2026-04-03: v3.4.0 — 2.1.87-91 integration.
- 2026-03-28: v3.3.0 — 2.1.77-86 integration.
- 2026-03-15: v3.2.0 — 2.1.72-76 integration.
- 2026-03-08: v3.1.0 — 2.1.51-71 integration.
- 2026-03-03: v3.0.0 — multi-agent-optimize patterns.
- 2026-02-06: Agent prompts optimization (constraint-first).
- 2026-01-31: Token optimization via shared references.
