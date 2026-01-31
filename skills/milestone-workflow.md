# Milestone Workflow

**Category**: Task Management
**Priority**: High
**Applies to**: All milestone-based workflows

## Purpose

This skill defines how the workflow system integrates with GitHub milestones to execute issues by priority using **isolated workspaces** for each ticket.

## Parameter Format

```
--milestone:N              # Execute all open issues in milestone N by priority
--milestone:N:ISSUE        # Execute specific issue ISSUE from milestone N only
--parallel:N               # Run N issues in parallel (default: 2, max: 5)
--auto-continue            # Skip per-issue approval gates (trusted workflows)
```

## Workspace Architecture

### Overview

Each ticket executes in its own isolated workspace directory. A root orchestrator monitors and manages execution across all workspaces, enabling true parallel execution without artifact collisions.

### Directory Structure

```
project-root/
├── .workspaces/                           # Workspace orchestration root
│   ├── orchestrator.json                  # Root orchestrator state
│   └── milestone-{N}/                     # Per-milestone container
│       ├── {issue#}/                      # Issue workspace
│       │   ├── .context/                  # Standard workflow artifacts
│       │   │   ├── planning.md
│       │   │   ├── analyzing.md
│       │   │   ├── development.md
│       │   │   ├── testing.md
│       │   │   ├── documentation.md
│       │   │   ├── complete.md
│       │   │   ├── error.md
│       │   │   └── images/
│       │   ├── workspace.json             # Workspace metadata and state
│       │   └── handoff.md                 # Compressed context for orchestrator
│       └── {issue#}/                      # Another issue workspace
│
└── .context/                              # Non-milestone workflows (unchanged)
```

### Orchestrator State (`orchestrator.json`)

**Location:** `.workspaces/orchestrator.json`

The root orchestrator maintains global state across all workspaces:

```json
{
  "version": "2.0",
  "type": "workspace-orchestrator",
  "created_at": "2025-01-27T12:00:00Z",
  "updated_at": "2025-01-27T12:30:00Z",

  "milestone": {
    "number": 1,
    "title": "Sprint 1",
    "description": "...",
    "state": "open",
    "due_on": "2025-02-01T00:00:00Z",
    "html_url": "https://github.com/owner/repo/milestone/1"
  },

  "configuration": {
    "parallel_tracks": 3,
    "auto_continue": false,
    "workspace_root": ".workspaces/milestone-1"
  },

  "issues": [
    {
      "number": 42,
      "title": "Implement login flow",
      "priority": 0,
      "priority_label": "P0",
      "slug": "implement-login-flow",
      "branch_name": "feature/42-implement-login-flow",
      "workspace_path": ".workspaces/milestone-1/42",
      "status": "in_progress",
      "track": 1,
      "current_stage": "DV",
      "started_at": "2025-01-27T12:00:00Z",
      "completed_at": null
    },
    {
      "number": 43,
      "title": "Fix password reset",
      "priority": 1,
      "priority_label": "P1",
      "slug": "fix-password-reset",
      "branch_name": "feature/43-fix-password-reset",
      "workspace_path": ".workspaces/milestone-1/43",
      "status": "in_progress",
      "track": 2,
      "current_stage": "AR",
      "started_at": "2025-01-27T12:05:00Z",
      "completed_at": null
    },
    {
      "number": 44,
      "title": "Add logout button",
      "priority": 1,
      "priority_label": "P1",
      "slug": "add-logout-button",
      "branch_name": "feature/44-add-logout-button",
      "workspace_path": ".workspaces/milestone-1/44",
      "status": "pending",
      "track": null,
      "current_stage": null,
      "started_at": null,
      "completed_at": null
    }
  ],

  "tracks": {
    "1": {
      "issue_number": 42,
      "status": "active",
      "task_prefix": "t1",
      "last_heartbeat": "2025-01-27T12:30:00Z"
    },
    "2": {
      "issue_number": 43,
      "status": "active",
      "task_prefix": "t2",
      "last_heartbeat": "2025-01-27T12:28:00Z"
    },
    "3": {
      "issue_number": null,
      "status": "available",
      "task_prefix": "t3",
      "last_heartbeat": null
    }
  },

  "summary": {
    "total_issues": 3,
    "completed": 0,
    "in_progress": 2,
    "pending": 1,
    "failed": 0
  },

  "execution": {
    "started_at": "2025-01-27T12:00:00Z",
    "estimated_completion": null,
    "last_orchestrator_check": "2025-01-27T12:30:00Z"
  }
}
```

