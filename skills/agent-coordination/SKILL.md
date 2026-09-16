---
name: agent-coordination
description: Use when coordinating agent handoffs, debugging multi-stage execution, or managing parallel agent workflows. Patterns for multi-agent coordination, handoffs, parallel execution, and error escalation.
effort: medium
version: 0.4.0
related:
  - ../worktask/SKILL.md
  - ../claude-constitution/SKILL.md
  - ../security-review-process/SKILL.md
  - ../release-engineering/SKILL.md
  - ../incident-response/SKILL.md
---

# Agent Coordination

Coordinating agents across worktask stages: handoffs, dispatch limits, errors.

- **Stage codes and agents**: `${CLAUDE_SKILL_DIR}/../shared/stage-codes.md`
- **State ledger**: `${CLAUDE_SKILL_DIR}/../shared/state-ledger.md`
- **Per-stage I/O contracts**: `${CLAUDE_SKILL_DIR}/../shared/stage-contracts.md` — the Inputs → Outputs → Validation table every stage agent's Completion Verification references.
- `references/hook-monitoring.md` — wiring or debugging hooks: event catalog (lifecycle, agent-teams, MCP elicitation), matchers, conditional `if`, PreToolUse defer/block, PostToolUse output replacement, gate-feedback contract, OTEL, agent-teams vs subagents.
- `references/headless-dispatch.md` — dispatching from CI/cron/a shell: `task.metadata` → `claude agents` flag bridge, per-stage one-liners, live-session discovery, permission-mode pinning.

## Handoff Protocol

1. Agent completes work matching the stage-contracts Required Outputs.
2. Updates the ledger: `state-patch.sh --task-status <ID> completed`.
3. Creates the stage artifact — `planning-0.md` for the first PL run, `planning-1.md` for the next (`skills/worktask/references/pl0-procedure.md § Plan File & Run Index Naming`) — with its required sections.
4. Writes a compressed handoff (50–100 tokens).
5. Orchestrator validates against stage-contracts before transition.
6. Next agent starts: `state-patch.sh --task-status <ID> in_progress`.

### Orchestrator → PL0 Handoff

Before PL0 the orchestrator writes `.context/exploration.md` with pre-explored codebase facts, so PL0 never re-explores. Its prompt to PL0 MUST include:

```
Read .context/exploration.md for codebase context.
Do NOT re-read files listed there unless you need additional detail.
```

#### `metadata.skip_exploration` Propagation

Every task PL0 creates downstream (AR0, TL0, DV0, …) carries `skip_exploration: true` (boolean) and `exploration_anchors` (string[] of `<file>#<anchor>` pointers, e.g. `["exploration.md#facts", "planning-0.md#requirements"]`).

AR/TL/DV/DR honour them: the anchors are the authoritative pre-explored set — no Glob/Grep over files they cover, read the anchor rather than the whole file. **Why**: re-exploration is the largest avoidable AR/TL token cost once the cache prefix exists.

**Opt-out**: an agent that must widen scope (AR finds an undeclared dependency) MAY explore further, but MUST log one `audit.jsonl` line `action: "exploration_extended"`, `metadata: {reason: "<why>"}` so reviewers see the broadened scope.

### Stage Agent File Read Rules

Every stage reads `exploration.md`; source-file access differs.

| Stage | Source files | Reason |
|-------|:------------:|--------|
| PL | No | Requirements only, no code changes |
| AR | Selective | Only files needing architectural analysis |
| TL | No | Coordination only |
| DV | Yes (modify targets) | Must read files it will modify |
| DR / QA | Yes (changed files) | Must review actual changes |
| DC | No | Documentation from artifacts |

### Handoff Checklist

- [ ] Stage objectives completed
- [ ] Artifact created in `.context/`
- [ ] Task status updated
- [ ] Handoff summary prepared
- [ ] Open questions documented

## Error Handling

### Retry / Escalate Matrix

| Classification | Trigger | Retry | Escalate to |
|---|---|---|---|
| `transient` | 5xx / rate-limit / network | 3, backoff 2^n s | — (same agent) |
| `logic` | bug / wrong approach | 3, corrective context from retry 2 | — (same agent) |
| `missing_input` | required artifact absent | No | previous stage per chain |
| `ambiguous_requirements` | requirements unclear | No | PL |
| `design_flaw` | architecture blocks implementation | No | AR |
| `hard_constraint` | ethics / security / legal block | No | abort + block for human (`"ST"`) |
| `exhausted` | `retry_count == 3` | No | previous stage per chain |

Metadata: `retry_count++` on each retry; on escalation set `error_escalated_to` to the target and reset **`retry_count` alone** at handoff.

#### Retry / Escalate Matrix — one ceiling, reachable from every retrying class

Every retrying class carries the same ceiling of **3**, so `exhausted` is reachable from each of them; the non-retrying classes never pass through it because they escalate on their first failure. No class parks below its own trigger. The ceiling is single-sourced in the table above — `skills/worktask/SKILL.md § Retry Logic` and its `retry_count == 3` escalation trigger restate it and must not diverge.

#### Retry / Escalate Matrix — the per-edge escalation cap

`metadata.escalation_counts` on the escalating task counts escalations per target, keyed by the target's **full task id** (`{"AR0": 2}`) so a split stage's writers do not share a counter. Increment it on each escalation handoff; **it is explicitly NOT reset** by that handoff, unlike `retry_count`. Resetting it would erase the only bound on the loop it exists to bound, and DV→AR→DV→AR would ping-pong forever.

At **cap 2** on an edge the escalating task is written `status: "failed"` with `last_error.class: "exhausted"` instead of escalating again; `failed` is settled, so the completion loop terminates. Schema: `skills/shared/state-ledger.md § Schema — error & retry properties`.

#### Retry / Escalate Matrix — environmental contention

