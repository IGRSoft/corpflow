# Milestone Workflow

GitHub milestone integration with isolated workspaces for each ticket.

## Parameter Format

```
--milestone:N              # Execute all open issues by priority
--milestone:N:ISSUE        # Execute specific issue
--parallel:N               # Run N issues in parallel (max 5)
--auto-continue            # Skip per-issue approval gates
```

## Workspace Architecture

Each ticket executes in its own isolated workspace.

### Legacy Mode (default)

```
.workspaces/
├── orchestrator.json              # Root orchestrator state
└── milestone-{N}/
    └── {issue#}/
        ├── .context/              # Standard workflow artifacts
        ├── workspace.json         # Workspace metadata and state
        └── handoff.md             # Compressed context for orchestrator
```

### Worktree Mode (`--worktree`)

Each issue gets a dedicated git worktree with full source isolation:

```
.worktrees/
├── orchestrator.json              # Root orchestrator state
└── milestone-{N}/
    └── {issue#}/                  # Git worktree root (full source copy)
        ├── .git                   # Worktree git link file
        ├── .context/              # Workflow artifacts (inside worktree)
        ├── workspace.json         # Workspace metadata (isolation: "worktree")
        ├── handoff.md             # Compressed context
        ├── src/                   # Full source tree
        └── ...                    # All project files
```

**Key difference**: In worktree mode, the entire source tree exists inside each issue directory. Each worktree has its own branch checked out independently — no `git checkout` switching needed. Multiple issues can execute truly in parallel.

> Add `.worktrees/` to `.gitignore` to prevent worktree contents from appearing as untracked files.

### Orchestrator State (Required Schema)

#### Legacy Mode (version 2.0)

```json
{
  "version": "2.0",
  "milestone": { "number": 1, "title": "Sprint 1" },
  "configuration": { "parallel_tracks": 3, "auto_continue": false },
  "base_branch": "develop",
  "created_at": "2026-01-31T10:00:00Z",
  "issues": [
    {
      "number": 42,
      "title": "feat: Add login flow",
      "priority": "P0",
      "status": "in_progress",
      "track": 1,
      "current_stage": "DV",
      "branch": "feature/42-add-login-flow",
      "workspace": ".workspaces/milestone-1/42"
    },
    {
      "number": 43,
      "title": "feat: Add logout button",
      "priority": "P1",
      "status": "pending",
      "track": null,
      "branch": "feature/43-add-logout-button",
      "workspace": ".workspaces/milestone-1/43"
    }
  ],
  "tracks": {
    "1": { "issue_number": 42, "task_prefix": "t1" },
    "2": { "issue_number": null, "status": "available" }
  },
  "progress": {
    "total": 2,
    "completed": 0,
    "in_progress": 1,
    "pending": 1
  }
}
```

#### Worktree Mode (version 3.0)

```json
{
  "version": "3.0",
  "milestone": { "number": 1, "title": "Sprint 1" },
  "configuration": {
    "parallel_tracks": 3,
    "auto_continue": false,
    "isolation": "worktree"
  },
  "base_branch": "develop",
  "created_at": "2026-02-23T10:00:00Z",
  "issues": [
    {
      "number": 42,
      "title": "feat: Add login flow",
      "priority": "P0",
      "status": "in_progress",
      "track": 1,
      "current_stage": "DV",
      "branch": "feature/42-add-login-flow",
      "workspace": ".worktrees/milestone-1/42",
      "isolation": "worktree"
    }
  ],
  "tracks": {
    "1": { "issue_number": 42, "task_prefix": "t1" },
    "2": { "issue_number": null, "status": "available" }
  },
  "progress": {
    "total": 1,
    "completed": 0,
    "in_progress": 1,
    "pending": 0
  }
}
```

### Status Transitions

```
pending → in_progress → completed
                     → failed
                     → skipped
```

**Starting an issue**:
1. Set `status: "in_progress"`
2. Assign `track: N`
3. Checkout dedicated branch
4. Begin staged workflow (PL → AR → ... → ST)

