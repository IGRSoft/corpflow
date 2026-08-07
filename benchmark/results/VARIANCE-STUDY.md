# Variance study — procedure

`token-findings-2.md` names this as its own top follow-up and it has never been
run; `token-findings-3.md` is another n=1, and partial. Until it exists, every
comparison in this directory is a single sample, and findings-2's own argument
stands: a ~0.25% effect is invisible against swings of 10–20% in metrics the
levers do not control.

**This is the only step in the eval work that spends real money.** Everything
else — the held-out oracle, fail-closed verdicts, era stamping, retention, the
label dataset — runs offline and free.

## Preconditions

1. A credential the gate accepts: an active `claude` login, or `ANTHROPIC_API_KEY`
   (read `benchmark/README.md § Credentials` first — an OAuth-shaped value
   exported as an API key 401s *and* overrides a working login).
2. A **fixed tree** for the whole study: `git status` clean, same `git_sha` for
   every run. A mid-study edit silently creates a new era.
3. `benchmarkkit.rotation.RETENTION["live"]` is unbounded, so no run in the study
   rotates an earlier one away. Confirm before starting.

## Procedure

Three paired runs (each dispatches both arms across all 10 stages):

```bash
for i in 1 2 3; do
  ./benchmark/run-benchmark.sh --live --budget 50.00
done
```

**Sizing.** The one complete arm on record (`live-20260807T114444Z-a0cdb43`,
WITHOUT, 10 stages) attributed **$19.73**, so a paired run needs roughly **$40**
and three runs **~$120**. The pre-flight now projects $39.38 for a paired run and
will decline anything under that, which is the point: the earlier flat per-stage
projection accepted $30 for a run that could not finish, and the run duly
truncated at 4/10 WITH stages.

**`--budget` is not a hard stop.** It bounds what dispatch will start; a stage
already in flight has no ceiling, so realized spend can exceed the cap by one
stage. The run above spent $34.32 against a $30 cap. Budget the study against the
projection with headroom, and record realized spend from the records rather than
assuming the cap held.

Each arm runs under half the budget, so neither can starve the other — the
failure that made that first run an invalid A/B.

If a run returns rc=4, read the partial record from `results/runs/live/` — do not
read granularity from the shell exit, which `run-benchmark.sh` collapses to 1.

## What to compute

For each of `cache_read`, `out`, paid slice (`fresh_in + cache_creation`),
`cost_usd`, and `oracle.tiers.implied.pass_rate`, across the three runs per arm.
Use the implied tier, not the overall rate: the specified tier is a floor both
arms are expected to clear, so its variance is uninformative by design.

| statistic | why |
|---|---|
| mean | the centre to compare future runs against |
| min / max | the observed envelope |
| coefficient of variation (σ/μ) | the noise floor — any claimed effect smaller than this is unmeasurable at n=3 |

Write the result to `benchmark/results/variance-envelope.md`.

## Then re-state the existing findings

Go back through `token-findings-1.md`, `-2.md`, and `-3.md` and mark each
directional claim as **survives** or **inside the noise floor** against the
measured CV. Findings-2 predicts most token-trim claims will land in the second
category; confirming that is a real result, not a failure.

Hold that document's standard: report against the envelope, keep contradictions
intact, and do not spin a negative result positive.

## Honest limits of n=3

Three samples per arm gives a rough envelope, not a confidence interval. It is
enough to answer "is this effect bigger than the noise?" and not enough to
estimate the effect size. Say so in `variance-envelope.md` rather than implying
more precision than three runs can carry.
