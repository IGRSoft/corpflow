# request-plan — 0.4.0, batch 6 and the first same-version noise band

Two captures at spec 0.4.0 over a corpus grown to 259 cases, differing only in output
directory. **Both completed: 259/259 records each, $416.75 imputed for the pair, zero errors.**

The useful result is not the pass rate. It is the **17.1% per-case flip rate between two
byte-identical runs**, which reproduces the 16% the 0.3.0 A/B saw and makes any per-case claim
from a single capture unreliable. The aggregate is steady at 78.7% / 79.5%; the individual
verdicts underneath it are not.

A human labelling pass followed: 60 cases against capture #1, 41 pass / 18 fail / 1 defer.
**Corrected rate 85%, 95% CI [81%, 91%]; TPR 92%, TNR 100% on 18 human negatives.** The held-out
tranche yielded **4 genuine negatives against batch 5's one** — the `buried` weighting delivered.
Every TNR here is quoted with its denominator, and the held-out row rests on **four** negatives, which
is why its interval reaches 100%.

## Pre-capture gate — recorded before any spend

Per `.context/architecture-0.md § spend-boundary` and `.context/team-lead-0.md § DV2 brief`.

| clause | check | result |
|---|---|---|
| 1 — floor pinned, atomic-pin step 5 | `jq -e '.held_out_from == 213'` + full step-5 chain | **`true`, `pin ok` (rc 0)** |
| 2 — batch-6 size ceiling ≤ 58 | `jq -r '[.splits\|keys[]\|tonumber]\|map(select(.>212))\|length'` | **58** |
| 3 — projected pair cost < $500 | 259 cases × $0.82/case × 2 sweeps | **$424.76** |
| 4 — explicit `--budget` per invocation | `--budget 220` per sweep (ceiling $440 pair) | prepared, not invoked |

$0.82/case is the rate the 0.3.0 capture actually recorded ($164.08 / 201). The pair
projects to $424.76, leaving ~$75 against the approved $500. The case-count ceiling binds
first here: the cost ceiling would permit up to ~103 new cases, so at 58 the two
constraints do not disagree and no re-size was required (sw-TL0-1 did not fire).

**One deviation from clause 1 as written.** AR words it "the pin commit exists". DV2 is
forbidden to commit — FN owns every git write — so the pin exists as a complete, verified
**working tree**, and step 5 was run against the files on disk exactly as specified. The
grouping FN must honour is in § The pin is one commit.

### Budget guard raised to $260 — appended 2026-09-06, NOT a retroactive edit

**The table above is the record of what was checked before any spend and is unchanged.** `--budget 220`
is the figure that gate was passed against, and it stays written that way.

Partway through capture #1 the observed per-case imputed cost drifted above the $0.82 the gate
projected, narrowing the headroom under the $220 guard. DV2 did **not** move the ceiling: a mid-run
adjustment made to avoid an inconvenient exit code would erase exactly what this section exists to
record. The question was escalated instead, and **the user raised the per-sweep guard to $260.**

How it is applied: capture #1 was **not** restarted — it was already ~199 records in and healthy, and
interrupting a run to change a ceiling it might never reach is pure loss. If #1 exits 4 on a breach it
is re-run with `--budget 260`, which resumes and dispatches only the remaining cases; both the breach
and the resume are reported rather than presented as one uninterrupted run. Capture #2 runs with
`--budget 260` from the start.

**$260 x 2 = $520 imputed, which is above the $500 originally approved.** That is stated here as the
overrun it is, not dressed as "within budget". The user was shown the figure explicitly and accepted
it on the stated basis: `total_cost_usd` is a list-price **imputation** rather than money on this host
(no `ANTHROPIC_API_KEY`; `authMethod: "claude.ai"`, `subscriptionType: "max"`), so the resource
actually drawn down is the operator's Max subscription allowance — which the $500 never covered in the
first place. The $500 figure and the thing being spent were never the same quantity; raising the guard
does not change what is consumed, only how far the run is allowed to proceed before halting.


## The 26-case `adjacent` analysis

This overturns the reading in `request-plan-0.3.0.md § Batch 5 by cell`, which calls
`adjacent` at 5/10 = 50% "the standout" against a corpus 81%. That is a **harness** count.
The human labels committed alongside it do not support it.

### Batch 5's `adjacent` failures, per case

Of batch 5's ten `adjacent` cases (186-195), the harness passed 5 and failed 5. Three of
the five were drawn into the label sample:

| case | split | harness failed on | human | what it is |
|---|---|---|---|---|
| 187 | test | `asked-instead-of-planning` | **defer** | the stream-json capture defect; the plan was never stored |
| 191 | dev | 6 template assertions | **pass** | grader too strict |
| 193 | dev | `finds-the-real-surface` | **pass** | grader too strict |

