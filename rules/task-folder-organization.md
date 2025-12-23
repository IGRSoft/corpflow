# Task Folder Organization

**Category**: Task Management
**Priority**: High
**Applies to**: All tasks and features

## Purpose

This rule establishes the required organizational structure for tasks, ensuring consistency, traceability, and effective documentation across all development work.

## The Rule

**Every task MUST have its own dedicated folder** with a standardized structure and naming convention.

### Why Dedicated Folders?

1. **Isolation**: Each task's documentation, artifacts, and history remain separate
2. **Traceability**: Complete audit trail from planning through deployment
3. **Context Preservation**: Future developers can understand decision-making process
4. **State Management**: Clear tracking of progress and completion status
5. **Searchability**: Organized folder structure enables quick location of past work

## Naming Convention

### Format

```
YYYYMMDD-short-title/
```

### Components

1. **Date (YYYYMMDD)**: Creation date in ISO format
   - Example: `20251123` for November 23, 2025

2. **Hyphen**: Single hyphen separator (`-`)

3. **Short Title**: Concise, descriptive title
   - Use kebab-case (lowercase with hyphens)
   - Maximum 3-5 words
   - Describe WHAT, not HOW

### Good Examples

```
20251123-fix-mcp-config
20251120-user-authentication
20251118-payment-gateway-integration
```

### Bad Examples

```
fix-mcp              # No date
20251123_fix_mcp     # Wrong separator (underscores)
20251123-Fix-MCP     # Not kebab-case
task-001             # Not descriptive, no date
```

## Folder Structure

### Flat Layout

All markdown files are stored directly in the task folder root (no subfolders except for images):

```
tasks/YYYYMMDD-short-title/
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
  "task_id": "YYYYMMDD-short-title",
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
  "retries": { "P": 0, "A": 0, "T": 0, "D": 0, "Q": 0, "W": 0, "F": 0, "S": 0, "max": 3 }
}
```

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

When a user attaches images during a workflow task, copy them to the task's `images/` folder.

### Image Handling Process

1. **Detect attached images**: Screenshots, mockups, diagrams
2. **Copy to task folder**: `tasks/YYYYMMDD-task-name/images/`
3. **Use descriptive names**: `login-screen-mockup.png`, `error-screenshot-01.png`
4. **Reference in documentation**: Link to images in markdown files

### Naming Convention for Images

```
images/
├── mockup-login-screen.png
├── screenshot-error-state.png
├── diagram-architecture.png
└── user-flow-checkout.png
```

## File Organization Guidelines

### Flat Structure by Stage

Files are named by **workflow stage** and stored in the task folder root:

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
tasks/20251123-fix-login-timeout/
├── task-state.json
├── planning.md
├── development.md
└── testing.md
```

### Example 2: Feature Development

```
tasks/20251120-user-authentication/
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
tasks/20251125-api-integration/
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

1. **No dedicated folder**: Documenting in random locations
2. **Inconsistent naming**: Different formats for different tasks
3. **Missing task-state.json**: No way to track progress
4. **Creating subfolders**: Keep all .md files in task root (except images/)
5. **Poor naming**: `task-1`, `temp-fix`, `test-123`
6. **Ignoring errors**: Always create error.md when escalation is needed

### DO

1. **Always create folder**: Even for small tasks
2. **Follow naming convention**: YYYYMMDD-short-title
3. **Document decisions**: Explain WHY, not just WHAT
4. **Update state**: Keep task-state.json current
5. **Flat structure**: All .md files in task root (images/ only subdirectory)
6. **Log errors**: Create error.md when issues require escalation
