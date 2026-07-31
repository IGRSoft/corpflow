# Token-attribution findings — Live resumed run (DR-SR-QA-DC-FN-ST), run 3

**Status:** partial record, n=1, resumed after crash. **Scope:** live run
`live-20260706T142415Z-f563b5c` covers only the last 6 of 10 pipeline stages
(DR, SR, QA, DC, FN, ST). PL/AR/TL/DV ran successfully but their token usage
was lost before the record was written (see Data gaps). Resumed-stage spend:
**$9.9708** against an $18.00 cap (55.4% utilized).

## Data source

- **File:** `benchmark/results/runs/live/live-20260706T142415Z-f563b5c.json`
- Mode: `live`, git_sha `f563b5c`, resume invocation `--stages DR,SR,QA,DC,FN,ST`.
- `paths.without` is entirely `null` — no comparison arm was run this pass.

## Per-stage table (this run)

| Stage | fresh_in | cache_creation | cache_read | out | cost_usd | tool_calls |
|-------|---------:|---------------:|-----------:|----:|---------:|-----------:|
| DR | 2,153 | 119,949 | 1,280,164 | 59,258 | $3.3330 | 42 |
| SR | 2,178 | 73,135 | 1,001,709 | 42,182 | $2.2988 | 33 |
| QA | 37 | 79,217 | 1,362,749 | 21,580 | $2.9494 | 85 |
| DC | 176 | 37,817 | 472,008 | 7,028 | $0.1593 | 29 |
| FN | 1,748 | 41,962 | 419,485 | 12,625 | $0.9549 | 20 |
| ST | 11 | 27,448 | 163,191 | 4,043 | $0.2754 | 12 |
| **TOTAL** | **6,303** | **379,528** | **4,699,306** | **146,716** | **$9.9708** | **221** |

### Anomalies flagged

1. **DR `out=59,258` tokens is the largest single-stage output in this run
   (40.4% of total resumed output, 146,716) and is anomalous in absolute
   terms** — no baseline for DR's per-stage `out` exists in token-findings-2.md
   (that report only totals `out` across all 10 stages: 152,601 baseline /
   174,633 post). DR's `out` alone here is comparable in scale to what run-0's
   *entire pipeline* produced as output in some stages combined. This warrants
   direct investigation: is DR emitting excessive prose/diff output, or is
   this proportionate to review scope (36 files reviewed per DR0 handoff)?
   Flagged for PE stage as the top output-token target.
2. **QA `tool_calls=85` is disproportionately high** relative to its `out`
   (21,580) and cost — more than double DR's 42 and 2.5x SR's 33, despite QA
   producing the least fresh_in (37 tokens) of any stage. This pattern
   (high tool-call count, tiny fresh_in, moderate out) is consistent with a
   verification-heavy stage (test execution loops, coverage reads) rather
   than a token-inefficiency, but should be checked against the actual QA0
   transcript for redundant re-reads.
3. **DC `fresh_in=176`** is 4x baseline-run0 (82) and 4x post-run0 (44). Small
   absolute numbers make this noisy, but the direction is consistent
   (fresh_in creeping up in DC across all three record snapshots we now have:
   82 → 44 → 176).

## Cache efficiency (cache_read vs fresh_in + cache_creation)

| Stage | cache_read | paid slice (fresh_in+cache_creation) | cache-hit % |
|-------|-----------:|--------------------------------------:|------------:|
| DR | 1,280,164 | 122,102 | 91.3% |
| SR | 1,001,709 | 75,313 | 93.0% |
| QA | 1,362,749 | 79,254 | 94.5% |
| DC | 472,008 | 37,993 | 92.6% |
| FN | 419,485 | 43,710 | 90.6% |
| ST | 163,191 | 27,459 | 85.6% |
| **TOTAL** | **4,699,306** | **385,831** | **92.4%** |

