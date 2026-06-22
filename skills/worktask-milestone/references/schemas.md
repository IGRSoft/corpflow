# Orchestrator & Workspace Schemas

## Orchestrator State (Required Schema)

### Orchestrator (version 3.0)

```json
{
  "version": "3.0",
  "milestone": { "number": 1, "title": "Sprint 1" },
  "configuration": {
    "parallel_tracks": 3,
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

## Workspace State

### Workspace (version 2.0)

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
  "worktask": { "track": 1, "task_prefix": "t1", "complexity_score": 18 },
  "execution": { "current_stage": "DV", "retry_count": 0 },
  "task_ids": { "PL": "t1-1", "AR": "t1-2", "DV": "t1-3", "DR": "t1-4", "QA": "t1-5" }
}
```
