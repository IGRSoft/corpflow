# Milestone Initialization & Workflow Setup

## Milestone Initialization

When `--milestone:N` is specified:

### 1. Fetch Milestone Issues

```bash
# Get milestone info
gh api repos/:owner/:repo/milestones/{N} --jq '.title'

# Get all open issues
gh issue list --milestone "{title}" --json number,title,labels,body
```

### 2. Filter Issues with Existing PRs

Skip issues that already have linked PRs:

```bash
# Check for linked PRs on each issue
gh api /repos/:owner/:repo/issues/{issue#}/timeline --jq '[.[] | select(.event == "cross-referenced" and .source.issue.pull_request)] | length'
```

If count > 0, mark issue as `skipped_has_pr` and exclude from workflow.

### 3. Sort by Priority

| Priority | Label | Order |
|----------|-------|-------|
| Critical | P0, priority:critical | 1 |
| High | P1, priority:high | 2 |
| Medium | P2, priority:medium | 3 |
| Low | P3, priority:low | 4 |
| None | (unlabeled) | 5 |

### 4. Per-Issue Workspace Setup

For each issue in priority order:

#### Legacy Mode (default)

```bash
# Create isolated workspace
mkdir -p .workspaces/milestone-{N}/{issue#}/.context

# CRITICAL: Create branch from base (using remote to avoid conflicts)
git fetch origin develop  # or base branch from issue body
git checkout -b feature/{issue#}-{slug} origin/develop
```

#### Worktree Mode (`--worktree`)

```bash
# Create worktree with dedicated branch (no checkout switching needed)
git fetch origin develop
git worktree add -b feature/{issue#}-{slug} \
  .worktrees/milestone-{N}/{issue#} origin/develop

# Create .context/ inside worktree
mkdir -p .worktrees/milestone-{N}/{issue#}/.context
```

**Key difference**: No `git checkout` needed. Each worktree has its own branch checked out independently. Multiple issues can run truly in parallel without branch conflicts.

### 5. Initialize Orchestrator

Create orchestrator.json to track all issues.

#### Legacy Mode

Location: `.workspaces/orchestrator.json`

```json
{
  "version": "2.0",
  "milestone_number": 1,
  "milestone_title": "Sprint 2025-W05",
  "parallel_tracks": 2,
  "base_branch": "develop",
  "created_at": "2026-01-31T10:00:00Z",
  "issues": [
    {
      "number": 27,
      "title": "feat: Add watermark support",
      "priority": "P0",
      "status": "pending",
      "track": null,
      "branch": "feature/27-watermark-support",
      "workspace": ".workspaces/milestone-1/27"
    }
  ]
}
```

#### Worktree Mode

Location: `.worktrees/orchestrator.json`

```json
{
  "version": "3.0",
  "milestone_number": 1,
  "milestone_title": "Sprint 2025-W05",
  "parallel_tracks": 3,
  "isolation": "worktree",
  "base_branch": "develop",
  "created_at": "2026-02-23T10:00:00Z",
  "issues": [
    {
      "number": 27,
      "title": "feat: Add watermark support",
      "priority": "P0",
      "status": "pending",
      "track": null,
      "branch": "feature/27-watermark-support",
      "workspace": ".worktrees/milestone-1/27",
      "isolation": "worktree"
    }
  ]
}
```

### 6. Execute Per-Issue Workflow

Each issue runs the full staged workflow independently:

```
Issue #27 → feature/27-watermark → PL→AR→TL→DV→QA→DC→FN→ST → PR → complete
Issue #26 → feature/26-font-family → PL→AR→TL→DV→QA→DC→FN→ST → PR → complete
```

See `shared/milestone-helpers.md` for helper functions.

## Workflow Initialization

```typescript
const workflowId = "dark-mode-2025";
const stages = ["PL", "AR", "TL", "DV", "QA", "DC", "FN", "ST"];
const stageNames = { PL: "Planning", AR: "Architecture", TL: "Team Lead", DV: "Development", QA: "QA Testing", DC: "Documentation", FN: "Finalization", ST: "Stakeholder" };

// Create tasks
stages.forEach((code, i) => {
  TaskCreate({
    subject: `${code}: ${stageNames[code]}`,
    description: `Stage ${i + 1}`,
    activeForm: `Working on ${stageNames[code]}`,
    metadata: { stage: code, workflow_id: workflowId, priority: "medium" }
  });
});

// Chain dependencies: 2←1, 3←2, ..., 8←7
for (let i = 2; i <= 8; i++) {
  TaskUpdate({ taskId: String(i), addBlockedBy: [String(i - 1)] });
}

// Start first task
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
```
