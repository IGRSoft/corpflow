---
name: task-folder-organization
description: Context folder structure (.context/) with artifact naming and path resolution. Use when setting up task folders, organizing worktask artifacts, or resolving artifact paths.
effort: medium
version: 0.2.0
---

# Task Folder Organization

**Category**: Task Management
**Priority**: High
**Applies to**: All tasks and features

## Purpose

This rule establishes the required organizational structure for tasks, ensuring consistency, traceability, and effective documentation across all development work.

## The Rule

**Every project MUST have a `.context/` folder** for worktask artifacts with a standardized structure.

### Why `.context/` Folder?

1. **Simplicity**: Single location for all worktask artifacts
2. **Traceability**: Complete audit trail from planning through deployment
3. **Context Preservation**: Future developers can understand decision-making process
4. **State Management**: Clear tracking of progress and completion status
5. **Git Integration**: `.context/` can be gitignored or committed as needed

## Location

The `.context/` folder is located at the project root:

```
project-root/
├── .context/           # Worktask artifacts
│   ├── planning-0.md   # First plan; subsequent runs add planning-1.md, planning-2.md, ...
│   ├── designs/        # CANONICAL Figma asset dir: figma-*.png + figma-registry.md + Pencil .pen mockups
│   ├── images/         # User-attached screenshots + DV implementation screenshots (NOT Figma)
│   ├── errors/         # Per-agent escalation narratives (developer.md, qa-engineer.md, ...)
│   └── logs/           # Runtime capture logs (build, test, monitor, sim, incident)
├── src/
├── tests/
└── ...
```

## Folder Structure

### Flat Layout

All markdown files are stored directly in `.context/` (no subfolders except for `designs/`, `images/`, `errors/`, and `logs/`). Run 0 is shown; see Run-Index Naming below.

#### Stage Artifacts (run-numbered)

```
.context/
├── planning-0.md            # First plan (PL run 0); subsequent runs add planning-1.md, planning-2.md, ...
├── analyzing-0.md           # Technical design, architecture (AR stage)
├── coordination-0.md        # Team coordination (TL stage)
├── development-0.md         # Implementation notes (DV stage)
├── developer-review-0.md    # Code review findings (DR stage)
├── security-review-0.md     # OWASP audit, findings (SR stage)
├── testing-0.md             # Test plan, results (QA stage)
├── documentation-0.md       # Documentation plan (DC stage)
├── release-0.md             # Version, changelog, readiness (RE stage)
├── complete-summary-0.md    # Final validation (FN stage)
├── retrospective-0.md       # Stakeholder sign-off (ST stage)
├── incident-0.md            # Incident triage, RCA (IR stage - emergency)
├── ethics-review-0.md       # Ethics compliance review (ET stage)
```

#### Shared Files & Directories

```
# …continued: .context/ shared, run-independent entries
├── milestone.json           # GitHub milestone context (when run under /megatask)
├── deployment.md            # Deployment plan (if applicable)
├── state.json               # Worktask ledger (shared across runs; re-seeded each PL run)
├── gh-issue.json            # Run-independent .context ↔ GitHub issue anchor (one issue per .context/; see skills/gh-issue-dedup)
├── designs/                 # CANONICAL Figma asset dir: figma-*.png + figma-registry.md + Pencil .pen mockups
├── images/                  # User-attached screenshots + DV implementation screenshots (distinct from designs/)
├── errors/                  # Per-agent escalation narratives (see Per-Agent Error Files)
└── logs/                    # Runtime capture logs: build/test/monitor/sim/incident/hotfix
```

#### Run-Index Naming

Each stage artifact uses the pattern `<basename>-N.md` where N equals `task.metadata.run_index` (integer stamped by PL0 on every downstream task). First run uses N=0. Subsequent PL reruns increment N. `state.json`, `gh-issue.json`, `errors/`, `logs/`, `designs/`, and `images/` are shared across all runs. Note: `state.json` is re-seeded (metadata wiped) each PL run, so the persistent `.context ↔ issue` binding lives in `gh-issue.json`, not `state.json` — this is what lets a follow-up run comment on the existing issue instead of opening a duplicate (`skills/gh-issue-dedup`).

### Multi-Run Layout

