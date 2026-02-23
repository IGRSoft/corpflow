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
│   ├── designs/        # Designer-generated .pen mockups
│   └── images/         # User-attached screenshots, diagrams
├── src/
├── tests/
└── ...
```

## Folder Structure

### Flat Layout

All markdown files are stored directly in `.context/` (no subfolders except for `designs/` and `images/`):

```
.context/
├── planning.md              # Requirements, acceptance criteria (PL stage)
├── analyzing.md             # Technical design, architecture (AR stage)
├── coordination.md          # Team coordination (TL stage)
├── development.md           # Implementation notes (DV stage)
├── security-review.md       # OWASP audit, findings (SR stage) [NEW]
├── testing.md               # Test plan, results (QA stage)
├── documentation.md         # Documentation plan (DC stage)
├── release-prep.md          # Version, changelog, readiness (RE stage) [NEW]
├── complete.md              # Final validation (FN stage)
├── approval.md              # Stakeholder sign-off (ST stage)
├── incident-report.md       # Incident triage, RCA (IR stage - emergency) [NEW]
├── milestone.json           # GitHub milestone context (when --milestone used)
├── deployment.md            # Deployment plan (if applicable)
├── error.md                 # Error log for escalations (created on errors)
├── designs/                 # Designer-generated .pen mockups
└── images/                  # User-attached screenshots, diagrams
```

### Required Files

#### 1. `planning.md`

Product Manager's planning document containing:
- Problem statement
- Requirements (functional and non-functional)
- Acceptance criteria
- Success metrics
- Constraints and dependencies

### Optional Files (by Workflow Variant)

**8-Stage Workflow (standard):**
- **analyzing.md**: Architecture decisions (AR stage)
- **coordination.md**: Team coordination (TL stage)
- **development.md**: Implementation notes (DV stage)
- **testing.md**: Test plan and results (QA stage)
- **documentation.md**: Documentation plan (DC stage)
- **complete.md**: Final validation (FN stage)
- **approval.md**: Stakeholder sign-off (ST stage)

**10-Stage Workflow (secure/full):**
- All of the above, plus:
- **security-review.md**: OWASP audit, security findings (SR stage)
- **release-prep.md**: Version, changelog, deployment readiness (RE stage)

**Emergency Workflow:**
- **incident-report.md**: Incident triage, RCA (IR stage)
- **development.md**: Hotfix implementation (DV stage)
- **testing.md**: Regression tests (QA stage)
- **release-prep.md**: Hotfix release (RE stage)
- **complete.md**: Emergency deployment (FN stage)

**Always Optional:**
- **milestone.json**: GitHub milestone context (when `--milestone` used)
- **deployment.md**: Deployment plan (if applicable)
- **error.md**: Error log for escalation scenarios

### Milestone Context File (`milestone.json`)

Created when `/workflow --milestone:N` is used. Contains:

- **milestone**: GitHub milestone metadata (number, title, due date)
- **issues**: Array of issues sorted by priority with branch names
- **execution**: Current issue, completed/pending arrays
- **summary**: Issue counts and progress

See [Milestone Workflow](milestone-workflow.md) for full schema.

### designs/ Directory

Contains Designer-generated .pen mockups created via Pencil MCP tools.

### images/ Directory

Contains user-attached screenshots, diagrams, and other visual references.

### Agent-Generated Pencil Mockups

The Designer agent generates .pen design mockups for UI-related tasks using the Pencil MCP server and saves them to `.context/designs/`.

**Workflow:**
1. Product Manager detects UI work (design score >= 5)
2. Product Manager invokes Designer with mockup request
3. Designer loads Pencil tools via `ToolSearch({ query: "+pencil" })`
4. Designer generates 1-2 .pen mockups for key screens and states
5. Designer validates visually with `get_screenshot()`
6. Designer saves to `.context/designs/mockup-*.pen`
7. Designer references mockups in design documentation
8. Downstream stages use mockups: AR reviews, DV implements, QA validates

**Pencil Mockups vs User-Attached Images:**

| Type | Source | Location | Format |
|------|--------|----------|--------|
| Pencil Mockups | Designer agent | `.context/designs/mockup-*.pen` | .pen (JSON) |
| Screenshots | User | `.context/images/screenshot-*.png` | PNG/JPG |
| Diagrams | User | `.context/images/diagram-*.png` | PNG/SVG |

**Naming**: `mockup-[feature]-[screen]-[variant].pen`

```
.context/
├── designs/
│   ├── mockup-login-screen.pen              # Designer: default state
│   ├── mockup-login-screen-error.pen        # Designer: error state
│   └── mockup-profile-edit-form.pen         # Designer: main screen
└── images/
    ├── screenshot-bug-report.png            # User-attached
    └── diagram-architecture.png             # User-attached
