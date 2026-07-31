---
name: worktask
description: Initialize a new worktask task with proper folder structure and Task System integration
argument-hint: '<task description> [--secure] [--emergency] [--auto=[plan, decision, finalization]]'
version: 0.3.0
model: opus
allowed-tools: Read, Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), TaskCreate, TaskUpdate, TaskGet, TaskList, Task(igrsoft:product-manager)
---

> **EXECUTION MODEL (BINDING)** — two gates, two human checkpoints, plus an optional decision delegate.
> The **PL gate** is the post-plan human checkpoint: after PL0 completes, the orchestrator
> presents the generated plan and waits for explicit user approval (`AskUserQuestion`) before
> dispatching any implementation stage (AR/DV/...). It is carried by `PL0.metadata.plan_gate`, which
> defaults to `"checkpoint"`; `--auto=[plan]` (legacy alias `--auto-plan`) and `--emergency` stamp `"bypass"` to auto-proceed (a batch orchestrator such as `/megatask` instead stamps it directly on each per-issue PL0).
> The **decision gate** is carried by `PL0.metadata.decision_gate`, default `"user"`: PL open
> questions surface to the user at the plan gate. `--auto=[decision]` stamps `"auto"` — open
> questions are resolved by a Fable-model decision delegate instead of blocking on the user
> (see § Step A.4 Auto-Decision Pre-Pass). Escalation-class questions always fall back to the user.
> The **FN gate** is the pre-finalization human checkpoint: `PL0.metadata.fn_gate` defaults to
> `"checkpoint"`, so the orchestrator STOPs immediately before the FN `Task()` delegation, presents a
> pre-FN summary, and waits for `AskUserQuestion` approval before any commit/push/PR. It is stamped
> `"bypass"` only by `--auto=[finalization]` (legacy alias `--auto-finalization`) or `--emergency` (unattended fast-path); `/megatask` stamps it directly on each per-issue PL0.
> Every worktask is worktree-isolated, so the PR is the review surface for the implementation.

# Worktask Command

Initialize a new worktask task with proper folder structure and Task System integration.

> **CRITICAL CONSTRAINTS**
> - MUST use TaskCreate/TaskUpdate/TaskGet/TaskList for worktask state. Do NOT use Claude Code's built-in plan mode.
> - Every stage MUST be a Task System task. Do NOT skip TaskCreate.
> - If Task tools are unavailable, STOP and report. Do NOT fall back to alternative planning.

## Usage

```
/worktask "Task Title" [options]     # Execute a single task through the staged pipeline
```

> **Multi-issue batches moved to `/megatask`.** To execute a GitHub milestone or an array of issues
> with dependency/blocker ordering, use `/megatask N` or `/megatask --issues 12,15,18`. `/worktask`
> is strictly single-issue and milestone-agnostic — it has no `--milestone` flag. See
> `commands/megatask.md` and `skills/megatask/SKILL.md`.

## Worktask Types

| Type | Stages | Entry point |
|------|--------|-------------|
| Standard | PL→AR→TL→DV→DR→QA→DC→FN→ST | `/worktask` |
| Secure | PL→AR→TL→DV→DR→SR→QA→DC→RE→FN→ST | `/worktask --secure` |
| Emergency | IR→DV→DR→QA→RE→FN | `/worktask --emergency` |

AR and TL are optional within the standard and secure pipelines: AR is a tier default PL0 may
override in either direction, and TL is included only when PL0 splits the work across ≥2
developers. Criteria: `skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria (PL0
authority)`.

See `skills/shared/stage-codes.md` for stage details.

## Options

### Gate automation flag (`--auto`)

`--auto=[<values>]` takes an **array** of automation values — any non-empty subset of
`plan`, `decision`, `finalization`, comma-separated. Brackets are optional and whitespace inside
them is tolerated: `--auto=[plan, decision]`, `--auto=plan,finalization`, and `--auto=[decision]`
are all valid. An unknown value is a parse error — reject the invocation and report; do NOT drop
the value silently. Each value is independent (orthogonal carriers on PL0).

#### Gate automation flag — values

