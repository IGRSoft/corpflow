---
name: state-ledger
version: 1.1.0
---

# State Ledger Reference

Single source of truth for worktask stage state.

## The ledger is `state.json`

`.context/state.json` `tasks{}` is the **only** stage ledger — authoritative for stage status,
dependencies, routing metadata, and results. It lives in the worktask folder, so it survives session
end, compaction, and resume with no configuration. Full schema:
`skills/worktask/references/handoff-protocol.md#state-json-schema`.

corpflow does **not** use Claude Code's Task System (`TaskCreate` / `TaskUpdate` / `TaskGet` /
`TaskList`) — not even where those tools are available.

> **Why, so nobody re-adds them**: CC 2.1.233 removed the Todo/task-tracking tools on every model
> this plugin dispatches (Opus 4.8, Sonnet 5, Fable 5, Mythos 5, newer), so an orchestrator built on
> them cannot run at all. `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` restores them; the plugin deliberately
> does not depend on it — one ledger, one code path. `CLAUDE_CODE_ENABLE_TASKS` is **not** that
> switch.

## Ledger Keys

`[STAGE][N]`, N 0-based and sequential per stage code: first `DV` created → `DV0`, second → `DV1`
(`PL0`, `AR0`, `DV0`, `DV1`). The human-readable label lives in `tasks.<ID>.metadata.description`.

**PL is always `PL0` only** (singleton — no splitting); other stages split into sub-tasks, which is
what the numbered key exists to express: parallel DVN tracks are distinct keys. Handoff edges
(`handoffs["PL→AR"]`) stay keyed by bare **stage code**, not by ledger id.

## Write Operations

Never edit `state.json` directly — every write goes through
`skills/worktask/scripts/state-patch.sh`, which owns the merge lock, the atomic
tmp→fsync→rename, and the disk guard.

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

`--task-create` is idempotent (an existing key is left untouched), `--task-block` unions and
`--task-unblock` subtracts — re-running a seed or a teardown is safe. `--task-create` is the ONLY
op that may introduce a key; status, block, unblock and meta refuse an id that does not exist yet,
so create the task before wiring or annotating it.

## Metadata Fields

Types, ranges, defaults and the required-field rule live in § JSON Schema below — these tables add
only purpose and normative use.

### Routing fields

| Field | Purpose |
|-------|---------|
| `stage` | Stage code, unnumbered. The schema enum is the full vocabulary, not the per-run set — AR and TL tasks exist only when PL0 included them |
| `agent` | Agent to execute this task. **MUST be fully-qualified `plugin:agent` form** (`corpflow:software-architector`, `apple-developer:ios-developer`); bare names are not accepted |
| `model` | Model alias (fable, opus, sonnet, haiku), always passed explicitly to `Task()` — never rely on frontmatter inheritance, which now falls through to `CLAUDE_CODE_SUBAGENT_MODEL` when unset (`skills/shared/model-selection.md § Default Subagent Model`). A managed `availableModels`/`enforceAvailableModels` allowlist can silently resolve a valid alias to a different model (`skills/worktask/SKILL.md § Pre-Stage Validation` step 6) |

### Run & context fields

| Field | Purpose |
|-------|---------|
| `run_index` | PL0-stamped on every downstream task (same N as `planning-N.md`); resolves `<stage>-N.md` paths (`skills/worktask/references/pl0-procedure.md § Stage Artifact Naming`) |
| `context_refs` | Anchor refs the stage agent greps instead of reading whole files — § Context delivery |
| `state_file` | Path to the ledger, read by the stage agent before delegation. Mandatory — an absent `state.json` is a hard failure, not a degraded mode |

### Error & retry fields

| Field | Purpose |
|-------|---------|
| `error_file` | Auto-derived from `agent` when absent (§ error_file derivation). The stage agent reads it to see its own prior retry narrative |
| `retry_count` | Incremented on retry; resets on escalation or success |
| `error_escalated_to` | Stage code the failure escalated to when `retry_count` reached 3 |

### Worktask & workspace fields

| Field | Purpose |
|-------|---------|
| `worktask_id` | Links task to worktask instance |
| `priority` | Task priority |
| `milestone_number` | GitHub milestone (megatask mode) |
| `issue_number` | GitHub issue being worked |
| `track` | Parallel track number |
| `workspace_path` | Absolute root of the tree this task is **assigned** to — see § workspace_path below |
| `isolation` | Always `"worktree"` on file-writing tasks (DV, and megatask per-issue AR/DR/QA); PL0 stamps it unconditionally and every reader treats it that way |
| `worktree_branch` | Branch name in the worktree. ≠ `facts.branch`, the planned host-session branch — `skills/worktask/references/handoff-protocol.md § branch` |

#### workspace_path

Writers: `/worktask` steps 3a/4 and `/megatask`. Under `/megatask` it is the per-issue worktree,
otherwise `git rev-parse --show-toplevel` at init
(`skills/worktask/references/initialization-patterns.md § Seeded workspace_path`). Never leave it
unset: three assigned-tree guards read it and each degrades to a silent pass when it is absent.

### Dispatch metadata (optional)

