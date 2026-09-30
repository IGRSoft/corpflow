# Variance envelope

## Era python-2 (n=3)

Three complete paired runs, commit `89500e0`, era `python-2`. WITH = corpflow 4.1.0 +
apple-developer 1.31.0; WITHOUT = plugin-free, isolated config dir. The previous-era
record `live-20260929T204447Z-d8d8392` is **not** in the set and not comparable
(`KNOWN-BAD-RECORDS.md`: WITH loaded the installed plugin, WITHOUT carried 36 plugins).

| run | run_id | WITH | WITHOUT |
|---|---|---|---|
| 1 | `live-20260930T080425Z-89500e0` | $10.99 | $5.52 |
| 2 | `live-20260930T090418Z-89500e0` | $10.72 | $5.96 |
| 3 | `live-20260930T100549Z-89500e0` | $12.57 | $5.17 |

### The measurement

Same method as the n=2 section below: same-arm spread is the floor, the per-run
WITH-vs-WITHOUT delta is the effect. Spread is (max−min)/min across the three runs.

| metric | WITHOUT min–max (spread) | WITH min–max (spread) | effect 1 | effect 2 | effect 3 |
|---|---|---|---|---|---|
| `cost_usd` | 5.17–5.96 (15.4%) | 10.72–12.57 (17.3%) | +99.2% | +79.7% | +143.3% |
| `tokens` (total) | 128,511–148,113 (15.3%) | 172,404–202,974 (17.7%) | +35.7% | **+16.4%** | +57.9% |
| `wall_clock_s` | 1200–1363 (13.6%) | 2267–2690 (18.7%) | +74.8% | +69.3% | +124.1% |
| `loc_produced` | 2077–2254 (8.5%) | 1988–2568 (29.2%) | +1.9% | −11.8% | +23.6% |
| `test_count` | 73–96 (31.5%) | 59–88 (49.2%) | −38.5% | −8.3% | +13.7% |
| oracle `cases_passed` | 42–42 (0%) | 42–42 (0%) | 0 | 0 | 0 |

`coverage_pct` is `null` in every arm; `stage_count` is 10 in every arm.

### What survives its own noise floor

- **`cost_usd` — survives.** Floor 15–17%; every effect is +80% or more, same sign in
  all three runs. The plugin roughly doubles run cost on this workload (+80% to +143%).
- **`wall_clock_s` — survives, with the old caveat.** Floor 14–19%; effects +69% to
  +124%, same sign. Wall-clock still includes harness build time.
- **`tokens` — does not clearly survive.** Same sign in all runs, but the smallest
  effect (+16.4%) sits inside the 15–18% floor. Direction only.
- **`loc_produced`, `test_count` — noise.** Both change sign across runs.
- **Oracle — saturated.** 42/42 in all six arm-runs; it separates nothing.

### What changed versus n=2

- The floor is wider. The python-1 WITHOUT arm reproduced to 1.3%; here it moves
  15.4%. Two points understated it; n=3 is still a spread, not a distribution.
- The cost effect is larger (+80–143% vs +32–39%). The eras differ in harness, plugin
  isolation and plugin version, so this is not a before/after of any single change.

Per-stage cost deltas and their causes: `token-findings-4.md`.

---

The sections below are the python-1 n=2 measurement, kept as history.

## Era python-1 — first measurement (n=2)

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
