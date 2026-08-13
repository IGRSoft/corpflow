---
name: task-system
description: Task System tools reference (Create/Update/Get/List) with metadata fields and status values. Use when working with TaskCreate, TaskUpdate, or managing task state.
version: 0.1.0
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

### Routing fields

| Field | Purpose |
|-------|---------|
| `stage` | Stage code unnumbered (PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET). The enum is the full vocabulary, not the per-run set — AR and TL tasks exist only when PL0 included them |
| `agent` | Agent to execute this task. **MUST be fully-qualified `plugin:agent` form** (e.g., `corpflow:software-architector`, `apple-developer:ios-developer`). Bare names are not accepted |
| `model` | Model alias for this stage (fable, opus, sonnet, haiku). Always pass explicitly to `Task()` — do not rely on frontmatter inheritance. Under a managed `availableModels`/`enforceAvailableModels` allowlist a valid alias may silently resolve to a different model — see `skills/worktask/SKILL.md § Pre-Stage Validation` step 6 |

### Run & context fields

| Field | Purpose |
|-------|---------|
| `run_index` | Integer ≥ 0; PL0 stamps this on every downstream task (same N as `planning-N.md`). Default 0. Orchestrator uses it to resolve `<stage>-N.md` paths. See `agents/product-manager.md § Stage Artifact Naming`. |
| `context_refs` | JSON-encoded array of anchor refs (e.g. `["architecture-N.md#decisions","planning-N.md#requirements"]`) the stage agent should grep instead of reading whole files. Preferred over `context_files` (handoff-protocol mode). When present, agent reads `state.json` + only these anchors |
| `state_file` | Path to the worktask state ledger. Default `.context/state.json`. Read by the stage agent before delegation (per `skills/worktask/references/handoff-protocol.md#state-json-schema`). Absent state.json triggers fallback path F1 (`context_files` mode) |

### Error & retry fields

| Field | Purpose |
|-------|---------|
| `context_files` | (F1 fallback.) Comma-separated list of `.context/` artifacts this stage should read in full when `state.json` is absent or `context_refs` is missing. MUST include `error_file` — orchestrator appends automatically on `TaskCreate`/`TaskUpdate` if omitted. Required for AC-16/AC-17 |
| `error_file` | Path `.context/errors/<agent-basename>.md`. Auto-derived from `agent` if absent. Basename = last `:`-separated segment; collisions joined with `-`. Auto-appended to `context_files` so the stage agent reads its own prior retry narrative |
| `retry_count` | Integer 0–3. Incremented on retry; resets on escalation or success |
| `error_escalated_to` | Stage code the failure escalated to when `retry_count` reached 3 |

### Worktask & workspace fields

| Field | Purpose |
|-------|---------|
| `worktask_id` | Links task to worktask instance |
| `priority` | high, medium, low |
| `milestone_number` | GitHub milestone (megatask mode) |
| `issue_number` | GitHub issue being worked |
| `workspace_path` | Absolute root of the tree this task is **assigned** to — see § workspace_path below |
| `track` | Parallel track number 1–5 |
| `isolation` | Always `"worktree"` on file-writing tasks (DV and megatask per-issue AR/DR/QA). PL0 stamps this unconditionally; developer.md § D0.0, technical-lead.md DR check, SKILL.md 4.8, and workspace-modes.md all treat it as always `"worktree"`. |
| `worktree_branch` | Branch name in worktree (convenience field). ≠ `facts.branch` (the planned host-session branch, named once at PL start and refinable at most once more pre-commit) — see `skills/worktask/references/handoff-protocol.md § branch` for the disambiguation |

#### workspace_path

Stamped on **every** run — `/worktask` steps 3a/4 as well as `/megatask` — and mirrored into
`state.json .metadata.workspace_path`. Under `/megatask` it is the per-issue worktree; otherwise
it is `git rev-parse --show-toplevel` at init. Never leave it unset: three assigned-tree guards
read it and each degrades to a silent pass when it is absent. See
`skills/worktask/references/initialization-patterns.md § Seeded workspace_path`.

### Dispatch metadata (optional)

These fields map to `claude agents run` CLI flags per `skills/agent-coordination/references/headless-dispatch.md`. All are optional and additive — the in-process orchestrator honours `model` (always) and `permission_mode` (audits per `skills/worktask/SKILL.md § Permission-Mode Pinning`); the rest are advisory in-process and consumed only by external CLI dispatchers.

#### Dispatch field table

