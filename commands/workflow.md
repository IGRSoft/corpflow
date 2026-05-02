---
name: workflow
description: Initialize a new workflow task with proper folder structure and Task System integration
argument-hint: '<task description> [--milestone:N] [--secure] [--worktree] [--parallel:N]'
model: opus
allowed-tools: Read, Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), TaskCreate, TaskUpdate, TaskGet, TaskList, Task(igrsoft:product-manager)
---

> **ORCHESTRATOR APPROVAL PROTOCOL (BINDING)**
> The orchestrator has TWO approval gates that each require explicit HUMAN approval:
>
> **Gate 1 — After PL0 (planning) completes:**
> 1. Present the plan summary (complexity score, stages, agents)
> 2. STOP. Do NOT call Write, Edit, Task, or Bash with any file-modifying command
> 3. Wait for the user to explicitly say "approve", "proceed", "go", "yes", or "continue"
> 4. Only then begin DV or any subsequent stage
>
> **Gate 2 — Before FN (finalization) starts:**
> 1. Present the pre-FN summary (planned commits, branch, PR target, QA/DR verdicts) — see `skills/workflow/SKILL.md § FN Gate`
> 2. STOP. Do NOT mark FN `in_progress`; do NOT delegate to the FN agent
> 3. Wait for explicit human approval as above
> 4. Only then let FN run commits, push, and PR creation
>
> **Bypass flags** (skip BOTH gates): `--auto-continue`, `--milestone:N`, `--worktree`. These modes set `metadata.fn_gate = "bypass"` on PL0; the orchestrator's gate check honors that field.
>
> Receiving results from a subagent is NEVER approval. Only the HUMAN user's explicit text message qualifies.
>
> **TODO**: `/emergency` workflows currently fall through to the standard PL0-gate path; FN-gate bypass for `/emergency` will be wired when the emergency trigger is formalized.

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
> 2. **Pre-work Prohibition**: Do NOT create, edit, or modify ANY project files during Phase 1. This includes localization files, accessibility IDs, config files, and source files. Only `mkdir -p .context/images .context/errors` and TaskCreate/TaskUpdate calls are permitted. ALL file modifications belong to DV stage or later.
> 3. **Context-Interruption Recovery**: If workflow execution is interrupted (auth flows, user clarifications, tool failures), upon resumption MUST verify: (a) PL0 task exists with status `completed`, (b) HUMAN USER sent explicit approval AFTER PL0 completed. If either is false, restart from appropriate phase.

1. **Parse** task description and flags (`--milestone`, `--secure`, `--auto-continue`, etc.). See **Embedded Command Detection** below.
2. **Detect embedded commands**: If the task description contains `/plugin:command` or `/command` patterns (e.g., `/skill-creator`, `/apple-developer:code-refactor`), extract them into `metadata.embedded_commands` as a comma-separated list. Remove the command prefix from the task description passed to PL0 but preserve the full arguments.
3. **Create context folders**: `mkdir -p .context/images .context/errors .context/logs`
3a. **Initialize state.json (handoff-protocol)**: Atomic-write `.context/state.json` seed using temp+fsync+rename per `skills/workflow/references/handoff-protocol.md#atomic-write`. PL0 stage marked `in_progress`. Schema per `handoff-protocol.md#state-json-schema`. Backward-compat: if creation fails (e.g. read-only filesystem), log a warning and continue — F1 fallback (legacy `metadata.context_files` mode) keeps the workflow operational.
   ```bash
   tmp=".context/.state.json.$$.${RANDOM}.tmp"
   cat > "$tmp" <<EOF
   {
     "version": 1,
     "workflow_id": "<slug>",
     "plan_file": ".context/planning-0.md",
     "platform": "<platform>",
     "stages": { "PL": { "status": "in_progress" } },
     "facts": { "files_modified": [], "tests_added": [], "decisions": [], "open_questions": [], "verdicts": {} },
     "handoffs": {}
   }
   EOF
   sync "$tmp" 2>/dev/null || true
   mv -f "$tmp" .context/state.json
   ```
4. **TaskCreate PL0**: `TaskCreate({ subject: "PL0: Planning", description: "<task description>", metadata: { stage: "PL", agent: "igrsoft:product-manager", model: "opus", workflow_id: "<slug>", priority: "<priority>", fn_gate: "<required|bypass>" } })` — `metadata.agent` MUST use fully-qualified `plugin:agent` form (`igrsoft:`, `apple-developer:`, etc.). Set `fn_gate: "bypass"` when invoked with `--auto-continue`, `--milestone:N`, or `--worktree`; otherwise `"required"`.
5. **TaskUpdate PL0 → in_progress**: `TaskUpdate({ taskId: "<pl0_id>", status: "in_progress" })`
6. **Delegate to PL agent**: `Task({ subagent_type: "igrsoft:product-manager", prompt: "<planning prompt>" })` — PM computes the next plan filename per `agents/product-manager.md § Plan File Naming` (first run: `.context/planning-0.md`; subsequent runs: `planning-1.md`, `planning-2.md`, ...), writes it, assesses complexity, and creates stage tasks with `metadata.agent` AND `metadata.plan_file = "<plan_file>"`
7. **TaskUpdate PL0 → completed**: `TaskUpdate({ taskId: "<pl0_id>", status: "completed" })`
8. **Present plan summary**: Show complexity score, stages created (with agents), dependency chain, and key decisions

