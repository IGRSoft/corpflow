# Company Workflow Plugin

A comprehensive 8-stage workflow system for Claude Code with TodoWrite integration, stage transitions, approval gates, and structured task management.

## Features

- **8-Stage Workflow**: Planning → Architecture → Team Lead → Development → QA → Documentation → Finalization → Stakeholder
- **TodoWrite Integration**: Visual progress tracking with mandatory stage code format
- **Approval Gates**: P3 approval gate for standard workflows, auto-skip for fast workflows
- **Error Handling**: Retry logic (max 3 per stage) and escalation chains
- **Task State Management**: `task-state.json` as single source of truth
- **Flat Task Structure**: Organized task folders with consistent naming

## Installation

Add to your Claude Code configuration:

```bash
# Clone the repository
git clone https://github.com/igrsoft/company-workflow.git

# Or add as a marketplace
claude plugins add /path/to/company-workflow
```

## Quick Start

### Workflow Triggers

```
workflow: [task description]   # Standard - stops at P3 for user approval
fworkflow: [task description]  # Fast - skips P3 approval, auto-continues
```

### Examples

```
workflow: Add dark mode to settings
fworkflow: Fix login button typo
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
| P | Planning | project-manager | Define requirements |
| A | Architecture | architect-review | Design solution |
| T | Team Lead | team-lead | Coordinate approach |
| D | Development | [language-pro] | Implement solution |
| Q | QA | test-automator | Test and validate |
| W | Documentation | docs-architect | Write technical docs |
| F | Finalization | project-manager | Prepare release |
| S | Stakeholder | stakeholder | Final approval |

## Status Codes

| Code | Name | TodoWrite Status |
|------|------|------------------|
| 0 | preparing | pending |
| 1 | executing | in_progress |
| 2 | error | in_progress |
| 3 | done | completed |

## Task Folder Structure

```
tasks/YYYYMMDD-short-title/
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
- `workflow-engineer` - Workflow system expert
- `project-manager` - Planning and finalization
- `team-lead` - Team coordination
- `stakeholder` - Business approval

### Commands
- `/workflow-init` - Initialize a new workflow task
- `/workflow-status` - Display current task status

### Rules
- `workflow.md` - Complete workflow system rules
- `task-folder-organization.md` - Task folder structure

### Tools
- `setup-task.py` - Python script for task initialization

## Error Handling

### Retry Logic
Each stage can retry up to 3 times before escalation.

### Escalation Chain
```
S → F → Q → D → T → A → P → USER
```

## License

MIT
