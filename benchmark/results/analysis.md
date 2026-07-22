# Benchmark Analysis — live-20260722T123755Z-5790adb (live)

_as of 2026-07-22T12:38:04Z_

## totals

| metric | WITH | WITHOUT | Δ | premium % |
|---|---|---|---|---|
| tokens total | 238530 | 160839 | 77691 | 48.3% |
| cost (USD) | 25.5058 | 14.7538 | 10.752 | 72.9% |

## per-stage

| stage | cost (USD) | cost share % | out tokens | out share % | cache-hit % | tool calls |
|---|---|---|---|---|---|---|
| PL | 2.2169 | 5.5% | 28405 | 7.3% | 94.6% | 30 |
| AR | 5.3575 | 13.3% | 22944 | 5.9% | 90.9% | 47 |
| TL | 0.5375 | 1.3% | 8263 | 2.1% | 84.9% | 13 |
| DV | 12.7524 | 31.7% | 122157 | 31.3% | 97.8% | 123 |
| DR | 1.971 | 4.9% | 17428 | 4.5% | 89.3% | 27 |
| SR | 1.0884 | 2.7% | 12947 | 3.3% | 90.3% | 29 |
| QA | 0.8718 | 2.2% | 9486 | 2.4% | 90.5% | 30 |
| DC | 0.1189 | 0.3% | 3405 | 0.9% | 84.5% | 9 |
| FN | 0.2903 | 0.7% | 5286 | 1.4% | 80.1% | 7 |
| ST | 0.301 | 0.7% | 5987 | 1.5% | 81.4% | 11 |
| PL | 0.9409 | 2.3% | 8774 | 2.2% | 77.7% | 3 |
| AR | 1.5728 | 3.9% | 21451 | 5.5% | 82.6% | 6 |
| TL | 0.4604 | 1.1% | 6422 | 1.6% | 85.8% | 6 |
| DV | 6.5489 | 16.3% | 77429 | 19.8% | 97.2% | 67 |
| DR | 1.9544 | 4.9% | 14777 | 3.8% | 90.6% | 13 |
| SR | 1.726 | 4.3% | 10037 | 2.6% | 88.4% | 14 |
| QA | 0.5974 | 1.5% | 4925 | 1.3% | 93.7% | 13 |
| DC | 0.2093 | 0.5% | 3762 | 1.0% | 85.1% | 11 |
| FN | 0.4276 | 1.1% | 4038 | 1.0% | 88.5% | 6 |
| ST | 0.3162 | 0.8% | 2207 | 0.6% | 88.0% | 5 |

## paired-tokens

| stage | WITH in | WITH out | WITHOUT in | WITHOUT out |
|---|---|---|---|---|
| PL | 45 | 28405 | 8 | 8774 |
| AR | 10 | 22944 | 6804 | 21451 |
| TL | 11 | 8263 | 7 | 6422 |
| DV | 1790 | 122157 | 74 | 77429 |
| DR | 32 | 17428 | 23 | 14777 |
| SR | 28 | 12947 | 19 | 10037 |
| QA | 123 | 9486 | 15 | 4925 |
| DC | 54 | 3405 | 52 | 3762 |
| FN | 120 | 5286 | 8 | 4038 |
| ST | 9 | 5987 | 7 | 2207 |

## cache-economics

| stage | cache_creation |
|---|---|
| DV | 302007 |
| DV | 170183 |
| DR | 108120 |
| DR | 107031 |
| SR | 106651 |

## quality-delta

| metric | WITH | WITHOUT |
|---|---|---|
| loc_produced | 2213 | 1751 |
| test_count | 67 | 67 |
| pass_fail | pass | pass |
| tokens per LOC | 107.7858 | 91.8555 |

## validity-caveats

- n=1: single-run comparison; treat deltas as directional, not statistically robust.

## improvement-candidates

- [ ] (stage_cost_outlier) PL: cost $2.2169 is 2.45x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) AR: cost $5.3575 is 5.91x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DV: cost $12.7524 is 14.07x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DR: cost $1.9710 is 2.17x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) AR: cost $1.5728 is 1.74x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DV: cost $6.5489 is 7.23x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DR: cost $1.9544 is 2.16x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) SR: cost $1.7260 is 1.90x the per-stage median ($0.9063)
- [ ] (out_token_spike) PL: out-tokens 28405 is 3.11x the per-stage median (9130)
- [ ] (out_token_spike) AR: out-tokens 22944 is 2.51x the per-stage median (9130)
- [ ] (out_token_spike) DV: out-tokens 122157 is 13.38x the per-stage median (9130)
- [ ] (out_token_spike) DR: out-tokens 17428 is 1.91x the per-stage median (9130)
- [ ] (out_token_spike) AR: out-tokens 21451 is 2.35x the per-stage median (9130)
- [ ] (out_token_spike) DV: out-tokens 77429 is 8.48x the per-stage median (9130)
- [ ] (out_token_spike) DR: out-tokens 14777 is 1.62x the per-stage median (9130)
- [ ] (tool_call_spike) AR: 47 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV: 123 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV: 67 tool calls exceeds max(40, 1.5x median) = 40
