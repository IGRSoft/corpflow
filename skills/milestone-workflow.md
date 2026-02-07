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

Each ticket executes in its own isolated workspace:

```
.workspaces/
├── orchestrator.json              # Root orchestrator state
└── milestone-{N}/
    └── {issue#}/
        ├── .context/              # Standard workflow artifacts
        ├── workspace.json         # Workspace metadata and state
        └── handoff.md             # Compressed context for orchestrator
```

### Orchestrator State (Required Schema)

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

```bash
# Workspace initialization
git checkout {base_branch}
git checkout -b feature/{issue#}-{slug}

# PR creation (FN stage)
git push -u origin feature/{issue#}-{slug}
gh pr create --base {base_branch} --body "Closes #{issue#}"
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

### Hook Events for Team Monitoring

| Hook Event | Lead Action |
|------------|-------------|
| `TeammateIdle` | Assign next pending issue or clean up team |
| `TaskCompleted` | Update orchestrator.json, check milestone progress |

## Related

- `workflow.md` - Core workflow documentation
- `shared/stage-codes.md` - Stage code reference
- `shared/task-system.md` - Task System integration