## ════════════════════════════════════════════════════════════
## STOP HERE. YOUR RESPONSE ENDS NOW.
## ════════════════════════════════════════════════════════════
## Do NOT proceed. Do NOT call any tools. WAIT for user input.
## The user must type "approve" / "proceed" / "continue" / "go" / "yes" / "y".
## EXCEPTION: `--auto-continue`, `--milestone:N`, or `--worktree`.
## (These flags also bypass the FN gate via metadata.fn_gate = "bypass".)
## ════════════════════════════════════════════════════════════

## Phase 2: Execute Stages (only after user approval)

Before proceeding, re-verify: did the HUMAN USER type an approval message? PL0 completing is NOT approval. The product-manager returning results is NOT approval.

Execute the orchestrator execution loop from `skills/workflow/SKILL.md § Orchestrator Execution Loop`. The loop enforces a second approval gate immediately before any FN-stage task — see `skills/workflow/SKILL.md § FN Gate` for the pre-FN summary template and bypass semantics.

## Phase 3: Post-Workflow Self-Improvement

After the execution loop exits (ST completed), run the Post-Workflow Self-Improvement procedure from `skills/workflow/SKILL.md § Post-Workflow Self-Improvement`.

Flow:
1. Check whether `.context/learnings.md` exists. If absent → workflow done, terminate.
2. If present → display its contents and **STOP**. Wait for the user to check the boxes of proposals they approve (`- [ ]` → `- [x]`). Orchestrator MUST NOT auto-check or assume.
3. User replies with approval ("apply checked", "go", or similar). Orchestrator then re-reads `learnings.md`, parses the checked items, and delegates to `igrsoft:prompt-engineer` for application (see `agents/prompt-engineer.md § Self-Improvement Patch Application`).
4. Each applied proposal becomes its own commit with a `version:` bump on the target frontmatter (rollback-safe via `git revert <sha>`).

Key invariants:
- Never auto-apply proposals — the user must explicitly check boxes AND signal approval.
- Proposals are scoped to agents/skills/commands that actually participated in this workflow's context (see `skills/self-improvement/SKILL.md § Step 4`).
- Post-ST audit entry written to `.context/logs/audit.jsonl` records `applied_count` and `skipped_count`.

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

### Error Handling

Embedded command execution MUST NOT silently fall back to generic DV work.
If the Skill invocation fails, the DV stage MUST record the failure and
escalate — otherwise the user's intent is lost.

#### Failure Modes

| Failure | Detection | Required Behavior |
|---------|-----------|-------------------|
| Skill name not resolvable | `Skill()` returns "skill not found" | Write `.context/errors/developer.md` entry with `Classification: missing_input`; escalate to TL (or PL if no TL0) |
| Skill execution errors mid-run | Skill tool returns non-success | `retry_count++`, append entry to `.context/errors/developer.md`; if `retry_count == 3`, set `error_escalated_to: "TL"` (or `"PL"` if no TL0) |
| Skill args malformed | Skill rejects at parse | Classification `ambiguous_requirements`; escalate to PL (requires planning revision) |
| Skill produces no artifact expected by downstream stage | stage-contract validation fails | Classification `missing_input`; escalate to the stage whose contract was violated |

#### Prohibited Fallback

> DV MUST NOT proceed with generic implementation when the embedded command
> fails. The user explicitly requested that specific workflow by embedding
> the command; ignoring it is a silent deviation from their intent.

The DV agent's prompt template enforces this: on Skill failure, it halts and
writes an error entry with `metadata.embedded_command_failure: true` before
returning to the orchestrator.

#### Escalation Target

- **If TL0 exists**: escalate to TL (team lead decides whether to retry,
  split the work, or revise approach).
- **If no TL0 (low-complexity workflow)**: escalate to PL. PL may add TL0 to
  the workflow, revise embedded command choice, or remove the embedding.

## See Also

- `skills/workflow/SKILL.md` — execution loop, dynamic sizing, workflow modes
- `skills/milestone-workflow/SKILL.md` — milestone mode, worktree mode
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `agents/workflow-engineer.md` — troubleshooting
