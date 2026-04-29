# Task Folder Examples & Asset Management

## designs/ Directory

Contains design assets: Figma screenshots (.png) captured during PL stage and Pencil mockups (.pen) created via Pencil MCP tools.

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
| Figma Screenshots | Product Manager (PL) | `.context/designs/figma-*.png` | PNG |
| Screenshots | User | `.context/images/screenshot-*.png` | PNG/JPG |
| Diagrams | User | `.context/images/diagram-*.png` | PNG/SVG |
| Build Logs | DV / background Bash | `.context/logs/build-*.log` | plain text |
| Test Logs | QA / test_sim | `.context/logs/test-*.log` | plain text |
| Monitor Streams | Any agent w/ Monitor | `.context/logs/monitor-*.log` | plain text |
| Simulator Logs | DV / QA (launch_app_logs_sim) | `.context/logs/sim-*.log` | plain text |
| Incident Tails | IR / incident-responder | `.context/logs/incident-*.log` | plain text |

**Naming**:
- Pencil: `mockup-[feature]-[screen]-[variant].pen`
- Figma: `figma-[screen]-[node-id].png`

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

> **Note on `planning-N.md`**: each example below shows a single-plan workspace, so the plan file is `planning-0.md`. If PL is invoked again in the same `.context/` (e.g. mid-workflow re-plan), the next plan is written to `planning-1.md`, then `planning-2.md`, and so on — earlier plans are preserved. See `agents/product-manager.md § Plan File Naming`.

### Example 1: Simple Bug Fix (9-stage, low complexity)

```
.context/
├── planning-0.md
├── development.md
├── developer-review.md
└── testing.md
```

### Example 2: Feature Development (9-stage, full)

```
.context/
├── planning-0.md
├── analyzing.md
├── coordination.md
├── development.md
├── developer-review.md
├── testing.md
├── documentation.md
├── complete.md
├── approval.md
└── images/
    └── feature-mockup.png
```

### Example 2a: Feature with Background Build/Test Logs

Runtime capture from `run_in_background` Bash and Monitor-tool streaming lands in `.context/logs/`. Names follow `<kind>-<scope>-<timestamp>.log`.

```
.context/
├── planning-0.md
├── development.md
├── developer-review.md
├── testing.md
├── complete.md
└── logs/
    ├── build-20260420-141522.log           # DV: build_sim run
    ├── test-qa-20260420-143008.log         # QA: test_sim run
    ├── monitor-developer-20260420-142250.log  # Monitor stream during DV
    └── sim-iphone15-20260420-143201.log    # QA: launch_app_logs_sim
```

### Example 2b: Feature with Designer-Generated Pencil Mockups

```
.context/
├── planning-0.md                               # References mockups in Design Requirements
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

### Example 2c: Feature with Figma Design References

```
.context/
├── planning-0.md                               # References Figma screenshots in Design Requirements
├── exploration.md                            # Contains Figma design context summary
├── analyzing.md
├── development.md                            # Uses Figma screenshots as implementation guide
├── testing.md                                # Design comparison results
├── designs/
│   ├── figma-login-screen-42-1.png           # Figma: login screen (node 42:1)
│   ├── figma-login-error-42-5.png            # Figma: error state (node 42:5)
│   └── mockup-login-screen.pen               # Pencil: supplementary mockup
└── images/
```

### Example 3: Security-Critical Feature (11-stage)

```
.context/
├── planning-0.md
├── analyzing.md
├── coordination.md
├── development.md
├── developer-review.md    # DR stage output
├── security-review.md     # SR stage output
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
├── incident-report.md     # IR stage output
├── development.md
├── developer-review.md    # DR stage output
├── testing.md
├── release-prep.md        # RE stage output
└── complete.md
```

### Example 5: Task with Errors

```
.context/
├── planning-0.md
├── analyzing.md
├── development.md
├── errors/
│   ├── developer.md      # DV retries (one section per retry)
│   └── qa-engineer.md    # QA retries (if QA also failed)
├── testing.md
└── images/
```

### Example 6: Milestone-Based Workflow

```
.context/
├── milestone.json        # GitHub milestone context
├── planning-0.md
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
│   ├── planning-0.md
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
