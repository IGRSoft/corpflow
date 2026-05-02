# igrsoft Plugin Memory

Repository-tracked memory note. The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; this file mirrors version-tracking + optimization history for in-repo discoverability and CI checks (e.g. release tooling that reads `version:` from this file).

## Version Tracking

- Plugin version: **3.7.0** (handoff-protocol redesign on branch `feature/handoff-protocol`; minor bump per SemVer because the protocol is additive — `metadata.context_refs` + `state_file` are new fields, `state.json` is new infrastructure, legacy `metadata.context_files` path remains operational)
- Claude Code latest known: 2.1.121 (2026-04-28)
- Claude Code min required: 2.1.114
- Location: `/Users/korich/Projects/igrsoft/company-workflow`

## Optimization History

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
