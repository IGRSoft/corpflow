# Resume After Interruption — full procedure

Read on reattach from `skills/worktask/SKILL.md § Resume After Interruption` (stub). The orchestrator loop is restartable. On reattach (PostCompact, session crash, `--resume` flag), diagnose state via `TaskList()` + `.context/logs/audit.jsonl` tail before resuming.

## State → Action Table

### Initialization rows

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| No tasks | — | Worktask never initialized. Start over with `/worktask <task>` |
| PL0 only, `pending` | — | PL0 not started. Delegate PL0; after PL0 completes, the Step A.5 plan gate applies (STOP for approval unless `plan_gate == "bypass"`) |
| PL0 only, `in_progress` | no `subagent_stopped` for PL0 | PL0 crashed mid-stage. Re-delegate PL0 (idempotent) |
| PL0 `completed`, no stage tasks | — | PL0 did not create stages. Re-run PL0 |

### Plan-gate row

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, stage tasks `pending`, no stage `in_progress` | No `approval_received` audit line for PL<run_index> | Branch on `PL<run_index>.metadata.plan_gate`. If `"bypass"` (`--auto=[plan]` / `--emergency`, or stamped by `/megatask`): stages not yet dispatched — re-enter the stage loop and delegate the first unblocked stage; do NOT stop. If `"checkpoint"` (default): parked at the post-plan human checkpoint — STOP and prompt for approval; proceed only once an `approval_received` line with `subject:"PL<run_index>"` is logged. |

### Auto-decision row

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, stage tasks `pending`, `PL0.metadata.decision_gate == "auto"`, PL0 handoff carries non-empty `open_questions[]` | `auto_decision_dispatched` for `PL<run_index>` present but no matching `auto_decision_resolved` | Auto-decision pass interrupted mid-delegate. Re-run `commands/worktask.md § Step A.4` — already-applied decisions are visible as `(auto-decided)` entries in `facts.decisions[]`; do not re-decide those — then continue to the plan-gate row above. Unanswered `escalate` items always STOP for the user, even on a `bypass` plan gate (a `/megatask` per-issue run never reaches this row — it parks instead: settled `failed` + `parked_escalation`, `commands/worktask.md § Step A.4 Escalation guard`). |

### Mid-stage & FN-gate rows

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, `approval_received` present, some stages `in_progress` | most recent `subagent_stopped` `result: error` | Mid-stage failure. Read `.context/errors/<agent>.md`, honor `retry_count` |
| PL0 `completed`, all stages `completed` except FN, FN `pending`, audit tail has `fn_gate_waiting` for FN | No `approval_received` audit line for `FN<run_index>` | At the FN gate, parked. Branch on `PL<run_index>.metadata.fn_gate` (default `"checkpoint"`). If `"checkpoint"`: re-present the pre-FN summary (`references/fn-gate.md`), STOP, and delegate FN only once an `approval_received` line with `subject:"FN<run_index>"` is logged. If `"bypass"` (`--auto=[finalization]` / `--emergency`, or stamped by `/megatask`): proceed — delegate FN. |

### Near-done & stale rows

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, all stages `completed` except FN | — | Near-done. Re-enter loop; the FN gate check (step 4.9) decides whether to STOP (`checkpoint`) or proceed (`bypass`) |
| Stages `in_progress` with no `metadata.retry_count` | missing audit lines | Stale task state. Re-derive from most recent `.context/logs/` capture |

### Live-agent rows — liveness branch

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| Any stage `in_progress` AND `claude agents --json --all` shows live `agent_id` matching that stage | — | Subagent still alive. Branch on `{state, waitingFor}` (see Resume Procedure step 0) — never blind re-delegate a live agent |
| Live `agent_id` matching that stage AND `waitingFor` = `approval`/`input` | — | Agent parked **on us**. Cheap `SendMessage` reattach with the awaited answer — do not re-delegate |
| Live `agent_id` matching that stage AND its status reads **"Needs input"** (sandbox / MCP-input / managed-settings prompt) | — | Parked **on us** but operator-owned. Reattach via `SendMessage` only to surface the prompt verbatim — never auto-answer or re-dispatch a duplicate for that stage |
| Live `agent_id` matching that stage AND `waitingFor` = null/empty (mid-work) | — | Agent busy. **Leave it** — poll/await; do **not** double-dispatch or nudge |

