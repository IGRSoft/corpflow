# Company Worktask Plugin

A comprehensive 9-stage worktask system for Claude Code with Task System integration, worktree-isolated unattended execution, stage transitions, and structured task management.

claude-code min version: "2.1.169"

> **Claude Code feature bands**: latest integrated band is **2.1.171→2.1.175** (latest known CC: **2.1.175**; 2.1.171 was never published). Plugin **3.17.0** headline: **sub-agents now spawn their own sub-agents, up to 5 levels deep** (v2.1.172) — nested Tier-1→Tier-2 delegation chains are native and `/cost-report`'s `dispatch_depth` activates — plus **Fable 5 includes 1M context by default** (v2.1.173): on accounts without 1M usage credits, fable-tier dispatch fails (`Usage credits required for 1M context`) — see `skills/shared/model-selection.md` for the degrade path. Prior band (2.1.166→2.1.170, plugin 3.13.0) routed the 6 highest-reasoning agents — software-architector (AR), technical-lead (DR/TC), developer (DV), prompt-engineer (PE), security-reviewer (SR), ethics-reviewer (ET) — onto the `fable` tier (product-manager/PL and incident-responder/IR stay `opus`). **Alias caveat**: the `fable` alias resolves only on **CC ≥ 2.1.170**; on the minimum (2.1.169) it degrades to the provider default until you update.

> **3.23.1 — OV-131 worktask guardrails**: hardens the worktask trigger/resume machinery from the OV-131 prompt audit. Adds the canonical **`skills/shared/worktask-triggers.md`** — a single source of truth carrying the **§BLOCKING** first-action rule (a `/worktask`/`worktask:`/`fworktask:`/`quick:`/`micro:` message must launch the pipeline via its canonical entry point before any reads, exploration, or delegation) plus the per-trigger stage / unattended-vs-checkpoint table — repairing the dangling references in `skills/SKILL.md` and `skills/worktask/SKILL.md`. Adds an **INVOCATION GATE** banner to the worktask skill so a directly-delegated read surfaces the violation. PL0 dynamic sizing now records **`metadata.skipped_stages`** (`{stage, reason}`) so `state.json` self-documents which of the 9 standard stages were dropped and why. Introduces the **`metadata.plan_gate`** carrier (`bypass` for the unattended triggers, `checkpoint` for `micro:`/`quick:`, mirroring `fn_gate`) so resume-after-interruption honors the `micro:`/`quick:` post-plan human checkpoint instead of silently dispatching stages. All edits are additive docs/prompt changes — no behavior change for the always-unattended main pipeline.

> **3.21.0 — android-developer wired into the DV router**: the `developer` (DV) router now routes native Android work to the **android-developer** plugin (Kotlin, Jetpack Compose, Gradle, Hilt, Room, Retrofit, Coroutines, Material 3, plus architecture, test-generation, and code-fix specialists) instead of letting the `android` Detection-Rules row dead-end at a "kotlin patterns" placeholder. Adds `Task(android-developer:*)` targets, retargets the `android` Detection row to `android-developer:android-developer` (now keyed on `AndroidManifest.xml` + Gradle module markers, distinct from the JVM-backend `build.gradle` collision), an Android Platform Specialization table (phone/tablet, kotlin-architector, test-generator, code-fixer), android rows in Direct Platform Specialist Routing, a cross-plugin-handoff android-developer protocol table + `error_file` rule, and reuses the existing `android_adapter` screenshot path (`requires_screenshots: true` by default — `adb exec-out screencap -p` captures plus Gradle build/test transcripts as Build Evidence). There is no Android build MCP, so builds run through scoped `Bash(gradle:*|./gradlew|adb:*)`. Requires the android-developer plugin installed alongside igrsoft.

> **3.20.0 — frontend-developer wired into the DV router**: the `developer` (DV) router now routes web front-end work to the **frontend-developer** plugin (React/Next, Vue/Nuxt, Svelte 5, Angular, TypeScript, modern CSS/Tailwind, plus architecture, test-generation, and code-fix specialists) instead of letting the `web` Detection-Rules row fall through to a placeholder. Adds `Task(frontend-developer:*)` targets, retargets the `web` Detection row to `frontend-developer:frontend-developer`, a Web Platform Specialization table, a web-vs-native(Apple) precedence note (UI/app layer → `frontend-developer`, native module → `apple-developer:*`), web rows in Direct Platform Specialist Routing + Routing Audit, and reuses the existing `web_adapter` screenshot path (`requires_screenshots: true` by default — Playwright/Chrome MCP captures plus Lighthouse/axe as Build Evidence). Requires the frontend-developer plugin installed alongside igrsoft.

