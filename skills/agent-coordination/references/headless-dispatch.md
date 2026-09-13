# Headless Dispatch — `claude agents` Flag Bridge

The contract mapping `task.metadata` to `claude agents run` CLI flags, for external orchestrators (CI runners, batch schedulers, the user's shell) invoking a worktask stage outside the in-process `Task()` path.

> The corpflow orchestrator dispatches every stage in-process via `Task({ subagent_type, model, prompt })`; the flags below are honoured **only** by `claude agents run …`. PL0 populates the fields anyway, so every downstream dispatcher — in-process or CLI — reads one source of truth.

## Translation Table

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `agent` | `--agent <name>` | string | N/A (in-process uses `Task({subagent_type})`) | overrides the session's `settings.json` `agent` default; e.g. force `corpflow:developer` for a one-shot run |
| `--all` (listing flag, not a `metadata` key) | `claude agents --all` | bool | N/A (listing only) | includes **completed** sessions in `claude agents [--json]` output; pair with `state` to tell `done` apart from `running`/`blocked` |

### Translation table — model & effort

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `model` | `--model <id>` | string | **Yes** (passed to `Task()`) | DV→`claude-opus-5`; QA/FN→`claude-sonnet-5` (benchmark-parity snapshots — § Alias note). Caveat: a managed `availableModels` allowlist also constrains subagent overrides, and `enforceAvailableModels` constrains the Default model — a requested id may silently down-resolve; audit, don't assume |
| `effort` | `--effort <tier>` | `low\|medium\|high\|xhigh\|max` | Advisory | DV complex→`xhigh`; DR→`high`; FN→`medium`; RE→`low`. `ultracode` is an additional dispatch-surface value accepted by `claude agents --effort` and delivered to the dispatched session — it is NOT a plugin `metadata.effort` tier; the plugin enum stays `low/medium/high/xhigh/max`. Caveat: a managed or user `maxEffortLevel` (top-level, or per model under `modelSettings`) caps effort on every provider — a tier pinned above the cap runs at the cap with no error; audit, don't assume |

### Translation table — permission, workspace & MCP

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `permission_mode` | `--permission-mode <mode>` | `default\|acceptEdits\|plan\|bypassPermissions` | **Yes — audited** (§ Permission-Mode Pinning) | SR/FN→`default`; DV under `--auto=[plan]`→`bypassPermissions`. The CLI's choices are `acceptEdits\|auto\|bypassPermissions\|manual\|dontAsk\|plan`, with no `default`: pass plugin `default` as `manual`. `auto` and `dontAsk` are CLI-only values, NOT plugin `metadata.permission_mode` tiers; the plugin enum is unchanged |
| `workspace_path` | `--cwd <path>` | string | N/A (in-process inherits parent cwd) | megatask tracks → per-issue worktree |
| `add_dirs` (array) | repeated `--add-dir <path>` | string[] | N/A | cross-repo work, monorepo siblings |
| `mcp_config_path` | `--mcp-config <path>` | string | N/A | scoped MCP set per dispatch |

### Translation table — plugins, skip-permissions & settings

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `plugin_dir_overrides` (array) | repeated `--plugin-dir <path>` | string[] | N/A | local plugin development; a path may name a folder of plugins, and each child folder with a manifest loads |
| `dangerously_skip_permissions` | `--dangerously-skip-permissions` | bool | Advisory; orchestrator MAY refuse | CI batch only, with a deny-list in `settings.json` |
| `settings_path` | `--settings <path>` | string | N/A | provider / org config swap |

### Advisory vs audited legend

"Advisory" = recorded on the task and read by external dispatchers, but the in-process `Task()` tool has no equivalent parameter today. "Audited" = the orchestrator writes an `audit.jsonl` line when the field is set, even though it cannot enforce the mode on a `Task()` child.

## Per-Stage Recommended Flag Sets

One canonical invocation; substitute the per-stage row plus concrete IDs from `task.metadata` at call time.

```bash
claude agents run --cwd "$WORKTREE" --model "$MODEL" --effort "$EFFORT" \
  --permission-mode "$MODE" -- "$AGENT" < "$PROMPT"
```

Neither `claude agents run` nor top-level `--cwd` exists on the probed CLI (§ Watch run — CC 2.1.270 (observed)): read the one-liner as the flag mapping, not a runnable command, until it is re-derived.

| Stage | `$AGENT` | `$MODEL` | `$EFFORT` | `$MODE` |
|---|---|---|---|---|
| **DV** | `corpflow:developer` | `claude-opus-5` | `high` | `bypassPermissions` |
| **DR** | `corpflow:technical-lead` | `claude-opus-5` | `high` | `acceptEdits` |
| **SR** | `corpflow:security-reviewer` | `claude-opus-5` | `xhigh` | `default` |
| **QA** | `corpflow:qa-engineer` | `claude-sonnet-5` | `medium` | `acceptEdits` |
| **FN** | `corpflow:project-manager` | `claude-sonnet-5` | `medium` | `default` |
| **RE** | `corpflow:release-engineer` | `claude-sonnet-5` | `low` | `default` |
| **ST** | `corpflow:stakeholder` | `claude-sonnet-5` | `low` | `acceptEdits` |

### Model & effort defaults

Defaults track `skills/shared/model-selection.md`; override per task when `metadata.model` / `metadata.effort` are set. DR runs technical-lead at **opus/high**, matching `skills/shared/stage-codes.md` and the stage table in `benchmark/harness/benchmarklive/stage_table.py` (the machine-checked SSOT); the agent's `model: opus` frontmatter default applies to both the DR stage dispatch and direct TC consults.

### Alias note

> The pinned ids exist for **SSOT parity** — they match `STAGE_TABLE` in the live-dispatch table so a benchmark run is byte-reproducible. They coincide with what the aliases resolve to today (`opus` → Claude Opus 5, `sonnet` → Claude Sonnet 5), but that is timing, not a guarantee: prefer **aliases** in ad-hoc runner scripts (deprecation-proof, `skills/shared/model-selection.md`) and keep pinned ids only where byte-reproducibility matters. Re-pinning the SSOT is a **benchmark change, not a docs refresh** — measurements before and after are not comparable, so record the cut-over in `benchmark/README.md`.

### Runner-side reliability

- The `stream-json` **init event** carries `mcp_server_errors` — the `--mcp-config` entries the validator skipped (terminal runs also print a startup warning). A runner depending on a scoped MCP set (`metadata.mcp_config_path`) reads this at init rather than discovering the gap at the first `mcp__<server>__*` call. `claude mcp list` / `/mcp` report HTTP status and error text on failed connections and warn about config values with hidden whitespace.
- With `--forward-subagent-text`, depth-2+ subagents appear in the stream keyed by their spawning Agent `tool_use` id, so per-stage token attribution sees nested Tier-2 work instead of folding it into the parent stage.
- A turn dying on a mid-stream API error no longer discards text `claude -p` already produced — salvage the partial work instead of treating the dispatch as empty.

#### Background-worker & env reliability

> Pre-warmed background/agent-view workers do not leak another directory's project settings, attach does not fail with `EAUTH` after daemon auto-update or claim-after-idle, a nested child stopping does not stick the parent `active`, and background sessions do not inherit another session's `ANTHROPIC_*` env. They preserve shell-exported `ANTHROPIC_BASE_URL`, inherit the dispatching shell's `PATH`, honor `effortLevel` when forked through the daemon, and follow `CLAUDE_CODE_EXTRA_BODY`. A login-expiry warning fires **before** interruption so a runner can re-auth ahead of the cut-off, and gateway-auth jobs (`ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`) survive daemon respawns without coming back "Not logged in".

#### Unattended-runner resilience

> `CLAUDE_CODE_MAX_RETRIES` is capped at 15; for unattended batches set `CLAUDE_CODE_RETRY_WATCHDOG` instead — it raises the default retry count for non-capacity transient errors to 300 and lifts the cap. The streaming idle watchdog is default-on for all providers: a stream silent for 5 minutes aborts and retries (`CLAUDE_ENABLE_STREAM_WATCHDOG=0` disables). Transient 429s unrelated to the usage limit retry automatically with backoff for subscribers.

#### Structured output & MCP auth

> `--json-schema` structured output is reliable for dispatch pipelines (no indefinite `StructuredOutput` re-call; schema-validation failures abort after 5 attempts). Authenticate MCP servers up front with `claude mcp login <name>` / `claude mcp logout <name>` (`--no-browser` completes over SSH). `claude agents --dangerously-skip-permissions` shows the bypass disclaimer and applies bypass mode to spawned agents instead of silently falling back to auto mode.

#### Print-mode (`claude -p`) runners

> `--permission-prompts none` makes an unattended runner deny anything that would prompt instead of hanging, while the active permission mode keeps deciding the rest. It is a print-mode flag, not a `claude agents` flag and not a ledger field. `claude -p` waits for a Monitor the model armed to fire or time out before exiting. Background commands a subagent starts have no time cap and run until they exit or are stopped, so a runner stops them explicitly. A `cd` persists across turns in non-interactive sessions.

## Live Session Discovery

`claude agents --json` returns a JSON array of currently-live Claude sessions — poll it to discover *what is already running*, complementing the dispatch table above which covers *how to start* something. Canonical orchestrator shell-out, scoped to one worktask track:

```bash
claude agents --json | jq -r --arg track "$TRACK_ID" '
  .[] | select(.metadata.worktask_track == $track) | .agent_id'
```

### Usage patterns

- **Resume pre-check** — before respawning a subagent during resume, query live sessions; if any `agent_id` from `.context/state.json.facts.dispatched_agents[]` still appears, reattach via `SendMessage` instead of re-delegating (`skills/worktask/references/resume.md § Resume Procedure` step 0). Kills the "blind respawn of an already-working subagent" waste class.
- **Parallel track health** — `claude agents --json | jq '[.[] | select(.tag=="corpflow-track")] | length'` should equal the orchestrator-derived `parallel_tracks`. Less = stalled track.
- **Status-line integration** — drives tmux / status-bar widgets showing the active stage without polluting `.context/`.

The CLI is stable but the JSON schema is **not formally versioned** — guard every read with defensive jq (`.parent_agent_id // "none"`); see § Schema Versioning Watch.

### Schema Versioning Watch

#### Recorded baseline (CC 2.1.169)

Array of objects with these observed top-level fields:

- Required: `session_id` (string), `agent_type` (string), `agent_id` (string), `started_at` (ISO-8601 string)
- Optional: `parent_agent_id` (string), `cwd` (string), `tag` (string), `metadata` (object), `waitingFor` (string — what a live session is blocked on, e.g. `approval`/`input`; empty/null = busy mid-work), `id` (string — stable session identifier), `state` (string — lifecycle phase, e.g. `running`/`blocked`/`done`)

Rows additionally render a `done/total` progress count in the human-readable (non-`--json`) listing.

#### `--all` semantics

> `claude agents [--json] --all` includes **completed** sessions (otherwise filtered out); **blocked** and **just-dispatched** sessions are always listed. Combined with `state`, a resume scan can distinguish a `blocked` agent (reattach via `SendMessage`) from a genuinely absent one (re-delegate) — closing the "blind re-dispatch of an invisible blocked agent" waste class (`skills/worktask/references/resume.md § Resume Procedure` step 0).

#### "Needs input" status axis

> Sessions parked on a **sandbox approval**, an **MCP elicitation/input request**, or a **managed-settings prompt** report as "Needs input" rather than busy/"Working". The exact JSON field/value is **unconfirmed** (possibly a new `waitingFor` enum value, possibly a separate flag) — until a watch run pins it, treat any such session as **parked on us** (same bucket as `waitingFor: approval/input`), never as busy. These parks are operator-owned (`skills/worktask/references/resume.md § Live-agent rows`). The watch run that pins the field MUST update this entry.

#### Defensive-read rule for optional fields

`waitingFor`, `id`, and `state` are read defensively (`.waitingFor // empty`, `.id // ""`, `.state // ""`) to guard against drift; additive optional fields do **not** bump min CC (the § If the baseline shifts rule covers only *required* / renamed / type-changed fields). The resume loop branches directly on `{agent_id, state, waitingFor}`.

#### Watch protocol for future /cc-update runs

In any cc-update whose CC version delta touches the `claude agents` CLI surface, the prompt-engineer MUST run `claude agents --json | jq 'first | keys'`, diff the key list against the recorded baseline, and surface any drift as a Q for the operator.

#### Drift observed on CC 2.1.175

> ⚠ 2026-06-12, unannounced in the changelog: with only interactive sessions live, rows came back as `{pid, cwd, kind: "interactive", startedAt, sessionId}` — **camelCase** (`session_id` → `sessionId`), `startedAt` as **epoch-millis number** (was ISO-8601 string), a new `kind` discriminator, and no `agent_id`/`state`/`waitingFor` on that row type. **Unconfirmed** whether dispatched-agent rows (`kind` ≠ `interactive`) kept the snake_case baseline shape — no live agents existed at observation time.

##### Mitigations until the agent-row variant is pinned

> (a) coalesce both spellings in every read (pattern below); (b) filter by `kind` before matching resume rows; (c) expect the resume pre-check to degrade safely to "absent → re-delegate" when fields read null.

#### Watch run 2026-07-07

> Interactive-row variant returned `{cwd, kind, name, pid, sessionId, startedAt}` — the same camelCase shape as 2.1.175 plus a new optional **`name`** key (readable default session names; also the `SendMessage`/`/rename` address — `/rename` on background sessions persists across restarts). Agent-row variant still unconfirmed. Baseline-shift rule not triggered — additive optional key on the interactive variant only.

#### Watch run — CC 2.1.234→2.1.251 band (from release notes, not observed)

> Behaviour confirmed, JSON shape **not**: live **teammates** now appear in `ListAgents`/`claude agents --json` (previously absent, so a reachable teammate read as gone), a session can identify **its own row** by name, and the pre-warmed idle worker no longer appears until a task claims it — removing a phantom row from the resume pre-check. Next live watch run must confirm the teammate row's `kind` discriminator and whether own-name reuses the existing `name` key (2026-07-07 baseline) or arrives as a new one. Baseline-shift rule not triggered on the strength of release notes alone.

#### Watch run — CC 2.1.270 (observed)

> Live probe; `--json --all` returned interactive rows only. Those rows carry exactly `{cwd, kind, name, pid, sessionId, startedAt, status}` with `status: "busy"` — the 2026-07-07 key set plus `status`, and **no `id`** key. The resume identity chain `agent_id // id // sessionId` already tolerates the missing `id`. A session's own name reuses the existing `name` key: `ListAgents` reported "This session is tallahassee-a7" and the `--json` row carried `name: "tallahassee-a7"`. The teammate row's `kind` and the background-row key set remain **unobserved**. Baseline-shift rule not triggered — `status` is additive and `id` was optional.
>
> Dispatch-surface drift: `claude agents run` is **not** a subcommand — `claude agents run --help` prints the plain `claude agents` usage, whose options are defaults for agent-view dispatch. Top-level `claude` accepts `--bg`, `--model`, `--effort`, `--permission-mode`, `--add-dir`, `--plugin-dir`, `--settings` and `--mcp-config` but has **no `--cwd`**, so an external dispatcher must `cd` into the worktree first. § Per-Stage Recommended Flag Sets and the translation table still name `claude agents run` and `--cwd`; re-deriving the external one-liner is an **open follow-up**.

#### Defensive jq pattern

Canonical for any plugin code reading this output:

```jq
.[] | {
  session:    (.session_id // .sessionId // "unknown"),   # camelCase observed on 2.1.175
  kind:       (.kind // "agent"),                          # "interactive" rows are NOT dispatched agents — filter before matching
  parent:     (.parent_agent_id // .parentAgentId // "none"),
  tag:        (.tag // "untagged"),
  waiting_for: (.waitingFor // ""),  # "" = busy mid-work; "approval"/"input" = parked on us
  state:       (.state // "")        # "running"/"blocked"/"done"
}
```

#### If the baseline shifts

On a baseline shift (new required field, renamed field, type change), the next cc-update MUST bump min CC version and add a migration note to the relevant `cc-features-<from>-<to>.md` band file.

#### Child tool grants: `--tools`, MCP denials & WebSearch

> `--tools` listing `Grep`/`Glob` wires up dedicated native search tools rather than shelling out — relevant only to a runner hand-building the `--tools` set; the in-process `Task()` path inherits agent-frontmatter `tools:` unchanged. A subagent's `disallowedTools` honors MCP **server-level** specs (`mcp__server`, `mcp__*`), so a cross-plugin dispatch can deny a whole server to a child instead of enumerating tools. `WebSearch` works inside subagents (~200 calls/session, `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` tunes it). Auth-capable MCP servers hide auth-stub tools from headless / SDK runs, so a child never sees stubs it cannot complete.

## Session Lifecycle CLI (attach / logs / stop / respawn / rm)

`claude attach <id>` attaches a terminal to a **running** background session; `--resume` is for a **stopped** conversation. The two are not interchangeable, and the `--resume` message now prints the exact `attach` command when the target is still running. `logs`, `stop`, `respawn`, and `rm` complete the surface, all documented in `claude --help`.

These are **operator** tools. The orchestrator's own reattach path stays `SendMessage` (`skills/worktask/references/resume.md`) — `attach` changes what a human debugging alongside a run can do, not what the loop does. Two lifecycle fixes worth relying on: `claude agents`/`claude rm` no longer refuse to delete a session whose worktree branch was merged locally but not pushed, and a weeks-old background session is no longer resurrected after the machine was off — it shows as stopped at its real end and asks before resuming. `claude --resume <session-id> --bg` continues that session under its own ID when nothing is running it, so a recorded `dispatched_agents[]` id stays valid; when a copy starts instead, the CLI announces it.

## Permission-Mode Pinning (in-process)

When the orchestrator reads `task.metadata.permission_mode === "default"` for a stage, it MUST NOT propagate `--dangerously-skip-permissions` or any equivalent shorthand into descendant `Task()` calls or nested `Bash` invocations for that stage, and MUST append one `audit.jsonl` line:

```json
{
  "ts": "<ISO-8601 UTC>",
  "actor": "orchestrator",
  "action": "permission_mode_pinned",
  "subject": "<task_id>",
  "result": "ok",
  "metadata": { "stage": "<code>", "mode": "default" }
}
```

Subagents natively inherit the parent session's permission mode (the Task tool's deprecated `mode` parameter is ignored), so pinning is about *not widening* the inherited mode — the audit line records that the boundary held. Every other flag above is advisory in-process and takes effect only when an external runner shells out `claude agents run …`.