**Zero genuine negatives.** Two are false fails — consistent with § Every disagreement is a
false fail, which establishes that this capture's grader errs strict and never lenient —
and one is a known capture defect. The other two of the five (among 188, 190, 195) went
unlabelled and are undecided.

The one genuine `adjacent` negative in the whole capture is **case 33**, and it is
**pre-existing**, not batch 5.

### The confound, and it is checkable

| pool | batch 5's 10 | pre-existing 16 |
|---|--:|--:|
| capability-registry.sh **excluded** (`tests/`, `skills/*/references/`, `skills/shared/*.md`) | **10** | 3 |
| capability-registry.sh **enumerated** (`SKILL.md`, `commands/`, `agents/`, `hooks/`, `skills/*/scripts/`) | **0** | 13 |

An `adjacent` case asks whether the plan **names** the near-miss surface. Ground it on a
surface the plan cannot look up and the case stops testing adjacency and starts testing
search — it is a `buried` case wearing the wrong label, and `finds-the-real-surface` then
fails for a discovery reason. Batch 5 applied one surface pool uniformly to both cells. For
`buried` that is on-design. For `adjacent` it collapses the cell.

So neither the 50% nor the 73% corpus figure is evidence about `adjacent`, and the 0.3.0
open question — "case difficulty or a real regression" — was **unanswerable as posed**.
Batch 6 answers it by removing the confound rather than re-running the bet.

### Where the negatives actually come from

All 13 human negatives in the 0.3.0 sample, by cell. The sample is enriched toward harness
failures, so these are **not** corpus rates; the composition is what the weighting reads.

| grounding | human negatives | of labelled | batch-5 cases in cell | batch-5 genuine yield |
|---|--:|--:|--:|--:|
| buried | **8** | 25 | 8 | **2 (199, 203) = 25%** |
| absent | 4 | 16 | 18 | 1 (168, `dev`) = 5.6% |
| adjacent | 1 | 9 | 10 | **0** |
| obvious | 0 | 10 | 0 | — |

`buried` is the engine, measured rather than nominated, and case **199** — the only genuine
held-out negative the tranche produced — is `buried`. `finds-the-real-surface` carries 7 of
the 13, which is the assertion `buried` and `adjacent` both exercise and `obvious` and
`absent` do not.

By type: feature 6, incident 3, docs 2, refactor 1, bug 1, migration **0 of 6**. By route:
std 10, emerg 3 of 9 labelled (33%), secure 0 of 1. Both agree with the corpus harness
table (docs 65%, incident 69%, feature 79%; migration 100%; emerg 70%, secure 90%).

## Batch 6

**58 cases, ids 213-270**, taking the corpus from 201 to 259 (as generated then: 182 plan,
45 clarify, 32 refute; 173 / 45 / 41 after the 2026-09-07 relabel below). `eval_set_version` and `SKILL.md version:` both stay **0.4.0** (AD-2) — load-bearing,
since AC-10 needs the pair at one spec version.

| cell | n | surfaces | why |
|---|--:|---|---|
| buried | **30** | registry-**excluded** | the measured engine; 8 of 13 negatives, 25% batch-5 yield, source of the only held-out negative |
| adjacent | **18** | registry-**enumerated** | the confound repair; the configuration case 33's negative came from |
| absent | **10** | none | control on the unresolved "are the new absent cases easier" question (p ≈ 0.17) |
| obvious | **0** | — | 92% harness, 0 negatives from 10 labels; buys no measurement |
| refute | **0** | — | `disputes-the-premise` has a measured false-negative floor and every repair was rejected, so a refute failure is uninterpretable as a negative |

The 10 `absent` cases are written in the shape of the genuine negatives **36, 95, 120** —
plausible for a repo like this one, ungroundable in this one — not batch 5's generic-SaaS
template, per the 0.3.0 instruction to *"sample the existing prompts for difficulty rather
than writing fresh ones from the same template."*

Route: 11 emerg of 58 (19%) against a corpus 11%. `secure`: none.

**Held out: 23 of the 58** stratify to `test` (12 buried / 7 adjacent / 4 absent; 19 plan /
4 clarify), against batch 5's 18 with only 8 `buried` in the entire batch. At batch 5's
measured 25% `buried` yield, 12 held-out `buried` cases project ~3 genuine held-out
negatives against batch 5's 1. That arithmetic is the case for 58 over ~45; it is a
projection of yield, not of a result.

**Lints:** all 23 in `tests/python/test_skill_evals.py` pass over the grown corpus. One
caught a real defect during authoring — case 232's prompt contained a phrase that also
appears in `CHANGELOG.md`, i.e. inside the searched tree, which would have made it a
lookup. Reworded, re-run green. No existing id changed tranche and ids 1-212 are
byte-identical in `evals.json`.