### Workspace State (`workspace.json`)

**Location:** `.workspaces/milestone-{N}/{issue#}/workspace.json`

Each workspace maintains its own isolated state:

```json
{
  "version": "1.0",
  "type": "ticket-workspace",
  "created_at": "2025-01-27T12:00:00Z",
  "updated_at": "2025-01-27T12:25:00Z",

  "issue": {
    "number": 42,
    "title": "Implement login flow",
    "body": "As a user, I want to login securely...",
    "labels": ["feature", "P0"],
    "milestone_number": 1
  },

  "git": {
    "branch_name": "feature/42-implement-login-flow",
    "branch_created": true,
    "base_branch": "develop",
    "base_branch_source": "develop_fallback",
    "commits": []
  },

  "workflow": {
    "workflow_id": "milestone-1-issue-42",
    "track": 1,
    "task_prefix": "t1",
    "stages_enabled": ["PL", "AR", "DV", "QA"],
    "stages_deleted": ["TL", "DC", "FN", "ST"],
    "complexity_score": 18,
    "model_hint": "sonnet"
  },

  "execution": {
    "current_stage": "DV",
    "stage_history": [
      {"stage": "PL", "status": "completed", "started": "...", "completed": "...", "task_id": "t1-1"},
      {"stage": "AR", "status": "completed", "started": "...", "completed": "...", "task_id": "t1-2"},
      {"stage": "DV", "status": "in_progress", "started": "...", "completed": null, "task_id": "t1-3"}
    ],
    "retry_count": 0,
    "last_error": null
  },

  "task_ids": {
    "PL": "t1-1",
    "AR": "t1-2",
    "DV": "t1-3",
    "QA": "t1-4"
  },

  "artifacts": {
    "planning.md": true,
    "analyzing.md": true,
    "development.md": false,
    "testing.md": false
  },

  "orchestrator_sync": {
    "last_reported_stage": "DV",
    "last_sync_at": "2025-01-27T12:25:00Z"
  }
}
```

## GitHub CLI Commands

```bash
# Fetch milestone metadata
gh api /repos/{owner}/{repo}/milestones/{N}

# Fetch all open issues in milestone
gh api "/repos/{owner}/{repo}/issues?milestone={N}&state=open&per_page=100"

# Fetch specific issue
gh api /repos/{owner}/{repo}/issues/{ISSUE}
```

## Priority Sorting

Issues are sorted by priority labels before execution:

**Priority Order (highest first):**
1. `P0` or `priority:critical`
2. `P1` or `priority:high`
3. `P2` or `priority:medium`
4. `P3` or `priority:low`
5. No priority label (lowest)

**Sorting Algorithm:**
```typescript
const priorityOrder = {
  'P0': 0, 'priority:critical': 0,
  'P1': 1, 'priority:high': 1,
  'P2': 2, 'priority:medium': 2,
  'P3': 3, 'priority:low': 3
};

issues.sort((a, b) => {
  const aPriority = Math.min(...a.labels.map(l => priorityOrder[l.name] ?? 99));
  const bPriority = Math.min(...b.labels.map(l => priorityOrder[l.name] ?? 99));
  return aPriority - bPriority;
});
```

## Branch Naming Convention

**Format:** `feature/{issue#}-{slug}`