**Poor cache reuse:** ST at 85.6% is the weakest of the six — noticeably
below the other five (90.6%–94.5%), and below run-0-baseline's own ST
(82.0%→85.6%, +3.6pp so actually improved vs baseline, but still trails
post-run0's 89.5%; direction reversed vs post). All other stages sit at
or above 90%, consistent with a well-primed cache prefix this late in the
pipeline (DR is stage 5 of 6 measured, cache has accumulated from PL/AR/TL/DV
upstream even though those stages' own usage is unmeasured this run).

No stage in this run falls into genuinely poor cache-hit territory (all ≥85%);
this is a materially healthier cache profile than token-findings-1's early-stage
observation (33.8% cache-hit at pipeline stage 1), which is expected structurally
— cache-hit % climbs monotonically as more prefix context accumulates, and these
6 stages are all late in the pipeline.

## Cost concentration

| Stage | cost_usd | % of resumed total ($9.9708) |
|-------|---------:|------------------------------:|
| DR | $3.3330 | 33.4% |
| SR | $2.2988 | 23.1% |
| QA | $2.9494 | 29.6% |
| DC | $0.1593 | 1.6% |
| FN | $0.9549 | 9.6% |
| ST | $0.2754 | 2.8% |

**DR + SR + QA = 86.1% of resumed spend** ($8.581 of $9.971), confirming the
prompt's stated ~86% figure. Value alignment:

- **DR (33.4%, highest)**: review/gate stage — DR0's handoff shows substantive
  work (36 files reviewed, byte-level schema parity check, `make test` +
  `make benchmark` verification). Cost is plausibly proportionate to scope,
  but the `out=59,258` anomaly above suggests some of this cost is output-token
  driven rather than reasoning/tool-call driven (only 42 tool_calls, the
  second-lowest count of the six stages) — i.e., DR is talking a lot per
  tool call. This is the strongest signal that DR's prompt could be tightened
  to produce a denser report with fewer tokens.
- **QA (29.6%)**: this stage. High tool_calls (85) reflects genuine
  verification work (deterministic record checks, `swift test` run, temp-dir
  cleanup) — cost here tracks activity volume more than verbosity.
- **SR (23.1%)**: folded review stage per this worktask's plan (SR was
  "skipped" as a standalone stage but its work is folded into DR/DV review +
  a live `sr.txt` prompt per `skipped_stages` in state.json — worth checking
  why it still consumed 23% of spend as a distinct measured stage if its
  substantive work was meant to be folded elsewhere).
- **DC/FN/ST (1.6% / 9.6% / 2.8%)**: proportionate to their lighter scope
  (version bump + doc summary, closeout, retrospective).

Overall: cost concentration in DR/SR/QA roughly tracks their higher
responsibility (review + verification gates), but DR's `out`-heavy profile
and SR's unexpectedly high share (given it was supposed to be "folded," not
a full independent stage) are the two items worth PE attention.

## Comparison vs token-findings-2.md run-0 (overlapping stages: DR, SR, QA, DC, FN, ST)

Compared against both run-0 arms (baseline = pre-trim, post = all token-trim
levers applied). This run (call it "run-3 resumed") is a **different git_sha
(f563b5c) and a different prompt generation** (post-migration Swift benchmark
harness, not the same prompts token-findings-2 measured) — so this is a
directional cross-run comparison, not an apples-to-apples lever A/B.

| Stage | Metric | run0-baseline | run0-post | run-3 (this run) | Δ vs baseline | Δ vs post |
|-------|--------|---------------:|----------:|------------------:|---------------:|-----------:|
| DR | paid slice | 73,648 | 91,810 | 122,102 | **+65.8%** | **+33.0%** |
| DR | cache-hit % | 86.1% | 90.6% | 91.3% | +5.2pp | +0.7pp |
| DR | fresh_in | 1,877 | 1,895 | 2,153 | +14.7% | +13.6% |
| SR | paid slice | 58,053 | 53,540 | 75,313 | **+29.7%** | **+40.7%** |
| SR | cache-hit % | 91.2% | 90.9% | 93.0% | +1.8pp | +2.1pp |
| SR | fresh_in | 2,041 | 1,908 | 2,178 | +6.7% | +14.2% |
| QA | paid slice | 66,108 | 78,607 | 79,254 | +19.9% | +0.8% |
| QA | cache-hit % | 93.1% | 94.5% | 94.5% | +1.4pp | +0.0pp |
| QA | fresh_in | 28 | 35 | 37 | +32.1%* | +5.7%* |
| DC | paid slice | 27,122 | 22,568 | 37,993 | **+40.1%** | **+68.3%** |
| DC | cache-hit % | 88.0% | 75.4% | 92.6% | +4.6pp | +17.2pp |
| DC | fresh_in | 82 | 44 | 176 | +114.6%* | +300.0%* |
| FN | paid slice | 35,820 | 36,783 | 43,710 | +22.0% | +18.8% |
| FN | cache-hit % | 89.4% | 91.0% | 90.6% | +1.2pp | -0.4pp |
| ST | paid slice | 19,723 | 17,637 | 27,459 | **+39.2%** | **+55.7%** |
| ST | cache-hit % | 82.0% | 89.5% | 85.6% | +3.6pp | -3.9pp |

