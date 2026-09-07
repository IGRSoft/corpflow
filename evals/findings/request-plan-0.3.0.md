# request-plan — 0.3.0 capture

The first per-case-paired A/B this corpus has had. It measures the three 0.3.0 rule edits
against the 0.2.0 responses on a fixed grading surface, and it comes back **null**.

The labelling pass that followed is the more useful half: TNR clears its floor for the first
time, every human/harness disagreement runs one way, and the held-out tranche yielded one
negative rather than the three the harness reported.

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
| cases | 201 (134 plan / 35 clarify / 32 refute); **60 human-labelled**, 59 usable |
| cost | **$164.08**, $0.82/case, 0 retries, 0 rate-limit failures |

Provenance is tighter than 0.2.0's, which smeared across `86f5aef ×109, fb8020d ×35,
6ef343a ×12` because commits landed between resumes. This run completed in one process, so
`provenance` — computed once before the sweep — describes every case in it.

## Headline

**Harness 162/201 = 81%. Corrected 86%, 95% CI [82%, 90%]. TPR 93%, TNR 100% on 13
human negatives.**

60 labels, 59 usable (one deferred). The raw labelled count is not a corpus rate — the
sample is enriched toward harness failures — so only the weighted correction compares to
anything.

> **Restated 2026-09-05 after a weighting defect was found in `label-align.py`.** The
> figures below are recomputed, not the ones this document first carried. The tool derived
> its strata as `(split, grader_verdict)` rather than from the draw, which put all 18
> tranche cases in a stratum whose population was the whole 82-case `test` split and
> weighted each ~4.6x — an extrapolation of a deliberately harder tail across the corpus.
> `--min-id` also narrowed the labels without narrowing the population or `p_obs`, so the
> held-out row was a corpus rate corrected by subset-derived TPR/TNR, and `--min-id 168`
> never isolated the tranche in the first place: batch 5 seeded 12 dev cases in the same
> id range. `evals/README.md § The weights belong to the draw` records the whole account.
>
> **Nothing about the paired A/B, the flip analysis, the contamination scan or the
> per-dimension tables changes** — those are harness counts and never passed through a
> weight. What moved is the calibration block, by 1-2 points.

### Calibration

Recomputed from the draw's own strata (`dev/pass` 25 of 69, `dev/fail` 17 of 17,
`test/held-out` 17 of 18 with one deferred):

| | TPR | TNR | human negatives | corrected |
|---|--:|--:|--:|--:|
| all 59 labelled (weighted) | **93%** | **100%** | 13 | 86% [82–90] |
| held-out tranche, 17 | 94% | 100% | **1** | 89% [83–100] |
| — 0.2.0, for comparison | 96% | **69%** | 12 | *see below* |

Reproduce without repaying for the capture — `--p-obs` supplies the observed rate the
gitignored responses would otherwise have to:

```sh
python3 evals/scripts/label-align.py \
  --labels evals/labels/request-plan-0.3.0-human.jsonl \
  --sample evals/labels/request-plan-0.3.0-sample.json --p-obs 0.80597
python3 evals/scripts/label-align.py \
  --labels evals/labels/request-plan-0.3.0-human.jsonl \
  --sample evals/labels/request-plan-0.3.0-sample.json \
  --stratum test/held-out --p-obs 0.83333
