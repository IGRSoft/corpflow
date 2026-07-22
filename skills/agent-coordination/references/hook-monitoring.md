# Hook-Based Stage Monitoring

Claude Code hook events enable automated monitoring of agent lifecycle within worktasks.

## Subagent Lifecycle Hooks

| Hook Event | Fires When | Matcher | Payload Fields |
|------------|------------|---------|----------------|
| `SubagentStart` | Stage agent spawned | Agent type name (e.g., `igrsoft:developer`) | `agent_id`, `agent_type` |
| `SubagentStop` | Stage agent completes | Agent type name | `agent_id`, `agent_type` |
| `PermissionDenied` | Auto-mode classifier denies a tool call | — | Tool name, denial reason |
| `StopFailure` | API error causes turn end | — | Error details |
| `CwdChanged` | Working directory changes | — | New cwd path |
| `FileChanged` | Monitored file modified | — | File path |
| `TaskCreated` | TaskCreate tool called | — | Task ID, subject |
| `WorktreeCreate` | Worktree created | — | Worktree path |

### Later lifecycle events

| Hook Event | Fires When | Matcher | Payload Fields |
|------------|------------|---------|----------------|
| `MessageDisplay` | A message is displayed to the user | — | `message`, `role` (`user`/`assistant`), `display_type` |
| `SessionStart` | Session begins | — | `session_id`, `session_title`, `reloadSkills` (bool), `source` (session origin — a forked session reports `"fork"`, not `"resume"`) |
| `Notification` | Background agent needs input or finishes | — | reason ∈ `agent_needs_input` / `agent_completed` |

### Notification as resume wake-up

> **`Notification` as resume wake-up**: background sessions in `claude agents` that need input or finish fire the `Notification` hook with `agent_needs_input` / `agent_completed`. For worktask resume this is the push complement to polling `claude agents --json` — wire a `Notification` hook to nudge the orchestrator (or the operator, via PushNotification) the moment a parked stage needs an answer. The `--json` pre-check remains the authoritative reconciliation (`skills/worktask/references/resume.md` step 0).

> The Agent tool has no `resume` parameter. Use `SendMessage` to communicate with running agents instead.

### SessionStart reloadSkills

> **SessionStart `reloadSkills:true`**: when a `SessionStart` hook fires with `reloadSkills: true`, plugin skills are reloaded mid-session (e.g., after a `/reload-skills` command). Hot-reload re-announces **only changed skills** (delta, not the full set) — hooks listening on `SessionStart` must re-apply skill-specific initialization idempotently and must not assume every skill re-announces. The `sessionTitle` field (allows the agent to set the session title visible in the UI) is available alongside `reloadSkills`.

### SessionStart headless streaming

> **SessionStart headless streaming**: `SessionStart` hook events stream in headless sessions — a headless run cannot idle-reap remote workers mid-hook before the `SessionStart` handler finishes. Plugin hooks use `${CLAUDE_PLUGIN_ROOT}` exec-form (`type: command` + `args`); `${user_config.*}` shell-form hook commands are rejected at load, which does not affect them.

### Compaction recovery & hook-output guards

> Parent agents reliably recover subagent results after context compaction. Background agents that are killed or interrupted preserve partial results in context, preventing total loss of intermediate work. The `PostCompact` hook can re-inject critical state after auto-compaction.

> Hook output exceeding 50K characters is saved to disk with a file path + preview injected into context instead of the full output. This prevents large hook results from consuming context window budget.

> PreToolUse/PostToolUse hooks receive `file_path` as an absolute path for Write/Edit/Read tools, matching documented behavior.

### PreCompact & plugin monitors

> The `PreCompact` hook fires **before** automatic compaction and can block it by returning exit code 2 — useful for guarding critical stage handoffs from premature summarization. See `context-compression` skill for the paired `PostCompact` recovery pattern. **As of plugin v3.10.0, the managed hook `hooks/precompact-checkpoint.sh` (registered in `plugin.json`) snapshots `.context/state.json` to `.context/state.checkpoint-<ts>.json` on every compaction — never blocks (exit 0 always).**

