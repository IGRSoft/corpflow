# Headless Dispatch — `claude agents` Flag Bridge

External orchestrators (CI runners, batch schedulers, the user's own shell) that want to invoke a worktask stage outside the in-process `Task()` path need a stable contract from `task.metadata` to `claude agents run` CLI flags. This reference is that contract.

> Today the igrsoft orchestrator dispatches every stage in-process via `Task({ subagent_type, model, prompt })` (see `skills/worktask/SKILL.md` line ~497). The CLI flags listed below are honoured **only** by `claude agents run …` invocations. PL0 populates the fields anyway so any downstream dispatcher — in-process or CLI — reads from the same source of truth.

## Translation Table

| `task.metadata` key | CLI flag | Type | Honoured in-process? | Stage examples |
|---|---|---|---|---|
| `model` | `--model <id>` | string | **Yes** (passed to `Task()`) | DV→`claude-opus-4-8`; QA→`claude-sonnet-4-6`; FN→`claude-sonnet-4-6` |
| `effort` | `--effort <tier>` | `low\|medium\|high\|xhigh\|max` | Advisory | DV complex→`xhigh`; DR→`high`; FN/RE→`medium` |
| `permission_mode` | `--permission-mode <mode>` | `default\|acceptEdits\|plan\|bypassPermissions` | **Yes — audited** (see § Permission-Mode Pinning below) | SR/FN→`default`; DV under `--auto-continue`→`bypassPermissions` |
| `workspace_path` | `--cwd <path>` | string | N/A (in-process inherits parent cwd) | milestone tracks → per-issue worktree |
| `add_dirs` (array) | repeated `--add-dir <path>` | string[] | N/A | cross-repo work, monorepo siblings |
| `mcp_config_path` | `--mcp-config <path>` | string | N/A | scoped MCP set per dispatch |
| `plugin_dir_overrides` (array) | repeated `--plugin-dir <path>` | string[] | N/A | local plugin development |
| `dangerously_skip_permissions` | `--dangerously-skip-permissions` | bool | Advisory; orchestrator MAY refuse | CI batch only, with a deny-list in `settings.json` |
| `settings_path` | `--settings <path>` | string | N/A | provider / org config swap |

"Advisory" = the field is recorded on the task and read by external dispatchers, but the in-process `Task()` tool has no equivalent parameter today. "Audited" = the orchestrator writes an `audit.jsonl` line when the field is set, even though it cannot enforce the mode on a `Task()` child.

## Per-Stage Recommended Flag Sets

The minimum recommended flag set per stage when dispatching from a headless runner. Substitute concrete IDs from `task.metadata` at call time.

| Stage | Canonical headless one-liner |
|---|---|
| **DV** | `claude agents run --cwd "$WORKTREE" --model claude-opus-4-8 --effort xhigh --permission-mode bypassPermissions -- igrsoft:developer < dv-prompt.txt` |
| **DR** | `claude agents run --cwd "$WORKTREE" --model claude-opus-4-8 --effort high --permission-mode acceptEdits -- igrsoft:technical-lead < dr-prompt.txt` |
| **SR** | `claude agents run --cwd "$WORKTREE" --model claude-opus-4-8 --effort xhigh --permission-mode default -- igrsoft:security-reviewer < sr-prompt.txt` |
| **QA** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort high --permission-mode acceptEdits -- igrsoft:qa-engineer < qa-prompt.txt` |
| **FN** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort medium --permission-mode default -- igrsoft:project-manager < fn-prompt.txt` |
| **RE** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort medium --permission-mode default -- igrsoft:release-engineer < re-prompt.txt` |
| **ST** | `claude agents run --cwd "$WORKTREE" --model claude-sonnet-4-6 --effort medium --permission-mode acceptEdits -- igrsoft:stakeholder < st-prompt.txt` |

The model/effort defaults track `skills/shared/model-selection.md`. Override per task when `metadata.model` / `metadata.effort` are set.

## Live Session Discovery (v2.1.145–146)

`claude agents --json` (CC v2.1.145+, refined in v2.1.146) returns a JSON array of currently-live Claude sessions. The orchestrator and external runners can poll this to discover *what is already running* — complementing the dispatch table above which covers *how to start* something headlessly.

Canonical orchestrator shell-out, scoped to one worktask track:

```bash
claude agents --json | jq -r --arg track "$TRACK_ID" '
  .[] | select(.metadata.worktask_track == $track) | .agent_id'
```

Three usage patterns:

- **Resume pre-check** — before respawning a subagent during worktask resume, query live sessions; if any `agent_id` from `.context/state.json.facts.dispatched_agents[]` still appears, prefer `SendMessage` reattach over re-delegation. Eliminates the "blind respawn of an already-working subagent" token-waste class. See `skills/worktask/SKILL.md § Resume Procedure` step 0.
- **Parallel track health** — for `--parallel:N` milestone runs, periodic `claude agents --json | jq '[.[] | select(.tag=="igrsoft-track")] | length'` should equal N. Less = stalled track.
- **Status-line integration** — drives tmux / shell-status-bar widgets showing the active worktask stage without polluting `.context/`.

Caveat: the CLI is stable but the JSON schema is not formally versioned — guard every read with defensive jq (`.parent_agent_id // "none"`). See § Schema Versioning Watch below.

### Schema Versioning Watch (v2.1.150 baseline)

The `claude agents --json` output schema is **not formally versioned** by Claude Code as of v2.1.150. Plugin consumers must defensively guard fields.

**Recorded baseline** (CC 2.1.150) — array of objects with these observed top-level fields:

- Required: `session_id` (string), `agent_type` (string), `agent_id` (string), `started_at` (ISO-8601 string)
- Optional: `parent_agent_id` (string), `cwd` (string), `tag` (string), `metadata` (object)

**Watch protocol for future `/cc-update` runs**: in any cc-update where the CC version delta touches `claude agents` CLI surface, the prompt-engineer MUST run `claude agents --json | jq 'first | keys'` and diff the key list against this recorded baseline. Surface any drift as a Q for the operator.

**Defensive jq pattern** (canonical for any plugin code reading this output):

```jq
.[] | {
  session: (.session_id // "unknown"),
  parent:  (.parent_agent_id // "none"),
  tag:     (.tag // "untagged")
}
```

**If the baseline shifts** (new required field, renamed field, type change), the next cc-update MUST bump min CC version and add a migration note to the relevant `cc-features-<from>-<to>.md` band file.

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

This is the one behaviour change the in-process orchestrator applies based on dispatch metadata. Every other flag listed above is advisory in-process and only takes effect when an external runner shells out `claude agents run …`.

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

## Background Shell Dispatch (v2.1.154)

CC v2.1.154 introduces two new ways to spawn background shell work without occupying a foreground agent turn:

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

## Related

- `skills/shared/task-system.md § Dispatch metadata` — schema for the new optional fields.
- `skills/agent-coordination/SKILL.md § Audit Trail` — schema for `permission_mode_pinned` and `external_dispatch` actions.
- `skills/shared/model-selection.md` — model/effort tier defaults the table above tracks.
- `agents/product-manager.md § Optional dispatch metadata` — PL0's writer rules for these fields.
- `commands/worktask.md § Headless dispatch` — canonical headless one-liner using `jq` to read the metadata.