| Field | Purpose | Honoured in-process? |
|-------|---------|----------------------|
| `effort` | Effort tier (`low\|medium\|high\|xhigh\|max`) for this dispatch. Falls back to agent frontmatter when absent | Advisory |
| `permission_mode` | Permission boundary (`default\|acceptEdits\|plan\|bypassPermissions`). PL0 SHOULD set `default` on SR/FN tasks under `--secure`/`--full` | **Yes — audited** |
| `add_dirs` | Array of extra directories to expose to the dispatched session (`--add-dir`) | Advisory |
| `mcp_config_path` | Path to a scoped MCP config (`--mcp-config`) for this dispatch | Advisory |
| `plugin_dir_overrides` | Array of `--plugin-dir` paths (local plugin development) | Advisory |
| `dangerously_skip_permissions` | Boolean. CI batch only; PL0 MUST NOT set this on PL/SR/FN tasks | Advisory; orchestrator MAY refuse |
| `settings_path` | Path to alternative `settings.json` (`--settings`) for provider/org swap | Advisory |

#### Dispatch writer rules

PL0's writer rules for these fields live in `agents/product-manager.md § Optional dispatch metadata`. The `workspace_path` field (already documented above — always stamped, not dispatch-optional) doubles as the `--cwd` source for headless dispatchers.

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
```

#### Schema — run & context properties

```json
// …continued: task.metadata JSON Schema "properties" (part 2 of 5)
    "run_index": {
      "type": "integer",
      "minimum": 0,
      "default": 0,
      "description": "Propagated by PL0. Same N as planning-N.md. Orchestrator uses it to resolve <stage>-N.md paths."
    },
    "context_refs": {
      "type": "string",
      "description": "JSON-encoded array of anchor refs, e.g. '[\"architecture-N.md#decisions\",\"planning-N.md#requirements\"]'. Preferred (handoff-protocol mode)."
    },
    "state_file": {
      "type": "string",
      "default": ".context/state.json",
      "pattern": "^\\.context/[a-z0-9/_.-]+\\.json$"
    },
