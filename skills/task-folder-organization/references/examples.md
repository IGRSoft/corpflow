# Task Folder Examples & Asset Management

## designs/ Directory

Contains design assets: Figma screenshots (.png) captured during PL stage and Pencil mockups (.pen) created via Pencil MCP tools.

## images/ Directory

Contains user-attached screenshots, diagrams, and other visual references.

## Agent-Generated Pencil Mockups

The Designer agent generates .pen design mockups for UI-related tasks using the Pencil MCP server and saves them to `.context/designs/`.

**Worktask:**
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
- Figma: `figma-[screen]-[state]-[node-id].png`

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

When a user attaches images during a worktask task, copy them to `.context/images/`.

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

> **Note on `planning-N.md`**: each example below shows a single-plan workspace (run 0), so the plan file is `planning-0.md` and all stage artifacts use suffix `-0`. If PL reruns (e.g. mid-worktask re-plan), N increments and all downstream artifacts for that run use the new suffix. Earlier runs are preserved. See `agents/product-manager.md § Plan File & Run Index Naming`.

### Example 1: Simple Bug Fix (9-stage, low complexity)

```
.context/
├── planning-0.md
├── development-0.md
├── developer-review-0.md
└── testing-0.md
```

### Example 2: Feature Development (9-stage, full)

```
.context/
├── planning-0.md
├── analyzing-0.md
├── coordination-0.md
├── development-0.md
├── developer-review-0.md
├── testing-0.md
├── documentation-0.md
├── complete-summary-0.md
├── retrospective-0.md
└── images/
    └── feature-mockup.png
```

### Example 2a: Feature with Background Build/Test Logs

Runtime capture from `run_in_background` Bash and Monitor-tool streaming lands in `.context/logs/`. Names follow `<kind>-<scope>-<timestamp>.log`.

```
.context/
├── planning-0.md
├── development-0.md
├── developer-review-0.md
├── testing-0.md
├── complete-summary-0.md
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
├── analyzing-0.md                              # Reviews mockup feasibility
├── coordination-0.md
├── development-0.md                            # Uses mockups as implementation guide
├── testing-0.md                                # Validates against mockups
├── documentation-0.md
├── complete-summary-0.md
├── retrospective-0.md
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
├── exploration.md                              # Contains Figma design context summary
├── analyzing-0.md
├── development-0.md                            # Uses Figma screenshots as implementation guide
├── testing-0.md                                # Design comparison results
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
├── analyzing-0.md
├── coordination-0.md
├── development-0.md
├── developer-review-0.md
├── security-review-0.md
├── testing-0.md
├── documentation-0.md
├── release-0.md
├── complete-summary-0.md
├── retrospective-0.md
└── images/
    ├── auth-flow.png
    └── security-diagram.png
```

### Example 4: Emergency Hotfix (emergency worktask)

```
.context/
├── incident-0.md
├── development-0.md
├── developer-review-0.md
├── testing-0.md
├── release-0.md
└── complete-summary-0.md
```

### Example 5: Task with Errors

```
.context/
├── planning-0.md
├── analyzing-0.md
├── development-0.md
├── errors/
│   ├── developer.md      # DV retries (one section per retry)
│   └── qa-engineer.md    # QA retries (if QA also failed)
├── testing-0.md
└── images/
```

### Example 6: Milestone-Based Worktask

```
.context/
├── milestone.json        # GitHub milestone context
├── planning-0.md
├── analyzing-0.md
├── development-0.md
├── testing-0.md
└── images/
```

### Example 7: Milestone Worktask (Worktree-Isolated)

In milestone mode, `.context/` lives inside each worktree (always):

```
.worktrees/milestone-1/42/              # Git worktree root (full source copy)
├── .context/                            # Worktask artifacts
│   ├── planning-0.md
│   ├── analyzing-0.md
│   ├── development-0.md
│   ├── testing-0.md
│   └── designs/
├── workspace.json                       # Workspace metadata (isolation: "worktree")
├── handoff.md                           # Compressed context
├── src/                                 # Source code (worktree copy)
├── tests/                               # Tests (worktree copy)
└── Package.swift                        # Build config (worktree copy)
```

**Key difference**: In worktree mode, the project source files are duplicated inside each issue directory. This provides complete source-level isolation but uses more disk space.

### Example 8: Multi-Run Same `.context/`

When PL reruns (scope change, re-plan), artifacts from all runs coexist. `state.json`, `errors/`, and `logs/` are shared.

```
.context/
├── planning-0.md           # Original plan (run 0)
├── analyzing-0.md
├── development-0.md
├── testing-0.md
├── complete-summary-0.md
├── planning-1.md           # Re-plan (run 1, scope change)
├── analyzing-1.md
├── development-1.md
├── testing-1.md
├── complete-summary-1.md
├── state.json              # Shared ledger (reset per run, patches accumulate)
├── errors/
│   └── developer.md        # Errors from any run
└── logs/
    └── build-*.log
```
