# Resume After Interruption — full procedure

Read on reattach from `skills/worktask/SKILL.md § Resume After Interruption` (stub). The orchestrator loop is restartable. On reattach (PostCompact, session crash, `--resume` flag), diagnose state via `TaskList()` + `.context/logs/audit.jsonl` tail before resuming.

## State → Action Table

| TaskList Shape | Audit Tail | Action |
|----------------|------------|--------|
| No tasks | — | Worktask never initialized. Start over with `/worktask <task>` |
| PL0 only, `pending` | — | PL0 not started. Delegate PL0; proceed unattended into the stage loop (no approval gate) |
| PL0 only, `in_progress` | no `subagent_stopped` for PL0 | PL0 crashed mid-stage. Re-delegate PL0 (idempotent) |
| PL0 `completed`, no stage tasks | — | PL0 did not create stages. Re-run PL0 |
| PL0 `completed`, stage tasks `pending`, no stage `in_progress` | No `approval_received` audit line for PL0 | If `PL0.metadata.plan_gate == "bypass"` (unattended `/worktask`/`worktask:`/`fworktask:`): stages not yet dispatched — re-enter the stage loop and delegate the first unblocked stage; do NOT stop. If `PL0.metadata.plan_gate == "checkpoint"` (`micro:`/`quick:`): parked at the post-plan human checkpoint — STOP and prompt for approval; proceed only once `approval_received` is logged. |
| PL0 `completed`, `approval_received` present, some stages `in_progress` | most recent `subagent_stopped` `result: error` | Mid-stage failure. Read `.context/errors/<agent>.md`, honor `retry_count` |
| PL0 `completed`, all stages `completed` except FN, FN `pending`, audit tail has `fn_gate_waiting` for FN | — | At FN gate. Re-present pre-FN summary (`references/fn-gate.md`); STOP and wait for human approval (unless `PL0.metadata.fn_gate == "bypass"`) |
| PL0 `completed`, all stages `completed` except FN | — | Near-done. Re-enter loop; FN gate check decides whether to STOP or proceed |
| Stages `in_progress` with no `metadata.retry_count` | missing audit lines | Stale task state. Re-derive from most recent `.context/logs/` capture |
| Any stage `in_progress` AND `claude agents --json --all` shows live `agent_id` matching that stage | — | Subagent still alive. Branch on `{state, waitingFor}` (see Resume Procedure step 0) — never blind re-delegate a live agent |
| Live `agent_id` matching that stage AND `waitingFor` = `approval`/`input` | — | Agent parked **on us**. Cheap `SendMessage` reattach with the awaited answer — do not re-delegate |
| Live `agent_id` matching that stage AND `waitingFor` = null/empty (mid-work) | — | Agent busy. **Leave it** — poll/await; do **not** double-dispatch or nudge |
| `agent_id` for an `in_progress` stage shows `state: blocked` | — | Alive but parked. Reattach via `SendMessage` — do not re-delegate |
| `agent_id` absent from `claude agents --json --all` (or `state: done`) for an `in_progress` stage | — | Agent gone. Re-delegate from the first incomplete stage |
| `state.json.workflow.run_id` present, `workflow.status:"running"`, `Workflow` tool available | audit tail has `workflow_launched`, no `workflow_returned` | Dynamic span still in flight. `resumeFromRunId = workflow.run_id` — the engine replays the cached prefix and continues from the first incomplete stage (`dynamic-workflow.md#resume`). |
| `state.json.workflow.run_id` present, `Workflow` tool **absent** (cold resume in headless `claude agents run`, SDK / `--print`) | `workflow_launched` present, no live engine run | Degrade to manual mode: write `dynamic_fallback`, rebuild the ledger via F4 frontmatter walk if needed, continue the manual loop from the first incomplete stage. Resume is replay-or-degrade, never rejoin. |
| `state.json.workflow.run_id` present, `workflow.status:"returned"` | audit tail has `workflow_returned` | Span complete — re-enter at the FN gate (orchestrator-owned). Build the pre-FN summary from reconciled `state.json`. |

## Resume Procedure

0. `claude agents --json --all | jq '.[] | {agent_id, state, waitingFor}'` — match rows against `.context/state.json.facts.dispatched_agents[]` (`--all` also surfaces completed and just-dispatched sessions) and branch directly:
   - live + `waitingFor` = `approval`/`input` → it is parked **on us**; `SendMessage` the awaited answer (cheap nudge, no re-dispatch).
   - live + `waitingFor` = null/empty (mid-work) → **leave it**; poll/await — do **not** `SendMessage` (avoids nudging a busy agent) and do **not** re-delegate.
   - `state` = `blocked` → alive but parked; **reattach** via `SendMessage`, do not re-delegate.
   - `state` = `done`, or the `agent_id` is genuinely absent even with `--all` → re-delegate from the first incomplete stage.

   This single pre-check eliminates three waste classes: blind respawn of an already-working subagent, redundant nudging of a busy one, and blind re-dispatch of an invisible blocked one. If the `claude agents` command is unavailable in the environment (runtime/tool fallback), skip the pre-check and re-delegate from the first incomplete stage. See `skills/agent-coordination/references/headless-dispatch.md § Live Session Discovery`.

   **Reliability note (CC ≥ 2.1.172)**: the `state` signal got more trustworthy — CC 2.1.172 fixed background sub-agents staying stuck as `active` after a nested child they spawned was stopped, and removed the up-to-30s busy-spinner lag in the agents view. With nested spawning live (5 levels), only match **top-level** dispatched agents from `facts.dispatched_agents[]`; rows whose `parent_agent_id` points at another live row are the stage agent's own children — never reattach or re-delegate those directly. Nothing here is retired; the branch table above is unchanged.

   **Authority caveat**: a `SendMessage` reattach may *nudge* a parked agent (supply an awaited answer, re-prompt) but **cannot authorize** anything — a relayed `SendMessage` does not carry the operator's permission authority (the receiver refuses relayed permission requests; auto mode blocks them). Permission escalations remain operator-owned and cannot be satisfied via a relayed message. (Note: worktasks are unattended — there are no PL0 or FN human approval gates to satisfy; this caveat applies to permission escalations only.)
1. `tail -n 50 .context/logs/audit.jsonl | jq .` — last 50 audit lines
2. `TaskList()` — current Task System state
3. Cross-reference with `stage-contracts.md` — identify first incomplete stage
4. Re-read that stage's `.context/*.md` artifact (if partial)
5. If `metadata.retry_count > 0`, read `.context/errors/<agent>.md` for retry history
6. Continue from the execution loop's `while (tasks.some(...))` — no need to replay completed stages
7. Write a `resume` audit entry: `{actor: "orchestrator", action: "resume", subject: "<worktask_id>", result: "ok"}`

See `context-compression.md § PostCompact Recovery` for the compaction-specific flow.
