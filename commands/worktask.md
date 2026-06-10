---
name: worktask
description: Initialize a new worktask task with proper folder structure and Task System integration
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
> 1. Present the pre-FN summary (planned commits, branch, PR target, QA/DR verdicts) — see `skills/worktask/SKILL.md § FN Gate`
> 2. STOP. Do NOT mark FN `in_progress`; do NOT delegate to the FN agent
> 3. Wait for explicit human approval as above
> 4. Only then let FN run commits, push, and PR creation
>
> **Bypass flags** (skip BOTH gates): `--auto-continue`, `--milestone:N`, `--worktree`. These modes set `metadata.fn_gate = "bypass"` on PL0; the orchestrator's gate check honors that field.
>
> Receiving results from a subagent is NEVER approval. Only the HUMAN user's explicit text message qualifies.
>
> **TODO**: `/emergency` worktasks currently fall through to the standard PL0-gate path; FN-gate bypass for `/emergency` will be wired when the emergency trigger is formalized.

# Worktask Command

Initialize a new worktask task with proper folder structure and Task System integration.

> **CRITICAL CONSTRAINTS**
> - MUST use TaskCreate/TaskUpdate/TaskGet/TaskList for worktask state. Do NOT use Claude Code's built-in plan mode.
> - Every stage MUST be a Task System task. Do NOT skip TaskCreate.
> - If Task tools are unavailable, STOP and report. Do NOT fall back to alternative planning.

## Usage

```
/worktask --milestone:N              # Execute milestone N issues by priority
/worktask --milestone:N:ISSUE        # Execute specific issue from milestone N
/worktask "Task Title" [options]     # Execute a custom task
```

## Worktask Types

| Type | Stages | Trigger |
|------|--------|---------|
| Standard | PL→AR→TL→DV→DR→QA→DC→FN→ST | `/worktask` |
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
| `--dynamic` | Run the autonomous span (AR→…→QA/DC/RE, between the two human gates) on the native Workflow engine (`ultracode` tool). Both gates and the no-self-commit rule stay orchestrator-owned; degrades to the manual loop when the tool is absent. See `skills/worktask/references/dynamic-workflow.md`. |
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|all>` | Target platform |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 11-stage worktask |
| `--worktree` | Use git worktrees for issue isolation (requires --milestone). Configure `worktree.sparsePaths` in settings.json for large repos |
| `--no-gh-issue` | Skip the post-PL GitHub issue auto-publish step. Sets `metadata.no_gh_issue: true` on the PL0 task; `skills/worktask/references/publish-pl-issue.sh` audits `deferred`/`opted_out` and the stage loop continues as normal. |

## Examples

```bash
/worktask --milestone:1                  # Milestone mode (compose with --parallel:N, :ISSUE)
/worktask --milestone:1 --worktree       # Worktree mode (true parallel isolation)
/worktask "Add dark mode support"        # Standard mode (compose with --priority, --secure)
/emergency "Production login failing"    # Emergency
```

## Phase 1: Planning (execute immediately)

> **BINDING CONSTRAINTS FOR PHASE 1**
> 1. After PL0 completes: STOP. Do NOT call Write, Edit, Bash, or any file-modifying tool.
> 2. **Pre-work Prohibition**: Do NOT create, edit, or modify ANY project files during Phase 1. This includes localization files, accessibility IDs, config files, and source files. Only `mkdir -p .context/images .context/errors` and TaskCreate/TaskUpdate calls are permitted. ALL file modifications belong to DV stage or later.
> 3. **Context-Interruption Recovery**: If worktask execution is interrupted (auth flows, user clarifications, tool failures), upon resumption MUST verify: (a) PL0 task exists with status `completed`, (b) HUMAN USER sent explicit approval AFTER PL0 completed. If either is false, restart from appropriate phase.

1. **Parse** task description and flags (`--milestone`, `--secure`, `--auto-continue`, etc.). See **Embedded Command Detection** below.
2. **Detect embedded commands**: If the task description contains `/plugin:command` or `/command` patterns (e.g., `/skill-creator`, `/apple-developer:code-refactor`), extract them into `metadata.embedded_commands` as a comma-separated list. Remove the command prefix from the task description passed to PL0 but preserve the full arguments.
3. **Create context folders**: `mkdir -p .context/images .context/errors .context/logs`
3a. **Initialize state.json (handoff-protocol)**: Atomic-write `.context/state.json` seed using temp+fsync+rename per `skills/worktask/references/handoff-protocol.md#atomic-write`. PL0 stage marked `in_progress`. Schema per `handoff-protocol.md#state-json-schema`. Backward-compat: if creation fails (e.g. read-only filesystem), log a warning and continue — F1 fallback (legacy `metadata.context_files` mode) keeps the worktask operational.
   ```bash
   tmp=".context/.state.json.$$.${RANDOM}.tmp"
   cat > "$tmp" <<EOF
   {
     "version": 1,
     "worktask_id": "<slug>",
     "plan_file": ".context/planning-0.md",
     "platform": "<platform>",
     "run_index": 0,
     "stages": { "PL": { "status": "in_progress" } },
     "facts": { "files_modified": [], "tests_added": [], "decisions": [], "open_questions": [], "verdicts": {} },
     "handoffs": {}
   }
   EOF
   sync "$tmp" 2>/dev/null || true
   mv -f "$tmp" .context/state.json
   ```
