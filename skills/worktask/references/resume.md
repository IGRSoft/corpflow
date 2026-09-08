# Resume After Interruption — full procedure

Read on reattach from `skills/worktask/SKILL.md § Resume After Interruption` (stub). The orchestrator loop is restartable: on reattach (PostCompact, session crash, `--resume`), diagnose state from `.context/state.json` `tasks{}` + the `.context/logs/audit.jsonl` tail before resuming.

## State → Action Table

### Initialization rows

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| No tasks | — | Worktask never initialized. Start over with `/worktask <task>` |
| PL0 only, `pending` | — | PL0 not started. Delegate PL0; after PL0 completes, the Step A.5 plan gate applies (STOP for approval unless `plan_gate == "bypass"`) |
| PL0 only, `in_progress` | no `subagent_stopped` for PL0 | PL0 crashed mid-stage. Re-delegate PL0 (idempotent) |
| PL0 `completed`, no stage tasks | — | PL0 did not create stages. Re-run PL0 |

### Branch-rename detection (run once on re-entry)

Before acting on the ledger, run `bash skills/worktask/scripts/fn-preflight.sh branch-divergence`
once. Read-only, always exit 0, never blocks. `third_party` means something outside the pipeline
renamed the local branch while the run was interrupted — surface it before continuing; `expected`
needs no action. It compares against the `to` of the last `branch_renamed / ok` row, so an R4
refinement of `facts.branch` never registers as an external rename.

### Branch-target refinement row

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, stage tasks `pending` | No `branch_target_refined` row for `PL<run_index>` | The one-shot refinement of the planned branch name has not run. Run `commands/worktask.md § Step A.4b` once, then continue to the plan-gate row below. The helper is self-guarding (it scans the audit log for a prior successful row), so a duplicate invocation is a `noop`, never a second refinement — and it performs no git mutation, so running it on resume cannot disturb the working tree. A resumed orchestrator reads `facts.branch` from the ledger and MUST NOT re-run `branch-name.sh` in rename mode; re-derivation is what would silently discard a refined value. |

### Plan-gate row

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, stage tasks `pending`, no stage `in_progress` | No `approval_received` audit line for PL<run_index> | Before branching on `plan_gate`, run Step A.4b if no `branch_target_refined` row exists for `PL<run_index>` (row above) — the gate summary must carry the final name. Then branch on `PL<run_index>.metadata.plan_gate`. If `"bypass"` (`--auto=[plan]` / `--emergency`, or stamped by `/megatask`): stages not yet dispatched — re-enter the stage loop and delegate the first unblocked stage; do NOT stop. If `"checkpoint"` (default): parked at the post-plan human checkpoint — STOP and prompt for approval; proceed only once an `approval_received` line with `subject:"PL<run_index>"` is logged. |

### Plan-revision row

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `in_progress`, stage tasks present | `plan_revision_dispatched` for `PL<run_index>` with no later `approval_received` | Plan revision in flight (gate rejection). NOT the fresh-run path — a plain PL0 re-delegate would allocate `planning-<N+1>`, reset `facts.*`, and seed a duplicate chain. If the Step 0 pre-check shows the PM agent still live, leave/reattach per the live-agent rows; only if it is gone, re-dispatch PM **with `plan_revision: true`** and the original rejection feedback — if the feedback is no longer in context (compaction), ask the user to restate it rather than dispatching without it (`commands/worktask.md § Plan-revision re-dispatch` — frozen `run_index`/`plan_file`, no state.json reset, in-place patches only). On PM's return, re-enter the plan gate at Step A.5. |

#### Plan-revision row — the branch target is not re-refined

A revision leaves the refined `facts.branch` as-is and never re-refines: the once-per-run-index window is already spent (`commands/worktask.md § Plan-revision invariants` row 5). Do NOT re-run Step A.4b here, even when the revision changed the plan title — the gate summary showed the name before approval, which is where a user who dislikes it says so.

