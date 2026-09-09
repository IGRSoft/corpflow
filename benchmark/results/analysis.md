# Benchmark Analysis — live-20260909T152543Z-9d407c5 (live)

_as of 2026-09-09T15:25:44Z_

## totals

| metric | WITH | WITHOUT | Δ | premium % |
|---|---|---|---|---|
| tokens total | 217503 | 177284 | 40219 | 22.7% |
| cost (USD) | 19.79 | 20.56 | -0.77 | -3.8% |

## per-stage

| stage | arm | cost (USD) | cost share % | out tokens | out share % | cache-hit % | tool calls |
|---|---|---|---|---|---|---|---|
| PL | with | 3.05 | 7.6% | 31782 | 8.1% | 96.2% | 41 |
| AR | with | 2.01 | 5.0% | 25249 | 6.4% | 91.9% | 14 |
| TL | with | 0.24 | 0.6% | 4412 | 1.1% | 86.2% | 8 |
| DV | with | 8.46 | 21.0% | 88559 | 22.5% | 97.5% | 52 |
| DR | with | 1.90 | 4.7% | 20151 | 5.1% | 92.2% | 27 |
| SR | with | 2.20 | 5.4% | 16812 | 4.3% | 93.5% | 28 |
| QA | with | 0.95 | 2.4% | 14638 | 3.7% | 96.1% | 31 |
| DC | with | 0.11 | 0.3% | 4581 | 1.2% | 93.0% | 18 |
| FN | with | 0.33 | 0.8% | 6086 | 1.5% | 90.1% | 12 |
| ST | with | 0.53 | 1.3% | 4658 | 1.2% | 81.0% | 10 |
| PL | without | 1.01 | 2.5% | 6751 | 1.7% | 77.5% | 3 |
| AR | without | 1.64 | 4.1% | 19890 | 5.1% | 83.1% | 5 |
| TL | without | 0.53 | 1.3% | 5887 | 1.5% | 85.3% | 5 |
| DV | without | 9.86 | 24.4% | 93735 | 23.8% | 98.0% | 63 |
| DR | without | 3.10 | 7.7% | 21503 | 5.5% | 94.1% | 20 |
| SR | without | 2.54 | 6.3% | 8266 | 2.1% | 87.9% | 14 |
| QA | without | 0.55 | 1.4% | 3634 | 0.9% | 92.3% | 10 |
| DC | without | 0.30 | 0.7% | 10317 | 2.6% | 94.6% | 18 |
| FN | without | 0.65 | 1.6% | 5309 | 1.3% | 93.1% | 13 |
| ST | without | 0.38 | 0.9% | 1567 | 0.4% | 79.5% | 3 |

## paired-tokens

| stage | WITH in | WITH cached-in | WITH out | WITHOUT in | WITHOUT cached-in | WITHOUT out |
|---|---|---|---|---|---|---|
| PL | 84 | 2616037 | 31782 | 8 | 321033 | 6751 |
| AR | 30 | 1082646 | 25249 | 12 | 541790 | 19890 |
| TL | 16 | 274891 | 4412 | 12 | 616592 | 5887 |
| DV | 106 | 8478468 | 88559 | 128 | 10852513 | 93735 |
| DR | 36 | 1117920 | 20151 | 42 | 2424075 | 21503 |
| SR | 38 | 1583145 | 16812 | 30 | 1412619 | 8266 |
| QA | 64 | 2314844 | 14638 | 22 | 1048668 | 3634 |
| DC | 153 | 387767 | 4581 | 137 | 1223950 | 10317 |
| FN | 26 | 474684 | 6086 | 26 | 1288311 | 5309 |
| ST | 22 | 527489 | 4658 | 8 | 367263 | 1567 |

## cache-economics

| stage | arm | cache_creation |
|---|---|---|
| DV | without | 219982 |
| DV | with | 211458 |
| SR | without | 171556 |
| DR | without | 142182 |
| SR | with | 103583 |

## quality-delta

**Held-out oracle** — the arm's binary scored against goldens captured from
`ttt-template`. This is the only quality signal here the arm did not author.

| metric | WITH | WITHOUT |
|---|---|---|
| oracle cases passed | 35/35 (100.0%) | 35/35 (100.0%) |
| ├ specified (contract restated) | 24/24 (100.0%) | 24/24 (100.0%) |
| └ implied (derived from the rules) | 11/11 (100.0%) | 11/11 (100.0%) |
| pass_fail | pass | pass |

`pass_fail` reads the specified tier alone — an arm is not failed for behaviour
nobody described to it. The implied tier is the discriminating signal.

**Self-graded** — the arm wrote both the implementation and these tests, so
a high count is not evidence of correctness.

| metric | WITH | WITHOUT |
|---|---|---|
| test_count (self-written) | 85 | 80 |

**Descriptive only** — size, not quality. More lines for the same feature is
not a better result.

| metric | WITH | WITHOUT |
|---|---|---|
| loc_produced | 2418 | 2003 |
| tokens per LOC | 89.9516 | 88.5092 |

## validity-caveats

- cross-era vs previous run live-20260814T102001Z-cce3984: prompt_contract: 'scripted-cli-v2' vs 'scripted-cli-v3' — token, cost, and quality figures are NOT comparable across this boundary.
- n=1: single-run comparison; treat deltas as directional, not statistically robust.

## improvement-candidates

- [ ] (stage_cost_outlier) PL [with]: cost $3.0495 is 3.11x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) AR [with]: cost $2.0083 is 2.05x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) DV [with]: cost $8.4626 is 8.62x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) DR [with]: cost $1.8959 is 1.93x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) SR [with]: cost $2.1961 is 2.24x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) AR [without]: cost $1.6404 is 1.67x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) DV [without]: cost $9.8601 is 10.04x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) DR [without]: cost $3.1006 is 3.16x the per-stage median ($0.9820)
- [ ] (stage_cost_outlier) SR [without]: cost $2.5429 is 2.59x the per-stage median ($0.9820)
- [ ] (out_token_spike) PL [with]: out-tokens 31782 is 3.42x the per-stage median (9292)
- [ ] (out_token_spike) AR [with]: out-tokens 25249 is 2.72x the per-stage median (9292)
- [ ] (out_token_spike) DV [with]: out-tokens 88559 is 9.53x the per-stage median (9292)
- [ ] (out_token_spike) DR [with]: out-tokens 20151 is 2.17x the per-stage median (9292)
- [ ] (out_token_spike) SR [with]: out-tokens 16812 is 1.81x the per-stage median (9292)
- [ ] (out_token_spike) QA [with]: out-tokens 14638 is 1.58x the per-stage median (9292)
- [ ] (out_token_spike) AR [without]: out-tokens 19890 is 2.14x the per-stage median (9292)
- [ ] (out_token_spike) DV [without]: out-tokens 93735 is 10.09x the per-stage median (9292)
- [ ] (out_token_spike) DR [without]: out-tokens 21503 is 2.31x the per-stage median (9292)
- [ ] (tool_call_spike) PL [with]: 41 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV [with]: 52 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV [without]: 63 tool calls exceeds max(40, 1.5x median) = 40
