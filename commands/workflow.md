---
name: workflow
description: Initialize a new workflow task with proper folder structure and Task System integration
argument-hint: '<task description> [--milestone:N] [--secure] [--worktree] [--parallel:N]'
model: opus
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, TaskCreate, TaskUpdate, TaskGet, TaskList, Task(igrsoft:product-manager)
---

# Workflow Command

Initialize a new workflow task with proper folder structure and Task System integration.

> **CRITICAL CONSTRAINTS**
> - MUST use TaskCreate/TaskUpdate/TaskGet/TaskList for workflow state. Do NOT use Claude Code's built-in plan mode.
> - Every stage MUST be a Task System task. Do NOT skip TaskCreate.
> - If Task tools are unavailable, STOP and report. Do NOT fall back to alternative planning.

## Usage

```
/workflow --milestone:N              # Execute milestone N issues by priority
/workflow --milestone:N:ISSUE        # Execute specific issue from milestone N
/workflow "Task Title" [options]     # Execute a custom task
```

## Workflow Types

| Type | Stages | Trigger |
|------|--------|---------|
| Standard | PL→AR→TL→DV→QA→DC→FN→ST | `/workflow` |
| Secure | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | `--secure` |
| Emergency | IR→DV→QA→RE→FN | `/emergency` |

See `skills/shared/stage-codes.md` for stage details.

## Options

| Option | Effect |
|--------|--------|
| `--milestone:N` | Execute GitHub milestone N issues |
| `--milestone:N:ISSUE` | Execute specific issue |
| `--parallel:N` | N concurrent tracks (max 5) |
| `--auto-continue` | Skip approval gates |
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|all>` | Target platform |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 10-stage workflow |
| `--worktree` | Use git worktrees for issue isolation (requires --milestone). Configure `worktree.sparsePaths` in settings.json for large repos |

## Examples

```bash
# Milestone mode
/workflow --milestone:1
/workflow --milestone:1 --parallel:3
/workflow --milestone:2:123

# Worktree mode (true parallel isolation)
/workflow --milestone:1 --worktree
/workflow --milestone:1 --worktree --parallel:3

# Standard mode
/workflow "Add dark mode support"
/workflow "Fix login crash" --priority High

# Secure workflow
/workflow "Implement OAuth" --secure