```

#### Schema — error & retry properties

```json
// …continued: task.metadata JSON Schema "properties" (part 3 of 5)
    "context_files": {
      "type": "string",
      "pattern": "^([a-z0-9/_.-]+\\.(md|json|jsonl|png|jpg|pen)(,[a-z0-9/_.-]+\\.(md|json|jsonl|png|jpg|pen))*)?$",
      "description": "F1 fallback. Used when state.json is absent."
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
```

#### Schema — worktask properties

```json
// …continued: task.metadata JSON Schema "properties" (part 4 of 5)
    "track": {
      "type": "integer",
      "minimum": 1,
      "maximum": 5
    },
    "isolation": {
      "enum": ["worktree"],
      "description": "Always 'worktree' on file-writing tasks. PL0 stamps unconditionally; no other value is valid."
    },
    "workspace_path": {
      "type": "string",
      "description": "Absolute root of the assigned tree. Stamped on EVERY run (not megatask-only) and mirrored to state.json .metadata.workspace_path. Isolation is not assignment: a stale worktree satisfies 'isolation' and still fails this. Absent ⇒ three guards silently no-op."
    },
    "priority": {
      "enum": ["high", "medium", "low"]
    },
    "approved": {
      "enum": ["user", "auto"]
    },
```

#### Schema — requires_screenshots + required-fields rule

```json
// …continued: task.metadata JSON Schema (part 5 of 5, closes "properties")
    "requires_screenshots": {
      "type": "boolean",
      "description": "Advisory: DV and QA tasks SHOULD carry this, stamped by PL0 from the plan frontmatter (writer: product-manager via detect-ui-change.sh). Drives dv-screenshot-capture + hooks/dv-screenshot-gate.sh + attach-visual-evidence.sh. Downstream readers default it true as defense-in-depth when absent."
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

#### error_file derivation

Orchestrator populates if absent:
- `agent: "corpflow:developer"` → `error_file: ".context/errors/developer.md"` (last segment)
- `agent: "apple-developer:ios-developer"` → `error_file: ".context/errors/ios-developer.md"` (last segment)
- Basename collision across plugins → join with `-`: `.context/errors/apple-developer-ios-developer.md`

#### context_files ↔ error_file coupling

On every `TaskCreate` and `TaskUpdate`,
the orchestrator ensures `metadata.error_file` appears in `metadata.context_files`
(appended if absent, deduped if already present). This guarantees the stage
agent receives its own error history in its reading scope — on retry, it can
see what it tried before and why it failed.

#### context_refs vs context_files (handoff-protocol mode)

When `metadata.context_refs` is set, the stage agent reads `state_file` + only the listed anchors; when absent or `state_file` is missing on disk, it falls back to reading every `context_files` path in full. `context_refs` wins when state.json is present; `context_files` is the safety net. F1 (`context_files` mode) rationale and the F1..F4 matrix: `skills/worktask/references/handoff-protocol.md#fallback-paths`.

#### Orchestrator normalization snippet

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

## state.json Top-Level `metadata` Fields

These fields live at `state.json:$.metadata` (worktask-scoped, distinct from `task.metadata` documented above). Canonical schema lives in `skills/worktask/references/handoff-protocol.md#state-json-schema`; the table below is the additive index of fields documented elsewhere in this plugin.

### Orchestrator-stamped fields

| Field | Type | Description |
|-------|------|-------------|
| `metadata.embedded_commands` | string (optional) | Comma-separated list of `/plugin:command` slash-command identifiers detected on the worktask trigger (e.g. `skill-creator`). Writer: orchestrator at `/worktask` parse time. Reader: DV agent before stage work begins. See `commands/worktask.md § Embedded Command Detection`. |
| `metadata.preexisting_plan` | string (optional) | Absolute path to a user-approved plan supplied at worktask init; PL0 adopts it verbatim and reuses anchors. Writer: orchestrator. Reader: PL agent. |
| `metadata.no_gh_issue` | boolean (optional) | When `true`, suppresses post-PL GitHub issue publishing. Writer: orchestrator at parse time (set by the `--no-gh-issue` CLI flag). Reader: `skills/worktask/scripts/publish-pl-issue.sh`. |

### Issue publishing field

| Field | Type | Description |
|-------|------|-------------|
| `metadata.github_issue_url` | string (optional) | GitHub issue URL written by `publish-pl-issue.sh` on the run that CREATES the issue. Pattern: `^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+(#issuecomment-[0-9]+)?$`. The helper short-circuits (`already_published`) on a resume of that same run. **`state.json` is re-seeded on every fresh `/worktask`, so this field does NOT survive a `run_index` increment** — the run-independent `.context/gh-issue.json` anchor (below) carries the canonical `.context ↔ issue` binding across runs, so a later run comments on the existing issue instead of duplicating it (see `skills/gh-issue-dedup`). Writer: `publish-pl-issue.sh`. Readers: `publish-pl-issue.sh` (idempotency), FN PR-issue-link validator (rank-1). |

### Run-independent issue anchor

> **Run-independent issue anchor — `.context/gh-issue.json`** (a sibling FILE, not a `state.json` field): binds one `.context/` to one GitHub issue and survives `run_index` increments (state.json is re-seeded; this is not). Schema and protocol: `skills/gh-issue-dedup`; folder placement: `skills/task-folder-organization/SKILL.md`. Written/read by `publish-pl-issue.sh`; read by the FN PR-issue-link validator (rank-2).

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

Use for dynamic worktask sizing during PL/AR stages.

## Cross-Session Persistence

Set `CLAUDE_CODE_TASK_LIST_ID` for persistence across sessions:

```bash
CLAUDE_CODE_TASK_LIST_ID="my-project" claude
```

Storage: `~/.claude/tasks/<list-id>/`

## Hook Events for Task Monitoring

Configure in project `settings.json` or agent frontmatter `hooks` field:

### Hook event table

| Hook Event | Fires When | Configuration Level |
|------------|------------|---------------------|
| `SubagentStart` | Stage agent spawned | settings.json (matcher: agent type) |
| `SubagentStop` | Stage agent completes | settings.json or agent frontmatter |
| `TeammateIdle` | Teammate finishes and idles | settings.json (agent teams only) |
| `TaskCompleted` | Task marked completed | settings.json (agent teams only) |
| `PostCompact` | After context compaction completes | settings.json (all modes) |
| `Elicitation` | MCP server requests user input | settings.json |
| `ElicitationResult` | User responds to MCP elicitation | settings.json |

#### Hook event table (continued)

| Hook Event | Fires When | Configuration Level |
|------------|------------|---------------------|
| `StopFailure` | API error causes turn end | settings.json |
| `CwdChanged` | Working directory changes | settings.json |
| `FileChanged` | Monitored file modified | settings.json |
| `TaskCreated` | TaskCreate tool called | settings.json |
| `PermissionDenied` | Auto-mode classifier denies tool call | settings.json (all modes) |
| `WorktreeCreate` | Worktree created | settings.json |

### Hook usage notes

`TeammateIdle` and `TaskCompleted` require `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

> Hooks support a conditional `if` field using permission rule syntax to reduce process spawning overhead.

> `SessionEnd` hook timeout is configurable via `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` for worktasks requiring cleanup time (e.g., worktree pruning, orchestrator state finalization).

See `agent-coordination.md § Hook-Based Stage Monitoring` for configuration examples.

## Agent Teams Integration

With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, every session has **one implicit team** — spawn teammates via the **Agent tool's `name` parameter**; `team_name` is accepted but ignored. `SendMessage` remains the inter-teammate channel.

| Tool | Purpose |
|------|---------|
| `Agent(name: …)` | Spawn a teammate into the session's implicit team |
| `SendMessage` | Send messages between teammates |

Task storage: `~/.claude/tasks/` (session-scoped subdirectory; no explicit team name — `team_name` is accepted but ignored in the implicit team model)

### Custom Auto-Memory Directory

Configure a custom directory for worktask-specific auto-memory:

```json
{
  "autoMemoryDirectory": ".worktask-memory/"
}
```

Allows worktask-specific memory separate from the default `~/.claude/` location.

Teammates share a task list and can self-claim available work. See `../megatask/references/agent-teams.md` for megatask patterns.
