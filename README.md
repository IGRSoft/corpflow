# Company Worktask Plugin

A comprehensive 11-stage worktask system for Claude Code with Task System integration, worktree-isolated execution with a single post-plan human approval gate, stage transitions, and structured task management.

claude-code min version: "2.1.183"

> **Claude Code feature bands**: latest integrated band is **2.1.176→2.1.183** (latest known CC: **2.1.183**), plugin **3.24.0**. Headline: the **agent-teams API changed** (v2.1.178) — `TeamCreate`/`TeamDelete` were removed; every session now has **one implicit team** and teammates are spawned via the **Agent tool's `name` parameter** (`team_name` accepted but ignored). The band also adds **auto-mode git safety** (destructive git, non-agent `commit --amend`, and IaC `destroy` are blocked unless explicitly requested — v2.1.183), **pre-launch subagent spawn classification** with foreground/background sharing the 5-level nesting cap (v2.1.178/2.1.181), compaction honoring `--fallback-model` (v2.1.178), and model-governance refinements (`availableModels` alias-redirect hardening + `/fast` allowlist refusal, Fable-5 auto-mode fallback to best Opus — v2.1.176; frontmatter model-deprecation warnings — v2.1.183). The prior integrated band (2.1.171→2.1.175, plugin 3.17.0) brought **5-level nested sub-agent delegation** (v2.1.172) and **Fable 5 1M-context-by-default** (v2.1.173). **Alias caveat**: the `fable` alias resolves only on **CC ≥ 2.1.170**.

> **3.24.0 — Claude Code 2.1.176→2.1.183 band (agent-teams API + auto-mode guardrails)**: integrates the agent-teams API change (implicit per-session team; spawn via `Agent(name: …)`; `team_name` ignored — v2.1.178) across the team/coordination docs (`skills/shared/task-system.md`, `skills/worktask-milestone/references/agent-teams.md`, `skills/agent-coordination/*`, `skills/worktask/references/stage-details.md`), plus the auto-mode behavioral guardrails: destructive-git / non-agent-`--amend` / IaC-`destroy` blocks and `attribution.sessionUrl` (`skills/shared/git-conventions.md`, `commands/create-pr.md`); scheduled/webhook trigger deliveries can't satisfy an approval park (`skills/worktask/references/resume.md`); pre-launch spawn classification + fg/bg depth parity + `Tool(param:value)` permission syntax (`skills/agent-coordination/SKILL.md`); subagent MCP server-level `disallowedTools` + WebSearch (`skills/agent-coordination/references/headless-dispatch.md`, `skills/cross-plugin-handoff/references/plugin-protocols.md`); compaction `--fallback-model` (`skills/context-compression/SKILL.md`); model-governance refinements (`skills/shared/model-selection.md`); workflow auto-engage scoping (`skills/worktask/references/dynamic-workflow.md`); and a `commands/cc-update.md` Feature Category Mapping refresh. Min CC raised **2.1.169 → 2.1.183**; pure docs/metadata, no source changes.

> **3.25.0 — restored PL plan-approval gate + single `worktask` trigger**: re-introduces the one human checkpoint after planning — `PL0.metadata.plan_gate` now defaults to `"checkpoint"`, so plain `worktask` STOPs after PL0, presents the plan, and waits for `AskUserQuestion` approval before dispatching implementation stages (enforced by the new `commands/worktask.md § Step A.5` and the `skills/worktask/SKILL.md` PRECONDITION CHECK). The approval audit line uses `subject:"PL<run_index>"` so a re-run cannot reuse a stale approval. New **`--auto-plan`** flag stamps `plan_gate: "bypass"` for a trusted fast-path; **`--milestone:N`** bypasses both gates for unattended batches (keeping its R1 multi-PR confirmation). The FN gate is unchanged (`fn_gate: "bypass"`, unattended). Collapses the trigger set to a **single `worktask`** trigger — `micro:`, `quick:`, and `fworktask:` are removed (PL0 dynamic sizing subsumes the old "small task" shortcuts by dropping stages); the deprecated `--auto-continue` flag and the legacy `approval-gate-hook.md` reference are deleted. ~17 files reconciled across `commands/`, `skills/`, `agents/`, plus README/MEMORY.