**Slug Generation Rules:**
1. Lowercase title
2. Replace spaces with hyphens
3. Remove special characters (except hyphens)
4. Truncate to 50 characters max
5. Remove trailing hyphens

**Examples:**
| Issue # | Title | Branch |
|---------|-------|--------|
| 42 | Implement login flow | `feature/42-implement-login-flow` |
| 43 | Fix password reset | `feature/43-fix-password-reset` |
| 44 | [URGENT] Fix critical bug!!! | `feature/44-urgent-fix-critical-bug` |

## Base Branch Resolution

Each issue can specify its own base branch for feature branch creation and PR targets. The resolution follows a per-issue fallback chain.

### Resolution Priority

1. **Issue Body Field**: Parse `base_branch: <branch>` from issue body
2. **Develop Fallback**: If `develop` branch exists on remote
3. **Master Default**: Fall back to `master`

### Issue Body Format

Add the following line anywhere in the GitHub issue body to specify the base branch:

```
base_branch: develop
```

Or target a specific release branch:

```
base_branch: release/2.0
```

### Resolution Implementation

```bash
# Step 1: Parse issue body for base_branch field
base_branch=$(echo "$issue_body" | grep -oP '^base_branch:\s*\K\S+' | head -1)

# Step 2: If not found or invalid, check if develop exists
if [ -z "$base_branch" ] || ! git ls-remote --heads origin "$base_branch" | grep -q "$base_branch"; then
  if git ls-remote --heads origin develop | grep -q develop; then
    base_branch="develop"
    source="develop_fallback"
  else
    base_branch="master"
    source="master_default"
  fi
else
  source="issue_body"
fi
```

### Workspace Integration

The resolved base branch is stored in `workspace.json`:

```json
{
  "git": {
    "branch_name": "feature/42-implement-login-flow",
    "base_branch": "develop",
    "base_branch_source": "develop_fallback"
  }
}
```

**Source Values:**
| Source | Meaning |
|--------|---------|
| `issue_body` | From `base_branch:` field in issue body |
| `develop_fallback` | `develop` branch exists on remote |
| `master_default` | Default fallback to `master` |

### PR Creation

PRs are created targeting the resolved base branch:

```bash
gh pr create \
  --base {base_branch} \
  --title "{issue.title}" \
  --body "Closes #{issue.number}"
```

## Orchestrator Pattern

### Initialization Sequence

```
1. USER INVOKES: /workflow --milestone:N --parallel:3

2. ORCHESTRATOR SETUP:
   a. Create .workspaces/milestone-{N}/ directory
   b. Fetch milestone and issues from GitHub
   c. Sort issues by priority
   d. Create orchestrator.json with configuration
   e. Create orchestrator task: TaskCreate({ taskId: "orch-1", ... })

3. WORKSPACE INITIALIZATION (for first N issues where N = parallel_tracks):
   For each issue in first N:
   a. Create workspace directory: .workspaces/milestone-{N}/{issue#}/
   b. Create workspace.json with issue metadata
   c. Create .context/ subdirectory
   d. Create track-prefixed tasks (t1-1, t1-2, ... for track 1)
   e. Set up task dependencies
   f. Create and checkout git branch: feature/{issue#}-{slug}
   g. Start PL stage: TaskUpdate({ taskId: "t{track}-1", status: "in_progress" })

4. PARALLEL EXECUTION BEGINS:
   - Track 1: Issue #42 → PL stage starts
   - Track 2: Issue #43 → PL stage starts
   - Track 3: Issue #44 → PL stage starts
```

### Monitoring Loop

The orchestrator periodically monitors workspace status:

```
ORCHESTRATOR MONITORING CYCLE:

1. CHECK TRACK STATUS:
   For each active track:
   a. Read workspace.json for current state
   b. Check Task System for task status
   c. Update orchestrator.json with latest state

2. HANDLE COMPLETED TRACKS:
   If a track has completed its workflow:
   a. Mark issue as completed in orchestrator.json
   b. PR should already be created by FN stage
   c. Free up track for next pending issue

3. ASSIGN PENDING ISSUES:
   If available tracks and pending issues:
   a. Get next highest-priority pending issue
   b. Initialize workspace for issue
   c. Assign to available track
   d. Start PL stage for new workspace

4. HANDLE ERRORS:
   If a workspace reports error:
   a. Check retry count vs max (3)
   b. If retries available: Allow workspace to retry
   c. If max retries: Escalate within workspace or pause track
   d. Update orchestrator.json with error state

5. APPROVAL GATES (unless --auto-continue):
   When track completes PL3 (planning):
   a. STOP AND ASK: "Track 1 (Issue #42) planning complete. Continue? [Y/n/skip]"
   b. Wait for user response
   c. Resume approved tracks, skip/pause others
```

### Task System Integration

Track-prefixed task IDs enable parallel execution without collisions:

```
Root Tasks (Orchestrator Level):
├── "orch-1": Milestone 1 Orchestrator (in_progress)

Track 1 Tasks (Issue #42):
├── "t1-1": P: Planning - Issue #42 (completed)
├── "t1-2": A: Architecture - Issue #42 (completed)
├── "t1-3": D: Development - Issue #42 (in_progress)
└── "t1-4": Q: QA Testing - Issue #42 (pending, blocked by t1-3)

Track 2 Tasks (Issue #43):
├── "t2-1": P: Planning - Issue #43 (completed)
├── "t2-2": A: Architecture - Issue #43 (in_progress)
├── "t2-3": D: Development - Issue #43 (pending, blocked by t2-2)
└── "t2-4": Q: QA Testing - Issue #43 (pending, blocked by t2-3)
```

**Task Creation Pattern:**

```typescript
function initializeWorkspaceTasks(issueNumber: number, track: number, milestoneNumber: number) {
  const prefix = `t${track}`;
  const workflowId = `milestone-${milestoneNumber}-issue-${issueNumber}`;
  const workspacePath = `.workspaces/milestone-${milestoneNumber}/${issueNumber}`;

  // Create tasks with track-prefixed IDs
  TaskCreate({
    taskId: `${prefix}-1`,
    subject: `PL: Planning - Issue #${issueNumber}`,
    description: `Define requirements for issue #${issueNumber}`,
    activeForm: "Planning requirements",
    metadata: {
      stage: "PL",
      workflow_id: workflowId,
      issue_number: issueNumber,
      milestone_number: milestoneNumber,
      track: track,
      workspace_path: workspacePath
    }
  });

  // Create AR, DV, QA tasks similarly with appropriate task_ids
  // t{track}-2 for AR, t{track}-3 for DV, t{track}-4 for QA, etc.

  // Set up dependencies within this track
  TaskUpdate({ taskId: `${prefix}-2`, addBlockedBy: [`${prefix}-1`] });
  TaskUpdate({ taskId: `${prefix}-3`, addBlockedBy: [`${prefix}-2`] });
  TaskUpdate({ taskId: `${prefix}-4`, addBlockedBy: [`${prefix}-3`] });
}
```

## Execution Flow

### All Issues Mode: `/workflow --milestone:N`

```
1. FETCH MILESTONE
   gh api /repos/{owner}/{repo}/milestones/N
   gh api "/repos/{owner}/{repo}/issues?milestone=N&state=open"

2. CREATE ORCHESTRATOR
   - Create .workspaces/milestone-{N}/ directory
   - Sort issues by priority
   - Create orchestrator.json
   - Set parallel_tracks from --parallel:N (default: 2)
   - Set auto_continue from --auto-continue flag

