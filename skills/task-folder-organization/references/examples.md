# Task Folder Examples & Asset Management

## designs/ Directory

Contains Designer-generated .pen mockups created via Pencil MCP tools.

## images/ Directory

Contains user-attached screenshots, diagrams, and other visual references.

## Agent-Generated Pencil Mockups

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

## Folder Structure Examples

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