`*` = tiny absolute base (fresh_in in the tens-to-hundreds), so the % swing
is noisy and should not be over-weighted (same caveat token-findings-2 itself
applied to QA's fresh_in 28→35).

**Directional read:** paid slice rose across every stage vs both run-0 arms,
most sharply for DR (+33 to +66%), DC (+40 to +68%), and ST (+39 to +56%).
Cache-hit % is broadly flat-to-improved (mostly +1 to +5pp, with ST and FN
dipping slightly vs run0-post). **This is consistent with token-findings-2's
own conclusion that single-sample cross-run deltas cannot be trusted at this
scale** — run-3 is a different codebase state (post Swift migration) and a
different set of prompts than what token-findings-2 measured, so the
consistent upward paid-slice movement here is a genuinely new observation,
not proof of regression from the token-trim levers. It does mean: **whatever
gains token-findings-2's Batch 3/5 levers achieved, they have not prevented
paid-slice growth in this run's DR/DC/ST stages**, and PE should treat this as
fresh baseline data for the Swift-migration-era prompts, not as a referendum
on the earlier levers.

## Data gaps

**PL, AR, TL, DV token usage is entirely unmeasured for this run.** These
four stages executed successfully (state.json shows all four `completed`
with `pass`/`ok` verdicts, substantive artifacts: `planning-1.md`,
`architecture-1.md`, `coordination-1.md`, `development-1.md`, and DV's handoff
lists concrete deliverables — 4 commits, 226 Swift tests, 37 Python files
retired). **Their token cost is real and was incurred, but the harness
crashed before the record was written, and the Layer-2 audit fallback
(presumably a secondary usage-capture path) was also empty for this window.**

This means:
- The $9.9708 in this record is **only the tail 6 stages**, not the full
  pipeline cost. The true full-pipeline cost for this worktask run is
  **unknown but strictly greater than $9.9708** — likely substantially
  greater, since DV alone in token-findings-1/2's samples was consistently
  the single largest stage (run0-baseline DV paid slice = 142,311, larger
  than DR+SR+QA combined in that run).
- No cache-hit or cost-concentration analysis is possible for PL/AR/TL/DV
  this run.
- Any "total pipeline cost vs budget" claim for this worktask must caveat
  that the visible $9.97 figure undercounts actual spend by an unknown
  (but probably large) margin.

**Recommendation (harness P2 finding):** persist the token/usage record
**incrementally after EACH stage completes**, not only at end-of-run or on
budget-breach. A per-stage append-and-flush (even a simple JSONL line per
stage, reconciled into the final JSON at close-out) would make this class of
loss impossible — a crash after stage N would only lose stage N+1's
in-flight data, not N prior stages' worth of usage. This is the single
highest-value harness reliability fix arising from this run, independent of
any token-optimization work. Filed as **P2 harness finding** (not P1 — no
data corruption or safety issue, but a real observability gap that directly
degrades this benchmark's own purpose).

## Generated app verification

Ran `swift test` once in the DV workdir
(`benchmark/workdirs/live-20260706T142415Z-f563b5c`), Package.swift targets
`TicTacToeKit` (macOS 15 / iOS 18, Swift 6 language mode):

- **Result: 38 tests, 6 suites, all passed** (ModelsTests, EngineTests,
  GameViewModelTests + nested "statusText coverage" and "Sound behavior"
  suites, RouterTests). Total wall time 3.475s.
- This is a subset of DV's claimed "TicTacToeKitTests: 48 (macOS + iOS
  Simulator)" — the 38 observed here is the macOS-only single-platform run;
  the remaining 10 are presumably iOS-simulator-only cases not exercised by
  a bare `swift test` (consistent with q1's open question about
  iOS-simulator availability, still unresolved per state.json).
- Cross-checked against the 3 deterministic run records
  (`deterministic-20260706T072557Z-4a60fb6`, `-073412Z-3b46a71`,
  `-075048Z-3b46a71`): all three report `pass_fail: pass`, `test_count: 48`,
  confirming the full 48-test suite (incl. iOS Simulator cases) passes in
  the harness's own deterministic path, even though this local ad hoc
  `swift test` only exercised 38.
- **Known P1 (temp-dir leak) reconfirmed**: prior to this run's `swift test`,
  `$TMPDIR` already contained 80 leftover lock-sentinel artifacts named
  `ttt_test_{with,without}_<UUID>_*.lock` (0 bytes each — lock files, not the
  full ~154MB app-copy directories the original P1 finding described). These
  were deleted as part of this QA pass. No new large (multi-MB) orphan
  directories were created by this single `swift test` invocation itself in
  `$TMPDIR` proper; the fix (adding `defer`-based cleanup in
  GenLib/Generators, per `.context/errors/qa-engineer.md`) is still
  outstanding and should not be considered resolved by this cleanup alone —
  it was a one-time sweep, not a code fix.

## Recommendations for PE stage (phase-6 token-utilization prompt edits)

Ranked by expected leverage, using this run's `out` and `tool_calls` signal:

1. **DR prompt — highest priority.** `out=59,258` (40% of this run's total
   output) with only 42 tool_calls is the clearest signal of a
   verbosity-not-verification cost driver. Tighten DR's review-report
   template toward more structured/compact output (tables over prose,
   pointer-to-diff instead of reproducing diff content, cap narrative
   sections). Expected to be the single largest token-reduction opportunity
   in the resumed-stage set.
2. **SR — verify fold is actually happening.** Per state.json,
   `skipped_stages` says SR was folded into DR/DV review + a live `sr.txt`
   prompt, yet SR appears as a fully separate 23.1%-of-cost stage in this
   record with its own fresh_in/cache_creation/out. Either (a) the "folded"
   description is stale/inaccurate and SR is genuinely a full stage this
   run, or (b) SR is redundantly re-doing work DR already covered. PE should
   clarify with AR/TL artifacts which is true — if (b), this is a
   double-payment opportunity, not just a prompt-tightening one.
3. **QA tool_calls — investigate for redundant reads, not necessarily bad.**
   85 tool_calls against only 21,580 out tokens suggests QA is
   read/verification-heavy rather than verbose, which is directionally
   correct for a QA stage, but PE should sample the actual transcript to
   confirm calls aren't re-reading the same files multiple times (the
   Diff-Only Read Rule exists precisely to prevent this class of waste).
