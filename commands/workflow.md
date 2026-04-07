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
| Standard | PL→AR→TL→DV→QA→DC→FN→ST | `/workflow` |
| Secure | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | `--secure` |
| Emergency | IR→DV→QA→RE→FN | `/emergency` |

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
| `--secure` / `--full` | Use 10-stage workflow |
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

1. **Parse** task description and flags (`--milestone`, `--secure`, `--auto-continue`, etc.)
2. **Create context folder**: `mkdir -p .context/images`
3. **TaskCreate PL0**: `TaskCreate({ subject: "PL0: Planning", description: "<task description>", metadata: { stage: "PL", agent: "product-manager", model: "opus", workflow_id: "<slug>", priority: "<priority>" } })`
4. **TaskUpdate PL0 → in_progress**: `TaskUpdate({ taskId: "<pl0_id>", status: "in_progress" })`
5. **Delegate to PL agent**: `Task({ subagent_type: "igrsoft:product-manager", prompt: "<planning prompt>" })` — PM creates `.context/planning.md`, assesses complexity, creates stage tasks with `metadata.agent`
6. **TaskUpdate PL0 → completed**: `TaskUpdate({ taskId: "<pl0_id>", status: "completed" })`
7. **Present plan summary**: Show complexity score, stages created (with agents), dependency chain, and key decisions

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

## See Also

- `skills/workflow/SKILL.md` — execution loop, dynamic sizing, workflow modes
- `skills/milestone-workflow/SKILL.md` — milestone mode, worktree mode
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `agents/workflow-engineer.md` — troubleshooting