> **3.23.2 — recall-first DR review gate**: rewrites the DR-stage review command (`commands/code-review-dev.md`) around recall — decoupled **Phase 1 DETECTION / Phase 2 VERIFICATION+FILTERING / Phase 3 completeness**, a 12-class bug checklist, **mandatory read-beyond-the-diff** context gathering (callers/consumers, dynamic/string-literal refs, type definitions, acceptance-criteria intent check), a BLOCKED-verification keep rule, **P0/P1/P2** severity routing, and an explicit decision+coverage output — so confirmed correctness/security/concurrency/regression risks stop slipping past DR to QA. Adapts the source's Conductor review tools to the plugin's real mechanism (read-only `git diff origin/master...HEAD` acquisition + findings to `developer-review-N.md`; `allowed-tools` now declares read-only `git diff`/`log`/`show`). Adds an **Escalation to DV** loop — a read-confirmed *sound* P0/P1 sets `verdict: fail`, which re-dispatches DV to remediate, then DR re-reviews. Also fixes a routing bug in `agents/technical-lead.md` §DR3.5 + visual-evidence: the escalation classification was `ambiguous_requirements` (which the retry/escalate matrix routes to **PL**) while the intent is **DV** — corrected to `missing_input` (matrix → previous stage = DV). Also retires two unused commands — `/api-docs` and `/onboard-task` (deleted from `commands/` and the marketplace manifest; 45→43 commands).

> **3.23.1 — OV-131 worktask guardrails**: hardens the worktask trigger/resume machinery from the OV-131 prompt audit. Adds the canonical **`skills/shared/worktask-triggers.md`** — a single source of truth carrying the **§BLOCKING** first-action rule (a `/worktask`/`worktask:`/`fworktask:`/`quick:`/`micro:` message must launch the pipeline via its canonical entry point before any reads, exploration, or delegation) plus the per-trigger stage / unattended-vs-checkpoint table — repairing the dangling references in `skills/SKILL.md` and `skills/worktask/SKILL.md`. Adds an **INVOCATION GATE** banner to the worktask skill so a directly-delegated read surfaces the violation. PL0 dynamic sizing now records **`metadata.skipped_stages`** (`{stage, reason}`) so `state.json` self-documents which of the 9 standard stages were dropped and why. Introduces the **`metadata.plan_gate`** carrier (`bypass` for the unattended triggers, `checkpoint` for `micro:`/`quick:`, mirroring `fn_gate`) so resume-after-interruption honors the `micro:`/`quick:` post-plan human checkpoint instead of silently dispatching stages. All edits are additive docs/prompt changes — no behavior change for the always-unattended main pipeline.

> **3.14.0 maintenance note**: plugin **3.14.0** retires the sub-2.1.169 backward-compat layer — the resume degrade tiers, dead "(v2.1.XXX+)" gates in operational guidance, and the legacy *unnumbered* artifact-name grace are gone (min CC stays **2.1.169**; integrated band stays **2.1.166→2.1.170**). **Resume caveat**: a worktask interrupted under plugin ≤3.13.0 that wrote unnumbered `.context/<basename>.md` artifacts will no longer resume-resolve them — finish in-flight worktasks before upgrading. Numbered `<basename>-N.md` artifacts (the default for many releases) are unaffected.

> **Managed version gating (optional, v2.1.163+)**: organizations can hard-gate the Claude Code version this plugin runs on via the `requiredMinimumVersion` / `requiredMaximumVersion` managed-settings keys (enterprise/team managed `settings.json`). Use these keys if your org needs to pin CC within a tested window. Related model governance: a managed `availableModels` allowlist constrains subagent model overrides too (v2.1.172), and `enforceAvailableModels` (v2.1.175) extends it to the Default model — under management, the plugin's per-stage `metadata.model` aliases may silently resolve to a different model (the orchestrator audits this; see `skills/worktask/SKILL.md § Pre-Stage Validation`).

## Features