### Auto-decision row

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, stage tasks `pending`, `PL0.metadata.decision_gate == "auto"`, `facts.open_questions[]` holds a `sw-PL<N>-*` item with `status != "resolved"` | `auto_decision_dispatched` for `PL<run_index>` present but no matching `auto_decision_resolved` | Auto-decision pass interrupted mid-delegate. Re-run `commands/worktask.md § Step A.4` — already-applied decisions are visible as `facts.open_questions[]` items marked `status: "resolved"` carrying an `(auto-decided)` `resolution` (never dropped, and never mirrored into `facts.decisions[]`); do not re-decide those — then continue to the plan-gate row above. Unanswered `escalate` items always STOP for the user, even on a `bypass` plan gate (a `/megatask` per-issue run never reaches this row — it parks instead: settled `failed` + `parked_escalation`, `commands/worktask.md § Step A.4 Escalation guard`). |

### Mid-stage & FN-gate rows

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, `approval_received` present, some stages `in_progress` | most recent `subagent_stopped` `result: error` | Mid-stage failure. Read `.context/errors/<agent>.md`, honor `retry_count` — never overrides the retry ceiling; an exhausted stage needs § Explicit-replay row |
| PL0 `completed`, all stages `completed` except FN, FN `pending`, audit tail has `fn_gate_waiting` for FN | No `approval_received` audit line for `FN<run_index>` | At the FN gate, parked. Branch on `PL<run_index>.metadata.fn_gate` (default `"checkpoint"`). If `"checkpoint"`: re-present the pre-FN summary (`references/fn-gate.md`), STOP, and delegate FN only once an `approval_received` line with `subject:"FN<run_index>"` is logged. If `"bypass"` (`--auto=[finalization]` / `--emergency`, or stamped by `/megatask`): proceed — delegate FN. |

### Near-done & stale rows

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| PL0 `completed`, all stages `completed` except FN | — | Near-done. Re-enter loop; the FN gate check (step 4.9) decides whether to STOP (`checkpoint`) or proceed (`bypass`) |
| Stages `in_progress` with no `metadata.retry_count` | missing audit lines | Stale task state. Re-derive from most recent `.context/logs/` capture |

### Live-agent rows — liveness branch

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| Any stage `in_progress` AND `claude agents --json --all` shows live `agent_id` matching that stage | — | Subagent still alive. Branch on `{state, waitingFor}` (see Resume Procedure step 0) — never blind re-delegate a live agent |
| Live `agent_id` matching that stage AND `waitingFor` = `approval`/`input` | — | Agent parked **on us**. Cheap `SendMessage` reattach with the awaited answer — do not re-delegate |
| Live `agent_id` matching that stage AND its status reads **"Needs input"** (sandbox / MCP-input / managed-settings prompt) | — | Parked **on us** but operator-owned. Reattach via `SendMessage` only to surface the prompt verbatim — never auto-answer or re-dispatch a duplicate for that stage |
| Live `agent_id` matching that stage AND `waitingFor` = null/empty (mid-work) | — | Agent busy. **Leave it** — poll/await; do **not** double-dispatch or nudge |

### Live-agent rows — broken hook configuration

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| Live `agent_id` matching that stage AND its `claude agents` row names a **hook plus a schema error** (a `PermissionRequest`/`PreToolUse` hook printed an invalid answer) | — | Operator-owned park: broken hook config, not a stage to re-dispatch. `SendMessage` cannot clear it — the same hook rejects the next tool call too. Fix the hook, then resume normally. Do not spend a `retry_count` on it |

Distinct from the "Needs input" row above, which is also operator-owned but *answerable*: that one
parks on a prompt a human can respond to, this one parks on configuration that must be edited
before the session can move at all. Before CC 2.1.248 such a session waited silently and read as a
busy agent.

### Live-agent rows — parked or gone

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| `agent_id` for an `in_progress` stage shows `state: blocked` | — | Alive but parked. Reattach via `SendMessage` — do not re-delegate |
| `agent_id` absent from `claude agents --json --all` (or `state: done`) for an `in_progress` stage | — | Agent gone. Re-delegate from the first incomplete stage |
| **Several** `agent_id`s absent at once, all vanishing at the same timestamp, session run under `--max-budget-usd` | no per-stage failure rows | **Budget halt, not stage failure.** Reaching the cap denies new spawns *and* halts running background subagents, so healthy in-flight stages die together with no error of their own. Raise the budget, then re-dispatch — and do **not** increment `metadata.retry_count`: those 3 retries are reserved for genuine stage failures, and spending them on an external stop escalates a run that never actually failed |

