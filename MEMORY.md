# corpflow Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **4.0.15** — state-ledger cutover: `state.json` `tasks{}` replaces the retired Task System and the old `stages{}` map
- Claude Code min required: **2.1.233** (README.md is authoritative; pinned to the band top per the v3.35.0/v3.37.0 precedent — the ledger cutover itself no longer depends on any CC task tool)
- Claude Code latest integrated band: **2.1.221→2.1.233**

## CC Feature Band Index

Canonical band files live in the authoritative memory directory (`~/.claude/projects/<slug>/memory/`).

| Band | Canonical file | Plugin release |
|------|----------------|----------------|
| 2.1.221→2.1.233 | cc-features-2.1.221-233.md | v4.0.15 (Todo-tool removal → state-ledger cutover; 200-spawn cap gone; fork-by-default) |
| 2.1.216→2.1.220 | cc-features-2.1.216-220.md | v3.37.0 (nesting depth 5→3 + 20-concurrent cap; Opus 5 default; min CC → 2.1.220) |
| 2.1.210→2.1.215 | cc-features-2.1.210-215.md | v3.35.0 (MCP auto-background + spawn cap + "Needs input"; min CC → 2.1.215, version-gate cleanup) |
| 2.1.203→2.1.209 | cc-features-2.1.203-209.md | v3.34.0 (background-agent/worktree stabilization) |
| 2.1.185→2.1.202 | cc-features-2.1.185-202.md | v3.30.0 (background-default dispatch + Sonnet 5) |
| 2.1.176→2.1.183 | cc-features-2.1.176-183.md | v3.24.0 (agent-teams API) |
| 2.1.171→2.1.175 | cc-features-2.1.171-175.md | v3.17.0 (nested sub-agents) |
| 2.1.166→2.1.170 | cc-features-2.1.166-170.md | v3.13.0 (Fable 5) |
| 2.1.157→2.1.165 | cc-features-2.1.157-165.md | v3.12.0 |
| 2.1.151→2.1.156 | cc-features-2.1.151-156.md | v3.10.13 (top-Opus refresh) |
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

> Band files before 2.1.221 are missing from disk — plausibly collateral from the CC 2.1.228 bug "session cleanup deleting contents inside a project's memory folder". Index rows kept as the record of what existed.

## Release History (last 12, newest first)

- 2026-08-15: v4.0.15 — CC 2.1.233 removed the Todo/task tools on every model the plugin dispatches; full cutover to a `state.json` `tasks{}` ledger, no mirror, no fallback.
- 2026-08-15: v4.0.14 — megatask conflict-prevention tooling from a 9-issue parallel-batch post-mortem (#291): condition-first conflict recovery, worktree scratch exclusion, pbxproj union resolver.
- 2026-08-13: v4.0.13 — plugin renamed `company-workflow` → `corpflow`; ids, env vars, and repo slug moved, vendor identity unchanged. BREAKING, no alias.
- 2026-08-12: v4.0.12 — activated guards already written: `metadata.workspace_path` now stamped by `/worktask`, unset is a loud failure, `dv-tree-preflight.sh` actually invoked.
- 2026-08-10: v4.0.11 — fail-loud worktask tooling from the #431 retrospective (9 proposals).
- 2026-08-07: v4.0.10 — eval audit (#279): held-out oracle grades each arm's binary against 30 cases.
- 2026-08-06: v4.0.9 — opt-in change→test selection behind `./run-tests.sh --changed`.
- 2026-08-06: v4.0.8 — `state-patch.sh` idempotency guard widened to compare the whole patch.
- 2026-08-06: v4.0.7 — branch naming R1–R4: title-driven `--goal`, end-to-end once-only rename.
- 2026-08-05: v4.0.6 — test-execution gate: runner-aware, quote-aware strip of non-selecting flags.
- 2026-08-05: v4.0.5 — test-suite stringency hardening: 45 `.bats` / 501 `@test` → 53 / 680.
- 2026-08-05: v4.0.4 — gate-revision semantics: plan-gate rejection is an in-place revision, not a new run.

## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
