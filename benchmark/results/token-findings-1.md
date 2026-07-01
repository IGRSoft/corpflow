# Token-attribution findings — WITH-path cache-read vs fresh, per stage (run 1)

**Status:** directional (n=1 live sample). **Scope:** offline analysis only — no live
re-measurement was performed (that requires real API spend and is deferred to a
`/worktask --secure` follow-up). All figures below were **recomputed by DV** from the
raw `usage` objects on disk, not copied from the PL/AR handoffs.

## Evidence files (recomputed, not copied)

- Per-stage source: `.context/live-ab/{with1_estimate,with2_create,with3_test}.json`
  — three real `claude agents run --output-format json` captures with `usage` objects
  carrying `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
  `output_tokens`.
- On-disk retained record: `benchmark/results/history.json` `live[0]`
  (`run_id=live-20260701T074319Z-69c430f`): `tokens.in=574557`, `tokens.out=7329`,
  `tokens.total=581886`, **no** cache fields.

## Binding interpretation note

The Anthropic `usage` object reports `input_tokens` as the **fresh, uncached** input.
`cache_read_input_tokens` and `cache_creation_input_tokens` are **separate, additive**
counts — NOT inclusive of `input_tokens`. Therefore:

```
total input = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
```

The two samples are **distinct runs** and must not be conflated: the `.context/live-ab`
3-stage WITH capture totals **915,290** input tokens, whereas the on-disk retained live
record's `tokens.in=574557` is a **different, older n=1 sample**. This findings report is
grounded in the `live-ab` capture; the on-disk record is cited only to show the retained
schema predates cache attribution (it renders with em-dash for the cache-derived rows).

## Recomputed per-stage breakdown (from live-ab)

| stage | fresh `input_tokens` | `cache_creation` | `cache_read` | `output` | stage total input | cache_read % of stage input |
|---|---:|---:|---:|---:|---:|---:|
| with1_estimate | 33,482 | 11,639 | 23,022 | 997 | 68,143 | 33.78% |
| with2_create | 37,652 | 56,772 | 207,310 | 4,227 | 301,734 | 68.71% |
| with3_test | 37,458 | 60,683 | 447,272 | 7,936 | 545,413 | 82.01% |
| **WITH total** | **108,592** | **129,094** | **677,604** | **13,160** | **915,290** | **74.03%** |

## Headline numbers (recomputed)

- **cache_read is the sink: 677,604 tokens = 74.03% of all WITH-path input.**
- Fresh (paid at full rate): 108,592 = **11.86%**.
- cache_creation (paid, cache write): 129,094 = **14.10%**.
- **PAID input (fresh + cache_creation) = 237,686 = 25.97%** of total input.
- **cache-hit % (cache_read / total input) = 74.03%.**
- Output: 13,160 tokens.
- Per-stage `cache_read` share climbs **monotonically: 33.78% → 68.71% → 82.01%** as
  context accumulates across the pipeline.

## The biggest token sinks (ranked)

1. **cache_read (~74%)** — re-reading accumulated context. Billed at roughly a tenth of
   the fresh rate, so it dominates the raw token count far more than it dominates spend.
2. **PAID input (~26% = fresh 11.9% + cache_creation 14.1%)** — this is what actually
   costs near-full rate; it is where reduction effort pays off.
3. **Monotonic per-stage cache_read climb (33.8% → 68.7% → 82.0%)** — later stages
   inherit and re-read every earlier stage's context; the test stage alone re-reads
   447,272 cached tokens.

## Reframed reduction target

The raw input:output ratio (≈78:1 on the retained record; ≈70:1 here, 915,290 / 13,160)
**overstates paid spend ~4x**, because ~74% of "input" is cheap cache_read. The correct
target is **NOT "slash total input"** but:

- **Stabilize / reuse cache prefixes** so cache_read stays a cache HIT rather than forcing
  fresh re-encoding (cache misses convert cheap cache_read into expensive fresh input).
- **Trim what the high-share late stages send FRESH** (the 26% paid slice), since the
  create/test stages carry the largest absolute fresh + cache_creation counts.

Both reductions require a **fresh live re-measurement to validate** — deferred to a
`/worktask --secure` follow-up. Nothing in this run re-runs the live pipeline.

## Confidence

n=1, directional. A single 3-stage WITH capture; no statistical rigor beyond one sample.
The direction (cache_read dominates, climbs per stage, paid input is ~1/4 of the raw
count) is unambiguous in the data, but the exact percentages should be re-measured before
being used for cost projection.
