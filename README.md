# Company Workflow Plugin

A comprehensive 8-stage workflow system for Claude Code with TodoWrite integration, stage transitions, approval gates, and structured task management.

## Features

- **8-Stage Workflow**: Planning → Architecture → Team Lead → Development → QA → Documentation → Finalization → Stakeholder
- **TodoWrite Integration**: Visual progress tracking with mandatory stage code format
- **Approval Gates**: P3 approval gate for standard workflows, auto-skip for fast workflows
- **Error Handling**: Retry logic (max 3 per stage) and escalation chains
- **Task State Management**: `task-state.json` as single source of truth
- **Flat Task Structure**: Organized task folders with consistent naming
- **Agent-Specific Commands**: Specialized commands for each workflow role

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
workflow: [task description]   # Standard - stops at P3 for user approval
fworkflow: [task description]  # Fast - skips P3 approval, auto-continues
quick: [task description]      # 3-stage workflow: P → D → Q
micro: [task description]      # Direct execution, no workflow
```

When Claude detects these prefixes, it automatically invokes `/workflow` to set up the workflow context, TodoWrite integration, and stage management.

### Examples

```
workflow: Add dark mode to settings
fworkflow: Fix login button typo
workflow: /apple-developer:code-legacy-modernize migrate @StateObject to @Environment
quick: Add validation to login form
```

### Combining with Other Commands

You can embed slash commands within workflow triggers. The workflow system will:
1. Set up the context and planning
2. Execute the embedded command during the appropriate stage

```
workflow: /apple-developer:code-refactor src/Views/SettingsView.swift
fworkflow: /code-review PR #123
```

## Workflow Tiers

| Trigger | Stages | Use For |
|---------|--------|---------|
| `micro: [task]` | Direct edit | Single-file fixes, typos |
| `quick: [task]` | P → D → Q | Small features, bug fixes |
| `workflow: [task]` | Full 8 stages | Multi-file features, architectural changes |
| `fworkflow: [task]` | Full 8 stages (no P3) | Trusted full workflows |

## 8-Stage Workflow

| Code | Stage | Agent | Purpose |
|------|-------|-------|---------|
| P | Planning | product-manager | Define requirements |
| A | Architecture | software-architector | Design solution |
| T | Team Lead | team-lead | Coordinate approach |
| D | Development | [language-pro] | Implement solution |
| Q | QA | qa-engineer | Test and validate |
| W | Documentation | technical-writer | Write technical docs |
| F | Finalization | project-manager | Prepare release |
| S | Stakeholder | stakeholder | Final approval |

## Status Codes

| Code | Name | TodoWrite Status |
|------|------|------------------|
| 0 | preparing | pending |
| 1 | executing | in_progress |
| 2 | error | in_progress |
| 3 | done | completed |

## Context Folder Structure

```
.context/
├── task-state.json          # State management
├── planning.md              # P stage
├── analyzing.md             # A stage
├── development.md           # D stage
├── testing.md               # Q stage
├── documentation.md         # W stage
├── complete.md              # F stage
├── error.md                 # Error log (if needed)
└── images/                  # Visual assets
```

## Components

### Agents

| Agent | Description | Workflow Stage |
|-------|-------------|----------------|
| `product-manager` | Product strategy, requirements | P (Planning) |
| `software-architector` | Architecture, design patterns | A (Architecture) |
| `team-lead` | Team coordination, code reviews | T (Team Lead) |
| `qa-engineer` | Testing, quality assurance | Q (QA) |
| `technical-writer` | Documentation | W (Documentation) |
| `project-manager` | Sprint management, releases | F (Finalization) |
| `stakeholder` | Business approval, ROI | S (Stakeholder) |
| `workflow-engineer` | Workflow troubleshooting | Support |

### Commands

#### Core Workflow
| Command | Description |
|---------|-------------|
| `/workflow` | Initialize a new workflow task |
| `/estimate` | Estimate task complexity and effort |

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

#### Workflow Engineer
| Command | Description |
|---------|-------------|
| `/workflow-debug` | Diagnose workflow issues |
| `/workflow-reset` | Reset stuck workflow |

### Skills
- `workflow.md` - Complete workflow system documentation
- `task-folder-organization.md` - Task folder structure
- `five-whys.md` - Root cause analysis technique
- `workflow-triggers.md` - Automatic trigger detection

### Tools
- `setup-task.py` - Python script for task initialization

## Error Handling

### Retry Logic
Each stage can retry up to 3 times before escalation.

### Escalation Chain
```
S → F → Q → D → T → A → P → USER
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
/workflow-debug                     # Diagnose issues
/workflow-reset --to D              # Reset to stage
/standup                            # Check progress
```

## License

MIT
