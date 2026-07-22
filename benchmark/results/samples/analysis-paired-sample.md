# Benchmark Analysis — live-20260722-sample (live)

_as of 2026-07-22T05:52:34Z_

## totals

| metric | WITH | WITHOUT | Δ | premium % |
|---|---|---|---|---|
| tokens total | 66000 | 62100 | 3900 | 6.3% |
| cost (USD) | 0.8 | 0.71 | 0.09 | 12.7% |

## per-stage

| stage | cost (USD) | cost share % | out tokens | out share % | cache-hit % | tool calls |
|---|---|---|---|---|---|---|
| PL | 0.18 | 11.9% | 3200 | 12.7% | 6.1% | 8 |
| DV | 0.62 | 41.1% | 9800 | 39.0% | 12.7% | 64 |
| PL | 0.16 | 10.6% | 3000 | 12.0% | 0.0% | 6 |
| DV | 0.55 | 36.4% | 9100 | 36.3% | 0.0% | 58 |

## paired-tokens

| stage | WITH in | WITH out | WITHOUT in | WITHOUT out |
|---|---|---|---|---|
| PL | 12000 | 3200 | 11000 | 3000 |
| DV | 41000 | 9800 | 39000 | 9100 |

## cache-economics

| stage | cache_creation |
|---|---|
| DV | 900 |
| PL | 400 |

## quality-delta

| metric | WITH | WITHOUT |
|---|---|---|
| loc_produced | 165 | 91 |
| test_count | 12 | 9 |
| pass_fail | pass | pass |
| tokens per LOC | 400 | 682.4176 |

## validity-caveats

- cross-era record: token payload predates cache_read/cache_creation tracking; cache-hit and cache-economics figures are unavailable for the affected arm.
- n=1: single-run comparison; treat deltas as directional, not statistically robust.

## generated-project

### with arm — `/var/folders/rs/7nnkz5qd7csgpv7crrqgt5p40000gp/T/sample-apxg9h_8/workdirs/live-20260722-sample/with`
_total LOC: 165_

| file | LOC |
|---|---|
| Sources/TicTacToeKit/AIOpponent.swift | 68 |
| Sources/TicTacToeKit/Board.swift | 42 |
| Sources/TicTacToeKit/GameViewModel.swift | 55 |

### without arm — `/var/folders/rs/7nnkz5qd7csgpv7crrqgt5p40000gp/T/sample-apxg9h_8/workdirs/live-20260722-sample/without`
_total LOC: 91_

| file | LOC |
|---|---|
| Sources/TicTacToeKit/AIOpponent.swift | 51 |
| Sources/TicTacToeKit/Board.swift | 40 |


## improvement-candidates

- [ ] (stage_cost_outlier) DV: cost $0.6200 is 1.70x the per-stage median ($0.3650)
- [ ] (stage_cost_outlier) DV: cost $0.5500 is 1.51x the per-stage median ($0.3650)
- [ ] (out_token_spike) DV: out-tokens 9800 is 1.59x the per-stage median (6150)
- [ ] (tool_call_spike) DV: 64 tool calls exceeds max(40, 1.5x median) = 50
- [ ] (tool_call_spike) DV: 58 tool calls exceeds max(40, 1.5x median) = 50
- [ ] (background_nested_spawn) DV: 2 nested background subagent spawn(s) recorded