**QA-only** — DV's handful of executed tests cannot establish the trigger. `environmental_contention` never retries and never escalates: re-baseline once on a quiet machine and note the outcome in `testing-N.md § Notes` — no defect, no `error_escalated_to`.

**Trigger — all three, conjunctively:** failures confined to wall-clock/async-timing suites;
failing-set **membership** differs between two consecutive runs; no source change between them.

**Voiding branch (mandatory exit).** Membership "shifts" means the *set* differs — a member added
or dropped — not ordering, not duration. If the re-baseline run fails with the same members as the
previous run, the classification is **void**: reclassify as `logic` and escalate to DV.

### Escalation Chains

```
11-stage: ST→FN→RE→DC→QA→SR→DR→DV→TL→AR→PL→USER
9-stage:  ST→FN→DC→QA→DR→DV→TL→AR→PL→USER
Emergency: FN→RE→QA→DR→DV→IR→USER
Ethics: Any→ethics-reviewer→stakeholder→USER
```

### Error Documentation

Append to `.context/errors/<agent>.md` — one file per `metadata.agent` basename, shared across retries and splits (DV0/DV1/DV2 → `developer.md`):

```markdown
## [STAGE][N] Retry [X/max] — [TIMESTAMP]
**Agent**: [agent name]
**Task ID**: [task_id]
**Classification**: [transient | logic | missing_input | ambiguous_requirements | design_flaw | hard_constraint | exhausted | environmental_contention]
### Problem
[Description]
### Resolution Path
- [ ] [Action]
```

Raw captures (build/test/monitor stdout) go to `.context/logs/` per `logging-conventions`.

## Parallel Execution

Every megatask issue and every DV stage runs in its own worktree and branch, so source-tree conflicts cannot arise: parallel issues, parallel DVN streams, QA ∥ DC, and agent-team members are all unconditionally safe to overlap. DC ∥ QA saves 30–40% wall clock; starting DC during DV gets docs ready sooner.