- **Worktree-isolated + one plan-approval gate (v3.25.0)**: every worktask runs in a dedicated git worktree and STOPs once after planning for the user to approve the plan (`plan_gate: "checkpoint"`); `--auto-plan` / `--milestone:N` skip the stop. FN finalization (commit/push/PR) remains unattended — changes are reviewable as PRs.
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
claude plugins add /path/to/company-worktask
```

## Quick Start

### Worktask Triggers

Simply prefix your task with one of these triggers:

```
worktask: [task description]   # The worktask pipeline — PL0 dynamic sizing picks stages
```

There is one trigger. PL0 sizes the pipeline by complexity (dropping AR/TL/DC for small tasks). Use `--auto-plan` to skip the plan-approval stop; `--milestone:N` for unattended batches.

When Claude detects these prefixes, it automatically invokes `/worktask` to set up the worktask context, Task System integration, and stage management.

### Examples

```
worktask: Add dark mode to settings
worktask: /apple-developer:code-legacy-modernize migrate @StateObject to @Environment
worktask: /system-developer:code-modernize . --target cpp23
```

### Combining with Other Commands

You can embed slash commands within worktask triggers. The orchestrator will:
1. Set up the context and planning
2. Detect the embedded `/command` pattern and store it in `metadata.embedded_commands`
3. Pass the command to the DV stage agent, which invokes it via the `Skill` tool
4. The embedded command's output feeds into the DV stage implementation

Embedded commands are detected by matching `/<name>` or `/<plugin:name>` patterns against available skills. The command arguments are preserved and passed through.

```
worktask: /apple-developer:code-refactor src/Views/SettingsView.swift
worktask: /code-review PR #123
```

## Pipeline Sizing

One trigger (`worktask:`). PL0 dynamic sizing selects the stage set by complexity score:

| Complexity | Typical stages | For |
|---|---|---|
| Low | PL → DV → DR → QA (AR/TL/DC dropped) | Single-file fixes, small bug fixes |
| Standard | Full 9 stages | Multi-file features, architectural changes |
| Secure (`--secure`) | 11 stages (adds SR, RE) | Security-sensitive work |

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
| `team-lead` | Team coordination, code reviews | TL (Team Lead) |
| `developer` | Dynamic platform developer routing | DV (Development) |
| `qa-engineer` | Testing, quality assurance | QA (QA) |
| `technical-writer` | Documentation | DC (Documentation) |
| `project-manager` | Sprint management, releases | FN (Finalization) |
| `stakeholder` | Business approval, ROI | ST (Stakeholder) |
| `designer` | UI/UX strategy, design systems | PL (Planning) |
| `ethics-reviewer` | Constitutional compliance, harm assessment | Support |
| `prompt-engineer` | Agent/command optimization | Support |
| `workflow-engineer` | Worktask troubleshooting | Support |

### Commands

#### Core Worktask
| Command | Description |
|---------|-------------|
| `/worktask` | Initialize a new worktask task |
| `/estimate` | Estimate task complexity and effort |
| `/export-estimate` | Export estimates to CSV |
| `/context-status` | Check context and worktask state |

#### Designer
| Command | Description |
|---------|-------------|
| `/design-specs` | Generate design specifications |
| `/design-review` | Review design decisions |
| `/a11y-audit` | Accessibility audit (WCAG) |

#### Product Manager
| Command | Description |
|---------|-------------|
| `/pm-prioritize` | RICE/WSJF prioritization |
| `/pm-requirements` | Generate PRD |
| `/pm-roadmap` | Product roadmap planning |

#### Software Architect
| Command | Description |
|---------|-------------|
| `/arch-review` | Architecture review |
| `/arch-decision` | Create ADRs |
| `/tech-debt` | Technical debt analysis |

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
| `/release-notes` | Generate release notes |

#### Team Lead
| Command | Description |
|---------|-------------|
| `/standup` | Standup summary |
| `/senior-review` | Senior developer code review |
| `/code-review-dev` | Development-focused code review |
| `/code-impl` | Code implementation guidance |

#### Technical Writer
| Command | Description |
|---------|-------------|
| `/doc-audit` | Documentation audit |
| `/readme-update` | README maintenance |

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

### Skills (27 total)
- `dv-screenshot-capture/SKILL.md` - DV stage screenshot capture with platform adapters (apple/web/android/cli-fallback)
- `worktask.md` - Complete worktask system documentation
- `task-folder-organization.md` - Task folder structure
- `shared/five-whys.md` - Root cause analysis technique
- `claude-constitution.md` - Constitutional principles and ethics framework
- `agent-coordination.md` - Multi-agent coordination patterns
- `context-compression.md` - Context optimization techniques
- `cost-optimization.md` - Token and cost management
- `csv-export-templates.md` - Export format templates
- `estimation/SKILL.md` - Complexity estimation methods
- `worktask-milestone/SKILL.md` - Milestone-based worktask tracking
- `review/SKILL.md` - Senior review guidelines
- `self-improvement/SKILL.md` - ST-stage retrospective: diff-based learning from user edits; writes `.context/learnings.md` with per-proposal approval checklist, scoped to in-context agents/skills/commands only
- `worktask-testing-strategy.md` - Worktask-integrated testing planning for PL/AR stages
- `worktask/references/handoff-protocol.md` - Inter-stage handoff schema: state.json ledger, frontmatter contract, cache-friendly prompt layout

### Tools

## Error Handling

### Retry Logic
Each stage can retry up to 3 times before escalation. Error narrative tracked per-agent in `.context/errors/<agent>.md` (parallel-safe for concurrent stage failures). Raw build/test captures go to `.context/logs/` per `logging-conventions` skill.

```markdown
## Retry 2 — 2026-04-20T14:32:10Z
**Agent**: developer (DV0)
**Classification**: logic
**retry_count**: 2
```

### Escalation Chain
```
ST → FN → QA → DV → TL → AR → PL → USER
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
/worktask "Task"                    # Start worktask
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
/release-notes                      # Generate release notes
/executive-summary                  # Stakeholder summary
/sprint-plan                        # Plan next sprint
```

### Troubleshooting
```
/standup                            # Check progress
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
