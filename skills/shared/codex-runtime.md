---
name: codex-runtime
---

# Codex Runtime Adapter

This reference translates canonical Corpflow commands and agents to Codex. It is shared support
material, not a user-invocable skill.

## Paths

Treat `BASE_PLUGIN_ROOT` as the canonical plugin root. Hook entrypoints initialize it through
`corpflow_init_base_paths`; an interactive skill resolves it as two directories above its own
`SKILL.md`. Use `corpflow_plugin_path` for executable paths. Codex provides `PLUGIN_ROOT` and
`PLUGIN_DATA` to plugin hooks; Claude Code provides `CLAUDE_PLUGIN_ROOT` and
`CLAUDE_PLUGIN_DATA`. Shared logic consumes only the normalized `BASE_*` values.

## Command execution

Read the corresponding `commands/<name>.md` completely and apply its argument grammar, workflow,
write boundaries, and output contract. Translate only the host operations:

| Canonical Claude operation | Codex operation |
|---|---|
| `Task(...)` | `spawn_agent` with `fork_turns: "none"` |
| `TaskStop(id)` | `interrupt_agent` |
| `ListAgents()` | `list_agents` |
| `SendMessage(id, text)` | `send_message`; use `followup_task` when an idle agent must run again |
| `TaskOutput` / `Monitor` | `wait_agent`, or wait on the active command session |
| `AskUserQuestion` | `request_user_input` |
| `Skill(name)` | Invoke the installed `$name` skill or read its `SKILL.md` when it is support-only |
| `EnterWorktree(path)` / worktree shell | Run with `workdir` set to the absolute worktree and pass it to children as `WORKSPACE_ROOT` |
| `/name` handoff | `$name` in Codex-facing output |

Do not translate prose examples, persisted agent aliases, or ledger schemas. `cc-update` remains a
Claude Code maintenance workflow even when `$cc-update` launches it from Codex.

## Agent dispatch

1. Read the canonical `agents/<agent>.md` role file and the composed stage brief.
2. Resolve the dispatch fields with `corpflow_codex_dispatch_json`: `haiku` → `gpt-6-luna`,
   `sonnet` or `opus` → `gpt-6-sol`, and `fable` → `gpt-6-astra`. It copies the requested
   reasoning effort unchanged and emits the concrete model as `model_resolved`.
3. Call `spawn_agent` before writing a dispatch row. Spawn with a stable
   `cf_<stage>_<attempt>` task name, fresh context, the workspace path, role instructions, context
   references, and completion contract in the message. The task name is not an agent id.
4. Only after `spawn_agent` succeeds, record its returned identifier with
   `state-patch.sh --dispatch`; keep the alias in
   `model_requested` and store the concrete GPT model as `model_resolved` when completing the row.
5. Coordinate through Codex agent controls while respecting the current concurrency limit and the
   ledger DAG. Never invent an external plugin agent: invoke its installed skill or take the
   canonical project-tool fallback.

Never synthesize an agent id or mark a dispatch `launched` before the tool returns one. Only call
`wait_agent` when at least one real spawned agent is still live; an empty agent list is a dispatch
failure, not a reason to wait.

Codex versions may return an `agent_id` plus a canonical `task_name`, or only the canonical name.
Persist `agent_id` when present; otherwise persist the exact `task_name` (such as
`/root/cf_pl0_1`) in the existing ledger `agent_id` field. `state-patch.sh` accepts both forms. Use
the canonical name as the collaboration-tool target. Never derive one identifier from the other.

## Questions and failures

Use `request_user_input` for material choices, with the recommended option first. Treat missing
plugins, unavailable models, permission failures, and dispatch failures as the corresponding
existing Corpflow blocked/error class. Codex has no Claude model-switch or PermissionDenied hook;
the orchestrator records those failures directly.