**Never parallelize**: AR before PL (needs requirements), DV before TL (needs coordination), QA before DV (can't test unwritten code).

### Parallel Tool Call Safety

A failed `Read`, `WebFetch`, `Glob`, or read-only `Bash` probe (`grep`, `git diff`, `ls`) does not cancel its sibling parallel calls — only mutating `Bash` errors cascade. Batch reads, searches, and shell probes freely.

## Audit Trail

Every material worktask action writes one JSONL line to `.context/logs/audit.jsonl` (folder per `logging-conventions`). The file is append-only and outlives individual stage artifacts — on resume or incident review, the audit tail is the single source of truth for what happened.

### Writers

| Actor | Action Examples |
|-------|-----------------|
| Orchestrator | `worktask_init`, `stage_transition`, `approval_received`, `resume`, `stage_replay`, `permission_mode_pinned`, `github_issue_created`, `dispatch_depth_projected` (Pre-Stage Validation check 11), `stage_returned_incomplete` (Step 6.5a2), `reattach_send_result` (one per reattach attempt — `worktask/references/resume.md § Reattach rows`), `cross_session_ask` (`deferred` ask leg + `ok` relay leg, Step 6.5a3) |
| Stage agents | `artifact_created`, `error_recorded`, `retry_attempt`, `escalation`, `full_test_run`, `scoped_test_run`, `message_ack` (`state-patch.sh --ack`) |
| Any agent whose nested `Task()` is refused by the depth cap | `dispatch_flattened` (§ Depth-refusal self-report) — the writer is the *refused dispatcher*, which may be a stage agent or a nested platform router, never the orchestrator |
| `PermissionDenied` hook | `permission_denied` (auto-mode classifier blocks a tool) |

#### Test-run counter rows

One row per test **invocation**, keyed on the invocation's shape rather than the plan's mode: ≥1 `-only-testing:` flag → `scoped_test_run`; zero selection flags → `full_test_run`; `build-only` runs emit none. `metadata: {stage, plan_mode, suites_selected, run_index}` — carrying `plan_mode` next to the shape is what makes "how often did we actually run everything" answerable. **Audit-only, never a gate**: a missing counter row must not block a stage and must not appear in any completion checklist.

#### Writers — plugin hooks (authoritative)

| Actor | Action Examples |
|-------|-----------------|
| `hook:audit-subagent` (SubagentStop, plugin) | `subagent_stopped` |
| `hook:audit-tooluse` (PostToolUse, plugin) | `tool_invoked` for `Bash\|Write\|Edit` (ledger patches recognised by command) with `duration_ms` + `effort` |
| `hook:state-merge` (SubagentStop, via `state-patch.sh --via hook`) | `stage_transition` with `task_id` + `metadata.{verdict, via, dedupe_key}`; one-shot `state_merge_noop` when the stop carried no stage and no artifact |
| `hook:precompact` (PreCompact, plugin) | `precompact_checkpoint` with `state_file` + `run_index` + `artifacts[]` |
| `hook:agent-stop` (Stop, PL/FN/ST agents) | `stage_completion_hook` with `metadata.stage` |
| `hook:test-execution-gate` (PreToolUse, plugin) | `test_execution_blocked`, `test_execution_deduped`, `test_dedupe_skipped_zero_prior`, `test_delegation_observed`, plus one-shot `test_gate_disabled` / `test_dedupe_disabled` |

#### Plugin-hook row fields

Every row above is **authoritative**. `audit-subagent` and `agent-stop` rows also carry `parent_agent_id`, `background_tasks_count`/`_ids`, `session_crons_count`/`_ids`. `stage_transition` is emitted ONLY on the hook path — a hook completion runs no Bash tool call, so `hook:audit-tooluse` never sees it; other layers stay scraped to avoid double counting.

#### Writers — model-switch hooks (authoritative)

| Actor | Action Examples |
|-------|-----------------|
| `hook:model-switch-gate` (PreModelSwitch, plugin) | `model_switch_blocked`, `model_switch_confirm_requested`, `model_switch_annotated`, and one-shot `model_switch_gate_disabled` hatch note — `metadata.{stage, task_id, pinned, requested, kind}` |
| `hook:model-switch-audit` (PostModelSwitch, plugin) | `model_switched` with `metadata.{pinned, origin, resolved, off_tier, dedupe_key}`, gated on an existing ledger |

#### Writers — external & adapters

| Actor | Action Examples |
|-------|-----------------|
| External dispatcher | `external_dispatch` (CI/cron/user-shell invoked a stage via `claude agents run` — see `references/headless-dispatch.md`) |
| `apple-canvas` adapter (in `dv-screenshot-capture`) | `canvas_render` (one row per phase ∈ scaffold\|complete\|retry — see `skills/dv-screenshot-capture/references/apple-canvas.md § Audit row schema`) |
| `preview-ensurer` skill | `preview_added` (one row per `#Preview` block written to source — `metadata: {file, view_type, mock_strategy, lines_added}`) |
| QA visual-diff wrapper (`skills/dv-screenshot-capture/scripts/visual-diff.sh`) | `visual_diff_run` (one row per RMSE diff — `metadata: {reference, candidate, metric:"RMSE", value_percent, threshold_percent, verdict}`) |

#### Hook authority + dedupe rule

Hook-emitted rows carry `actor: "hook:<name>"` and `metadata.dedupe_key`. Agent-emitted rows for the same action stay forward-compatible (for installs where plugin hooks are disabled via `allowManagedHooksOnly: false` + plugin disabled) but are **advisory**. Readers (resume protocol, incident-responder) MUST prefer the `hook:*` row when two rows share a `dedupe_key`.

#### Hook authority — canonical vs mirrored writers

A hook row's actor is `hook:<name>` **or** `<plugin>:hook:<name>` — every installed sibling plugin mirrors these hooks under its own prefix, so one completion yields one canonical row plus one per sibling. Mirrors set `metadata.advisory: true` and carry thinner metadata (an empty `subject` in particular). Authority within a `dedupe_key` group is therefore three-tier: canonical hook row, then any hook row, then first-by-index. Readers MUST NOT match on `startswith("hook:")` alone; route through `scripts/audit-dedup.sh`, which implements the ladder.

#### Dedupe-key shapes — tool & subagent

- `tool_invoked`: `"<session_id>:<tool_use_id>"`
- `subagent_stopped`: `"<session_id>:<agent_id>:stop"`

#### Dedupe-key shapes — stage & issue

- `stage_completion_hook`: `"<session_id>:<agent_id>:stage:<PL|FN|ST>"`
- `stage_replay`: `"<worktask_id>:<run_index>:<task_id>:replay:<ts>"` — the timestamp is deliberate: replay is repeatable by design, so two legitimate replays of one stage must NOT collapse. Written by `state-patch.sh --task-replay`, on success only; a refusal changed nothing and records nothing.
- `github_issue_created`: `"<worktask_id>:<run_index>:gh_issue"` — collision on resume detects already-published; multi-track safety via `run_index` increment. Writer: orchestrator (via `skills/worktask/scripts/publish-pl-issue.sh` between PL approval and stage-loop entry).
- `model_switched`: `"<session_id>:<agent_id>:model-switch:<ts>:<resolved>"` — timestamp and destination are deliberate: a session that switches twice (fallback, then back) must keep both rows. Writer: `hooks/model-switch-audit.sh`.

### Schema

```jsonc
{
  "ts": "ISO-8601 UTC",
  "actor": "orchestrator|<agent-name>|hook:<name>",
  "action": "worktask_init|stage_transition|artifact_created|error_recorded|retry_attempt|escalation|approval_received|resume|stage_replay|permission_denied|subagent_stopped|tool_invoked|precompact_checkpoint|stage_completion_hook|permission_mode_pinned|external_dispatch|github_issue_created|canvas_render|preview_added|visual_diff_run|full_test_run|scoped_test_run|test_execution_blocked|test_execution_deduped|test_dedupe_skipped_zero_prior|test_delegation_observed|test_gate_disabled|test_dedupe_disabled|state_merge_noop|facts_items_rejected|dispatch_depth_projected|dispatch_flattened|stage_returned_incomplete|reattach_send_result|message_ack|cross_session_ask|model_switch_blocked|model_switch_confirm_requested|model_switch_annotated|model_switch_gate_disabled|model_switched",
```

#### Schema — remaining fields

```jsonc
// …continued: the same object
  "subject": "task ID or artifact path",
  "result": "ok|error|deferred|blocked",
  "task_id": "optional — ledger key, e.g. DV0",
  "artifact": "optional — .context/ path",
  "metadata": { "...": "action-specific extras" }
}
```

#### Hook-written metadata fields

Optional `metadata` fields on hook-written `subagent_stopped` / `stage_completion_hook` rows, in addition to action-specific extras:

- `duration_ms` (subagent_stopped only): number
- `effort`: `"low"|"medium"|"high"|"xhigh"|"max"|"unknown"`
- `stage`: `"PL"|"FN"|"ST"` on stage_completion_hook, any stage code on subagent_stopped (from `CLAUDE_TASK_METADATA_STAGE`), `"unknown"` when unstamped
- `agent_id` (subagent_stopped only): string — `"unknown"` when absent
- `parent_agent_id`: string — `"none"` when not in hook stdin
- `background_tasks_count` / `session_crons_count`: integer ≥ 0
- `background_task_ids` / `session_cron_ids`: string[] — a `"unknown"` entry means the ID field name shifted; see `references/hook-monitoring.md § BG-Task ID Schema Watch`
- `dedupe_key`: string (always present)

### Append Pattern (Bash)

```bash
mkdir -p .context/logs
jq -c --arg ts "$(date -u +%FT%TZ)" \
  '. + {ts: $ts}' <<< '{"actor":"orchestrator","action":"stage_transition","subject":"DV0→DR0","result":"ok","task_id":"4"}' \
  >> .context/logs/audit.jsonl
```

### Retention

Follows `.context/` hygiene — cleared on task archival (FN stage or `/worktask` completion). Do NOT rotate within a task; the full trail is required for PostCompact recovery and incident post-mortems.

## Task Decomposition

Whether a stage splits depends on *who* initiates the split and *what* the dependency shape is. Pick one pattern — do not mix.

### Decision Table

| Condition | Pattern | Effect | Example |
|-----------|---------|--------|---------|
| Independent sub-scopes, different owners | **TL-initiated (parallel)** | DVN blocked by TL0, all concurrent; DR0 blocked by all DVN | `theme colors` + `switcher` + `dark assets` |
| Cross-cutting refactor across many modules | **TL-initiated (parallel)** + `track` metadata | Each stream gets its own worktree | `rename User → Account` |
| Sequential discovery (later work depends on earlier) | **DV-initiated (sequential)** | DVN blocked by DV0, run in order | `implement auth` → `migrate users` |
| Stage failed and the retry needs narrower scope | **DV-initiated (sequential)** | DV1 is the focused retry; `retry_count` resets | DV0 full feature → DV1 auth only |
| Single cohesive scope, <3 files | **No split** | DV0 handles it | `fix null check in login validator` |

Full code patterns: `worktask/references/initialization-patterns.md § Stage Sub-Task Splitting`.

### When NOT to Split

- **PL/FN/ST** — always singletons (PL0, FN0, ST0).
- **Trivial scope** — orchestration cost exceeds the benefit.
- **Shared mutable state** — if two streams edit the same file, serialize; merge conflicts cost more than the latency saved.

## Agent Selection

### Sub-Task Delegation

| Sub-Task | Delegate To | Model |
|----------|-------------|-------|
| Status check | Self | haiku |
| Code implementation | developer | opus |
| Architecture question | software-architector | opus |
| Platform architecture (apple/systems/android/web/backend/ai) | the platform's architect agent — roster in `skills/shared/routing-matrix.md § Functional-role aliases` | opus |
| Technical decision | technical-lead | opus |
| Test design | qa-engineer | sonnet |

> **Cross-plugin AR collaboration**: on platform projects `software-architector` consults that platform's architect during AR for platform-specific architecture (for Apple: pattern selection, DI, navigation, concurrency; equivalents elsewhere). Per-platform table: `agents/software-architector.md § Platform Architecture Collaboration`; protocol: `cross-plugin-handoff` skill.

#### When not to delegate

The table says who takes a sub-task, not that every sub-task needs one. The ceilings below are
*caps*, and there is deliberately **no per-session total-spawn cap**, so nothing here stops a stage
spending its budget on spawns a direct tool call would have answered.

Delegate for work that is genuinely independent and parallelizable, or needs expertise this stage
lacks: a wide multi-file investigation, a platform specialist, a per-stream DV split. Do not
delegate what a grep and two reads would settle, and never spawn a subagent to double-check your
own output. Where one delegate suffices, use one.

This bites hardest on the `opus` stages, which reach for delegation more readily. Section `[4b]`
carries the same rule at dispatch; it is here too because a stage agent reads this skill directly
when deciding whom to call. Source: `skills/shared/model-prompting.md § opus`.

#### Nested delegation

> Sub-agents spawn their own sub-agents, up to **3 levels deep** by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; `=1` disables nesting entirely). Depth counts **from the session root**, so the main session is depth 0 and its directly-dispatched stage agent is depth 1. The canonical DV chain — session → `developer` (1) → `apple-developer:ios-developer` (2) → `apple-developer:test-generator` (3) — sits exactly on the default ceiling; the orchestrator does not flatten Tier-2 dispatch into its own loop.