### Live-agent rows — parked or gone

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| `agent_id` for an `in_progress` stage shows `state: blocked` | — | Alive but parked. Reattach via `SendMessage` — do not re-delegate |
| `agent_id` absent from `claude agents --json --all` (or `state: done`) for an `in_progress` stage | — | Agent gone. Re-delegate from the first incomplete stage |
| **Several** `agent_id`s absent at once, all vanishing at the same timestamp, session run under `--max-budget-usd` | no per-stage failure rows | **Budget halt, not stage failure.** Reaching the cap denies new spawns *and* halts running background subagents, so healthy in-flight stages die together with no error of their own. Raise the budget, then re-dispatch — and do **not** increment `metadata.retry_count`: those 3 retries are reserved for genuine stage failures, and spending them on an external stop escalates a run that never actually failed |

## Resume Procedure

0. `claude agents --json --all | jq '.[] | {agent_id, state, waitingFor}'` — match rows against `.context/state.json.facts.dispatched_agents[]` (`--all` also surfaces completed and just-dispatched sessions) and branch directly:
   - live + `waitingFor` = `approval`/`input` → it is parked **on us**; `SendMessage` the awaited answer (cheap nudge, no re-dispatch).
   - live + status **"Needs input"** (sandbox / MCP-input / managed-settings prompt) → parked on us but **operator-owned**; reattach only to surface the prompt verbatim — never auto-answer or re-delegate.
   - live + `waitingFor` = null/empty (mid-work) → **leave it**; poll/await — do **not** `SendMessage` (avoids nudging a busy agent) and do **not** re-delegate.
   - `state` = `blocked` → alive but parked; **reattach** via `SendMessage`, do not re-delegate.
   - `state` = `done`, or the `agent_id` is genuinely absent even with `--all` → re-delegate from the first incomplete stage.

### Step 0 notes — why the pre-check

   This single pre-check eliminates three waste classes: blind respawn of an already-working subagent, redundant nudging of a busy one, and blind re-dispatch of an invisible blocked one. If the `claude agents` command is unavailable in the environment (runtime/tool fallback), skip the pre-check and re-delegate from the first incomplete stage. See `skills/agent-coordination/references/headless-dispatch.md § Live Session Discovery`.

### Step 0 notes — dispatched_agents matching

   **`dispatched_agents[]` is now populated (v3.31.0).** The orchestrator loop writes one entry per `task_id` (`{stage, task_id, subagent_type, agent_id?, name?, model_requested?, model_resolved?, status}`), so this pre-check has real rows to match against — previously the field was referenced but never written. **Degrade rules for imperfect rows:**
   - **`agent_id` present** → match the `claude agents --json --all` row by id; branch per the table above.
#### Degrade rules — absent or terminal rows

   - **`agent_id` absent** (runtime surfaced no launch-ack) → best-effort match by `subagent_type` among the **non-interactive** rows (skip rows with `waitingFor = approval/input` — those are parked on us and matched by their own park signal). If exactly one candidate, adopt it; if ambiguous or none, **degrade to today's skip-precheck path** (re-delegate from the first incomplete stage).
   - **entry `status: completed|failed`** (terminal) → the stage already resolved; do not reattach — advance to the next incomplete stage. (Terminal entries are eviction candidates and may be absent after compaction; treat absence as "no live agent".)
#### Worktree re-entry

   - **`stages.<CODE>.worktree.path` recorded** → re-enter the exact worktree with `EnterWorktree(path)` before resuming that stage (mid-session worktree switching), so DR/QA/DV-retry run in the right directory rather than the shared checkout. The recorded `worktree.branch` gives the branch without shelling `git rev-parse`.

### Step 0 notes — state-signal reliability

   The `state` signal is trustworthy — a background sub-agent no longer sticks as `active` after a nested child it spawned was stopped. With nested spawning (3 levels by default), only match **top-level** dispatched agents from `facts.dispatched_agents[]`; rows whose `parent_agent_id` points at another live row are the stage agent's own children — never reattach or re-delegate those directly.

   A resumed background agent restores its **own prompt and tool restrictions** instead of reverting to the default agent, so a live row matched to a stage is still that stage's agent. Prefer reattach over defensive re-dispatch: identity is no longer a reason to re-delegate.

