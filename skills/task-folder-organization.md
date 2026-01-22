# Task Folder Organization

**Category**: Task Management
**Priority**: High
**Applies to**: All tasks and features

## Purpose

This rule establishes the required organizational structure for tasks, ensuring consistency, traceability, and effective documentation across all development work.

## The Rule

**Every project MUST have a `.context/` folder** for workflow artifacts with a standardized structure.

### Why `.context/` Folder?

1. **Simplicity**: Single location for all workflow artifacts
2. **Traceability**: Complete audit trail from planning through deployment
3. **Context Preservation**: Future developers can understand decision-making process
4. **State Management**: Clear tracking of progress and completion status
5. **Git Integration**: `.context/` can be gitignored or committed as needed

## Location

The `.context/` folder is located at the project root:

```
project-root/
├── .context/           # Workflow artifacts
│   ├── task-state.json
│   ├── planning.md
│   └── images/
├── src/
├── tests/
└── ...
```

## Folder Structure

### Flat Layout

All markdown files are stored directly in `.context/` (no subfolders except for images):

```
.context/
├── task-state.json          # State management (single source of truth)
├── planning.md              # Requirements, acceptance criteria (P stage)
├── analyzing.md             # Technical design, architecture (A stage)
├── development.md           # Implementation notes (D stage)
├── testing.md               # Test plan, results (Q stage)
├── documentation.md         # Documentation plan (W stage)
├── complete.md              # Final validation (F stage)
├── release.md               # Release notes (F stage)
├── security-review.md       # Security audit (if applicable)
├── deployment.md            # Deployment plan (if applicable)
├── error.md                 # Error log for escalations (created on errors)
└── images/                  # Design references, screenshots, user-attached images
```

### Required Files

#### 1. `task-state.json`

State management and metadata tracking:

```json
{
  "task_id": "current-task",
  "title": "Human Readable Task Title",
  "created_date": "YYYY-MM-DD",
  "execution_mode": "async",
  "priority": "high|medium|low",
  "platform": "all",
  "state": {
    "current": "planning:executing",
    "statusCode": "1",
    "agent": "P"
  },
  "dependencies": [],
  "blockers": [],
  "retries": { "P": 0, "A": 0, "T": 0, "D": 0, "Q": 0, "W": 0, "F": 0, "S": 0, "max": 3 },

  "cost_tracking": {
    "total_estimated_tokens": 0,
    "by_stage": {
      "P": { "tokens": 0, "model": "sonnet", "cost": 0 },
      "A": { "tokens": 0, "model": "opus", "cost": 0 },
      "T": { "tokens": 0, "model": "sonnet", "cost": 0 },
      "D": { "tokens": 0, "model": "sonnet", "cost": 0 },
      "Q": { "tokens": 0, "model": "haiku", "cost": 0 },
      "W": { "tokens": 0, "model": "haiku", "cost": 0 },
      "F": { "tokens": 0, "model": "sonnet", "cost": 0 },
      "S": { "tokens": 0, "model": "sonnet", "cost": 0 }
    },
    "budget_limit": null,
    "budget_used_percent": 0,
    "alerts": [],
    "billing_month": "YYYY-MM"
  },

  "context_tracking": {
    "last_compression": null,
    "estimated_tokens": 0,
    "compression_needed": false,
    "artifact_references": []
  },

  "parallel_execution": {
    "enabled": false,
    "active_stages": [],
    "safe_combinations": [["W", "Q"]],
    "started_at": null,
    "primary_for_conflicts": null
  }
}
```

#### Schema Field Descriptions

##### cost_tracking
- **total_estimated_tokens**: Running total of tokens used across all stages
- **by_stage**: Per-stage breakdown with tokens, model used, and cost
- **budget_limit**: Optional budget cap (null = unlimited)
- **budget_used_percent**: Percentage of budget consumed
- **alerts**: Array of cost alert messages
- **billing_month**: Current billing month (YYYY-MM format)