## External-Dispatch Audit Hook

A headless runner invoking a stage via `claude agents run …` MUST append one line to the same worktask's `.context/logs/audit.jsonl`:

```json
{
  "ts": "<ISO-8601 UTC>",
  "actor": "external:<runner-name>",
  "action": "external_dispatch",
  "subject": "<task_id>",
  "result": "ok",
  "task_id": "<task_id>",
  "metadata": {
    "invoker": "<ci|cron|user-shell>",
    "agent": "<plugin:agent>",
    "flags": ["--model=…", "--effort=…", "--permission-mode=…", "--cwd=…"]
  }
}
```

Without it the post-worktask audit cannot distinguish in-process delegation from CLI dispatch — which matters for cost attribution, security review, and reproducibility.

## Anti-Patterns

- **Do not** pass `--dangerously-skip-permissions` from an interactive session — it is for headless CI runs that already carry a deny-list (`permissions.deny`, `autoMode.hard_deny`) in `settings.json`; interactively, let the permission UI handle prompts.
- **Do not** point `--cwd` and `task.metadata.workspace_path` at different paths — resolve one canonical worktree directory and pass it consistently.
- **Do not** set `dangerously_skip_permissions: true` on PL/SR/FN tasks: human review is the entire point of a gated stage. PL0 SHOULD reject such metadata at validation time.
- **Do not** treat CLI flags as a replacement for agent-frontmatter `tools:` restrictions — flags configure the *session*, frontmatter restricts the *agent*; both apply.