### Explicit-replay row

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| A settled stage (`completed`, or `in_progress` at `retry_count == 3` with `error_escalated_to` set) **and a human has asked for that one stage to run again** | — | Explicit replay, **not** reattach. `/worktask --resume <STAGE_ID>` (add `--cascade` for transitive dependents). The only path that may override the retry ceiling; never entered automatically |

#### Explicit replay vs automatic reattach — the three discriminators

1. **Trigger.** Reattach is entered by the orchestrator on re-entry (PostCompact, crash, session resume); replay only by a human typing `--resume <STAGE_ID>`.
2. **Target selection.** Reattach *derives* its target (first incomplete stage). Replay is *given* one named ledger id, which may be `completed`.
3. **Retry ceiling.** Reattach honours it (exhausted ⇒ escalate). Replay overrides it and records a `stage_replay` audit row.

The non-overlap is structural: this row's Ledger Shape carries a **non-ledger** condition (a human instruction), so a diagnostic ledger scan can never *match* it — it is reachable only by invocation.

#### Explicit replay — the guarded primitive

`/worktask --resume` calls `state-patch.sh --task-replay <ID> [--cascade]`, which refuses (exit 4, ledger byte-unchanged) when the target's agent is live or parked, when liveness is indeterminate, when `PL0` is not `completed`, or when any cascade member is blocked. Liveness comes from this runbook's own detector (`stale-check.sh`) — deliberately no second implementation to drift from these tables. Full procedure and pre-replay confirmation: `commands/worktask.md § Phase 0`.

#### Parked-or-gone rows — the retry ceiling still binds

Neither row above, nor the automatic rows in § Mid-stage & FN-gate rows, may override
`metadata.retry_count`: a re-delegate is still subject to the ceiling, and an exhausted stage
escalates rather than re-running. The ceiling is overridable only through § Explicit-replay row,
which a human enters by name.

### Mid-stage yield

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| Stage returned (not live, not errored) but the artifact is absent, present with no `handoff.verdict`, or **marked `partial`** (`maxTurns` ceiling) even when a verdict IS present | `stage_returned_incomplete` | Reattach via `SendMessage`; never re-delegate |

The agent ended its turn with budget remaining and no finished handoff. To the runtime that is an
ordinary return, which is why 6.5a's errored-return arm never fires.

Reattach via `SendMessage` to finish the same work. Do **not** re-delegate (a fresh dispatch redoes
work against a tree the yielded agent already edited) and do **not** increment `retry_count`:
nothing failed. Detector: `skills/worktask/SKILL.md § Step 6.5a2`.

#### Mid-stage yield — the three reasons

`metadata.reason` carries `artifact_absent`, `handoff_verdict_missing`, or `max_turns_partial`.
The third is the case where a subagent stopped at its `maxTurns` ceiling returns output **marked
partial**, with a hint to continue via `SendMessage`. Every corpflow agent declares a ceiling
(`agents/*.md`, e.g. `agents/team-lead.md`: 30), and this arm fires **regardless of whether a
verdict was written** — a stage can hit the ceiling after writing one.

#### Mid-stage yield vs a budget halt

Both skip `retry_count`, and there the similarity ends: a budget halt is **re-dispatched** once the
budget is raised, while a `max_turns_partial` stage is **reattached**. The agent still holds the
tree it edited, so re-delegating discards that work and re-pays the stage
(`agent-coordination/SKILL.md § Budget halts are not stage failures`).

### Reattach rows — the SendMessage has a result too

