# Hook-Based Stage Monitoring

Claude Code hook events enable automated monitoring of agent lifecycle within workflows.

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

> As of CC 2.1.77, the Agent tool `resume` parameter is removed. Use `SendMessage` to communicate with running agents instead.

> Parent agents reliably recover subagent results after context compaction. Background agents that are killed or interrupted preserve partial results in context, preventing total loss of intermediate work. The `PostCompact` hook can re-inject critical state after auto-compaction.

> Hook output exceeding 50K characters is saved to disk with a file path + preview injected into context instead of the full output (v2.1.89). This prevents large hook results from consuming context window budget.

> PreToolUse/PostToolUse hooks receive `file_path` as an absolute path for Write/Edit/Read tools, matching documented behavior (confirmed v2.1.89).

> `PreCompact` hook (v2.1.105+) fires **before** automatic compaction and can block it by returning exit code 2 — useful for guarding critical stage handoffs from premature summarization. See `context-compression` skill for the paired `PostCompact` recovery pattern. **As of plugin v3.10.0, `${CLAUDE_PLUGIN_ROOT}/hooks/precompact-checkpoint.sh` ships in `plugin.json` and snapshots `.context/state.json` to `.context/state.checkpoint-<ts>.json` on every compaction — never blocks (exit 0 always).**

> Background monitor support for plugins via `monitors` manifest key (v2.1.105+). Declare long-running monitors that stream events into the session without occupying a foreground tool call.

> Subagents that stall fail with a clear error after 10 minutes (v2.1.113). Orchestrators should surface this error and either retry the stage or escalate rather than waiting indefinitely. Crash fix (v2.1.114): permission dialog no longer crashes when an agent teams teammate requests tool permission.

### Managed (plugin) vs ad-hoc (user) hooks

**Plugin-managed hooks** ship in `.claude-plugin/plugin.json` and survive `allowManagedHooksOnly: true` enforcement. As of v3.10.0 the igrsoft plugin ships four managed hooks: `audit-tooluse` (PostToolUse), `audit-subagent` (SubagentStop), `precompact-checkpoint` (PreCompact), and a `mcp_tool` PushNotification at PL/FN Stop. The audit trail is a **plugin invariant** — these need to fire deterministically across every install.

**Ad-hoc user hooks** go in project `settings.json` (or `~/.claude/settings.json`) and are for opt-in workflows like dashboard webhooks or external SIEM forwarding. Examples below remain valid templates for that case.

### Project-Level Configuration

Add to project `settings.json` for workflow-wide monitoring:

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

## Conditional Hook Execution (v2.1.85+)

Hooks support an `if` field using permission rule syntax to avoid unnecessary process spawning. The `if` matcher correctly handles compound commands (`ls && git push`) and commands with env-var prefixes (`FOO=bar git push`) as of v2.1.89.

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

PreToolUse hooks can satisfy `AskUserQuestion` by returning `{ "updatedInput": "answer" }`, enabling automated responses in workflow pipelines without user interaction.

### PreToolUse Defer Decision (v2.1.89+)

PreToolUse hooks can return `"defer"` as the permission decision. This pauses headless (`-p`) sessions at the tool call, allowing later resumption with `-p --resume` to re-evaluate. Useful for CI/CD pipelines that need human approval at specific workflow gates.

### PreToolUse Blocking via Exit Code (v2.1.90+)

PreToolUse hooks emitting JSON to stdout with exit code 2 now correctly block tool calls. Previously this combination could be ignored.

### PermissionDenied Hook (v2.1.89+)

The `PermissionDenied` hook fires after auto-mode classifier denials. Return `{retry: true}` to tell the model it can retry the tool call. This enables workflow agents to recover from permission denials automatically.

### PostToolUse Format-on-Save (v2.1.90+)

PostToolUse format-on-save hooks no longer cause "File content has changed" errors between consecutive Edit/Write calls. Safe to use PostToolUse hooks that rewrite files (linters, formatters) without breaking subsequent edits.

### hookSpecificOutput.sessionTitle (v2.1.94+)

`UserPromptSubmit` hooks receive `hookSpecificOutput.sessionTitle` in their payload, enabling hooks to react to or log the session title.

