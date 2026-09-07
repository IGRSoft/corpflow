# request-plan — 0.2.0 calibration

The first capture that provably measured the tree under test. Not comparable with the 0.0.1
baseline: that run had no `--plugin-dir`, so the installed release answered and its records
cannot say which skill version produced them (`evals/README.md § The capture surface`).

## Provenance

| | |
|---|---|
| eval set | `skills/request-plan/evals/evals.json`, `eval_set_version: 0.2.0` |
| skill | `skills/request-plan/SKILL.md`, `version: 0.2.0` |
| model | `claude-sonnet-5` |
| mode | `command`, `bypassPermissions`, isolated capture tree |
| `plugin_sha` | `86f5aef` ×109, `fb8020d` ×35, `6ef343a` ×12 — **no `-dirty`** |
| captured | 2026-08-26 |
| cases | 156 (116 plan / 23 refute / 17 clarify); **60 human-labelled** |
| cost | **$126.46**, $0.81/case |

The capture spans three revisions because a rate-limited sweep was resumed twice. `git diff`
across all three touches nothing in `SKILL.md`, `references/`, `commands/`, `agents/` or the
shared canon, so the measured surface is identical; `eval-grade.py` reports the spread rather
than hiding it.

## Headline

**Harness 127/156 = 81%. TPR 96%, TNR 69% on 12 human negatives. ~~Corrected 77%,
95% CI [65%, 85%]~~ — withdrawn, see below.**

The raw human figure — 50 of 60 labelled — is **not** a corpus rate and must not be quoted as
one. The labelled sample is deliberately enriched toward harness-fails; only the
stratum-weighted correction is comparable to anything — and this capture no longer has one.

### Calibration

| | TPR | TNR | human negatives | corrected |
|---|--:|--:|--:|--:|
| all 60 labelled | 96% | **69%** | 12 | **withdrawn** |
| dev subset, 42 | **93%** | **69%** | 12 | **withdrawn** |
| held-out 18 | 100% | n/a | 0 | n/a |

> **Withdrawn 2026-09-05.** Every weighted figure from this capture is retracted; the
> label-only ones (TPR, TNR, the confusion matrix, every per-case reading below) stand
> untouched.
>
> Two independent reasons, and either alone is sufficient:
>
> 1. **The draw and the labels disagree about which stratum each case sits in.**
>    `request-plan-0.2.0-sample.json` records `dev/pass` 25 and `dev/fail` 17; the exported
>    labels carry `dev/pass` 30 and `dev/fail` 12. The grade set moved after the draw was
>    cut, so the sampling fractions divided back out were never the ones taken.
>    `label-align.py` now detects exactly this and exits 65 rather than printing a rate.
> 2. **The weighting itself was wrong for every capture.** Strata were derived as
>    `(split, grader_verdict)` instead of from the draw, so the tranche taken whole was
>    weighted against the entire `test` split. See `evals/README.md § The weights belong to
>    the draw`.
>
> **Recovery was attempted and is not possible.** Re-cutting the draw needs the grade set
> the labels were taken under, which needs the stored responses — and they are gone. A
> sweep of every checkout and worktree on the capture host on 2026-09-05 found exactly one
> surviving responses directory, `responses-v0.1.0-baseline` (96 records, `skill_version`
> 0.1.0), which the 0.0.1 reset had already retired. Neither `responses-0.2.0` nor
> `responses-0.3.0` exists anywhere.
>
> So the corrected rate is **withdrawn permanently, not pending**. Nothing short of a fresh
> ~$164 sweep produces a number here, and that number would measure a different capture.
> `evals/README.md § The capture surface` said this would happen — *"a grade is reproducible
> only by paying for the capture again, so record the numbers that matter in the commit or a
> findings doc rather than assuming the responses will be there"* — and it is the reason
> `label-align.py` now takes `--p-obs`: the 0.3.0 figures were re-derivable from committed
> labels plus a recorded rate, and these were not, because the stratum assignment they needed
> was only ever in the deleted grade set.

**TPR clears the 90% target. TNR misses the 80% floor** on 12 human negatives, and is
reported rather than tuned:
the two false passes that hold it down are the already-ships boundary, whose assertion was
withdrawn at 0.1.0 for 12 firings and 0 true positives. Reinstating it on two cases would fit
the grader to them.

#### Why TNR fell during the run

It read 73% before the case corrections below and 69% after. The fall is the honest part.
Four of the grader's true negatives were cases where it failed a response on template grounds
while the human failed it on *answer type* — the two agreed on the verdict for unrelated
reasons. Agreement by coincidence is not detection, and removing it lowered the number it had
been propping up.

## The held-out measurement is uninformative

The tranche now contains **zero human failures**. Its only three — 125, 153, 163 — are among
the five cases converted to `refute` below, which flipped their verdicts to pass.

