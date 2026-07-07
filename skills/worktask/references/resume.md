# Resume After Interruption — full procedure

Read on reattach from `skills/worktask/SKILL.md § Resume After Interruption` (stub). The orchestrator loop is restartable. On reattach (PostCompact, session crash, `--resume` flag), diagnose state via `TaskList()` + `.context/logs/audit.jsonl` tail before resuming.

## State → Action Table

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| No tasks | — | Worktask never initialized. Start over with `/worktask <task>` |
| PL0 only, `pending` | — | PL0 not started. Delegate PL0; after PL0 completes, the Step A.5 plan gate applies (STOP for approval unless `plan_gate == "bypass"`) |
| PL0 only, `in_progress` | no `subagent_stopped` for PL0 | PL0 crashed mid-stage. Re-delegate PL0 (idempotent) |
| PL0 `completed`, no stage tasks | — | PL0 did not create stages. Re-run PL0 |
| PL0 `completed`, stage tasks `pending`, no stage `in_progress` | No `approval_received` audit line for PL<run_index> | Branch on `PL<run_index>.metadata.plan_gate`. If `"bypass"` (`--auto-plan` / `--emergency`, or stamped by `/megatask`): stages not yet dispatched — re-enter the stage loop and delegate the first unblocked stage; do NOT stop. If `"checkpoint"` (default): parked at the post-plan human checkpoint — STOP and prompt for approval; proceed only once an `approval_received` line with `subject:"PL<run_index>"` is logged. |
| PL0 `completed`, `approval_received` present, some stages `in_progress` | most recent `subagent_stopped` `result: error` | Mid-stage failure. Read `.context/errors/<agent>.md`, honor `retry_count` |
| PL0 `completed`, all stages `completed` except FN, FN `pending`, audit tail has `fn_gate_waiting` for FN | No `approval_received` audit line for `FN<run_index>` | At the FN gate, parked. Branch on `PL<run_index>.metadata.fn_gate` (default `"checkpoint"`). If `"checkpoint"`: re-present the pre-FN summary (`references/fn-gate.md`), STOP, and delegate FN only once an `approval_received` line with `subject:"FN<run_index>"` is logged. If `"bypass"` (`--auto-finalization` / `--emergency`, or stamped by `/megatask`): proceed — delegate FN. |
| PL0 `completed`, all stages `completed` except FN | — | Near-done. Re-enter loop; the FN gate check (step 4.9) decides whether to STOP (`checkpoint`) or proceed (`bypass`) |
| Stages `in_progress` with no `metadata.retry_count` | missing audit lines | Stale task state. Re-derive from most recent `.context/logs/` capture |
| Any stage `in_progress` AND `claude agents --json --all` shows live `agent_id` matching that stage | — | Subagent still alive. Branch on `{state, waitingFor}` (see Resume Procedure step 0) — never blind re-delegate a live agent |
| Live `agent_id` matching that stage AND `waitingFor` = `approval`/`input` | — | Agent parked **on us**. Cheap `SendMessage` reattach with the awaited answer — do not re-delegate |
| Live `agent_id` matching that stage AND `waitingFor` = null/empty (mid-work) | — | Agent busy. **Leave it** — poll/await; do **not** double-dispatch or nudge |
| `agent_id` for an `in_progress` stage shows `state: blocked` | — | Alive but parked. Reattach via `SendMessage` — do not re-delegate |
| `agent_id` absent from `claude agents --json --all` (or `state: done`) for an `in_progress` stage | — | Agent gone. Re-delegate from the first incomplete stage |

## Resume Procedure

