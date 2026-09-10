# Variance envelope — first measurement (n=2)

`VARIANCE-STUDY.md` specifies three paired runs. This is **two**, and the reason is
recorded below rather than smoothed over. Everything here is measured; nothing is
projected.

## What was run

Two complete paired runs, same tree, same commit, same era:

| run | run_id | realized |
|---|---|---|
| A | `live-20260910T172219Z-954783e` | $42.32 |
| B | `live-20260910T185926Z-954783e` | $44.12 |

A third run was attempted **first** and is not in the set:
`live-20260910T160618Z-954783e` truncated at 14/20 stages (`live_partial`) after
$32.48. It was not overspend — see § Why n=2, not n=3.

## The measurement

Same-arm spread between two identical runs is the noise floor. The WITH-vs-WITHOUT
delta is the effect. An effect smaller than its floor is not measurable by a single
run.

| metric | WITHOUT A→B | WITH A→B | effect (A) | effect (B) |
|---|---|---|---|---|
| `cost_usd` | **+1.3%** | +6.5% | +31.9% | +38.7% |
| `tokens` | +13.4% | −17.8% | +45.9% | **+5.7%** |
| `loc_produced` | +27.7% | +4.0% | +10.3% | **−10.1%** |
| `test_count` | **+61.8%** | +19.4% | −8.8% | −32.7% |
| `wall_clock_s` | +4.9% | −8.5% | +52.3% | +32.8% |

## What survives its own noise floor

**`cost_usd`, and nothing else.** The WITHOUT arm reproduced to within **1.3%**
across two runs, while the WITH arm cost **+32%** and **+39%** more than its paired
WITHOUT. The effect is an order of magnitude larger than the floor, in the same
direction, in both runs. **The plugin costs roughly a third more to run. That is
quotable.**

Everything else fails:

- **`tokens`** — the effect swings +45.9% → +5.7% between runs whose own arms move
  13–18%. `token-findings-2.md` asked whether a ~0.25% lever could be seen against
  10–20% swings; it cannot, and this is the measurement that says so. **No token
  delta in `token-findings-{1,2,3}.md` is supported by the single run it was taken
  from.**
- **`loc_produced`** — the effect changes sign (+10.3%, −10.1%) while the WITHOUT arm
  alone moves 27.7%. Noise.
- **`test_count`** — the noisiest metric measured: the WITHOUT arm produced 68 tests
  in one run and 110 in the other, **+61.8%**, with no input changed. Any claim that
  one arm tests more than the other needs far more than n=2.
- **`wall_clock_s`** — the effect is large (+52%, +33%) and same-signed, so it may be
  real, but the arms themselves move 5–9% and wall-clock carries the harness's own
  build time. Suggestive, not established.

## The oracle separated nothing, again

Four arm-observations across the two runs: **42/42 every time, `specified` 33/33 and
`implied` 9/9.** The 2026-09-10 tier audit corrected a real mistiering — six cases
whose behaviour the contract had absorbed were sitting in `implied` — and the new
`implied` cases do separate deliberately-wrong mutants, which `test_oracle.py` pins.
They do not separate two runs of the same model following the same contract.

One observation sharpens this: in the truncated run, the WITH arm swept **42/42 after
only 4 of 10 stages** (2174 LOC, 90 tests). The oracle is saturated by DV; the
remaining six stages contribute nothing it can see. `e65a8c1` already concluded the
arms are "functionally equivalent on this surface", and three further runs agree.
**Treat the oracle as a floor that catches a broken arm, not as a quality axis.**

## Why n=2, not n=3

The first run truncated on a budget-gate interaction, not on cost.
`dispatch.py` splits the budget per arm (`per_arm_budget = budget / arms`), and
`RunningTally.reserve()` carries the largest stage seen so far as the floor for every
later stage. After the WITH arm's DV cost $12.35, every subsequent stage — including
a $0.20 DC — demanded $12.35 of headroom:

```
spent $16.32 + max(estimate $2.70, max_stage $12.35) = $28.67 > $25 per-arm
```

The arm died needing about $7 more of real spend, having realized $32.48 of a $50
budget. Raising the budget to $80 (per-arm $40) let runs A and B finish; both then
realized ~$43, comfortably inside the original $50.

That lost run consumed the third sample's budget. At the $200 ceiling and ~$43 a run,
$41.88 remained — under the cost of one more run — so the study stops at n=2 rather
than breach.

**n=2 is a spread, not a distribution.** Two points cannot estimate a standard
deviation or a CV, and nothing here should be quoted as one. What two points *can* do
is establish a lower bound on variability, and that bound is already large enough to
disqualify four of the five metrics. A third run would tighten the floor; it would not
rescue `test_count` from a 62% swing.

## What to do next

1. **Recalibrate `STAGE_EXPECTED_TOKENS`** (`benchmarklive/budget.py`), still derived
   from a single 2026-08-07 record. Three runs of real per-stage cost now exist,
   including the truncated one, whose 14 stages are valid measurements.
2. **Fix the reserve rule** so a heavy DV cannot strand the six cheap stages after it
   — reserve the *next* stage's estimate, not the worst stage seen.
3. **Re-examine `token-findings-{1,2,3}.md`** against this floor. Their directional
   claims were taken at n=1 from a metric that moves 13–18% on its own.
4. **Fix `VARIANCE-STUDY.md`'s precondition.** It requires `git status` clean for the
   whole study, but every run writes `history.json` and `result.html`, so the tree
   cannot stay clean across three runs. The intent is "no source edits mid-study";
   `git_sha` held at `954783e` throughout.