```

**The 0.2.0 comparison row no longer has a corrected rate.** Run against its own draw,
`label-align.py` now refuses (rc 65): that draw records `dev/pass` 25 and `dev/fail` 17,
but its labels carry `dev/pass` 30 and `dev/fail` 12 — the grade set moved after the draw
was cut, so every weight it ever produced divided out a sampling fraction nobody took. Its
TPR/TNR stand (they need only the labels); its **77% [65–85] does not** and is withdrawn.
The 69%→100% TNR movement is unaffected, since both are label-only quantities.

Read the held-out row with care regardless of weighting: it rests on **one** human
negative, and `label-align.py` prints its own sub-20 warning on it.

**TNR clears the 80% floor for the first time** — 100% on 13 human negatives, against
69% at 0.2.0. The reason is
categorical, not marginal: **there are zero false passes in this sample.** Every one of the
six human/harness disagreements runs the other way — the grader failed something the human
passed. The two false passes that held 0.2.0's TNR down were both the already-ships
boundary, and no case in this sample reproduces them.

Read the held-out row with care; see § The held-out tranche.

## Every disagreement is a false fail

| case | expected | harness failed on | human |
|---|---|---|---|
| 210 | refute | `disputes-the-premise` | pass |
| 211 | refute | `disputes-the-premise` | pass |
| 212 | refute | `disputes-the-premise` | pass |
| 67 | plan | `finds-the-real-surface` | pass |
| 193 | plan | `finds-the-real-surface` | pass |
| 191 | plan | 6 template assertions | pass |

Three of the six are the `disputes-the-premise` defect predicted below — **the labels
confirm it rather than merely permitting it**, which is what the prediction was waiting on.
The grader is now measurably too strict and not at all too lenient, which is the safe
direction to be wrong in but still costs 39 recorded failures of which at least 6 are not
failures.

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
rendered the full build plan anyway) and case 59 is unclear from its opening.

### Labels settled three of the seven

**Labels settled three of the seven.** 210, 211 and 212 were drawn into the 60-case sample
and all three came back `pass` — the reading above is confirmed, not merely permitted. The
remaining four (17, 22, 59, 125) were **not sampled**, so they stay unresolved; deciding
them needs a targeted pass, not another sweep.

### Why it keeps recurring

**The design is the defect, not the coverage.** "Already" takes an open verb class; an
enumerated list cannot close it. This is the fourth time the list has been found short — the
0.0.1 capture added `fixed`/`closed` after two misses, the 0.2.0 capture added two whole
patterns after two more — and each widening was a response to the previous capture's misses.
The pattern of repair is itself the evidence that enumeration is the wrong mechanism.

### The obvious repair was measured, and it does not work

The labels justify a fix, so the fix was attempted. Every variant was measured over all 201
responses before being applied, and **none is worth applying.** Recall on `refute` against
firing on `plan` — the latter is the false-pass proxy, since a pattern that matches ordinary
planning prose would pass a refute case that never refuted:

| variant | fires on refute | fires on plan | rescues of 7 |
|---|--:|--:|--:|
| current | 78% | **57%** | 0 |
| + open-class `already <verb>` | **100%** | **87%** | 7 |
| + open-class, first 400 chars | 78% | 49% | 6 |
| + open-class, first 250 chars | 75% | 41% | 5 |

#### Why widening backfires

The baseline row is the finding: **the current criterion already fires on 57% of responses
that are not refutations at all.** Widening it to catch all seven takes that to 87% — a
criterion true of seven answers in eight grades nothing, and on a refute case it becomes a
false pass. That is the shape that gave the LLM judge a 0% TNR twice and withdrew
`no-build-plan-for-work-that-exists` at 0.1.0. Position-scoping is the best of the family
and still fires on 41% of plans for 75% recall.

### Withdrawal does not work either

The other option is to drop the criterion, as 0.1.0 dropped its predecessor. But refute
cases would then be graded on `cites-evidence` alone, and **that fires on 32 of 32 refute
responses** — every refute case would pass unconditionally. Withdrawal grades nothing, which
is worse than grading badly.

### Conclusion: leave it, and read refute grades as a floor

No regex over this text separates a refutation from a plan, because the two correct
refutation shapes are textually opposite: one **stops** without a template (212), and one
**refutes then plans the live remainder** (210, 211), which § 4 has required since 0.1.0.
Nothing lexical spans both while excluding a plan that merely describes what the repo
already does — and describing that is *good grounding*, not refutation.

#### What is recorded instead

The criterion therefore stays exactly as it is, and the reading is recorded instead:
**`refute` grades are a floor with a measured false-negative rate of at least 3 of 32
(labelled) and plausibly 7 of 32.** This is a judge criterion, as the eval set already says
of its sibling; reaching it needs an evaluator that can read what an answer is *about*.

The recommendation in the previous revision — rewrite it around the construction — was
wrong. Measuring it before applying it is the only reason that is visible here rather than
shipped.

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

## The held-out tranche: one negative, not three

This was the point of batch 5. It half worked, and the labels are what show the difference.

| | batch 4 (spent) | batch 5 (this capture) |
|---|---|---|
| n | 18 | 18 |
| outcomes | 15 plan / 3 refute / **0 clarify** | 7 clarify / 7 plan / 4 refute |
| grounding | 17 buried / 1 obvious | 7 absent / 5 buried / 4 adjacent / 2 obvious |
| harness | 18/18 = **100%** | 15/18 = 83% |
| harness failures | **0** | **3**, on 3 distinct mechanisms |

### Labels cut three harness failures down to one

The three harness failures did not survive labelling as three:

| case | harness | human | what it turned out to be |
|---|---|---|---|
| 199 | fail | **fail** | a real miss — the only genuine held-out negative |
| 212 | fail | pass | the `disputes-the-premise` grader defect |
| 187 | fail | **defer** | a capture defect — see below |

So held-out TNR is **100% on a single labelled negative**, and `label-align.py` prints its
own warning on the row: *under 20 labels, directional only, a single case moves these
rates.* Take that seriously. Batch 5 moved held-out negatives from **0 to 1**. That is a
real improvement over an unmeasurable rate and it is nowhere near a measured one.

I wrote "the objective is met" in this document before the labels existed. That was wrong,
and the correction is the point: a tranche designed to contain failures produced one, which
is what the design could deliver rather than what it promised.

### Case 187 is a capture defect, and the mechanism is known

`extract_response()` stores `obj["result"]` from `claude -p --output-format json`. That field
carries **only the final assistant message**, not all of the turn's assistant output. When
the model emits its answer and then emits a second message — here, after a background check
came back — the first is discarded and the second is stored as the whole response.

#### What 187 shows

Its stored response holds only a **follow-up turn** — it opens by reporting a background
check coming back, refers to "the plan" as already written, and closes by asking whether to
save it. The plan itself is not in the record: 1,339 chars against 1,872 output tokens, and
no Context/Goal/Phases/Effort heading anywhere. `asked-instead-of-planning` cannot be
assessed against a plan that was never stored, which is why the label is `defer`.

Bounded, not systemic: five other responses open with a continuation-style preamble
(19, 32, 59, 71, 203) and every one of them contains the full template underneath. **1 of
201**, so this capture stands.

##### Fixed for the next sweep

The defect reproduces on demand — a prompt that says one word,
runs a command, then says another word returns only the second word under
`--output-format json` — and the capture path now uses `stream-json`, keeping every
assistant block. It cannot be repaired retroactively: 187's plan was never stored.

### The stated engine did not fire

The design nominated the `absent`→`clarify` cell as the negative generator, on the 0.2.0
evidence that it was the weakest column (harness 71%, human 2/6). **All 7 held-out `clarify`
cases passed.** The negatives came from `adjacent`, `buried` and `refute` instead.

#### Are the new `absent` cases just easier?

Across all 18 new `absent` cases the harness scored 17/18 (94%) against 13/17 (76%) on the
17 pre-existing ones in the same capture. Fisher's exact on that split is p ≈ 0.17 — not
significant, but the direction says the `absent` cases written for batch 5 are plausibly
**easier** than the ones already in the corpus, and that possibility should not be quietly
absorbed. Anyone re-cutting this cell should sample the existing prompts for difficulty
rather than writing fresh ones from the same template.

The labels sharpen this rather than soften it: all 7 held-out `clarify` cases passed on the
human read too, so the cell produced no negatives by either measure. The nominated engine
did not fire, and the single negative that did arrive came from `buried`.

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

The 0.2.0 responses re-graded identically at the time, so the paired baseline was sound when
this A/B was run. **It is no longer durable, and that claim is retracted:** a sweep of the
capture host on 2026-09-05 found neither `responses-0.2.0` nor `responses-0.3.0` — the only
surviving capture is `responses-v0.1.0-baseline`. The paired result stands as recorded and
can no longer be re-derived from responses; what survives is the committed labels, the draws,
and the rates written down here. **TNR is 100% with zero false passes** on 13 human negatives, clearing the 80%
floor 0.2.0 missed at 69% — the grader errs strict, never lenient. Corrected rate
86% [82–90] on 59 labels, at eval-set **0.3.0**; the shipping spec is 0.4.0 and unmeasured.
`disputes-the-premise` has a false-negative mode with a named cause, now confirmed by three
human labels rather than argued. The capture surface was clean: one sha, no dirty tree, zero
retries, `evals_files=0`.

### Does not establish

Anything about the three 0.3.0 edits — the delta is +1 on 156 with a 16% flip rate, which is
a null result, not a confirmation and not a refutation. **A held-out TNR worth the name**:
the tranche yielded exactly one human negative, so 100% rests on n=1 and the alignment tool
says so itself. Attribution between the three edits, which one capture could never separate.
Anything about `natural` mode.

### Open

Whether the `absent` cases written for batch 5 are easier than the corpus's existing ones
(p ≈ 0.17, underpowered) — the labels agree with the harness on all of them, which is
consistent with "easier" and does not distinguish it from "correctly answered". Whether
`adjacent` at 50% on batch 5 is case difficulty or a real regression. Cases 17, 22, 59 and
125: four `disputes-the-premise` failures that went unsampled and are still undecided. How
`eval-capture.py` came to store only a follow-up turn for case 187.

## Next

1. **Do not touch `disputes-the-premise`.** Measured above: every repair is worse than the
   defect. Read `refute` grades as a floor instead, and record the false-negative rate
   alongside any refute number quoted from this capture.
2. ~~Fix the capture path before the next sweep.~~ **Done.** `build_argv` now dispatches
   `--output-format stream-json --verbose` and `extract_response` concatenates every
   assistant text block. Validated against real CLI output, not only mocks; the legacy
   envelope still parses so stored dispatches read back unchanged. This does **not**
   retroactively repair case 187 — the discarded plan was never written to disk.
3. **Label 17, 22, 59 and 125** if the refute cell is ever quoted precisely. They no longer
   gate a rewrite — nothing is being rewritten — so this is now optional rather than
   blocking.
### Then

4. **Do not re-capture to settle the 0.3.0 edits with a single run.** Repeated captures at
   one version to size the noise band, or leave the question open. A second single capture
   will not answer it.
5. Held-out negatives remain the scarce resource: 1 from 18. A tranche that reliably
   produces them is the open design problem, and weighting toward a historically weak cell
   did not solve it.
6. **The 13 graded failures were re-diagnosed, and the first diagnosis was wrong.** They
   were read as a missing rule each. They are not: `request-plan` states each of those
   rules more than once and the copies contradict each other, so every one is a model
   correctly following the wrong copy — `SKILL.md § 4` against `§ 1` for the four
   name-the-absence-then-plan answers, `references/context-gathering.md` carrying the
   refuted 0.2.0 stop condition against `SKILL.md` for the eight neighbour-stops, and
   `references/handoff.md`'s topic-flavour `--secure` bullet against canon for case 80.
   All three are reconciled at SKILL.md 0.4.0 and pinned by parity contracts; see the
   `evals.json` `grading` entry. Consistent with item 4 above: **no re-capture was
   commissioned to prove it**, and none should be. Two theories were tested and disproved
   and should not be revived — that the capability registry hid the excluded file classes
   (5 of the 8 neighbour-stops ground on registry-*enumerated* files), and that the tier
   drift needed a new prohibition (`handoff.md` already carried one, undone by the drifted
   bullet 15 lines above it).
