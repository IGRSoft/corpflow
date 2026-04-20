# Company Workflow Plugin

A comprehensive 9-stage workflow system for Claude Code with Task System integration, stage transitions, approval gates, and structured task management.

claude-code min version: "2.1.114"

## Features

- **9-Stage Workflow**: Planning → Architecture → Team Lead → Development → Developer Review → QA → Documentation → Finalization → Stakeholder
- **Task System Integration**: Native `TaskCreate`, `TaskUpdate`, `TaskGet`, `TaskList` tools
- **Native Dependencies**: `blockedBy` arrays for explicit dependency management
- **Cross-Session Persistence**: Tasks persist across sessions
- **Dynamic Task Creation**: PL0 creates subsequent stage tasks based on complexity assessment
- **Error Handling**: Retry logic (max 3 per stage) and escalation chains
- **Workflow State Management**: Task System handles all state persistence
- **Sub-agent Visibility**: All agents can view tasks with `TaskGet`
- **Agent-Specific Commands**: Specialized commands for each workflow role
- **Ethics Review**: Optional constitutional compliance checkpoint for high-risk features

## Task System

The workflow uses Claude Code's Task System for persistent task management:

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
- **Metadata support**: Store priority, stage, workflow_id per task
- **UI integration**: `Ctrl+T` task view in Claude Code

### Cross-Session Persistence

By default, tasks persist within a session. For cross-session persistence:

```bash
# Per-session (temporary)
CLAUDE_CODE_TASK_LIST_ID="my-project" claude

# Permanent (add to .claude/settings.json)
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "project-workflow"
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

### Workflow Triggers

Simply prefix your task with one of these triggers:

```
workflow: [task description]   # Standard - PL0 creates stages after planning
fworkflow: [task description]  # Fast - auto-continues through all stages
quick: [task description]      # 4-stage workflow: PL → DV → DR → QA
micro: [task description]      # Lightweight: plan → approve → execute
```

When Claude detects these prefixes, it automatically invokes `/workflow` to set up the workflow context, Task System integration, and stage management.

### Examples

```
workflow: Add dark mode to settings
fworkflow: Fix login button typo
workflow: /apple-developer:code-legacy-modernize migrate @StateObject to @Environment
quick: Add validation to login form
```

### Combining with Other Commands

You can embed slash commands within workflow triggers. The orchestrator will:
1. Set up the context and planning
2. Detect the embedded `/command` pattern and store it in `metadata.embedded_commands`
3. Pass the command to the DV stage agent, which invokes it via the `Skill` tool
4. The embedded command's output feeds into the DV stage implementation

Embedded commands are detected by matching `/<name>` or `/<plugin:name>` patterns against available skills. The command arguments are preserved and passed through.

```
workflow: /apple-developer:code-refactor src/Views/SettingsView.swift
fworkflow: /code-review PR #123
```

## Workflow Tiers

| Trigger | Stages | Use For |
|---------|--------|---------|
| `micro: [task]` | Plan → approve → edit | Single-file fixes, typos |
| `quick: [task]` | PL → DV → DR → QA | Small features, bug fixes |
| `workflow: [task]` | Full 9 stages | Multi-file features, architectural changes |
| `fworkflow: [task]` | Full 9 stages (auto-continue) | Trusted full workflows |

## 9-Stage Workflow

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
  metadata: { stage: "PL", agent: "product-manager", workflow_id: "dark-mode", priority: "medium" }
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
├── planning.md              # PL stage
├── analyzing.md             # AR stage
├── development.md           # DV stage
├── developer-review.md      # DR stage
├── testing.md               # QA stage
├── documentation.md         # DC stage
├── complete.md              # FN stage
├── error.md                 # Error log (if needed)
├── designs/                 # Designer-generated .pen mockups
└── images/                  # User-attached visual assets
```

## Components

### Agents

| Agent | Description | Workflow Stage |
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
| `workflow-engineer` | Workflow troubleshooting | Support |

### Commands

#### Core Workflow
| Command | Description |
|---------|-------------|
| `/workflow` | Initialize a new workflow task |
| `/estimate` | Estimate task complexity and effort |
| `/export-estimate` | Export estimates to CSV |
| `/context-status` | Check context and workflow state |

#### Designer
| Command | Description |
|---------|-------------|
| `/design-specs` | Generate design specifications |
| `/design-review` | Review design decisions |
| `/ux-flow` | Create user flow diagrams |
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

### Skills
- `workflow.md` - Complete workflow system documentation
- `task-folder-organization.md` - Task folder structure
- `shared/five-whys.md` - Root cause analysis technique
- `claude-constitution.md` - Constitutional principles and ethics framework
- `agent-coordination.md` - Multi-agent coordination patterns
- `context-compression.md` - Context optimization techniques
- `cost-optimization.md` - Token and cost management
- `csv-export-templates.md` - Export format templates
- `estimation/SKILL.md` - Complexity estimation methods
- `milestone-workflow.md` - Milestone-based workflow tracking
- `review/SKILL.md` - Senior review guidelines
- `workflow-testing-strategy.md` - Workflow-integrated testing planning for PL/AR stages

### Tools

## Error Handling

### Retry Logic
Each stage can retry up to 3 times before escalation. Error context tracked in `.context/error.md`:

```markdown
## Development Error - 2025-01-26
**Retry**: 2/3
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
/workflow "Task"                    # Start workflow
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

## License

MIT