Optional, additive fields — `effort`, `permission_mode`, `add_dirs`, `mcp_config_path`,
`plugin_dir_overrides`, `dangerously_skip_permissions`, `settings_path` — each mapping 1:1 to a
`claude agents run` flag; canonical per-field table (flag, type, in-process honouring, usage):
`skills/agent-coordination/references/headless-dispatch.md § Translation table`. In-process the
orchestrator honours `model` (always) and `permission_mode` (audited per `skills/worktask/SKILL.md
§ Permission-Mode Pinning`); the rest are advisory, consumed only by external CLI dispatchers,
except `dangerously_skip_permissions`, which the orchestrator MAY refuse.

#### Dispatch writer rules

PL0 SHOULD set `permission_mode: default` on SR/FN tasks under `--secure`/`--full` and MUST NOT set
`dangerously_skip_permissions` (CI batch only) on PL/SR/FN tasks; full rules:
`skills/worktask/references/pl0-procedure.md § Optional dispatch metadata`. `workspace_path` (always
stamped, not dispatch-optional) doubles as the `--cwd` source for headless dispatchers.

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
      "enum": ["user", "auto"],
      "description": "Plan-approval carrier on PL0, written by the orchestrator at the Step A.5 plan gate. Absent ⇒ stage agents block."
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

Orchestrator populates if absent — basename = last `:`-separated segment of `agent`:
- `corpflow:developer` → `.context/errors/developer.md`; `apple-developer:ios-developer` → `.context/errors/ios-developer.md`
- Basename collision across plugins → join with `-`: `.context/errors/apple-developer-ios-developer.md`

#### Context delivery

`metadata.context_refs` is the only context-delivery mechanism — no whole-file fallback list,
because the ledger is mandatory and the degraded "state.json is absent" path it existed to serve
cannot occur. On retry the stage agent also reads its own `error_file`, so it sees what it tried
before and why it failed.

## state.json Top-Level `metadata` Fields

Worktask-scoped fields at `state.json:$.metadata`, distinct from the `task.metadata` above. Canonical schema: `skills/worktask/references/handoff-protocol.md#state-json-schema`; the tables below index fields documented elsewhere in this plugin. All optional.

### Orchestrator-stamped fields

| Field | Writer → Reader | Description |
|-------|-----------------|-------------|
| `embedded_commands` | orchestrator at `/worktask` parse time → DV agent | Comma-separated `/plugin:command` identifiers detected on the trigger (e.g. `skill-creator`). See `commands/worktask.md § Embedded Command Detection` |
| `preexisting_plan` | orchestrator → PL agent | Absolute path to a user-approved plan supplied at init; PL0 adopts it verbatim and reuses its anchors |
| `no_gh_issue` | orchestrator, from `--no-gh-issue` → `skills/worktask/scripts/publish-pl-issue.sh` | When `true`, suppresses post-PL GitHub issue publishing |

### Issue publishing field

`metadata.github_issue_url` — issue URL written by `publish-pl-issue.sh` on the run that CREATES the issue; it short-circuits (`already_published`) on a resume of that same run. Readers: `publish-pl-issue.sh` (idempotency), FN PR-issue-link validator (rank-1). Pattern: `^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+(#issuecomment-[0-9]+)?$`.

**`state.json` is re-seeded on every fresh `/worktask`, so this field does NOT survive a `run_index` increment** — the run-independent anchor below carries the binding across runs, so a later run comments on the existing issue instead of duplicating it (`skills/gh-issue-dedup`).

### Run-independent issue anchor

> **`.context/gh-issue.json`** (a sibling FILE, not a `state.json` field): binds one `.context/` to one GitHub issue and survives `run_index` increments. Schema and protocol: `skills/gh-issue-dedup`; folder placement: `skills/task-folder-organization/SKILL.md`. Written/read by `publish-pl-issue.sh`; read by the FN PR-issue-link validator (rank-2).

## Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Not started, may be blocked |
| `in_progress` | Active work |
| `completed` | Done |
| `blocked` | Waiting on an unsatisfied `blocked_by` entry |
| `skipped` | Dropped by dynamic sizing during PL/AR (`state-patch.sh --task-status QA0 skipped`). The entry stays as an audit record of what was sized out; terminal, and never blocks a dependent |

## Hook Events for Stage Monitoring

Stage-monitoring hooks are configured in project `settings.json` or the agent frontmatter `hooks`
field. Canonical event catalog (subagent lifecycle, agent-teams, elicitation, matchers, payloads,
the conditional `if` field) and configuration examples:
`skills/agent-coordination/references/hook-monitoring.md § Project-Level Configuration`.

> `SessionEnd` hook timeout is configurable via `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` for worktasks requiring cleanup time (e.g., worktree pruning, orchestrator state finalization).

## Agent Teams Integration

With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` every session has **one implicit team** — spawn
teammates via the **Agent tool's `name` parameter** (`Agent(name: …)`; `team_name` is accepted but
ignored), and `SendMessage` remains the inter-teammate channel. Teammates coordinate through the
same `.context/state.json` ledger as every other stage and can self-claim available work. Live
teammates are now visible to `ListAgents`/`claude agents --json`, so a lead resuming mid-batch uses
the same pre-check as the stage loop (`../worktask/references/resume.md § Step 0 notes — own-name &
teammate visibility`). Megatask patterns: `../megatask/references/agent-teams.md`. Set `"autoMemoryDirectory": ".worktask-memory/"`
in settings for worktask-specific auto-memory, separate from the default `~/.claude/`.