When PL0 reruns (e.g. scope change, re-plan), it increments the run index and writes `planning-1.md`, `planning-2.md`, etc. All downstream agents inherit the new N via `task.metadata.run_index` and write `<basename>-1.md`, `<basename>-2.md`, etc. alongside the previous run's files. `state.json`, `errors/`, `logs/`, `designs/`, and `images/` are **always shared** — never duplicated per run.

```
.context/
├── planning-0.md       # Run 0
├── analyzing-0.md
├── development-0.md
├── complete-summary-0.md
├── planning-1.md       # Run 1 (re-plan)
├── analyzing-1.md
├── development-1.md
├── complete-summary-1.md
├── state.json          # Shared (reset + patched each run)
├── gh-issue.json       # Shared (run-independent issue anchor; persists across re-seeds)
├── errors/             # Shared (cumulative across runs)
└── logs/               # Shared (cumulative across runs)
```

### Canonical Figma Asset Directory

**`.context/designs/` is the single canonical directory for all Figma assets** — per-frame screenshots (`figma-*.png`), the design registry (`figma-registry.md`), and Pencil `.pen` mockups all live here. This is the one authoritative location; PM (PL stage), the orchestrator, and QA all reference `.context/designs/` and never disagree.

#### Writers & Readers

- **Writer**: `product-manager` (PL stage) persists Figma PNGs here in-turn via `Bash(curl:*)` and writes `figma-registry.md` (see `agents/product-manager.md § Figma Design Capture`).
- **Reader**: `qa-engineer` (QA stage) reads `figma-registry.md` and compares against each persisted frame file (see `agents/qa-engineer.md § Design Comparison`).
- **`.context/images/` is a distinct directory** — it holds user-attached screenshots/diagrams and DV implementation screenshots (`screenshots.md` manifest), NOT Figma assets. There is no shared-location conflict between the two; do not write Figma screenshots to `images/`.

#### Figma Filename Grammar

Filename grammar for Figma assets: `figma-[screen]-[state]-[node-id].png` (per-frame children use the child name/id; the container overview uses the container name/id). See `agents/product-manager.md § Capture Workflow`.

### Required Files

#### 1. `planning-N.md` (numbered: `planning-0.md`, `planning-1.md`, ...)

Product Manager's planning document containing:
- Problem statement
- Requirements (functional and non-functional)
- Acceptance criteria
- Success metrics
- Constraints and dependencies

### Optional Files (by Worktask Variant)

#### 8-Stage Worktask (standard)

- **analyzing-N.md**: Architecture decisions (AR stage)
- **coordination-N.md**: Team coordination (TL stage)
- **development-N.md**: Implementation notes (DV stage)
- **developer-review-N.md**: Code review findings (DR stage)
- **testing-N.md**: Test plan and results (QA stage)
- **documentation-N.md**: Documentation plan (DC stage)
- **complete-summary-N.md**: Final validation (FN stage)
- **retrospective-N.md**: Stakeholder sign-off (ST stage)

#### 10-Stage Worktask (secure/full)

- All of the above, plus:
- **security-review-N.md**: OWASP audit, security findings (SR stage)
- **release-N.md**: Version, changelog, deployment readiness (RE stage)

#### Emergency Worktask

- **incident-N.md**: Incident triage, RCA (IR stage)
- **development-N.md**: Hotfix implementation (DV stage)
- **testing-N.md**: Regression tests (QA stage)
- **release-N.md**: Hotfix release (RE stage)
- **complete-summary-N.md**: Emergency deployment (FN stage)

#### Always Optional

