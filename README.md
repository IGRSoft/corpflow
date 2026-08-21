# Company Worktask Plugin

A staged worktask system for Claude Code — **9 stages standard, 11 with `--secure`** — with a durable state ledger, worktree-isolated execution behind two human approval gates (plan + finalization), stage transitions, and structured task management.

**Plugin 4.0.22 · Requires Claude Code 2.1.233+**

## Features

- **Worktree-isolated + two approval gates (plan + finalization)**: every worktask runs in a dedicated git worktree and STOPs twice — once after planning to approve the plan (`plan_gate: "checkpoint"`; skipped by `--auto=[plan]` / `--emergency`) and once before finalization to approve commit/push/PR (`fn_gate: "checkpoint"`; skipped by `--auto=[finalization]` / `--emergency`). By default FN STOPs before any commit/push/PR; `--auto=[finalization]` finalizes unattended. The values are orthogonal — `plan` skips only the plan gate, never the FN gate; the third value, `--auto=[decision]`, skips no gate but delegates PL open questions to a Fable-model decision pass instead of the user. Changes are reviewable as PRs. (Batch runs via **`/megatask`** stamp both gates `"bypass"` directly per issue — see the Megatask feature below.)
- **`/megatask` — dependency-DAG batch orchestration**: run many worktasks across a GitHub milestone (`/megatask N`) or an explicit issue array (`/megatask --issues 12,15,18`). Parses `Depends on:` / `Blocks:` + P0–P3 labels into a DAG, executes in topological + priority order (never starting an issue whose blockers are unmerged), isolates each issue in its own worktree, and drives completion via the `megatask-monitor` hook (unblock-dependents + progress). One human checkpoint: the R1 batch confirmation.
- **9-Stage Worktask**: Planning → Architecture → Team Lead → Development → Developer Review → QA → Documentation → Finalization → Stakeholder
- **State Ledger**: `.context/state.json` `tasks{}` — one durable ledger, written only through `state-patch.sh`
- **Native Dependencies**: `blocked_by` arrays for explicit dependency management
- **Durable by construction**: the ledger is a file in the worktask folder, so it survives sessions, compaction, and resume
- **Dynamic Task Creation**: PL0 seeds subsequent stage tasks based on complexity assessment
- **Error Handling**: Retry logic (max 3 per stage) and escalation chains
- **Sub-agent Visibility**: every agent reads the same ledger
- **Agent-Specific Commands**: Specialized commands for each worktask role
- **Ethics Review**: Optional constitutional compliance checkpoint for high-risk features

## State Ledger

Stage state lives in `.context/state.json` under `tasks{}`, keyed by stage id (`PL0`, `DV0`,
`DV1`). All writes go through `skills/worktask/scripts/state-patch.sh`, which owns the merge
lock, the atomic write, and the disk guard.

| Operation | Command |
|-----------|---------|
| Create | `state-patch.sh --task-create <ID> --metadata '<json>'` |
| Set status | `state-patch.sh --task-status <ID> <status>` |
| Add dependency | `state-patch.sh --task-block <ID> --on <ID[,ID...]>` |
| Merge metadata | `state-patch.sh --task-meta <ID> --set '<json>'` |

### Key Benefits

- **Durable**: a file in the worktask folder — survives sessions, compaction, and resume with no configuration
- **Native dependencies**: `blocked_by` arrays, resolved by the orchestrator loop
- **Sub-agent visibility**: every agent reads the same ledger
- **Parallel-track safe**: numbered keys mean `DV0` and `DV1` are distinct entries, not a collision
- **Metadata support**: routing, gates, and dispatch config per task

> corpflow does **not** use Claude Code's `TaskCreate`/`TaskUpdate`/`TaskGet`/`TaskList` tools.
> CC 2.1.233 removed them on Opus 4.8, Sonnet 5, Fable 5, Mythos 5 and newer — every model this
> plugin dispatches — so the ledger is the only mechanism that works. See
> `skills/shared/state-ledger.md`.