Correcting them there was the lesser harm: a case whose premise is false would have corrupted
the one-shot measurement. But it removed every negative, so **held-out TNR is unmeasurable and
TPR 100% over 18 all-positive cases tests nothing about failure detection.** It also means the
held-out set was adjusted using information from its own labels.

Recovering a real held-out number needs roughly 20 more labels from the 51-case
`test`/harness-pass stratum. Until then this corpus has never measured held-out failure
detection.

### Resolved at 0.3.0

> **Resolved at 0.3.0** (`evals/findings/request-plan-0.3.0.md`). Batch 5 replaced this
> tranche rather than growing it — these 18 were read during the labelling below, and
> re-stratifying does not make a case unread. Its successor is 18 fresh cases at ids 168+
> (7 clarify / 7 plan / 4 refute) carrying **3 harness failures on 3 distinct mechanisms**,
> so held-out TNR is measurable once labelled. Note the engine missed: the `absent` cell
> nominated as the negative generator passed 7 of 7, and the negatives came from
> `adjacent`, `buried` and `refute`.

## Contamination: 6 of 156 (4%), zero answer-key reads

Against 0.0.1's 7 of 114 with at least 3 reading `expected_outcome` outright. The fatal
channel is closed; the isolated capture tree works.

| channel | n | what it is |
|---|--:|---|
| answer-key | **0** | read the case's own verdict |
| strip | 3 | saw the deleted eval files in `git status` |
| harness-log | 3 | read this capture's own `#333` commits |

The strip removes the answer key but cannot remove the fact of the strip. Both residual
channels are that.

**The scan itself was wrong twice, in both directions.** Its first version reported 12%
including a fatal read — four of those were sound responses (one listed `expected_outcome`
as a *field name* while planning schema documentation; three proposed *adding* an eval case).
A later version under-counted at 2% by missing the phrasing "deleted and uncommitted" and by
letting the grounding exemption excuse a case that read `git status` outright. An inflated
contamination rate misleads exactly as much as a deflated one; the false positives are pinned
as tests in `tests/python/test_eval_capture.py`.

## What the failures say

15 of the 60 labelled responses failed. They fall into six mechanisms, and **the largest
result is a mechanism that has disappeared**.

| mechanism | n | class |
|---|--:|---|
| refuted where the case expected a plan | 7 | contradiction |
| planned where a clarification was owed | 4 | contradiction |
| over-routed to `--secure` from its own findings | 3 | contradiction |
| asked where a plan was owed | 1 | ignored |
| effort as a range, not a 0–25 value | 1 | ignored |
| **`missed-the-real-surface`** | **0** | — |

`missed-the-real-surface` was 15 of 22 failures in 0.0.1 and is now zero. The capability
registry and the § 2 search-depth rules did what they were written to do.

What remains is almost entirely one class: **places where two rule surfaces disagree and the
model followed the other one.** These are not the model trying less hard — each trace obeyed a
real rule, and a different rule graded it.

### The three contradictions

**1. Tier rule against `derive_route()`** — 3 traces. `estimation-methodology § Worktask Tier
Selection` reads *"IF **the work** reads, writes, or exposes credentials"*; the generator
derives ground truth from the request's words alone, deliberately. All three asked "will the
work touch a secret?", answered yes, and escalated. Only the generator can be right: ground
truth has to be derivable from the prompt. **Unfixed — the edit is owed.**

**2. `SKILL.md § 1` against itself** — 4 traces, all `absent` grounding. The branches are
listed "in order", and rule 1 (*fold the ambiguity into the plan*) is both first and broader
than rule 2 (*no surface at all → ask, and only ask*). A request naming a system the repo
lacks is ambiguity that changes the phases, so rule 1 consumes rule 2's cases. All four traces
executed rule 1 correctly. **Unfixed — the edit is owed.**

**3. `§ 4` against the batch-4 cases** — 7 traces. **Resolved here**, see below.

## Case corrections made in this cycle

**Five cases converted to `refute`** (18, 125, 153, 159, 163). Each asserts an absence the
search disproves outright: one claims the planning stage is undocumented, against a 713-line
`pl0-procedure.md`; another claims nothing scores stored responses, against `eval-grade.py`.
The model was right and the cases were wrong.

Prompts are paraphrased here on purpose. `test_skill_evals.py` scans every tracked *and
untracked* file for any six-word window of any prompt, and `evals/findings/` is not exempt —
a findings doc quoting the case it discusses turns that case into a lookup at the next
capture. The first draft of this document tripped that lint on two cases. Converted rather than relabelled because a case whose
*premise* changed cannot be repaired by a rubric note.