| Value | Effect |
|-------|--------|
| `plan` | Stamp `plan_gate: "bypass"` — skip the post-PL plan-approval STOP and auto-proceed into the stage loop (trusted fast-path). FN gate is independent — still checkpoints unless `finalization` is also set. |
| `decision` | Stamp `decision_gate: "auto"` — when PL0 surfaces `open_questions[]`, delegate their resolution to a **Fable-model decision pass** (§ Step A.4) instead of blocking on the user. Bypasses NO gate by itself: under a `checkpoint` plan gate the auto-decisions are presented (marked) for approval. Escalation-class questions (irreversible, scope-expanding, security-posture, spend) always fall back to the user. |
| `finalization` | Stamp `fn_gate: "bypass"` — skip the pre-FN finalization-approval STOP; auto commit/push/PR (trusted fast-path). Plan gate still applies unless `plan` is also set. |

#### Legacy aliases (deprecated)

| Legacy flag | Canonical equivalent |
|-------------|----------------------|
| `--auto-plan` | `--auto=[plan]` |
| `--auto-finalization` | `--auto=[finalization]` |

Both legacy flags remain accepted and compose with `--auto=[...]` (union of values). New
invocations and documentation MUST use the array form.

### Scope and pipeline flags

| Option | Effect |
|--------|--------|
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|systems\|backend\|ai\|all>` | Target platform |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 11-stage worktask |
| `--emergency` | Run the incident pipeline (IR→DV→DR→QA→RE→FN) instead of the standard PL-first pipeline; IR stage owned by `incident-responder`. Replaces the former `emergency:` prefix. |
| `--no-gh-issue` | Skip the post-PL GitHub issue auto-publish step. Sets `metadata.no_gh_issue: true` on the PL0 task; `skills/worktask/scripts/publish-pl-issue.sh` audits `deferred`/`opted_out` and the stage loop continues as normal. |

## Examples

```bash
/worktask "Add dark mode support"        # Standard mode (compose with --priority, --secure)
/worktask --emergency "Production login failing"   # Emergency (incident pipeline)
# Multi-issue: /megatask 1   (milestone)   or   /megatask --issues 12,15,18   (array)
```

## Phase 1: Planning (execute immediately)

> **BINDING CONSTRAINTS FOR PHASE 1**
> 1. **Pre-work Prohibition**: Do NOT create, edit, or modify ANY project files during Phase 1. This includes localization files, accessibility IDs, config files, and source files. Only `mkdir -p .context/designs .context/images .context/errors` and TaskCreate/TaskUpdate calls are permitted. ALL file modifications belong to DV stage or later.
> 2. **Context-Interruption Recovery**: If worktask execution is interrupted (auth flows, tool failures), upon resumption MUST verify that the PL0 task exists with status `completed`. If not, restart from the appropriate phase. (There are two human checkpoints — the PL gate at Step A.5 and the FN gate before finalization; the FN gate check applies (STOP on `checkpoint`, proceed on `bypass`) — `skills/worktask/SKILL.md § FN Gate`.)

### Steps 1–3 — Parse flags and create context folders

1. **Parse** task description and flags (`--secure`, `--auto=[plan, decision, finalization]` — plus the legacy aliases `--auto-plan`/`--auto-finalization` — `--emergency`, etc.). Resolve the `--auto` array per § Gate automation flag: strip optional brackets, split on commas, trim whitespace, union with any legacy aliases, reject unknown values. See **Embedded Command Detection** below.
2. **Detect embedded commands**: If the task description contains `/plugin:command` or `/command` patterns (e.g., `/skill-creator`, `/apple-developer:fix-refactor`), extract them into `metadata.embedded_commands` as a comma-separated list. Remove the command prefix from the task description passed to PL0 but preserve the full arguments.
3. **Create context folders**: `mkdir -p .context/designs .context/images .context/errors .context/logs`

### Step 3a — Initialize state.json (handoff-protocol)

3a. **Initialize state.json (handoff-protocol)**: Atomic-write `.context/state.json` seed using temp+fsync+rename per `skills/worktask/references/handoff-protocol.md#atomic-write`. PL0 stage marked `in_progress`. Schema per `handoff-protocol.md#state-json-schema`. **Re-run aware**: the seed MUST compute the next free planning index from any pre-existing `.context/planning-*.md` (NOT hard-code `0`) — on a re-run in a populated `.context/`, hard-coding `planning-0.md` would pin the old plan and cause PL0 to overwrite it. Backward-compat: if creation fails (e.g. read-only filesystem), log a warning and continue — F1 fallback (legacy `metadata.context_files` mode) keeps the worktask operational.