## Installation

### Requirements

| Requirement | Needed for |
|-------------|------------|
| **Claude Code 2.1.233+** | The state ledger. 2.1.233 removed the `TaskCreate`/`TaskUpdate`/`TaskGet`/`TaskList` tools on every model this plugin dispatches, and the ledger is the replacement — see the note under [State Ledger](#state-ledger) |
| **git** | Every worktask runs in a dedicated worktree |
| **jq** | `state-patch.sh`, the only writer to the ledger. Hard requirement — without it no stage can complete |
| **`gh`**, authenticated | Post-PL issue publishing, `/megatask` milestone and issue reads, FN pull requests |
| **yq** | Full artifact frontmatter validation. Without it the handoff gate degrades to a grep-only check rather than failing |
| **python3 ≥ 3.10** | `/estimate --export csv` only. Note macOS ships 3.9.6 as `/usr/bin/python3`, which is too old — `brew install python@3.12` if you need the CSV pack |

Screenshot capture at the DV stage pulls in per-platform tooling on demand (ImageMagick,
pngquant, Playwright, a Swift toolchain). None of it is needed to install or to run a
worktask; see `skills/dv-screenshot-capture/SKILL.md` for what each capture path expects.

### Install

This repository is both a Claude Code marketplace (`igrsoft`) and the plugin it publishes
(`corpflow`). From inside Claude Code:

```
/plugin marketplace add IGRSoft/corpflow
/plugin install corpflow@igrsoft
```

The plugin activates as soon as it is safe to do so; if the commands do not appear, run
`/reload-plugins`. Hooks — including the `SubagentStop` state-merge safety net — are registered
by `.claude-plugin/plugin.json` on install. There is no manual hook step.

### Verify

`/plugin` should list **corpflow** as enabled, and `/worktask` should autocomplete. Then:

```
/request-plan "add a dark mode toggle to settings"
```

A plan comes back without touching the repo — the cheapest end-to-end check that agents,
skills, and routing all resolved.

### Optional — platform plugins

The DV stage routes to whichever platform plugin matches the repo, and falls back to project
tooling when none is installed. Each is a separate marketplace under the same org, installed the
same way (`/plugin marketplace add IGRSoft/<name>` then `/plugin install <name>@<name>`):

| Plugin | Covers |
|--------|--------|
| `apple-developer` | Swift, SwiftUI, UIKit, AppKit |
| `android-developer` | Kotlin, Jetpack Compose, Gradle |
| `frontend-developer` | TypeScript, React, Vue, Svelte, Angular, CSS |
| `backend-developer` | Node, Go, JVM, Python-web, Ruby, PHP, .NET |
| `system-developer` | C, C++, Python, Bash |
| `ai-engineer` | LLM apps, RAG, fine-tuning, MLOps, evals |

Version floors and the routing contract live in `skills/shared/compatible-plugins.md`.

### Routing overrides

Alias→plugin routing is canonical in `skills/shared/routing-matrix.md` — one row per
platform entry point and functional role (`corpflow:apple-developer →
apple-developer:apple-developer`, `corpflow:web-code-fixer →
frontend-developer:fe-code-fixer`, …). A project can swap any of them: copy
`skills/cross-plugin-handoff/templates/PROJECT-CORPFLOW.md` to the project root as
`CORPFLOW.md`, keep only the rows you override under `## Routing`, and the next worktask
resolves through your targets instead:

```markdown
## Routing

| Alias | Target |
|-------|--------|
| `corpflow:apple-developer` | `my-org-apple:apple-developer` |
| `corpflow:apple-code-fixer` | `my-org-apple:code-fixer` |
```

Overrides resolve once at worktask init (persisted as `state.routing`); uninstalled
targets fall back to the default with a `plugin_unavailable` audit row.

### From source

For contributing, or to run the plugin from a working tree:

```bash
git clone https://github.com/IGRSoft/corpflow.git
cd corpflow
make bootstrap     # vendor bats, check the swift toolchain, probe kcov
make test          # offline suite — no API calls, no spend
```

Then point Claude Code at the checkout with `/plugin marketplace add /path/to/corpflow`
and install as above.

## Quick Start

### Launching a Worktask

Run the worktask command:

```
/worktask "[task description]"   # The worktask pipeline — PL0 dynamic sizing picks stages
```

`/worktask` is the single-issue entry point. PL0 sizes the pipeline by complexity (dropping AR/TL/DC for small tasks). Use `--auto=[plan]` to skip the plan-approval stop; `--auto=[finalization]` to skip the finalization-approval stop (auto commit/push/PR); `--auto=[decision]` to let a Fable-model delegate answer PL0's open questions; combine as `--auto=[plan, decision, finalization]` for a fully unattended run (escalation-class questions still stop). Use `--emergency` for the incident pipeline (skips both gates). You can also launch via `Skill({skill:"corpflow:worktask"})`. For **multi-issue batches**, use **`/megatask N`** (a milestone) or **`/megatask --issues 12,15,18`** (an array) — it orders by a dependency/blocker DAG and runs each issue unattended.

`/worktask` sets up the worktask context, the state ledger, and stage management.

### Examples

```
/worktask "Add dark mode to settings"
/worktask "/apple-developer:fix-modernize migrate @StateObject to @Environment"
/worktask "/system-developer:fix-modernize . --target cpp23"
```

### Combining with Other Commands

You can embed slash commands within the worktask payload. The orchestrator will:
1. Set up the context and planning
2. Detect the embedded `/command` pattern and store it in `metadata.embedded_commands`
3. Pass the command to the DV stage agent, which invokes it via the `Skill` tool
4. The embedded command's output feeds into the DV stage implementation

Embedded commands are detected by matching `/<name>` or `/<plugin:name>` patterns against available skills. The command arguments are preserved and passed through.

```
/worktask "/apple-developer:fix-refactor src/Views/SettingsView.swift"
/worktask "/code-review PR #123"
```

## Options

### `/worktask`

Gate automation — `--auto=[<values>]` takes an array of any subset of `plan`, `decision`,
`finalization` (brackets optional, e.g. `--auto=plan,decision`). Each value is independent:

| Value | Effect |
|-------|--------|
| `plan` | Stamp `plan_gate: "bypass"` — skip the post-PL plan-approval STOP and proceed straight into the stage loop. FN gate still checkpoints. |
| `decision` | Stamp `decision_gate: "auto"` — PL0's open questions are answered by a Fable-model decision delegate instead of blocking on the user; the amendments land in the plan's existing anchors and the decisions themselves in `state.json facts.decisions[]` marked `(auto-decided)`. Escalation-class questions (irreversible, scope-expanding, security-posture, spend) still stop for a human. Bypasses no gate. |
| `finalization` | Stamp `fn_gate: "bypass"` — skip the pre-FN STOP; auto commit/push/PR. Plan gate still checkpoints. |

Scope and pipeline flags:

| Flag | Effect |
|------|--------|
| `--secure` / `--full` | Force the 11-stage pipeline (adds SR after DR, RE before FN) |
| `--emergency` | Run the incident pipeline (IR→DV→DR→QA→RE→FN); bypasses both gates |
| `--ethics-review` | Add an ET checkpoint after PL |
| `--with-design` | Invoke `designer` during PL (without the flag, Designer is skipped even for UI work) |
| `--sequential` | DC waits for QA instead of running in parallel |
| `--priority High\|Medium\|Low` | Task priority |
| `--platform apple\|android\|web\|systems\|backend\|ai\|all` | Target platform context |
| `--no-gh-issue` | Skip the post-PL GitHub issue auto-publish step |

### `/megatask`

| Form | Effect |
|------|--------|
| `/megatask N` | All open issues in GitHub milestone N |
| `/megatask N --issues 12,15` | Subset of milestone N |
| `/megatask --issues 12,15,18` | Explicit issue array, milestone-agnostic |
| `--secure` | Run each per-issue worktask on the 11-stage path |
| `--platform apple\|android\|web\|systems\|backend\|ai\|all` | Target platform context |
| `--dry-run` | Stop after the DAG is built — no worktrees, no PRs |

## Pipeline Sizing

Single entry point (`/worktask`). PL always runs; PL0 dynamic sizing scores complexity (0–50) and creates only the stages the work needs:

| Score | Tier | Stages created (PL always runs) |
|-------|------|---------------------------------|
| 0–10 | Low | DV → DR → QA |
| 11–20 | Medium | AR (default — PL0 may override per Stage Inclusion Criteria) → DV → DR → QA |
| 21–30 | Moderate | AR (default — PL0 may override per Stage Inclusion Criteria) → DV → DR → QA |
| 31–40 | High | AR (default — PL0 may override per Stage Inclusion Criteria) → DV → DR → QA → DC → FN → ST |
| 41–50 | Critical | AR (default — PL0 may override per Stage Inclusion Criteria) → DV → DR → SR → QA → DC → RE → FN → ST (adds SR + RE) |

\+ TL — only when PL0 splits the work across ≥2 developers (see Stage Inclusion Criteria in `skills/estimation-methodology/SKILL.md`)

`--secure` / `--full` forces the 11-stage path (SR after DR, RE before FN). Security-sensitive features auto-include SR regardless of score.

## 9-Stage Worktask

| Code | Stage | Agent | Purpose |
|------|-------|-------|---------|
| PL | Planning | product-manager | Define requirements |
| AR | Architecture | software-architector | Design solution |
| TL | Team Lead | team-lead | Coordinate approach |
| DV | Development | [language-pro] | Implement solution |
| DR | Developer Review | technical-lead | Code quality review |
| QA | QA | qa-engineer | Test and validate |
| DC | Documentation | technical-writer | Write technical docs |
| FN | Finalization | project-manager | Prepare release |
| ST | Stakeholder | stakeholder | Final approval |

## Ledger Initialization

Only `PL0` is seeded at startup. PL0 seeds subsequent stage tasks after planning:

```bash
# Seed PL0 only — the PL agent seeds remaining stages after planning.
state-patch.sh --task-create PL0 --metadata '{
  "stage":"PL","agent":"corpflow:product-manager",
  "description":"Define requirements, assess complexity, seed stage tasks",
  "worktask_id":"dark-mode","priority":"medium"}'

state-patch.sh --task-status PL0 in_progress

# After planning, PL0 seeds stages based on complexity:
# AR0, DV0, QA0, … — each with metadata.agent for executor resolution.
# Stage agents can split into sub-tasks: DV0 → DV1, DV2
```

## Context Folder Structure

```
.context/
├── planning-0.md            # PL stage (run 0; subsequent PL runs add planning-1.md, planning-2.md, …)
├── architecture-0.md           # AR stage (run 0)
├── coordination-0.md        # TL stage (run 0)
├── development-0.md         # DV stage (run 0)
├── developer-review-0.md    # DR stage (run 0)
├── security-review-0.md     # SR stage (run 0, secure/full variant)
├── testing-0.md             # QA stage (run 0)
├── documentation-0.md       # DC stage (run 0)
├── release-0.md             # RE stage (run 0, secure/full variant)
├── complete-summary-0.md    # FN stage (run 0)
├── retrospective-0.md       # ST stage (run 0)
├── state.json               # Worktask ledger (shared across runs)
├── errors/                  # Per-agent error narratives (if needed)
│   ├── developer.md         # DV retries
│   └── qa-engineer.md       # QA retries
├── designs/                 # Designer-generated .pen mockups
├── images/                  # User-attached visual assets
└── logs/                    # Raw runtime capture (build/test/monitor)
```

All stage artifacts follow the `<basename>-N.md` pattern where N equals `task.metadata.run_index` (stamped by PL0 on every downstream task). First run uses N=0.

## Components

### Agents

| Agent | Description | Worktask Stage |
|-------|-------------|----------------|
| `product-manager` | Product strategy, requirements | PL (Planning) |
| `software-architector` | Architecture, design patterns | AR (Architecture) |
| `team-lead` | Team coordination, sprint planning | TL (Team Lead) |
| `developer` | Dynamic platform developer routing | DV (Development) |
| `technical-lead` | Code quality, technical review | DR (Developer Review) |
| `qa-engineer` | Testing, quality assurance | QA (QA) |
| `technical-writer` | Documentation | DC (Documentation) |
| `project-manager` | Sprint management, releases | FN (Finalization) |
| `stakeholder` | Business approval, ROI | ST (Stakeholder) |
| `security-reviewer` | OWASP compliance, vulnerability review | SR (Security Review, secure/full) |
| `release-engineer` | Versioning, changelog, deployment readiness | RE (Release Engineering, secure/full) |
| `incident-responder` | Production triage, hotfix coordination | IR (Incident Response, emergency) |
| `designer` | UI/UX strategy, design systems | PL (Planning) |
| `ethics-reviewer` | Constitutional compliance, harm assessment | Support |
| `prompt-engineer` | Agent/command optimization | Support |
| `workflow-engineer` | Worktask troubleshooting | Support |

### Commands

36 commands, grouped by domain prefix. Top-level orchestration commands stay unprefixed; every other command carries a stable domain prefix.

#### Core / Orchestration
| Command | Description |
|---------|-------------|
| `/worktask` | Initialize a single staged worktask (milestone-agnostic) |
| `/megatask` | Orchestrate many worktasks across a milestone or issue array, ordered by a dependency/blocker DAG |
| `/estimate` | Estimate task complexity and effort; `--review` senior-reviews an estimate, `--export csv` emits the CSV pack |
| `/context-status` | Check context and worktask state |
| `/request-plan` | Turn a free-form request into a lightweight, context-aware plan |
| `/improve-yourself` | Retrospective: propose agent/skill/command updates from user edits |
| `/cost-report` | Worktask token-cost report |
| `/agent-report` | Which agents actually executed, from the audit trail |
| `/cc-update` | Update plugin agents/commands/skills for new Claude Code features |

#### Design (`design-`)
| Command | Description |
|---------|-------------|
| `/design-specs` | Generate design specifications |
| `/design-review` | Review design decisions |
| `/design-accessibility` | Accessibility audit (WCAG) |

#### Product (`pm-`)
| Command | Description |
|---------|-------------|
| `/pm-prioritize` | RICE/WSJF prioritization |
| `/pm-requirements` | Generate PRD |
| `/pm-roadmap` | Product roadmap planning |
| `/pm-milestone` | Generate milestone tickets with agent assignments |
| `/pm-sprint` | Sprint planning |
| `/pm-risk` | Risk assessment |

#### Architecture (`arch-`)
| Command | Description |
|---------|-------------|
| `/arch-review` | Architecture review |
| `/arch-decision` | Create ADRs, or TDRs via `--type tdr` |
| `/arch-debt` | Technical debt analysis |

#### Development (`dev-`)
| Command | Description |
|---------|-------------|
| `/dev-code-review` | Developer code-review DR gate; `--depth deep` adds full technical-review analysis |

#### QA / Test (`test-`)
| Command | Description |
|---------|-------------|
| `/test-plan` | Generate test plan |
| `/test-coverage` | Coverage analysis |
| `/test-report` | QA summary report |

#### Docs (`docs-`)
| Command | Description |
|---------|-------------|
| `/docs-audit` | Documentation audit |
| `/docs-readme` | README maintenance |
| `/docs-release-notes` | Generate release notes |

#### Business (`business-`)
| Command | Description |
|---------|-------------|
| `/business-report` | Business reporting via `--type case\|roi\|summary` |

#### Ethics
| Command | Description |
|---------|-------------|
| `/ethics-review` | Constitutional compliance review; `--lens harm` runs a full stakeholder harm assessment |

#### Authoring
| Command | Description |
|---------|-------------|
| `/create-agent` | Create new agent definition |
| `/optimize-agent` | Optimize existing agent |
| `/optimize-command` | Optimize command definition |
| `/prompt-audit` | Audit prompt effectiveness |

#### App Store / Publishing (`appstore-`)

**These three commands are Apple-specific and are the only ones that are.** They target
App Store Connect and the Apple listing format, and have no cross-platform equivalent.
Every other command in this plugin is platform-neutral and routes through
`skills/shared/platform-detection.md`. `/appstore-screenshots` takes `--apple-platform`
(an Apple device class), deliberately distinct from the plugin-wide `--platform`.

| Command | Description |
|---------|-------------|
| `/appstore-info` | Scaffold App Store listing content from README (Apple-only) |
| `/appstore-iap` | Set up App Store Connect in-app purchases (Apple-only) |
| `/appstore-screenshots` | Generate App Store screenshots (Apple-only) |

### Skills (25 total)
- `agent-coordination` — Multi-agent coordination, handoffs, parallel execution, error escalation
- `appstore-screenshots` — App Store screenshot generation (device specs, layout, Pencil MCP)
- `claude-constitution` — Constitutional principles and ethics framework
- `code-comment-standard` — Compact source-comment standard (WHY/contract only); loadable skill wrapping code-documentation.md
- `context-compression` — Context compression between agent handoffs
- `cost-optimization` — Token and cost tracking/optimization
- `cross-plugin-handoff` — Handoff protocol to external plugins; includes the add/replace-a-plugin checklist. Compatible dev plugins are registered in `skills/shared/compatible-plugins.md` (apple-developer, system-developer, android-developer, frontend-developer, backend-developer, ai-engineer)
- `csv-export-templates` — CSV export structure for Google Sheets import
- `dv-screenshot-capture` — DV-stage screenshot capture, attached to the PR as visual evidence
- `estimation-methodology` — Complexity scoring (0–50) and T-shirt sizing
- `gh-issue-dedup` — One GitHub issue per `.context/`; later runs comment instead of duplicating
- `incident-response` — Incident classification, hotfix worktask, rollback, post-mortem (IR)
- `logging-conventions` — Route runtime log capture to `.context/logs/`
- `megatask` — Dependency-DAG orchestration of many worktasks (the `/megatask` command)
- `milestone-helpers` — Helper patterns for milestone/megatask operations (ships from `skills/shared/milestone-helpers/`)
- `pencil-design-worktask` — Design mockup generation via Pencil MCP (Designer)
- `preview-ensurer` — Auto-add `#Preview` to modified SwiftUI views before snapshotting
- `release-engineering` — Semantic versioning, changelog, deployment readiness (RE)
- `request-plan` — Turn a free-form request into a lightweight, context-aware plan
- `security-review-process` — OWASP Top 10 checklist, dependency supply-chain triage, secure-coding patterns (SR)
- `self-improvement` — ST-stage retrospective: propose scoped updates from user edits
- `senior-developer-review` — Senior technical review framework for estimates
- `task-folder-organization` — `.context/` folder structure and artifact naming
- `worktask` — Complete staged worktask system (dynamic sizing, init, stage management)
- `worktask-testing-strategy` — Test-strategy planning for PL/AR stages

Each name above is the invocable id — prefix with `corpflow:` (e.g. `Skill({skill:"corpflow:worktask"})`). See [skills/README.md](skills/README.md) for the full index with effort levels and shared (non-loadable) utilities.

### Hooks

Registered in `.claude-plugin/plugin.json`. Several are **gates** — they can block a stage from completing, not just observe it.

| Hook | Event | Purpose |
|------|-------|---------|
| `audit-tooluse.sh` | PostToolUse (`Bash`/`Write`/`Edit`) | Appends canonical tool rows to `.context/logs/audit.jsonl`; Bash rows only for ledger patches |
| `anchor-preflight.sh` | PostToolUse (`Write`/`Edit`) | Anchor-lint pre-flight on `.context/<stage>-N.md` artifacts |
| `comment-standard-context.sh` | PostToolUse (`Write`/`Edit`) | Injects the comment standard once per session on the first source edit |
| `audit-subagent.sh` | SubagentStop | Writes `subagent_stopped` audit rows |
| `dv-screenshot-gate.sh` | SubagentStop | **Blocks** DV completion when the screenshot manifest is missing |
| `state-merge.sh` | SubagentStop | Merges artifact `handoff:` frontmatter into `.context/state.json` |
| `megatask-monitor.sh` | SubagentStop | Drives the megatask completion loop (unblock dependents, progress) |
| `precompact-checkpoint.sh` | PreCompact | Checkpoints `state.json` before auto-compaction |
| `agent-stop.sh` | Stop (wired via agent frontmatter) | Stage-boundary audit row + PL/FN approval-gate notification |

A `Stop` matcher on `product-manager`/`project-manager` also fires a `conductor` `PushNotification` when an approval gate is ready for review.

## Error Handling

### Retry Logic
Retry budget depends on how the failure classifies: `transient` retries up to **3** times (exponential backoff), `logic` up to **2** (corrective context added on the second attempt). `missing_input`, `ambiguous_requirements`, `design_flaw`, and `hard_constraint` do **not** retry — they escalate immediately. Full matrix in `skills/agent-coordination/SKILL.md` § Retry / Escalate Matrix.

Error narrative tracked per-agent in `.context/errors/<agent>.md` (parallel-safe for concurrent stage failures). Raw build/test captures go to `.context/logs/` per `logging-conventions` skill.

```markdown
## Retry 2 — 2026-04-20T14:32:10Z
**Agent**: developer (DV0)
**Classification**: logic
**retry_count**: 2
```

### Escalation Chains
```
9-stage:   ST → FN → DC → QA → DR → DV → TL → AR → PL → USER
11-stage:  ST → FN → RE → DC → QA → SR → DR → DV → TL → AR → PL → USER
Emergency: FN → RE → QA → DR → DV → IR → USER
Ethics:    Any → ethics-reviewer → stakeholder → USER
```

## Command Quick Reference

> Per-command usage (grouped by role/phase) lives in the **Commands** tables above (§ Commands). Every command — planning, development, testing, docs, release, troubleshooting, and `/improve-yourself` retrospective flags — is documented there.

## Development

The deterministic test suite runs offline — bats for shell, stdlib `unittest` for Python, Swift Testing for the benchmark artifact package. No system `bats` or `kcov` needed; `make bootstrap` vendors what it can and probes the rest.

```bash
make bootstrap     # vendor bats, check the swift toolchain, probe kcov
make test          # full offline suite (bats + Python + Swift), via run-tests.sh
make coverage      # + kcov / llvm-cov gating (≥85% target)
make test-ios      # TicTacToeKit on an iOS Simulator (SKIPs without a runtime)
make benchmark     # deterministic A/B plugin-overhead benchmark
make benchmark-live BUDGET=10.00   # live full-pipeline run (credential-gated, opt-in)
make report        # HTML report → benchmark/results/result.html
make clean
```

`make help` lists every target. Details live with the suites they describe:

- [tests/README.md](tests/README.md) — suite organization, fixtures, coverage verdict
- [benchmark/README.md](benchmark/README.md) — the WITH/WITHOUT Tic-Tac-Toe A/B harness
- [skills/README.md](skills/README.md) — full skill index with effort levels
- [CHANGELOG.md](CHANGELOG.md) — release history (`4.0.0`+); earlier majors archived in [CHANGELOG-3.x.md](CHANGELOG-3.x.md), [CHANGELOG-2.x.md](CHANGELOG-2.x.md), and [CHANGELOG-1.x.md](CHANGELOG-1.x.md)

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
