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

> **Why, so nobody re-adds them**: the Todo/task-tracking tools are offered only on Claude 3.x,
> Opus 4.0–4.7, Sonnet 4.0–4.6 and Haiku 4.5, so an orchestrator built on them cannot run on the
> opus-, sonnet- or fable-tier models this plugin dispatches. A haiku-tier stage
> (`corpflow:technical-writer`) does see them, and uses the ledger all the same.
> `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` offers them on other models; the plugin deliberately does not
> depend on it — one ledger, one code path. `CLAUDE_CODE_ENABLE_TASKS` is **not** that switch.

## Ledger Keys

`[STAGE][N]`, N 0-based and sequential per stage code: first `DV` created → `DV0`, second → `DV1`
(`PL0`, `AR0`, `DV0`, `DV1`). The human-readable label lives in `tasks.<ID>.metadata.description`.

**PL is always `PL0` only** (singleton — no splitting); other stages split into sub-tasks, which is
what the numbered key exists to express: parallel DVN tracks are distinct keys. Handoff edges carry
that same split: `handoffs["<PREV_CODE>→<TASK_ID>"]` — the source is a bare **stage code**, the
destination is the **ledger id** of the task that wrote the edge (`PL→AR0`, `TL→DV1`). Keying the
destination by bare code let four parallel DV tracks overwrite one another's edge; the source needs
no id, because it answers only which stage this followed. **Breaking for in-flight ledgers**: no
migration, no tolerant reader — an old-shape key reads as absent and forces a logged re-merge.

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
| `model` | Model alias (fable, opus, sonnet, haiku), always passed explicitly to `Task()` — never rely on frontmatter inheritance, which now falls through to `CLAUDE_CODE_SUBAGENT_MODEL` when unset (`skills/shared/model-selection.md § Default Subagent Model`). A managed `availableModels`/`enforceAvailableModels` allowlist can silently resolve a valid alias to a different model (`skills/worktask/SKILL.md § Pre-Stage Validation` step 6). `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` overrides even the explicit alias, so `dispatched_agents[].model_resolved` diverges from the pin: Step 6.5b backfills it when the runtime surfaces the model that ran (`skills/worktask/SKILL.md § Step 6.5b — dispatch entry completed`), and PL0 raises a plan-gate sweep item (`skills/shared/model-selection.md § Forced subagent model overrides every pin`) |

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
| `escalation_counts` | Escalations attempted per edge, keyed by the **full task id** of the target (`{"AR0": 2}`) so a split stage's writers do not share a counter. Survives the escalation handoff that resets `retry_count`; at cap 2 the task is written `failed` with `last_error.class: "exhausted"` |

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

### Fan-out fields (DV rows)

Set on DV rows only. Canonical model, naming grammar and the single-DV case:
`skills/worktask/references/handoff-protocol.md § DV fan-out — ledger tasks`.

| Field | Purpose |
|-------|---------|
| `stream` | Kebab slug naming this row's artifact, unique among the run's DV rows. Assigned by the row's creator (PL0, or TL when TL runs) — DV never invents one. Mandatory once a run carries ≥2 DV rows; omittable for a lone DV row |
| `artifact` | The path this row writes, `.context/development-<N>-<stream>.md` (`.context/development-<N>.md` for a lone row). Planned value only: `tasks.<ID>.artifact`, stamped by `state-patch.sh --artifact` at completion, outranks it |

### Landing fields (DV rows)

Written on DV rows and read by `skills/worktask/scripts/land-artifacts.sh`. Declarations, passes and
refusal reasons: `skills/worktask/references/handoff-protocol.md § Landing consumed artifacts`.

| Field | Purpose |
|-------|---------|
| `produces` | Producer rows: repo-relative, post-merge paths this row `git add`s for its consumers before its completion patch. Written by PL0 or TL only |
| `consumes` | Consumer rows: `[{from: "DV<n>", paths: [path]}]`, each path one the producer lists in `produces`. The row is also `blocked_by` every `from`. Written by PL0 or TL only |

#### Landing results

| Field | Purpose |
|-------|---------|
| `landed_paths` | Consumer rows: sorted unique paths landed untracked into this row's tree. Written only by `land-artifacts.sh`; absent or `[]` is normal (§ The landed set) |
| `landed_roots` | Consumer rows: every spelling of each tree those paths landed into — the banner path, `git rev-parse --show-toplevel`, the physical root. Written only by `land-artifacts.sh`, in the same write as `landed_paths` |
| `landing_error` | `{reason, path, producer}` while a refused landing holds this row `blocked`; `null` once released |