3b. **Verify SubagentStop hook installed**: After state.json seed, verify `.claude/hooks/state-merge.sh` exists and is executable AND the plugin's `plugin.json` registers the SubagentStop hook entry. If the project-local hook is missing, copy from `${CLAUDE_PLUGIN_ROOT}/.claude/hooks/state-merge.sh`. This hook is the Layer 2 safety net that patches state.json when agents skip self-patching. See `initialization-patterns.md#hook-installation`.
   ```bash
   hook_src="${CLAUDE_PLUGIN_ROOT}/.claude/hooks/state-merge.sh"
   hook_dst=".claude/hooks/state-merge.sh"
   if [[ ! -x "$hook_dst" ]] && [[ -f "$hook_src" ]]; then
     mkdir -p .claude/hooks
     cp "$hook_src" "$hook_dst" && chmod +x "$hook_dst"
   fi
   ```
   **Regression guard**: If neither the plugin-registered hook NOR the project-local copy exist, emit a warning: `"⚠ state-merge.sh hook not installed — state.json will only be patched if agents self-merge (Layer 1) or orchestrator Step 6.5 fires (Layer 3). Run hook-install.sh to fix."` Do NOT block the worktask.
4. **TaskCreate PL0**: `TaskCreate({ subject: "PL0: Planning", description: "<task description>", metadata: { stage: "PL", agent: "igrsoft:product-manager", model: "opus", worktask_id: "<slug>", priority: "<priority>", fn_gate: "<required|bypass>", execution_mode: "<manual|dynamic>" } })` — `metadata.agent` MUST use fully-qualified `plugin:agent` form (`igrsoft:`, `apple-developer:`, etc.). Set `fn_gate: "bypass"` when invoked with `--auto-continue`, `--milestone:N`, or `--worktree`; otherwise `"required"`. Set `execution_mode: "dynamic"` when invoked with `--dynamic`; otherwise `"manual"` (the default). `execution_mode` only selects HOW the autonomous span runs (native Workflow engine vs the manual stage loop) — it does NOT change either approval gate.
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

**Step A — Publish approved plan to GitHub** (run BEFORE the stage loop, after
approval is confirmed):

    HELPER="${CLAUDE_PLUGIN_ROOT}/skills/worktask/references/publish-pl-issue.sh"
    if [ -f "$HELPER" ]; then
      bash "$HELPER"; true
    else
      LOG_DIR="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/logs"
      mkdir -p "$LOG_DIR"
      STATE_FILE="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/state.json"
      jq -cn --arg ts "$(date -u +%FT%TZ)" --arg dk "$(jq -r '.worktask_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo unknown):$(jq -r '.run_index // 0' "$STATE_FILE" 2>/dev/null || echo 0):gh_issue" \
        '{ts:$ts, actor:"orchestrator", action:"github_issue_created", subject:"PL0", result:"deferred", task_id:"1", metadata:{via:"publish-pl-issue.sh", reason:"helper_not_found", dedupe_key:$dk}}' \
        >> "$LOG_DIR/audit.jsonl"; true
    fi

- The trailing `; true` is mandatory — the helper is non-blocking by contract.
  A helper failure MUST NEVER fail the worktask.