#### Step 3a snippets — init procedure

   The re-run-aware next-free-planning-index resolver (N=0 on a fresh `.context/`, nullglob-safe) and the atomic `state.json` seed write are canonical in `skills/worktask/references/initialization-patterns.md`. Compute N, then atomic-write the seed (`{version:1, worktask_id, plan_file: .context/planning-${N}.md, platform, run_index:N, stages.PL.status:in_progress, empty facts incl. dispatched_agents:[], handoffs:{}}`) per `handoff-protocol.md#atomic-write`.

   The seeded `plan_file` is the **path** shape (`.context/planning-${N}.md`), not a bare basename — task metadata carries the basename shape instead. Both are legal; see the `plan_file` shape boundary in `handoff-protocol.md § state.json schema`.

#### Step 3a field notes

   `facts.dispatched_agents: []` is seeded (additive, version:1) so the orchestrator loop appends per-`task_id` dispatch entries in place. The other v1 additive fields (`stages.<CODE>.completed_via`/`last_error`/`worktree`, `facts.capabilities`) are written on demand — do NOT seed them; their absence is meaningful. See `handoff-protocol.md#state-json-schema`.
### Step 3b — Verify SubagentStop hook installed

3b. **Verify SubagentStop hook installed**: After state.json seed, verify `.claude/hooks/state-merge.sh` exists and is executable AND the plugin's `plugin.json` registers the SubagentStop hook entry. If the project-local hook is missing, copy from `<plugin-root>/.claude/hooks/state-merge.sh` (resolved in the snippet below). This hook is the Layer 2 safety net that patches state.json when agents skip self-patching. See `initialization-patterns.md#hook-installation`.