> Background monitor support for plugins via the `monitors` manifest key. Declare long-running monitors that stream events into the session without occupying a foreground tool call.

### Stall timeout

> Subagents that stall fail with a clear error after 10 minutes. Orchestrators should surface this error and either retry the stage or escalate rather than waiting indefinitely.

### Gate-feedback contract & Stop/SubagentStop additionalContext

Stop and SubagentStop hooks may return `hookSpecificOutput.additionalContext` to feed remediation text back to the model **without** being labeled an error. Unlike a bare `{"decision":"block"}`, the `additionalContext` rides into the re-run's context as actionable guidance, turning a dead-end block into a fix instruction.

```json
{
  "decision": "block",
  "reason": "missing screenshots.md …",
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "run dv-screenshot-capture (apple-canvas/cli-fallback); headless is not a skip reason; expected manifest .context/images/<worktask_id>/screenshots.md"
  }
}
```

#### Gate-feedback contract (one contract, two surfaces)

**Gate-feedback contract (one contract, two surfaces).** Every worktask gate — hook-enforced *or* orchestrator-mediated — must return **structured remediation** that flows into the *next attempt's context*:

| Surface | Mechanism | Reference user |
|---------|-----------|----------------|
| Hook gate | `hookSpecificOutput.additionalContext` alongside `decision:block` | `hooks/dv-screenshot-gate.sh` (block path) |
| Orchestrator gate | inject `blockers[]` / `blocking_defects[]` verbatim into the re-dispatched stage prompt | `skills/worktask/SKILL.md` DR→DV / QA→DV loop-back (`gate_remediation_injected` audit row) |

#### Surface symmetry & unchanged block-path schema

The two surfaces are symmetric: the hook embeds remediation in the block JSON; the orchestrator embeds the upstream blocker list in the retry prompt. Keep them in sync when either changes. The block-path `decision:block` verb, the exit-0 discipline, and the `screenshot_gate_block` audit-row schema are unchanged — `hookSpecificOutput` is an additive stdout field only.

### OTEL Dispatch Tree Parenting

`claude_code.tool` OTEL spans carry `agent_id` and `parent_agent_id` attributes; subagent spans correctly nest under the dispatching `Agent` tool span rather than appearing as orphan roots.

**Plugin impact**: when an OTEL collector (Honeycomb/Datadog/Jaeger) is wired via `settings.json` → `otelExporter`, the PL→AR→TL→DV→DR→SR→QA→DC→RE→FN→ST dispatch becomes a single nested trace tree. Diagnostic value: spot which stage spawned an orphan span (= subagent that escaped the dispatch chain).

#### Hook-stdin forward-compat

**Hook-stdin forward-compat**: `parent_agent_id` is OTEL-side and not confirmed in Stop/SubagentStop hook stdin, but `audit-subagent.sh` and `agent-stop.sh` defensively capture it with `(.parent_agent_id // "none")` — no-op until CC surfaces it in hook payloads, automatically populated the moment it does. Paired with the `dedupe_key_extended` audit field (see `skills/agent-coordination/SKILL.md § Dedupe Key Migration`) the worktask gets parent-aware audit dedup without any future plugin release.

### Background Tasks & Crons Visibility

Stop/SubagentStop hook stdin payloads include `background_tasks` and `session_crons` arrays. The plugin captures these into audit rows for `/cost-report` cross-correlation (which cron/bg task was active when a stage spiked).

#### Captured fields

Captured fields (additive metadata on existing audit rows; written by `hooks/audit-subagent.sh` and `hooks/agent-stop.sh`):

- `background_tasks_count: ((.background_tasks // []) | length)`
- `background_task_ids: ((.background_tasks // []) | map(.id // .task_id // "unknown"))`
- `session_crons_count: ((.session_crons // []) | length)`
- `session_cron_ids: ((.session_crons // []) | map(.id // .cron_id // "unknown"))`

