---
name: milestone-workflow
description: GitHub milestone integration with isolated workspaces for multi-issue tracking. Use when running milestone-based workflows with --milestone flag or managing parallel issue tracks.
effort: high
---

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

#### Sparse Checkout

For large monorepos, configure `worktree.sparsePaths` in project `settings.json` to check out only relevant directories:

```json
{
  "worktree": {
    "sparsePaths": ["src/", "tests/", "Package.swift"]
  }
}
```

This reduces disk usage per worktree and speeds up initialization.

> `--worktree` startup reads git refs directly and skips redundant fetch, significantly faster for repos with many branches.

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

See references/ for detailed schemas, git integration commands, and agent teams patterns.

## Related

- `workflow.md` - Core workflow documentation
- `${CLAUDE_SKILL_DIR}/shared/stage-codes.md` - Stage code reference
- `${CLAUDE_SKILL_DIR}/shared/task-system.md` - Task System integration