# Emergency
/emergency "Production login failing"
```

## Execution Steps (MANDATORY)

1. **Create context folder**: `mkdir -p .context/images`
2. **Create planning.md** template in `.context/` with requirements, acceptance criteria, success metrics
3. **TaskCreate PL0**: `TaskCreate({ subject: "PL0: Planning", description: "<task description>", metadata: { stage: "PL", agent: "product-manager", workflow_id: "<slug>", priority: "<priority>" } })`
4. **TaskUpdate PL0 to in_progress**: `TaskUpdate({ taskId: "<pl0_id>", status: "in_progress" })`
5. **Delegate to PL agent**: `Task({ subagent_type: "igrsoft:product-manager", prompt: "<planning prompt>" })` — PL0 assesses complexity, creates stage tasks with `metadata.agent`
6. **TaskUpdate PL0 to completed**: `TaskUpdate({ taskId: "<pl0_id>", status: "completed" })`
7. **Present plan and STOP**: Show the user a summary of PL0 results — complexity score, stages created, and key decisions. Then **STOP and wait for user approval** before proceeding.
8. **Execute remaining stages** (only after user approves): Run the orchestrator execution loop (see `skills/workflow/SKILL.md § Orchestrator Execution Loop`)

## Milestone Mode

When using `--milestone:N`, operates in **workspace mode**:

```
.workspaces/
├── orchestrator.json              # Root orchestrator state
└── milestone-{N}/
    └── {issue#}/
        ├── .context/              # Isolated artifacts
        ├── workspace.json         # Workspace state
        └── handoff.md             # Compressed context
```

### Command Flow for --milestone:N

#### Step 1: Initialize Milestone

```bash
# Fetch milestone info
gh api repos/:owner/:repo/milestones/{N} --jq '.title'

# Get issues and check for existing PRs
gh issue list --milestone "{title}" --json number,title,labels,body

# For each issue, check if PR already exists
gh api /repos/:owner/:repo/issues/{issue#}/timeline \
  --jq '[.[] | select(.event == "cross-referenced" and .source.issue.pull_request)] | length'
# If count > 0, mark as "skipped_has_pr"

# Create orchestrator
mkdir -p .workspaces/milestone-{N}      # Legacy mode
# OR
mkdir -p .worktrees/milestone-{N}        # Worktree mode
# Write orchestrator.json with sorted issues (excluding those with PRs)
```

#### Step 2: Per-Issue Setup (CRITICAL)

For each issue in priority order:

##### Legacy Mode (default)

```bash
# 1. Create workspace
mkdir -p .workspaces/milestone-{N}/{issue#}/.context

# 2. Create branch FROM BASE (using remote to avoid conflicts)
git fetch origin develop
git checkout -b feature/{issue#}-{slug} origin/develop

# 3. Update orchestrator.json → status: "in_progress"
# 4. Execute staged workflow: PL → AR → TL → DV → QA → DC → FN → ST
```

##### Worktree Mode (`--worktree`)

```bash
# 1. Create worktree with dedicated branch (no checkout needed)
git fetch origin develop
git worktree add -b feature/{issue#}-{slug} \
  .worktrees/milestone-{N}/{issue#} origin/develop

# 2. Create .context/ inside worktree
mkdir -p .worktrees/milestone-{N}/{issue#}/.context

# 3. Update orchestrator.json → status: "in_progress", isolation: "worktree"
# 4. Execute staged workflow (all operations inside worktree)
```

#### Step 3: Issue Completion

##### Legacy Mode

```bash
# 1. Commit all changes
git add -A
git commit -m "#{issue} feat: {title}"

# 2. Push branch
git push -u origin feature/{issue#}-{slug}

# 3. Create PR
gh pr create --base develop --title "#{issue} {title}" --body "Closes #{issue}"

# 4. Update orchestrator.json → status: "completed"
# 5. Move to next issue
```

##### Worktree Mode

```bash
# 1. Commit inside worktree
git -C .worktrees/milestone-{N}/{issue#} add -A
git -C .worktrees/milestone-{N}/{issue#} commit -m "#{issue} feat: {title}"

# 2. Push from worktree
git -C .worktrees/milestone-{N}/{issue#} push -u origin feature/{issue#}-{slug}

# 3. Create PR
gh pr create --base develop --title "#{issue} {title}" --body "Closes #{issue}"

# 4. Update orchestrator.json → status: "completed"
# 5. Exit worktree context if EnterWorktree was used
# ExitWorktree tool call
# 6. Remove worktree (branch persists on remote)
git worktree remove .worktrees/milestone-{N}/{issue#}
# Stale worktrees auto-cleaned on startup
```

### Flow Diagram (Legacy — Sequential)

```
/workflow --milestone:1
    │
    ├─→ Create orchestrator.json
    │
    ├─→ Issue #27 (P0)
    │   ├─→ git checkout -b feature/27-watermark
    │   ├─→ PL → AR → TL → DV → QA → DC → FN → ST
    │   ├─→ git push && gh pr create
    │   └─→ Update orchestrator: completed
    │
    └─→ Issue #26 (P1)  ← must wait for #27 (shared worktree)
        ├─→ git fetch origin develop
        ├─→ git checkout -b feature/26-font-family origin/develop
        ├─→ PL → AR → TL → DV → QA → DC → FN → ST
        ├─→ git push && gh pr create
        └─→ Update orchestrator: completed
```

### Flow Diagram (Worktree — Parallel)

```
/workflow --milestone:1 --worktree --parallel:2
    │
    ├─→ Create orchestrator.json (isolation: "worktree")
    │
    ├─→ Issue #27 (P0) ─── PARALLEL ───────────────────────
    │   ├─→ git worktree add -b feature/27-watermark
    │   │     .worktrees/milestone-1/27 origin/develop
    │   ├─→ PL → AR → TL → DV → QA → DC → FN → ST
    │   ├─→ git -C .worktrees/.../27 push && gh pr create
    │   ├─→ git worktree remove .worktrees/.../27
    │   └─→ Update orchestrator: completed
    │
    └─→ Issue #26 (P1) ─── PARALLEL (no branch conflicts!) ─
        ├─→ git worktree add -b feature/26-font-family
        │     .worktrees/milestone-1/26 origin/develop
        ├─→ PL → AR → TL → DV → QA → DC → FN → ST
        ├─→ git -C .worktrees/.../26 push && gh pr create
        ├─→ git worktree remove .worktrees/.../26
        └─→ Update orchestrator: completed
```

**Key improvement**: Both issues execute simultaneously because each has its own worktree with an independent branch. No `git checkout` switching needed.

### Track-Prefixed Task IDs

| Track | Task IDs |
|-------|----------|
| 1 | t1-1, t1-2, t1-3 |
| 2 | t2-1, t2-2, t2-3 |

See `skills/milestone-workflow.md` for full workspace documentation.

## Dynamic Sizing

PL0 assesses complexity (0-50 score) and creates only the needed stages:

| Score | PL0 Creates |
|-------|-------------|
| 0-10 | DV0, QA0 |
| 11-20 | AR0, DV0, QA0 |
| 21-30 | AR0, TL0, DV0, QA0 |
| 31+ | All stages (AR0, TL0, DV0, QA0, DC0, FN0, ST0) |

Stage agents can split into sub-tasks (DV0→DV1, DV2). See `skills/workflow.md`.

## Workflow Modes

### Standard (`/workflow`)
- PL0 created at startup, subsequent stages created by PL after planning
- Dynamic stage creation based on complexity assessment

### Design Auto-Detection

Designer automatically joins PL stage when task description contains UI/UX indicators:
- **UI keywords**: button, form, screen, modal, navigation, menu, layout
- **UX terms**: user flow, accessibility, usability, gesture
- **Visual design**: color, theme, dark mode, typography, animation
- **High-confidence**: "redesign", "new UI", "UI/UX", "design system"

No flag required - design collaboration is context-driven.

### Ethics Review (`--ethics-review`)
Inserts ET stage after PL:
```
PL → ET → AR → TL → DV → QA → DC → FN → ST
```

Recommended for: user tracking, algorithmic recommendations, financial transactions, content moderation.

### Secure (`--secure`, `--full`)
10-stage with SR (Security Review) and RE (Release Engineering):
```
PL → AR → TL → DV → SR → QA → DC → RE → FN → ST
```

Use for: authentication, payments, PII, cryptography, external API secrets.

### Emergency (`/emergency`)
5-stage rapid response:
```
IR → DV → QA → RE → FN
```

## Output

```
Workflow Initiated (Standard)

Task: Add dark mode support
Location: .context/
Mode: Standard (PL0 creates stages after planning)

I've initiated the workflow. Starting PL0...
```

## Next Steps

1. PL0 completes planning.md with requirements
2. PL0 assesses complexity and creates subsequent stage tasks
3. Each stage agent loads its rules and executes the task
4. Agents may split their stage into sub-tasks (DV1, DV2, etc.)

## Related

- `skills/workflow.md` - Complete workflow documentation
- `skills/milestone-workflow.md` - GitHub milestone integration
- `skills/task-folder-organization.md` - Folder structure
- `agents/workflow-engineer.md` - Troubleshooting