**Completing an issue**:
1. Push branch to origin
2. Create PR with "Closes #issue"
3. Set `status: "completed"`
4. Free track for next issue

### Workspace State

#### Legacy (version 1.0)

```json
{
  "version": "1.0",
  "issue": { "number": 42, "title": "Add login flow", "labels": ["feature"] },
  "git": { "branch_name": "feature/42-add-login-flow", "base_branch": "develop" },
  "workflow": { "track": 1, "task_prefix": "t1", "complexity_score": 18 },
  "execution": { "current_stage": "DV", "retry_count": 0 },
  "task_ids": { "PL": "t1-1", "AR": "t1-2", "DV": "t1-3", "QA": "t1-4" }
}
```

#### Worktree (version 2.0)

```json
{
  "version": "2.0",
  "isolation": "worktree",
  "issue": { "number": 42, "title": "Add login flow", "labels": ["feature"] },
  "git": {
    "branch_name": "feature/42-add-login-flow",
    "base_branch": "develop",
    "worktree_path": ".worktrees/milestone-1/42"
  },
  "workflow": { "track": 1, "task_prefix": "t1", "complexity_score": 18 },
  "execution": { "current_stage": "DV", "retry_count": 0 },
  "task_ids": { "PL": "t1-1", "AR": "t1-2", "DV": "t1-3", "QA": "t1-4" }
}
```

## Priority Sorting

Issues sorted by priority labels (highest first):
1. `P0` / `priority:critical`
2. `P1` / `priority:high`
3. `P2` / `priority:medium`
4. `P3` / `priority:low`
5. No priority label

## Base Branch Resolution

Per-issue fallback chain:
1. **Issue body**: Parse `base_branch: <branch>` from issue
2. **Develop fallback**: If `develop` exists on remote
3. **Master default**: Fall back to `master`

Stored in `workspace.json` with `base_branch_source`: `issue_body`, `develop_fallback`, or `master_default`.

## Branch Naming

**Format**: `feature/{issue#}-{slug}`

Slug: lowercase title, spaces→hyphens, no special chars, max 50 chars.

## Track-Prefixed Task IDs

```
Track 1: t1-1 (PL), t1-2 (AR), t1-3 (DV), t1-4 (QA)
Track 2: t2-1 (PL), t2-2 (AR), t2-3 (DV), t2-4 (QA)
```