#### Step 3b hook-install snippet

   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # Claude Code substitutes this token when loading this file
   # Empty? Substitute <plugin-root>: the dir containing .claude-plugin/plugin.json — two levels
   # above the worktask skill's base directory (see skills/shared/plugin-root-resolution.md).
   [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
   hook_src="$PLUGIN_ROOT/.claude/hooks/state-merge.sh"
   hook_dst=".claude/hooks/state-merge.sh"
   if [[ ! -x "$hook_dst" ]] && [[ -f "$hook_src" ]]; then
     mkdir -p .claude/hooks
     cp "$hook_src" "$hook_dst" && chmod +x "$hook_dst"
   fi
   ```

#### Step 3b regression guard

   **Regression guard**: If neither the plugin-registered hook NOR the project-local copy exist, emit a warning: `"⚠ state-merge.sh hook not installed — state.json will only be patched if agents self-merge (Layer 1) or orchestrator Step 6.5 fires (Layer 3). Run hook-install.sh to fix."` Do NOT block the worktask.
### Step 3c — Name the branch once (PL start)

3c. **Name the branch**: after the state.json seed and before `TaskCreate` for PL0, run
   `bash skills/worktask/scripts/branch-name.sh --goal "<task description>"`. This is the ONLY
   place a worktask branch is ever renamed — the once-only rule per
   `skills/shared/git-conventions.md § Branch Naming`. Every outcome exits 0 (a naming problem
   must never stop planning) and the step self-disables under `/megatask` or `--emergency`
   routing.

#### Step 3c — validate before stamping

   Capture the script's final `branch=<name>` stdout line; **before stamping it, verify it
   matches `^[A-Za-z0-9._/-]+$`** (defence in depth alongside the script's own emission
   validation and FN's re-validation before use — see `agents/project-manager.md § Final FN
   steps`) — a value that fails this check MUST be stamped as empty, never as-is. Stamp the
   result into `state.json facts.branch` (the script itself never writes state.json — see
   `skills/worktask/references/handoff-protocol.md § branch`).

### Step 4 — TaskCreate PL0

4. **TaskCreate PL0**: `TaskCreate({ subject: "PL0: Planning", description: "<task description>", metadata: { stage: "PL", agent: "igrsoft:product-manager", model: "opus", worktask_id: "<slug>", priority: "<priority>", plan_gate: "checkpoint", decision_gate: "user", fn_gate: "checkpoint", isolation: "worktree" } })` — `metadata.agent` MUST use fully-qualified `plugin:agent` form (`igrsoft:`, `apple-developer:`, etc.).

#### Step 4 — fn_gate stamping

Stamp `fn_gate`: default `fn_gate: "checkpoint"` (the orchestrator STOPs immediately before the FN `Task()` delegation and asks for finalization approval before any commit/push/PR — handled at SKILL.md loop step 4.9). Stamp `fn_gate: "bypass"` ONLY when the resolved `--auto` array contains `finalization` (canonical `--auto=[finalization]`; legacy alias `--auto-finalization`) OR when `--emergency` is set (incident pipeline finalizes unattended). `--auto=[plan]` MUST NEVER stamp `fn_gate: "bypass"` — it is orthogonal and bypasses only the plan gate. (A batch orchestrator such as `/megatask` stamps `fn_gate: "bypass"` directly on each per-issue PL0 — `/worktask` itself has no batch flag.)

#### Step 4 — plan_gate stamping

Also stamp `plan_gate`: default `plan_gate: "checkpoint"` (the orchestrator STOPs after PL0 and asks for plan approval before dispatching stages). Stamp `plan_gate: "bypass"` ONLY when the resolved `--auto` array contains `plan` (canonical `--auto=[plan]`; legacy alias `--auto-plan`) OR when `--emergency` is set (emergency pipeline runs unattended from IR — no plan approval gate). (A batch orchestrator such as `/megatask` stamps `plan_gate: "bypass"` directly on each per-issue PL0.) `plan_gate`, `decision_gate`, and `fn_gate` are the carriers resume logic branches on after interruption — see `skills/worktask/references/resume.md § State → Action Table`.

#### Step 4 — decision_gate stamping

Also stamp `decision_gate`: default `decision_gate: "user"` (PL open questions surface to the user at the plan gate — existing behavior). Stamp `decision_gate: "auto"` ONLY when the resolved `--auto` array contains `decision`. The carrier is consumed by two readers: the PM agent (holds no gate round-trip for questions — returns them in `open_questions[]`; see `agents/product-manager.md § Plan-Gate Open-Question Batching`) and the orchestrator's Step A.4 auto-decision pre-pass below. `decision_gate` bypasses neither `plan_gate` nor `fn_gate` — it only changes WHO answers PL0's open questions. `--emergency` leaves it at `"user"` (the incident pipeline has no PL stage, so the carrier is inert there). (A batch orchestrator such as `/megatask` stamps `decision_gate: "auto"` directly on each per-issue PL0.)

### Steps 5–6 — Dispatch the PL agent

5. **TaskUpdate PL0 → in_progress**: `TaskUpdate({ taskId: "<pl0_id>", status: "in_progress" })`
6. **Delegate to PL agent**: `Task({ subagent_type: "igrsoft:product-manager", prompt: "<planning prompt>" })` — PM computes the next free plan filename per `agents/product-manager.md § Plan File Naming` (glob+increment: first run `.context/planning-0.md`; subsequent runs `planning-1.md`, `planning-2.md`, ...), writes it, assesses complexity, and creates stage tasks with `metadata.agent` AND `metadata.plan_file = "<plan_file>"`. The `plan_file`/`run_index` already in the seeded `state.json` (step 3a) are provisional — PM recomputes and is authoritative.
#### Step 6 — record dropped stages

   - **Record dropped and added stages**: when PL0's dynamic sizing omits any of the full 9-stage pipeline (`PL→AR→TL→DV→DR→QA→DC→FN→ST`), PM stamps the PL0 task's `metadata.skipped_stages` (`{stage, reason}` list) so `state.json` self-documents the drops; when PL0 includes a stage beyond the tier default (AR0 forced at a low tier, TL0 at any tier), it stamps the symmetric `metadata.added_stages` with the identical `{stage, reason}` shape. See `agents/product-manager.md § Dynamic Worktask Sizing (PL0 Stage)`.
### Steps 7–8 — Complete PL0 and present the plan

7. **TaskUpdate PL0 → completed**: `TaskUpdate({ taskId: "<pl0_id>", status: "completed" })`
8. **Present plan summary**: Show complexity score, stages created (with agents), dependency chain, and key decisions, then continue to Phase 2, which runs the Plan Gate Check (Step A.5) before the stage loop.

## Phase 2: Execute Stages (proceeds automatically)

Phase 2 begins with the Auto-Decision Pre-Pass (Step A.4, no-op unless `decision_gate == "auto"` AND PL0 left open questions), then the Plan Gate Check (Step A.5): on a `checkpoint` plan gate the orchestrator presents the plan and waits for user approval before the stage loop; on `bypass` (`--auto=[plan]` / `--emergency`, or a gate stamped directly by `/megatask`) it proceeds directly.

### Step A.4 — Auto-Decision Pre-Pass (runs before Step A.5)

Read `PL0.metadata.decision_gate` via `TaskGet` (default `"user"` when absent) and PL0's
`open_questions[]` (typed handoff / plan-frontmatter — the numbered elicitation list from
`agents/product-manager.md § Plan-Gate Open-Question Batching`). This step is a **no-op** when
`decision_gate == "user"` or `open_questions[]` is empty/absent — fall through to Step A.5.

#### Auto-decision dispatch (Fable delegate)

When `decision_gate == "auto"` and `open_questions[]` is non-empty:

1. Append an `auto_decision_dispatched` audit row (`subject:"PL<N>"`, `metadata.questions: <count>`).
2. Re-dispatch the PM as a decision delegate on the **Fable model**:
   `Task({ subagent_type: "igrsoft:product-manager", model: "fable", prompt: <decision prompt> })`.
   The prompt carries the open-question list verbatim (each with its recommended default) and the
   plan file path; its duties are § Auto-decision recording contract below. **Model fallback**:
   apply loop step 5f exactly — if `facts.capabilities.fable_dispatch == "credit_blocked"`,
   dispatch on `"opus"` and audit `model_resolution_constrained`.

#### Auto-decision recording contract

The decision prompt instructs the delegate to decide every non-escalation question (default-biased
— deviate from the PM's recommended default only with stated evidence), apply the resulting
amendments to the plan's EXISTING mandatory anchors (`## requirements` / `## acceptance-criteria` /
`## scope`) in ONE batch pass, and return each decision as a typed-return `key_decisions[]` entry
prefixed `(auto-decided)`, plus any `escalate` items. It adds NO new anchor to `planning-N.md` —
the PL anchor set is exact (`skills/worktask/references/handoff-protocol.md § #anchor-allow-list`).
It does NOT re-run `state-patch.sh`: PL0 is already `completed`, so the plan amendments are its
only writes.

