# Benchmark Analysis — live-20260722T123755Z-5790adb (live)

_as of 2026-07-22T12:38:04Z_

## totals

| metric | WITH | WITHOUT | Δ | premium % |
|---|---|---|---|---|
| tokens total | 238530 | 160839 | 77691 | 48.3% |
| cost (USD) | 25.5058 | 14.7538 | 10.752 | 72.9% |

## per-stage

| stage | arm | cost (USD) | cost share % | out tokens | out share % | cache-hit % | tool calls |
|---|---|---|---|---|---|---|---|
| PL | with | 2.2169 | 5.5% | 28405 | 7.3% | 94.6% | 30 |
| AR | with | 5.3575 | 13.3% | 22944 | 5.9% | 90.9% | 47 |
| TL | with | 0.5375 | 1.3% | 8263 | 2.1% | 84.9% | 13 |
| DV | with | 12.7524 | 31.7% | 122157 | 31.3% | 97.8% | 123 |
| DR | with | 1.971 | 4.9% | 17428 | 4.5% | 89.3% | 27 |
| SR | with | 1.0884 | 2.7% | 12947 | 3.3% | 90.3% | 29 |
| QA | with | 0.8718 | 2.2% | 9486 | 2.4% | 90.5% | 30 |
| DC | with | 0.1189 | 0.3% | 3405 | 0.9% | 84.5% | 9 |
| FN | with | 0.2903 | 0.7% | 5286 | 1.4% | 80.1% | 7 |
| ST | with | 0.301 | 0.7% | 5987 | 1.5% | 81.4% | 11 |
| PL | without | 0.9409 | 2.3% | 8774 | 2.2% | 77.7% | 3 |
| AR | without | 1.5728 | 3.9% | 21451 | 5.5% | 82.6% | 6 |
| TL | without | 0.4604 | 1.1% | 6422 | 1.6% | 85.8% | 6 |
| DV | without | 6.5489 | 16.3% | 77429 | 19.8% | 97.2% | 67 |
| DR | without | 1.9544 | 4.9% | 14777 | 3.8% | 90.6% | 13 |
| SR | without | 1.726 | 4.3% | 10037 | 2.6% | 88.4% | 14 |
| QA | without | 0.5974 | 1.5% | 4925 | 1.3% | 93.7% | 13 |
| DC | without | 0.2093 | 0.5% | 3762 | 1.0% | 85.1% | 11 |
| FN | without | 0.4276 | 1.1% | 4038 | 1.0% | 88.5% | 6 |
| ST | without | 0.3162 | 0.8% | 2207 | 0.6% | 88.0% | 5 |

## paired-tokens

| stage | WITH in | WITH cached-in | WITH out | WITHOUT in | WITHOUT cached-in | WITHOUT out |
|---|---|---|---|---|---|---|
| PL | 45 | 1312595 | 28405 | 8 | 275125 | 8774 |
| AR | 10 | 415199 | 22944 | 6804 | 488755 | 21451 |
| TL | 11 | 356102 | 8263 | 7 | 327078 | 6422 |
| DV | 1790 | 13638225 | 122157 | 74 | 5989394 | 77429 |
| DR | 32 | 1013235 | 17428 | 23 | 1133315 | 14777 |
| SR | 28 | 538498 | 12947 | 19 | 920883 | 10037 |
| QA | 123 | 863553 | 9486 | 15 | 793406 | 4925 |
| DC | 54 | 255724 | 3405 | 52 | 494440 | 3762 |
| FN | 120 | 146432 | 5286 | 8 | 382695 | 4038 |
| ST | 9 | 154273 | 5987 | 7 | 286259 | 2207 |

## cache-economics

| stage | arm | cache_creation |
|---|---|---|
| DV | with | 302007 |
| DV | without | 170183 |
| DR | with | 108120 |
| DR | without | 107031 |
| SR | without | 106651 |

## quality-delta

**Held-out oracle** — the arm's binary scored against goldens captured from
`ttt-template`. This is the only quality signal here the arm did not author.

| metric | WITH | WITHOUT |
|---|---|---|
| oracle cases passed | not measured | not measured |
| pass_fail | pass | pass |

`pass_fail` reads the specified tier alone — an arm is not failed for behaviour
nobody described to it. The implied tier is the discriminating signal.

**Self-graded** — the arm wrote both the implementation and these tests, so
a high count is not evidence of correctness.

| metric | WITH | WITHOUT |
|---|---|---|
| test_count (self-written) | 67 | 67 |
| coverage % | 0.0% | 0.0% |

**Descriptive only** — size, not quality. More lines for the same feature is
not a better result.

| metric | WITH | WITHOUT |
|---|---|---|
| loc_produced | 2213 | 1751 |
| tokens per LOC | 107.7858 | 91.8555 |

## validity-caveats

- unstamped record: no era block, so comparability against other records cannot be verified — re-run to stamp harness, prompt contract, and model pins.
- cross-era vs previous run live-20260721T190044Z-9bd7a47: era-unstamped — token, cost, and quality figures are NOT comparable across this boundary.
- n=1: single-run comparison; treat deltas as directional, not statistically robust.

## improvement-candidates

- [ ] (stage_cost_outlier) PL [with]: cost $2.2169 is 2.45x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) AR [with]: cost $5.3575 is 5.91x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DV [with]: cost $12.7524 is 14.07x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DR [with]: cost $1.9710 is 2.17x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) AR [without]: cost $1.5728 is 1.74x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DV [without]: cost $6.5489 is 7.23x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) DR [without]: cost $1.9544 is 2.16x the per-stage median ($0.9063)
- [ ] (stage_cost_outlier) SR [without]: cost $1.7260 is 1.90x the per-stage median ($0.9063)
- [ ] (out_token_spike) PL [with]: out-tokens 28405 is 3.11x the per-stage median (9130)
- [ ] (out_token_spike) AR [with]: out-tokens 22944 is 2.51x the per-stage median (9130)
- [ ] (out_token_spike) DV [with]: out-tokens 122157 is 13.38x the per-stage median (9130)
- [ ] (out_token_spike) DR [with]: out-tokens 17428 is 1.91x the per-stage median (9130)
- [ ] (out_token_spike) AR [without]: out-tokens 21451 is 2.35x the per-stage median (9130)
- [ ] (out_token_spike) DV [without]: out-tokens 77429 is 8.48x the per-stage median (9130)
- [ ] (out_token_spike) DR [without]: out-tokens 14777 is 1.62x the per-stage median (9130)
- [ ] (tool_call_spike) AR [with]: 47 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV [with]: 123 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV [without]: 67 tool calls exceeds max(40, 1.5x median) = 40
