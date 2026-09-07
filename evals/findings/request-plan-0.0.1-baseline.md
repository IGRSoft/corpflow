# request-plan — 0.0.1 baseline

The point future work measures from: one validated case set, one capture at one skill version,
one grader run, one complete human labelling pass. Nothing here is comparable with any number
from before the reset (`evals/README.md § Baseline 0.0.1`).

## Provenance

| | |
|---|---|
| eval set | `skills/request-plan/evals/evals.json`, `eval_set_version: 0.0.1` |
| skill | `skills/request-plan/SKILL.md`, `version: 0.0.1` |
| model | `claude-sonnet-5` |
| mode | `command` (invokes the skill explicitly), `bypassPermissions` |
| `plugin_sha` | `9e2cda9-dirty` — **dirty**: the reset itself was uncommitted at capture time |
| captured / labelled | 2026-08-23 |
| cases | 114 (77 plan / 20 refute / 17 clarify), **all 114 human-labelled** |
| cost | **$71.73**, $0.63/case |

`plugin_sha` ends in `-dirty` and that is load-bearing: the tree carried the whole reset
uncommitted. Re-capturing at the committed SHA would cost another $72 to produce the same
numbers, so the dirty marker is the honest record rather than something to launder.

## Headline

**Human: 92/114 = 81%. Harness: 65/114 = 57%.**

The human number is the baseline. The harness number is what the assertion set can currently
see, and the gap between them is a property of the grader, not of the skill.

### Harness calibration

| | |
|---|--:|
| TPR (harness passes what a human passes) | **63%** |
| TNR (harness fails what a human fails) | **68%** |
| TPR + TNR − 1 | 0.31 |
| observed harness rate | 57% |
| Rogan-Gladen corrected | **81%** |

The correction lands on 81% and the humans independently scored 81%. Two estimates built from
different inputs agreeing to the point is the strongest internal check available here, and it
says the harness's 57% is a measurement artefact.

> **Untouched by the 2026-09-05 weighting retraction.** That defect only reaches captures
> whose labels were an enriched *sample*; this one labelled 113 of 114 cases, so every
> sampling fraction is ~1 and no weight was ever divided out. 0.0.1 remains retired for the
> separate reason in `evals/README.md § Baseline 0.0.1` — it was captured without
> `--plugin-dir`, so its rates measure an unknown skill version.

It also says the harness is weak. At TPR 63% it fails **34 of the 92 responses a human
passed** — a 37% false-fail rate. TPR + TNR − 1 = 0.31 clears the "barely beats a coin" floor of
0.2, but not by much: any pass rate this harness reports unaided should be treated as a lower
bound and corrected, never quoted raw.

## CONTAMINATION: the capture can read its own answer key

**7 of 114 responses reached the eval corpus during the run, and at least 3 read the answer.**

| case | what the response said |
|---|---|
| 17 | quoted its own case: *"This exact prompt is even a tracked eval case (`evals.json` id 611, `expected_outcome: "refute"`)"* |
| 94 | *"You're testing the skill against its own eval case — there's nothing further to do"* |
| 120 | *"including this exact prompt, logged as eval case #120 for this skill"* |
| 35, 82, 89, 115 | named `evals.json` or `gen-request-plan-cases.py` as a surface |

### Why the lint could not catch it

This is the same defect class as the tracked-vs-working-tree leak fixed in this change, one
level deeper. `eval-capture.py` runs the model against the working tree; `evals.json` and
`gen-request-plan-cases.py` live in that tree; and the prompt-leak lint **exempts both by
design**, on the reasoning that "a case has to live somewhere". True — but the file it lives in
carries `expected_outcome`, which is the answer. The exemption that makes the lint possible is
the hole.

Case 17 is the clearest instance: it read `expected_outcome: "refute"` and refuted. It is
counted as a human pass in every table below, and it should not be counted as evidence of
anything.

### What it costs

**This bounds the baseline.** 81% is an upper bound on 7 cases and an honest estimate on 107.
It does not invalidate the headline — 6% of the set at worst — but it must be fixed before the
next capture, or the number moves for reasons that have nothing to do with the skill.

The fix is not another lint. Capture has to run against a tree that does not contain the eval
set: dispatch from a copy with `skills/*/evals/` and `evals/` removed, or capture from a
worktree pinned before the cases existed. Filed here rather than fixed, because changing the
capture surface after a $72 run should be a deliberate, separately-reviewed change.

## By expected outcome