#### Auto-decision ledger merge (orchestrator)

3. On return the ORCHESTRATOR — not the delegate — merges the ledger via `atomicMergeStateJson`:
   append each decided item to `state.json facts.decisions[]` marked `(auto-decided)` and remove
   the resolved entries from `facts.open_questions[]`. This is what makes the decisions visible to
   AR/TL/DV, which read `facts.decisions`/`facts.open_questions` on stage entry
   (`skills/shared/stage-contracts.md`).
4. Append one `auto_decision_resolved` audit row (`subject:"PL<N>"`, `metadata: { decided: <count>,
   escalated: <count>, model_resolved: <alias>, decisions: [{question, answer, rationale}] }`) —
   the per-question rationale is carried there, one line each.

#### Escalation guard (BINDING)

The delegate MUST NOT auto-decide **escalation-class** questions: anything irreversible or
destructive (data deletion, force-push, external publication), scope-expanding beyond the task
description, security-posture-weakening, or spend-authorizing. It returns those as `escalate`
items. If any `escalate` items exist, Step A.5 runs as a **`checkpoint`** gate for those items
even when `plan_gate == "bypass"` — the user answers only the escalated questions, the batch
amendment pass applies their answers, then the bypass path resumes. Auto-decision never widens
what runs unattended; it only answers what a human would otherwise be interrupted for.