Task creation pattern:
```typescript
TaskCreate({
  taskId: `t${track}-1`,
  subject: `PL: Planning - Issue #${issueNumber}`,
  metadata: {
    stage: "PL", issue_number: issueNumber, track: track,
    workspace_path: `.workspaces/milestone-${milestone}/${issueNumber}`
  }
});
```

## Orchestrator Pattern

### Initialization

1. Create `.workspaces/milestone-{N}/` directory
2. Fetch milestone and issues from GitHub
3. Sort issues by priority, create orchestrator.json
4. Initialize first N workspaces (N = parallel_tracks)
5. Create track-prefixed tasks, start PL stage

### Monitoring Loop

1. **Check tracks**: Read workspace.json for current state
2. **Handle completion**: Free track, assign next pending issue
3. **Handle errors**: Retry within workspace or escalate
4. **Approval gates**: Pause at PL3 unless `--auto-continue`

## Execution Flow

### All Issues: `/workflow --milestone:N`

1. Fetch milestone and issues from GitHub
2. Create orchestrator with sorted issues
3. Initialize first N workspaces in parallel
4. Each workspace executes independently
5. On completion: PR created, track freed, next issue assigned

### Single Issue: `/workflow --milestone:N:ISSUE`

1. Validate issue belongs to milestone
2. Create single workspace
3. Execute workflow stages
4. Create PR with "Closes #ISSUE"

### Multi-Issue Parallelism

| Tracks | 5 issues | Time | Savings |
|--------|----------|------|---------|
| 1 | 5 × 1h | 5h | — |
| 2 | 3 × 1h | 3h | 40% |
| 5 | 1 × 1h | 1h | 80% |

## Git Integration

### Legacy Mode

```bash
# Workspace initialization (sequential — one branch at a time)
git checkout {base_branch}
git checkout -b feature/{issue#}-{slug}

# PR creation (FN stage)
git push -u origin feature/{issue#}-{slug}
gh pr create --base {base_branch} --body "Closes #{issue#}"
```

### Worktree Mode

```bash
# Workspace initialization (parallel — each issue gets own worktree)
git fetch origin {base_branch}
git worktree add -b feature/{issue#}-{slug} \
  .worktrees/milestone-{N}/{issue#} origin/{base_branch}
mkdir -p .worktrees/milestone-{N}/{issue#}/.context

# All git operations use -C flag for worktree path
git -C .worktrees/milestone-{N}/{issue#} add -A
git -C .worktrees/milestone-{N}/{issue#} commit -m "#{issue} feat: {title}"
git -C .worktrees/milestone-{N}/{issue#} push -u origin feature/{issue#}-{slug}
gh pr create --base {base_branch} --body "Closes #{issue#}"

# Cleanup after PR
git worktree remove .worktrees/milestone-{N}/{issue#}
git worktree prune
```

## Stage Integration

| Stage | Workspace Actions |
|-------|-------------------|
| PL | Read issue from workspace.json, write planning.md |
| DV | Branch checked out, commit to workspace branch |
| FN | Push branch, create PR, signal orchestrator |

## Context Lifecycle

| Event | Action |
|-------|--------|
| PR Created | Archive `.context/` to `.context.archive/{timestamp}/` |
| Issue Complete | Preserve workspace.json and handoff.md |
| Milestone Complete | Archive to `.workspaces/archive/` |

Fresh agent context per issue - orchestrator delegates via Task tool, each subagent starts clean.

## Worktree Lifecycle

Applies when `--worktree` flag is used with `--milestone:N`.

### Creation

| Event | Action |
|-------|--------|
| Issue starts (PL) | `git worktree add -b {branch} {path} origin/{base}` |
| Context setup | `mkdir -p {worktree_path}/.context` |
| Metadata | Write `workspace.json` with `isolation: "worktree"`, `version: "2.0"` |

### During Execution

| Event | Action |
|-------|--------|
| Stage work | All file operations happen inside worktree path |
| Git operations | Use `git -C {worktree_path}` prefix |
| Context path | `{worktree_path}/.context/` |
| Builds/tests | Run from worktree directory |
| Commits | Committed to the worktree's branch automatically |

### Cleanup

| Event | Action |
|-------|--------|
| PR created | `git worktree remove {path}` (branch persists on remote) |
| Uncommitted changes | Warn user, preserve worktree |
| Failed issue | Preserve worktree for debugging |
| Milestone complete | `git worktree prune` to remove all stale entries |

### Edge Cases

1. **Uncommitted changes**: `removeIssueWorktree()` checks `git status --porcelain` and refuses removal by default. Pass `force=true` to override.
2. **Failed issues**: Worktree preserved with `status: "failed"` in orchestrator. User can inspect and retry.
3. **Stale worktrees**: If a session crashes, run `git worktree prune` to clean up orphaned entries.
4. **Disk space**: Each worktree duplicates the working tree. For large repos, monitor with `du -sh .worktrees/`.

## Error Handling

| Error Type | Workspace Action | Orchestrator Action |
|------------|------------------|---------------------|
| Transient | Retry (3x) | Monitor |
| Fatal | Mark failed | Free track, alert user |

**Global errors**: Milestone not found, issue not in milestone, rate limit.

## Issue Status Values

- `pending` - Not started
- `in_progress` - Workspace active
- `completed` - PR created
- `skipped` - Manually skipped
- `skipped_has_pr` - Already has linked PR (auto-detected)
- `failed` - Max retries exceeded

## GitHub CLI

```bash
gh api /repos/{owner}/{repo}/milestones/{N}
gh api "/repos/{owner}/{repo}/issues?milestone={N}&state=open"
```

## Agent Teams Mode (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, milestone workflows can use agent teams for true parallel issue execution instead of sequential Task-based orchestration.

### Architecture Comparison

| Aspect | Task-Based Orchestrator | Agent Teams |
|--------|------------------------|-------------|
| Parallelism | Sequential stages, parallel tracks via orchestrator.json | True parallel: each issue is an independent teammate |
| Communication | Via artifacts in .context/ and workspace.json | Direct inter-teammate messaging |
| Context | Shared context window (compressed handoffs) | Independent context per teammate |
| Token cost | Lower (single context window) | Higher (N context windows) |
| Best for | Complex issues with dependencies | Independent issues with clear scope |

### When to Use Agent Teams

**Use agent teams when**:
- Issues are truly independent (no cross-issue dependencies)
- Issues have clear acceptance criteria in the issue body
- Milestone has 3-5 issues (optimal team size)
- Token budget allows parallel sessions

**Stay with Task-based orchestrator when**:
- Issues depend on each other
- Context sharing between issues matters
- Token budget is constrained
- Issues require sequential implementation

### Agent Teams Milestone Pattern

```
Lead Session (workflow-engineer):
  1. Fetch milestone issues
  2. Create agent team with one teammate per issue (max 5)
  3. Each teammate: issue context, workspace path, branch name
  4. Teammates execute independently: PL→DV→QA→FN
  5. Lead monitors via shared task list
  6. Each teammate creates its own PR
  7. Lead synthesizes results and cleans up team
```

### Teammate Spawn Prompt Template

#### Legacy Mode

```
You are working on Issue #{issue_number}: {issue_title}

Workspace: .workspaces/milestone-{N}/{issue_number}
Branch: feature/{issue_number}-{slug}
Base: {base_branch}

Execute the workflow for this issue:
1. Create .context/ directory in your workspace
2. PL: Plan requirements from the issue body
3. DV: Implement the solution
4. QA: Test the implementation
5. FN: Commit, push, and create PR with "Closes #{issue_number}"

Write all artifacts to your workspace .context/ directory.

Issue body:
{issue_body}
```

#### Worktree Mode

```
You are working on Issue #{issue_number}: {issue_title}

Worktree: .worktrees/milestone-{N}/{issue_number}
Branch: feature/{issue_number}-{slug} (already checked out in worktree)
Base: {base_branch}

IMPORTANT: All file operations must happen inside the worktree directory.
The worktree has its own copy of the source tree with the correct branch.
Use `git -C .worktrees/milestone-{N}/{issue_number}` for all git commands.

Execute the workflow for this issue:
1. All artifacts go to .worktrees/milestone-{N}/{issue_number}/.context/
2. PL: Plan requirements from the issue body
3. DV: Implement the solution (source files are in the worktree)
4. QA: Test the implementation (run tests from worktree directory)
5. FN: Commit, push, and create PR with "Closes #{issue_number}"
6. Cleanup: git worktree remove .worktrees/milestone-{N}/{issue_number}

Issue body:
{issue_body}
```

### Worktree + Agent Teams

When both `--worktree` and agent teams are enabled, each teammate operates in its own worktree. This provides the strongest isolation:

- Each teammate has its own git branch checked out in a separate directory
- No branch-switching conflicts between teammates
- Each teammate's `.context/` lives inside its worktree
- Worktrees are cleaned up when each teammate completes its issue

This is the **recommended configuration** for milestone parallel execution when token budget allows it.

### Hook Events for Team Monitoring

| Hook Event | Lead Action | Payload (2.1.69+) |
|------------|-------------|--------------------|
| `TeammateIdle` | Assign next pending issue or clean up team | `agent_id`, `agent_type` |
| `TaskCompleted` | Update orchestrator.json, check milestone progress | `agent_id`, `agent_type` |

Handlers can return `{"continue": false, "stopReason": "..."}` to stop a teammate when its issue is complete or when milestone budget is exhausted.

## Related

- `workflow.md` - Core workflow documentation
- `shared/stage-codes.md` - Stage code reference
- `shared/task-system.md` - Task System integration
