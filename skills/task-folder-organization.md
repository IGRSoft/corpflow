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
├── planning.md              # Requirements, acceptance criteria (P stage)
├── analyzing.md             # Technical design, architecture (A stage)
├── development.md           # Implementation notes (D stage)
├── testing.md               # Test plan, results (Q stage)
├── documentation.md         # Documentation plan (W stage)
├── complete.md              # Final validation (F stage)
├── release.md               # Release notes (F stage)
├── milestone.json           # GitHub milestone context (when --milestone used)
├── security-review.md       # Security audit (if applicable)
├── deployment.md            # Deployment plan (if applicable)
├── error.md                 # Error log for escalations (created on errors)
└── images/                  # Design references, screenshots, user-attached images
```

### Required Files

#### 1. `planning.md`

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
- **milestone.json**: GitHub milestone context (when `--milestone` used)
- **security-review.md**: Security audit (if applicable)
- **deployment.md**: Deployment plan (if applicable)
- **error.md**: Error log for escalation scenarios

### Milestone Context File (`milestone.json`)

Created when `/workflow --milestone:N` is used. Contains:

- **milestone**: GitHub milestone metadata (number, title, due date)
- **issues**: Array of issues sorted by priority with branch names
- **execution**: Current issue, completed/pending arrays
- **summary**: Issue counts and progress

See [Milestone Workflow](milestone-workflow.md) for full schema.

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
├── planning.md
├── development.md
└── testing.md
```

### Example 2: Feature Development

```
.context/
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
├── planning.md
├── analyzing.md
├── development.md
├── error.md              # Created when errors occurred
├── testing.md
└── images/
```

### Example 4: Milestone-Based Workflow

```
.context/
├── milestone.json        # GitHub milestone context
├── planning.md
├── analyzing.md
├── development.md
├── testing.md
└── images/
```

## Common Pitfalls

### DON'T

1. **No .context folder**: Documenting in random locations
2. **Skipping Task System initialization**: No way to track progress
3. **Creating subfolders**: Keep all .md files in .context/ root (except images/)
4. **Ignoring errors**: Always create error.md when escalation is needed
5. **Multiple context folders**: Only one .context/ per project

### DO

1. **Always create .context/**: Even for small tasks
2. **Document decisions**: Explain WHY, not just WHAT
3. **Update Task System**: Keep task status current
4. **Flat structure**: All .md files in .context/ (images/ only subdirectory)
5. **Log errors**: Create error.md when issues require escalation
6. **Clean up**: Archive or clear .context/ when starting new tasks