4. **DC fresh_in creep (82→44→176 across 3 samples)** — small absolute
   numbers, low priority, but worth a one-line prompt check: is DC re-reading
   full files it already has cached context for, on this run specifically?
5. **Harness-side, not prompt-side:** implement the incremental
   per-stage record-write fix (Data gaps section) before the next live run —
   without it, PE's next optimization pass will face the same PL/AR/TL/DV
   blind spot, undermining any claim about total-pipeline token reduction.

## Verdict

**Conditional go for PE stage consumption.**

- The 6 measured stages (DR/SR/QA/DC/FN/ST) are real, non-partial data
  (record shows no truncation for these stages) and usable as-is for
  prompt-tightening decisions on those specific stages — DR, SR, and QA in
  particular have clear, actionable signal (see Recommendations 1–3).
- **Go is conditional on PE explicitly scoping its phase-6 edits to the 6
  measured stages only.** PE must NOT claim any full-pipeline token-reduction
  result from this run — PL/AR/TL/DV are unmeasured, and per token-findings-2's
  own precedent, single-run deltas are noisy even where data exists. Frame
  phase-6 outputs as "informed by run-3's DR/SR/QA/DC/FN/ST signal," not as
  a validated full-pipeline win/loss.
- The generated-app quality gate is clean (38/38 local, 48/48 deterministic
  x3, zero regressions) — no blocker to PE proceeding on the code side.
- The P2 harness finding (incremental persistence) should be filed as a
  parallel/follow-up worktask, not a blocker to PE, since it does not affect
  the validity of the 6 stages that WERE captured.

---

## Related

- token-findings-1.md — foundational cache_read dominance findings (run 1)
- token-findings-2.md — baseline-vs-post lever A/B, honest mixed-result
  conclusion, proposed N-run variance study (still unactioned as of this run)
- `.context/errors/qa-engineer.md` — QA[2] P1 temp-dir leak finding (harness)
- `benchmark/results/runs/live/live-20260706T142415Z-f563b5c.json` — source record
- `benchmark/results/runs/deterministic/deterministic-20260706T0{72557,73412,75048}Z-*.json` — deterministic parity records referenced in Generated app verification