**Three cases repointed** (23, 67, 152). All seven `finds-the-real-surface` false alarms were
responses that never named the ground file; on three, the surface they reached was the better
one — `anchor-preflight.sh` really is the anchor lint, `pairing.py` really is the comparability
gate. Case 152 is dual-owned and lists both.

**`disputes-the-premise` widened** by two patterns, after the boundary was settled and not
before: one response opened *"the premise doesn't hold"* and another *"Already built."*

`prompt_digest` was untouched throughout, so none of this required re-capturing. Every flipped
label carries a dated note.

## The LLM judge: closed, not deferred

`judge-traces.py` was retired at TNR 0%. `evals/README.md` set the terms for reinstatement —
measure it on labels it has not seen — and this pass produced exactly that.

**TNR 0% again.** 0 of the 10 human failures caught; 59 of 60 traces passed;
`claude-opus-5` at effort `max`, $7.54. The deterministic harness scores TPR 92% / TNR 80% on
the same 60 cases, unweighted.

Two captures, two independent label sets, the same result. Verdicts are committed to
`evals/judgements/request-plan.jsonl` so the next reinstatement proposal argues against a
measurement rather than an anecdote.

## By grounding

| grounding | n | harness | human (labelled) |
|---|--:|--:|--:|
| obvious | 36 | 92% | 9/9 |
| adjacent | 16 | 81% | 3/4 |
| buried | 87 | 79% | 36/41 |
| absent | 17 | **71%** | **2/6** |

`absent` is the weak column and the human column is weaker than the harness column — the
ask-versus-plan contradiction above, which the harness cannot see because it grades outcome
type and the disagreement is about which outcome was owed.

## By request type and route

| type | n | harness | | route | n | harness |
|---|--:|--:|---|---|--:|--:|
| bug | 44 | 89% | | std | 133 | 81% |
| refactor | 18 | 89% | | secure | 9 | 89% |
| docs | 20 | 85% | | emerg | 14 | 79% |
| feature | 50 | 76% | | | | |
| incident | 17 | 71% | | | | |
| migration | 7 | 71% | | | | |

`secure` (9) and `emerg` (14) are too small to carry a rate alone.

## By expected outcome

| outcome | n | harness |
|---|--:|--:|
| refute | 23 | 87% |
| plan | 116 | 82% |
| clarify | 17 | 71% |

## What this establishes, and what it does not

**Establishes:** a calibrated pass rate with a confidence interval; the first capture that
provably measured this tree; a clean answer-key channel; the disappearance of the dominant
0.0.1 failure mode; and a second, independent refutation of the LLM judge.

**Does not establish:**

- **Attribution.** Three spec versions stacked since the last capture — 0.1.0, the 4.0.26
  command reorganization, 0.2.0. One capture measures all three and can separate none.
- **Held-out failure detection.** See above; the tranche has no negatives left.
- **Anything about `natural` mode.** Captured in `command` mode only, so whether the skill
  triggers unprompted is still unmeasured.
- **That any rule change works.** The two contradictions still open are argued from the traces
  that motivated them. Only responses produced under the new rule measure whether it worked.

## Recommended next actions, in order

1. **Fix the two open contradictions** — the tier rule's surface check, and `§ 1`'s branch
   order. Both are spec changes and move the `SKILL.md` / `eval_set_version` pair to 0.3.0.
2. **Label ~20 more held-out cases**, so the next capture has a real held-out TNR to move
   against.
3. **Only then re-capture.** A cheap partial signal is available first: re-running the 15
   failing cases costs about $12. Not a measurement — not a random sample, and the grader is
   calibrated on the full set — but it shows whether the contradictions stopped producing the
   same answer.

## Forward reference: what the 0.3.0 capture measured

Actions 1 and 3 were taken; action 2 was superseded by replacing the tranche. The 0.3.0
capture (201 cases, $164.08, `plugin_sha 0e1dcfc`) re-graded these responses against the
grown eval set and reproduced this document exactly — **127/156**, every dimension matching
to the rounding — which is what makes the comparison per-case paired.

**The paired delta is +1 (127 → 128 on the 156 shared cases), with 25 of them flipping.**
The two contradictions fixed at 0.3.0 are therefore **not measurable** above run-to-run
variance from a single paired capture. Pairing controls for case identity, not for model
stochasticity, and the 16% flip rate says stochasticity dominates. The recommendation in
action 3 above — that responses under the new rule would show whether it worked — held only
if the effect exceeded that noise floor, and it does not.

### `disputes-the-premise` understates both captures

One finding needs reading back into this document: **`disputes-the-premise` fails 7 of
32 refute cases in the 0.3.0 capture and 3 of the paired ids here**, every one on an
`already <verb>` construction whose verb the enumerated list omits. The rate above is
understated by that amount, in both captures equally.