##### Depth budget sharing

> Foreground and background subagents share one depth budget — a foreground chain plus a backgrounded child count against the same cap. Each level summarizes upward, and the audit trail's `dispatch_depth` makes depth visible.

> **`/megatask` consumes a level**: a batch run dispatches a per-issue `/worktask` orchestrator as its own sub-agent (depth 1), pushing that same DV chain to depth 4 — one past the default. Raise `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` before the batch, or accept a flattened Tier-2 dispatch. See `skills/megatask/SKILL.md § Nesting-depth budget`.

#### Pre-launch spawn classification

> In auto mode the permission classifier evaluates a subagent spawn **before** it launches, so a dispatch can be denied up front (`PermissionDenied` hook fires). Treat a refused spawn like a failed stage and route it per the retry/escalate matrix rather than assuming every `Task(...)` starts.

#### Depth-refusal self-report

> **When the depth cap refuses a nested `Task()`, the refused dispatcher MUST append one `dispatch_flattened` row to `.context/logs/audit.jsonl` BEFORE doing that work inline.** Emitting it afterwards is the exact failure this contract exists to prevent: an agent that finishes the specialist's job and then forgets leaves an artifact indistinguishable from one the specialist actually produced.

##### No hook covers this refusal

Unlike a refused *tool* (`PermissionDenied`), nothing in the plugin hook vocabulary (`references/hook-monitoring.md`) is depth-shaped, so this row is a self-report — advisory only once a future hook supersedes it. It closes the silence; it does not guarantee capture.

