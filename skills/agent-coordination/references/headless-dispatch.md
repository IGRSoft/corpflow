# Headless Dispatch — `claude agents` Flag Bridge

External orchestrators (CI runners, batch schedulers, the user's own shell) that want to invoke a worktask stage outside the in-process `Task()` path need a stable contract from `task.metadata` to `claude agents run` CLI flags. This reference is that contract.

> Today the igrsoft orchestrator dispatches every stage in-process via `Task({ subagent_type, model, prompt })` (see `skills/worktask/SKILL.md` line ~497). The CLI flags listed below are honoured **only** by `claude agents run …` invocations. PL0 populates the fields anyway so any downstream dispatcher — in-process or CLI — reads from the same source of truth.

## Translation Table

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `agent` | `--agent <name>` | string | N/A (in-process uses `Task({subagent_type})`) | overrides the session's `settings.json` `agent` default; e.g. force `igrsoft:developer` for a one-shot run |
| `--all` (listing flag, not a `metadata` key) | `claude agents --all` | bool | N/A (listing only) | includes **completed** sessions in `claude agents [--json]` output; pair with `state` to tell `done` apart from `running`/`blocked` |

### Translation table — model & effort

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `model` | `--model <id>` | string | **Yes** (passed to `Task()`) | DV→`claude-opus-4-8`; QA→`claude-sonnet-4-6`; FN→`claude-sonnet-4-6`. Caveat: a managed `availableModels` allowlist also constrains subagent model overrides, and `enforceAvailableModels` constrains the Default model too — a requested id may silently down-resolve; audit, don't assume |
| `effort` | `--effort <tier>` | `low\|medium\|high\|xhigh\|max` | Advisory | DV complex→`xhigh`; DR→`high`; FN/RE→`medium`. `ultracode` is an additional dispatch-surface value accepted by `claude agents --effort` and delivered to the dispatched session — it is NOT a plugin `metadata.effort` tier; the plugin enum stays `low/medium/high/xhigh/max` |

### Translation table — permission, workspace & MCP

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `permission_mode` | `--permission-mode <mode>` | `default\|acceptEdits\|plan\|bypassPermissions` (`manual` = accepted alias for `default`) | **Yes — audited** (see § Permission-Mode Pinning below) | SR/FN→`default`; DV under `--auto-plan`→`bypassPermissions` |
| `workspace_path` | `--cwd <path>` | string | N/A (in-process inherits parent cwd) | megatask tracks → per-issue worktree |
| `add_dirs` (array) | repeated `--add-dir <path>` | string[] | N/A | cross-repo work, monorepo siblings |
| `mcp_config_path` | `--mcp-config <path>` | string | N/A | scoped MCP set per dispatch |

### Translation table — plugins, skip-permissions & settings

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `plugin_dir_overrides` (array) | repeated `--plugin-dir <path>` | string[] | N/A | local plugin development |
| `dangerously_skip_permissions` | `--dangerously-skip-permissions` | bool | Advisory; orchestrator MAY refuse | CI batch only, with a deny-list in `settings.json` |
| `settings_path` | `--settings <path>` | string | N/A | provider / org config swap |

### Advisory vs audited legend

"Advisory" = the field is recorded on the task and read by external dispatchers, but the in-process `Task()` tool has no equivalent parameter today. "Audited" = the orchestrator writes an `audit.jsonl` line when the field is set, even though it cannot enforce the mode on a `Task()` child.

## Per-Stage Recommended Flag Sets

The minimum recommended flag set per stage when dispatching from a headless runner. Substitute concrete IDs from `task.metadata` at call time.

| Stage | Canonical headless one-liner |
|---|---|
| **DV** | `claude agents run --cwd "$WORKTREE" --model claude-opus-4-8 --effort xhigh --permission-mode bypassPermissions -- igrsoft:developer < dv-prompt.txt` |
| **DR** | `claude agents run --cwd "$WORKTREE" --model claude-opus-4-8 --effort xhigh --permission-mode acceptEdits -- igrsoft:technical-lead < dr-prompt.txt` |
| **SR** | `claude agents run --cwd "$WORKTREE" --model claude-opus-4-8 --effort xhigh --permission-mode default -- igrsoft:security-reviewer < sr-prompt.txt` |
| **QA** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort high --permission-mode acceptEdits -- igrsoft:qa-engineer < qa-prompt.txt` |

### FN / RE / ST one-liners

| Stage | Canonical headless one-liner |
|---|---|
| **FN** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort medium --permission-mode default -- igrsoft:project-manager < fn-prompt.txt` |
| **RE** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort medium --permission-mode default -- igrsoft:release-engineer < re-prompt.txt` |
| **ST** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort medium --permission-mode acceptEdits -- igrsoft:stakeholder < st-prompt.txt` |

### Model & effort defaults

The model/effort defaults track `skills/shared/model-selection.md`. Override per task when `metadata.model` / `metadata.effort` are set. DR runs technical-lead at **opus/xhigh** (matches `skills/shared/stage-codes.md` and the stage table in `benchmark/harness/Sources/BenchmarkLive/Dispatch.swift`, the machine-checked SSOT — the Python `dispatch.py` predecessor was retired in v3.29.0); the agent's `model: opus` frontmatter default applies to both the DR stage dispatch and direct TC consults.

### Sonnet 5 alias note

> The pinned `claude-sonnet-4-6` ids above are benchmark-parity snapshots, not a tier recommendation — the `sonnet` **alias** resolves to Claude Sonnet 5 (CC default; native 1M context). Prefer aliases in ad-hoc runner scripts (deprecation-proof per `skills/shared/model-selection.md`); keep pinned ids only where byte-reproducibility against the benchmark SSOT matters.

### Background-worker & env reliability

> Background/agent-view workers are reliable for headless dispatch: pre-warmed workers do not leak another directory's project settings, attach does not fail with `EAUTH` after daemon auto-update or claim-after-idle, a nested child stopping does not stick the parent `active`, and background sessions do not inherit another session's `ANTHROPIC_*` provider env. Background sessions preserve shell-exported `ANTHROPIC_BASE_URL`, inherit the dispatching shell's `PATH`, honor `effortLevel` when forked through the daemon, and follow `CLAUDE_CODE_EXTRA_BODY`. A login-expiry warning fires **before** a background session is interrupted, so a headless runner can re-auth ahead of the cut-off. Background jobs on LLM-gateway auth (`ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`) survive daemon respawns without coming back "Not logged in".

### Unattended-runner resilience

> `CLAUDE_CODE_MAX_RETRIES` is capped at 15; for unattended batches set `CLAUDE_CODE_RETRY_WATCHDOG` instead — it raises the default retry count for non-capacity transient errors to 300 and lifts the 15-retry cap. The streaming idle watchdog is default-on for all providers: a stream silent for 5 minutes aborts and retries (`CLAUDE_ENABLE_STREAM_WATCHDOG=0` disables). Transient 429s unrelated to the usage limit retry automatically with backoff for subscribers.

#### Structured output & MCP auth

> `--json-schema` structured output is reliable for dispatch pipelines (no indefinite `StructuredOutput` re-call; schema-validation failures abort after 5 attempts). Authenticate MCP servers up front with `claude mcp login <name>` / `claude mcp logout <name>` (`--no-browser` completes over SSH) — pairs with the auth-stub-hiding note below. `claude agents --dangerously-skip-permissions` shows the bypass disclaimer and applies bypass mode to spawned agents instead of silently falling back to auto mode.

## Live Session Discovery

`claude agents --json` returns a JSON array of currently-live Claude sessions. The orchestrator and external runners can poll this to discover *what is already running* — complementing the dispatch table above which covers *how to start* something headlessly.

Canonical orchestrator shell-out, scoped to one worktask track:

```bash
claude agents --json | jq -r --arg track "$TRACK_ID" '
  .[] | select(.metadata.worktask_track == $track) | .agent_id'
```

### Usage patterns

Three usage patterns:

- **Resume pre-check** — before respawning a subagent during worktask resume, query live sessions; if any `agent_id` from `.context/state.json.facts.dispatched_agents[]` still appears, prefer `SendMessage` reattach over re-delegation. Eliminates the "blind respawn of an already-working subagent" token-waste class. See `skills/worktask/SKILL.md § Resume Procedure` step 0.
- **Parallel track health** — for megatask runs, periodic `claude agents --json | jq '[.[] | select(.tag=="igrsoft-track")] | length'` should equal the orchestrator-derived `parallel_tracks`. Less = stalled track.
- **Status-line integration** — drives tmux / shell-status-bar widgets showing the active worktask stage without polluting `.context/`.

### Schema-drift caveat

Caveat: the CLI is stable but the JSON schema is not formally versioned — guard every read with defensive jq (`.parent_agent_id // "none"`). See § Schema Versioning Watch below.

### Schema Versioning Watch

The `claude agents --json` output schema is **not formally versioned** by Claude Code. Plugin consumers must defensively guard fields.

#### Recorded baseline (CC 2.1.169)

**Recorded baseline** (first pinned on CC 2.1.169) — array of objects with these observed top-level fields:

- Required: `session_id` (string), `agent_type` (string), `agent_id` (string), `started_at` (ISO-8601 string)
- Optional: `parent_agent_id` (string), `cwd` (string), `tag` (string), `metadata` (object), `waitingFor` (string — what a live session is blocked on, e.g. `approval`/`input`; empty/null = busy mid-work), `id` (string — stable session identifier), `state` (string — lifecycle phase, e.g. `running`/`blocked`/`done`)

Rows additionally render a `done/total` progress count in the human-readable (non-`--json`) listing.

#### `--all` semantics

> `claude agents [--json] --all` includes **completed** sessions (otherwise filtered out); **blocked** and **just-dispatched** sessions are always present in the listing. Combined with the `state` field, a resume scan can distinguish a `blocked` agent (reattach via `SendMessage`) from a genuinely absent one (re-delegate) — closing the "blind re-dispatch of an invisible blocked agent" waste class. See `skills/worktask/SKILL.md § Resume Procedure` step 0.

#### "Needs input" status axis

> Sessions parked on a **sandbox approval**, an **MCP elicitation/input request**, or a **managed-settings prompt** surface distinctly — the agent view and `claude agents --json` report them as "Needs input" instead of reading as busy/"Working". The exact JSON field/value for this axis is **unconfirmed** (could be a new `waitingFor` enum value alongside `approval`/`input`, or a separate flag) — until a watch run pins it, treat any session parked on a sandbox/MCP-input/managed-settings prompt as **parked on us** (same bucket as `waitingFor: approval/input`), never as busy mid-work. Resume-side handling: these parks are operator-owned — see `skills/worktask/references/resume.md § Live-agent rows`. The watch run that pins the exact field MUST update this entry.

#### Defensive-read rule for optional fields

`waitingFor`, `id`, and `state` are read defensively (`.waitingFor // empty`, `.id // ""`, `.state // ""`) to guard against schema drift — the listing schema is not formally versioned, and additive optional fields do **not** bump min CC (per the "If the baseline shifts" rule below, which is reserved for *required* / renamed / type-changed fields). The resume loop branches directly on `{agent_id, state, waitingFor}` (`skills/worktask/SKILL.md § Resume Procedure` step 0).

#### Watch protocol for future /cc-update runs

**Watch protocol for future `/cc-update` runs**: in any cc-update where the CC version delta touches `claude agents` CLI surface, the prompt-engineer MUST run `claude agents --json | jq 'first | keys'` and diff the key list against this recorded baseline. Surface any drift as a Q for the operator.

#### Drift observed on CC 2.1.175

> ⚠ **Drift observed on CC 2.1.175** (2026-06-12, v3.17.0 cc-update; unannounced in the changelog): with only interactive sessions live, rows came back as `{pid, cwd, kind: "interactive", startedAt, sessionId}` — **camelCase** (`session_id` → `sessionId`), `startedAt` as **epoch-millis number** (was ISO-8601 string), a new `kind` discriminator, and no `agent_id`/`state`/`waitingFor` on that row type. **Unconfirmed** whether dispatched-agent rows (`kind` ≠ `interactive`) kept the snake_case baseline shape — no live agents existed at observation time.

##### Mitigations until the agent-row variant is pinned

> Until a watch run pins the agent-row variant: (a) coalesce both spellings in every read (pattern below); (b) filter by `kind` before matching resume rows; (c) expect the resume pre-check to degrade safely to "absent → re-delegate" when fields read null.

#### Watch run 2026-07-07 (v3.30.0 cc-update)

> **Watch run 2026-07-07 (v3.30.0 cc-update)**: interactive-row variant returned `{cwd, kind, name, pid, sessionId, startedAt}` — same camelCase shape as the 2.1.175 observation plus a new optional **`name`** key (readable default session names; also the `SendMessage`/`/rename` address — `/rename` on background sessions persists across restarts). Agent-row variant still unconfirmed (no dispatched agents live at observation time). Baseline-shift rule not triggered — additive optional key on the interactive variant only.

#### Defensive jq pattern

**Defensive jq pattern** (canonical for any plugin code reading this output):

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

**If the baseline shifts** (new required field, renamed field, type change), the next cc-update MUST bump min CC version and add a migration note to the relevant `cc-features-<from>-<to>.md` band file.

#### `--tools` Grep/Glob

> When a headless dispatch passes `--tools` and explicitly lists `Grep`/`Glob`, native builds wire up dedicated search tools for them (rather than falling back to shelling out). No plugin change needed — relevant only when an external runner hand-builds the `--tools` set; the in-process `Task()` path inherits agent-frontmatter `tools:` unchanged.

#### Subagent tool enforcement

> A subagent's `disallowedTools` honors MCP **server-level** specs (`mcp__server`, `mcp__*`), so a headless cross-plugin dispatch can deny an entire MCP server to a child rather than enumerating each tool. `WebSearch` works inside subagents — a child can rely on it (session-wide ceiling: ~200 WebSearch calls per session by default, `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` to tune). Auth-capable MCP servers do not expose their auth-stub tools to headless / SDK runs, so a `--print`/`agents run` child does not see stub auth tools it cannot complete. These let server-level MCP denials and child `WebSearch` be relied upon in cross-plugin dispatch.

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

Subagents natively inherit the parent session's permission mode (the Task tool's deprecated `mode` parameter is ignored), so mode pinning is about *not widening* the inherited mode — the audit line records that the boundary held. Every other flag listed above is advisory in-process and only takes effect when an external runner shells out `claude agents run …`.