Dedupe unchanged: these are metadata-only; `dedupe_key` shape preserved. With nested sub-agent spawning, real `parent_agent_id` values flow in hook stdin — `hooks/audit-dedup.sh --check-mode` auto-detects them and switches base→extended dedupe keys with no code change (designed for exactly this cut-over in v3.10.6).

### OTEL `tool_parameters`, resource-attribute labels & log-event correlation

- `tool_decision` telemetry events carry a `tool_parameters` field — the decision span records *which* tool args were classified, not just the tool name. Lets cost/audit dashboards distinguish e.g. a `Bash git push` decision from a `Bash ls`.
- `OTEL_RESOURCE_ATTRIBUTES` values surface as **metric-datapoint labels**, not only on spans. Tag `worktask_id` / `stage` there to slice collector dashboards (Honeycomb/Datadog) per-stage without parsing span attributes.
- `claude_code.lines_of_code.count` carries a `model` attribute — per-model LoC attribution lands in collector dashboards for free; pairs with the fable/opus/sonnet/haiku stage split in `skills/shared/stage-codes.md` to show which tier wrote the code.
#### Log correlation & content limits

- OTEL log events carry `message.uuid`, `client_request_id`, and `tool_source` — message-level correlation and tool provenance across spans and audit rows without re-deriving IDs.
- `CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH` configures the 60 KB truncation limit on OTEL content attributes — set it alongside `OTEL_RESOURCE_ATTRIBUTES` when a collector enforces a payload ceiling.
#### Trace nesting & effort attribution

- Log events emitted outside the turn's async context (background/notification-triggered) carry the interaction span's trace context — a background-agent completion nests under the originating trace instead of appearing as an orphan.
- Session transcripts record the reasoning effort level on each assistant message, and the `subagentStatusLine` payload includes reasoning effort — effort attribution without parsing model metadata (pairs with `§ Hook Effort Visibility`).

#### BG-Task ID Schema Watch

**BG-Task ID Schema Watch**: the ID extraction uses a defensive coalesce `(.id // .task_id // "unknown")` / `(.id // .cron_id // "unknown")` because the canonical key name is not yet confirmed in CC docs. Any `"unknown"` value appearing in `background_task_ids` or `session_cron_ids` is a signal that CC has begun populating the arrays with payloads whose ID field name is neither `id` nor `task_id`/`cron_id`. When that happens, the next `/cc-update` should pin the canonical key (remove the coalesce) and update both hook scripts. Until then the coalesce keeps the capture working across whichever name CC chooses.

### Managed (plugin) vs ad-hoc (user) hooks

**Plugin-managed hooks** ship in `.claude-plugin/plugin.json` and survive `allowManagedHooksOnly: true` enforcement. As of v3.10.0 the igrsoft plugin ships four managed hooks: `audit-tooluse` (PostToolUse), `audit-subagent` (SubagentStop), `precompact-checkpoint` (PreCompact), and a `mcp_tool` PushNotification at PL/FN Stop. The audit trail is a **plugin invariant** — these need to fire deterministically across every install.

**Ad-hoc user hooks** go in project `settings.json` (or `~/.claude/settings.json`) and are for opt-in worktasks like dashboard webhooks or external SIEM forwarding. Examples below remain valid templates for that case.

### Project-Level Configuration

Add to project `settings.json` for worktask-wide monitoring:

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "igrsoft:.*",
        "hooks": [
          { "type": "command", "command": "./tools/log-stage-start.sh" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "./tools/log-stage-complete.sh" }
        ]
      }
    ]
  }
}
```

Hooks also support HTTP endpoints for external monitoring:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "hooks": [
          { "type": "http", "url": "https://dashboard.example.com/webhook/stage-complete" }
        ]
      }
    ]
  }
}
```

## Conditional Hook Execution