## The pin is one commit

FN must land these four together. `evals/README.md` is **not** among them — it asserts
nothing about the key (AD-1) and belongs to DV1/DV3.

1. `evals/scripts/gen-request-plan-cases.py` — batch 6 authored, ids 213-270
2. `skills/request-plan/evals/evals.json` — regenerated (no `--restratify`), plus the dated
   `CORPUS GROWN, NOT SPEC (batch 6, 2026-09-05)` provenance entry
3. `evals/splits/request-plan.json` — `held_out_from: 213`, the 58 split assignments
   appended by hand, and the note's absence paragraph rewritten
4. `evals/labelling.md` — the floor prose corrected from absent to pinned

Splitting them re-opens the invariant that broke at the 4→5 transition. Nothing downstream
detects a floor left on a spent tranche.

## The captures

Three things blocked these at various points. All three are now closed, and the record of each
matters more than the fact that it cleared — two were decisions the user made with the trade-off
stated, and the third was a mechanical refusal that prevented a wasted spend.

### What was blocked, and how each cleared

**1. Resource substitution — the approval and the resource were never the same quantity.** The
approval was for $500 of *metered* spend, but this host carries no `ANTHROPIC_API_KEY`:
`has_credential()` falls through to the CLI probe, which returns `authMethod: "claude.ai"`,
`subscriptionType: "max"`. `total_cost_usd` is therefore a **list-price imputation, not money** —
a 4-token probe reported `0.2766656` with `costBasis: "list"`. The real draw is the operator's Max
subscription allowance. **Answered (user): run on the allowance**, with that substitution understood.

**2. No human labelling pass. Answered (user): finish without labels** — a decision later reversed
when the perishable window was taken up, so a 60-case pass did run against capture #1. See
§ Calibration.

**3. The capture tree is HEAD, so an uncommitted pin cannot be captured.** The first real invocation
**refused at pre-flight, exit 2, before any dispatch**: `assert_clean_tree()` requires a clean tree
because `make_capture_tree()` builds the tree under test with `git worktree add --detach HEAD` —
tracked-at-HEAD only. Batch 6 existed solely as working-tree changes, so it was absent from the tree
the model would search. **The refusal prevented a wasted spend:** the sweep would otherwise have
dispatched 259 prompts against a HEAD containing none of the three workstreams' changes and stamped
a provenance describing a tree that never existed. This is `architecture-0.md § spend-boundary` gate
clause 1 — *"the pin commit exists"* — as a mechanical precondition rather than a wording choice.
The only bypass, `--no-isolate`, is forbidden by its own contract for a quotable number and was not
used. FN then committed all nine tracked files across the three workstreams; the atomic pin landed
intact as `9280b39` with exactly its four files, and HEAD `42308a1` contains batch 6.

### Capture #1 — complete

| | |
|---|---|
| eval set | `skills/request-plan/evals/evals.json`, `eval_set_version: 0.4.0`, sha256 `c18e3226…63b62d` |
| skill | `skills/request-plan/SKILL.md`, `version: 0.4.0` |
| model | `claude-sonnet-5` |
| mode | `command`, `bypassPermissions`, isolated capture tree, `--concurrency 1` |
| `plugin_sha` | **`42308a1` x259 — one sha, no `-dirty`** |
| probe | 45 commands offered, 28 expected, 0 missing, 0 leaked, **`evals_files=0`** |
| captured | 2026-09-06 |
| cases | **259/259 records; 0 missing, 0 extra** (182 plan, 45 clarify, 32 refute at capture time) |
| cost | **$207.10 imputed**, `--budget 220`, **no breach**, exit 0, 0 errors, 0 retries |
| runtime | ~9h at `--concurrency 1` |

Capture #1 finished under the **original $220** guard. The raise to $260 was never invoked here and
applies to capture #2 only.

**Harness pass rate: 204/259 = 78.8%.**

| slice | harness |
|---|--:|
| pre-existing 1-212 | 165/201 = 82% |
| batch 6 (213-270) | 39/58 = 67% |
| batch 6 held-out (23) | 16/23 = 70% |

Batch 6 is harder than the corpus it joined, which is what it was built to be. By cell within batch
6: `buried` 18/30 = 60%, `adjacent` 15/18 = 83%, `absent` 6/10 = 60%.

### Capture #2 — complete, and identical by construction

| | |
|---|---|
| eval set | byte-identical to #1: sha256 `c18e3226…63b62d` (verified before dispatch) |
| skill | `version: 0.4.0`, unchanged |
| `plugin_sha` | **`42308a1` x259 — one sha, no `-dirty`** |
| probe | 45 offered, 28 expected, 0 missing, 0 leaked, **`evals_files=0`** |
| cases | **259/259 records; 0 missing, 0 extra** |
| cost | **$209.65 imputed**, `--budget 260`, no breach, exit 0, 0 errors |

