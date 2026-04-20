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
| `stage` | Stage code unnumbered (PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET) |
| `agent` | Agent to execute this task. **MUST be fully-qualified `plugin:agent` form** (e.g., `igrsoft:software-architector`, `apple-developer:ios-developer`). Bare names are accepted via a back-compat shim that prepends `igrsoft:` and emits a deprecation warning — emit qualified form at the call site |
| `model` | Model alias for this stage (opus, sonnet, haiku). Always pass explicitly to `Task()` — do not rely on frontmatter inheritance |
| `context_files` | Comma-separated list of `.context/` artifacts this stage should read. MUST include `error_file` — orchestrator appends automatically on `TaskCreate`/`TaskUpdate` if omitted |
| `error_file` | Path `.context/errors/<agent-basename>.md`. Auto-derived from `agent` if absent. Basename = last `:`-separated segment; collisions joined with `-`. Auto-appended to `context_files` so the stage agent reads its own prior retry narrative |
| `retry_count` | Integer 0–3. Incremented on retry; resets on escalation or success |
| `error_escalated_to` | Stage code the failure escalated to when `retry_count` reached 3 |
| `workflow_id` | Links task to workflow instance |
| `priority` | high, medium, low |
| `milestone_number` | GitHub milestone (--milestone mode) |
| `issue_number` | GitHub issue being worked |
| `workspace_path` | Workspace directory (milestone mode) or worktree path |
| `track` | Parallel track number 1–5 |
| `isolation` | `"worktree"` when using git worktree isolation (--worktree flag) |
| `worktree_branch` | Branch name in worktree (convenience field, worktree mode only) |
| `approved` | `"user"` after explicit post-PL0 approval, `"auto"` for `--auto-continue`, absent otherwise |

### JSON Schema

Orchestrator SHOULD validate metadata before spawning the stage agent. Non-PL tasks require `stage`, `agent`, `model`, `error_file`.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "stage": {
      "enum": ["PL", "AR", "TL", "DV", "DR", "SR", "QA", "DC", "RE", "FN", "ST", "IR", "ET"]
    },
    "agent": {
      "type": "string",
      "pattern": "^([a-z0-9-]+:)?[a-z0-9-]+$"
    },
    "model": {
      "enum": ["opus", "sonnet", "haiku"]
    },
    "context_files": {
      "type": "string",
      "pattern": "^([a-z0-9/_.-]+\\.(md|json|jsonl|png|jpg|pen)(,[a-z0-9/_.-]+\\.(md|json|jsonl|png|jpg|pen))*)?$"
    },
    "error_file": {
      "type": "string",
      "pattern": "^\\.context/errors/[a-z0-9-]+\\.md$"
    },
    "retry_count": {
      "type": "integer",
      "minimum": 0,
      "maximum": 3
    },
    "error_escalated_to": {
      "enum": ["PL", "AR", "TL", "DV", "DR", "SR", "QA", "DC", "RE", "FN", "ST", "IR", "ET"]
    },
    "track": {
      "type": "integer",
      "minimum": 1,
      "maximum": 5
    },
    "isolation": {
      "enum": ["worktree"]
    },
    "priority": {
      "enum": ["high", "medium", "low"]
    },
    "approved": {
      "enum": ["user", "auto"]
    }
  },
  "allOf": [
    {
      "if": {
        "properties": { "stage": { "not": { "const": "PL" } } },
        "required": ["stage"]
      },
      "then": {
        "required": ["stage", "agent", "model", "error_file"]
      }
    }
  ]
}
```

**error_file derivation** (orchestrator populates if absent):
- `agent: "igrsoft:developer"` → `error_file: ".context/errors/developer.md"` (last segment)
- `agent: "apple-developer:ios-developer"` → `error_file: ".context/errors/ios-developer.md"` (last segment)
- Basename collision across plugins → join with `-`: `.context/errors/apple-developer-ios-developer.md`

**context_files ↔ error_file coupling**: On every `TaskCreate` and `TaskUpdate`,
the orchestrator ensures `metadata.error_file` appears in `metadata.context_files`
(appended if absent, deduped if already present). This guarantees the stage
agent receives its own error history in its reading scope — on retry, it can
see what it tried before and why it failed.

```typescript
// Orchestrator normalization (runs before Task() delegation)
function normalizeMetadata(meta) {
  const basename = meta.agent.split(':').pop();
  meta.error_file ??= `.context/errors/${basename}.md`;
  const files = new Set((meta.context_files ?? '').split(',').map(s => s.trim()).filter(Boolean));
  files.add(meta.error_file);
  meta.context_files = [...files].join(',');
  return meta;
}
```

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
| `PermissionDenied` | Auto-mode classifier denies tool call | settings.json (all modes) |
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