### Step 0 notes — authority caveat

   **Authority caveat**: a `SendMessage` reattach may *nudge* a parked agent (supply an awaited answer, re-prompt) but **cannot authorize** anything — a relayed `SendMessage` does not carry the operator's permission authority (the receiver refuses relayed permission requests; auto mode blocks them). Permission escalations remain operator-owned and cannot be satisfied via a relayed message. (Note: the PL gate is operator-owned and cannot be satisfied by a relayed message either; this caveat covers both permission escalations and the PL approval gate.)

### Step 0 notes — trigger delivery & reattach

   **Trigger-delivery caveat**: scheduled-task and webhook trigger deliveries are classified as **task notifications** — in auto mode they cannot approve a pending action or set a session title. A trigger-delivered event therefore does **not** satisfy a `waitingFor = approval` park (treat it like a relayed message, not operator authority): keep the stage parked and resolve the approval through the operator-owned path. This extends the SendMessage-authority caveat above to trigger deliveries.

   **Reattach reliability**: subagent messages sent while the subagent is finishing its turn are not dropped, and `ctrl+b` does not restart the session on reattach — a mid-turn reattach is reliable and will not lose the awaited answer.

### Step 0 notes — background-agent guarantees

   Runtime-assured at the plugin's min CC — the resume loop may rely on all of these unconditionally:

#### Push & honest completion

   - **Push signals**: sessions that finish or need input fire the `Notification` hook (`agent_completed` / `agent_needs_input`) — prefer these as the resume wake-up; the `claude agents --json` pre-check above stays the authoritative reconciliation.
   - **Honest completion**: an errored subagent surfaces as an **error with partial work preserved**, never an empty success — trust `subagent_stopped` `result: error` rows. Result reporting waits for real completion instead of fabricating a done status for a still-running agent (a behavioral improvement, not a hard invariant — keep the fn-gate cross-check in `references/fn-gate.md`, "BG notification ≠ approval").
#### Stopped & work preservation

   - **Stopped means stopped**: a stopped background agent stays stopped; an agent killed by the operator never auto-respawns or re-runs a stale prompt; a worker killed by a daemon restart auto-resumes from where it left off when the agents view next opens — re-delegate only when the pre-check shows the agent truly absent.
   - **Work preservation**: waking a background job cannot delete its transcript or re-run the original prompt; returning to `claude agents` carries a running subagent's work over instead of restarting; long-running background commands survive the session process being stopped/restarted/updated; locked `.git/worktrees/` entries from killed agents are released by a periodic sweep once the owning process is gone — stale-worktree cleanup is not a resume chore.
#### Reattach, cross-spawn & inspection

   - **Reattach fidelity**: `SendMessage` detects a re-spawned agent reusing a previous agent's name and asks the caller to retarget; a background agent resumed via `SendMessage` does not stick as `failed`/`completed`; an explicit per-stage model override survives resume and follow-up `SendMessage` (see `skills/shared/model-selection.md § Per-Invocation Override`); session `/rename` persists across background restarts.
   - **Cross-spawn targeting**: `TaskStop`/`TaskOutput` find agents spawned by **another** agent and list them by id/description on error — resume can target a cross-spawned stage agent.
   - **Inspection**: completed background agents stay in `/tasks` until cleanup, and attaching shows the transcript immediately — a just-finished stage is still inspectable during resume. Reopening a stopped background session resumes it or reports why it cannot — treat a resume refusal as a signal to re-delegate, not a reason to retry blindly.

### Steps 1–7 — replay & audit

1. `tail -n 50 .context/logs/audit.jsonl | jq .` — last 50 audit lines
2. `TaskList()` — current Task System state
3. Cross-reference with `stage-contracts.md` — identify first incomplete stage
4. Re-read that stage's `.context/*.md` artifact (if partial)
5. If `metadata.retry_count > 0`, read `.context/errors/<agent>.md` for retry history
6. Continue from the execution loop's `while (tasks.some(...))` — no need to replay completed stages
7. Write a `resume` audit entry: `{actor: "orchestrator", action: "resume", subject: "<worktask_id>", result: "ok"}`

See `context-compression.md § PostCompact Recovery` for the compaction-specific flow.
