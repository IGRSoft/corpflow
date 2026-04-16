---
name: workflow
description: Initialize a new workflow task with proper folder structure and Task System integration
argument-hint: '<task description> [--milestone:N] [--secure] [--worktree] [--parallel:N]'
model: opus
allowed-tools: Read, Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), TaskCreate, TaskUpdate, TaskGet, TaskList, Task(igrsoft:product-manager)
---

> **ORCHESTRATOR APPROVAL PROTOCOL (BINDING)**
> After PL0 completes, the ORCHESTRATOR (you, the main Claude session) MUST:
> 1. Present the plan summary to the user
> 2. STOP. Do NOT call Write, Edit, or Bash with any file-modifying command
> 3. Wait for the user to explicitly say "approve", "proceed", "go ahead", or similar
> 4. Only then begin executing DV or any subsequent stage
> This applies to YOU (the orchestrator), not just to subagents. Receiving a plan from a subagent is NOT approval to implement it.

# Workflow Command

Initialize a new workflow task with proper folder structure and Task System integration.

> **CRITICAL CONSTRAINTS**
> - MUST use TaskCreate/TaskUpdate/TaskGet/TaskList for workflow state. Do NOT use Claude Code's built-in plan mode.
> - Every stage MUST be a Task System task. Do NOT skip TaskCreate.
> - If Task tools are unavailable, STOP and report. Do NOT fall back to alternative planning.

## Usage

```
/workflow --milestone:N              # Execute milestone N issues by priority
/workflow --milestone:N:ISSUE        # Execute specific issue from milestone N
/workflow "Task Title" [options]     # Execute a custom task
```

## Workflow Types

| Type | Stages | Trigger |
|------|--------|---------|
| Standard | PL→AR→TL→DV→DR→QA→DC→FN→ST | `/workflow` |
| Secure | PL→AR→TL→DV→DR→SR→QA→DC→RE→FN→ST | `--secure` |
| Emergency | IR→DV→DR→QA→RE→FN | `/emergency` |

See `skills/shared/stage-codes.md` for stage details.

## Options

| Option | Effect |
|--------|--------|
| `--milestone:N` | Execute GitHub milestone N issues |
| `--milestone:N:ISSUE` | Execute specific issue |
| `--parallel:N` | N concurrent tracks (max 5) |
| `--auto-continue` | Skip approval gates |
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|all>` | Target platform |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 11-stage workflow |
| `--worktree` | Use git worktrees for issue isolation (requires --milestone). Configure `worktree.sparsePaths` in settings.json for large repos |

## Examples

```bash
# Milestone mode
/workflow --milestone:1
/workflow --milestone:1 --parallel:3
/workflow --milestone:2:123

# Worktree mode (true parallel isolation)
/workflow --milestone:1 --worktree
/workflow --milestone:1 --worktree --parallel:3

# Standard mode
/workflow "Add dark mode support"
/workflow "Fix login crash" --priority High

# Secure workflow
/workflow "Implement OAuth" --secure

