# Dynamic Worktask Execution Mode (CC native Workflow engine) — Reference

Canonical reference for the **opt-in `--dynamic` execution mode** that runs the worktask's
autonomous, gate-free span on Claude Code's native dynamic-workflow engine (`Workflow` tool, `/workflows`,
v2.1.154). This is **additive**: nothing changes unless `--dynamic` is set. When the `Workflow` tool is
absent the orchestrator falls back to the manual loop unchanged.

This file is referenced by:

- `commands/worktask.md` — Phase 1 writes `metadata.execution_mode`; Phase 2 post-PL0-gate dispatch branch.
- `skills/worktask/SKILL.md` — manual loop is the default; dynamic mode delegates AR→DC/RE here.
- `skills/agent-coordination/SKILL.md` — § Parallel Execution (Native Workflow fan-out) + audit actor.
- `skills/worktask/references/handoff-protocol.md` — optional `workflow` state.json object + fallback F5.

> **NON-NEGOTIABLE INVARIANTS (the orchestrator owns these even in dynamic mode):**
> 1. **PL0 gate** — the post-planning HUMAN approval gate runs BEFORE any workflow is launched. The
>    `Workflow` tool is never dispatched until the human approves the plan.
> 2. **FN gate** — the pre-finalization HUMAN approval gate runs AFTER the workflow returns. The workflow
>    span STOPS before FN; commit/push/PR is never inside the workflow.
> 3. **No self-commit** — the workflow span never commits, pushes, or opens a PR. That is the
>    orchestrator-owned, human-gated FN stage.
> 4. The two **APPROVAL PROTOCOL** blocks in `commands/worktask.md` stay byte-identical. Dynamic mode adds
>    a branch *between* the gates; it does not weaken, move, or delegate either gate.

---

## #span-boundary

The native Workflow owns **only the contiguous gate-free span** between the two human gates.

```
PL0 (plan) -> PL0 GATE (HUMAN) -> publish-pl-issue.sh
   -> +-- native Workflow (background, run_id) ----------------------+
      |  AR -> TL -> DV(fan-out) -> DR -> [SR] -> QA -> [DC] -> [RE]  |   (STOPS before FN)
      +-------------------------------------------------------------+   returns aggregated schema
   -> FN GATE (HUMAN) -> FN (commit/push/PR) -> ST -> self-improvement
```

- **AR / TL run INSIDE the workflow** — they are stages, not gates. TL is where dynamic DV fan-out is
  decided (`parallel()`).
- The workflow **never crosses a human gate**. PL0 gate is upstream (orchestrator); FN gate is downstream
  (orchestrator). ST and self-improvement run after FN, in the orchestrator.

### #mode-span-gates — decision table

| Mode | Trigger | Workflow span | PL0 gate | FN gate | Notes |
|------|---------|---------------|----------|---------|-------|
| Interactive | `--dynamic` (no bypass flag) | AR → … → QA/DC/RE (stops before FN) | HUMAN (orchestrator, pre-launch) | HUMAN (orchestrator, on return) | Default dynamic shape. |
| Auto-continue | `--dynamic --auto-continue` | AR → … → ST (one workflow, no interactive gate) | bypass (`fn_gate:"bypass"`) | bypass | `fn_gate:"bypass"` already set; span extends past FN to ST. |
| Worktree | `--dynamic --worktree` | AR → … → ST | bypass | bypass | Per-issue isolation via `isolation:'worktree'`. |
| Milestone | `--dynamic --milestone:N` | `pipeline(issues, …)` fan-out, AR → … → ST per lane | bypass | bypass | **R1: one explicit operator confirmation stating the PR count before any lane runs.** |

> **Bypass modes** (`--auto-continue`/`--milestone`/`--worktree`) already set `metadata.fn_gate:"bypass"`
> on PL0. Because there is no interactive gate, the dynamic span extends to **PL→ST as one workflow**.
> Even so, the milestone launch requires R1 confirmation (below) — bypassing the *interactive* gate does
> not bypass the *multi-PR* confirmation.

---

## #script-template — single-issue

The script is a pure JS module: a literal `meta` export plus a default async function receiving the engine
helpers (`phase`, `agent`, `parallel`). **Cache-prefix discipline (binding):** the script body MUST be
deterministic — no `Date.now()`, no `Math.random()`, no per-run counters or timestamps baked into prompts
or `meta`. All run-varying values (`run_index`, `worktask_id`, model aliases) are passed in as `input`,
not generated inside the body. This keeps the cached prefix stable so `resumeFromRunId` replay hits cache.