- The helper self-skips (`--no-gh-issue`, milestone mode, already published,
  missing `gh`/auth/remote) — each exits 0 and audits a `deferred` row.
  Sanitiser rules + non-blocking guarantee: `skills/worktask/SKILL.md § PL Issue Publish`.
- This step is NOT optional. Do not skip it because SKILL.md describes it —
  the orchestrator MUST run the command above as written.

**Step B — Select execution mode** (after Step A, before/around the stage loop):

Read `PL0.metadata.execution_mode` (default `"manual"` when absent).

- **Dynamic** (`execution_mode == "dynamic"` AND the `ultracode` tool present): dispatch the autonomous
  span (AR→…→QA/DC/RE, stopping before FN) per `skills/worktask/references/dynamic-workflow.md`
  (`#script-template`; `#milestone-template` + R1 one-confirmation multi-PR guard for `--milestone:N`).
  Audit `workflow_launched`; on return run `#boundary-reconciliation` + audit `workflow_returned`;
  **then evaluate the FN gate exactly as in the manual loop** — the span never crosses FN.
- **Otherwise** run the manual loop below unchanged; if `--dynamic` was requested but the tool is absent,
  write a `dynamic_fallback` audit row first. Crashed dynamic runs resume in manual mode
  (`dynamic-workflow.md#resume`).

Both gates are **orchestrator-owned in both modes**; the APPROVAL PROTOCOL blocks at the top of this
file are unaffected.

Execute the orchestrator execution loop from `skills/worktask/SKILL.md § Orchestrator Execution Loop`. The loop enforces a second approval gate immediately before any FN-stage task — see `skills/worktask/SKILL.md § FN Gate` for the pre-FN summary template and bypass semantics.

**BINDING: Workspace-root cross-check before every `Task()` delegation** — Conductor-managed sessions spawn the orchestrator inside a workspace clone whose `pwd` differs from the canonical plugin source repo. Before every `Task()` call in the stage loop, the orchestrator MUST verify that the working tree matches the task's declared workspace, and MUST inject the resolved root into the stage prompt so the subagent targets the right directory:

```bash
# Workspace-root cross-check (runs in orchestrator turn, not in subagent)
_orch_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
_task_root=$(jq -r '.metadata.workspace_path // empty' .context/state.json)
_task_root="${_task_root:-$_orch_root}"
if [ "$_orch_root" != "$_task_root" ]; then
  echo "⚠ cwd mismatch: orchestrator is at $_orch_root but task.metadata.workspace_path is $_task_root. Aborting delegation until resolved." >&2
  # Write audit row and STOP — do not call Task()
  exit 1
fi
```

The orchestrator MUST also append `WORKSPACE_ROOT=$_orch_root` as the first line of every stage prompt banner (section [7] suffix per the cache-prefix spec) so the subagent knows which directory to target. See `skills/worktask/references/workspace-modes.md § Conductor Workspace Topology` for the failure mode this guard prevents.