##### Escalation guard — unattended `/megatask` per-issue runs (PARK)

Under a `/megatask` per-issue run (detected by `PL0.metadata.megatask_group`) there is no user to
stop for. Instead of holding the checkpoint, **PARK the issue**: write
`workspace.json.execution.status: "failed"` with `execution.reason: "parked_escalation"`, append an
`escalation_parked` audit row (`subject:"PL<N>"`, `metadata.escalated: [<questions>]`), and STOP
this worktask without dispatching any stage. Parking rides the monitor's existing failure path
(`hooks/megatask-monitor.sh` settles only `completed`/`failed`): the track is freed, dependents
stay `blocked`, and the batch summary lists the issue with its unanswered escalate questions for a
follow-up interactive `/worktask`.

#### Presentation in the gate summary

On a `checkpoint` plan gate, the Step A.5 summary MUST list every auto-decided question with its
chosen answer marked `(auto-decided by Fable — see facts.decisions[] / audit)`, so the user
approves the decisions together with the plan. On `bypass`, the audit rows plus the merged
`facts.decisions[]` entries are the durable record.

### Step A.5 — Plan Gate Check (runs after Step A.4, before Step A publish)

Read `PL0.metadata.plan_gate` via `TaskGet` (default `"checkpoint"` when absent). Resolve the run
index `N` from `state.json.run_index` (default `0`).

#### Plan gate checkpoint path

**If `plan_gate == "checkpoint"`** (default — plain `worktask` with no bypass flag):
1. Read `state.json.plan_file` to locate the plan; accept either shape (`handoff-protocol.md § plan_file shape boundary`).
2. Present the plan summary to the user: complexity score, stages created (with agents),
   dependency chain, key decisions, and both inclusion decisions (see below).