Hooks support an `if` field using permission rule syntax to avoid unnecessary process spawning. The `if` matcher correctly handles compound commands (`ls && git push`), commands with env-var prefixes (`FOO=bar git push`), and path-conditional `if` matchers on `Read`/`Edit`/`Write` tool calls match against the target file path. Path-glob anchoring: a single-segment `dir/**` in a hook `if:` condition matches only `<cwd>/dir` — write `**/dir/**` for any-depth matching.

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "if": "agent_type matches 'igrsoft:.*'",
        "hooks": [
          { "type": "command", "command": "./tools/log-stage-complete.sh" }
        ]
      }
    ]
  }
}
```

### PreToolUse Hook Automation

PreToolUse hooks can satisfy `AskUserQuestion` by returning `{ "updatedInput": "answer" }`, enabling automated responses in worktask pipelines without user interaction.

### PreToolUse Defer Decision

PreToolUse hooks can return `"defer"` as the permission decision. This pauses headless (`-p`) sessions at the tool call, allowing later resumption with `-p --resume` to re-evaluate. Useful for CI/CD pipelines that need human approval at specific worktask gates.

### PreToolUse Blocking via Exit Code

PreToolUse hooks emitting JSON to stdout with exit code 2 block the tool call — and the block holds even when the hook's stdout JSON fails schema validation. A malformed payload cannot silently downgrade an intended block to a pass.

### PermissionDenied Hook

The `PermissionDenied` hook fires after auto-mode classifier denials. Return `{retry: true}` to tell the model it can retry the tool call. This enables worktask agents to recover from permission denials automatically.

### PostToolUse Format-on-Save

PostToolUse format-on-save hooks do not cause "File content has changed" errors between consecutive Edit/Write calls. Safe to use PostToolUse hooks that rewrite files (linters, formatters) without breaking subsequent edits.

### hookSpecificOutput.sessionTitle

`UserPromptSubmit` hooks receive `hookSpecificOutput.sessionTitle` in their payload, enabling hooks to react to or log the session title.

### Hook Error Stderr & failure semantics

Hook errors include the first line of stderr in the transcript for self-diagnosis without `--debug`. `SessionStart`, `Setup`, and `SubagentStart` hooks exiting with code 2 do not hide their stderr either — the error shows in the transcript.

A hook-callback timeout is reported as a timeout, and hook infrastructure errors are reported as such — neither is misreported as a user rejection. Do not treat a timed-out or crashed hook as an operator deny; route it as a transient failure, not a refusal.

### Settings Resilience

Unrecognized hook event names in `settings.json` do not break the entire settings file. Forward-compatible hook configurations survive CC downgrades gracefully.

### permissions.deny Override & hook `ask` floor

`permissions.deny` rules correctly override PreToolUse hook `permissionDecision: "ask"` decisions — a deny rule takes precedence over a hook that returns "ask". In the other direction, auto mode cannot override a PreToolUse hook's `ask`: a hook `ask` floors the decision at a prompt, even for unsandboxed Bash.

### Plugin Hook allowManagedHooksOnly

Plugin hooks from force-enabled plugins run when `allowManagedHooksOnly` is set, restricting execution to managed hook types only.

### Main-Thread Agent Hooks

Agent frontmatter `hooks:` fire when the agent runs as a main-thread agent via `--agent <name>`, not only for subagent invocations. Plugin agents that ship lifecycle hooks (e.g., audit-trail writers) apply consistently in both subagent and main-thread modes, for events beyond `Stop`/`SubagentStop` too.

### Agent Frontmatter mcpServers

Agent frontmatter `mcpServers` are loaded for main-thread agent sessions invoked via `--agent`. Plugin agents that declare MCP server requirements get the same server set in interactive `--agent` runs as in subagent delegations.

### MCP Tool Hooks

Hooks can invoke MCP tools directly via `type: "mcp_tool"` (alongside `command` and `http`). Useful for hooks that need to call MCP server actions (e.g., elicitations, tool searches) without shelling out:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "hooks": [
          { "type": "mcp_tool", "server": "audit-mcp", "tool": "log_event" }
        ]
      }
    ]
  }
}
```

#### Matcher semantics