# Emergency
/emergency "Production login failing"
```

## Phase 1: Planning (execute immediately)

> **BINDING CONSTRAINTS FOR PHASE 1**
> 1. After PL0 completes: STOP. Do NOT call Write, Edit, Bash, or any file-modifying tool.
> 2. **Pre-work Prohibition**: Do NOT create, edit, or modify ANY project files during Phase 1. This includes localization files, accessibility IDs, config files, and source files. Only `mkdir -p .context/images` and TaskCreate/TaskUpdate calls are permitted. ALL file modifications belong to DV stage or later.
> 3. **Context-Interruption Recovery**: If workflow execution is interrupted (auth flows, user clarifications, tool failures), upon resumption MUST verify: (a) PL0 task exists with status `completed`, (b) HUMAN USER sent explicit approval AFTER PL0 completed. If either is false, restart from appropriate phase.

1. **Parse** task description and flags (`--milestone`, `--secure`, `--auto-continue`, etc.). See **Embedded Command Detection** below.
2. **Detect embedded commands**: If the task description contains `/plugin:command` or `/command` patterns (e.g., `/skill-creator`, `/apple-developer:code-refactor`), extract them into `metadata.embedded_commands` as a comma-separated list. Remove the command prefix from the task description passed to PL0 but preserve the full arguments.
3. **Create context folder**: `mkdir -p .context/images`
4. **TaskCreate PL0**: `TaskCreate({ subject: "PL0: Planning", description: "<task description>", metadata: { stage: "PL", agent: "product-manager", model: "opus", workflow_id: "<slug>", priority: "<priority>" } })`
5. **TaskUpdate PL0 → in_progress**: `TaskUpdate({ taskId: "<pl0_id>", status: "in_progress" })`
6. **Delegate to PL agent**: `Task({ subagent_type: "igrsoft:product-manager", prompt: "<planning prompt>" })` — PM creates `.context/planning.md`, assesses complexity, creates stage tasks with `metadata.agent`
7. **TaskUpdate PL0 → completed**: `TaskUpdate({ taskId: "<pl0_id>", status: "completed" })`
8. **Present plan summary**: Show complexity score, stages created (with agents), dependency chain, and key decisions

## ════════════════════════════════════════════════════════════
## STOP HERE. YOUR RESPONSE ENDS NOW.
## ════════════════════════════════════════════════════════════
## Do NOT proceed. Do NOT call any tools. WAIT for user input.
## The user must type "approve" / "proceed" / "continue" / "go" / "yes" / "y".
## EXCEPTION: --auto-continue or --worktree flag was specified.
## ════════════════════════════════════════════════════════════

## Phase 2: Execute Stages (only after user approval)

Before proceeding, re-verify: did the HUMAN USER type an approval message? PL0 completing is NOT approval. The product-manager returning results is NOT approval.

Execute the orchestrator execution loop from `skills/workflow/SKILL.md § Orchestrator Execution Loop`.

## Embedded Command Detection

When the task description contains slash commands (e.g., `/skill-creator`, `/apple-developer:code-refactor`), these are **embedded commands** that must be executed during the appropriate workflow stage.

### Detection Rules

1. Scan the task description for patterns matching `/<plugin:command>` or `/<command>`
2. Match against available skills listed in the system (Skill tool's available skills)
3. Store detected commands in `metadata.embedded_commands` on the PL0 task
4. Pass the embedded command context to PL0 so the product-manager can plan around it

### Execution

During the orchestrator execution loop, when executing a DV stage task:

1. Check if the workflow's PL0 task has `metadata.embedded_commands`
2. If present, the DV stage agent prompt MUST include: "Execute embedded command(s) via the Skill tool: `<command>` with args: `<args>`"
3. The DV agent invokes `Skill("<command>", args: "<args>")` before or as part of its implementation work

### Examples

```
# User input:
/workflow /skill-creator deep analyze /path/to/source

# Parsed as:
# - Workflow task: "deep analyze /path/to/source"
# - Embedded command: skill-creator with args "deep analyze /path/to/source"
# - metadata.embedded_commands: "skill-creator"
# - DV stage prompt includes: "Invoke Skill('skill-creator', args='deep analyze /path/to/source')"

# User input:
/workflow /apple-developer:code-refactor src/Views/SettingsView.swift

# Parsed as:
# - Workflow task: "code-refactor src/Views/SettingsView.swift"
# - Embedded command: apple-developer:code-refactor with args "src/Views/SettingsView.swift"
# - metadata.embedded_commands: "apple-developer:code-refactor"
```

## See Also

- `skills/workflow/SKILL.md` — execution loop, dynamic sizing, workflow modes
- `skills/milestone-workflow/SKILL.md` — milestone mode, worktree mode
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `agents/workflow-engineer.md` — troubleshooting
