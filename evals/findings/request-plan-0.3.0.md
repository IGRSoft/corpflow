# request-plan — 0.3.0 capture

The first per-case-paired A/B this corpus has had. It measures the three 0.3.0 rule edits
against the 0.2.0 responses on a fixed grading surface, and it comes back **null**.

## Provenance

| | |
|---|---|
| eval set | `skills/request-plan/evals/evals.json`, `eval_set_version: 0.3.0` |
| skill | `skills/request-plan/SKILL.md`, `version: 0.3.0` |
| model | `claude-sonnet-5` |
| mode | `command`, `bypassPermissions`, isolated capture tree |
| `plugin_sha` | `0e1dcfc` ×201 — one sha, **no `-dirty`** |
| probe | 45 commands offered, 28 expected, 0 missing, `evals_files=0` |
| captured | 2026-08-27 |
| cases | 201 (134 plan / 35 clarify / 32 refute); **0 human-labelled so far** |
| cost | **$164.08**, $0.82/case, 0 retries, 0 rate-limit failures |

Provenance is tighter than 0.2.0's, which smeared across `86f5aef ×109, fb8020d ×35,
6ef343a ×12` because commits landed between resumes. This run completed in one process, so
`provenance` — computed once before the sweep — describes every case in it.

## Headline

**Harness 162/201 = 81%.** No calibration yet: the 60-case labelling sample is cut
(`evals/review/request-plan-0.3.0.html`) but unlabelled, so **no TPR, TNR or corrected rate
exists for this capture**. A raw harness rate is uncalibrated and means only what it
literally counts.

## The paired A/B is null

Ids 1–167 carry unchanged `prompt_digest`s, so the 0.2.0 responses re-grade against this
`evals.json` without repaying. That re-grade reproduces the 0.2.0 capture exactly — 127/156,
and every dimension figure matches to the rounding — which establishes the baseline is
sound before anything is read into the delta.

| | 0.2.0 | 0.3.0 | Δ |
|---|--:|--:|--:|
| paired (156 cases) | 127 (81.4%) | 128 (82.1%) | **+1** |

**25 of 156 paired cases (16%) flipped**: 13 fail→pass, 12 pass→fail. Net +1.

That is the whole result. A sign test on 13-vs-12 is as close to the null as the data can
get. The three 0.3.0 edits are **not detectable above run-to-run variance**, and the honest
reading is not "the edits did nothing" but "one paired capture cannot see an effect this
small against a 16% flip rate."

### Why the paired design did not deliver what was expected of it

Pairing controls for **case identity**. It does not control for **model stochasticity**, and
stochasticity is the dominant term here: re-running the same corpus against the same spec
would flip cases too, and nothing in this run separates that from the edits. The plan's
premise — that pairing would make the three edits measurable — was wrong, and it was wrong
for a reason worth writing down rather than repeating.

Separating them needs repeated sampling at one version (n captures of the same spec to
size the noise band), not a second single capture of a different one. At $164 a sweep that
is a real cost, and it should be decided deliberately rather than assumed.

### What the flips were made of

| assertion | repaired at 0.3.0 | newly failing at 0.3.0 | net |
|---|--:|--:|--:|
| `routes-to-standard-tier` | 5 | 2 | **+3** |
| `finds-the-real-surface` | 4 | 7 | **−3** |
| `template-sections-present` | 3 | 2 | +1 |
| `disputes-the-premise` | 1 | 2 | −1 |
| `should-have-asked-not-planned` | 1 | 0 | +1 |
| `routes-to-emergency-tier` | 1 | 1 | 0 |

The two edits with a named target both move the right way and both are inside the noise:
routing nets +3 (edit 1, the tier surface that now reads the request), and the single
`absent`-grounding repair is edit 2 (the § 1 branch reorder). Neither is a measurement.
`finds-the-real-surface` nets −3 on a mechanism **no 0.3.0 edit touches**, which is the
clearest available evidence that this column is noise rather than signal.

## `disputes-the-premise` has a measured false-negative mode

**7 of the 32 refute cases fail on `disputes-the-premise` alone** — 18% of all 39 harness
failures in this capture. Every one of the seven contains an `already <verb>` construction
whose verb is missing from the assertion's enumerated list:

> `converts`, `anticipated`, `records`, `handles`, `runs`, `uses`, `named`, `scoped`,
> `stops`, `asserts`

### The cases

Case 212 is the unambiguous one. Its response opens by stating the calculator does convert
hours to a monetary figure, cites the defining function by file and line, runs the script's
self-test to confirm, and stops without rendering a template. That is the reference shape
for a refutation, and it was scored a failure. Cases 210 and 211 refute a stale headline and
then plan the live remainder behind it, which SKILL.md § 4 has defined as the *best* answer
since 0.1.0; both were scored failures on the same regex. Cases 17 and 125 look like the
same shape. Case 22 is a genuine failure on the 0.2.0 human labels (it refuted and then
rendered the full build plan anyway) and case 59 is unclear from its opening — both need a
label, not a reading.

### Why it keeps recurring

**The design is the defect, not the coverage.** "Already" takes an open verb class; an
enumerated list cannot close it. This is the fourth time the list has been found short — the
0.0.1 capture added `fixed`/`closed` after two misses, the 0.2.0 capture added two whole
patterns after two more — and each widening was a response to the previous capture's misses.
The pattern of repair is itself the evidence that enumeration is the wrong mechanism.

### Not changed here

**Not changed here, deliberately.** Widening the regex now would (a) fit the grader to the
cases that exposed it, which `evals/README.md` forbids and which is exactly how the LLM
judge was talked into a 0% TNR twice, and (b) invalidate the paired comparison above by
changing the grading surface mid-analysis. The 60 labels resolve which of the seven are
genuine misses; the fix belongs after that, as a spec change with a version move.

Note the direction of the bias: this mode **understates** the pass rate in both captures,
so it does not distort the paired delta. It does inflate the failure count in each — the
0.2.0 arm carries 3 of these, the 0.3.0 arm 7.

## Contamination: 10 of 201 (5%), zero answer-key reads

| channel | n | what it is |
|---|--:|---|
| answer-key | **0** | read the case's own verdict — fatal |
| strip | 6 | saw the deleted eval files in `git status` |
| harness-log | 6 | read this capture's own commits in `git log` |
| self-aware | 0 | said outright that this interaction was an eval |

The fatal channel is clean, as at 0.2.0. The rate is 5% against 0.2.0's 4% on the same two
non-fatal channels; both are self-inflicted by capturing from a repo whose recent history is
about the capture.

### A caution on the flip analysis

4 of the 13 cases tainted in either capture flipped, against 16% of all paired cases. On
n=13 that is not a finding — but it is the right direction for a contaminated case to
behave, and it is one more reason to read the +1 delta as churn rather than effect. A
capture whose `git log` does not describe the eval corpus would remove the channel entirely.

## The held-out tranche contains failures again

This was the point of batch 5, and it worked.

| | batch 4 (spent) | batch 5 (this capture) |
|---|---|---|
| n | 18 | 18 |
| outcomes | 15 plan / 3 refute / **0 clarify** | 7 clarify / 7 plan / 4 refute |
| grounding | 17 buried / 1 obvious | 7 absent / 5 buried / 4 adjacent / 2 obvious |
| harness | 18/18 = **100%** | 15/18 = 83% |
| harness failures | **0** | **3**, on 3 distinct mechanisms |

The three: case 187 asked where a plan was owed, 199 missed the real surface, 212 is the
`disputes-the-premise` false negative above. Held-out TNR is measurable for the first time
once these are labelled — which was the entire objective, and it is met.

### The stated engine did not fire

The design nominated the `absent`→`clarify` cell as the negative generator, on the 0.2.0
evidence that it was the weakest column (harness 71%, human 2/6). **All 7 held-out `clarify`
cases passed.** The negatives came from `adjacent`, `buried` and `refute` instead.

Across all 18 new `absent` cases the harness scored 17/18 (94%) against 13/17 (76%) on the
17 pre-existing ones in the same capture. Fisher's exact on that split is p ≈ 0.17 — not
significant, but the direction says the `absent` cases written for batch 5 are plausibly
**easier** than the ones already in the corpus, and that possibility should not be quietly
absorbed. Anyone re-cutting this cell should sample the existing prompts for difficulty
rather than writing fresh ones from the same template.

The tranche is non-degenerate regardless, so the objective holds. It was met by a mechanism
the plan did not predict, which is worth more than the prediction.

## Batch 5 by cell

**34/45 = 76%**, against 81% on the pre-existing corpus in the same run — the new cases are
harder overall, as intended.

| cell | n | harness |
|---|--:|--:|
| absent → clarify | 18 | 17 (94%) |
| buried → plan | 13 | 10 (77%) |
| adjacent → plan | 10 | 5 (**50%**) |
| refute | 9 | 6 (67%) |
| obvious (refute) | 4 | 2 (50%) |

`adjacent` at 5/10 is the standout. Four of the five failures are `finds-the-real-surface`
against the near-miss surface the case names — the cell where the plan must reach a file
that *almost* covers the request. Corpus `adjacent` sat at 81% before; these ten pull it to
73%. Either the batch-5 `adjacent` cases are harder than the corpus average, or the cell was
under-measured at 16 cases. The labels will say which.

## By dimension, full 201

| grounding | n | harness | | type | n | harness | | route | n | harness |
|---|--:|--:|---|---|--:|--:|---|---|--:|--:|
| obvious | 40 | 92% | | migration | 15 | 100% | | secure | 10 | 90% |
| absent | 35 | 86% | | refactor | 20 | 90% | | std | 168 | 82% |
| buried | 100 | 76% | | bug | 55 | 85% | | emerg | 23 | 70% |
| adjacent | 26 | 73% | | feature | 62 | 79% | | | | |
| | | | | incident | 26 | 69% | | | | |
| | | | | docs | 23 | 65% | | | | |

`docs` fell 85% → 65% on the paired ids (−4 cases) and `migration` rose to 100%. Both sit on
denominators of 20 and 15 and both are inside the flip band; neither is a finding.

## What this establishes, and what it does not

### Establishes

The 0.2.0 responses are preserved and re-grade identically, so a paired
baseline exists and is durable. The held-out tranche contains failures on three mechanisms
and can measure TNR once labelled. `disputes-the-premise` has a systematic, reproducible
false-negative mode with a named cause. The capture surface was clean: one sha, no dirty
tree, zero retries, `evals_files=0`.

### Does not establish

Anything about the three 0.3.0 edits — the delta is +1 on 156 with a
16% flip rate, which is a null result, not a confirmation and not a refutation. Any
calibrated rate for 0.3.0: TPR, TNR and the Rogan-Gladen correction all await the 60 labels.
Attribution between the three edits, which one capture could never separate. Anything about
`natural` mode.

### Open

Whether the `absent` cases written for batch 5 are easier than the corpus's
existing ones (p ≈ 0.17, underpowered). Whether `adjacent` at 50% on batch 5 is case
difficulty or a real regression. Whether the seven `disputes-the-premise` failures are
grader artifacts or model failures — three are verified artifacts, four need labels.

## Next

1. Label the 60 in `evals/review/request-plan-0.3.0.html` — the fresh held-out tranche whole
   (18) plus the enriched dev sample (42: all 17 dev failures, 25 of 69 dev passes at weight
   2.76). This is the real non-money cost.
2. `label-align.py --labels … --grades … --min-id 168` for held-out TPR/TNR, and without
   `--min-id` for the weighted full-set rates and the Rogan-Gladen correction.
3. Decide `disputes-the-premise` on the labels, not on this document.
4. If the three 0.3.0 edits need an actual verdict, budget repeated captures at one version
   to size the noise band first. A second single capture will not answer it.