## External-Dispatch Audit Hook

When a headless runner invokes a stage via `claude agents run …` instead of the in-process orchestrator, the runner MUST append one `audit.jsonl` line at the same worktask's `.context/logs/audit.jsonl`:

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

Without this line, the post-worktask audit cannot distinguish in-process delegation from CLI dispatch — which matters for cost attribution, security review, and reproducibility.

## Anti-Patterns

- **Do not** pass `--dangerously-skip-permissions` from an interactive session. It is reserved for headless CI runs that already have a deny-list (`permissions.deny`, `autoMode.hard_deny`) in `settings.json`. Interactive sessions should leave it unset and let the permission UI handle prompts.
- **Do not** mix `--cwd` and `task.metadata.workspace_path` pointing at different paths. The runner MUST resolve one canonical worktree directory and pass it consistently.
- **Do not** set `dangerously_skip_permissions: true` on PL/SR/FN tasks — these are gated stages where human review is the entire point. PL0 SHOULD reject such metadata at validation time.
- **Do not** treat the CLI flags as a replacement for agent-frontmatter `tools:` restrictions. The flags configure the *session*; the frontmatter restricts the *agent*. Both apply.

### FN-gate race

- **Do not** let a headless code-writing dispatch race the FN gate: background agents launched from `claude agents` **auto commit, push, and open a draft PR** when they finish code work in a worktree instead of stopping to ask. For gated worktasks, scope DV dispatches to implementation only (no push-capable permission mode / credentials) so commit/push/PR stays owned by the FN stage behind `fn_gate`. (Megatask lanes stamp per-issue `fn_gate: "bypass"`, so lane auto-PR is by-design there.)

## Background Shell Dispatch

Two ways to spawn background shell work without occupying a foreground agent turn:

### `claude agents` `! <command>` — inline background shell

From inside a running session, prefix any shell command with `!` to dispatch it as a background task:

```bash
# Inside a claude agents session — runs in background, result delivered as a message
! git log --oneline -20
! swift build 2>&1 | tail -20
```

The `!`-prefixed command runs in a background shell and delivers stdout/stderr back into the session context when complete. Unlike a `Bash` tool call, it does not block the agent's turn — the agent can continue planning while the shell command executes.

### `claude --bg --exec '<command>'`

From outside a session, launch a one-shot background command that auto-exits on completion:

```bash
claude --bg --exec 'cd "$WORKTREE" && swift build 2>&1 > .context/build.log'
```

Useful for CI/cron jobs that need Claude's tool environment but don't require an interactive agent. The session is ephemeral — it exits when the command exits. Combine with `--cwd`, `--model`, `--permission-mode` as needed.

Both mechanisms are additive to the existing `claude agents run … < prompt.txt` headless pattern above; choose based on whether you need full agent reasoning (`agents run`) or a shell side-effect (`! <cmd>` / `--bg --exec`).
