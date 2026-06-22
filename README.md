# Company Worktask Plugin

A staged worktask system for Claude Code — **9 stages standard, 11 with `--secure`** — with Task System integration, worktree-isolated execution behind two human approval gates (plan + finalization), stage transitions, and structured task management.

**Plugin v3.26.0 · Requires Claude Code 2.1.183+**

## Features

- **Worktree-isolated + two approval gates (plan + finalization)**: every worktask runs in a dedicated git worktree and STOPs twice — once after planning to approve the plan (`plan_gate: "checkpoint"`; skipped by `--auto-plan` / `--emergency`) and once before finalization to approve commit/push/PR (`fn_gate: "checkpoint"`; skipped by `--auto-finalization` / `--emergency`). By default FN STOPs before any commit/push/PR; `--auto-finalization` finalizes unattended. `--auto-plan` is orthogonal — it skips only the plan gate, never the FN gate. Changes are reviewable as PRs. (Batch runs via **`/megatask`** stamp both gates `"bypass"` directly per issue — see the Megatask feature below.)
- **`/megatask` — dependency-DAG batch orchestration**: run many worktasks across a GitHub milestone (`/megatask N`) or an explicit issue array (`/megatask --issues 12,15,18`). Parses `Depends on:` / `Blocks:` + P0–P3 labels into a DAG, executes in topological + priority order (never starting an issue whose blockers are unmerged), isolates each issue in its own worktree, and drives completion via the `megatask-monitor` hook (unblock-dependents + progress). One human checkpoint: the R1 batch confirmation.
- **9-Stage Worktask**: Planning → Architecture → Team Lead → Development → Developer Review → QA → Documentation → Finalization → Stakeholder
- **Task System Integration**: Native `TaskCreate`, `TaskUpdate`, `TaskGet`, `TaskList` tools
- **Native Dependencies**: `blockedBy` arrays for explicit dependency management
- **Cross-Session Persistence**: Tasks persist across sessions
- **Dynamic Task Creation**: PL0 creates subsequent stage tasks based on complexity assessment
- **Error Handling**: Retry logic (max 3 per stage) and escalation chains
- **Worktask State Management**: Task System handles all state persistence
- **Sub-agent Visibility**: All agents can view tasks with `TaskGet`
- **Agent-Specific Commands**: Specialized commands for each worktask role
- **Ethics Review**: Optional constitutional compliance checkpoint for high-risk features

## Task System

The worktask uses Claude Code's Task System for persistent task management:

| Tool | Purpose |
|------|---------|
| `TaskCreate` | Create tasks with subject, description, activeForm, metadata |
| `TaskUpdate` | Update status, owner, add/remove blockedBy |
| `TaskGet` | Retrieve current task state |
| `TaskList` | View all tasks and their statuses |

### Key Benefits

- **Cross-session persistence**: Tasks survive session boundaries (see below)
- **Native dependencies**: `blockedBy` arrays handled by the system
- **Sub-agent visibility**: Any agent can query task state
- **Task ownership**: Explicit `owner` field tracks responsible agent
- **Metadata support**: Store priority, stage, worktask_id per task
- **UI integration**: `Ctrl+T` task view in Claude Code

### Cross-Session Persistence

By default, tasks persist within a session. For cross-session persistence:

```bash
# Per-session (temporary)
CLAUDE_CODE_TASK_LIST_ID="my-project" claude

# Permanent (add to .claude/settings.json)
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "project-worktask"
  }
}
```

Tasks are stored at `~/.claude/tasks/<list-id>/` as individual JSON files.

## Installation

Add to your Claude Code configuration:

```bash
# Clone the repository
git clone https://github.com/igrsoft/company-workflow.git

# Or add as a plugin
claude plugins add /path/to/company-workflow
```

## Quick Start

### Launching a Worktask

Run the worktask command:

```
/worktask "[task description]"   # The worktask pipeline — PL0 dynamic sizing picks stages
```

`/worktask` is the single-issue entry point. PL0 sizes the pipeline by complexity (dropping AR/TL/DC for small tasks). Use `--auto-plan` to skip the plan-approval stop; `--auto-finalization` to skip the finalization-approval stop (auto commit/push/PR); `--emergency` for the incident pipeline (skips both gates). You can also launch via `Skill({skill:"igrsoft:worktask"})`. For **multi-issue batches**, use **`/megatask N`** (a milestone) or **`/megatask --issues 12,15,18`** (an array) — it orders by a dependency/blocker DAG and runs each issue unattended.

`/worktask` sets up the worktask context, Task System integration, and stage management.

### Examples

