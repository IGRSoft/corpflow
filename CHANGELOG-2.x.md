# Changelog — 2.x (archived)

Archived release history for `2.0.0`. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

**Reconstructed from git history.** The 2.x line predates this project's changelog and the repository carries no release tags, so the entry below was derived from the commits between the `2.0.0` bump in `06dfe97` (2026-01-26) and the `3.0.0` bump in `04cd855a` (2026-01-30) — it is not a contemporaneous record. Neighbouring lines live in [CHANGELOG-1.x.md](CHANGELOG-1.x.md), [CHANGELOG-3.x.md](CHANGELOG-3.x.md) (`3.0.0`–`3.43.0`), and [CHANGELOG.md](CHANGELOG.md).

## [2.0.0] - 2026-01-26

The only release on the 2.x line, and the shortest-lived major in the project's history — four days, superseded by `3.0.0` on 2026-01-30. `2.0.0` was set once and never bumped, so everything below shipped continuously under one version number.

The whole major is one migration: **hand-rolled JSON state gave way to Claude Code's native Task System.** The line opens by porting every agent to Task System Format and closes by deleting the JSON state file and its tooling outright — the intermediate steps that renamed and extended `workflow-state.json` were superseded within the same major. Agent count went 12 → 13, skills 11 → 13.

### Breaking

- **All workflow agents migrated to Task System Format.** Task System Format sections were added to every 8-stage agent, commands and skills were rewritten around Task System patterns, `setup-task.py` was changed to generate Task System commands, and the manifests moved to `2.0.0` (`06dfe97`).
- **`task-state.json` renamed to `workflow-state.json`** to align with the v2 schema, with every documentation and tooling reference updated. `setup-task.py` began creating `.context/` at the project root instead of inside dated task folders (`bc12be1`).
- **`workflow-state.json` removed entirely.** All JSON state-management logic was dropped in favour of native `TaskCreate` / `TaskUpdate` / `TaskGet` / `TaskList`, with dependency management handled by `blockedBy`. The `/workflow-debug`, `/workflow-reset`, and `/workflow-parallel` commands were deleted along with it, and agent responsibilities were simplified to the Task System-only approach (`99e7fca`).

### Added

- **`technical-lead` agent** for deep technical excellence — code-quality standards, technology evaluation, and technical-debt management — with `/tech-review` and `/tech-decision`. `team-lead` was refocused on people and process coordination, and `agent-coordination` gained technical-lead routing guidance (`1c0ec9e`).
- **Workspace-based milestone orchestration** (`3cde831`): per-ticket workspaces at `.workspaces/milestone-{N}/{issue#}/`, an `orchestrator.json` for track and issue state, a `workspace.json` per-ticket execution context, track-prefixed task IDs (`t1-1`, `t2-1`, …) so parallel tracks cannot collide, and a git branch per workspace. The P and F stages became workspace-aware.
- **Per-issue base-branch resolution** (`109f207`) — parses a `base_branch` field out of the issue body, checks the branch exists on the remote, and falls back issue body → `develop` → `master`. The chosen path is recorded in `base_branch_source`, and PR creation passes it through `--base`.
- **Context flushing between milestone issues** (`14f170d`). After PR creation, `.context/` is archived to `.context.archive/{timestamp}/` while `workspace.json` and `handoff.md` are kept, and each issue is delegated to a fresh subagent — file artifacts survive, accumulated agent context does not.
- **Unified complexity assessment and model routing** (`23c1644`) — a 5-factor score on a 0–50 scale, driving `haiku`/`sonnet`/`opus` selection. W+Q parallel execution became the default, multi-issue parallelism landed behind `--parallel:N` (default 2, max 5), and P3 approval enforcement plus per-issue approval gates were added. The commit claims 40–50% faster milestone execution and 40–50% cost savings at the A stage.
- **Test planning in the P and A stages** (`f352a61`) — the product manager defines test strategy before coding starts, the architect designs for testability and test doubles, backed by a new testing-strategy skill (later `skills/workflow-testing-strategy.md`, `dde55c3`).
- **Swift Testing as the mandatory unit-test framework** (`33d93ff`) — Swift Testing for unit tests and XCTest for UI tests at the D stage, enforced for all new unit tests at Q, and threaded through the testing-strategy skill, `qa-engineer`, the requirements template, `/test-plan`, and `/test-coverage`.
- **Canonical status-code reference** (`207bd95`) — a dual-layer status system documented in `skills/workflow.md` with a stage-lifecycle state-machine diagram, a quick reference in `workflow-engineer`, standardized notation across all files, and an explicit Task System → `statusCode` mapping, to stop the two from desynchronizing.
- **Task metadata and cross-session persistence** (`fa55e39`) — `metadata` field support plus `CLAUDE_CODE_TASK_LIST_ID` configuration so task lists survive across sessions.
- **`cross-plugin-handoff` skill** (`dde55c3`).

### Changed

- **Task deletion centralized in `workflow.md`** as a single source of truth, cutting the duplicated logic across agents, and paired with a safe deletion pattern that cleans up dependencies automatically (`23c1644`).
- **`marketplace.json` re-synced with the files on disk** (`f65ea37`).

### Removed

- The historical `migration-v2.md` document, once the migration it described was complete (`fa55e39`).
- The committed `.context/` directory, which had been checked in as a structural example (`d935893`).
