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
| Standard 8/10-stage | Default | Not recommended |
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