```
/worktask "Add dark mode to settings"
/worktask "/apple-developer:code-legacy-modernize migrate @StateObject to @Environment"
/worktask "/system-developer:code-modernize . --target cpp23"
```

### Combining with Other Commands

You can embed slash commands within the worktask payload. The orchestrator will:
1. Set up the context and planning
2. Detect the embedded `/command` pattern and store it in `metadata.embedded_commands`
3. Pass the command to the DV stage agent, which invokes it via the `Skill` tool
4. The embedded command's output feeds into the DV stage implementation

Embedded commands are detected by matching `/<name>` or `/<plugin:name>` patterns against available skills. The command arguments are preserved and passed through.

```
/worktask "/apple-developer:code-refactor src/Views/SettingsView.swift"
/worktask "/code-review PR #123"
```

## Pipeline Sizing

Single entry point (`/worktask`). PL always runs; PL0 dynamic sizing scores complexity (0–50) and creates only the stages the work needs:

| Score | Tier | Stages created (PL always runs) |
|-------|------|---------------------------------|
| 0–10 | Low | DV → DR → QA |
| 11–20 | Medium | AR → DV → DR → QA |
| 21–30 | Moderate | AR → TL → DV → DR → QA |
| 31–40 | High | AR → TL → DV → DR → QA → DC → FN → ST (full 9 stages) |
| 41–50 | Critical | AR → TL → DV → DR → SR → QA → DC → RE → FN → ST (11 stages, adds SR + RE) |

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

## Task System Initialization

Only `PL0` is created at startup. PL0 creates subsequent stage tasks after planning:

```typescript
// Create PL0 only — PL agent creates remaining stages after planning
TaskCreate({
  subject: "PL0: Planning",
  description: "Define requirements, assess complexity, create stage tasks",
  activeForm: "Planning...",
  metadata: { stage: "PL", agent: "igrsoft:product-manager", worktask_id: "dark-mode", priority: "medium" }
});

// Start PL0
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });

// After planning, PL0 creates stages based on complexity:
// AR0, DV0, QA0, etc. — each with metadata.agent for executor resolution
// Stage agents can split into sub-tasks: DV0 → DV1, DV2
```

## Context Folder Structure