```js
// .context/workflow/single-issue.workflow.js  (authored per-run by the orchestrator from the template)
export const meta = {
  name: "igrsoft-worktask-span",
  description: "AR->TL->DV->DR->[SR]->QA->[DC]->[RE] autonomous span between the PL0 and FN human gates",
  version: 1,
};

export default async function ({ phase, agent, parallel, input }) {
  // `input` carries non-deterministic values from the orchestrator (NOT generated here):
  //   { worktask_id, run_index, plan_file, platform, models, stages, complexity, secure }
  const { models, stages, complexity, secure } = input;

  const ar = await phase("AR", () =>
    agent(stagePrompt("AR", input), { agentType: "igrsoft:software-architector", model: models.AR, schema: SCHEMA.AR }));

  const tl = await phase("TL", () =>
    agent(stagePrompt("TL", input), { agentType: "igrsoft:team-lead", model: models.TL, schema: SCHEMA.TL }));

  // DV fan-out is decided by TL output (tl.fanout is an array of sub-task prompts, length 1 = no fan-out).
  const dv = await phase("DV", () =>
    parallel(tl.fanout.map((p) =>
      agent(p, { agentType: "igrsoft:developer", model: models.DV, schema: SCHEMA.DV, isolation: "worktree" }))));

  const dr = await phase("DR", () =>
    agent(stagePrompt("DR", input), { agentType: "igrsoft:technical-lead", model: models.DR, schema: SCHEMA.DR }));

  // Adversarial multi-dimension verifier fan-out when complexity >= 25 (correctness/performance/maintainability).
  if (complexity >= 25) {
    await phase("DR-verify", () =>
      parallel(["correctness", "performance", "maintainability"].map((dim) =>
        agent(verifierPrompt(dim, input), { agentType: "igrsoft:technical-lead", model: models.DR, schema: SCHEMA.DR }))));
  }

  if (secure) {
    await phase("SR", () =>
      agent(stagePrompt("SR", input), { agentType: "igrsoft:security-reviewer", model: models.SR, schema: SCHEMA.SR }));
  }

  const qa = await phase("QA", () =>
    agent(stagePrompt("QA", input), { agentType: "igrsoft:qa-engineer", model: models.QA, schema: SCHEMA.QA }));

  if (stages.includes("DC")) {
    await phase("DC", () =>
      agent(stagePrompt("DC", input), { agentType: "igrsoft:technical-writer", model: models.DC, schema: SCHEMA.DC }));
  }
  if (stages.includes("RE")) {
    await phase("RE", () =>
      agent(stagePrompt("RE", input), { agentType: "igrsoft:release-engineer", model: models.RE, schema: SCHEMA.RE }));
  }

  // Aggregated result; orchestrator reconciles into state.json on return, then evaluates the FN gate.
  return { ar, tl, dv, dr, qa };
}
```