Every row above that says "reattach via `SendMessage`" assumed the send succeeds. It no longer
does: each non-delivery mode is observable rather than a silent success. **This is the entry the
plugin's min-CC floor rests on.** Read the result before treating any reattach as done, and log one
`reattach_send_result` row per attempt. Contract: `result: "ok"` means delivered; every non-delivery
is `result: "blocked"` with the mode (`refused`, `dropped`, `oversized`, `burst_limited`,
`session_list_truncated`) in `metadata.reason`. Never log a delivered-and-awaiting send as `deferred`, and never omit the
field: `stale-check.sh` reads any *present* result other than `ok` as undelivered, while a missing
or null `result` counts as delivered — an omitted result hides a non-delivery instead of surfacing
it.

#### Reattach rows — the result table

| Send result | Action |
|---|---|
| Delivered | Proceed exactly as the triggering row says — leave the stage `in_progress` and await its return |
| `refused` — recipient sets `crossSessionInbound: "refuse"`, or holds an invalid value under managed settings | Stage stays parked. Recipient-config block, operator-owned: escalate, do **not** re-delegate and do **not** increment `retry_count` |
| `dropped` — recipient's inbox is full or rate-limited | Stage stays parked. Back off and retry once; a second drop escalates |
| `oversized` — refused up front for message size | Stage stays parked. The reattach prompt is too large — an authoring defect on our side, not a recipient problem. Shorten and retry |
| `burst_limited` — refused up front for send rate | Stage stays parked. Back off briefly, retry once |

#### Reattach rows — an unconfirmed absence

| Send result | Action |
|---|---|
| `session_list_truncated` — the account's session list was too long to enumerate fully | **Any "agent gone" verdict reached under this condition is unconfirmed, not established.** Never re-delegate off it: retry discovery once, then escalate |

#### Reattach rows — undelivered means unchanged

A delivered nudge advances the stage; every other result leaves it exactly where it was. Treating
an undelivered send as delivered is how a parked stage silently becomes an abandoned one.

### Reply routing

| Ledger Shape | Audit Tail | Action |
|----------------|------------|--------|
| Stage `in_progress`; its return carries `handoff.verdict: "blocked"` with `cross_session_ask` present | `cross_session_ask` with `result: "deferred"` and no later `result: "ok"` for that `task_id` | The peer's reply lands in **this** (orchestrator) conversation, never on the stage. Check this session's own recent turns first. Present → relay it to the stage's `agent_id` via `SendMessage` and log the `ok` leg. Absent → still outstanding; do **not** re-delegate and do **not** re-ask (a second send duplicates the question to the peer) |

#### Reply routing — why the stage cannot ask for itself

A subagent's `SendMessage` to another **session** delivers its reply to the parent session's
conversation, so a stage agent that sends its own cross-session ask can never receive the answer —
it would wait forever. The stage names who to ask and what; the orchestrator owns the send. Rule
and schema: `agent-coordination/SKILL.md § Replies from a subagent land in the parent conversation`
and `handoff-protocol.md § Schema — open_questions, refs, constraints`.

A stage that sent its own ask before this rule existed has no path to the answer. Treat it like
`stage_returned_incomplete` and reattach so the ask is redone through the orchestrator.

## Resume Procedure

0. `claude agents --json --all | jq '.[] | {agent_id, state, waitingFor}'` — match rows against `.context/state.json.facts.dispatched_agents[]` (`--all` also surfaces completed and just-dispatched sessions) and branch directly:
   - live + `waitingFor` = `approval`/`input` → it is parked **on us**; `SendMessage` the awaited answer (cheap nudge, no re-dispatch).
   - live + status **"Needs input"** (sandbox / MCP-input / managed-settings prompt) → parked on us but **operator-owned**; reattach only to surface the prompt verbatim — never auto-answer or re-delegate.
   - live + `waitingFor` = null/empty (mid-work) → **leave it**; poll/await — do **not** `SendMessage` (avoids nudging a busy agent) and do **not** re-delegate.
   - `state` = `blocked` → alive but parked; **reattach** via `SendMessage`, do not re-delegate.
   - `state` = `done`, or the `agent_id` is genuinely absent even with `--all` → re-delegate from the first incomplete stage.

