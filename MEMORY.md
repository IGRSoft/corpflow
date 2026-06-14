# igrsoft Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **3.21.0** (request-plan skill + /request-plan command: lightweight context-aware plan-from-request bridge → worktask trigger; reuses estimation tier-selection + three-stage-planning phasing)
- Claude Code min required: **2.1.169** (README.md is authoritative; Fable alias resolves only on CC ≥ 2.1.170, degrades to provider default on 2.1.169)
- Claude Code latest integrated band: **2.1.171→2.1.175** (2.1.171 never published)

## CC Feature Band Index

Canonical band files live in the authoritative memory directory (`~/.claude/projects/<slug>/memory/`).

| Band | Canonical file | Plugin release |
|------|----------------|----------------|
| 2.1.171→2.1.175 | cc-features-2.1.171-175.md | v3.17.0 (nested sub-agents) |
| 2.1.166→2.1.170 | cc-features-2.1.166-170.md | v3.13.0 (Fable 5) |
| 2.1.157→2.1.165 | cc-features-2.1.157-165.md | v3.12.0 |
| 2.1.151→2.1.156 | cc-features-2.1.151-156.md | v3.10.13 (Opus 4.8) |
| 2.1.143→2.1.150 | cc-features-2.1.143-150.md | v3.10.6 |
| 2.1.141→2.1.142 | cc-features-2.1.141-142.md | v3.9.3 |
| 2.1.129→2.1.140 | cc-features-2.1.129-140.md | v3.9.2 |
| 2.1.122→2.1.128 | cc-features-2.1.122-128.md | v3.8.1 |
| 2.1.115→2.1.121 | cc-features-2.1.115-121.md | v3.6.1 |
| 2.1.102→2.1.114 | cc-features-2.1.102-114.md | v3.6.0 |
| 2.1.92→2.1.101 | cc-features-2.1.92-101.md | v3.5.0 |
| 2.1.87→2.1.91 | cc-features-2.1.87-91.md | v3.4.0 |
| 2.1.77→2.1.86 | cc-features-2.1.77-86.md | v3.3.0 |
| 2.1.51→2.1.76 | cc-features-2.1.51-76.md | v3.1.0/v3.2.0 |

## Release History (last 12, newest first)

- 2026-06-12: v3.18.0 — system-developer plugin routing: developer.md detection rules + specialist tables for C/C++/Python/Bash (closes unhandled `.py` gap), `systems` platform enum + cli-fallback screenshot row, cross-plugin-handoff system-developer protocol table.
- 2026-06-12: v3.17.0 — CC 2.1.171→2.1.175 band (15 files): 5-level nested sub-agents, availableModels/enforceAvailableModels caveats, Fable-1M degrade + R8, fable-blind drift fixes.
- 2026-06-12: v3.16.0 — screenshot-attachment wiring (#150): PL stamps `requires_screenshots` (detect-ui-change.sh S1–S4, fail-safe-true), PR `## Visual evidence` embed + marker-deduped issue comment via attach-visual-evidence.sh (PUBLISH_LIB_ONLY host-tier reuse; UI change ⇒ screenshots on BOTH issue and PR).
- 2026-06-10: v3.15.0 — token optimization: worktask SKILL split into trigger-read references (−32%), lean MEMORY.md (−95%), description cap, command thinning, desc-lint.sh.
- 2026-06-09: v3.14.0 — sub-2.1.169 compat retirement (resume degrade tiers collapsed to baseline, legacy artifact-grace retired, Fable tier reconciled).
- 2026-06-09: v3.13.0 — CC 2.1.166→2.1.170 band + Fable 5 routing (6 agents opus→fable; min CC 2.1.114→2.1.169).
- 2026-06-05: v3.12.1 — state-merge numbered-artifact resolution (`resolve_artifact` exact→highest-N→legacy→empty; +3 self-tests).
- 2026-06-05: v3.12.0 — CC 2.1.157→2.1.165 band + self-healing gates (`additionalContext` remediation) + precise resume (`waitingFor` 3-way branch).
- 2026-06-05: v3.11.4 — design↔result image-diff join (QA joins DV images via registry ID; RMSE pre-pass before multimodal vision).
- 2026-06-05: v3.11.3 — dv-screenshot-gate SubagentStop block hook + non-waivable DR manifest rule + Figma placement guard.
- 2026-06-05: v3.11.2 — Figma image embed fix for private/internal repos (publish-pl-issue.sh hosting-tier redesign).
- 2026-05-29: v3.11.0 — opt-in `--dynamic` worktask mode (dynamic-workflow reference) + Opus 4.8 reconcile.
- 2026-05-29: v3.10.13 — CC 2.1.151→2.1.156 Opus 4.8 transition (default high effort, `/effort xhigh`, fast mode).

## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