#### The landed set

The paths landed into **one tree**: `landed_paths` from every row whose `landed_roots` holds that
tree, so no reader has to decide which row is the consumer. Every reader computes it with this
expression, byte for byte, always passing the tree as `--arg root`:

```jq
[(.tasks // {})[] | .metadata | select(any(.landed_roots // [] | arrays | .[]; . == $root)) | .landed_paths // [] | arrays | .[] | strings | select(test("^[A-Za-z0-9._@+/-]+$"))] | unique | .[]
```

The key is the tree that received the landing, not a row's assigned `workspace_path`: a re-pin
rewrites that path, and a copy left in the old tree must stay excluded there. An entry outside the
`[A-Za-z0-9._@+/-]` alphabet is dropped, so it never becomes a match pattern.

##### The landed set — each reader's root

| Reader | `$root` |
|--------|---------|
| Script transports (fn-preflight base-sanity, `skills/worktask/SKILL.md` Step 4.7a) | `land-artifacts.sh --list-landed --tree "$(git rev-parse --show-toplevel)"`. `--tree` is required (exit 2 without it); the script matches the tree's physical path |
| `hooks/dv-comment-density-gate.sh` | Its physical `_root`, resolved with `cd -P` and `pwd -P` |
| `agents/project-manager.md` (FN scope check) | `git rev-parse --show-toplevel` |
| `agents/technical-lead.md` (DR untracked check) | The exact string it gave `git -C` |
| Any reader with no tree to hand | `--arg root ""`, which matches no row: the set is empty, never the union over every tree |

##### The landed set — subtracting it

A reader subtracts the set from **untracked** entries only, enumerated file-level
(`git status --porcelain --untracked-files=all` or `git ls-files --others --exclude-standard`),
since default porcelain collapses a new directory to `?? dir/`. It never subtracts from `M`, `A` or
`D` lines: a staged landed path is a consumer violation and stays visible. An empty set is normal;
only `land-artifacts.sh` writes it, and the producer's tree ships every landed file.

### Dispatch metadata (optional)

Optional, additive fields — `permission_mode`, `add_dirs`, `mcp_config_path`,
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

#### effort is mandatory, and still advisory as a flag

`effort` left the optional set above when the Step C.0a resolver began reading it
(`skills/shared/stage-contracts.md § Blocking items are resolved, not asked`). The two axes are
independent: as a **ledger record** it is required, because the resolver bumps it one rung and a
per-stage override exists nowhere else; as a **dispatch flag** it stays advisory, since in-process
`Task()` takes no effort argument. `state-patch.sh` validates it against `EFFORT_ENUM` on
`--task-create` and `--task-meta`.

### JSON Schema

Orchestrator SHOULD validate metadata before spawning the stage agent. Non-PL tasks require `stage`, `agent`, `model`, `effort`, `error_file`.

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
    "effort": {
      "enum": ["low", "medium", "high", "xhigh", "max"]
    },
    "description": {
      "type": "string",
      "maxLength": 240,
      "description": "Human-readable stage label (the retired Task System subject line). Lives here, not top-level: state-patch.sh writes tasks.<ID> fields only through --metadata/--set. Capped: see below."
    },
```

#### `description` is capped at 240 chars

Both writers — `--task-create --metadata` and `--task-meta --set` — truncate a longer value with an
ellipsis rather than rejecting it: a refused `--task-create` would break PL0 stage creation.

The orchestrator's **dispatch-time appends** (test scope, bans, the FN banner) are a different
thing. They mutate an in-memory copy that is never written back, so they are transient and
uncapped; capping post-append would silently strip those banners from the prompt that needs them.

#### Schema — run & context properties

```json
// …continued: task.metadata JSON Schema "properties" (part 2 of 8)
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
// …continued: task.metadata JSON Schema "properties" (part 3 of 8)
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
    "escalation_counts": {
      "type": "object",
      "propertyNames": { "pattern": "^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)[0-9]+$" },
      "additionalProperties": { "type": "integer", "minimum": 0, "maximum": 3 }
    },
```

#### Schema — worktask properties

```json
// …continued: task.metadata JSON Schema "properties" (part 4 of 8)
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

#### Schema — DV fan-out properties