Only the out-dir differed (AC-10 satisfied). **Harness pass rate: 205/259 = 79.2%.**

### Contamination — and one case that must be excluded

| | capture #1 | capture #2 |
|---|--:|--:|
| answer-key read (**fatal**) | **0** | **1** — case 146 |
| saw the strip via `git status` | 2 (72, 89) | 4 (72, 82, 112, 251) |
| read this capture's own commits | 0 | 0 |
| said outright it was an eval | 0 | 0 |
| **total tainted** | 2 of 259 (1%) | 5 of 259 (2%) |

`scan-contamination.py` is explicit that an answer-key read *"is not a discount — exclude those
cases"*, so **case 146 is excluded from every paired figure below**. Both sweeps are cleaner than
0.3.0's 10 of 201 (5%); #1 is the cleanest capture this corpus has had.

**Headline on the 258 paired cases, case 146 excluded:**

| | harness |
|---|--:|
| capture #1 | 203/258 = **78.7%** |
| capture #2 | 205/258 = **79.5%** |
| aggregate delta | +2 cases = +0.8 pp |

(Unexcluded, for reference: #1 204/259 = 78.8%, #2 205/259 = 79.2%.)

## The noise band — the deliverable, and it undercuts the headline

This is what the 0.3.0 findings' § Next item 4 asked for and could not fund: two captures at one
spec version, over one corpus, differing only in output directory.

| | |
|---|--:|
| paired cases | 258 (both sweeps complete; no intersection loss) |
| aggregate movement | **+2 cases, +0.8 pp** |
| pass -> fail | 21 |
| fail -> pass | 23 |
| **total per-case flips** | **44 / 258 = 17.1%** |

Per-case source: **`evals/findings/request-plan-0.4.0-verdicts.jsonl`** (both captures' verdicts, one
row per case) — see § Reproducing these numbers.

**The aggregate is stable and the per-case verdicts are not.** Two byte-identical runs agree to
within a percentage point in aggregate while disagreeing on **44 individual cases**. The 0.3.0
paired A/B measured a 16% flip rate and that figure was treated as a caution; **this pair reproduces
it at 17.1% on a larger corpus**, which promotes it from a one-off observation to a property of this
eval.

**Say plainly what that costs.** The 78.7%/79.5% headline is stable as an aggregate and **unreliable
as a per-case claim**. Any single capture's verdict on any single case is roughly a 1-in-6 coin
flip. No A/B on this corpus can resolve an effect smaller than about 44 cases, and nothing in this
run — including the batch-6 design it was built to test — should be read at per-case resolution
from one sweep.

That is also, independently, why **no delta is attributed to the 0.4.0 drifted-rule reconciliations**
(sw-AR0-1, binding). The `evals.json` entry predicted a handful of affected cases against a 16% flip
rate; this pair now measures that flip rate at 17.1% directly. The reconciliations were never
measurable by a capture pair, and this data confirms the prohibition was correct rather than
merely cautious. The `evals.json` grading entry stands unamended.

### Flip rate by cell — the noisiest cell is the one batch 6 was weighted toward

| cell | flipped | of | rate |
|---|--:|--:|--:|
| **buried** | **29** | 129 | **22%** |
| adjacent | 7 | 44 | 16% |
| obvious | 4 | 40 | 10% |
| absent | 4 | 45 | 9% |

This is a finding against the design recorded in § Batch 6. `buried` was weighted to 30 of 58 cases
because the 0.3.0 labels showed it produced 8 of 13 genuine negatives. It does produce failures —
and it is also **the least reproducible cell in the corpus**, flipping more than twice as often as
`absent` or `obvious`. "This cell yields negatives" and "this cell yields coin-flips" are not
distinguishable from harness counts alone, and this pair shows a substantial part of `buried`'s
yield is the second thing.

### The held-out tranche, settled by the labels

Capture #1 reported 7 harness failures of 23; capture #2 reported 6. **The human labels put the
genuine count at 4: cases 229, 231, 241, 262.** Against batch 5's tranche, which yielded **one**
genuine held-out negative from 18, batch 6 yielded **four from 23**. The `buried`-weighted design
delivered on the scarce resource — three of the four are `buried` (229, 231, 241), one is `absent`
(262), and `adjacent` produced **none**.

| id | cell | capture #1 | capture #2 | human | what it is |
|---|---|---|---|---|---|
| 229 | buried | fail | **pass** | **fail** | genuine — capture #2 missed it |
| 231 | buried | fail | fail | **fail** | genuine — both captures caught it |
| 241 | buried | fail | **pass** | **fail** | genuine — capture #2 missed it |
| 262 | absent | fail | fail | **fail** | genuine — both captures caught it |
| 216 | buried | fail | fail | pass | false fail, stable — grader defect |
| 267 | absent | fail | fail | pass | false fail, stable — grader defect |
| 221 | buried | pass | fail | pass | false fail, flipped — noise |
| 226 | buried | fail | pass | pass | false fail, flipped — noise |
| 269 | absent | pass | fail | pass | false fail, flipped — noise |

#### The "stable across both captures" heuristic was wrong, and worth recording as wrong

Before the labels existed this document proposed that failures reproducing in both captures — 216,
231, 262, 267 — were the likeliest genuine ones. **That heuristic was 50% accurate: 231 and 262 are
real, 216 and 267 are false fails.** Worse, it points the wrong way at both ends: **229 and 241 are
genuine negatives that only ONE capture caught**, so filtering on cross-capture stability would have
discarded half the real negatives while keeping two artifacts.

The reason is that the flip rate and the grader defect are independent failure modes. Stability
filters out *noise*; it does nothing about a *systematic* grader error, which is stable by
construction — 216 and 267 reproduce precisely because the defect that produces them is
deterministic. **Reproducibility is not a proxy for correctness, and a single capture would have
missed half the genuine held-out negatives here.** That is the sharpest practical cost of the 17.1%
flip rate measured above, and it is an argument for labels rather than for more captures.

### The `adjacent` result cuts against the design that produced it

| slice | capture #1 | capture #2 |
|---|--:|--:|
| batch 6 `adjacent` (registry-**enumerated** surfaces) | 15/18 = 83% | 16/18 = 89% |
| batch 5 `adjacent` (registry-**excluded** surfaces) | 7/10 = 70% | 6/10 = 60% |
| pre-existing `adjacent` 1-167 | 12/16 = 75% | 13/16 = 81% |
| **batch 6 held-out `adjacent` (7 cases)** | **0 failures** | **0 failures** |

Read carefully this **confirms the confound diagnosis and refutes the cell's usefulness at the same
time**, and both halves survive the pair rather than resting on one run.

Grounding `adjacent` cases on surfaces the plan can look up makes them pass, in both captures, which
is exactly what § The confound predicted: batch 5's 50% was about *discoverability*, not adjacency.
The 0.3.0 open question — *"is `adjacent` at 50% case difficulty or a real regression"* — is answered
as **neither**; it was a surface-pool artifact, and the question was unanswerable as posed.

But 18 of batch 6's 58 cases were spent establishing that, and they produced **zero held-out failures
across two captures**. `adjacent` is a clean diagnostic and **not a source of held-out negatives**,
which were the scarce resource the tranche exists to produce. That is a finding against the weighting
recorded in § Batch 6, and a batch 7 sized on this evidence should cut `adjacent` sharply.

## Calibration — AC-7 and AC-8 are met

A human labelling pass was run over the 60-case draw against **capture #1** after all
(`sw-DV2-5`): 41 pass, 18 fail, 1 defer (case 157). The corrected rates below are label-derived and
supersede the "deliberately not measured" position this document previously held.

**Full set** — n=59 graded, the defer excluded:

| | |
|---|--:|
| TPR | **92%** |
| TNR | **100%** — on **18 human negatives** |
| observed pass rate | 79% |
| **corrected** | **85%**, 95% CI **[81%, 91%]** |

Strata and weights, read from the hand-written draw rather than re-derived:
`dev/fail` 17 of 29 (1 deferred) weight 1.71 | `dev/pass` 19 of 81 weight 4.26 |
`test/held-out` 23 of 23 weight 1.00.

**Held-out tranche** — 23 of 23, taken whole:

| | |
|---|--:|
| TPR | **84%** |
| TNR | **100%** — on **4 human negatives** |
| observed | 70% |
| **corrected** | **83%**, 95% CI **[70%, 100%]** |

**Read the held-out row with care, and read its denominator first.** TNR 100% rests on **four**
human negatives, and the confidence interval touching 100% is what n=4 looks like — it is not a
strong claim about the grader, it is a small sample stated honestly. The full-set TNR 100% rests on
18, which is firmer but still means only that *no human failure in this draw was passed by the
grader*. The error direction is unchanged from 0.3.0: every human/harness disagreement runs
grader-too-strict, never too-lenient.

### Reproducing these figures from git alone (AC-8)

`responses-0.4.0-a/` is gitignored and both prior capture sets have already vanished from this host.
The `--p-obs` values below supply the observed rate the responses would otherwise have to, so the
corrected figures survive their deletion:

```sh
python3 evals/scripts/label-align.py \
  --labels evals/labels/request-plan-0.4.0-human.jsonl \
  --sample evals/labels/request-plan-0.4.0-sample.json --p-obs 0.78764

python3 evals/scripts/label-align.py \
  --labels evals/labels/request-plan-0.4.0-human.jsonl \
  --sample evals/labels/request-plan-0.4.0-sample.json \
  --stratum test/held-out --p-obs 0.69565
```

**On the `--p-obs` values, precisely.** `0.69565` is capture #1's held-out rate, 16/23, exactly as
described. `0.78764` is **204/259 — capture #1's rate over all 259 cases, NOT the 258-case excluded
rate**, which is 203/258 = 0.78682. An earlier draft of this document described it as the latter; that
description was wrong and the value above is the one actually passed.

The published figures are unaffected, and the reason is worth stating rather than asserting: **case
146 is `train`**, so it is outside the 60-case labelling draw entirely and outside all three strata.
The contamination exclusion never reached the calibration frame, and the two rates differ by 0.0008.
Re-running with `--p-obs 0.78682` returns the same **85% [81, 91]**. Either value reproduces the
published result; `0.78764` is recorded because it is what was run.

### What the labels settle, and what the 17.1% flip rate still bounds

These corrected rates are computed from **capture #1's verdicts**. The pair disagrees on 44 of 258
cases, so:

- **Settled:** the grader's error *direction* (strict, never lenient, on 18 human negatives); the
  count of genuine held-out negatives in this tranche (**4**); that batch 6 beat batch 5 on the
  scarce resource (4 from 23 against 1 from 18); that the template cascade is a real grader defect.
- **Not settled:** the corrected rate as a stable property of the skill. 85% [81–91] describes
  capture #1. Capture #2 scored one case higher in aggregate but differs on 44 cases individually,
  and re-labelling against #2 would move the corrected figure by an unknown amount. **A corrected
  rate from one capture is not a per-case-reliable measurement of the skill**, and the CI above
  reflects sampling error only — it does not include run-to-run variance.

**This changes nothing about sw-AR0-1.** No delta is attributed to the 0.4.0 drifted-rule
reconciliations. The labels measure the grader against a human, not one spec version against another,
and the `evals.json` grading entry stands unamended.

### The grader was repaired after this calibration — 2026-09-07

The labels measured the harness as over-strict and never lenient — 18 human failures, all caught,
**zero false negatives** — so every repair they justify subtracts failures at no cost in recall. Six
of the 41 human passes were scored as failures, and they reduce to two defects, both repaired
against this same corpus and these same captures:

- **The template cascade** (§ Next item 1). Nine cases carried `expected_outcome: plan` while being
  refutations of a false premise: 78, 79, 104, 191, 216, 220, 225, 226, 252. They are relabelled in
  the generator's refutation table, not in `evals.json` — the case array is regenerated wholesale, so
  a hand-edit there would have been reverted by the next run. The corpus is now 173 plan / 45 clarify
  / 41 refute, and the held-out tranche 17 plan / 2 refute / 4 clarify against the zero refute cases
  it was designed with. None of its four genuine negatives (229, 231, 241, 262) is touched, so the
  tranche's measurement value survives; the composition claim above does not.
- **The outcome classifier**, which let a question mark below the section quorum decide the verdict.
  The repair is **one-directional**: a `plan` may become a `clarify`, never the reverse. Over both
  captures 36 responses change class, **0 pass→fail**. A two-section response carrying a rhetorical
  `?` is still a clarification — this is not "punctuation no longer decides".

**Every harness number above this heading is the pre-repair grader, and stays that way.** The
corrected 85% CI [81%, 91%] describes capture #1 as graded then, and the `eval_set_sha256` recorded
in `request-plan-0.4.0-verdicts.jsonl` is deliberately **not** updated: it names the case set those
per-case verdicts were graded against, and the rows are meaningless repointed at a different one. No
corrected rate is republished either — post-repair the harness disagrees with **none** of the 59
graded labels, so the correction collapses to the corpus observed rate
(212/259 = 82%) and is in-sample: a consistency check, never a headline.

## The `test` split is not an id range — a trap that produced a wrong number

Recorded as a worked instance because the general rule is already written in `evals/labelling.md`
and it still caught a reader of this pipeline.

Counting held-out human negatives by **`case_id >= 213`** gives **10**. The correct count, resolved
through the splits manifest, is **4**:

```
WRONG  case_id >= 213                -> 10: [213, 215, 218, 229, 230, 231, 241, 250, 262, 263]
RIGHT  splits[id] == 'test' and >=213 ->  4: [229, 231, 241, 262]
wrongly swept in: 213, 215, 218, 230, 250, 263 — every one of them `dev`
```

The id floor is not the tranche. Batch 6 spans ids 213-270 and stratifies to **23 `test`, 24 `dev`,
11 `train`** — so 35 of the 58 new cases sit inside the range while belonging to no held-out set.
`held_out_from: 213` is a **floor for the tranche's members**, not a definition of membership; the
manifest is the only authority on which side of the line a case falls.

Resolve membership through `splits[id] == 'test'`, or let `label-align.py --stratum test/held-out`
do it. Never an id comparison. The failure is silent: 10 negatives against the same 23-case
denominator would have published a held-out TNR over a population that does not exist, and nothing
downstream would have flagged it.

## The floor's lifecycle — pinned for the captures, deleted by the labelling pass

**`held_out_from` is absent from `evals/splits/request-plan.json` as of 2026-09-07, and that is the
correct end state for this run.** Read the sequence before reading the absence:

| when | state | why |
|---|---|---|
| 2026-09-05, with the batch-6 append | **pinned to 213** | the tranche was written after the frozen manifest and pinned before any capture read it |
| 2026-09-06, both captures | **pinned to 213** | AC-4 and AC-6 were verified against it; the pre-capture gate recorded `.held_out_from == 213` as `true` before a dollar was spent |
| 2026-09-07, the labelling pass | **spent** | the draw took batch 6's `test` cases **whole**, 23 of 23 (`test/held-out`, weight 1.00) |
| 2026-09-07, this edit | **deleted** | `evals/labelling.md:179`: *"Pin it in the edit that appends a batch and delete it in the pass that spends one"* |

**This is the documented lifecycle, not a retraction.** Batch 6 *was* genuinely held out — pinned
before any capture read it, and the two 0.4.0 captures ran against that pin. What spent it was the
labelling pass that produced § Calibration's numbers, and the rule is that the pass which spends a
tranche is the pass which deletes the floor. Nothing above is invalidated: **AC-6's evidence is the pin
at capture time**, which the gate record preserves, and the 4 genuine held-out negatives were drawn
from a tranche that was unread when the captures ran.

A reader arriving later must not conclude from the absent key that batch 6 was never held out. It was.
It is simply spent now, like batches 4 and 5 before it, and ids 213-270 may never be quoted as held out
again.

**One claim in the rule is now falsified, and it is worth recording.** `evals/labelling.md` says a
floor left on a spent tranche is something *"nothing downstream can detect"*, and
`architecture-0.md § atomic-pin` repeats it. That was true when written and is **no longer true**:
`tests/python/test_eval_capture.py::test_the_manifest_never_vouches_for_a_tranche_already_read`
detects exactly this, and it is what caught the stale floor here — the pin was left on a spent tranche
for the length of the labelling pass and the suite failed until this edit. The detector exists; the
prose that says it does not should be corrected wherever it appears.

With the key gone both consumers refuse rather than guess, which is the point of deleting it:

```
sample-for-labelling.py, key absent     -> exit 64  ("pins no held_out_from … not a spent one")
sample-for-labelling.py --held-out-from -> exit 0   (explicit operator override still available)
```

`label-align.py` is unaffected and the AC-8 commands above still reproduce: they pass `--sample`,
which carries the strata, and never read the manifest floor.

## Cost — outcome against ceiling

| | |
|---|--:|
| capture #1 | **$207.10** (`--budget 220`, never breached) |
| capture #2 | **$209.65** (`--budget 260`, never breached) |
| **pair total** | **$416.75 imputed** |

**The pair came in under $440** — what the original $220 x 2 would have allowed — **and under the
$500 originally approved. The $260 raise was authorized but never invoked on either sweep.** Had it
been used to its ceiling the pair would have allowed $520, which *would* have exceeded the $500; the
raised ceiling exceeds the approval, the actual spend did not. Both statements belong here and the
second does not cancel the first.

The more important qualification is unchanged: **$416.75 is a list-price imputation, not money.**
This host has no `ANTHROPIC_API_KEY` and the run drew on the operator's Max subscription allowance,
which the $500 approval never described. The dollar figures measure token volume at list prices;
they do not measure what was actually consumed.

## Reproducing these numbers

Responses are gitignored and both prior capture sets have already vanished from this host, so what
survives in git is this document, the grades, and the eval set.

```sh
python3 evals/scripts/eval-grade.py --eval-set skills/request-plan/evals/evals.json \
  --responses skills/request-plan/evals/responses-0.4.0-a     # 204/259
python3 evals/scripts/eval-grade.py --eval-set skills/request-plan/evals/evals.json \
  --responses skills/request-plan/evals/responses-0.4.0-b     # 205/259
python3 evals/scripts/scan-contamination.py --eval-set skills/request-plan/evals/evals.json \
  --responses skills/request-plan/evals/responses-0.4.0-b     # case 146: answer-key read
```

**The flip rate's source of truth is `evals/findings/request-plan-0.4.0-verdicts.jsonl`** — one row
per case carrying both captures' verdicts, their failed assertions, the split, the dimensions and the
human label where one exists. It exists because the 17.1% figure was the single headline number that
could *not* be re-derived from git: `responses-0.4.0-{a,b}/` are gitignored and `.context/logs/` is
git-excluded (`.git/info/exclude:1`), so the flip count rested on logs no reader of this repository
could open. Committing the evidence is the fix; softening the claim was not.

Recompute the flip count, the per-cell table, the two pass rates and the held-out negatives from that
file alone:

```sh
python3 - <<'PY'
import json, collections
rows=[json.loads(l) for l in open('evals/findings/request-plan-0.4.0-verdicts.jsonl') if l.strip()]
inc=[r for r in rows[1:] if not r['excluded']]                      # 258; drops case 146
fl=[r for r in inc if r['a_status'] != r['b_status']]               # 44 -> 17.1%
print(len(inc), len(fl), f"{100*len(fl)/len(inc):.1f}%")
den=collections.Counter(r['grounding'] for r in inc)
num=collections.Counter(r['grounding'] for r in fl)
for g in sorted(den): print(g, num[g], den[g], f"{100*num[g]/den[g]:.0f}%")
PY
```

The `.context/logs/test-developer-*` transcripts remain as the working record, but nothing published
here depends on them any more.

The two `--p-obs` alignment invocations that reproduce the corrected rates are in
§ Calibration — Reproducing these figures from git alone. Both run with no response directory present,
which is what AC-8 asks for.

## What this establishes, and what it does not

**Establishes.** Batch 6 exists, is pinned at `held_out_from: 213`, and 23 of its cases are genuinely
held out. The shipping spec 0.4.0 now has a **calibrated** rate — **85% [81-91]**, TPR 92%, TNR 100%
on 18 human negatives — where it previously had none. **This corpus has a measured same-version noise
band for the first time: 17.1% per-case flips, reproducing 0.3.0's 16%.** The held-out tranche yielded
**4 genuine negatives against batch 5's 1**, three of them `buried`, so the weighting chosen from the
0.3.0 labels did what two prior tranches failed to do. Capture hygiene was the best recorded: one sha,
no `-dirty`, `evals_files=0`, 1% taint in #1 against 0.3.0's 5%. The batch-5 `adjacent` reading is
overturned on evidence. **The six-assertion template cascade is a confirmed grader defect** — 216 and
226 join 0.3.0's 191 as human passes scored as failures.

**Does not establish.** That 85% is a stable property of the skill: it is capture #1's rate, the pair
disagrees on 44 of 258 cases, and the CI covers sampling error only, not run-to-run variance. Anything
about the 0.4.0 reconciliations — by binding condition, and now also because the measured noise floor
exceeds their predicted effect. That `buried`'s higher yield reflects difficulty rather than partly
irreproducibility: it is the noisiest cell at 22% flip and it also produced 3 of the 4 genuine
negatives, and this run cannot separate those. Any per-case claim from a single capture.

**Open.** Whether the template cascade defect is worth repairing, and at what cost — see § Next.
How much of `buried`'s 22% flip rate is prompt ambiguity versus model variance. Whether the corrected
rate moves if the same 60 cases are relabelled against capture #2. Whether a batch 7 should keep
`adjacent` at all: it produced 0 genuine negatives from 7 held-out cases here.

## Next

1. **The six-assertion template cascade was a real grader defect with three independent
   confirmations** — case 191 at 0.3.0, cases 216 and 226 here, all human passes scored as failures on
   the same signature. It was the single largest source of false failures measured in this corpus, and
   it inflates every harness number quoted from a capture in this document. **It has since been
   repaired** — 2026-09-07, § The grader was repaired after this calibration. The nine mislabelled
   cases are refutations in the generator's table, so the plan template is no longer run against them.
2. **Do not touch `disputes-the-premise`.** Unchanged from 0.3.0: its false-negative floor was measured
   and every repair was rejected. The cascade above is a *different* defect and the two must not be
   conflated in whatever fixes the first.
3. **Labels beat captures for this corpus.** Two captures cost ~9h each and $416.75 imputed, and the
   second changed the aggregate by one case while disagreeing on 44. A 60-case labelling pass settled
   the grader's error direction, the genuine held-out count, and a defect with three confirmations.
   The next increment should buy labels before it buys another sweep.
4. **A batch 7, if sized, should cut `adjacent`** (0 genuine negatives from 7 held-out) and keep
   `buried` despite its noise (3 of 4 genuine negatives) — while accepting that `buried`'s yield is
   partly irreproducible and that stability is not a filter for genuineness.