```
.context/
├── planning-0.md            # PL stage (run 0; subsequent PL runs add planning-1.md, planning-2.md, …)
├── analyzing-0.md           # AR stage (run 0)
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

#### Core Worktask
| Command | Description |
|---------|-------------|
| `/worktask` | Initialize a single staged worktask (milestone-agnostic) |
| `/megatask` | Orchestrate many worktasks across a milestone or issue array, ordered by a dependency/blocker DAG |
| `/estimate` | Estimate task complexity and effort |
| `/export-estimate` | Export estimates to CSV |
| `/context-status` | Check context and worktask state |
| `/request-plan` | Turn a free-form request into a lightweight, context-aware plan |
| `/improve-yourself` | Retrospective: propose agent/skill/command updates from user edits |

#### Designer
| Command | Description |
|---------|-------------|
| `/design-specs` | Generate design specifications |
| `/design-review` | Review design decisions |
| `/accessibility-audit` | Accessibility audit (WCAG) |

#### Product Manager
| Command | Description |
|---------|-------------|
| `/pm-prioritize` | RICE/WSJF prioritization |
| `/pm-requirements` | Generate PRD |
| `/pm-roadmap` | Product roadmap planning |
| `/pm-milestone` | Generate milestone tickets with agent assignments |

#### Software Architect
| Command | Description |
|---------|-------------|
| `/arch-review` | Architecture review |
| `/arch-decision` | Create ADRs |
| `/tech-debt` | Technical debt analysis |
| `/tech-decision` | Create TDRs (technology decision records) |
| `/tech-review` | Deep technical review (quality, performance, security) |

#### QA Engineer
| Command | Description |
|---------|-------------|
| `/test-plan` | Generate test plan |
| `/test-coverage` | Coverage analysis |
| `/qa-report` | QA summary report |

#### Project Manager
| Command | Description |
|---------|-------------|
| `/sprint-plan` | Sprint planning |
| `/risk-assess` | Risk assessment |
| `/create-release-notes` | Generate release notes |
| `/create-pr` | Commit and open a pull request to the parent branch |

#### Team Lead
| Command | Description |
|---------|-------------|
| `/senior-review` | Senior developer code review |
| `/code-review-dev` | Development-focused code review |
| `/code-impl` | Code implementation guidance |

#### Technical Writer
| Command | Description |
|---------|-------------|
| `/doc-audit` | Documentation audit |
| `/readme-update` | README maintenance |
| `/cc-update` | Update plugin agents/commands/skills for new Claude Code features |

#### Stakeholder
| Command | Description |
|---------|-------------|
| `/business-case` | Business case generation |
| `/roi-analysis` | ROI calculation |
| `/executive-summary` | Executive summary |
| `/cost-report` | Cost analysis report |

#### Prompt Engineer
| Command | Description |
|---------|-------------|
| `/create-agent` | Create new agent definition |
| `/optimize-agent` | Optimize existing agent |
| `/optimize-command` | Optimize command definition |
| `/prompt-audit` | Audit prompt effectiveness |

#### Ethics Reviewer
| Command | Description |
|---------|-------------|
| `/ethics-review` | Constitutional compliance review |
| `/harm-assessment` | Harm assessment analysis |
| `/transparency-check` | Verify output transparency |

#### App Store / Publishing
| Command | Description |
|---------|-------------|
| `/appstore-info` | Scaffold App Store listing content from README |
| `/appstore-iap` | Set up App Store Connect in-app purchases |
| `/appstore-screenshots` | Generate App Store screenshots |

### Skills (23 total)
- `agent-coordination` — Multi-agent coordination, handoffs, parallel execution, error escalation
- `appstore-screenshots` — App Store screenshot generation (device specs, layout, Pencil MCP)
- `claude-constitution` — Constitutional principles and ethics framework
- `context-compression` — Context compression between agent handoffs
- `cost-optimization` — Token and cost tracking/optimization
- `cross-plugin-handoff` — Handoff protocol to external plugins (apple-developer, system-developer, …)
- `csv-export-templates` — CSV export structure for Google Sheets import
- `dv-screenshot-capture` — DV-stage screenshot capture, attached to the PR as visual evidence
- `estimation` — Complexity scoring (0–50) and T-shirt sizing
- `incident-response` — Incident classification, hotfix worktask, rollback, post-mortem (IR)
- `logging-conventions` — Route runtime log capture to `.context/logs/`
- `megatask` — Dependency-DAG orchestration of many worktasks (the `/megatask` command)
- `pencil-design` — Design mockup generation via Pencil MCP (Designer)
- `preview-ensurer` — Auto-add `#Preview` to modified SwiftUI views before snapshotting
- `release-engineering` — Semantic versioning, changelog, deployment readiness (RE)
- `request-plan` — Turn a free-form request into a lightweight, context-aware plan
- `review` — Senior technical review framework for estimates
- `security-review-process` — OWASP Top 10 checklist and secure-coding patterns (SR)
- `self-improvement` — ST-stage retrospective: propose scoped updates from user edits
- `shared/milestone-helpers` — Helper patterns for milestone/megatask operations
- `task-folder-organization` — `.context/` folder structure and artifact naming
- `worktask` — Complete staged worktask system (dynamic sizing, init, stage management)
- `worktask-testing-strategy` — Test-strategy planning for PL/AR stages

## Error Handling

### Retry Logic
Each stage can retry up to 3 times before escalation. Error narrative tracked per-agent in `.context/errors/<agent>.md` (parallel-safe for concurrent stage failures). Raw build/test captures go to `.context/logs/` per `logging-conventions` skill.

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
```

## Command Quick Reference

### Before Starting Work
```
/estimate "Task description"        # Understand complexity
/pm-prioritize "Feature"            # Prioritize in backlog
```

### During Planning
```
/pm-requirements "Feature"          # Generate PRD
/pm-roadmap --add "Feature"         # Add to roadmap
/arch-decision "Decision"           # Document decisions
```

### During Development
```
/worktask "Task"                    # Start a single worktask
/megatask 7                         # Orchestrate a whole milestone (DAG-ordered)
/megatask --issues 12,15,18         # …or an explicit issue array
/arch-review                        # Review architecture
/tech-debt --path src/              # Check tech debt
```

### During Testing
```
/test-plan "Feature"                # Generate test plan
/test-coverage                      # Check coverage
/qa-report                          # Generate QA report
```

### During Documentation
```
/doc-audit                          # Find doc gaps
/readme-update                      # Update README
```

### During Release
```
/create-release-notes               # Generate release notes
/executive-summary                  # Stakeholder summary
/sprint-plan                        # Plan next sprint
```

### Troubleshooting
```
/context-status                     # Context analysis
```

### Post-Worktask Learning
```
/improve-yourself                   # Retrospective: propose agent/skill/command updates from user edits
/improve-yourself --since <ref>     # Explicit baseline (default: last agent commit)
/improve-yourself --dry-run         # Inspect proposals without applying
/improve-yourself --apply           # Apply user-checked proposals via prompt-engineer
```

## License

MIT