0. `claude agents --json --all | jq '.[] | {agent_id, state, waitingFor}'` — match rows against `.context/state.json.facts.dispatched_agents[]` (`--all` also surfaces completed and just-dispatched sessions) and branch directly:
   - live + `waitingFor` = `approval`/`input` → it is parked **on us**; `SendMessage` the awaited answer (cheap nudge, no re-dispatch).
   - live + `waitingFor` = null/empty (mid-work) → **leave it**; poll/await — do **not** `SendMessage` (avoids nudging a busy agent) and do **not** re-delegate.
   - `state` = `blocked` → alive but parked; **reattach** via `SendMessage`, do not re-delegate.
   - `state` = `done`, or the `agent_id` is genuinely absent even with `--all` → re-delegate from the first incomplete stage.

   This single pre-check eliminates three waste classes: blind respawn of an already-working subagent, redundant nudging of a busy one, and blind re-dispatch of an invisible blocked one. If the `claude agents` command is unavailable in the environment (runtime/tool fallback), skip the pre-check and re-delegate from the first incomplete stage. See `skills/agent-coordination/references/headless-dispatch.md § Live Session Discovery`.

   **`dispatched_agents[]` is now populated (v3.31.0).** The orchestrator loop writes one entry per `task_id` (`{stage, task_id, subagent_type, agent_id?, name?, model_requested?, model_resolved?, status}`), so this pre-check has real rows to match against — previously the field was referenced but never written. **Degrade rules for imperfect rows:**
   - **`agent_id` present** → match the `claude agents --json --all` row by id; branch per the table above.
   - **`agent_id` absent** (runtime surfaced no launch-ack) → best-effort match by `subagent_type` among the **non-interactive** rows (skip rows with `waitingFor = approval/input` — those are parked on us and matched by their own park signal). If exactly one candidate, adopt it; if ambiguous or none, **degrade to today's skip-precheck path** (re-delegate from the first incomplete stage).
   - **entry `status: completed|failed`** (terminal) → the stage already resolved; do not reattach — advance to the next incomplete stage. (Terminal entries are eviction candidates and may be absent after compaction; treat absence as "no live agent".)
   - **`stages.<CODE>.worktree.path` recorded** → re-enter the exact worktree with `EnterWorktree(path)` before resuming that stage (CC ≥ 2.1.157 mid-session worktree switching), so DR/QA/DV-retry run in the right directory rather than the shared checkout. The recorded `worktree.branch` gives the branch without shelling `git rev-parse`.

   **Reliability note (CC ≥ 2.1.172)**: the `state` signal got more trustworthy — CC 2.1.172 fixed background sub-agents staying stuck as `active` after a nested child they spawned was stopped, and removed the up-to-30s busy-spinner lag in the agents view. With nested spawning live (5 levels), only match **top-level** dispatched agents from `facts.dispatched_agents[]`; rows whose `parent_agent_id` points at another live row are the stage agent's own children — never reattach or re-delegate those directly. Nothing here is retired; the branch table above is unchanged.

   **Authority caveat**: a `SendMessage` reattach may *nudge* a parked agent (supply an awaited answer, re-prompt) but **cannot authorize** anything — a relayed `SendMessage` does not carry the operator's permission authority (the receiver refuses relayed permission requests; auto mode blocks them). Permission escalations remain operator-owned and cannot be satisfied via a relayed message. (Note: the PL gate is operator-owned and cannot be satisfied by a relayed message either; this caveat covers both permission escalations and the PL approval gate.)

   **Trigger-delivery caveat (CC ≥ 2.1.183)**: scheduled-task and webhook trigger deliveries are classified as **task notifications** — in auto mode they can no longer approve a pending action or set a session title. A trigger-delivered event therefore does **not** satisfy a `waitingFor = approval` park (treat it like a relayed message, not operator authority): keep the stage parked and resolve the approval through the operator-owned path. This extends the SendMessage-authority caveat above to trigger deliveries.

   **Reattach reliability (CC ≥ 2.1.183)**: subagent messages sent while the subagent is finishing its turn are no longer dropped, and `ctrl+b` no longer restarts the session on reattach — a mid-turn reattach is now reliable and will not lose the awaited answer.

   **Background-agent reliability (CC 2.1.185→2.1.202)**: (a) sessions that finish or need input fire the `Notification` hook (`agent_completed` / `agent_needs_input`, CC ≥ 2.1.198) — prefer these push signals as the resume wake-up; the `claude agents --json` pre-check above stays the authoritative reconciliation. (b) An errored subagent surfaces as an **error with partial work preserved** instead of an empty success (CC ≥ 2.1.199/2.1.200) — trust `subagent_stopped` `result: error` rows. (c) A stopped background agent stays stopped (CC ≥ 2.1.191), and a worker killed by a daemon restart auto-resumes from where it left off when the agents view next opens (CC ≥ 2.1.196) — re-delegate only when the pre-check shows the agent truly absent. (d) Waking a background job can no longer delete its transcript and re-run the original prompt (CC ≥ 2.1.196). (e) Long-running background commands survive the session process being stopped/restarted/updated (CC ≥ 2.1.196), and locked `.git/worktrees/` entries from killed agents are cleaned automatically (CC ≥ 2.1.187) — stale-worktree cleanup is no longer a resume chore. (f) `SendMessage` detects a re-spawned agent reusing a previous agent's name and asks the caller to retarget (CC ≥ 2.1.199) — closes the misroute hazard when re-dispatching a stage under the same name; session `/rename` persists across background restarts on CC ≥ 2.1.202.
1. `tail -n 50 .context/logs/audit.jsonl | jq .` — last 50 audit lines
2. `TaskList()` — current Task System state
3. Cross-reference with `stage-contracts.md` — identify first incomplete stage
4. Re-read that stage's `.context/*.md` artifact (if partial)
5. If `metadata.retry_count > 0`, read `.context/errors/<agent>.md` for retry history
6. Continue from the execution loop's `while (tasks.some(...))` — no need to replay completed stages
7. Write a `resume` audit entry: `{actor: "orchestrator", action: "resume", subject: "<worktask_id>", result: "ok"}`

See `context-compression.md § PostCompact Recovery` for the compaction-specific flow.