**Matcher semantics:** hook matchers with hyphenated identifiers **exact-match** rather than substring-matching — as of plugin v3.30.0 the Stop matcher is written with explicit wildcards (`.*igrsoft:product-manager.*|.*igrsoft:project-manager.*`, per the `mcp__server__.*` guidance) so it keeps firing regardless of how the runtime qualifies the agent name. Comma-separated matchers (`"Bash,PowerShell"`) do not fire — always use regex alternation (`Bash|PowerShell`), never commas.

#### Plugin v3.10.0 historical note

**Plugin v3.10.0 historical note:** `plugin.json` shipped an `mcp_tool` hook on `Stop` matching `igrsoft:product-manager|igrsoft:project-manager` that fired `conductor.PushNotification` at the PL and FN stages. The hook still fires at stage completion for observability (PushNotification). The PL stage is followed by a human plan-approval gate (Step A.5); the FN stage is now gated by a finalization checkpoint (`fn_gate`, default `"checkpoint"`) that STOPs before commit/push/PR unless bypassed by `--auto-finalization` / `--emergency` (a `/megatask` batch stamps `fn_gate: "bypass"` directly on each per-issue PL0). Gracefully no-ops if the conductor MCP server is unavailable.

### PostToolUse duration_ms

`PostToolUse` and `PostToolUseFailure` hook inputs include `duration_ms` — tool execution time excluding permission prompts and `PreToolUse` hooks. Useful for cost/perf telemetry and slow-tool alerting in worktask audit trails. **Plugin v3.10.0:** the managed hook `hooks/audit-tooluse.sh` (registered in `plugin.json`) consumes `duration_ms` + `effort.level` and writes `metadata` of every `audit.jsonl` `tool_invoked` row.

### PostToolUse Output Replacement

`PostToolUse` hooks can replace tool output for **all tools** by setting `hookSpecificOutput.updatedToolOutput`. Worktask agents can use this to redact secrets, normalize line endings, or inject structured envelopes into tool results before they hit the model's context.

```json
{
  "hookSpecificOutput": {
    "updatedToolOutput": "<sanitized output>"
  }
}
```

> Async `PostToolUse` hooks that emit no response payload do not write empty entries to the session transcript.

### Hook Effort Visibility

Hook payloads include `effort.level` (JSON field) and the `$CLAUDE_EFFORT` env var carries the active effort string (`low|medium|high|xhigh|max`). Audit/cost-tracking hooks can attribute spend to the effort tier without parsing model metadata. See `skills/shared/model-selection.md` for the tier model.

### Exec-Form Hook Commands