##### context_tracking
- **last_compression**: Timestamp of last context compression
- **estimated_tokens**: Current estimated context size
- **compression_needed**: Flag indicating compression is recommended
- **artifact_references**: List of artifact paths in current context

##### parallel_execution
- **enabled**: Whether parallel execution is active
- **active_stages**: Currently executing stages (e.g., ["W", "Q"])
- **safe_combinations**: Pre-defined safe parallel combinations
- **started_at**: Timestamp when parallel execution began
- **primary_for_conflicts**: Which stage has priority for artifact conflicts

#### 2. `planning.md`

Product Manager's planning document containing:
- Problem statement
- Requirements (functional and non-functional)
- Acceptance criteria
- Success metrics
- Constraints and dependencies

### Optional Files

- **analyzing.md**: Architecture decisions (A stage)
- **development.md**: Implementation notes (D stage)
- **testing.md**: Test plan and results (Q stage)
- **documentation.md**: Documentation plan (W stage)
- **complete.md**: Final validation (F stage)
- **release.md**: Release notes (F stage)
- **security-review.md**: Security audit (if applicable)
- **deployment.md**: Deployment plan (if applicable)
- **error.md**: Error log for escalation scenarios

### images/ Directory

The only subdirectory - contains visual references, mockups, screenshots, and user-attached images.

## User-Attached Images

When a user attaches images during a workflow task, copy them to `.context/images/`.

### Image Handling Process

1. **Detect attached images**: Screenshots, mockups, diagrams
2. **Copy to context folder**: `.context/images/`
3. **Use descriptive names**: `login-screen-mockup.png`, `error-screenshot-01.png`
4. **Reference in documentation**: Link to images in markdown files

### Naming Convention for Images

```
.context/images/
├── mockup-login-screen.png
├── screenshot-error-state.png
├── diagram-architecture.png
└── user-flow-checkout.png
```

## File Organization Guidelines

### Flat Structure by Stage

Files are named by **workflow stage** and stored in `.context/`:

| File | Stage | Owner |
|------|-------|-------|
| planning.md | P (Planning) | project-manager |
| analyzing.md | A (Architecture) | architect-review |
| development.md | D (Development) | [language-pro] |
| testing.md | Q (QA) | test-automator |
| documentation.md | W (Documentation) | docs-architect |
| complete.md | F (Finalization) | project-manager |
| release.md | F (Finalization) | project-manager |
| security-review.md | Optional | security-auditor |
| deployment.md | Optional | deployment-engineer |
| error.md | On error | Any agent |

### Documentation Standards

All markdown files should include:

1. **Header**: Task ID, date, author/agent
2. **Purpose**: What this document covers
3. **Content**: Detailed information for the stage
4. **Next Steps**: What comes next
5. **References**: Links to related documents

## Examples

### Example 1: Simple Bug Fix

```
.context/
├── task-state.json
├── planning.md
├── development.md
└── testing.md
```

### Example 2: Feature Development

```
.context/
├── task-state.json
├── planning.md
├── analyzing.md
├── development.md
├── testing.md
├── documentation.md
├── complete.md
├── security-review.md
└── images/
    ├── login-flow.png
    └── security-diagram.png
```

### Example 3: Task with Errors

```
.context/
├── task-state.json
├── planning.md
├── analyzing.md
├── development.md
├── error.md              # Created when errors occurred
├── testing.md
└── images/
```

## Common Pitfalls

### DON'T

1. **No .context folder**: Documenting in random locations
2. **Missing task-state.json**: No way to track progress
3. **Creating subfolders**: Keep all .md files in .context/ root (except images/)
4. **Ignoring errors**: Always create error.md when escalation is needed
5. **Multiple context folders**: Only one .context/ per project

### DO

1. **Always create .context/**: Even for small tasks
2. **Document decisions**: Explain WHY, not just WHAT
3. **Update state**: Keep task-state.json current
4. **Flat structure**: All .md files in .context/ (images/ only subdirectory)
5. **Log errors**: Create error.md when issues require escalation
6. **Clean up**: Archive or clear .context/ when starting new tasks
