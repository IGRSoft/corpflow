---
name: task-system
description: Task System tools reference (Create/Update/Get/List) with metadata fields and status values. Use when working with TaskCreate, TaskUpdate, or managing task state.
---

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
[STAGE][N]: [Description]
```

N is 0-based, sequential per stage code. First `DV` created → `DV0`, second → `DV1`.

Examples: `PL0: Planning`, `AR0: Architecture`, `DV0: Development`, `DV1: Implement auth module`

**PL is always `PL0` only** (singleton — no splitting). Other stages can split into sub-tasks.

## Metadata Fields

| Field | Purpose |
|-------|---------|
| `stage` | Stage code unnumbered (PL, AR, TL, DV, etc.) |
| `agent` | Agent to execute this task (e.g., `software-architector`). Model resolved from agent frontmatter |
| `workflow_id` | Links task to workflow instance |
| `priority` | high, medium, low |
| `milestone_number` | GitHub milestone (--milestone mode) |
| `issue_number` | GitHub issue being worked |
| `workspace_path` | Workspace directory (milestone mode) or worktree path |
| `track` | Parallel track number |
| `isolation` | `"worktree"` when using git worktree isolation (--worktree flag) |
| `worktree_branch` | Branch name in worktree (convenience field, worktree mode only) |

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
| `PostCompact` | After context compaction completes | settings.json (all modes) |
| `Elicitation` | MCP server requests user input | settings.json |
| `ElicitationResult` | User responds to MCP elicitation | settings.json |
| `StopFailure` | API error causes turn end | settings.json |
| `CwdChanged` | Working directory changes | settings.json |
| `FileChanged` | Monitored file modified | settings.json |
| `TaskCreated` | TaskCreate tool called | settings.json |
| `WorktreeCreate` | Worktree created | settings.json |

`TeammateIdle` and `TaskCompleted` require `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

> Hooks support a conditional `if` field (v2.1.85+) using permission rule syntax to reduce process spawning overhead.

> `SessionEnd` hook timeout is configurable via `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` for workflows requiring cleanup time (e.g., worktree pruning, orchestrator state finalization).

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

### Custom Auto-Memory Directory

Configure a custom directory for workflow-specific auto-memory:

```json
{
  "autoMemoryDirectory": ".workflow-memory/"
}
```

Allows workflow-specific memory separate from the default `~/.claude/` location.

Teammates share a task list and can self-claim available work. See `milestone-workflow.md § Agent Teams Mode` for milestone patterns.