### Step 0 notes — observed CLI field set

   The field names above are the contract; the shipping CLI exposes fewer. An observed
   `--json --all` row carries `id`, `sessionId`, `name`, `kind`, `cwd`, `pid`, `startedAt`, and
   **either** `state` (background) **or** `status` (interactive) — no `agent_id`, no `waitingFor`,
   no `parent_agent_id`. Read identity from `agent_id // id // sessionId` (`id` is a prefix of
   `sessionId`, so match on prefix too) and liveness from `waitingFor` when present, else
   `state`/`status`. An unrecognised token is **unknown, not absent** — never re-delegate off one.
   `skills/worktask/scripts/stale-check.sh` implements exactly this tolerance.

### Step 0 notes — own-name & teammate visibility

   `ListAgents`/`claude agents --json` now lists live **teammates** (previously invisible, so a
   reachable teammate read as absent) and tells a session **its own name** — the address peers use,
   and the one to avoid when constructing a `cross_session_ask` so a stage does not address itself.
   The pre-warmed idle worker no longer appears until a task claims it, removing a phantom row from
   the best-effort `subagent_type` match in § Degrade rules — absent or terminal rows.

   Both change the pre-check's error profile, not its shape: fewer false negatives (a teammate
   read as gone) and fewer false positives (a phantom read as live). The degrade rules are
   unchanged and simply act on better input.

### Step 0 notes — reattach vs re-dispatch has a price

   `SessionStart` resume hooks receive the session's **staleness and an estimated re-cache cost**.
   Reattach is not unconditionally cheaper than re-dispatch: a long-idle session whose prompt cache
   has aged out pays that re-cache on its first turn, which can exceed a fresh dispatch for a short
   stage. Weigh the reported cost rather than assuming, and prefer re-dispatch only when the
   estimate clearly exceeds the stage's own cost — reattach still wins whenever the agent holds
   edited tree state, at any cache price (§ Mid-stage yield).

### Step 0 notes — proactive detection

   These rows fire only once someone resumes. To ask "is anything wedged?" without resuming, run
   `skills/worktask/scripts/stale-check.sh` — it reconciles the same inputs and prints the verdict
   from these tables. Read-only; it recovers nothing.

### Step 0 notes — why the pre-check

   One pre-check eliminates three waste classes: blind respawn of a working subagent, redundant nudging of a busy one, blind re-dispatch of an invisible blocked one. When `claude agents` is unavailable, skip the pre-check and re-delegate from the first incomplete stage. See `skills/agent-coordination/references/headless-dispatch.md § Live Session Discovery`.

### Step 0 notes — dispatched_agents matching

   The orchestrator loop writes one `dispatched_agents[]` entry per `task_id` (`{stage, task_id, subagent_type, agent_id?, name?, model_requested?, model_resolved?, status}`), so this pre-check has real rows to match. **Degrade rules for imperfect rows:**
   - **`agent_id` present** → match the `claude agents --json --all` row by id; branch per the table above.
#### Degrade rules — absent or terminal rows

   - **`agent_id` absent** (no launch-ack) → best-effort match by `subagent_type` among the **non-interactive** rows (skip `waitingFor = approval/input` rows — parked on us, matched by their own park signal). Exactly one candidate ⇒ adopt it; ambiguous or none ⇒ **degrade to the skip-precheck path** (re-delegate from the first incomplete stage).
   - **entry `status: completed|failed`** → the stage already resolved; do not reattach, advance to the next incomplete stage. (Terminal entries are eviction candidates and may be absent after compaction; absence = "no live agent".)
#### Worktree re-entry

   - **`tasks.<ID>.worktree.path` recorded** → `EnterWorktree(path)` before resuming that stage (mid-session switching), so DR/QA/DV-retry run in the right directory rather than the shared checkout. The recorded `worktree.branch` gives the branch without shelling `git rev-parse`.

### Step 0 notes — state-signal reliability

   The `state` signal is trustworthy — a background sub-agent no longer sticks as `active` after a nested child is stopped. With nested spawning (3 levels by default), match only **top-level** agents from `facts.dispatched_agents[]`; rows whose `parent_agent_id` points at another live row are the stage agent's own children — never reattach or re-delegate those directly.

   A resumed background agent restores its **own prompt and tool restrictions** rather than reverting to the default agent, so a live row matched to a stage is still that stage's agent. Identity is no longer a reason to re-delegate: prefer reattach.

