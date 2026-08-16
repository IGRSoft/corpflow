---
name: state-ledger
description: State ledger reference — the state.json tasks{} map, its metadata schema, status values, and write operations. Use when creating, reading, or updating worktask stage state.
version: 1.0.0
---

# State Ledger Reference

Single source of truth for worktask stage state.

## The ledger is `state.json`

`.context/state.json` `tasks{}` is the **only** stage ledger. It is authoritative for stage
status, dependencies, routing metadata, and results. Full schema:
`skills/worktask/references/handoff-protocol.md#state-json-schema`.

corpflow does **not** use Claude Code's Task System (`TaskCreate` / `TaskUpdate` / `TaskGet` /
`TaskList`) — not even where those tools are available.

> **Why, so nobody re-adds them**: CC 2.1.233 removed the Todo/task-tracking tools on Opus 4.8,
> Sonnet 5, Fable 5, Mythos 5, and newer models. Every model this plugin dispatches is on that
> list, so an orchestrator built on those tools cannot run at all. `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`
> restores them, but the plugin deliberately does not depend on it — one ledger, one code path.
> `CLAUDE_CODE_ENABLE_TASKS` is **not** that switch; do not mistake one for the other.

## Ledger Keys

```
[STAGE][N]
```

N is 0-based, sequential per stage code. First `DV` created → `DV0`, second → `DV1`.

Examples: `PL0`, `AR0`, `DV0`, `DV1`. The human-readable label lives in `tasks.<ID>.metadata.description`.

**PL is always `PL0` only** (singleton — no splitting). Other stages can split into sub-tasks,
which is exactly what the numbered key exists to express: parallel DVN tracks are distinct keys.

Handoff edges (`handoffs["PL→AR"]`) stay keyed by bare **stage code**, not by ledger id.

## Write Operations

All writes go through `skills/worktask/scripts/state-patch.sh` — never edit `state.json`
directly. It owns the merge lock, the atomic tmp→fsync→rename, and the disk guard.

| Operation | Command |
|-----------|---------|
| Create | `state-patch.sh --task-create <ID> --metadata '<json>'` |
| Set status | `state-patch.sh --task-status <ID> <status>` |
| Add dependency | `state-patch.sh --task-block <ID> --on <ID[,ID...]>` |
| Remove dependency | `state-patch.sh --task-unblock <ID> --off <ID[,ID...]>` |
| Merge metadata | `state-patch.sh --task-meta <ID> --set '<json>'` |
| Complete from artifact | `state-patch.sh --stage <CODE> [--task-id <ID>] [--prev <CODE>] [--via <layer>]` |
| Resolve an id (read-only) | `state-patch.sh --resolve-task-id <CODE>` |

### Idempotency and key creation

`--task-create` is idempotent (an existing key is left untouched); `--task-block` unions and
`--task-unblock` subtracts, so re-running a seed or a teardown is safe. `--task-create` is also
the ONLY op that may introduce a key — status, block, unblock, and meta all refuse an id that
does not exist yet, so create the task before wiring or annotating it.

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
| `run_index` | Integer ≥ 0; PL0 stamps this on every downstream task (same N as `planning-N.md`). Default 0. Orchestrator uses it to resolve `<stage>-N.md` paths. See `skills/worktask/references/pl0-procedure.md § Stage Artifact Naming`. |
| `context_refs` | JSON-encoded array of anchor refs (e.g. `["architecture-N.md#decisions","planning-N.md#requirements"]`) the stage agent should grep instead of reading whole files. The stage agent reads `state.json` + only these anchors |
| `state_file` | Path to the worktask state ledger. Default `.context/state.json`. Read by the stage agent before delegation (per `skills/worktask/references/handoff-protocol.md#state-json-schema`). The ledger is mandatory — an absent `state.json` is a hard failure, not a degraded mode |

### Error & retry fields

| Field | Purpose |
|-------|---------|
| `error_file` | Path `.context/errors/<agent-basename>.md`. Auto-derived from `agent` if absent. Basename = last `:`-separated segment; collisions joined with `-`. The stage agent reads it to see its own prior retry narrative |
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

PL0's writer rules for these fields live in `skills/worktask/references/pl0-procedure.md § Optional dispatch metadata`. The `workspace_path` field (already documented above — always stamped, not dispatch-optional) doubles as the `--cwd` source for headless dispatchers.

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
    "description": {
      "type": "string",
      "description": "Human-readable stage label (the retired Task System subject line). Lives here, not top-level: state-patch.sh writes tasks.<ID> fields only through --metadata/--set."
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

#### Context delivery

`metadata.context_refs` is the only context-delivery mechanism: the stage agent reads
`state_file` plus the listed anchors, and nothing else by default. There is no whole-file
fallback list — the ledger is mandatory, so the degraded "state.json is absent" path it
existed to serve cannot occur.

On retry the stage agent additionally reads its own `error_file`, so it can see what it
tried before and why it failed.

#### Orchestrator normalization snippet

```typescript
// Orchestrator normalization (runs before Task() delegation)
function normalizeMetadata(meta) {
  const basename = meta.agent.split(':').pop();
  meta.error_file ??= `.context/errors/${basename}.md`;
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
| `blocked` | Waiting on an unsatisfied `blocked_by` entry |
| `skipped` | Dropped by dynamic sizing — see below |

## Dropping a Stage

```bash
state-patch.sh --task-status QA0 skipped
```

Use for dynamic worktask sizing during PL/AR stages. The entry stays in the ledger as an
audit record of what was sized out; `skipped` is terminal and never blocks a dependent.

## Persistence

The ledger lives at `.context/state.json` in the worktask folder, so it survives session
end, compaction, and resume with no configuration. Nothing else needs to be set.

## Hook Events for Stage Monitoring

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

Teammates coordinate through the same `.context/state.json` ledger as every other stage.

### Custom Auto-Memory Directory

Configure a custom directory for worktask-specific auto-memory:

```json
{
  "autoMemoryDirectory": ".worktask-memory/"
}
```

Allows worktask-specific memory separate from the default `~/.claude/` location.

Teammates share the ledger and can self-claim available work. See `../megatask/references/agent-teams.md` for megatask patterns.