| outcome | n | human | harness |
|---|--:|--:|--:|
| plan | 77 | **77%** (59) | 58% (45) |
| refute | 20 | **95%** (19) | 30% (6) |
| clarify | 17 | **82%** (14) | 82% (14) |

### Refute: a grader failure, not a skill failure

**`refute` is where the harness fails hardest: 95% human against 30% harness.** 13 of the
34 false fails are refute cases, on two assertions:

- `disputes-the-premise` (8 false fails) — the verb list is too short. Case 13 opens *"Already
  fixed — no plan needed"*, cites the contract comment and the bats guard, and stops. Textbook.
  The regex accepts `already ship|land|split|exist|done|implemented|happened|in place` and does
  not accept **fixed**, **closed**, **addressed**, **resolved**, or **handled**.
- `no-build-plan-for-work-that-exists` (12 false fails) — fires on a plan that refutes and then
  correctly plans the *narrower* live remainder. Case 17 refutes the blanket claim, then plans
  the one eviction path still broken. A human calls that the best possible answer; the
  regex_none sees `**In:**` and fails it.

## Case 4 was mis-converted — my error

Case 4 (*"CHANGELOG.md is 183KB"*) was converted to `refute` on `d32c8b3`. But that split left
119KB, the response measured 123KB and argued a further split is warranted, and the human passed
the resulting plan. The premise's **number** went stale; its **request** did not. It belongs
with 44/45/55 — correct the figure, keep it a plan — not with the 16 shipped-work conversions.
Recommend reverting it before the next capture. Worth re-auditing 5 and 53 on the same test.

## By grounding

| grounding | n | human | harness |
|---|--:|--:|--:|
| obvious | 34 | **94%** (32) | 65% (22) |
| buried | 46 | **67%** (31) | 37% (17) |
| adjacent | 17 | **88%** (15) | 71% (12) |
| absent | 17 | **82%** (14) | 82% (14) |

`buried` at 67% is the real defect surface and the only column where human and harness roughly
agree on the shape. **15 of the 22 human failures are `buried`**, and they share one mechanism:
the plan reaches a plausible neighbour and stops. Case 27 and case 65 both plan a `--compare`
flag in `commands/cost-report.md` and never reach
`benchmark/harness/benchmarkkit/analysis.py`, where run costs are actually produced. Case 23
attributes anchor enforcement to `cache-lint.sh` and never names `section-lint.sh`. Case 66
targets QA guidance and never touches `oracle.py`.

That is the failure `SKILL.md § 2`'s search-depth rules exist to prevent, and at 67% they are
not preventing it.

## By request type

| type | n | human | harness |
|---|--:|--:|--:|
| bug | 29 | **86%** (25) | 62% (18) |
| docs | 9 | **89%** (8) | 44% (4) |
| feature | 39 | **77%** (30) | 46% (18) |
| incident | 15 | **60%** (9) | 53% (8) |
| migration | 7 | **71%** (5) | 71% (5) |
| refactor | 15 | **100%** (15) | 80% (12) |

## By route

| route | n | human | harness |
|---|--:|--:|--:|
| std | 94 | **82%** (77) | 53% (50) |
| secure | 8 | **88%** (7) | 88% (7) |
| emerg | 12 | **67%** (8) | 67% (8) |

**Over-routing is the live routing error.** Cases 29 and 81 both take `--secure` for ordinary
work — a bash redaction-guard fix and an opt-in branch-name env knob, neither carrying a
credential, auth or permissions surface. The mirror error also appears: cases 64 and 108 route a
live blocker to the standard tier with `--emergency` demoted to a conditional aside. `secure`
(8) and `emerg` (12) are too small to carry a rate on their own.

## By split

| split | n | human | harness |
|---|--:|--:|--:|
| dev | 47 | **81%** (38) | 57% (27) |
| test | 46 | **76%** (35) | 54% (25) |
| train | 21 | **90%** (19) | 62% (13) |

**`test` is nominal, not held out.** Every case predates the reset. The dev/test gap measures
nothing and must not be quoted as generalisation.

## The false fails are one disagreement, not scattered grader bugs

**Correction to the first draft of this document.** It attributed the 34 false fails to three
regex bugs — `template-sections-present` on bold pseudo-headings, `scope-names-in-and-out` on
`**Out (P1/P2 below):**`, `effort-sized-with-complexity` on ranges. **None of the three
reproduce.** Run against this capture's responses, cases 1, 21 and 30 *hit* every pattern they
were said to miss; case 1's harness status is `pass`. Those notes describe v0.5.0 responses (see
§ Label provenance). The draft took them at face value. They are not grader bugs.