3. Call `AskUserQuestion`:
   *"Here is the generated plan for your worktask. Approve to begin implementation, or describe
   any changes you want first."*
   (`AskUserQuestion` does not auto-continue on idle by default — the gate holds
   until a human answers. Keep the `/config` idle-timeout opt-in OFF on hosts that run gated
   worktasks; an idle auto-answer would count as an approval the operator never gave. A
   background-task completion notification is never this approval either — it explicitly
   states no human input occurred, so do not treat it as the operator's answer.)

##### Stage-inclusion decisions in the gate summary

The step-2 summary MUST show both decisions explicitly, each with its one-line reason drawn from
`skipped_stages`/`added_stages`:

- **AR** — included or excluded, and whether that deviates from the tier default (flag the
  deviation; a tier-default AR still states its reason for being kept).
- **TL** — included or excluded on the split-work test, naming the workstreams when included.

#### Plan gate approval / rejection audit rows

4. **On approval**, append one line to `.context/logs/audit.jsonl`, then proceed to Step A:
   ```json
   {"ts":"<ISO>","actor":"orchestrator","action":"approval_received","subject":"PL<N>","result":"ok"}
   ```
5. **On rejection / revision request**, append:
   ```json
   {"ts":"<ISO>","actor":"orchestrator","action":"approval_rejected","subject":"PL<N>","result":"rejected"}
   ```
   STOP — do NOT enter the stage loop. Surface the user's feedback; re-run PL0 if revisions are needed.

#### Plan gate bypass path

**If `plan_gate == "bypass"`** (stamped by `--auto=[plan]` — legacy `--auto-plan` — or `--emergency`, or directly by `/megatask` on a per-issue PL0): proceed directly to
Step A. No prompt, no approval line. Exception: unresolved `escalate` items from Step A.4 force a
`checkpoint`-style stop for those items first (§ Step A.4 Escalation guard) — once the user has
answered them, append the standard `approval_received subject:"PL<N>"` row (that row is what
§ PRECONDITION CHECK Signal 2b requires as the escalate resolution) and then resume the bypass path.

### Step A — Publish plan to GitHub (run BEFORE the stage loop)

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # Claude Code substitutes this token when loading this file
    # Empty? Substitute <plugin-root>: the dir containing .claude-plugin/plugin.json — two levels
    # above the worktask skill's base directory (see skills/shared/plugin-root-resolution.md).
    [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
    HELPER="$PLUGIN_ROOT/skills/worktask/scripts/publish-pl-issue.sh"

#### Step A snippet — continued: invoke helper, or audit a deferred row

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

#### Step A publish invariants

- The trailing `; true` is mandatory — the helper is non-blocking by contract.
  A helper failure MUST NEVER fail the worktask.
- The helper self-skips (`--no-gh-issue`, megatask per-issue mode — detected via
  `workspace.json` presence / `metadata.milestone`, already published,
  missing `gh`/auth/remote) — each exits 0 and audits a `deferred` row.
  Sanitiser rules + non-blocking guarantee: `skills/worktask/SKILL.md § PL Issue Publish`.
- One `.context/` ↔ one GitHub issue: a second or later run in the same `.context/`
  resolves the run-independent `.context/gh-issue.json` anchor and posts a follow-up
  comment instead of opening a duplicate. Protocol: `skills/gh-issue-dedup`.
- This step is NOT optional. Do not skip it because SKILL.md describes it —
  the orchestrator MUST run the command above as written.

#### After Step A — run the stage loop

Execute the orchestrator execution loop from `skills/worktask/SKILL.md § Orchestrator Execution Loop`. Before the FN `Task()` delegation the orchestrator applies the FN gate check (STOP on `checkpoint`, proceed on `bypass`) — see `skills/worktask/SKILL.md § FN Gate`.

#### Workspace-root cross-check (BINDING)

**BINDING: Workspace-root cross-check before every `Task()` delegation** — Conductor-managed sessions spawn the orchestrator inside a workspace clone whose `pwd` differs from the canonical plugin source repo. Before every `Task()` call in the stage loop, the orchestrator MUST verify that the working tree matches the task's declared workspace, and MUST inject the resolved root into the stage prompt so the subagent targets the right directory:

##### Cross-check snippet and prompt-banner injection

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

#### Post-delegation state.json enforcement (BINDING)

**BINDING: Post-delegation state.json enforcement** — After every `Task()` return (the *completed stage result* — under background-default subagents, that is the completion notification, not the launch acknowledgement; see `skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6.5), before `TaskUpdate(stage→completed)`: re-read `.context/state.json`; if `stages.<CODE>.status` is NOT `completed`, run
   ```bash
   CLAUDE_ARTIFACT_PATH=".context/<artifact>-N.md" \
   CLAUDE_TASK_METADATA_STAGE="<CODE>" \
   STATE_MERGE_VIA=step6_5 \
   bash .claude/hooks/state-merge.sh
   ```

##### Layer-3 stamp and F3 fallback

   `STATE_MERGE_VIA=step6_5` stamps `stages.<CODE>.completed_via=step6_5` so this synchronous Layer-3 path is distinguishable from the SubagentStop-hook Layer-2 default (`hook`). Then re-read; if STILL not `completed`, apply the F3 fallback (derive minimal patch from agent return text — the F3 patch stamps `completed_via: "f3"`). This covers environments where the SubagentStop hook never fired. Full three-layer logic: `skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6.5.

### Step B — AR-reference check at DV completion

Runs only when `.context/state.json` has a `stages.AR` entry (AR is optional — see `skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`). After DV0 completes and before dispatching DR0:

```bash
STRICT_FLAG=""
[ "${IGRSOFT_AR_REF_STRICT:-0}" = "1" ] && STRICT_FLAG="--strict"
# shellcheck disable=SC2086
skills/worktask/scripts/handoff-harness.sh --validate-frontmatter ".context/development-${N}.md" \
  --state .context/state.json $STRICT_FLAG
```

#### Step B rollout and opt-in

**Rollout — warn-only in 3.42.0.** With no opt-in the harness emits `warn:` lines and exits 0. Record each warning as an audit row and carry it into the DR dispatch prompt so DR checks the linkage:

```json
{"ts":"<ISO>","actor":"orchestrator","action":"ar_ref_check","subject":"DV<N>","result":"warn"}
```

A warning is **not** a `missing_input` block and never stops the transition.

**Early opt-in — `IGRSOFT_AR_REF_STRICT=1`.** Set the env var and the orchestrator passes `--strict`; violations become `fail:` lines with exit 1 and block the DR dispatch until DV fixes the reference. Use it to shake out dangling references before the next minor, which flips `--strict` to the default. The inverse guard (an architecture reference with no `stages.AR` entry) warns in both modes and never fails.

## Phase 3: Post-Worktask Self-Improvement

After the execution loop exits (ST completed), run the Post-Worktask Self-Improvement procedure from `skills/worktask/SKILL.md § Post-Worktask Self-Improvement`.

### Phase 3 flow

1. Check whether `.context/learnings.md` exists. If absent → worktask done, terminate.
2. If present → display its contents and **STOP**. Wait for the user to check the boxes of proposals they approve (`- [ ]` → `- [x]`). Orchestrator MUST NOT auto-check or assume.
3. User replies with approval ("apply checked", "go", or similar). Orchestrator then re-reads `learnings.md`, parses the checked items, and delegates to `igrsoft:prompt-engineer` for application (see `agents/prompt-engineer.md § Self-Improvement Patch Application`).
4. Each applied proposal becomes its own commit with a `version:` bump on the target frontmatter (rollback-safe via `git revert <sha>`).

### Phase 3 key invariants

- Never auto-apply proposals — the user must explicitly check boxes AND signal approval.
- Proposals are scoped to agents/skills/commands that actually participated in this worktask's context (see `skills/self-improvement/SKILL.md § Step 4`).
- Post-ST audit entry written to `.context/logs/audit.jsonl` records `applied_count` and `skipped_count`.

## Embedded Command Detection

When the task description contains slash commands (e.g., `/skill-creator`, `/apple-developer:fix-refactor`), these are **embedded commands** that must be executed during the appropriate worktask stage.

### Detection Rules

1. Scan the task description for patterns matching `/<plugin:command>` or `/<command>`
2. Match against available skills listed in the system (Skill tool's available skills)
3. Store detected commands in `metadata.embedded_commands` on the PL0 task
4. Pass the embedded command context to PL0 so the product-manager can plan around it

> **Leading stacked skills**: when the user stacks slash commands
> (`/worktask /skill-a do XYZ`), Claude Code itself loads up to 5 **leading** skills before the
> turn runs — the embedded command's SKILL instructions may already be in context at PL0 time.
> Extraction into `metadata.embedded_commands` is unchanged, and the DV-stage `Skill()` invocation
> stays mandatory (it is the execution trigger, not a context load). Re-invoking an already-loaded
> skill does not append a duplicate copy of its instructions, so the DV
> invocation is token-safe.

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
/worktask /apple-developer:fix-refactor src/Views/SettingsView.swift

# Parsed as:
# - Worktask task: "fix-refactor src/Views/SettingsView.swift"
# - Embedded command: apple-developer:fix-refactor with args "src/Views/SettingsView.swift"
# - metadata.embedded_commands: "apple-developer:fix-refactor"
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

### Canonical one-liner & runner rules

The copy-paste `claude agents run` one-liner (reads a task's `task.json` metadata + rendered `prompt.txt`), the `sonnet`-alias / `--permission-mode manual`↔`default` equivalence, the mandatory `external_dispatch` audit line, and the CI-only `--dangerously-skip-permissions` caveat all live in `skills/agent-coordination/references/headless-dispatch.md`.

## See Also

- `skills/worktask/SKILL.md` — execution loop, dynamic sizing, worktask modes
- `commands/megatask.md` / `skills/megatask/SKILL.md` — multi-issue milestone/array orchestration (the former `--milestone` surface)
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `skills/agent-coordination/references/headless-dispatch.md` — `task.metadata` → `claude agents` flag bridge
- `agents/workflow-engineer.md` — troubleshooting