### Hook Error Stderr (v2.1.98+)

Hook errors now include the first line of stderr in the transcript for self-diagnosis without `--debug`.

### Settings Resilience (v2.1.101+)

Unrecognized hook event names in `settings.json` no longer break the entire settings file. Forward-compatible hook configurations survive CC downgrades gracefully.

### permissions.deny Override (v2.1.101+)

`permissions.deny` rules now correctly override PreToolUse hook `permissionDecision: "ask"` decisions. A deny rule takes precedence over a hook that returns "ask".

### Plugin Hook allowManagedHooksOnly (v2.1.101+)

Plugin hooks from force-enabled plugins now run when `allowManagedHooksOnly` is set, restricting execution to managed hook types only.

### Main-Thread Agent Hooks (v2.1.116+)

Agent frontmatter `hooks:` now fire when the agent runs as a main-thread agent via `--agent <name>`. Previously hooks declared in agent frontmatter only ran for subagent invocations. Plugin agents that ship lifecycle hooks (e.g., audit-trail writers) now apply consistently in both subagent and main-thread modes. **Companion fix (v2.1.118)**: agent-type hooks no longer fail with "Messages are required for agent hooks" when configured for events other than `Stop`/`SubagentStop`.

### Agent Frontmatter mcpServers (v2.1.117+)

Agent frontmatter `mcpServers` are now loaded for main-thread agent sessions invoked via `--agent`. Plugin agents that declare MCP server requirements get the same server set in interactive `--agent` runs as in subagent delegations.

### MCP Tool Hooks (v2.1.118+)

Hooks can invoke MCP tools directly via `type: "mcp_tool"` (previously `command` and `http` only). Useful for hooks that need to call MCP server actions (e.g., elicitations, tool searches) without shelling out:

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

**Plugin v3.10.0 use:** `plugin.json` ships an `mcp_tool` hook on `Stop` matching `igrsoft:product-manager|igrsoft:project-manager` that fires `conductor.PushNotification` at the PL and FN approval gates. Gracefully no-ops if the conductor MCP server is unavailable.

### PostToolUse duration_ms (v2.1.119+)

`PostToolUse` and `PostToolUseFailure` hook inputs now include `duration_ms` — tool execution time excluding permission prompts and `PreToolUse` hooks. Useful for cost/perf telemetry and slow-tool alerting in workflow audit trails. **Plugin v3.10.0:** `${CLAUDE_PLUGIN_ROOT}/hooks/audit-tooluse.sh` consumes `duration_ms` + `effort.level` and writes `metadata` of every `audit.jsonl` `tool_invoked` row.

### PostToolUse Output Replacement (v2.1.121+)

`PostToolUse` hooks can now replace tool output for **all tools** (previously MCP-only) by setting `hookSpecificOutput.updatedToolOutput`. Workflow agents can use this to redact secrets, normalize line endings, or inject structured envelopes into tool results before they hit the model's context.

```json
{
  "hookSpecificOutput": {
    "updatedToolOutput": "<sanitized output>"
  }
}
```

> Async `PostToolUse` hooks that emit no response payload no longer write empty entries to the session transcript (v2.1.119 fix).

### Hook Effort Visibility (v2.1.133+)

Hook payloads now include `effort.level` (JSON field) and the `$CLAUDE_EFFORT` env var carries the active effort string (`low|medium|high|xhigh|max`). Audit/cost-tracking hooks can attribute spend to the effort tier without parsing model metadata. See `skills/shared/model-selection.md` for the tier model.

### Exec-Form Hook Commands (v2.1.139+)

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

### PostToolUse `continueOnBlock` (v2.1.139+)

PostToolUse hook entries support `continueOnBlock: true` so a blocking hook earlier in the chain does not short-circuit subsequent hooks in the same matcher group. Use when independent observers (audit + cost) must both run even if one signals block.

### Hook Terminal Sequences (v2.1.141+)

