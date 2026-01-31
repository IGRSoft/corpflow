# Task System Reference

Single source of truth for Task System integration.

## Tools

| Tool | Purpose |
|------|---------|
| `TaskCreate` | Create tasks with subject, description, activeForm, metadata |
| `TaskUpdate` | Update status, owner, blockedBy, delete tasks |
| `TaskGet` | Retrieve current task state |
| `TaskList` | View all tasks and statuses |

## Subject Format

```
[STAGE]: [Description]
```

Examples: `PL: Planning`, `AR: Architecture`, `DV: Development`

## Metadata Fields

| Field | Purpose |
|-------|---------|
| `stage` | Stage code (PL, AR, TL, DV, etc.) |
| `workflow_id` | Links task to workflow instance |
| `priority` | high, medium, low |
| `milestone_number` | GitHub milestone (--milestone mode) |
| `issue_number` | GitHub issue being worked |
| `workspace_path` | Workspace directory (milestone mode) |
| `track` | Parallel track number |

## Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Not started, may be blocked |
| `in_progress` | Active work |
| `completed` | Done |

## Task Deletion

```typescript
TaskUpdate({ taskId: "6", delete: true });
```

Use for dynamic workflow sizing during PL/AR stages.

## Cross-Session Persistence

Set `CLAUDE_CODE_TASK_LIST_ID` for persistence across sessions:

```bash
CLAUDE_CODE_TASK_LIST_ID="my-project" claude
```

Storage: `~/.claude/tasks/<list-id>/`