The actual structure: **26 of the 34 false fails are two mirror images of one unsettled rule.**

### Cluster A — the case says `plan`, the model says "already ships" (13 cases)

18, 20, 45, 72, 78, 79, 84, 88, 98, 101, 104, 105, 114 — 9 `buried`, 3 `adjacent`, 1 `obvious`.
Each fails 3–6 template assertions *together*, because each declined the template outright.
Case 98 in full: *"This already ships. `/worktask-status` produces exactly 'one table showing
what every task is doing' … Nothing to plan or build."* It cites the command, the canon skill and
the script. The human passed it. The harness failed it on six assertions.

That is `SKILL.md § 4` working exactly as written. It is also a direct violation of the eval
set's **decision 6** — *"a case becomes `refute` only when it asks to build something that
already exists; a request to find or use an existing surface stays a plan — that is what
`buried` grounding is for."* The 0.0.1 reset kept this whole cluster as `plan` on that rule.

### Cluster B — the case says `refute`, the model plans the remainder (13 cases)

2, 4, 5, 9, 16, 17, 19, 21, 26, 30, 53, 59. Each refutes the stale premise and then plans the
narrower thing that *is* still broken. Case 9 finds `--json` shipped in `171c74f` and plans the
missing schema-pinning test. Case 26 finds the dedup choke point and plans the second inline
`gh issue create` path in `pm-milestone.md` that bypasses it. The human passed all 13.

That is also `§ 4` working as written — *"the test is whether anything remains to be done"* —
and it says 13 of my 16 refute conversions were too coarse. Only 8 of 20 refute cases got a
clean stop: 3, 7, 13, 22, 56, 58, 60, 85.

### What this means

The two refute assertions have **no demonstrated true positives in this capture**.
`no-build-plan-for-work-that-exists` fired on 12 cases, all 12 human passes, and did *not* fire
on case 22, the only refute case a human failed: TNR 0% on this tranche — the exact pathology
that retired the LLM judge. `disputes-the-premise` fired on 9, of which 8 are human passes and
the 9th (22) it caught for the wrong reason.

**Do not widen these regexes.** The boundary they are trying to grade — "already ships, stop"
versus "surface exists, plan the remainder" — is not currently decided the same way by the case
set and by the skill. Until that is settled, any regex tuned to the labels is fitted to a
contradiction.

## Label provenance — read before trusting the calibration

The labelling page keys `localStorage` on `request-plan-labels-v1`, not on the eval-set version,
and browsers share one partition across `file://` pages. Some notes were carried over from the
v0.5.0 session:

- 8 notes are tagged `[v050]`; 3 more say `NOTE PARTLY CORRECTED` or `STALE NOTE CORRECTED`,
  which shows the reviewer was re-reading responses and repairing notes case by case.
- **10 notes name an assertion the harness did not fail on this capture** (cases 1, 2, 7, 16,
  17, 21, 30, 31, 77, 102). The exported `harness_failed` field is regenerated from the current
  grades, so it matched; only the free-text note was restored from storage.
### Case 22 specifically

- **Case 22's verdict looks stale.** Its note describes a response that emits "the full
  build-plan template anyway"; this capture's case 22 is 1,094 characters that refute, cite
  `commands/agent-report.md`, and close with *"No plan, no `/worktask` line."* That is case 16's
  shape, which the same note calls "handled properly". If 22 flips to `pass`, the human rate is
  93/114 = 82% and both refute assertions have zero true positives.

The verdicts are not automatically stale — the reviewer demonstrably re-read responses — but
the calibration below should be treated as ±1–2 points and the refute tranche as unsettled.

## False passes (7)

Cases 40, 61, 64, 67, 73, 102, 108 — the harness passed what a human failed. Smaller and less
systematic than the false fails, but 6 of 7 are `plan` cases where the template was filled
correctly over a search that never reached the ground surface. The harness cannot see that:
`finds-the-real-surface` is a token match, so a plan naming the right file in passing while
planning against the wrong one clears it.

## Capture notes

Cases 82 and 106 timed out at the 300s default and were re-captured at 600s. Both are `buried`,
the tranche that searches hardest — and case 82 is a human failure that asked two clarifying
questions after all that time.

## What this baseline establishes, and what it does not