```

**Workspace isolation**: Each workspace has its own `.context/designs/` with isolated mockups.

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
| planning.md | PL (Planning) | product-manager |
| analyzing.md | AR (Architecture) | software-architector |
| coordination.md | TL (Team Lead) | team-lead |
| development.md | DV (Development) | developer |
| **security-review.md** | **SR (Security Review)** | **security-reviewer** |
| testing.md | QA (QA Testing) | qa-engineer |
| documentation.md | DC (Documentation) | technical-writer |
| **release-prep.md** | **RE (Release Engineering)** | **release-engineer** |
| complete.md | FN (Finalization) | project-manager |
| approval.md | ST (Stakeholder) | stakeholder |
| **incident-report.md** | **IR (Incident Response)** | **incident-responder** |
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

### Example 1: Simple Bug Fix (8-stage, low complexity)

```
.context/
├── planning.md
├── development.md
└── testing.md
```

### Example 2: Feature Development (8-stage, full)

```
.context/
├── planning.md
├── analyzing.md
├── coordination.md
├── development.md
├── testing.md
├── documentation.md
├── complete.md
├── approval.md
└── images/
    └── feature-mockup.png
```

### Example 2b: Feature with Designer-Generated Pencil Mockups

```
.context/
├── planning.md                               # References mockups in Design Requirements
├── analyzing.md                              # Reviews mockup feasibility
├── coordination.md
├── development.md                            # Uses mockups as implementation guide
├── testing.md                                # Validates against mockups
├── documentation.md
├── complete.md
├── approval.md
├── designs/
│   ├── mockup-user-profile-main.pen          # Designer: main profile screen
│   ├── mockup-user-profile-edit.pen          # Designer: edit mode
│   └── mockup-user-profile-edit-error.pen    # Designer: validation errors
└── images/
    └── feature-mockup.png
```

### Example 3: Security-Critical Feature (10-stage)

```
.context/
├── planning.md
├── analyzing.md
├── coordination.md
├── development.md
├── security-review.md     # SR stage output [NEW]
├── testing.md
├── documentation.md
├── release-prep.md        # RE stage output [NEW]
├── complete.md
├── approval.md
└── images/
    ├── auth-flow.png
    └── security-diagram.png
```

### Example 4: Emergency Hotfix (emergency workflow)

```
.context/
├── incident-report.md     # IR stage output [NEW]
├── development.md
├── testing.md
├── release-prep.md        # RE stage output
└── complete.md
```

### Example 5: Task with Errors

```
.context/
├── planning.md
├── analyzing.md
├── development.md
├── error.md              # Created when errors occurred
├── testing.md
└── images/
```

### Example 6: Milestone-Based Workflow

```
.context/
├── milestone.json        # GitHub milestone context
├── planning.md
├── analyzing.md
├── development.md
├── testing.md
└── images/
```

### Example 7: Worktree-Based Milestone Workflow

When using `--worktree` with milestones, `.context/` lives inside each worktree:

```
.worktrees/milestone-1/42/              # Git worktree root (full source copy)
├── .context/                            # Workflow artifacts
│   ├── planning.md
│   ├── analyzing.md
│   ├── development.md
│   ├── testing.md
│   └── designs/
├── workspace.json                       # Workspace metadata (isolation: "worktree")
├── handoff.md                           # Compressed context
├── src/                                 # Source code (worktree copy)
├── tests/                               # Tests (worktree copy)
└── Package.swift                        # Build config (worktree copy)
```

**Key difference**: In worktree mode, the project source files are duplicated inside each issue directory. This provides complete source-level isolation but uses more disk space.

## Common Pitfalls

### DON'T

1. **No .context folder**: Documenting in random locations
2. **Skipping Task System initialization**: No way to track progress
3. **Creating subfolders**: Keep all .md files in .context/ root (except designs/ and images/)
4. **Ignoring errors**: Always create error.md when escalation is needed
5. **Multiple context folders**: Only one .context/ per project
6. **Wrong .context/ location in worktree mode**: In worktree mode, `.context/` must be inside the worktree directory, not in the main repo's `.workspaces/`

### DO

1. **Always create .context/**: Even for small tasks
2. **Document decisions**: Explain WHY, not just WHAT
3. **Update Task System**: Keep task status current
4. **Flat structure**: All .md files in .context/ (designs/ and images/ are the only subdirectories)
5. **Log errors**: Create error.md when issues require escalation
6. **Clean up**: Archive or clear .context/ when starting new tasks
