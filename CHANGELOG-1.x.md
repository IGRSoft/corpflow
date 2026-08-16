# Changelog — 1.x (archived)

Archived release history for `1.0.0`. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

**Reconstructed from git history.** The 1.x line predates this project's changelog and the repository carries no release tags, so the entry below was derived from the commits between the root commit `af77456` (2025-12-23) and the `2.0.0` bump in `06dfe97` (2026-01-26) — it is not a contemporaneous record. Later releases live in [CHANGELOG-2.x.md](CHANGELOG-2.x.md), [CHANGELOG-3.x.md](CHANGELOG-3.x.md) (`3.0.0`–`3.43.0`), and [CHANGELOG.md](CHANGELOG.md).

## [1.0.0] - 2025-12-23

The first published version of the plugin, and the only release on the 1.x line. `1.0.0` was set in the root commit and never bumped, so everything below shipped continuously under a single version number between 2025-12-23 and 2026-01-26 rather than as separate releases.

The plugin started as an **8-stage workflow system** built on TodoWrite, with five agents (`product-manager`, `project-manager`, `stakeholder`, `team-lead`, `workflow-engineer`), two commands (`/workflow-init`, `/workflow-status`), and two rules files. By the end of the line it carried **12 agents, 42 commands, and 11 skills**, and had been renamed from `company-workflow` to `igrsoft`.

### Added

- **8-stage workflow pipeline** with TodoWrite integration, stage transitions, approval gates, and structured persistence — the founding surface of the plugin (`af77456`).
- **Seven more agents**: `qa-engineer` and `technical-writer` alongside `software-architector` (`1ca3676`), `designer` with design-workflow integration (`57e58ec`), `developer` and `prompt-engineer` with their ecosystem commands (`4dc62a0`), and `ethics-reviewer` (`faaddfd`).
- **23 agent-specific commands** (`2b076d8`), grouped by owning agent: PM (`pm-prioritize`, `pm-requirements`, `pm-roadmap`), architect (`arch-review`, `arch-decision`, `tech-debt`), QA (`test-plan`, `test-coverage`, `qa-report`), project manager (`sprint-plan`, `risk-assess`, `release-notes`), team lead (`onboard-task`, `standup`), technical writer (`doc-audit`, `api-docs`, `readme-update`), stakeholder (`business-case`, `roi-analysis`, `executive-summary`), workflow engineer (`workflow-debug`, `workflow-reset`), plus `estimate` for task complexity assessment.
- **`workflow:` prefix trigger** — typing `workflow: <task>` auto-invokes `/company-workflow:workflow-init`, backed by a new `rules/workflow-triggers.md` and a `--quick` flag on the init command (`ec1a4f7`).
- **Five Whys root-cause analysis skill** (`a6516ef`).
- **3-stage sequential estimation model** across all workflow agents — stage prioritization (Required / Nice-to-have / Not Required), sequential rules, gate management, stage-based resource allocation, and calendar-month billing (`5bfe1eb`).
- **Three optimization skills and three commands** — `cost-optimization`, `context-compression`, and `agent-coordination`, with `/cost-report`, `/context-status`, and `/workflow-parallel`. Five agents gained explicit boundaries, escalation rules, and coordination patterns (`a24cf56`).
- **Claude's Constitution as a first-class ethical framework** — a `claude-constitution` skill, the `ethics-reviewer` agent, ethics-focused commands, and constitutional-alignment sections added to all 11 existing agents, with ethics checkpoints wired into the workflow, agent coordination, and cost optimization (`faaddfd`).

### Changed

- **Task folders replaced by a single `.context/` directory.** Dated `tasks/YYYYMMDD-short-title/` folders were dropped in favour of one `.context/` per project, with traceability carried by `task-state.json` metadata instead of the folder name (`77d93c5`).
- **`/workflow-init` renamed to `/workflow`**, and the redundant `/workflow-status` command removed (`2b076d8`).
- **Plugin renamed `company-workflow` → `igrsoft`** (`73d2514`).
- **`task-state.json` schema extended** to carry cost tracking, context tracking, and parallel-execution state (`a24cf56`).
- **`team-lead` and `workflow-engineer` moved to `sonnet`** (`57702ae`).

### Fixed

- **Model name typos (`sonet` → `sonnet`)** in the `team-lead` and `workflow-engineer` agents, which had silently prevented the intended model from being selected (`a24cf56`).
- **`marketplace.json` was missing most of the plugin.** Agents, commands, and skills present on disk were never registered in the manifest, so they did not ship to installs (`48c8498`).
