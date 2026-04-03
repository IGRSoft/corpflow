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

Only PL0 is created at startup. PL0 creates all subsequent stage tasks after planning.

```typescript
const workflowId = "dark-mode-2025";

// Create only PL0 — PL agent creates subsequent stages after planning
TaskCreate({
  subject: "PL0: Planning",
  description: "Define requirements, assess complexity, create stage tasks",
  activeForm: "Planning task requirements",
  metadata: { stage: "PL", agent: "product-manager", model: "sonnet", workflow_id: workflowId, priority: "medium" }
});

// Start immediately
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
```

## PL Creates Subsequent Tasks

After planning completes, PL0 creates stage tasks based on complexity score. Each task is self-describing with `metadata.agent` specifying the executor and `metadata.model` specifying the model alias. **Capture returned task IDs** to correctly set up dependency chains.

```typescript
// Example: PL0 creates stages for a medium-complexity task
const workflowId = "dark-mode-2025";

// Capture task IDs returned by TaskCreate
const ar0 = TaskCreate({
  subject: "AR0: Architecture",
  description: "Design dark mode architecture with theme switching",
  activeForm: "Architecting solution",
  metadata: { stage: "AR", agent: "software-architector", model: "opus", workflow_id: workflowId, priority: "medium" }
});

const dv0 = TaskCreate({
  subject: "DV0: Development",
  description: "Implement dark mode theme system and color tokens",
  activeForm: "Implementing code",
  metadata: { stage: "DV", agent: "developer", model: "opus", workflow_id: workflowId, priority: "medium" }
});

const qa0 = TaskCreate({
  subject: "QA0: QA Testing",
  description: "Test theme switching, contrast ratios, persistence",
  activeForm: "Testing solution",
  metadata: { stage: "QA", agent: "qa-engineer", model: "haiku", workflow_id: workflowId, priority: "medium" }
});

// Chain dependencies using captured IDs (PL0 is taskId "1" from initial creation)
TaskUpdate({ taskId: ar0, addBlockedBy: ["1"] });  // AR0 ← PL0
TaskUpdate({ taskId: dv0, addBlockedBy: [ar0] });  // DV0 ← AR0
TaskUpdate({ taskId: qa0, addBlockedBy: [dv0] });  // QA0 ← DV0

// Mark PL0 completed
TaskUpdate({ taskId: "1", status: "completed" });
```

## Task Execution Pattern

When a task starts, the executor reads `metadata.agent` and spawns the agent:

```typescript
const task = TaskGet({ taskId: currentTaskId });
const agentType = task.metadata.agent;  // e.g., "developer"
const model = task.metadata.model;      // e.g., "haiku"

Task({
  subagent_type: `igrsoft:${agentType}`,  // loads agent rules from frontmatter
  model: model,                           // explicit model — do NOT rely on frontmatter inheritance
  prompt: task.description                 // task-specific instructions
});
```

## Stage Sub-Task Splitting

Any stage agent (except PL) can split its work into sub-tasks:

```typescript
// Developer splits DV0 into focused sub-tasks
TaskCreate({
  subject: "DV1: Implement theme color tokens",
  description: "Create semantic color tokens for light/dark themes",
  metadata: { stage: "DV", agent: "developer", model: "opus", workflow_id: workflowId, priority: "medium" }
});

TaskCreate({
  subject: "DV2: Implement theme switcher",
  description: "Add toggle and persistence for theme preference",
  metadata: { stage: "DV", agent: "developer", model: "opus", workflow_id: workflowId, priority: "medium" }
});

// DV1 and DV2 can run in parallel or sequentially
TaskUpdate({ taskId: "5", addBlockedBy: ["3"] });  // DV1 ← DV0
TaskUpdate({ taskId: "6", addBlockedBy: ["3"] });  // DV2 ← DV0
```