### FN-gate race

- **Do not** let a headless code-writing dispatch race the FN gate: background agents launched from `claude agents` **auto commit, push, and open a draft PR** when they finish code work in a worktree instead of stopping to ask. For gated worktasks, scope DV dispatches to implementation only (no push-capable permission mode / credentials) so commit/push/PR stays owned by the FN stage behind `fn_gate`. (Megatask lanes stamp per-issue `fn_gate: "bypass"`, so lane auto-PR is by-design there.)

## Background Shell Dispatch

Two ways to spawn background shell work without occupying a foreground agent turn — additive to `claude agents run … < prompt.txt`. Choose by whether you need agent reasoning (`agents run`) or just a shell side-effect.

- **`! <command>`** — inside a running session, prefixing a shell command with `!` (e.g. `! swift build 2>&1 | tail -20`) runs it in a background shell and delivers stdout/stderr into session context on completion. Unlike a `Bash` tool call it does not block the turn.
- **`claude --bg --exec '<command>'`** — from outside a session, a one-shot background command that auto-exits on completion, e.g. `claude --bg --exec 'cd "$WORKTREE" && swift build > .context/build.log 2>&1'`. For CI/cron jobs needing Claude's tool environment but no interactive agent; combine with `--cwd`, `--model`, `--permission-mode`.
