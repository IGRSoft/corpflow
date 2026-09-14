---
name: stage-contracts
version: 0.4.0
---

# Stage Contracts Reference

Single source of truth for what each stage consumes, produces, and how the orchestrator validates the handoff. Every stage agent's `## Completion Verification` section MUST link back here.

## How to Read a Contract

- **Inputs**: `.context/` artifacts and metadata read before starting. Missing → `missing_input` escalation (`agent-coordination` § Error Handling).
- **Outputs**: artifacts produced before `status: completed`, each with the listed minimum sections. **Every output MUST open with a `---\nhandoff:\n` YAML block** per `skills/worktask/references/handoff-protocol.md#frontmatter-schema`.
- **Validation**: the exact check the orchestrator runs on completion. False → the stage is not complete.
- **Agent + model** per stage: `skills/shared/stage-codes.md` — not restated here.
- **Error file**: `.context/errors/<agent-basename>.md`, derived from `metadata.agent` (`state-ledger` § Metadata Fields).

## Required Inputs (handoff-protocol)

Every stage agent reads inputs in this order, anchor-first:

1. Read `.context/state.json` (the worktask ledger). Extract `facts.decisions`, `facts.open_questions`, `handoffs`, `run_index`, and the `tasks` entries relevant to your stage.
2. Resolve `N` per [#run-index-resolution](#run-index-resolution). All this run's stage artifacts use `<basename>-${N}.md`.
3. Read only the listed anchors in upstream artifacts (e.g. `architecture-N.md#decisions`). Do **not** read whole files unless an anchor is absent.
4. Deep-read a full artifact only on retry (`retry_count > 0`), or when the frontmatter `next_stage_focus` explicitly names a non-anchored section.

**The ledger is mandatory.** An absent or unreadable `.context/state.json` is a hard failure, not a degraded mode: stop and report rather than guessing. There is no whole-file fallback list.

### #run-index-resolution

Canonical two-step resolver (see `skills/worktask/references/pl0-procedure.md § Stage Artifact Naming`):

1. `task.metadata.run_index` → `<basename>-${N}.md`.
2. Newest glob `<basename>-*.md` (highest N) when metadata is absent.

### No-restate rule

> Agents MUST NOT restate the run-index resolver or the atomic-write pseudocode in their own files — link to `#run-index-resolution` or `handoff-protocol.md#atomic-write` instead. Drift checker: `cache-lint.sh --frontmatter-template-lint`.

### #diff-only-read

Canonical cheapest-first read order for review/finalization stages (DR/SR/QA/DC/FN) when only a verdict, decisions, refs, or the delta is needed — full reads stay available whenever context requires them:

1. **Frontmatter-first**: read the upstream artifact's `handoff:` block (≤200 tok) instead of the whole artifact.
2. **Diff-only**: if `state.json → facts.files_read` lists a source path (read by DV or a prior stage), use `git diff <base>..HEAD -- <path>` for changed-file context, NOT `Read <path>`.
3. **Anchor-scoped**: when a single `## <anchor>` section suffices, `Read` that range, not the whole file.

#### Diff-only — full-read escape hatch

Read the full file ONLY when the above is insufficient, documenting the reason in the stage artifact's `§ Findings`/`§ Notes`; for files >200 lines use `Read` with `offset`/`limit` on the changed region. Absent `facts.files_read` → normal reads. Stage agents cite this anchor and keep a ~1-line steady-path reminder inline; they MUST NOT restate this full text.

## Required Outputs (handoff-protocol)

Every stage's output artifact MUST (full checklist: **Completion Verification** below):

1. Start with a `---\nhandoff:\n` block — ≤30 lines, ≤200 tokens, per-stage template `#tpl-<CODE>`.
2. Use H2 anchors from the per-stage allow-list in `handoff-protocol.md#anchor-allow-list` (kebab-case, no spaces, no underscores), plus the universal `## elicitation-sweep` anchor every artifact carries.
3. Atomically patch `tasks.<ID>` and the `handoffs["<PREV>→<TASK_ID>"]` edge into `.context/state.json`.

## Contract Table

Artifact paths use `<basename>-N.md` (N per [#run-index-resolution](#run-index-resolution)). Reading the rows:

- Every Validation cell implicitly requires that the named output artifact exists on disk; only the extra conditions are listed.
- **`<plan_file>`** resolves via `task.metadata.plan_file`; fallback newest `.context/planning-*.md`.
- **†** = frontmatter-first read (`Read <artifact> limit:30`); deep-read a body ONLY on anchor-miss, a section-flagging `verdict`/`next_stage_focus`, or `retry_count > 0`.
- Agent, model and error file per stage: **How to Read a Contract** above.

### PL–TL

| Stage | Required Inputs | Required Outputs | Validation |
|-------|-----------------|------------------|------------|
| **PL** | User request; trigger flags | `.context/<plan_file>` (`planning-N.md`, N = next free integer ≥ 0; `pl0-procedure.md § Plan File & Run Index Naming`): Goal, Scope, Complexity Score, Stage Plan, Approval Required. Plus `.context/designs/figma-registry.md` if Figma URLs provided | Complexity Score int 0–50 + Stage Plan lists downstream task subjects + `metadata.plan_file = <plan_file>` AND `metadata.run_index = N` stamped on every downstream task |
| **AR** | `<plan_file>` | `architecture-N.md`: Architecture Decisions, Trade-offs, Patterns, Integration Points | ≥1 decision with rationale |
| **TL** | `<plan_file>`, `architecture-N.md` (when AR ran) | `coordination-N.md`: Task Breakdown, Parallel Streams, Assignments, Risks | Task breakdown maps to DV sub-tasks |

### DV–SR

| Stage | Required Inputs | Required Outputs | Validation |
|-------|-----------------|------------------|------------|
| **DV** | `<plan_file>`; `architecture-N.md` (when AR ran — then MANDATORY, gate-enforced via `--validate-frontmatter --state`); `coordination-N.md` (when TL ran) | `development-N.md`: Files Changed, Approach, Tests Added, Verification Command quoting the runner's **verbatim** summary line — plus code changes | git diff non-empty + `files_touched` obeys `#files-touched` + the summary line is quoted + `tests_executed` + `test_summary_line` (or `test_suite_compiles` at 0) + `.context/logs/build-*.log` shows success |
| **DR** | `development-N.md` + source diff | `developer-review-N.md`: Code Quality, Test Coverage, Issues Found, Approval Status | Approval Status ∈ {approved, needs-changes, rejected} |
| **SR** | `development-N.md` + source diff | `security-review-N.md`: Threat Model, Findings, Severity, Remediation | No High/Critical findings unresolved |

### QA–RE

| Stage | Required Inputs | Required Outputs | Validation |
|-------|-----------------|------------------|------------|
| **QA** | `development-N.md`, `developer-review-N.md`, `.context/designs/figma-registry.md` (if present; else glob `.context/designs/figma-*.png`) | `testing-N.md`: Test Plan, Results, Design Comparison (if UI), Regression Check | `.context/logs/test-*.log` shows pass + no blocking defects + if `figma-registry.md` present, `testing-N.md § Design Comparison` has one row per registry entry |
| **DC** | `development-N.md`, `architecture-N.md` (when AR ran) † | `documentation-N.md`: Doc Changes, README Updates, API Docs | Docs diff present |
| **RE** | `development-N.md`, `testing-N.md`, `documentation-N.md` | `release-N.md`: Version Bump, Changelog, Deployment Checklist | Version bump proposed + changelog entry drafted |

### FN–ST

| Stage | Required Inputs | Required Outputs | Validation |
|-------|-----------------|------------------|------------|
| **FN** | Upstream `.context/*-N.md` † (log each deep read in the `deep_reads` tripwire) + `state.json` facts | `complete-summary-N.md`: Summary, Files Changed, Stage Timings, Next Actions. Plus `.context/attachments/{PR instructions,Review request}.md` (`conductor-attachments.md`) and commit/PR. Preflight: `skills/worktask/scripts/fn-preflight.sh` | Both attachments exist + commit created OR PR opened |
| **ST** | `complete-summary-N.md` | `retrospective-N.md`: Decision, Feedback, Follow-ups, Self-Improvement. Plus **optional** `.context/learnings.md`, only on in-scope user changes (`skills/self-improvement/SKILL.md`) | Decision ∈ {approved, rejected, changes-requested} + `self-improvement` invocation recorded (`learnings.md` present, or `Result: no-changes` in `.context/logs/self-improve-*.log`) |

### IR–ET

| Stage | Required Inputs | Required Outputs | Validation |
|-------|-----------------|------------------|------------|
| **IR** | User incident report | `incident-N.md`: Required Fix, Constraints, Blast Radius, Verification Command | All 4 sections non-empty |
| **ET** | `<plan_file>` + high-risk keyword match | `ethics-review-N.md`: Risk Assessment, Mitigation, Decision | Decision ∈ {pass, block, conditional} |

## Validation Protocol

The orchestrator runs validation between a stage's `completed` patch and the next stage's `in_progress`. Failure at any step → do NOT transition: append a `missing_input` entry to the *next* stage's error file and block until resolved.

### Steps 1–2

1. **File check**: every file in the next stage's `metadata.context_refs` exists on disk. A missing `metadata.error_file` means "no prior retries", not a failure.
2. **Frontmatter / typed-return check**: a **valid typed object** returned by the stage's `Task()` (orchestrator passed the `schema` from `handoff-protocol.md#handoff-schemas`, runtime honored it) **SUPERSEDES** this step — verdict and facts come from the validated object via `handoff-protocol.md#schema-to-state-map`, and the grep below is skipped; its only job, recovering the verdict from prose, is already done structurally.

#### Step 2 — no-typed-return grep path

With **no** typed return (the dispatch primitive takes no `schema` argument, or the stage returned no typed object), this grep is the path: `head -1 <artifact>` MUST equal `---`; `grep -c '^handoff:' <artifact>` MUST equal `1` within the top-of-file block. Missing frontmatter triggers fallback path F3 (orchestrator derives a minimal handoff record). The on-disk `.context/<artifact>-N.md` + `handoff:` frontmatter is written by the agent in BOTH cases — it remains the durability/compression form and the F4 regeneration source, never replaced by the typed return.

### Steps 3–5

3. **Anchor lint (DR gate)**: every produced artifact's H2 headings match the per-stage allow-list in `handoff-protocol.md#anchor-allow-list`. DR runs `cache-lint.sh --anchor-lint <artifact>` as a stage gate; the managed `PostToolUse` hook (`hooks/anchor-preflight.sh`) runs it at write time. No CI counterpart exists.
4. **Section check**: grep the output artifact for required section headers.
5. **Side-artifact check**: for DV/QA, the corresponding `.context/logs/` build/test capture exists.

### Steps 6–8

6. **Metadata check**: task `metadata` validates against `state-ledger` § JSON Schema.
7. **Error file check**: if `retry_count > 0`, `metadata.error_file` MUST exist on disk. If it is set but absent (orchestrator stamped the path, no agent has appended yet), treat as `retry_count = 0` — do NOT fail validation. The first appending agent creates it lazily (`mkdir -p` its parent, then append the retry block).
8. **state.json patch check**: after `Task()` returns, re-read `.context/state.json`. If `tasks.<ID>.status` is still `in_progress`, parse the artifact's `handoff:` frontmatter and atomic-merge it in (third belt-and-suspenders layer; `handoff-protocol.md#fallback-paths` F2/F3).

### Step 9 — AR-reference check (DV completion, warn-only in 3.42.0)

9. At DV completion, if `.context/state.json` has a `tasks.AR0` entry, run:

   ```bash
   skills/worktask/scripts/handoff-harness.sh --validate-frontmatter .context/development-N.md \
     --state .context/state.json
   ```

   A `warn:` line appends an audit row to `.context/logs/audit.jsonl` —
   `{"action":"ar_ref_check","result":"warn", …}` — surfaced in the DR dispatch prompt so DR
   reviews the missing linkage. It is **not** a `missing_input` block and does not stop the
   transition. Warn-only in 3.42.0; the orchestrator passes `--strict` (blocking) only when
   `CORPFLOW_AR_REF_STRICT=1` is set, and a future minor flips `--strict` to the default.

#### Step 9 — dispatch-time companion check

When AR completed, the DV0, DR0 **and** QA0 tasks MUST each carry `metadata.architecture_ref` (`{path, anchors, key_decisions}`) and name an `architecture-N.md` anchor in `context_refs`. When AR was excluded, none of them may carry either.

## Cross-Plugin Stages

When a stage is delegated to a qualified agent (e.g., `apple-developer:ios-developer` takes over DV):

- `metadata.agent` keeps the full qualified name; `metadata.error_file` derives from its last segment, collisions joined with `-` (`state-ledger` § error_file derivation).
- The output artifact path is unchanged — `.context/development-N.md` regardless of which plugin implemented DV.

## Multi-Run Within a Stage

When TL splits DV into DV0/DV1/DV2 (parallel streams):

- Each sub-task has its own `retry_count`
- All write to the same `.context/errors/developer.md` with distinct section headers (`## DV0 Retry 1 — …`, `## DV1 Retry 1 — …`)
- Output artifact is a single `.context/development-N.md` — each sub-task appends its "Files Changed" block

## Closing Elicitation Sweep

Canonical contract for the pipeline's end-of-stage asking logic. Every other file points here; none restates it.

### What it is and when it fires

Before it hands off, every stage runs one closing pass over its own output and asks what it decided on the user's behalf that the user would rather decide. Each surviving question becomes a typed `open_questions[]` item (§ Item shape).

**Every template that shows `open_questions[]` inherits this rule, including its vocabulary:** an observation with nothing to answer is not a sweep item and goes to `follow-ups` (§ A risk-shaped observation is not a sweep item).

**Mandatory for every stage.** A stage with nothing to ask emits an explicit `open_questions: []` plus a one-line "nothing to elicit" statement under its `## elicitation-sweep` heading — a mandatory H2 anchor in every artifact (`handoff-protocol.md#anchor-allow-list`). Silence is a contract violation, because an omitted sweep and an empty one are otherwise indistinguishable.

#### Agents emit; the orchestrator asks

Each stage writes its own stubs into `facts.open_questions[]` itself, in the `state-patch.sh --facts` payload of its self-patch call — nothing derives them from the frontmatter, and a stub that skips `--facts` never reaches a render (`handoff-protocol.md#facts-union`). No stage agent holds `AskUserQuestion`; the orchestrator alone renders.

#### Where an item is answered

Two destinations, selected per item by `blocks_next_stage` — never by stage:

- **`blocks_next_stage: true`** → answered at **its own stage boundary**, before the next stage is dispatched, because the next stage would otherwise build on a guess. PL's sweep is the long-standing instance of this, answered at the plan gate.
- **absent or `false`** → accumulates in the ledger and renders at the **FN gate**, grouped by originating stage, in batches of ≤4, immediately *before* the existing approve/reject call (`commands/worktask.md § Step C`; `skills/worktask/SKILL.md` loop step 4.9).

**No new gate is created**, and the FN and plan gates keep their existing firing conditions. A blocking item does add a round-trip at its own boundary — that is the point of the flag, and it is why the flag is set per item rather than per stage. *Who* takes it depends on the stage (§ Blocking items are resolved, not asked).

#### Blocking items are resolved, not asked

A `blocks_next_stage: true` item from a stage **other than PL, FN, ST or IR** does not stop the run for a human. It is handed to a **sub-agent dispatched one effort tier above the stage that raised it**, which answers it from the stage's own artifacts; the orchestrator waits for that answer and dispatches the next stage. Mechanism: `commands/worktask.md § Step C.0a`. Why a tier and not a model, how that tier travels, and where it is clamped: § Resolver Effort Tier.

The four exception stages keep their existing surfacing (§ Exceptions — PL, FN, ST, IR): PL's items are the plan gate's business, and FN/ST/IR are recorded rather than prompted already, so there is nothing for a resolver to unblock.

##### What the resolver is given

The stub carries `{id, class, ref, blocks_next_stage}` and nothing else, and § Token budget caps a handoff block at 200 tokens — far too thin to decide on. The resolver gets **paths, not inlined content**, and reads what it needs. Filenames resolve through `handoff-protocol.md #stage-artifact-map`; there is no second mapping.

| Tier | Contents |
|---|---|
| in full | the emitting stage's own artifact — it holds the `## elicitation-sweep` body with `options[]`, `recommended` and `rationale` |
| in full | `planning-N.md` — `## requirements`, `## acceptance-criteria`, `## scope` bound every answer |
| frontmatter only | every completed stage's artifact — the designed compression form |
| ledger | `facts.decisions[]`, `facts.verdicts`, and the item's already-`resolved` siblings — prior commitments the answer must not contradict |
| on demand | `files_touched` from the emitting stage's handoff, and any artifact the item names |

##### What the resolver is given — declaring the full reads

Full reads go in the existing `deep_reads` field (`handoff-protocol.md § Schema — deep_reads`), whose `reason` enum already carries `ambiguous` — a sweep item exists *because* something was ambiguous. **A resolver's `deep_reads` is exempt from the B4 fan-in tripwire**: that signal means "a producing stage's frontmatter is under-informative", and a resolver deep-reads by construction, so counting it turns the tripwire into noise.

##### The escalation guard is untouched

Only `effective_class == "decision"` items reach a resolver, and only after the § Step C.2 raise-only join has run — so an item the orchestrator raises to `escalate` can never arrive. Escalate items stop the run exactly as before. Nothing here widens what runs unattended, which is the invariant `commands/worktask.md § Escalation guard (BINDING)` exists to hold.

This is deliberately a partial remedy. It removes the human round-trip for the blocking items that were only ever a judgement call; it removes none of the ones that were correctly escalated, and it is not a licence to relabel the latter as the former to make a run quieter.

#### Facts are not sweep items

A question whose answer some artifact already holds is the agent's to resolve, not the user's to answer; cost is not an exemption — an expensive lookup is delegated work. The rule is stated once at `skills/worktask/references/pl0-procedure.md § Facts are PL0's job; decisions are the user's` and binds every stage, not only PL.

### Item shape

One shape over three transports — the stub-plus-anchor split `key_decisions` / `facts.decisions` already uses, because the 30-line frontmatter budget cannot hold option bodies.

| Transport | Carries |
|---|---|
| artifact body `## elicitation-sweep` | the FULL item: `options[]`, `recommended`, `rationale`. Canonical; mandatory anchor. |
| `handoff.open_questions[]` frontmatter | a STUB: `{id, class, ref}` |
| `facts.open_questions[]` ledger | the stub plus `stage`, `blocks_next_stage`, `status: open\|resolved` and `resolution` |
| typed return `open_questions[]` | the full item inline |

Schemas: `handoff-protocol.md#frontmatter-schema` `$defs/SweepItem` (full) and `$defs/SweepStub` (stub). `options[]` holds 2–4 `{label, detail}` entries with exactly one `recommended: true`; `class` is `decision` or `escalate`; `rationale` is one line; `ref` anchors into the emitting stage's own artifact, which the orchestrator resolves at render time.

#### The stub carries no summary

`summary` is **optional** on the stub and canonical in the artifact body: the render reads the question text from the `ref` anchor, whose existence `handoff-harness.sh` verifies. Optional, not forbidden — the stub is the only accepted item shape, so an optional field needs no discriminator to keep it apart from anything else.

The driver is the **200-token budget on the whole `handoff:` block**, enforced by `handoff-harness.sh` over the extracted frontmatter. It is a property of the block, not of the sweep: on a review stage `key_decisions` dominates, and shortening the stub alone will not bring an over-budget block back under.

#### A risk-shaped observation is not a sweep item

The class enum is exactly `decision | escalate` and stays that way. An observation that records a
risk without asking anything — no options, nothing to answer, nothing to gate — belongs in the
artifact's mandatory `follow-ups` anchor, which every development and review artifact already
carries. **Neither sweep class is a home for it.** Filing one as `escalate` to make it visible is
the mis-file that once nearly triggered a destructive action against a sibling's live stack; filing
one as `decision` puts an unanswerable question in front of the gate. If it has options and a
recommendation, it is a sweep item; if it is something the next run should look at, it is a
follow-up.

##### Reaffirmed, against three streams that reached for a third class

The ruling was re-opened and argued on its merits, not carried over. The counter-evidence is real:
three independent streams in one run reached for three labels the enum does not have — `defect`,
`constraint` and `risk`. Counted, that looks like demand for a third class.

Read closely, **none of the three is a question.** Each names a thing observed; none carries an
option set or a recommendation. Against this section's own test, all three are follow-ups. The
counter-evidence, examined rather than counted, **confirms** the ruling.

###### The pull is toward the transport, not the taxonomy

What the three labels do prove is a different defect: the sweep is the only transport with a ledger
channel (`--facts`) and a gate render, while `follow-ups` is artifact-only and reaches no decision
point. Widening the enum would satisfy that symptom and reintroduce the exact mis-file the incident
above records; the transport gap is filed as a follow-up instead.

**Ruling: the enum stays exactly `decision | escalate`.** A narrow enum is only survivable if its
refusal cannot be missed, which is why `state-patch.sh` echoes an out-of-enum rejection to standard
output as well as standard error. Keep the enum narrow, keep the refusal loud.

#### A re-emitted stub carries its answer forward

When a stage re-emits an item it already emitted — a rework round, a retry — it MUST carry the existing `status` and `resolution` forward rather than re-emitting the item as open. `open < resolved` is monotone in BOTH transports — artifact frontmatter `handoff.open_questions[]` **and** `state.json facts.open_questions[]` via `state-patch.sh --facts`: the ledger union refuses the downgrade (`state-patch.sh`), and this rule is the artifact-side half, which is the one that survives ledger eviction. Re-marking a settled item "open" has already destroyed a recorded answer once in this repository.

#### Ledger bounds

At most **4 items per stage** (the ask tool's questions-per-call ceiling, so one stage never needs
splitting). `state-patch.sh` clamps `facts.open_questions[]` to the **newest 4 per task**, and the
clamp is **resolved-first inside each task's bucket**: every unresolved item survives ahead of every
resolved one, because an unresolved item is still owed a render at the FN gate while a resolved one
is already eviction bait under eviction-order rule 2. Same single-chokepoint idiom as
`facts.decisions` (newest **8 per task**) and `facts.dispatched_agents` (6, launched-survive-first,
and **not** partitioned — it is not a per-writer field).

##### Ledger bounds — the partition key

The bucket is the **full task id** (`DV1`), never the bare stage code. A four-way DV split is four
independent writers sharing one code, so a stage-code bucket lets DV3 evict DV0's items — the same
modelling gap `handoffs` had before its edges became task-keyed. Questions carry the id in their own
`sw-<TASK_ID>-<n>`; decisions carry it in `.stage`, stamped from the writer's own identity at write
time on the incoming array only, so an incumbent is never re-attributed. An item with neither falls
into a reserved `_` bucket, which keeps a pre-partition ledger in one shared bucket rather than
scattered across confident mis-attributions.

###### The partition key is not the grouping key

`.stage` on a question keeps its bare-code meaning for the FN gate's grouping. Grouping and
partitioning are two jobs, so the clamp derives its own key rather than reusing that field.

**Breaking for in-flight ledgers, by policy**: no migration step, no tolerant reader. Under the new
writer an old ledger lands in the reserved bucket or forces a logged re-merge — it fails loudly or
not at all, never by silent mis-parse.

##### Ledger bounds — the overflow spill

Past 4 **unresolved** items in one task's bucket the clamp has no eviction bait left to drop, so it
evicts a live question. Those — and only those — are appended to
`.context/open-questions-<run_index>.jsonl`, one JSON object per line: the full stub plus
`spilled_at` and `spilled_from_stage`. Evicted **decisions** spill the same way to
`.context/decisions-<run_index>.jsonl`, minus the `was_resolved` annotation a decision has no status
to carry.

###### The spill is written before the rename

Both files are append-only, written inside the merge lock and **before** the ledger rename, so a
crash can leave a spill line whose eviction never committed (a duplicate the union collapses) but
never an eviction whose spill line is missing.

###### Every spill has a reader — never read a ring alone

`handoff.open_questions[]` and `facts.open_questions[]` are both the record.
`handoff-harness.sh` checks parity against ledger ∪ spill, and the FN gate reads both, unioned by
`.id` with **the ledger winning on conflict** — a spill line is a snapshot taken at eviction time
and is necessarily staler than an item the ledger later resolved. A missing spill file is the empty
set; one that exists but cannot be parsed is a failure, never an empty set.

The decisions ring is read the same way, by `state-patch.sh --read-decisions`. **Never read
`facts.decisions[]` alone**: past eight per task it is a partial record that reports no partiality,
which cost one run three of its cross-client parity decisions.

##### Ledger bounds — why 4 per task

4 is a **deliberate bound, not a default**: it is the per-stage emission ceiling stated at the top of
this section, so transport and emission are now the same number. That equality is the whole point —
a conforming writer never spills, and a writer that does spill is over-emitting, which is a signal
rather than a silent loss. The retired global 12 was smaller than what thirteen stages were told to
emit, so it destroyed conforming writers' items as a matter of course.

Decisions keep **8** and only their scope moved: nothing caps decision emission, so inventing a
smaller number would open a new eviction source in the change that exists to close one.

###### What the per-task bound costs

The cost is taken with open eyes. Per-task partitioning multiplies worst-case capacity by the task
count and **there is no global ceiling any more**; the backstops are `validate_state`'s
non-blocking `state.json … > 500 budget` notice and the two spill files. A loud oversized ledger beats a silently
lost decision.

Sweep answers are recorded in the item's own `resolution` field, **not** appended to
`facts.decisions[]` — one record, one place. A second write to the decisions ring would put the same
answer under two bounds with two eviction policies, and the ring is for decisions an author stated,
not for answers the gate collected.

#### Item ids

`sw-<TASK_ID>-<n>` — `sw-AR0-1`, `sw-DV1-2`. Task-scoped, because the ledger unions `open_questions[]` on `.id` (`handoff-protocol.md#facts-union`): an unscoped `q1` would silently replace PL's. Deterministic, so a stage re-run is byte-identical.

### Sweep obligation matrix

Every code in `stage-codes.md § Primary Stages`, unioned with the `handoff-protocol.md § Handoff
Schemas` titles, owes a sweep. No stage is exempt and there is no lower tier: a missing sweep fails
the run. The default, which twelve of the thirteen once restated as identical table rows, is: an
item is **surfaced at the FN gate when non-blocking and at this stage's own boundary when blocking**,
and in an unattended lane it is **recorded, not prompted**.

Which side applies is decided per item by `blocks_next_stage` (§ Where an item is answered), never by
the stage code. `commands/worktask.md § Step C` renders the non-blocking side; § Step C.0 renders the
blocking side at each boundary.

#### Exceptions — PL, FN, ST, IR

Four stages depart from that default, and only in how an item is surfaced or what an unattended lane
does with it — never in whether the sweep is owed:

| Code | Obligation | Surfaced by (non-blocking / blocking) | Unattended fallback |
|---|---|---|---|
| PL | Required | plan gate / plan gate (PL's boundary IS the plan gate) | auto-decided at § Step A.4, else recorded — unresolved `escalate` items still force the checkpoint stop |
| FN | Required | recorded for ST / FN's own boundary, before ST | recorded, not prompted |
| ST | Required | recorded as follow-ups / ST's own boundary | recorded, not prompted |
| IR | Required | FN gate / this stage's own boundary | `--emergency` bypasses both gates: recorded |

#### Why those four depart

PL, FN and ST differ because they have no *later* gate to defer to — PL's own boundary is the plan
gate, and FN and ST sit at or past the FN gate — so "surface at the FN gate" is not a destination
they can name. IR differs because `--emergency` bypasses both gates by design.

Every other code — AR, TL, DV, DR, SR, QA, DC, RE, ET — takes the default sentence above
unmodified, and a new stage code joins them by saying nothing here.

### Auto-answer boundary

Auto-answerable: `class: decision` items whose recommendation is reversible, in-scope, posture-neutral and spend-free. Never auto-answerable: the **escalation class**, enumerated once at `commands/worktask.md § Escalation guard (BINDING)` and deliberately not re-listed here.

There is exactly one auto-answer authority — the existing Fable decision delegate, widened to sweep items (`skills/worktask/SKILL.md § Auto-Decision Delegation`), running only under `decision_gate: "auto"`. A deterministic non-model hook is deferred to a follow-up; its mechanism would be the `PreToolUse` `{"updatedInput": …}` path in `skills/agent-coordination/references/hook-monitoring.md`.

#### Self-labels raise, never lower

`class` is the ordered lattice `decision < escalate`, and the orchestrator's effective class is `max(agent label, orchestrator label)` — computed before any auto-answer, so raising is honoured and lowering is refused by construction. `blocks_next_stage` is the 2-element lattice `false < true` and joins the same way, by OR: the orchestrator may raise an item to blocking, never clear the agent's flag. One idiom, two axes, and they are orthogonal — an `escalate` item may or may not block. Mechanism: `commands/worktask.md § Escalation guard — raise-only self-labels`. Escalation-class behaviour under a bypassed gate or an unattended lane is per carrier — one row each in § Unattended fallbacks.

##### The join is over labellers, never transports

The lattice above resolves a disagreement between two *parties* labelling one item. It does **not** apply when one agent's artifact stub and its own ledger stub disagree: that is a single author with two copies, so a divergence is a **defect, not a lattice**. Never join them — the harness fails the stage (`handoff-harness.sh check_sweep_ledger`, which compares `class` and `blocks_next_stage`, not just `id`) and the agent reconciles both copies. Joining instead converts a bookkeeping slip into a real gate, which is how a non-blocking QA-scoping question once stopped a run before DR. The corollary binds the orchestrator too: a value it raises at Step C.2 is written at C.5 to BOTH the artifact's `handoff.open_questions[]` stub **and** `state.json facts.open_questions[]`, because a one-sided write manufactures exactly the divergence the harness refuses.

### Not the sweep

The sweep carries decisions a person would want to make. Four cases already own a channel; routing them through the sweep duplicates a contract instead of reusing it. Never where a channel already exists.

| Case | Use this instead | Defined at |
|---|---|---|
| runtime evidence is needed | `requests_test_evidence:` in the stage artifact | `skills/shared/testing-strategy.md § Test-Execution Authority` |
| a stage PL0 skipped is needed | `requests_stage_escalation:` in the stage artifact | `skills/estimation-methodology/SKILL.md § Escalation schema` |
| a stage verdict | `handoff.verdict` + `facts.verdicts` | `skills/worktask/references/handoff-protocol.md` § Per-stage required-field matrix |
| an ethics decision | `ethics-review-N.md` `Decision ∈ {pass, block, conditional}` | `skills/shared/stage-contracts.md` § #tpl-et |

### Unattended fallbacks

Recording never stops; only prompting does. One behaviour row per carrier, each carrier detected from its own defining field.

#### Fallbacks — gate carriers

| Carrier | Detected by | Sweep behaviour |
|---|---|---|
| plan gate bypassed | `PL0.metadata.plan_gate == "bypass"` | PL's sweep recorded, not prompted — **except** unresolved `escalate` items, which still force the plan-gate checkpoint stop; non-PL sweeps still batch at FN |
| FN gate bypassed | `PL0.metadata.fn_gate == "bypass"` | collect and audit `sweep_recorded`; escalate-class items also audit `sweep_escalation_unprompted`. Subject is the boundary that would have rendered — `FN<N>` for a batched item, `<CODE><N>` for a blocking one |
| auto decision gate | `PL0.metadata.decision_gate == "auto"` | `decision` items answered by the delegate; `escalate` items hold their own checkpoint — the plan gate for planning-stage items, finalization otherwise |

#### Fallbacks — unattended lanes

| Carrier | Detected by | Sweep behaviour |
|---|---|---|
| `--emergency` | no PL task in `tasks` | both gates bypass, so every sweep is record-only |
| `/megatask` per issue | `PL0.metadata.megatask_group` | PARK on any escalate item, at whichever boundary it surfaces: `workspace.json.execution.status: "failed"`, `execution.reason: "parked_escalation"`, `escalation_parked` audit row with that boundary's `<CODE><N>` subject |
| `CORPFLOW_NONINTERACTIVE=1` | environment | record, never prompt |
| headless dispatch | external runner | data-only by construction — no stage agent holds the ask tool |

## Resolver Effort Tier

How the Step C.0a resolver's effort tier is chosen, transported and clamped. Kept out of
§ Closing Elicitation Sweep deliberately: the sweep obligation is strict from day one and its
section is linted for any warn-only, opt-in or advisory vocabulary, whereas effort transport is
genuinely advisory on one of its two surfaces. Two different subjects, two sections.

### Why a tier up, and why the same model

The item exists because the stage could not settle it at its own tier. Re-asking the same agent at the same effort re-runs the reasoning that already declined; one rung up is the cheapest thing that is actually different. The **model is unchanged** — the stage's assignment already reflects the work's difficulty, and swapping it would change two variables to explain one outcome.

Ladder, from `skills/shared/model-selection.md § Effort Levels`: `low < medium < high < xhigh < max`, saturating at `max`. Executable copy — the one every consumer reads — is `skills/worktask/scripts/effort-ladder.sh`; the bats suite asserts the two agree.

### The tier is a request, not a guarantee

`metadata.effort` is honoured on the headless dispatch surface (`--effort`) and is **advisory
in-process** — `Task()` takes no effort parameter, so an in-process resolver runs at its agent's own
frontmatter tier (`agent-coordination/references/headless-dispatch.md § Translation table — model &
effort`). The bump is therefore computed and recorded on every path and *applied* on one. Every
resolver audit row carries `effort_transport` saying which it was; `commands/worktask.md § Step C.0a
— the tier only reaches some dispatch surfaces` holds the table.

Recorded-not-applied is still worth doing: the ledger gains the tier the pipeline believes the item
deserved, which is what a later `Task()` effort parameter would consume unchanged. What it is not is
a licence to reach the number another way — substituting a higher-frontmatter agent trades the
domain expertise answering the question for a field value, which is the wrong direction.

### The tier the model can actually carry

`xhigh` requires Opus 5 or Fable 5; Sonnet silently downgrades the thinking budget rather than failing (`model-selection.md § xhigh routing`). A bump that crosses that line on a non-Opus model is therefore **clamped to `high`** and audited `effort_clamped`, never dispatched as a tier that evaporates in transit. No current stage hits the clamp — every non-Opus stage sits at `medium` or below — which is precisely why it has to be enforced in code rather than remembered: nothing in a run would show it if it started happening.

A second silent path is not clampable and must be read from the audit row instead: `xhigh`/`max` requested in a session with thinking turned off is sent as `high`. Resolvers therefore audit `effort_requested` **and** `effort_resolved`, the same reason `dispatched_agents[].model_resolved` exists.

## Per-Stage Frontmatter Templates

Canonical YAML templates for the `handoff:` block atop every stage artifact. Each agent's `## Handoff Protocol` pastes the matching block verbatim (with substitutions) into `.context/<artifact>-N.md` (N per [#run-index-resolution](#run-index-resolution)). These are the single source of truth — agents MUST NOT diverge from the field shape below. To change a template, edit here, then re-run `cache-lint.sh --frontmatter-template-lint agents/*.md` to revalidate every agent's inline copy.

### Typed-return equivalent

> Each template below has a `<CODE>Handoff` JSON-Schema counterpart in
> `handoff-protocol.md#handoff-schemas` — a *parallel, validated* channel sharing one verdict
> vocabulary per stage. Supersession rules and the write-either-way requirement: **Validation
> Protocol** steps 1–2 above.

### #tpl-pl — Planning (product-manager)

```yaml
---
handoff:
  stage: PL
  verdict: ok                  # ok / blocked / escalate
  summary: "<one-line summary ≤200 chars>"
  rejection_reason: "<gate feedback, revisions only; omit on first draft>"
  key_decisions:
    - { id: pd1, summary: "<decision>", anchor: "planning-N.md#scope" }
  next_stage_focus: "<imperative: what AR must grep/design>"
  open_questions:
    - { id: sw-PL0-1, class: decision, ref: "planning-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    spec: .context/attachments/<spec-file>
    plan: .context/planning-N.md#requirements
---
```

Prev→this label: `USER→PL`.

#### rejection_reason — after a plan-gate rejection

After a plan-gate rejection, the revised `planning-N.md` MUST set `rejection_reason:` to the user's gate feedback (verbatim or condensed) — distinct from the `## Key Decisions` narrative — so downstream stages and ST retrospectives can cite it without reconstructing it from `audit.jsonl`. Omit the field on a first, un-rejected draft.

### #tpl-ar — Architecture (software-architector)

```yaml
---
handoff:
  stage: AR
  verdict: ok                  # ok / blocked / escalate
  summary: "<one-line summary ≤200 chars>"
  key_decisions:
    - { id: ad1, summary: "<decision>", anchor: "architecture-N.md#decisions" }
  next_stage_focus: "<imperative — addressed to TL when TL is in the plan, else to DV>"
  open_questions:
    - { id: sw-AR0-1, class: decision, ref: "architecture-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    plan: .context/planning-N.md#requirements
    decisions: architecture-N.md#decisions
---
```

`key_decisions` is also the source the orchestrator digests into the `metadata.architecture_ref.key_decisions` string (≤200 chars) stamped on the DV0/DR0/QA0 dispatches — keep each summary self-contained.

Prev→this label: `PL→AR`. Skip-exploration short-circuit applies — see `agent-coordination/SKILL.md § Orchestrator → PL0 Handoff`.

### #tpl-tl — Team Lead (team-lead)

```yaml
---
handoff:
  stage: TL
  verdict: ok                  # ok / blocked / escalate
  summary: "<one-line coordination summary ≤200 chars>"
  next_stage_focus: "<imperative: DV batch order + parallelization>"
  open_questions:
    - { id: sw-TL0-1, class: decision, ref: "coordination-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    plan: .context/planning-N.md#requirements
    arch: .context/architecture-N.md#decisions   # ONLY when AR ran; omit otherwise
    fan_out: coordination-N.md#fan-out
---
```

Prev→this label: `AR→TL` (or `PL→TL` when AR was excluded). Skip-exploration short-circuit applies.

### #files-touched — the changed-file list

Every stage that emits `handoff.files_touched` emits it in **one** shape. Seven of nine budgeted
stages once failed the token budget on this field alone and each invented its own truncation, so
the shape is fixed here rather than left to the emitter.

#### Semantics — post-merge repo-relative

A path is written as it will read **after** this work
merges: relative to the repository root, never to a worktree, and never absolute. During a run the
file physically lives under the emitting task's `metadata.workspace_path`, so any consumer that
wants to open it resolves `<workspace_path>/<path>`. That resolution base is the answer to "where
is this file right now"; the recorded value is the answer to "what did this run change", and the
two differ for the whole life of a worktree. No script enforces existence today — enforcement waits
until the convention has run a full pipeline (see the DV artifact's `follow-ups`).

#### Cap — `FILES_TOUCHED_MAX = 10`

Emit the first ten repo-relative paths, then, when the full set
is larger, exactly one final entry of the literal form `+ <count> more`:

```yaml
  files_touched:
    - skills/worktask/scripts/state-patch.sh
    - skills/worktask/scripts/handoff-harness.sh
    - "+ 7 more"
```

Ten paths plus the marker cost 33 proxy tokens of the 200-token discretionary budget. The constant
lives here and in `handoff-harness.sh`; the budget checker gains no second block extractor and no
second cap constant, because the list stays inside the discretionary count rather than being
excluded from it. `handoff-harness.sh --validate-frontmatter` fails a list longer than the cap
without a marker, a marker that is not last, and more than one marker.

#### The marker obliges the body

**Whenever the marker is present**, the artifact's own changed-files body section carries the FULL
set and is marked authoritative **in the same edit** — the frontmatter is an excerpt, and an
excerpt nobody can complete is the ad-hoc truncation this convention replaces.

### #tpl-dv — Development (developer)

```yaml
---
handoff:
  stage: DV
  # task_id: DV1               # set only when the stage has more than one task
  verdict: ok                  # ok / blocked / escalate
  summary: "<N files modified, M tests added>"
  tests_executed: 12          # cases RUN, not discovered; 0 is legal
  test_summary_line: "12 tests, 0 failures"  # verbatim; REQUIRED when the count is non-zero
  test_suite_compiles: true   # true/false/unknown; REQUIRED when the count is 0
  files_touched:              # cap 10, then ONE marker; #files-touched
    - path/to/file1.md
    - "+ 7 more"              # obliges the FULL body set
  next_stage_focus: "<imperative: what DR/QA must focus on>"
  open_questions:
    - { id: sw-DV0-1, class: decision, ref: "development-N.md#elicitation-sweep", blocks_next_stage: false }
---
```

#### The refs and architecture half (tpl-dv)

```yaml
# …continued: handoff
  refs:
    decisions: architecture-N.md#decisions    # ONLY when AR ran; omit
    coordination: coordination-N.md#fan-out   # ONLY when TL ran; omit
    tests: development-N.md#tests-added
  architecture:                # ONLY when AR ran; omit the object otherwise
    ref: architecture-N.md#decisions
    applied: true              # truthful; see the reference contract below
```

Prev→this label: `TL→DV` (`AR→DV` without TL, `PL→DV` when neither ran, `IR→DV` on emergency).

#### UI evidence comes from the running app (tpl-dv)

A screenshot offered as DV evidence is captured from the app **built and run on its real runtime
surface this run**, with each control confirmed on-screen and driven — the full rule, including the
per-platform adapter table, is `skills/dv-screenshot-capture/SKILL.md § Capture`, and it is not
restated here.

The contract consequence is what belongs in this file: a `ui_visual_check` whose only evidence is a
static render — `#Preview`, `ImageRenderer`, an IDE canvas — is **incomplete, not merely weaker**.
Canvas capture is the registered *degraded* adapter on Apple and emits
`screenshot_platform_fallback`; a DV artifact resting on it without that row, or with it and no
statement of why the live surface was unavailable, has not shown the change working. Recapture from
a live-driven run rather than arguing the render is equivalent — the two differ exactly where UI
defects live: real data, real layout, real state transitions.

#### Verification Command carries the runner's verbatim summary line (tpl-dv)

`## verification-command` MUST carry the command **and** the summary line the runner printed,
copied byte-for-byte into the artifact or into a `.context/logs/` capture the artifact names. Not a
paraphrase, not a count retyped from memory, not "all tests pass".

This is a requirement, not a good habit. DV and QA hold test-execution authority and **nothing
between them does**, so once the stage closes no reader downstream can re-derive the number — the
artifact is the only record that a count was ever observed. A stage reporting a green suite without
the line has produced an unverifiable claim, and DR treats it as one.

Where a runner writes its tally only to a terminal, capture through a pty or a log and copy the line
out of the capture. Where a stage's scoped authority refuses the full-suite entrypoint, record the
refusal and quote the summary line of the scoped run that was permitted.

##### test_summary_line is the checked half (tpl-dv)

The same line goes in the frontmatter as `test_summary_line`, and DV and QA both carry it whenever
`tests_executed` is non-zero — they are the two stages holding test-execution authority, so no other
can produce it honestly. `handoff-harness.sh --validate-frontmatter` **fails** an artifact whose
line is absent, empty, digitless, or found neither in the artifact body nor in a `.context/logs/`
capture the artifact names. It **warns** when the line does not carry `tests_executed` as a
whole-number token: a TAP plan line (`1..840`) is a whole summary and a Gradle or Xcode formatter
need not repeat the count, so blocking there would fail honest stages.

##### tests_executed is the bats plan count, not the grand total (tpl-dv)

A multi-runner suite (bats + swift + python + a benchmark harness, say) reports `tests_executed` as
the **bats plan count alone**, never the sum across runners. The corroboration rule above requires
`test_summary_line` to carry `tests_executed` as a whole-number token, and only the bats TAP plan
(`1..N`) does that reliably — a non-bats runner's own summary line rarely repeats the grand total
verbatim. Convention, not accident: a run with 1949 bats cases plus 589 non-bats cases records
`tests_executed: 1949` with `test_summary_line: "1..1949"`; the 589 are attested in the artifact
body, not folded into the frontmatter count.

#### Zero executed tests must say whether the suite compiles (tpl-dv)

`tests_executed` counts cases that actually **ran** — the number in the summary line above, never
the number a runner enumerated before exiting. Zero is legal and is not a failure; being unable to
tell zero from "never built" is.

So when `tests_executed` is `0`, `test_suite_compiles` is REQUIRED: `true`, `false`, or `unknown`
with the reason in the body. **Compilation is checkable without test-execution authority**, which
is exactly why it is asked of the stage that was denied.

##### Why not build_status (tpl-dv)

`build_status` reports the app build. A test target can fail to compile while the app builds clean,
and that combination is what stayed invisible for ten hours of one run while four stages escalated
with remedies aimed at the wrong control. `handoff-harness.sh --validate-frontmatter` fails a DV
artifact reporting `tests_executed: 0` with no `test_suite_compiles`.

#### Architecture reference contract (tpl-dv)

When AR ran, BOTH `refs.decisions` and the `architecture` object are required; both are omitted
when AR was excluded. They are not alternatives: `refs.decisions` is the anchor-read pointer
downstream stages follow, `architecture.ref` is the typed carrier the `DVHandoff` schema
validates, `architecture.applied` is the assertion DR checks. Writing one without the other is a
contract violation — the harness accepts either (precedence below) but DR rejects an absent
`architecture` object as `missing_input`.

Gate precedence, in the single order shared by the harness, the schema and the DR rule:
`refs.decisions`, then `architecture.ref`. The chosen value must match
`^architecture-[0-9]+\.md(#[a-z-]+)?$` and resolve to a file next to the artifact — warn-only in
3.42.0, blocking under `--strict`. An architecture reference with no `tasks.AR0` entry trips the
inverse guard (warn, never a failure).

##### Unreadable-state exception

An unreadable `--state` fails (exit 1) under `--strict` in 3.42.0 itself, ahead of the rest of
this warn-only rollout.

### #tpl-dr — Developer Review (technical-lead)

```yaml
---
handoff:
  stage: DR
  verdict: pass                # pass / fail
  summary: "<N files reviewed. M findings, all addressed / K blockers remain>"
  key_decisions:
    - { id: dr1, summary: "<finding or approval>", anchor: "developer-review-N.md#findings" }
  open_questions:
    - { id: sw-DR0-1, class: decision, ref: "developer-review-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    dev: development-N.md#files-changed
    findings: developer-review-N.md#findings
---
```

Prev→this label: `DV→DR`.

### #tpl-sr — Security Review (security-reviewer)

```yaml
---
handoff:
  stage: SR
  verdict: pass                # pass / fail
  summary: "<N files reviewed. M security findings>"
  key_decisions:
    - { id: sr1, summary: "<security finding>", anchor: "security-review-N.md#findings" }
  open_questions:
    - { id: sw-SR0-1, class: decision, ref: "security-review-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    dev: development-N.md#files-changed
    findings: security-review-N.md#findings
---
```

Prev→this label: `DR→SR`.

### #tpl-qa — QA (qa-engineer)

```yaml
---
handoff:
  stage: QA
  verdict: go                  # go / no-go
  summary: "<N unit tests pass, M integration checks. Coverage X%>"
  tests_executed: 840          # cases RUN; QA holds full-suite authority
  test_summary_line: "1..840"  # verbatim; REQUIRED when the count is non-zero
  files_touched:
    - tests/added/test-file.sh
  key_decisions:
    - { id: qa1, summary: "Coverage X%, target met", anchor: "testing-N.md#coverage" }
  open_questions:
    - { id: sw-QA0-1, class: decision, ref: "testing-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    dev: development-N.md#files-changed
    results: testing-N.md#results
---
```

Prev→this label: `DR→QA` (or `SR→QA` when SR runs).

#### An unverified security claim in shipped docs is a finding (tpl-qa)

A security or networking claim in payload documentation that QA did not verify is a **finding**,
recorded in `key_decisions` and reflected in the verdict — not prose to be read past. "The README
says it binds to loopback" is a claim about the artifact, not about the system.

The pattern to demand is the one a remediation on this run produced: the corrected README **carries
the `lsof` command that would falsify it**. A claim that ships its own test cannot drift from the
system it describes, and checking it costs a single command instead of a review argument.

This is not QA inventing scope. A shipped README asserting loopback binding, over a database
listening on `*:5433` with a documented default credential, passed a full developer review; only a
live probe caught it.

### #tpl-dc — Documentation (technical-writer)

```yaml
---
handoff:
  stage: DC
  verdict: ok                  # ok / blocked / escalate
  summary: "Updated N documentation files. Cross-references added."
  files_touched:
    - docs/file1.md
  open_questions:
    - { id: sw-DC0-1, class: decision, ref: "documentation-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    dev: development-N.md#files-changed
    docs: documentation-N.md#files-changed
---
```

Prev→this label: `QA→DC`.

#### Security and networking claims cite their evidence (tpl-dc)

Any security or networking claim in payload documentation names **the stage and the evidence that
verified it** — a probe, a config line, a test — or it does not ship. "Binds to loopback", "requires
auth", "no credentials at rest" are all claims of this class.

Prefer a claim that carries its own falsifier: documentation that ships the command proving it
cannot drift from the system silently. A claim with no cited evidence is DC asserting something no
stage established, and it will be believed.

#### Under fan-out, DC reads a tree that does not exist yet (tpl-dc)

In fan-out mode DC runs before the streams are merged, so a cross-stream claim — a path, a command,
an integration — describes an **assembled tree DC cannot see**. Three of four paths one payload's
README documented were absent from the tree DC was reading. The README was right; DC's method could
not have established that.

Mark every cross-stream claim `consistency-checked, not executed`, naming what was compared and why
execution was impossible. An unmarked claim reads as verified, which is the failure: DC's verdict
then carries a confidence its evidence does not support, and the next reader has no way to tell.

### #tpl-re — Release Engineering (release-engineer)

```yaml
---
handoff:
  stage: RE
  verdict: ok                  # ok / blocked
  summary: "Release artifacts prepared. Version bumped to X.Y.Z"
  files_touched:
    - plugin.json
    - MEMORY.md
  key_decisions:
    - { id: re1, summary: "Version X.Y.Z", anchor: "release-N.md#version" }
  open_questions:
    - { id: sw-RE0-1, class: decision, ref: "release-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    artifacts: release-N.md#artifacts
    version: release-N.md#version
---
```

Prev→this label: `DC→RE`.

### #tpl-fn — Finalization (project-manager)

```yaml
---
handoff:
  stage: FN
  verdict: ok                  # ok / blocked
  summary: "All artifacts aggregated. complete-summary-N.md ready for ST approval."
  files_touched:
    - .context/complete-summary-N.md
  next_stage_focus: "ST approves merge and confirms MEMORY.md version bump"
  open_questions:
    - { id: sw-FN0-1, class: decision, ref: "complete-summary-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    summary: .context/complete-summary-N.md
    ledger: .context/state.json
---
```

Prev→this label: `RE→FN` (or `DC→FN` when RE is absent).

### #tpl-st — Stakeholder (stakeholder)

```yaml
---
handoff:
  stage: ST
  verdict: approve             # approve / reject
  summary: "Approved. <N follow-ups filed or 'No follow-ups'>."
  key_decisions:
    - { id: st1, summary: "Approve merge", anchor: "complete-summary-N.md#decision" }
  open_questions:
    - { id: sw-ST0-1, class: decision, ref: "retrospective-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    summary: .context/complete-summary-N.md
---
```

Prev→this label: `FN→ST`.

### #tpl-ir — Incident Response (incident-responder)

```yaml
---
handoff:
  stage: IR
  verdict: ok                  # ok / escalate
  summary: "Root cause: <X>. Fix plan: <Y>. Blast radius: <Z>"
  key_decisions:
    - { id: ir1, summary: "Root cause identified", anchor: "incident-N.md#root-cause" }
  next_stage_focus: "DV implements fix; QA runs regression"
  open_questions:
    - { id: sw-IR0-1, class: decision, ref: "incident-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    root_cause: incident-N.md#root-cause
    fix_plan: incident-N.md#fix-plan
---
```

Prev→this label: `USER→IR`.

### #tpl-et — Ethics Review (ethics-reviewer)

```yaml
---
handoff:
  stage: ET
  verdict: pass                # pass / fail (block/conditional → fail with key_decisions)
  summary: "Ethics review complete. Score: <X>/100. Status: <APPROVED|CONDITIONS|BLOCKED>."
  key_decisions:
    - { id: et1, summary: "Compliance verdict", anchor: "ethics-review-N.md#findings" }
  next_stage_focus: "Invoking stage resumes after ET verdict"
  open_questions:
    - { id: sw-ET0-1, class: decision, ref: "ethics-review-N.md#elicitation-sweep", blocks_next_stage: false }
  refs:
    review: .context/ethics-review-N.md
    ledger: .context/state.json
---
```

Prev→this label: `<invoker>→ET` (whichever stage triggered the ethics gate).

## Completion Verification — REQUIRED before return

Single source of truth for what every stage agent verifies before `status: completed`. Each agent's `## Handoff Protocol` MUST reference this checklist, not restate it. **Agents MUST repeat the numbered step outcomes verbatim in their return summary.** Execute in order:

### Steps 1–3

1. **Artifact frontmatter**: your artifact (`.context/<artifact>-N.md`) MUST start with `---\nhandoff:` conforming to the per-stage template at `stage-contracts.md#tpl-<CODE>`.
2. **Required fields**: frontmatter MUST include all required fields for your stage `<CODE>` per `handoff-protocol.md#frontmatter-schema` § Per-stage required-field matrix.
3. **Artifact filename**: MUST be the canonical name from `handoff-protocol.md#stage-artifact-map`. Non-canonical names (e.g. `arch-0.md` for `architecture-0.md`) break the SubagentStop safety net.

### Steps 4–5

4. **Patch state.json**: patch `tasks.<ID>` (`status`, `artifact`, `verdict`, `retry_count`) and `handoffs["<PREV>→<TASK_ID>"]` (≤300-char summary ending with a `ref:` pointer). The **source** side is a bare stage code — it answers which stage this followed, and each template's footer above names it (e.g. `PL→AR`, `USER→IR`). The **destination** side is the writing task's own id, so a split stage writes one edge per task (`TL→DV0`, `TL→DV1`) instead of four writers colliding on one key.
5. **Atomic write**: run `skills/worktask/scripts/state-patch.sh --stage <CODE> --prev <PREV>`, which performs the canonical locked read → merge → temp → fsync → rename of `handoff-protocol.md#atomic-write`. NEVER write `.context/state.json` directly. If the script cannot run at all, do not skip silently — use the Edit-direct fallback at `handoff-protocol.md#layer-1-fallback`.

### Post-return repair (F2/F3)

The orchestrator verifies `tasks.<ID>.status == "completed"` after the task returns. If still `in_progress`, the SubagentStop hook (`state-merge.sh`) repairs the ledger from the artifact's frontmatter (F2). If the artifact lacks frontmatter, the orchestrator derives a minimal handoff record from the return text (F3) — but downstream cache hits collapse, so valid frontmatter is mandatory in steady state.

## Cross References

- `skills/worktask/references/handoff-protocol.md` — canonical state.json + frontmatter + anchor specs
- `skills/shared/stage-codes.md` — code/agent/model lookup
- `skills/shared/state-ledger.md` — metadata schema, `error_file` derivation, `context_refs`/`state_file`
- `skills/agent-coordination/SKILL.md` § Error Handling — retry/escalate matrix
- `skills/logging-conventions/SKILL.md` — raw capture paths (`.context/logs/`)
- `skills/task-folder-organization/SKILL.md` — artifact naming and retention
- `skills/self-improvement/SKILL.md` — optional `.context/learnings.md` produced at ST