Hooks accept an `args: string[]` array next to `command`, avoiding shell-string quoting issues for commands with paths/spaces:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "hooks": [
          { "type": "command", "command": "./tools/log.sh", "args": ["--stage", "DV", "--json"] }
        ]
      }
    ]
  }
}
```

### PostToolUse `continueOnBlock` & mid-stream halt integrity

PostToolUse hook entries support `continueOnBlock: true` so a blocking hook earlier in the chain does not short-circuit subsequent hooks in the same matcher group. Use when independent observers (audit + cost) must both run even if one signals block. A hook's `{"continue": false}` halt holds even when the tool it is attached to fails or completes mid-stream — a halt cannot be dropped by tool-lifecycle races.

### Hook Terminal Sequences

Hook JSON output accepts a `terminalSequence` field for emitting terminal control sequences — desktop notifications (OSC 9 / OSC 99), window-title updates (OSC 0/2), and bells (BEL `\x07`) — without the hook owning a controlling terminal. Useful for `SubagentStop`, `StopFailure`, and `Stop` hooks in headless or background sessions where the parent UI should still notify the user.

```json
{
  "hookSpecificOutput": {
    "terminalSequence": "\u001b]9;Stage QA complete\u0007"
  }
}
```

Pair with the `monitors` manifest key for plugin-level lifecycle notifications that survive the lack of a TTY (CI, `claude agents` background dispatch).

### Hook Config Error Hints

Configuring a prompt-type or agent-type hook for `SessionStart`, `Setup`, or `SubagentStart` is rejected at load with a clear "use a command-type hook instead" message rather than a silent runtime no-op. Stage-lifecycle hooks that need to react before any session message exists MUST be `type: "command"` (or `type: "mcp_tool"`).

## Agent Teams Lifecycle Hooks

When agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), additional hook events are available:

| Hook Event | Fires When | Payload Fields | Use Case |
|------------|------------|----------------|----------|
| `TeammateIdle` | Teammate finishes work and becomes idle | `agent_id`, `agent_type` | Assign next task, reassign work |
| `TaskCompleted` | A task in the shared task list is completed | `agent_id`, `agent_type` | Trigger dependent stages, update orchestrator |

These hooks enable event-driven orchestration in megatask mode, where the lead session can react to teammate progress automatically.

### Stopping Teammates Programmatically

`TeammateIdle` and `TaskCompleted` hook handlers can return a stop signal to terminate a teammate:

```json
{ "continue": false, "stopReason": "Issue completed — PR created" }
```

Use cases: stop teammate when its issue is complete, when megatask budget is exhausted, or when a blocking error requires lead intervention.

> Background tasks a teammate launches survive the teammate finishing its turn — a `TeammateIdle` event does not imply the teammate's background work has stopped.

## Agent Teams vs Subagents

### Comparison for igrsoft Worktasks

| Aspect | Subagents (Task tool) | Agent Teams (`Agent(name: …)`) |
|--------|----------------------|------------------------|
| Context | Own window, results return to caller | Fully independent sessions |
| Communication | Report back to parent only | Direct inter-teammate messaging |
| Coordination | Task dependencies (blockedBy) | Shared task list + messaging |
| Tool restrictions | `tools` frontmatter per agent | Inherits lead's permissions |
| Token cost | Lower (results summarized) | Higher (N context windows) |
| Nesting | Up to 5 levels deep, foreground and background sharing one depth budget | Cannot spawn sub-teams |
| Source isolation | None by default; `isolation: worktree` in frontmatter | None by default; worktree mode recommended for megatask |

### When to Use Each

| Worktask Pattern | Subagents | Agent Teams |
|-----------------|-----------|-------------|
| Standard 9/11-stage | Default | Not recommended |
| Cross-plugin handoff (DV→apple-developer) | Default | Not applicable |
| Megatask sequential issues | Default (orchestrator) | Not recommended |
| Megatask parallel independent issues | Task-based tracks | Optional (experimental) |
| Cross-cutting research / competing hypotheses | Possible | Preferred |
| Code review from multiple perspectives | Possible | Preferred |

### Limitations

- Teammates cannot spawn their own teams (runtime-enforced). Foreground and background subagents share one 5-level nesting depth budget; whether the teammate runtime inherits that nesting is unverified — treat teammate→sub-agent spawning as unsupported until observed
- One implicit team per session — no create/teardown; spawn teammates with `Agent(name: …)` (`team_name` accepted but ignored)
- No session resumption for in-process teammates
- Higher token cost (~Nx for N teammates)
- `/clear` does not kill background agents — safe to clear main session during long runs
- Background bash processes spawned by subagents are properly cleaned up on exit

## MCP Elicitation

MCP servers can request structured input from users mid-task via interactive forms or browser URLs. Elicitation hooks enable worktask agents to intercept or customize these interactions.

### Hook Events

| Hook Event | Fires When | Use Case |
|------------|------------|----------|
| `Elicitation` | MCP server requests user input | Pre-fill defaults, validate requests, log elicitations |
| `ElicitationResult` | User responds to elicitation | Audit responses, transform data, route to agents |

### Worktask Integration

When agents interact with MCP servers (e.g., Xcode build, Figma, Chrome), elicitation requests may pause agent execution. Configure hooks to:
1. Log elicitation requests for audit trail
2. Pre-fill known values from task metadata
3. Route complex elicitations to the appropriate stage agent
