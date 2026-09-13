# Benchmark Analysis — live-20260910T185926Z-954783e (live)

_as of 2026-09-10T18:59:27Z_

## totals

| metric | WITH | WITHOUT | Δ | premium % |
|---|---|---|---|---|
| tokens total | 194109 | 183647 | 10462 | 5.7% |
| cost (USD) | 25.63 | 18.48 | 7.15 | 38.7% |

## per-stage

| stage | arm | cost (USD) | cost share % | out tokens | out share % | cache-hit % | tool calls |
|---|---|---|---|---|---|---|---|
| PL | with | 2.42 | 5.5% | 26829 | 7.1% | 95.2% | 37 |
| AR | with | 5.72 | 13.0% | 596 | 0.2% | 97.3% | 40 |
| TL | with | 0.30 | 0.7% | 5543 | 1.5% | 88.7% | 9 |
| DV | with | 10.75 | 24.4% | 97509 | 25.9% | 98.0% | 66 |
| DR | with | 2.06 | 4.7% | 20559 | 5.5% | 92.9% | 29 |
| SR | with | 2.68 | 6.1% | 18594 | 4.9% | 96.0% | 34 |
| QA | with | 0.62 | 1.4% | 7310 | 1.9% | 93.7% | 17 |
| DC | with | 0.12 | 0.3% | 5119 | 1.4% | 89.2% | 11 |
| FN | with | 0.28 | 0.6% | 4971 | 1.3% | 91.1% | 12 |
| ST | with | 0.70 | 1.6% | 6554 | 1.7% | 88.9% | 18 |
| PL | without | 1.35 | 3.1% | 12456 | 3.3% | 86.4% | 6 |
| AR | without | 2.17 | 4.9% | 27595 | 7.3% | 90.7% | 10 |
| TL | without | 0.52 | 1.2% | 3714 | 1.0% | 81.1% | 4 |
| DV | without | 8.35 | 18.9% | 88870 | 23.6% | 97.8% | 57 |
| DR | without | 2.71 | 6.1% | 20433 | 5.4% | 92.3% | 19 |
| SR | without | 1.77 | 4.0% | 10767 | 2.9% | 89.3% | 15 |
| QA | without | 0.59 | 1.3% | 4652 | 1.2% | 92.4% | 10 |
| DC | without | 0.25 | 0.6% | 10296 | 2.7% | 87.1% | 10 |
| FN | without | 0.39 | 0.9% | 2662 | 0.7% | 80.3% | 3 |
| ST | without | 0.40 | 0.9% | 1885 | 0.5% | 83.5% | 4 |

## paired-tokens

| stage | WITH in | WITH cached-in | WITH out | WITHOUT in | WITHOUT cached-in | WITHOUT out |
|---|---|---|---|---|---|---|
| PL | 64 | 1828923 | 26829 | 14 | 577478 | 12456 |
| AR | 2 | 122835 | 596 | 22 | 1068734 | 27595 |
| TL | 20 | 384859 | 5543 | 10 | 521549 | 3714 |
| DV | 134 | 12061386 | 97509 | 116 | 8615074 | 88870 |
| DR | 38 | 1309708 | 20559 | 30 | 1787120 | 20433 |
| SR | 70 | 2522127 | 18594 | 20 | 990780 | 10767 |
| QA | 36 | 1232160 | 7310 | 22 | 1106496 | 4652 |
| DC | 97 | 301439 | 5119 | 65 | 561402 | 10296 |
| FN | 26 | 426181 | 4971 | 8 | 380486 | 2662 |
| ST | 38 | 1021133 | 6554 | 10 | 457075 | 1885 |

## cache-economics

| stage | arm | cache_creation |
|---|---|---|
| DV | with | 240268 |
| DV | without | 191889 |
| DR | without | 137501 |
| ST | with | 112888 |
| SR | without | 105552 |

## quality-delta

**Held-out oracle** — the arm's binary scored against goldens captured from
`ttt-template`. This is the only quality signal here the arm did not author.

| metric | WITH | WITHOUT |
|---|---|---|
| oracle cases passed | 42/42 (100.0%) | 42/42 (100.0%) |
| ├ specified (contract restated) | 33/33 (100.0%) | 33/33 (100.0%) |
| └ implied (derived from the rules) | 9/9 (100.0%) | 9/9 (100.0%) |
| pass_fail | pass | pass |

`pass_fail` reads the specified tier alone — an arm is not failed for behaviour
nobody described to it. The implied tier is the discriminating signal.

**Self-graded** — the arm wrote both the implementation and these tests, so
a high count is not evidence of correctness.

| metric | WITH | WITHOUT |
|---|---|---|
| test_count (self-written) | 74 | 110 |

**Descriptive only** — size, not quality. More lines for the same feature is
not a better result.

| metric | WITH | WITHOUT |
|---|---|---|
| loc_produced | 2242 | 2495 |
| tokens per LOC | 86.5785 | 73.606 |

## validity-caveats

- n=1: single-run comparison; treat deltas as directional, not statistically robust.

## improvement-candidates

- [ ] (stage_cost_outlier) PL [with]: cost $2.4180 is 2.36x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) AR [with]: cost $5.7236 is 5.60x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) DV [with]: cost $10.7516 is 10.51x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) DR [with]: cost $2.0558 is 2.01x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) SR [with]: cost $2.6769 is 2.62x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) AR [without]: cost $2.1704 is 2.12x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) DV [without]: cost $8.3528 is 8.17x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) DR [without]: cost $2.7108 is 2.65x the per-stage median ($1.0226)
- [ ] (stage_cost_outlier) SR [without]: cost $1.7674 is 1.73x the per-stage median ($1.0226)
- [ ] (out_token_spike) PL [with]: out-tokens 26829 is 3.05x the per-stage median (8803)
- [ ] (out_token_spike) DV [with]: out-tokens 97509 is 11.08x the per-stage median (8803)
- [ ] (out_token_spike) DR [with]: out-tokens 20559 is 2.34x the per-stage median (8803)
- [ ] (out_token_spike) SR [with]: out-tokens 18594 is 2.11x the per-stage median (8803)
- [ ] (out_token_spike) AR [without]: out-tokens 27595 is 3.13x the per-stage median (8803)
- [ ] (out_token_spike) DV [without]: out-tokens 88870 is 10.10x the per-stage median (8803)
- [ ] (out_token_spike) DR [without]: out-tokens 20433 is 2.32x the per-stage median (8803)
- [ ] (tool_call_spike) DV [with]: 66 tool calls exceeds max(40, 1.5x median) = 40
- [ ] (tool_call_spike) DV [without]: 57 tool calls exceeds max(40, 1.5x median) = 40
