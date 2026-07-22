# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [3.36.0] - 2026-07-22

### Added

- **Benchmark harness improvements (Track 1)**:
  - Layer-1 capture persistence with `persist_capture()` — writes raw stage stdout before parsing with 25MB truncation and byte-stable defaults
  - Coverage attribution — deterministic `--agent` binding, nested spawns deduped from canonical audit rows, injectable clock
  - DV file-landing tripwire (`dv_file_gate()`) stops doomed spend before costly operations
  - Generated-project output sections in analysis Markdown and HTML reports (per-arm Swift file tree, LOC, arm folder path)
  
- **Paired ±agent benchmark runner (Track 1, amendments U3–U5)**:
  - Symmetric `with/` and `without/` arm folders with isolated cwd and stage contexts per arm
  - Both arms execute identical 10-stage prompt sequence (pl→ar→tl→dv→dr→sr→qa→dc→fn→st)
  - Per-call input/output token accounting persisted in run records and analysis reports
  - Prompt-surface neutralization (plugin-specific agent IDs and commands removed for fairness)
  
- **Deny-list enforcement (Track 1)**:
  - New `benchmark-settings.json` with deny-list for `git push`, `gh`, `curl`, `wget`, `WebFetch`, `WebSearch`
  - Applied to both WITH and WITHOUT arms for safety

- **Worktask infrastructure (Track 2, Phase 2.0)**:
  - `state-patch.sh --prev <CODE>` flag for atomic handoff-summary merge (additive, no breaking change)
  - `fn-preflight.sh` validator extracted from agent prose (new `validators.sh` entry point)
  
- **Governance & bounds (Track 2, Phases 2.1–3; Track 3)**:
  - Schema bounds enforcement: `facts.decisions` ≤ 8, `facts.dispatched_agents` ≤ 6
  - Subagents governance: `subagents_spawned` maxItems 5, no background nested in headless mode
  - Output-budget blocks in 6 agents (DR, PL, FN, QA, DV, AR)
  
- **Progressive-disclosure reference files (Track 2, Phase 4)**:
  - `skills/worktask/references/visual-qa.md` — QA design-comparison procedure
  - `skills/shared/platform-detection.md` — platform specialization routing
  - `skills/worktask/references/workspace-modes.md` — worktree mode detection and isolation rules

### Changed

- **Effort and model right-sizing (Track 2, Phase 1)**:
  - AR effort: `xhigh` → `high` (cost optimization)
  - ST effort: (no change) → `low` (alignment)
  - FN model: (no change) → `sonnet` (cost optimization; SSOT sync with stage-codes.md)
  - QA, DV, DR reconciled to STAGE_TABLE (medium, high, high)
  
- **Boilerplate dedup & section diet (Track 2, Phases 2–5)**:
  - 13 agents: inline jq `state-merge` blocks → `state-patch.sh --stage <CODE> --prev <PREV>` pointer (eliminates jq drift, sync hazard)
  - Handoff-preamble merge: duplicate expansion text collapsed to single copy (save ~1KB per agent)
  - Diff-Only Read Rule: centralized rule definition in `stage-contracts.md`, agents point via reference
  - Section-lint debt: 15 over-cap sections → 0 (all agents ≤ 1000 chars per section)
  - Plugin prose diet: agents/ byte reduction 283,888 → 245,987 B
  
- **Worktask Integration section (Track 2, Phase 4)** — Progressive-disclosure for complex topics:
  - `qa-engineer.md`: visual-comparison details → `visual-qa.md`
  - `developer.md`: platform-detection routing → `platform-detection.md`
  - `product-manager.md`, `technical-lead.md`, `project-manager.md`: streamlined with reference links
  
- **FN reader circuit (Track 3, B4)**:
  - Frontmatter-first reads (limit: 30 chars), deep-read only on anchor-miss/flagged verdict/retry
  - Added `deep_reads: []` optional array for audit trail

- **DV Validation cell (Track 3, B1)**:
  - DV stage-contracts row now includes file-landing check guidance

### Fixed

- **Permission mode (Track 1, A1)**:
  - Fixed `bypassPermissions` constant in `dispatch.py` and `baseline.py` (no cross-import, frozen-seam degrade when settings absent)
  - `--settings <benchmark-settings.json>` threaded into both arm argvs
  
- **Stale model cells (Track 2, Phase 1)**:
  - Removed 5 pre-existing fable/placeholder cells in stage-contracts model tables
  - Harmonized all STAGE_TABLE + stage-codes.md model references to SSOT single source

### Security

- Deny-list enforcement prevents accidental spend/network calls in benchmark harness (both arms)
- `bypassPermissions` mode with deny-list in settings file for transparent safety validation

### Known Considerations

- **SR-M1 advisory**: Settings fail-open if `benchmark-settings.json` absent (frozen-seam degrade); fail-closed recommended for pre-paid-run validation.

---

## [3.35.0] - 2026-07-09

### Added

- MCP auto-background await protocol integration
- Worktree-lock sweep for orphaned artifact cleanup
- Background-agent guarantees (200-spawn cap guidance)
- SendMessage-replay dedup for cross-session resume
- `agents --json` "Needs input" resume branch

### Changed

- Removed all pre-2.1.215 conditional/degrade branches (Claude Code 2.1.215+ required)
- Version-gate cleanup: consolidated CC feature detection to OTEL additions only
- Plugin minimum version now pinned to CC 2.1.215

---

**[Older versions archived in git history; view via `git log --grep="v3\\."`]**