### Step 0 notes — authority caveat

   A `SendMessage` reattach may *nudge* a parked agent (supply an awaited answer, re-prompt) but **cannot authorize** anything: a relayed message carries no operator permission authority (the receiver refuses relayed permission requests; auto mode blocks them). Both permission escalations and the PL approval gate stay operator-owned and unsatisfiable by relay.

### Step 0 notes — trigger delivery & reattach

   **Trigger-delivery caveat**: scheduled-task and webhook deliveries are **task notifications** — in auto mode they cannot approve a pending action or set a session title, so they do **not** satisfy a `waitingFor = approval` park. Treat one like a relayed message: keep the stage parked and resolve the approval through the operator-owned path.

   **Reattach reliability**: messages sent while a subagent is finishing its turn are not dropped, and `ctrl+b` does not restart the session — a mid-turn reattach will not lose the awaited answer.

### Step 0 notes — background-agent guarantees

   Runtime-assured at the plugin's min CC — the resume loop may rely on these unconditionally:

#### Push & honest completion

   - **Push signals**: finish/needs-input fires the `Notification` hook (`agent_completed` / `agent_needs_input`) — prefer it as the wake-up; the `claude agents --json` pre-check stays the authoritative reconciliation.
   - **Honest completion**: an errored subagent surfaces as an **error with partial work preserved**, never an empty success — trust `subagent_stopped` `result: error` rows. Reporting waits for real completion rather than fabricating done (behavioral improvement, not a hard invariant — keep the `references/fn-gate.md` cross-check, "BG notification ≠ approval").
#### Stopped & work preservation

   - **Stopped means stopped**: stopped stays stopped; an operator-killed agent never auto-respawns or re-runs a stale prompt; a daemon-restart-killed worker auto-resumes when the agents view next opens. Re-delegate only when the pre-check shows the agent truly absent.
   - **Work preservation**: waking a background job never deletes its transcript or re-runs the prompt; returning to `claude agents` carries running work over; long-running commands survive session restarts. A **running** background session now holds its worktree's lock, so cleanup and `git worktree remove` leave it alone; the periodic sweep of locked `.git/worktrees/` entries is the backstop for a *killed* session's stale lock, not the primary mechanism. Either way stale-worktree cleanup is not a resume chore.
#### Reattach, cross-spawn & inspection

   - **Reattach fidelity**: `SendMessage` asks the caller to retarget when a re-spawned agent reuses a previous name; a `SendMessage`-resumed agent does not stick as `failed`/`completed`; a per-stage model override survives resume and follow-up messages (`skills/shared/model-selection.md § Per-Invocation Override`); `/rename` persists across restarts.
   - **Cross-spawn targeting**: `TaskStop`/`TaskOutput` find agents spawned by **another** agent and list them by id/description on error — resume can target a cross-spawned stage agent.
   - **Inspection**: completed agents stay in `/tasks` until cleanup and attaching shows the transcript immediately, so a just-finished stage is still inspectable. Reopening a stopped session resumes it or reports why it cannot — a refusal means re-delegate, not retry blindly.

### Steps 1–7 — replay & audit

1. `tail -n 50 .context/logs/audit.jsonl | jq .` — last 50 audit lines
2. `.context/state.json` `tasks{}` — current ledger state
3. Cross-reference with `stage-contracts.md` — identify first incomplete stage
4. Re-read that stage's `.context/*.md` artifact (if partial)
5. If `metadata.retry_count > 0`, read `.context/errors/<agent>.md` for retry history
6. Continue from the execution loop's `while (tasks.some(...))` — no need to replay completed stages
7. Write a `resume` audit entry: `{actor: "orchestrator", action: "resume", subject: "<worktask_id>", result: "ok"}`

See `context-compression.md § PostCompact Recovery` for the compaction-specific flow.
