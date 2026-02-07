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
TaskUpdate({ taskId: "6", status: "deleted" });
```

Use for dynamic workflow sizing during PL/AR stages.

## Cross-Session Persistence

Set `CLAUDE_CODE_TASK_LIST_ID` for persistence across sessions:

```bash
CLAUDE_CODE_TASK_LIST_ID="my-project" claude
```

Storage: `~/.claude/tasks/<list-id>/`

## Hook Events for Task Monitoring

Configure in project `settings.json` or agent frontmatter `hooks` field:

| Hook Event | Fires When | Configuration Level |
|------------|------------|---------------------|
| `SubagentStart` | Stage agent spawned | settings.json (matcher: agent type) |
| `SubagentStop` | Stage agent completes | settings.json or agent frontmatter |
| `TeammateIdle` | Teammate finishes and idles | settings.json (agent teams only) |
| `TaskCompleted` | Task marked completed | settings.json (agent teams only) |

`TeammateIdle` and `TaskCompleted` require `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

See `agent-coordination.md § Hook-Based Stage Monitoring` for configuration examples.

## Agent Teams Integration

When agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), additional tools become available:

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create a new team for multi-agent coordination |
| `TeamDelete` | Remove team (requires all teammates stopped first) |
| `Teammate` | Spawn a teammate session |
| `SendMessage` | Send messages between teammates |

Team storage: `~/.claude/teams/{team-name}/config.json`
Task storage: `~/.claude/tasks/{team-name}/`

Teammates share a task list and can self-claim available work. See `milestone-workflow.md § Agent Teams Mode` for milestone patterns.