> **3.19.0 — backend-developer wired into the DV router**: the `developer` (DV) router now routes web/service back-end work to the **backend-developer** plugin (Node/TS, Go, JVM, Python web, Ruby, PHP, .NET, plus API-contract and persistence specialists) instead of letting it fall through to the generic developer or system-developer's language agents. Adds `Task(backend-developer:*)` targets, a backend Detection-Rules block with two precedence notes (Python *language* → `system-developer:python-developer` vs Python *web* → `backend-developer:python-backend-developer`; front-end vs back-end `package.json` resolved by dependency inspection, "both present → ask"), backend rows in Direct Platform Specialist Routing + Routing Audit, and a `backend` adapter row reusing the existing `cli_fallback_adapter` (curl/httpie transcripts, test output, k6 reports, migration logs — `requires_screenshots: false` by default). Requires the backend-developer plugin installed alongside igrsoft.

> **3.14.0 maintenance note**: plugin **3.14.0** retires the sub-2.1.169 backward-compat layer — the resume degrade tiers, dead "(v2.1.XXX+)" gates in operational guidance, and the legacy *unnumbered* artifact-name grace are gone (min CC stays **2.1.169**; integrated band stays **2.1.166→2.1.170**). **Resume caveat**: a worktask interrupted under plugin ≤3.13.0 that wrote unnumbered `.context/<basename>.md` artifacts will no longer resume-resolve them — finish in-flight worktasks before upgrading. Numbered `<basename>-N.md` artifacts (the default for many releases) are unaffected.

> **Managed version gating (optional, v2.1.163+)**: organizations can hard-gate the Claude Code version this plugin runs on via the `requiredMinimumVersion` / `requiredMaximumVersion` managed-settings keys (enterprise/team managed `settings.json`). Use these keys if your org needs to pin CC within a tested window. Related model governance: a managed `availableModels` allowlist constrains subagent model overrides too (v2.1.172), and `enforceAvailableModels` (v2.1.175) extends it to the Default model — under management, the plugin's per-stage `metadata.model` aliases may silently resolve to a different model (the orchestrator audits this; see `skills/worktask/SKILL.md § Pre-Stage Validation`).

## Features

- **Always worktree-isolated + unattended (v3.23.0)**: every worktask runs in a dedicated git worktree and proceeds end-to-end without human approval gates — changes are reviewable as PRs.
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
worktask: [task description]   # Standard - PL0 creates stages after planning
fworktask: [task description]  # Fast - auto-continues through all stages
quick: [task description]      # 4-stage worktask: PL → DV → DR → QA
micro: [task description]      # Lightweight: plan → approve → execute
```

When Claude detects these prefixes, it automatically invokes `/worktask` to set up the worktask context, Task System integration, and stage management.

### Examples

```
worktask: Add dark mode to settings
fworktask: Fix login button typo
worktask: /apple-developer:code-legacy-modernize migrate @StateObject to @Environment
worktask: /system-developer:code-modernize . --target cpp23
quick: Add validation to login form
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
fworktask: /code-review PR #123
```

## Worktask Tiers

| Trigger | Stages | Use For |
|---------|--------|---------|
| `micro: [task]` | Plan → approve → edit | Single-file fixes, typos |
| `quick: [task]` | PL → DV → DR → QA | Small features, bug fixes |
| `worktask: [task]` | Full 9 stages | Multi-file features, architectural changes |
| `fworktask: [task]` | Full 9 stages (auto-continue) | Trusted full worktasks |

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
| `/onboard-task` | Onboarding documentation |
| `/standup` | Standup summary |
| `/senior-review` | Senior developer code review |
| `/code-review-dev` | Development-focused code review |
| `/code-impl` | Code implementation guidance |

#### Technical Writer
| Command | Description |
|---------|-------------|
| `/doc-audit` | Documentation audit |
| `/api-docs` | API documentation |
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
/api-docs                           # Generate API docs
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