```json
// …continued: task.metadata JSON Schema "properties" (part 5 of 8)
    "stream": {
      "type": "string",
      "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$",
      "description": "DV rows only: kebab slug naming this row's artifact, unique among the run's DV rows. See § Fan-out fields (DV rows)."
    },
    "artifact": {
      "type": "string",
      "description": "DV rows only: the .context/ path this row writes. Planned value; tasks.<ID>.artifact outranks it once stamped at completion."
    },
```

#### Schema — landing declarations

```json
// …continued: task.metadata JSON Schema "properties" (part 6 of 8)
    "produces": {
      "type": "array",
      "items": { "type": "string" },
      "description": "DV rows: repo-relative paths this row stages for consumers."
    },
    "consumes": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["from", "paths"],
        "additionalProperties": false,
        "properties": {
          "from": { "type": "string", "pattern": "^DV[0-9]+$" },
          "paths": { "type": "array", "minItems": 1, "items": { "type": "string" } }
        }
      }
    },
```

#### Schema — landing results

```json
// …continued: task.metadata JSON Schema "properties" (part 7 of 8)
    "landed_paths": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Written only by land-artifacts.sh: paths landed untracked into this row's tree. May be absent or empty."
    },
    "landed_roots": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Written only by land-artifacts.sh with landed_paths: every spelling (banner path, git toplevel, physical) of each tree it landed into. The landed set is scoped by it."
    },
    "landing_error": {
      "type": ["object", "null"],
      "properties": {
        "reason": { "type": "string" },
        "path": { "type": "string" },
        "producer": { "type": "string" }
      }
    },
```

#### Schema — requires_screenshots + required-fields rule

```json
// …continued: task.metadata JSON Schema (part 8 of 8, closes "properties")
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
        "required": ["stage", "agent", "model", "effort", "error_file"]
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
| `with_design` | `--with-design` → `skills/worktask/references/pl0-procedure.md § Designer Invocation` | When `true`, PL0 invokes `corpflow:designer`; otherwise Designer is skipped even for UI work and the keyword score stays advisory. No component stamps the field, so the gate reads absent on every run. |

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
| `blocked` | Waiting on an unsatisfied `blocked_by` entry, or held by a refused landing (`metadata.landing_error`); released by clearing that field, then `--task-status <ID> pending` |
| `skipped` | Dropped by dynamic sizing during PL/AR (`state-patch.sh --task-status QA0 skipped`). The entry stays as an audit record of what was sized out; terminal, and never blocks a dependent |
| `failed` | Terminally failed: retries and per-edge escalations are both exhausted, `last_error.class` is `exhausted`, and no further dispatch will be attempted. Terminal, and settles the completion loop (`skills/worktask/SKILL.md` `SETTLED`) |

## Hook Events for Stage Monitoring

Stage-monitoring hooks are configured in project `settings.json` or the agent frontmatter `hooks`
field. Canonical event catalog (subagent lifecycle, agent-teams, elicitation, matchers, payloads,
the conditional `if` field) and configuration examples:
`skills/agent-coordination/references/hook-monitoring.md § Project-Level Configuration`.

> `SessionEnd` is registered by the plugin to `hooks/session-end-finalize.sh`, which appends one `session_end_finalize` audit row naming every task still `in_progress` at teardown — the only completion record background work killed with the session otherwise gets. It reports and never mutates task status. Its manifest entry carries `"timeout": 5`, so the row does not depend on the operator exporting `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` — without a per-hook `timeout` a SessionEnd hook gets 1.5 s (`skills/agent-coordination/references/hook-monitoring.md § SessionEnd finalization`).

## Agent Teams Integration

With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` every session has **one implicit team** — spawn
teammates via the **Agent tool's `name` parameter** (`Agent(name: …)`; `team_name` is accepted but
ignored), and `SendMessage` remains the inter-teammate channel. Teammates coordinate through the
same `.context/state.json` ledger as every other stage and can self-claim available work. Live
teammates are now visible to `ListAgents`/`claude agents --json`, so a lead resuming mid-batch uses
the same pre-check as the stage loop (`../worktask/references/resume.md § Step 0 notes — own-name &
teammate visibility`). Megatask patterns: `../megatask/references/agent-teams.md`. Set `"autoMemoryDirectory": ".worktask-memory/"`
in settings for worktask-specific auto-memory, separate from the default `~/.claude/`.