3. INITIALIZE FIRST N WORKSPACES (N = parallel_tracks):
   For each issue:
   a. Create workspace directory
   b. Create workspace.json with issue context
   c. Create .context/ with images/ subdirectory
   d. Create and checkout branch: feature/{issue#}-{slug}
   e. Create track-prefixed tasks
   f. Start PL stage

4. PARALLEL EXECUTION:
   Each workspace executes independently:
   - Agents read workspace.json for context
   - Write artifacts to workspace's .context/
   - Update track-prefixed task status

5. TRACK COMPLETION:
   When a workspace completes:
   a. PR created from workspace branch
   b. Track freed in orchestrator
   c. Next pending issue assigned to track
   d. New workspace initialized

6. MILESTONE COMPLETION:
   - All issues processed
   - All PRs created
```

### Single Issue Mode: `/workflow --milestone:N:ISSUE`

```
1. FETCH MILESTONE + SPECIFIC ISSUE
   gh api /repos/{owner}/{repo}/milestones/N
   gh api /repos/{owner}/{repo}/issues/ISSUE

2. VALIDATE
   - Confirm issue.milestone.number === N
   - Error if issue not in milestone

3. CREATE SINGLE WORKSPACE
   - Create .workspaces/milestone-{N}/{ISSUE}/
   - Create workspace.json with issue context
   - Set parallel_tracks to 1

4. EXECUTE SINGLE ISSUE
   a. Create and checkout branch: feature/{ISSUE}-{slug}
   b. Run workflow stages (PL → ... → QA)
   c. Create PR linking to issue (Closes #ISSUE)

5. COMPLETION
   - Single issue processed
   - PR created
```

### Per-Issue Approval Gate

**DEFAULT BEHAVIOR**: Stop after PL stage for user approval.

```typescript
// After PL stage completes in a workspace:
// STOP AND ASK: "Track 1 (Issue #42) planning complete. Continue? [Y/n/skip]"
// Wait for user response:
// - Y/yes → Continue to AR stage
// - n/no → Pause track
// - skip → Skip issue, free track for next
```

**`--auto-continue` flag**: Skip approval gates for trusted workflows.

### Multi-Issue Parallelism

```
Timeline with --parallel:3 on 5 issues:

Time    Track 1 (#42, P0)    Track 2 (#43, P1)    Track 3 (#44, P1)
─────   ─────────────────    ─────────────────    ─────────────────
T+0     P: Planning          P: Planning          P: Planning
T+5     [PL3 Gate]            [PL3 Gate]            [PL3 Gate]
T+6     A: Architecture      A: Architecture      A: Architecture
T+10    D: Development       D: Development       D: Development
T+20    Q: QA Testing        D: (continues)       D: (continues)
T+25    F: Finalization      Q: QA Testing        Q: QA Testing
T+28    COMPLETE             COMPLETE             COMPLETE
        ↓ Track 1 freed      ↓ Track 2 freed      ↓ Track 3 freed
T+30    Starts #45 (P2)      Starts #46 (P2)      (No more issues)
```

**Time savings:**
| Tracks | 5 issues | Time | Savings |
|--------|----------|------|---------|
| 1 (sequential) | 5 × 1h = 5h | 5 hours | — |
| 2 (default) | 3 × 1h = 3h | 3 hours | 40% |
| 5 (max) | 1 × 1h = 1h | 1 hour | 80% |

## Git Integration

### Per-Workspace Branch Checkout

Each workspace operates on its own feature branch created from the resolved base branch:

```bash
# During workspace initialization - checkout from resolved base branch
git checkout {base_branch}
git pull origin {base_branch}
git checkout -b feature/{issue#}-{slug}

# All commits within workspace go to this branch
git add .
git commit -m "#{issue#} feat: implement login flow"

# PR created from workspace branch targeting the base branch
git push -u origin feature/{issue#}-{slug}
gh pr create --base {base_branch} --title "Issue title" --body "Closes #{issue#}"
```

The `{base_branch}` is resolved per-issue (see Base Branch Resolution section above).

### Branch Management

- Branch created during workspace initialization
- All work committed to workspace branch
- PR created from workspace branch during FN stage
- Parallel workspaces work on separate branches simultaneously

## Stage Integration

### P Stage (Planning)

When in workspace context:
- Read issue body from `workspace.json`
- Use issue labels for type/priority classification
- Write `planning.md` to workspace's `.context/`
- Update `workspace.json` with stage completion

### D Stage (Development)

When in workspace context:
- Workspace branch already checked out
- Write artifacts to workspace's `.context/`
- Commit changes to workspace branch
- Reference issue in commit messages (`#{issue#}`)

### F Stage (Finalization)

When in workspace context:
- Push workspace branch to remote
- Create PR with "Closes #{issue#}" in body
- Update `workspace.json` with completion status
- Write compressed handoff to `handoff.md`
- Signal orchestrator that track is complete
- Archive `.context/` to `.context.archive/{timestamp}/`

## Context Lifecycle

### Automatic Archival After PR

Context is automatically archived after PR creation to:
1. Keep AI agent context manageable for subsequent issues
2. Preserve artifacts for reference if needed
3. Ensure fresh context for any follow-up work

| Event | Action | Location |
|-------|--------|----------|
| PR Created | Archive `.context/` | `.context.archive/{timestamp}/` |
| Issue Complete | Preserve archive | Workspace retained |
| Milestone Complete | Archive all | `.workspaces/archive/` |

### What Gets Archived
- All `.context/` contents (planning.md, analyzing.md, complete.md, etc.)
- Stage artifacts and temporary analysis files
- Images and generated diagrams

### What Gets Preserved (Not Archived)
- `handoff.md` - Orchestrator summary
- `workspace.json` - Issue metadata and state
- Git branch and PR references

### Accessing Archived Context

If needed, archived context is available at:
```
.workspaces/milestone-{N}/{issue#}/.context.archive/{timestamp}/
```

### Fresh Agent Context Per Issue

To avoid context window limits when processing multiple issues:
- Orchestrator delegates each issue to a fresh subagent via Task tool
- Each subagent starts with clean context (~1000 tokens)
- `workspace.json` provides persistent state across agents
- Previous issue's conversation history is NOT carried over

## Error Handling

### Per-Workspace Error Isolation

Each workspace has its own error context:

| Error Type | Workspace Action | Orchestrator Action |
|------------|------------------|---------------------|
| Transient | Retry (3x) | Monitor, no intervention |
| Logic | Fix and retry (2x) | Monitor, no intervention |
| Dependency | Escalate to previous stage | Pause track, alert user |
| Requirements | Escalate to PL stage | Pause track, return to planning |
| Fatal | Mark workspace failed | Free track, alert user |

### Error State in workspace.json

```json
{
  "execution": {
    "current_stage": "DV",
    "retry_count": 2,
    "last_error": {
      "type": "logic",
      "message": "Build failed: missing dependency",
      "stage": "DV",
      "timestamp": "2025-01-27T12:25:00Z",
      "resolution_attempted": "Added missing import"
    }
  }
}
```

### Global Error Handling

| Error | Handling |
|-------|----------|
| Milestone not found (404) | Error: "Milestone N not found" |
| Issue not found (404) | Error: "Issue ISSUE not found" |
| Issue not in milestone | Error: "Issue ISSUE is not part of milestone N" |
| Rate limit (403) | Retry with backoff, warn user |
| No repo detected | Error: "Not in git repo. --milestone requires GitHub" |
| Invalid format | Error: "Invalid format. Use --milestone:N or --milestone:N:ISSUE" |

## Issue Status Values

- `pending` - Not yet started, no workspace created
- `in_progress` - Workspace active, being worked on
- `completed` - PR created, workspace done
- `skipped` - Manually skipped by user
- `failed` - Failed after max retries

## Related

- [Workflow Command](../commands/workflow.md) - Main workflow command
- [Workflow System](workflow.md) - Core workflow documentation
- [Task Folder Organization](task-folder-organization.md) - Folder structure
- [workflow-engineer](../agents/workflow-engineer.md) - Orchestrator troubleshooting
