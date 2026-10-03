# Token-attribution findings — era python-3, `scripted-cli-v4`, n=3 (69a0947)

**Status:** three complete paired live runs, one workload (TicTacToe), one commit.
**Scope:** the effect of the premium-reduction plan (`69a0947`: AR consult gate, one-call
ledger writes, smaller DV prefix, inline PL/DR/SR runbooks, SR/QA Task lists, the DV→QA
acceptance-command guard) against the `c638dc2` baseline, and what still drives the premium.

## Data source

- Records: `benchmark/results/runs/live/live-20261001T{075458,085738,104654}Z-69a0947.json`
- Transcripts: `benchmark/workdirs/<run_id>/captures/{with,without}-<STAGE>.jsonl`
- Baseline: `c638dc2`, python-3, WITH $11.74 vs WITHOUT $6.30 mean (+86%), run 1 WITH 13/42.
  The prompt contract moved `scripted-cli-v3` → `v4` (`pl.txt` gained the CLI contract), so
  the pairing gate refuses mixed pairs; the comparison here is by hand.
- Run 2's WITH cost misses an interrupted DV attempt ($2.56): `KNOWN-BAD-RECORDS.md`.
- Noise floor: `variance-envelope.md § Era python-3, scripted-cli-v4 (n=3)`.

## Run totals

| run | WITH | WITHOUT | cost premium | oracle W / WO |
|---|---:|---:|---:|---|
| 1 `075458` | $10.17 | $6.58 | +54.7% | 42/42 / 42/42 |
| 2 `085738` | $7.49 (≈$10.05 spent) | $7.10 | +5.6% (≈+41.5%) | 42/42 / 42/42 |
| 3 `104654` | $9.81 | $6.23 | +57.4% | 42/42 / 42/42 |
| mean | $9.16 (≈$10.01) | $6.64 | +38% (≈+51%) | |

Plan target was mean WITH ≤ $9.45 (≤50%) with 42/42 everywhere: met as recorded, missed by
≈$0.56 once run 2's dropped spend is counted. Quality held: 42/42 in every arm, where
`c638dc2` run 1 scored 13/42.

## Per-stage cost (mean, USD)

| Stage | WITH | WITHOUT | Δ now | Δ at `c638dc2` | runs (Δ) |
|---|---:|---:|---:|---:|---|
| PL | 0.93 | 0.52 | +0.41 | +0.81 | +0.47 / +0.31 / +0.46 |
| AR | 1.56 | 1.06 | +0.50 | +1.70 | +0.35 / +0.56 / +0.59 |
| DV | 3.50 | 3.20 | +0.30 | +1.57 | +0.76 / −1.12* / +1.28 |
| DR | 1.13 | 0.69 | +0.44 | +0.67 | +0.42 / +0.44 / +0.45 |
| SR | 1.26 | 0.60 | +0.66 | +0.48 | +1.31 / +0.06 / +0.60 |
| rest (TL QA DC FN ST) | 0.77 | 0.57 | +0.20 | +0.19 | |

\* run 2's interrupted DV attempt is missing; excluding run 2, DV Δ ≈ +1.02.

## What the plan bought

- **AR −$1.20 of Δ.** Run 1 scored 20 and skipped the consult (`consult: skipped, score 20`).
  Runs 2–3 scored 22, just over the ≥21 gate, and consulted on Sonnet with a capped return:
  Δ +0.56/+0.59, against +1.70 for an xhigh Opus-tier sibling consult at `c638dc2`.
- **PL −$0.40.** 10 / 10 / 15 turns, against 17.7 at `c638dc2`; the runbook replaced the
  `pl0-procedure.md` read.
- **DR −$0.23.** Same direction, still 15–21 turns.
- **DV: the delegation contract held.** No DV run delegated (0 `Task`/`Agent` calls), and
  every oracle case passed. DV's own cost spread (Δ +0.76 to +1.28 in the clean runs) is the
  largest single variance source and needs per-turn attribution before another lever.

## What still drives the premium

1. **SR sibling consult rejected twice (+$0.6–1.3 in runs 1 and 3).** SR dispatched
   `apple-developer:security-auditor` twice per run; both returns failed
   `validate-consultant-return.sh` (`severity_counts` absent, then wrong keys) because
   apple-developer's `CORPFLOW.md` defines no `consultant-return.v1` fence. SR then ended
   `verdict: blocked` and reviewed the Apple domains itself. Run 2 did not consult: Δ +0.06.
   Fix in two places: apple-developer's `CORPFLOW.md` must carry the fence (sibling repo),
   and SR needs a consult gate like AR's so a Medium-complexity diff never pays for one.
2. **The AR gate sits on this workload's score.** With the contract now in `pl.txt`, PL
   scores the task 20–22 instead of 16–20, so the ≥21 floor opens in 2 of 3 runs. Raising
   it to the High tier (≥31) or to explicit triggers only would save ≈$0.4/run here; the
   quality risk is unmeasured because WITHOUT never consults and still scores 42/42.
3. **DR 15–21 turns, PL 10–15.** Both above the plan's PL ≤8 / DR ≤11 targets.

## Measurement defect found

The usage-limit retry (`benchmarklive/usage_limit.py`) re-dispatches the stage but drops the
failed attempt's spend from the record. Since fixed: the interrupted
attempt's usage is folded into the re-dispatched stage (`dispatch.fold_interrupted`).
