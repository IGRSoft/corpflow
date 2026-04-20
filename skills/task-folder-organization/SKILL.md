---
name: task-folder-organization
description: Context folder structure (.context/) with artifact naming and path resolution. Use when setting up task folders, organizing workflow artifacts, or resolving artifact paths.
effort: medium
---

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
│   ├── images/         # User-attached screenshots, diagrams
│   ├── errors/         # Per-agent escalation narratives (developer.md, qa-engineer.md, ...)
│   └── logs/           # Runtime capture logs (build, test, monitor, sim, incident)
├── src/
├── tests/
└── ...
```

## Folder Structure

### Flat Layout

All markdown files are stored directly in `.context/` (no subfolders except for `designs/`, `images/`, `errors/`, and `logs/`):

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
├── designs/                 # Design assets: Figma screenshots (.png) and Pencil mockups (.pen)
├── images/                  # User-attached screenshots, diagrams
├── errors/                  # Per-agent escalation narratives (see Per-Agent Error Files)
└── logs/                    # Runtime capture logs: build/test/monitor/sim/incident/hotfix
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
- **errors/**: Per-agent escalation narratives (see below)
- **logs/**: Runtime capture logs (see `logging-conventions` skill)

### Per-Agent Error Files (`errors/`)

`errors/` holds **per-agent escalation narratives** — one file per agent, created on failure. One file per agent prevents parallel stages (QA+DC, TL-split DVN streams, milestone tracks) from clobbering each other and preserves per-agent failure history.

- Filename: `.context/errors/<agent-basename>.md`
- Basename = last `:`-separated segment of `metadata.agent` (e.g., `developer`, `qa-engineer`, `ios-developer` for `apple-developer:ios-developer`)
- Collision fallback: when two plugins would yield the same basename, join with `-`: `apple-developer-ios-developer.md`
- Format: append-only, one `## Retry N — <ts>` section per failure. Machine-readable metadata line after each header (classification, task_id, retry_count).
- Multi-run within same agent (TL split `DV0`/`DV1`/`DV2`): single `developer.md` with per-task sections (`## DV0 Retry 1`, `## DV1 Retry 1`, ...).

### Runtime Logs (`logs/`)

`logs/` holds **raw runtime capture** — background `Bash` stdout, `Monitor`-tool streams, simulator log captures, and incident-investigation tails. It is **distinct from `errors/`**:

| Artifact | Lives At | Contains |
|----------|----------|----------|
| `<agent>.md` | `.context/errors/<agent>.md` | Human/agent-authored escalation narrative (per agent) |
| `*.log`      | `.context/logs/`             | Machine-written raw runtime output |

Filename grammar: `<kind>-<scope>-<timestamp>.log` where `<kind>` ∈ {build, test, monitor, sim, incident, hotfix}. See the `logging-conventions` skill for patterns, examples, and cleanup policy.

### Milestone Context File (`milestone.json`)

Created when `/workflow --milestone:N` is used. Contains:

- **milestone**: GitHub milestone metadata (number, title, due date)
- **issues**: Array of issues sorted by priority with branch names
- **execution**: Current issue, completed/pending arrays
- **summary**: Issue counts and progress

See [Milestone Workflow](milestone-workflow.md) for full schema.

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
| errors/&lt;agent&gt;.md | On error | Owning agent (one file per agent) |
| logs/*.log | Runtime capture | Any agent with Bash/Monitor |

### Documentation Standards

All markdown files should include:

1. **Header**: Task ID, date, author/agent
2. **Purpose**: What this document covers
3. **Content**: Detailed information for the stage
4. **Next Steps**: What comes next
5. **References**: Links to related documents

See references/ for detailed examples of folder structures across workflow variants.

## Common Pitfalls

### DON'T

1. **No .context folder**: Documenting in random locations
2. **Skipping Task System initialization**: No way to track progress
3. **Creating subfolders**: Keep all .md files in .context/ root (except `designs/`, `images/`, `errors/`, and `logs/`)
4. **Ignoring errors**: Always append to `.context/errors/<agent>.md` when escalation is needed
5. **Multiple context folders**: Only one .context/ per project
6. **Wrong .context/ location in worktree mode**: In worktree mode, `.context/` must be inside the worktree directory, not in the main repo's `.workspaces/`
7. **Single shared error file**: Never write to `.context/error.md` — that path is retired. Use per-agent files under `.context/errors/`.

### DO

1. **Always create .context/**: Even for small tasks
2. **Document decisions**: Explain WHY, not just WHAT
3. **Update Task System**: Keep task status current
4. **Flat structure**: All .md files in .context/ (`designs/`, `images/`, `errors/`, and `logs/` are the only subdirectories)
5. **Log errors**: Append to `.context/errors/<agent>.md` (per-agent) when issues require escalation
6. **Clean up**: Archive or clear .context/ when starting new tasks
