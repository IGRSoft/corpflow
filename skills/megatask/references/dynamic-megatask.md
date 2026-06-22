# Dynamic Megatask — per-issue lanes on the native Workflow engine

Megatask normally drives its tracks with the Task-based orchestrator loop (see `../SKILL.md §
Orchestrator Pattern`). When the native **Workflow** engine is available, megatask can instead fan its
**ready** issues onto engine lanes — one lane per issue, each lane running that issue's autonomous span
(AR → … → QA) in its own worktree. This is the megatask counterpart to the single-issue `--dynamic`
span documented in `../../worktask/references/dynamic-workflow.md`.

> **Scope.** This is the *milestone/array* fan-out that used to live in
> `worktask/references/dynamic-workflow.md#milestone-template`. It moved here in v3.26.0 because
> multi-issue orchestration is megatask's domain — `/worktask` is single-issue and milestone-agnostic.

## Gate model

Megatask runs unattended: each per-issue PL0 is stamped `plan_gate: "bypass"` and `fn_gate: "bypass"`,
so a lane may run all the way through FN/ST. The single human checkpoint is megatask's **R1 batch
confirmation** (`../SKILL.md` / `../../commands/megatask.md` Phase 1), which states the exact PR count
before any lane launches. The **no-self-commit** invariant still holds per lane unless that lane's
`fn_gate` is `"bypass"` (which, under megatask, it always is).

## #milestone-template — `pipeline()`

Each issue maps onto a lane; each lane runs in its own worktree (`.worktrees/<group>/{issue#}/`, where
`<group>` is `milestone-{N}` or `issues-{shortid}`). The DAG gates which issues are *ready* — only ready
issues are passed into the engine pipeline; dependents are launched in later pipeline invocations as
their blockers complete (see `dependency-graph.md § Readiness & Unblocking`).

```js
export const meta = { name: "igrsoft-megatask-span", description: "per-issue worktree lanes", version: 1 };

const { issues, models, group } = args;  // issues: ready set [{ number, prompt, plan_file, run_index }]
// R1 GUARD: the orchestrator has ALREADY obtained one explicit operator confirmation stating exactly
// issues.length PRs will be opened across this batch. This script assumes that confirmation happened upstream.
return pipeline(
  issues,
  (issue)    => agent(issue.prompt, { agentType: "igrsoft:software-architector", model: models.AR, schema: SCHEMA.AR, isolation: "worktree" }),
  (_, issue) => agent(issue.prompt, { agentType: "igrsoft:developer",            model: models.DV, schema: SCHEMA.DV, isolation: "worktree" }),
  (_, issue) => agent(issue.prompt, { agentType: "igrsoft:technical-lead",       model: models.DR, schema: SCHEMA.DR, isolation: "worktree" }),
  (_, issue) => agent(issue.prompt, { agentType: "igrsoft:qa-engineer",          model: models.QA, schema: SCHEMA.QA, isolation: "worktree" }),
);
```

Each lane writes `.worktrees/<group>/{issue#}/.context/<stage>-N.md` and merges into that worktree's
`state.json`. `SCHEMA.<CODE>` is resolved from the canonical
`../../worktask/references/handoff-protocol.md#handoff-schemas` (verbatim transcription, no I/O / clock /
RNG, per the cache-prefix discipline). Per-issue FN (commit/push/PR) runs in `"bypass"` after the single
R1 confirmation, exactly as the Task-based loop does — and writes the completion contract
(`workspace.json.execution.status` + `execution.pr`) that `../../hooks/megatask-monitor.sh` reads to
unblock dependents.

## Risk controls (megatask-engine)

| ID | Risk | Mitigation (binding) |
|----|------|----------------------|
| **R1** | A dynamic megatask opens **N PRs autonomously**, bypassing per-issue human review. | The launch **requires one explicit operator confirmation that states the exact PR count** before any lane runs (megatask's R1 batch gate). The launch banner reads: `"Megatask <group> will open <count> PRs across <count> issues autonomously. Confirm to proceed."` No lane runs until the operator confirms. |
| **R6** | The engine's ~1000-agent cap can be exceeded by **very large milestones** (each issue spends multiple lanes). | **Shard batches larger than ~200 issues** into multiple runs (4–5 lanes/issue × 200 ≈ the cap). Megatask computes `lanes × ready-issues` before launch and refuses a single run that would exceed the cap, prompting the operator to shard. The DAG naturally bounds the live lane count to the *ready* set, which helps. |

## Resume

A crashed dynamic megatask resumes in the Task-based orchestrator loop (replay-or-degrade, never
rejoin) — identical to single-issue `--dynamic` resume. The orchestrator re-reads `orchestrator.json`,
re-derives `parallel_tracks` from the current ready set, and continues. See `../SKILL.md § Monitoring
Loop` and `../../worktask/references/dynamic-workflow.md#resume`.

## Related

- `../SKILL.md` — megatask orchestration (Task-based default)
- `dependency-graph.md` — readiness/unblocking that decides each lane wave
- `../../worktask/references/dynamic-workflow.md` — single-issue `--dynamic` span (the per-lane shape)
- `../../hooks/megatask-monitor.sh` — completion → unblock-dependents monitor