`stagePrompt()`, `verifierPrompt()`, and `SCHEMA` are pure functions/literals defined alongside the
template (no I/O, no clock, no RNG). `code-review-dev` stays invoked **inside the DR agent** (the DR prompt
carries the `Skill("code-review-dev")` instruction exactly as the manual loop's section [7] suffix does).

### #milestone-template — `pipeline()`

Milestone mode maps N issues onto lanes; each lane runs in its own worktree
(`.worktrees/milestone-{N}/{issue#}/`).

```js
export const meta = { name: "igrsoft-milestone-span", description: "per-issue worktree lanes", version: 1 };

export default async function ({ pipeline, agent, input }) {
  const { issues, models, milestone } = input;  // issues: [{ number, prompt, plan_file, run_index }]
  // R1 GUARD: the orchestrator has ALREADY obtained one explicit operator confirmation that states
  // exactly issues.length PRs will be opened. This script assumes that confirmation happened upstream.
  return pipeline(issues, {
    planLane:   (issue) => agent(issue.prompt, { agentType: "igrsoft:software-architector", model: models.AR, schema: SCHEMA.AR, isolation: "worktree" }),
    devLane:    (issue) => agent(issue.prompt, { agentType: "igrsoft:developer",            model: models.DV, schema: SCHEMA.DV, isolation: "worktree" }),
    reviewLane: (issue) => agent(issue.prompt, { agentType: "igrsoft:technical-lead",       model: models.DR, schema: SCHEMA.DR, isolation: "worktree" }),
    qaLane:     (issue) => agent(issue.prompt, { agentType: "igrsoft:qa-engineer",          model: models.QA, schema: SCHEMA.QA, isolation: "worktree" }),
  });
}
```

Each lane writes `.worktrees/milestone-{N}/{issue#}/.context/<stage>-N.md` and merges into that worktree's
`state.json`. PR creation per issue is STILL the human-gated FN stage (bypass mode runs FN per lane only
after the single R1 confirmation; see #risk-register R1).

---

## #stage-agent-map

`agent(prompt, { agentType, model, isolation })`. `model` comes from `metadata.model` (unchanged source —
the orchestrator passes the per-stage alias into the script `input.models`). `agentType` is the
fully-qualified `igrsoft:<agent>` form matching a real file in `agents/`.

| Stage | agentType | model (alias, from metadata) | isolation | Frontmatter effort fallback |
|-------|-----------|------------------------------|-----------|------------------------------|
| AR | `igrsoft:software-architector` | opus | worktree (read) | xhigh |
| TL | `igrsoft:team-lead` | sonnet | worktree (read) | medium |
| DV | `igrsoft:developer` | opus | **worktree** | high |
| DR | `igrsoft:technical-lead` | opus | worktree (read) | high |
| SR | `igrsoft:security-reviewer` | opus | worktree (read) | xhigh |
| QA | `igrsoft:qa-engineer` | sonnet | worktree (read) | medium |
| DC | `igrsoft:technical-writer` | haiku | worktree (read) | low |
| RE | `igrsoft:release-engineer` | haiku | worktree (read) | low |

> **Effort param open item.** The `agent()` helper exposes `model` but (as of v2.1.154) has **no `effort`
> param**. Per-stage effort therefore falls back to each agent's **frontmatter `effort:`** (the
> "Frontmatter effort fallback" column above, sourced from `agents/<agent>.md`). This is acceptable because
> the plugin's frontmatter effort values already match the model-selection matrix
> (`skills/shared/model-selection.md`). When/if `agent()` gains an `effort` param, the orchestrator SHOULD
> pass `metadata.effort` through `input.efforts` and this fallback note can be retired.

---

## #handoff-schemas

Typed `schema` returns replace prose-frontmatter scraping on the typed path, but each stage STILL mirrors
its result to `state.json facts` and writes its `.context/<stage>-N.md` artifact (durability, human
readability, F4/F5 regeneration). Schemas are JSON Schema (draft 2020-12).

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DVHandoff",
  "type": "object",
  "required": ["verdict", "files_modified", "build_status"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "tests_added": { "type": "array", "items": { "type": "string" } },
    "build_status": { "type": "string", "enum": ["pass", "fail", "skipped"] },
    "decisions": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DRHandoff",
  "type": "object",
  "required": ["verdict", "findings", "blockers"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "p2_only": { "type": "boolean" }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "QAHandoff",
  "type": "object",
  "required": ["verdict", "tests_passed", "tests_failed"],
  "properties": {
    "verdict": { "type": "string", "enum": ["go", "no-go"] },
    "tests_passed": { "type": "integer", "minimum": 0 },
    "tests_failed": { "type": "integer", "minimum": 0 },
    "blocking_defects": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "SRHandoff",
  "type": "object",
  "required": ["verdict", "findings", "blockers"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "threat_model": { "type": "string" }
  }
}
```

### #schema-to-state-map

Each schema field maps onto the canonical `state.json` ledger (`handoff-protocol.md#state-json-schema`) and
the artifact anchor (`handoff-protocol.md#anchor-allow-list`):

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `DV.verdict` | `stages.DV.verdict` | development-N.md `## deviations` (summary line) |
| `DV.files_modified` | `facts.files_modified` (union) | development-N.md `## files-changed` |
| `DV.tests_added` | `facts.tests_added` (union) | development-N.md `## tests-added` |
| `DV.build_status` | `stages.DV.status` derivation | development-N.md `## deviations` |
| `DV.decisions` | `facts.decisions[]` | development-N.md (inline) |
| `DR.verdict` | `stages.DR.verdict` + `facts.verdicts.DR` | developer-review-N.md `## verdict` |
| `DR.findings`/`blockers` | `facts.decisions[]` (= findings) | developer-review-N.md `## findings`/`## blockers` |
| `QA.verdict` | `stages.QA.verdict` + `facts.verdicts.QA` | testing-N.md `## verdict` |
| `QA.tests_passed`/`failed` | `facts.verdicts.QA` (count string) | testing-N.md `## results` |
| `SR.*` | mirrors DR targets | security-review-N.md |

---

## #state-workflow-block

`state.json` gains an **optional** top-level `workflow` object (additive; version-1-compatible; ignored by
old readers — full schema lives in `handoff-protocol.md#state-json-schema § workflow`). The native `run_id`
is a **resume pointer only** — `state.json` + the Task System remain the source of truth.

```json
{
  "workflow": {
    "run_id": "<native Workflow runId>",
    "mode": "dynamic",
    "launched_at_stage": "AR",
    "stops_before": "FN",
    "budget": { "estimate_usd": 0, "ceiling_usd": 0 },
    "status": "running"
  }
}
```

### #boundary-reconciliation

On workflow **return**, the orchestrator reconciles (in the orchestrator turn, not the script):

1. Read `state.json`. For each stage in the returned aggregate, ensure `stages.<CODE>.status="completed"`
   and `verdict` are set (the script's single-writer merges should already have done this; reconciliation
   is idempotent — re-applying the same patch is a no-op).
2. Reconcile **Task System** status from `state.json`: for every stage with `status="completed"` in the
   ledger, mark the corresponding Task System task `completed`. (The script cannot call `TaskUpdate`; this
   is why reconciliation is orchestrator-owned.)
3. If any stage is missing from the ledger (script crashed mid-span), trigger **F5** (#fallback): reconcile
   from the typed `schema` returns the script *did* produce, else walk `.context/<stage>-N.md` frontmatter
   (F4 walk).
4. Set `workflow.status` to `returned`. Write `workflow_returned` audit row.
5. Evaluate the **FN gate exactly as today** (`skills/worktask/SKILL.md § FN Gate`).

---

## #resume

`resumeFromRunId = state.json.workflow.run_id`. Cached-prefix replay skips completed stages — the same
cache-prefix discipline (`handoff-protocol.md#cache-prefix`) that yields prompt-cache hits also makes
replay correct, which is why the script body MUST be free of timestamps/counters/RNG.

| State on reattach | Action |
|-------------------|--------|
| `workflow.run_id` present, `status:"running"`, `Workflow` tool available | `resumeFromRunId` — engine replays cached prefix, continues from first incomplete stage. |
| `workflow.run_id` present, `Workflow` tool **absent** (cold resume on older CC / headless / `--print`) | Degrade to manual loop. State→Action table is authoritative; F4 frontmatter walk rebuilds ledger; continue manually from first incomplete stage. |
| `workflow.run_id` present, `status:"returned"` | Span done — re-enter at the FN gate. |

> **Lost live-reattach (risk).** Once a dynamic run is resumed in manual mode, the live native run is not
> re-attached — there is no merge of an in-flight engine run back into the manual loop. Resume is
> "replay-or-degrade", never "rejoin". See #risk-register.

---

## #fallback

| Trigger | Detection | Degradation |
|---------|-----------|-------------|
| `Workflow` tool absent | `--dynamic` set but the `Workflow` tool is not in the orchestrator's tool list (older CC, headless `claude agents run`, SDK/`--print`) | Write `dynamic_fallback` audit row → run the **existing manual loop unchanged** (`skills/worktask/SKILL.md § Orchestrator Execution Loop`). |
| Dynamic run crashed | `workflow.status:"running"` on reattach but engine reports no live run | Resume in manual mode (see #resume). A crashed dynamic run always has a manual-mode recovery. |
| Mid-span state.json un-patchable | Script could not merge a stage's return | **F5** (`handoff-protocol.md#fallback-paths`): reconcile from typed schema returns; else F4 frontmatter walk on return. |

Detection is **fail-safe**: if there is any doubt the tool is present, the orchestrator MUST degrade to the
manual loop. The manual loop is always correct; dynamic mode is an optimization.

### #schema-merge-net

In manual mode, `state.json` integrity is protected by the 3-layer net (Layer 1 agent self-patch, Layer 2
`state-merge.sh` SubagentStop hook, Layer 3 orchestrator F3). In dynamic mode the **workflow script is the
single writer at sequential phase boundaries** — it atomic-merges each stage's typed `schema` return into
`state.json` and writes `audit.jsonl`. This **replaces** the 3-layer net *inside the span* with one
deterministic merge point. The design is **pessimistic**: the script merges + emits advisory
`workflow_agent_stopped` rows regardless of whether `SubagentStop` fires for workflow-spawned `agent()`
children (see #risk-register R2). If the hook DOES fire, its merge is an idempotent no-op against the
script's merge.

---

## #audit-vocabulary

Dynamic mode adds four audit actions (writers: orchestrator + `workflow-script` actor — see
`skills/agent-coordination/SKILL.md § Audit Trail Writers`). All are **advisory** when emitted by the
script (the orchestrator's reconciliation rows are authoritative).

| Action | Writer | When | Notes |
|--------|--------|------|-------|
| `workflow_launched` | orchestrator | After PL0 gate, before dispatching the `Workflow` tool | `metadata: { run_id, mode, stops_before, budget }` |
| `workflow_returned` | orchestrator | On workflow return, after reconciliation | `metadata: { run_id, stages_completed[] }` |
| `workflow_agent_stopped` | `workflow-script` | Each `agent()` child completion (advisory) | Mirrors `subagent_stopped`; deduped against the hook row if `SubagentStop` also fires. |
| `dynamic_fallback` | orchestrator | `Workflow` tool absent or run crashed → manual loop | `metadata: { reason }` |

---

## #budget

The native engine accepts a `budget` ceiling. **PL0 emits a budget estimate** during dynamic sizing
(`skills/worktask/SKILL.md § Dynamic Worktask Sizing`): a per-stage token/cost estimate summed across the
span, recorded at `state.json.workflow.budget.estimate_usd`. The orchestrator sets `ceiling_usd` (a
headroom multiple of the estimate, operator-tunable) and passes it to the `Workflow` tool. When the engine
hits the ceiling it pauses the run; the orchestrator surfaces the pause to the operator (it is NOT a
silent kill). Budget is **best-effort** — it bounds spend, it does not guarantee completion within it.

---

## #risk-register

| ID | Risk | Mitigation (binding) |
|----|------|----------------------|
| **R1** | **Dynamic-milestone opens N PRs autonomously**, bypassing per-issue human review. | The dynamic-milestone launch **requires one explicit operator confirmation that states the exact PR count** before any lane runs. Per-lane `fn_gate` policy MUST be explicit. The launch banner reads: `"Dynamic milestone N will open <count> PRs across <count> issues autonomously. Confirm to proceed."` No lane runs until the operator confirms. |
| **R2** | Unknown whether `SubagentStop` fires for workflow-spawned `agent()` children (so `state-merge.sh`/`audit-subagent.sh` may not run). | **Pessimistic design**: the script does its own schema-merge + emits advisory `workflow_agent_stopped` rows, so it is correct either way. If the hook fires, merges are idempotent no-ops. Recorded as open question q1 (build-time verification). |
| **R3** | `agent()` has no `effort` param → per-stage effort cannot be passed explicitly. | Falls back to agent **frontmatter `effort:`** (#stage-agent-map). Documented; retire when the param lands. |
| **R4** | Budget ceiling is best-effort, not a hard cap. | `ceiling_usd` bounds spend and pauses (not kills) the run; operator is surfaced the pause. Budget never guarantees completion. |
| **R5** | Lost live-reattach + DR-iteration efficiency: a resumed dynamic run degrades to manual rather than rejoining the live engine run; DR fix/re-review iterations inside the span re-run full stages rather than incremental. | Resume is "replay-or-degrade", never "rejoin" (#resume). DR adversarial fan-out is bounded to complexity ≥ 25 (#script-template) to limit iteration cost. |
| **R6** | The engine's ~1000-agent cap can be exceeded by very large milestones (each issue spends multiple lanes). | **Shard milestones larger than ~200 issues** into multiple dynamic runs (4-5 lanes/issue × 200 ≈ the cap). The orchestrator computes `lanes × issues` before launch and refuses a single run that would exceed the cap, prompting the operator to shard. |