| Field | Value |
|---|---|
| `actor` | the refused dispatcher (e.g. `apple-developer:apple-developer`), never `orchestrator` |
| `action` | `dispatch_flattened` |
| `subject` | the **specialist that would have been used** (e.g. `apple-developer:test-generator`) |
| `result` | `deferred` — the dispatch did not happen; the work still did |
| `metadata.attempted_depth` | the depth the refused child would have occupied |
| `metadata.cap` | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` as resolved at refusal time |

##### Required fields and pairing

All three of `subject`, `attempted_depth`, and `cap` are required. A row saying only that flattening happened does not tell an operator **whose judgment is missing from the output**, which is the only question the row is written to answer.

Pairs with the orchestrator's forward-looking `dispatch_depth_projected` (`skills/worktask/SKILL.md § Validation check 11`): the projection warns before the stage runs, this row records what the projection missed.

#### Background-by-default dispatch

> Subagents run in the **background by default** — the dispatching agent keeps its turn and receives the child's result as a completion notification. Two consequences: (1) a `Task()` launch acknowledgement is NOT stage completion — advance a stage (Step 6.5, the `completed` patch) only on the completion notification or the `subagent_stopped` audit row (`skills/worktask/SKILL.md § Orchestrator Execution Loop`); (2) unblocked sibling stages (parallel DVN tracks, DC+QA) genuinely overlap with no extra orchestration.

##### Depth accounting & background permission prompts

> Depth accounting survives resume: resumed subagents restore their original spawn depth, forked ones count toward the cap, and a resumed background agent restores its **own prompt and tool restrictions** rather than reverting to the default agent — so reattach is safe and re-dispatch is never required for identity reasons alone. Permission prompts from background subagents surface in the main session (dialog names the asking agent; Esc denies just that tool) instead of being auto-denied, so an unattended run parks on them — see the resume `waitingFor` branch table.

##### Two independent ceilings

> A dispatch can be refused by either of two caps; they are counted and raised separately. Check both before a wide fan-out, not just the one that bit last time.

| Ceiling | Default | Env override | Counts |
|---------|---------|--------------|--------|
| Nesting depth | 3 | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | Levels below the session root; `=1` disables nesting |
| Concurrently running | 20 | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | Agents alive *right now*, at every depth |

###### No total cap; concurrency is the one that bites

> There is **no per-session total-spawn cap** — a long session never refuses on a running total, so `/megatask` batch size is bounded by concurrency, disk, and rate budget alone. Concurrency is the easy ceiling to hit: background-by-default dispatch keeps stage agents alive simultaneously that were once sequential, each nested Tier-2 specialist counts while it runs, and `/megatask` runs `parallel_tracks` orchestrators each with a live stage agent and its children. Project peak concurrency, not the total, at the R1 gate.

###### Bash memory ceiling (Linux)

> `CLAUDE_CODE_TOOL_MEMORY_LIMIT` (opt-in, CC 2.1.233) puts Bash tool commands in a memory cgroup so a runaway build cannot stall the session. Linux only — on macOS runners a runaway build must still be caught by the build timeout. Worth setting on CI runners that execute `/<plugin>:build-test`.

###### Budget halts are not stage failures

> When `--max-budget-usd` trips, new spawns are denied *and running background subagents are halted*. A stage that disappears mid-work under a budget stop must be re-dispatched after the budget is raised — it must **not** consume one of that stage's 3 retries, which are reserved for genuine stage failures (`skills/worktask/references/resume.md`).

### Model Selection

Mechanical/rule-based → haiku; multi-step reasoning → sonnet; tradeoff analysis or architectural implications → opus. Tier detail: `skills/shared/model-selection.md`. **Rule**: prefer reading artifacts over invoking an agent.

Per-invocation override: `Task({ subagent_type: "corpflow:developer", model: "opus" })`.

> **Parameterized permission syntax**: permission rules accept `Tool(param:value)` with `*` wildcards — `Agent(model:opus)` permits only opus-model spawns, `Agent(model:*)` any override — so auto mode's dispatch overrides can be constrained without hand-listing every agent. `Agent(type)` deny rules and `Agent(x,y)` allowed-types restrictions are enforced for **named** subagent spawns too.

#### Model aliases, allowlists & @-mentions

> Agent teams inherit the leader's model; teammates use the parent session's model unless overridden. Aliases (`fable`/`opus`/`sonnet`/`haiku`) work across all providers. **Allowlist caveat**: a managed `availableModels` list constrains subagent overrides too, and `enforceAvailableModels` constrains the Default model — a valid alias may silently resolve to a different model (`skills/worktask/SKILL.md § Pre-Stage Validation` step 6). Named subagents appear in `@`-mention typeahead; `@` also mentions another Claude *session*, and `SendMessage` delivers to a bare name matching exactly one live session.

#### Cross-session reach & SendMessage authority

> `SendMessage` reaches sessions on **other machines**; `ListAgents` discovers them, labelling disconnected Remote Control rows `offline` and cloud rows `cloud`, and it also lists live **teammates** and reports the session's **own name** — the address peers use. `crossSessionInbound` (holds messages into a bypassed-permissions session for approval) and `dialogExpiry` govern inbound traffic; an invalid `crossSessionInbound` value warns and **holds** messages (user settings) or **refuses** them (managed settings) rather than being ignored.

> **Authority does not relay** — and matters more across machines, not less. Receivers **refuse relayed permission requests**; auto mode blocks them outright. A reattach may *nudge* a parked agent (re-prompt, supply an awaited answer) but never *authorize*: permission escalations and the PL gate stay operator-owned.

##### Delivery is reported, so check it

> A send can come back `refused`, `dropped` (full or rate-limited inbox), `oversized`, `burst_limited`, or `queued`, and `SendMessage`/`ListAgents` say when the account's session list was too long to enumerate fully — which makes any "peer is gone" conclusion drawn under that condition unconfirmed rather than established. `queued` means the target is an offline Remote Control session on another machine and delivery waits for it to reconnect: never re-send, or the message arrives twice. Branch on the result; the resume loop's table is `references/resume.md § Reattach rows — the SendMessage has a result too`.

##### notify_when_idle, availability & preview collapse

> **`notify_when_idle`** on a cross-session `SendMessage` asks a peer for one notice when it next goes idle — opt-in, one-shot, no polling, **same-machine peers only** (macOS and Linux). Prefer it over a `claude agents --json` poll whenever exactly one peer is awaited.

> **Availability is unconditional**: Bedrock/Vertex/Foundry, telemetry disabled, Windows, user namespaces and rootless containers, with a private per-user `/tmp` fallback when the default directory is unusable. Never gate a handoff, a dispatch flag, or a reattach path on provider or host OS.

> **Peer messages collapse to one line** — `Message from @<sender>: <first line>`, Ctrl+O expands. A relayed handoff or escalation must carry its verdict in the **first line**.

#### Replies from a subagent land in the parent conversation

> A `SendMessage` from a **subagent** to another **session** delivers the reply into the *parent* session's conversation, never back to the sending subagent. Only a sibling-or-parent **subagent** target (same session) round-trips correctly — including resume: a subagent that resumes another agent via `SendMessage` is woken by that agent's completion.

> Consequence, binding on every stage agent: **never `SendMessage` another session and then wait inline for the answer** — it will not arrive. Return `verdict: "blocked"` with `handoff.cross_session_ask` naming who to ask and what (`skills/worktask/references/handoff-protocol.md § Schema — open_questions, refs, constraints`); the orchestrator sends, receives the reply natively, and relays it (`skills/worktask/SKILL.md § Step 6.5a3`, `references/resume.md § Reply routing`).

#### Skill discovery & subagent_type resolution

> Subagents resolve project + user + plugin skills natively at every depth — a Level-3 child resolves `Skill("<name>")` like a Level-1 one — so never inline-load skill instructions before delegating. `subagent_type` matching is case- and separator-insensitive (`"Corpflow:Developer"` → `corpflow:developer`); the bare-name → `corpflow:` convention still sets resolution priority.

#### Dispatch flags & /agents UI

> `claude agents` dispatch flags (`--cwd`, `--add-dir`, `--settings`, `--mcp-config`, `--plugin-dir`, `--permission-mode`, `--model`, `--effort`, `--dangerously-skip-permissions`) map to `task.metadata` per the **`references/headless-dispatch.md`** translation table. PL0 populates the optional fields (`skills/worktask/references/pl0-procedure.md § Optional dispatch metadata`); external runners consume them via the one-liner in `commands/worktask.md § Headless dispatch`. `/agents` shows Running/Library tabs with a `* N running` indicator per type.

### Agent Naming & Collision Avoidance

Claude Code keys installed agents by frontmatter `name`, so two plugins shipping one name silently overwrite each other; `developer`, `qa-engineer`, `incident-responder`, `designer`, and `technical-writer` are generic across marketplaces (source: ai-research PR #554). Prefer **plugin-scoped names** (`<plugin>-<role>`) for new generic-role agents. The 16 existing corpflow agents are disambiguated by fully-qualified `subagent_type` prefixes, so no rename is forced — renaming would cascade into every `Task(subagent_type=…)` reference. When authoring via `/create-agent` / `/optimize-agent`, audit `name:` against known marketplace stems (`apple-developer:`, `security-scanning:`, `debugging-toolkit:`); `/optimize-agent § Frontmatter Audit` flags this as P1.

### Monitor Tool for Background Events

`Monitor` streams stdout from background scripts started via Bash `run_in_background` — event-driven, no polling loops. It watches **this** session's own background work; waiting on a *peer session* to go idle is `notify_when_idle` instead (§ Cross-session reach & SendMessage authority). Different targets, different mechanisms — neither substitutes for the other. Pattern: launch with `run_in_background: true`, tee into `.context/logs/` so the capture outlives the Monitor session (`logging-conventions`), note the returned shell ID, attach `Monitor` to it. After Monitor detaches (timeout, stage transition) the `.log` is still readable via `Read`.

```bash
<command> 2>&1 | tee .context/logs/<kind>-<slug>-<ts>.log
```

#### Per-Stage Monitor Usage

| Stage | Background command → what Monitor watches |
|-------|-------------------------------------------|
| DV | `xcodebuild …` / `swift build` → compile + dependency-resolution errors; abort on first failure |
| QA | `xcodebuild test …` → pass/fail per test, stop on first red; `xcrun simctl spawn … log stream` → runtime behavior |
| IR | `ssh prod tail -f /var/log/app.log` → recurring error pattern |
| DR/SR | `swiftlint --reporter json` → warnings streamed for severity triage |
| RE | `xcodebuild archive …` → signing / archive steps; abort on signing failure |
| FN | `gh run watch <run-id>` → PR check progress |

#### Stall Timeout

A subagent stalled >10 minutes fails with a clear error rather than hanging, and Monitor sessions inherit the guard: no output for >10 min is a failure — escalate per `Error Handling § Retry / Escalate Matrix`. Idle background shells may also be reaped under memory pressure; set `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` where a long-lived monitor or `tee` pipe must survive. The tee'd `.context/logs/*.log` is the durable record either way.

### MCP Auto-Background

An MCP tool call past the auto-background threshold (default **2 minutes**, `CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS`) is backgrounded by Claude Code itself: the caller gets a handle, not the result. Handle it exactly like a backgrounded `Task()` dispatch (§ Background-by-default dispatch).

- Do NOT read the handle as the build/test outcome — await the completion notification (or poll) first.
- A completion gate reading an artifact the call produces (e.g. `developer § D1`'s `build-developer-*.log`) MUST wait for the real completion signal: a log still being written is not "done", and file presence proves nothing.

#### MCP auto-background threshold tuning

- XcodeBuildMCP `build_sim` / `build_run_sim` / `test_sim` routinely exceed 2 minutes — DV/DR/QA flows chaining on them must await between steps.
- Raise or disable the threshold only when one turn genuinely needs a synchronous result (DV diagnosing a full log in one pass), and only on an external headless dispatch with its own environment: in-process `Task()` children share the session setting, so raising it session-wide costs every other MCP call its safety net.

### MCP Tool Inheritance

Subagents inherit MCP tools from servers **already running** in the parent at delegation time, so cross-plugin tools (XcodeBuildMCP, Pencil, …) need no per-tool `tools:` entries — provided the parent already spawned the server.

#### Lazy-spawn warmup requirement

Lazy-spawned servers (`npx -y …` over stdio) start only on the first tool call in a session, and inheriting the server *reference* does NOT trigger a spawn: delegate before any tool call and the child (especially under `isolation: worktree`) fails its first `mcp__<server>__*` call with "tool not available". The orchestrator MUST issue one warmup call before delegating to a child that needs one — canonical pattern (triggers, retry budget, audit lines, fallback banner) in `worktask § Pre-DV MCP warmup`; add a trigger block when introducing a new lazy-spawn MCP.

### MCP Unavailability Detection

Both warmup sites (`worktask § Pre-DV MCP warmup`, `developer § MCP Build Verification`) classify failures with one regex over the normalised message — `String(err.message ?? err).slice(0, 500)`, case-insensitive:

```
MCP_UNAVAILABLE_RE = /(tool not available|server (not reachable|unavailable)|connection refused|ECONNREFUSED|EPIPE|ETIMEDOUT|timed? ?out|spawn ENOENT|command not found|InputValidationError)/i
```

A **closed list of known-transient outages**, not a catch-all. Anything outside it (`TypeError`, schema-validation failures, assertion errors) is a real bug and MUST propagate — do not retry, do not fall back. A new lazy-spawn MCP with a new transient string SHOULD extend this regex here rather than match locally.

### Subagent Worktree Access

Worktree-isolated sub-agents automatically get Read/Edit access to their own worktree — no explicit grant needed — and **cannot** redirect git at the shared checkout: `git -C <shared path>`, `--git-dir`, `GIT_DIR`, and `GIT_WORK_TREE` are blocked. Isolation is runtime-enforced, not a convention DV is trusted to honor, so an escape attempt fails loudly instead of silently polluting the parent tree. The inverse still works: a **parent** session may reach in with `git -C .worktrees/…` (`skills/shared/milestone-helpers/SKILL.md § Git Commands Reference`); inside a worktree use plain `git` against the inherited cwd.

### Subagent runtime guarantees

- **Partial progress is trustworthy**: a background subagent cut off by a rate limit or server error returns its partial work; an API error (usage limit) is reported to the parent as an **error**, not a successful-looking result; a cutoff before any text fails cleanly. A teammate dying on an API error reports `failed` to the lead. Classify as `transient` (§ Retry / Escalate Matrix) — an errored return is never stage completion (`skills/worktask/SKILL.md` Step 6.5).
- **Forking is on by default**: `subagent_type: "fork"` inherits the parent's conversation **and prompt cache** — the cheapest handoff there is, since a stage needing the orchestrator's whole context pays cache-read rates instead of a re-sent brief. Fork when a stage keeps asking for upstream detail; dispatch normally when a narrow context is the point (`skills/cost-optimization/`). (`/fork` copies the conversation into a new background session; the in-session behavior lives at `/subtask`.)
#### Isolation, cwd & key order

- **Fresh worktrees**: `isolation: "worktree"` never reuses a stale worktree from a prior session, so old untracked files cannot leak into a new stage.
- **cwd survives resume**: subagents resumed via `SendMessage` restore the explicit `cwd` they were spawned with.
- **Stable key order**: `tasks{}` keys sort lexically by stage id, so handoff math like "the latest DV task is the highest-numbered DVN" holds.

## Coordination Patterns

### Sequential Pipeline (Default)
```
PL→AR→TL→DV→DR→QA→DC→FN→ST
```

This is the full reference pipeline, not the set that runs. PL0 sizes the actual stage set; **AR** and **TL** are optional (`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`), so the live chain may be `PL→AR→DV→…` or `PL→DV→…`.

### Parallel Documentation
```
       ┌→ DC ─┐
DR →──┤       ├→ FN
       └→ QA ─┘
```

### Quick Worktask
```
PL → DV → DR → QA
```

### Micro Execution
```
[Figma capture if URL provided] → Present plan → DV only
```

## Handoff Message Format

Verdict first, on the first line. When this is relayed to a peer session it collapses to a
one-line preview (§ Cross-session reach & SendMessage authority), and that line has to say how the
stage ended.

```markdown
## [FROM]→[TO] Handoff — [ok|blocked|escalate]: [one clause]

**Summary**: [One sentence]

**Deliverables**:
- [Artifact]: [purpose]

**Open Items**:
- [Question for next stage]
```

## Escalation Message Format

```markdown
## Escalation [FROM]→[TO] — [blocking|degraded]: [the ask, in one clause]

**Type**: [dependency|architecture|requirements]

**Problem**: [Description]
**Attempted**: [What was tried]
**Needed**: [Specific ask]
```

`Severity` moves into the heading rather than sitting on its own line: an escalation whose preview
reads only `## Escalation: DV→AR` tells the reader nothing they can triage on.

## Stage-Specific Handoffs

Fields each handoff must carry, in addition to the standard format above:

| Handoff | Required fields |
|---|---|
| DV → SR | **Security-Sensitive Areas** (area: why relevant); **Recommended Focus**: auth, data handling, APIs |
| SR → QA | **Security Status** [Approved\|Blocked\|Conditional]; **Critical/High Findings** count; **Security Tests Recommended** |
| DC → RE | **Commit Summary** (feat/fix list); **Recommended Version Bump** [MAJOR\|MINOR\|PATCH] |
| IR → DV | **Incident ID** INC-[N]; **Severity** P[0-3]; **Required Fix**; **Constraints**: minimal change, no refactoring |

## Constitutional Coordination

Ethics-reviewer can be invoked at any stage: optional via `--ethics-review`, mandatory when a high-risk feature is detected, on any agent's flagged concern, and as an immediate stop on a hard constraint.

Handoffs must be **truthful** (accurate status claims), **calibrated** (appropriate uncertainty), and **transparent** (no hidden issues).

## Multi-Reviewer Coordination

### Review Dimension Allocation

| Dimension | Focus | Include When |
|-----------|-------|-------------|
| **Security** | Vulnerabilities, auth, input validation | Code handling user input or auth |
| **Performance** | Query efficiency, memory, caching | Data access or hot path changes |
| **Architecture** | SOLID, coupling, patterns | Structural changes or new modules |
| **Testing** | Coverage, quality, edge cases | New functionality added |
| **Accessibility** | WCAG, ARIA, keyboard nav | UI/frontend changes |

Combinations: API endpoint, data model → Security + Performance + Architecture. UI component → Architecture + Testing + Accessibility. New feature (full) → Security + Performance + Architecture + Testing.

### Finding Consolidation

1. **Deduplicate**: merge findings at the same file:line.
2. **Resolve conflicts**: take the higher severity when reviewers disagree.
3. **Organize by severity**: Critical > High > Medium > Low.
4. **Cross-reference**: note findings appearing in multiple dimensions.

### Severity Calibration

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | Exploitable, high impact, easy to find | Block release |
| High | Exploitable or significant impact | Fix before merge |
| Medium | Potential risk, moderate impact | Track, fix soon |
| Low | Minor risk, defense in depth | Advisory |

## Task Decomposition for Parallel Work

### File Ownership Boundaries

1. Assign exclusive file ownership per agent — no overlap.
2. Define interface contracts at ownership boundaries.
3. Create shared types/interfaces before parallel execution starts.
4. Never modify files owned by another agent without team-lead approval.

### TL-Initiated DV Splitting

TL can split DV0 into parallel streams (DV0, DV1, DV2…) during coordination; each runs in its own worktree after TL completes, and the orchestrator picks up the new tasks on its next ledger re-read — no loop changes needed.

**Split criteria**: 2+ independent file groups with cleanly separable ownership and a small interface surface. **Artifact**: TL records the split as a `### Parallel Streams` H3 under `## fan-out` in `.context/coordination-N.md` — per-stream scope, file ownership, interface contracts.

**Anti-patterns**: splitting tightly coupled files across streams (merge conflicts); splitting small scope (coordination overhead exceeds time saved); missing DR0 rewiring (DR0 must depend on ALL DVN tasks, not just DV0).

### Hypothesis-Driven Debugging

For a bug with multiple candidate causes: generate N hypotheses spanning different failure categories, assign each to an investigator agent, have each gather confirming/falsifying evidence, then arbitrate ranked by confidence and evidence strength.

## Native Dynamic Workflows vs corpflow Staged Worktask

Claude Code's native `/workflows` command and Workflow tool cover **dynamic workflows** — ad-hoc background fan-out to tens-to-hundreds of concurrent agents with lightweight coordination. `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` (1–256) raises the Workflow tool's per-run concurrent agent limit for inference-bound fan-outs. Complementary to the staged worktask, not a replacement.

### Comparison

| Dimension | Native dynamic workflows (`/workflows`) | corpflow staged worktask |
|---|---|---|
| **Scale** | Tens–hundreds of parallel agents | 11 governed sequential/parallel stages |
| **Governance** | Ad-hoc, minimal overhead | Stage contracts, artifact audit trail, DR/SR/QA gates |
| **State / resume** | Orchestrator-in-context; manual resume | `.context/state.json` + audit.jsonl; Resume Procedure, checkpoints |
| **Reach for it when** | Quick parallelism without governance (batch linting, parallel research, one-off transforms) | Work needing security review, QA sign-off, docs, or an audited multi-stage handoff |

The worktask's two human checkpoints — the PL plan gate and the FN finalization gate (STOPs before commit/push/PR) — and their `--auto=[plan|finalization|decision]` / `--emergency` bypasses are specified in `skills/worktask/SKILL.md`; a `/megatask` batch stamps `plan_gate`/`fn_gate: "bypass"` on each per-issue PL0.

### Composition & workflow sizing

They compose: a DV agent inside a worktask may spin up a native dynamic workflow to parallelize sub-tasks, then consolidate before its DR handoff. Workflow-spawned agents carry `workflow.run_id`/`workflow.name` OTel attributes, so a composed fan-out can be reconstructed alongside the audit trail.

> Naming note: the `/config` **"Dynamic workflow size"** setting (advisory agent counts, default **medium** = aim for <15 agents, settable anywhere via `workflowSizeGuideline`) governs **native dynamic workflows** only — it is unrelated to PL0 dynamic *sizing* (complexity-scored stage selection). An 11-stage worktask is not "oversized" by it, but a DV fan-out composed *on top of* one is, and that fan-out spends from the same 20-concurrent budget.

### Gate prompts (AskUserQuestion)

> `AskUserQuestion` prompts are reserved for genuine decisions needing user input. Two **gates** exist and only two — the PL plan-approval gate and the FN finalization gate — and the FN gate additionally renders the batched closing elicitation sweep (`skills/shared/stage-contracts.md § Closing Elicitation Sweep`) immediately before its approve/reject call. Intra-loop stage transitions still proceed without confirmation, with one bounded exception: a sweep item marked `blocks_next_stage` is rendered at its own stage boundary, because the next stage would otherwise build on a guess. That is a render, not a gate — it creates no new approval carrier and changes no gate's firing condition — and it is opt-in per item, so the ordinary transition is unchanged.

#### Gate prompts — idle behaviour

These dialogs do not auto-continue on idle, so a PL/FN gate park holds indefinitely until the operator answers — the idle-timeout auto-continue is an explicit `/config` opt-in and MUST stay off on hosts running gated worktasks.