- **milestone.json**: GitHub milestone context (when run under `/megatask`)
- **deployment.md**: Deployment plan (if applicable)
- **errors/**: Per-agent escalation narratives (see below)
- **logs/**: Runtime capture logs (see `logging-conventions` skill)

### Per-Agent Error Files (`errors/`)

`errors/` holds **per-agent escalation narratives** — one file per agent, created on failure. One file per agent prevents parallel stages (QA+DC, TL-split DVN streams, megatask tracks) from clobbering each other and preserves per-agent failure history.

- Filename: `.context/errors/<agent-basename>.md`
- Basename = last `:`-separated segment of `metadata.agent` (e.g., `developer`, `qa-engineer`, `ios-developer` for `apple-developer:ios-developer`)
- Collision fallback: when two plugins would yield the same basename, join with `-`: `apple-developer-ios-developer.md`
- Format: append-only, one `## Retry N — <ts>` section per failure. Machine-readable metadata line after each header (classification, task_id, retry_count).
- Multi-run within same agent (TL split `DV0`/`DV1`/`DV2`): single `developer.md` with per-task sections (`## DV0 Retry 1`, `## DV1 Retry 1`, ...).

### Runtime Logs (`logs/`)

`logs/` holds **raw runtime capture** — background `Bash` stdout, `Monitor`-tool streams, simulator log captures, and incident-investigation tails — and is **distinct from `errors/`** (narrative escalation per agent).

The canonical `errors/<agent>.md` vs `logs/*.log` split table, filename grammar (`<kind>-<scope>-<timestamp>.log`), examples, and cleanup policy live in the **`logging-conventions`** skill (§The Split). Reference it there rather than restating — avoids drift.

### Milestone Context File (`milestone.json`)

Created when run under `/megatask`. Contains:

- **milestone**: GitHub milestone metadata (number, title, due date)
- **issues**: Array of issues sorted by priority with branch names
- **execution**: Current issue, completed/pending arrays
- **summary**: Issue counts and progress

See [Megatask](../megatask/SKILL.md) for full schema.

## File Organization Guidelines

### Flat Structure by Stage

Files are named by **worktask stage** and stored in `.context/`:

#### Core Stage Files

| File | Stage | Owner |
|------|-------|-------|
| planning-N.md (e.g. planning-0.md) | PL (Planning) | product-manager |
| analyzing-N.md | AR (Architecture) | software-architector |
| coordination-N.md | TL (Team Lead) | team-lead |
| development-N.md | DV (Development) | developer |
| developer-review-N.md | DR (Developer Review) | technical-lead |
| security-review-N.md | SR (Security Review) | security-reviewer |
| testing-N.md | QA (QA Testing) | qa-engineer |
| documentation-N.md | DC (Documentation) | technical-writer |

#### Extended & Shared Files

| File | Stage | Owner |
|------|-------|-------|
| release-N.md | RE (Release Engineering) | release-engineer |
| complete-summary-N.md | FN (Finalization) | project-manager |
| retrospective-N.md | ST (Stakeholder) | stakeholder |
| incident-N.md | IR (Incident Response) | incident-responder |
| ethics-review-N.md | ET (Ethics Review) | ethics-reviewer |
| deployment.md | Optional | deployment-engineer |
| state.json | Shared ledger | All stages |
| errors/&lt;agent&gt;.md | On error | Owning agent (one file per agent) |
| logs/*.log | Runtime capture | Any agent with Bash/Monitor |

### Documentation Standards

All markdown files should include:

1. **Header**: Task ID, date, author/agent
2. **Purpose**: What this document covers
3. **Content**: Detailed information for the stage
4. **Next Steps**: What comes next
5. **References**: Links to related documents

See references/ for detailed examples of folder structures across worktask variants.

## Common Pitfalls

### DON'T

1. **No .context folder**: Documenting in random locations
2. **Skipping Task System initialization**: No way to track progress
3. **Creating subfolders**: Keep all .md files in .context/ root (except `designs/`, `images/`, `errors/`, and `logs/`)
4. **Ignoring errors**: Always append to `.context/errors/<agent>.md` when escalation is needed
5. **Multiple context folders**: Only one .context/ per project
6. **Wrong .context/ location in worktree mode**: `.context/` must be inside the worktree directory (`.worktrees/milestone-{N}/{issue#}/.context/`), not in the main repo root
7. **Single shared error file**: Never write to `.context/error.md` — that path is retired. Use per-agent files under `.context/errors/`.

### DO

1. **Always create .context/**: Even for small tasks
2. **Document decisions**: Explain WHY, not just WHAT
3. **Update Task System**: Keep task status current
4. **Flat structure**: All .md files in .context/ (`designs/`, `images/`, `errors/`, and `logs/` are the only subdirectories)
5. **Log errors**: Append to `.context/errors/<agent>.md` (per-agent) when issues require escalation
6. **Clean up**: Archive or clear .context/ when starting new tasks