**BINDING: Post-delegation state.json enforcement** — After every `Task()` return, before `TaskUpdate(stage→completed)`: re-read `.context/state.json`; if `stages.<CODE>.status` is NOT `completed`, run
   ```bash
   CLAUDE_ARTIFACT_PATH=".context/<artifact>-N.md" \
   CLAUDE_TASK_METADATA_STAGE="<CODE>" \
   bash .claude/hooks/state-merge.sh
   ```
   then re-read; if STILL not `completed`, apply the F3 fallback (derive minimal patch from agent return text). This covers environments where the SubagentStop hook never fired. Full three-layer logic: `skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6.5.

## Phase 3: Post-Worktask Self-Improvement

After the execution loop exits (ST completed), run the Post-Worktask Self-Improvement procedure from `skills/worktask/SKILL.md § Post-Worktask Self-Improvement`.

Flow:
1. Check whether `.context/learnings.md` exists. If absent → worktask done, terminate.
2. If present → display its contents and **STOP**. Wait for the user to check the boxes of proposals they approve (`- [ ]` → `- [x]`). Orchestrator MUST NOT auto-check or assume.
3. User replies with approval ("apply checked", "go", or similar). Orchestrator then re-reads `learnings.md`, parses the checked items, and delegates to `igrsoft:prompt-engineer` for application (see `agents/prompt-engineer.md § Self-Improvement Patch Application`).
4. Each applied proposal becomes its own commit with a `version:` bump on the target frontmatter (rollback-safe via `git revert <sha>`).

Key invariants:
- Never auto-apply proposals — the user must explicitly check boxes AND signal approval.
- Proposals are scoped to agents/skills/commands that actually participated in this worktask's context (see `skills/self-improvement/SKILL.md § Step 4`).
- Post-ST audit entry written to `.context/logs/audit.jsonl` records `applied_count` and `skipped_count`.

## Embedded Command Detection

When the task description contains slash commands (e.g., `/skill-creator`, `/apple-developer:code-refactor`), these are **embedded commands** that must be executed during the appropriate worktask stage.

### Detection Rules

1. Scan the task description for patterns matching `/<plugin:command>` or `/<command>`
2. Match against available skills listed in the system (Skill tool's available skills)
3. Store detected commands in `metadata.embedded_commands` on the PL0 task
4. Pass the embedded command context to PL0 so the product-manager can plan around it

### Execution

During the orchestrator execution loop, when executing a DV stage task:

1. Check if the worktask's PL0 task has `metadata.embedded_commands`
2. If present, the DV stage agent prompt MUST include: "Execute embedded command(s) via the Skill tool: `<command>` with args: `<args>`"
3. The DV agent invokes `Skill("<command>", args: "<args>")` before or as part of its implementation work

### Examples

```
# User input:
/worktask /skill-creator deep analyze /path/to/source

# Parsed as:
# - Worktask task: "deep analyze /path/to/source"
# - Embedded command: skill-creator with args "deep analyze /path/to/source"
# - metadata.embedded_commands: "skill-creator"
# - DV stage prompt includes: "Invoke Skill('skill-creator', args='deep analyze /path/to/source')"

# User input:
/worktask /apple-developer:code-refactor src/Views/SettingsView.swift

# Parsed as:
# - Worktask task: "code-refactor src/Views/SettingsView.swift"
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
> fails. The user explicitly requested that specific worktask by embedding
> the command; ignoring it is a silent deviation from their intent.

The DV agent's prompt template enforces this: on Skill failure, it halts and
writes an error entry with `metadata.embedded_command_failure: true` before
returning to the orchestrator.

#### Escalation Target

- **If TL0 exists**: escalate to TL (team lead decides whether to retry,
  split the work, or revise approach).
- **If no TL0 (low-complexity worktask)**: escalate to PL. PL may add TL0 to
  the worktask, revise embedded command choice, or remove the embedding.

## Headless Dispatch (external runners)

External orchestrators (CI, cron, the user's shell) can invoke a single stage via `claude agents run …` instead of the in-process Task() path. PL0 populates the optional dispatch fields documented in `skills/shared/task-system.md § Dispatch metadata`; the runner reads them and builds the flag string. Full table and per-stage examples live in `skills/agent-coordination/references/headless-dispatch.md`.

Canonical one-liner (assumes `task.json` is one task's metadata blob and `prompt.txt` is the rendered stage prompt):

```bash
claude agents run \
  --cwd "$(jq -r '.metadata.workspace_path // "."' task.json)" \
  --plugin-dir "$PLUGIN_DIR" \
  --model "$(jq -r '.metadata.model // "claude-sonnet-4-6"' task.json)" \
  --effort "$(jq -r '.metadata.effort // "high"' task.json)" \
  --permission-mode "$(jq -r '.metadata.permission_mode // "default"' task.json)" \
  -- "$(jq -r .metadata.agent task.json)" < prompt.txt
```

The runner MUST append one `audit.jsonl` line `action: "external_dispatch"` per `skills/agent-coordination/SKILL.md § Audit Trail`. Do NOT pass `--dangerously-skip-permissions` from an interactive shell — it is reserved for CI batches with a deny-list in `settings.json`.

## See Also

- `skills/worktask/SKILL.md` — execution loop, dynamic sizing, worktask modes
- `skills/worktask/references/dynamic-workflow.md` — `--dynamic` native Workflow-engine execution mode
- `skills/worktask-milestone/SKILL.md` — milestone mode, worktree mode
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `skills/agent-coordination/references/headless-dispatch.md` — `task.metadata` → `claude agents` flag bridge
- `agents/workflow-engineer.md` — troubleshooting