Hook JSON output accepts a `terminalSequence` field for emitting terminal control sequences — desktop notifications (OSC 9 / OSC 99), window-title updates (OSC 0/2), and bells (BEL `\x07`) — without the hook owning a controlling terminal. Useful for `SubagentStop`, `StopFailure`, and `Stop` hooks in headless or background sessions where the parent UI should still notify the user.

```json
{
  "hookSpecificOutput": {
    "terminalSequence": "]9;Stage QA complete"
  }
}
```

Pair with the `monitors` manifest key (v2.1.105+) for plugin-level lifecycle notifications that survive the lack of a TTY (CI, `claude agents` background dispatch).

### Hook Config Error Hints (v2.1.142+)

Configuring a prompt-type or agent-type hook for `SessionStart`, `Setup`, or `SubagentStart` is now rejected at load with a clear "use a command-type hook instead" message rather than a silent runtime no-op. Stage-lifecycle hooks that need to react before any session message exists MUST be `type: "command"` (or `type: "mcp_tool"`).

## Agent Teams Lifecycle Hooks

When agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), additional hook events are available:

| Hook Event | Fires When | Payload Fields | Use Case |
|------------|------------|----------------|----------|
| `TeammateIdle` | Teammate finishes work and becomes idle | `agent_id`, `agent_type` | Assign next task, reassign work |
| `TaskCompleted` | A task in the shared task list is completed | `agent_id`, `agent_type` | Trigger dependent stages, update orchestrator |

These hooks enable event-driven orchestration in milestone mode, where the lead session can react to teammate progress automatically.

### Stopping Teammates Programmatically

`TeammateIdle` and `TaskCompleted` hook handlers can return a stop signal to terminate a teammate:

```json
{ "continue": false, "stopReason": "Issue completed — PR created" }
```

Use cases: stop teammate when its issue is complete, when milestone budget is exhausted, or when a blocking error requires lead intervention.

## Agent Teams vs Subagents

### Comparison for igrsoft Workflows

| Aspect | Subagents (Task tool) | Agent Teams (Teammate) |
|--------|----------------------|------------------------|
| Context | Own window, results return to caller | Fully independent sessions |
| Communication | Report back to parent only | Direct inter-teammate messaging |
| Coordination | Task dependencies (blockedBy) | Shared task list + messaging |
| Tool restrictions | `tools` frontmatter per agent | Inherits lead's permissions |
| Token cost | Lower (results summarized) | Higher (N context windows) |
| Nesting | Cannot spawn sub-subagents | Cannot spawn sub-teams |
| Source isolation | None by default; `isolation: worktree` in frontmatter | None by default; worktree mode recommended for milestone |

### When to Use Each

| Workflow Pattern | Subagents | Agent Teams |
|-----------------|-----------|-------------|
| Standard 9/11-stage | Default | Not recommended |
| Cross-plugin handoff (DV→apple-developer) | Default | Not applicable |
| Milestone sequential issues | Default (orchestrator) | Not recommended |
| Milestone parallel independent issues | Task-based tracks | Optional (experimental) |
| Cross-cutting research / competing hypotheses | Possible | Preferred |
| Code review from multiple perspectives | Possible | Preferred |

### Limitations

- Teammates cannot spawn their own teams or sub-agents (runtime-enforced)
- One team per session; clean up before starting another
- No session resumption for in-process teammates
- Higher token cost (~Nx for N teammates)
- `/clear` does not kill background agents — safe to clear main session during long runs
- Background bash processes spawned by subagents are properly cleaned up on exit

## MCP Elicitation

MCP servers can request structured input from users mid-task via interactive forms or browser URLs. Elicitation hooks enable workflow agents to intercept or customize these interactions.

### Hook Events

| Hook Event | Fires When | Use Case |
|------------|------------|----------|
| `Elicitation` | MCP server requests user input | Pre-fill defaults, validate requests, log elicitations |
| `ElicitationResult` | User responds to elicitation | Audit responses, transform data, route to agents |

### Workflow Integration

When agents interact with MCP servers (e.g., Xcode build, Figma, Chrome), elicitation requests may pause agent execution. Configure hooks to:
1. Log elicitation requests for audit trail
2. Pre-fill known values from task metadata
3. Route complex elicitations to the appropriate stage agent