**Establishes:** a calibrated pass rate of **81%** with TPR/TNR on a complete 114-case labelling
pass; `buried` search depth as the dominant real defect; over-routing to `--secure` as the
routing error; and a quantified, itemised list of grader bugs worth roughly 24 points of
apparent pass rate.

**Does not establish:**

- **Held-out generalisation.** See the split table.
- **A clean 7 cases.** See the contamination section.
- **Causal attribution.** This capture carries the § 2/§ 4 fix, 16 conversions, 7 retirements
  and 3 corrected prompts at once. Movement *from* here can be attributed; nothing *in* it can.
- **Anything about `natural` mode.** Captured in `command` mode only, so it never tested whether
  the skill triggers unprompted.

## Resolved: the boundary went to the skill (0.1.0)

The A/B question above was decided **B — the skill was wrong** — and shipped as `SKILL.md`
`version: 0.1.0`, `eval_set_version: 0.1.0`.

`§ 4`'s already-ships exception now requires all three of: the request asked to **build/add/fix**;
the thing exists as asked; **nothing remains**. Two shapes are called out as *not* the exception —
a request to find/reach/use an existing surface (still a plan, § 2's rule), and a shipped headline
with a live remainder (refute the stale part, plan the rest). `§ 2`'s pointer was narrowed to match;
it had been written against the wide § 4 and deferred too far.

### Grader changes that followed

- **`no-build-plan-for-work-that-exists` withdrawn**, its measurement recorded in
  `evals.json.grading`: 12 firings, 12 human passes, 0 true positives. Its question moves to
  `deferred` — distinguishing "planning the work it just refuted" from "planning the live
  remainder" needs a judge that reads what the plan is *about*.
- **`cites-evidence` replaces it** as the second refute assertion: a path or a commit SHA. A
  floor, not a score — all 20 refute responses clear it, so it catches regression, not quality.
  `paths_resolve` was tried first and withdrawn within the hour: it failed case 7, a textbook
  refutation citing `8fe5aec` and naming `genlib.py`/`treecopy.py` by basename, because a bare
  filename is deliberately not a cited path.
#### The engine matches case-sensitively

- **`disputes-the-premise` gained `(?i)`.** `eval-engine.check` matches with `re.MULTILINE` and
  **not** `re.IGNORECASE`, so a lowercase pattern cannot see a refutation that *opens* the
  response — which is where a refutation belongs. Case 13 led with "Already fixed — no plan
  needed" and was scored as never disputing anything. Verb list widened with the misses the
  capture actually produced (`fixed`, `does`, `closed`, `resolved`).

### Effect, re-graded against the same 114 responses

| | 0.0.1 | 0.1.0 |
|---|--:|--:|
| TPR | 63% | **71%** |
| TNR | 68% | 64% |
| harness pass rate | 57% | 64% |
| corrected | 81% | **81%** |
| refute tranche | 6/20 | **14/20** |

The corrected estimate does not move, which is the point: the skill was never at 57%, and the
grader is now closer to seeing that. The six refute cases still failing (4, 9, 16, 21, 53, 59) are
**correct** failures — those responses planned without ever saying the premise was stale, which
narrowed § 4 requires. They are the first genuine skill defects this tranche has produced.

Tuning stopped there deliberately. Chasing TPR to 100% against 0.0.1 labels would fit the grader
to a contract those responses were not answering.

## Recommended next actions, in order

1. **Settle the already-ships boundary.** Decision 6 (a request to *find or use* an existing
   surface stays a plan) and `SKILL.md § 4` (already ships → stop) currently give opposite
   answers on 26 cases, and the human labels side with § 4 on all of them. Either the `buried`
   capability cluster becomes `refute`, or § 4 gains an exception for "you asked me to find it,
   here it is, here is how to use it". This decides what the other steps mean.
2. **Fix the capture surface** so the model cannot read `evals.json`. Independent of step 1.
3. **Re-label the refute tranche after step 1**, with `localStorage` cleared first, so the
   verdicts are known-fresh. Case 22 at minimum needs a re-read.
4. **Only then** touch the assertions. Regexes tuned before step 1 are fitted to a contradiction.
### The one defect that needs no decision first

**`buried` search depth** — 15 of the 22 human failures, one mechanism: the plan reaches a
plausible neighbour and stops. Cases 27 and 65 both plan a `--compare` flag in
`commands/cost-report.md` and never reach `benchmark/harness/benchmarkkit/analysis.py`, where
run costs are produced. This is real, independent of the boundary question, and unaffected by
any grader change.
