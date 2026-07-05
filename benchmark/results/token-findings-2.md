# Token-attribution findings — Live A/B baseline vs post-trim measurement (run 2)

**Status:** mixed result, n=1 per arm, reported honestly without spin. **Scope:** two full
live 10-stage pipeline runs with per-stage token attribution (fresh, cache_creation,
cache_read, output, paid slice = fresh + cache_creation). Baseline captures the
production cache-prefix layout for the first time (Batch 1 preamble-fidelity fix); post
run applies all token-trim levers (Batch 3 cache-lint L1/L2/L3, Batch 5 agent/skill
dedup).

> **Quick recap:** token-findings-1.md (run 1) showed cache_read dominates input
> (74%), and paid slice is ~26% of raw input. This document compares a fresh
> baseline (with assembled cache-prefix sections) against a post-trim version. See
> the linked development-0.md sections for the full honest measurement conclusion.

## Baseline live record

**File:** `benchmark/results/runs/live/live-20260705T151539Z-779a9e8.json` (run 1, 10/10 stages, non-partial, $10.32 attributed)

- First baseline in repo history to measure ASSEMBLED [1][2][3][4][5] cache-prefix
  layout (production preamble + state-json + stage-contract), not bare flat prompts.
- Per-stage cache-hit range: 76.0% – 93.1%

**Per-stage paid-slice summary (fresh_in + cache_creation):**

| Stage | fresh_in | cache_creation | cache_read | paid slice | cache-hit % |
|-------|---------:|---------------:|-----------:|-----------:|------------:|
| PL | 1,791 | 47,267 | 378,695 | 49,058 | 88.5% |
| AR | 1,967 | 38,874 | 129,292 | 40,841 | 76.0% |
| TL | 17 | 25,628 | 287,148 | 25,645 | 91.8% |
| DV | 9,650 | 132,661 | 1,708,545 | 142,311 | 92.3% |
| DR | 1,877 | 71,771 | 455,374 | 73,648 | 86.1% |
| SR | 2,041 | 56,012 | 601,715 | 58,053 | 91.2% |
| QA | 28 | 66,080 | 885,181 | 66,108 | 93.1% |
| DC | 82 | 27,040 | 199,624 | 27,122 | 88.0% |
| FN | 1,781 | 34,039 | 300,719 | 35,820 | 89.4% |
| ST | 1,469 | 18,254 | 89,940 | 19,723 | 82.0% |
| **TOTAL** | **20,703** | **517,626** | **5,036,233** | **538,329** | **90.34%** |

## Post-trim live record

**File:** `benchmark/results/runs/live/live-20260705T175943Z-779a9e8.json` (run 1, all levers applied, 10/10 stages, non-partial, $11.73 attributed)

**Levers applied before this run:**
- Batch 1/1b/1c: preamble fidelity, dispatcher CLI fix, credential gate evolution
- Batch 3: cache-lint L1 forbidden-token scanner + L2 diff-only-read tightening + L3 state eviction verification
- Batch 5: agent/skill token dedup (P1 handoff-boilerplate collapse to pointer, P2/L2 read-discipline additive, P3-A routing override compression) — static byte delta -1,363 tokens

**Per-stage paid-slice summary:**

| Stage | fresh_in | cache_creation | cache_read | paid slice | cache-hit % |
|-------|---------:|---------------:|-----------:|-----------:|------------:|
| PL | 1,930 | 52,256 | 605,614 | 54,186 | 91.8% |
| AR | 1,970 | 38,906 | 208,104 | 40,876 | 83.6% |
| TL | 56 | 38,790 | 510,777 | 38,846 | 92.9% |
| DV | 9,650 | 131,507 | 1,703,820 | 141,157 | 92.3% |
| DR | 1,895 | 89,915 | 890,026 | 91,810 | 90.6% |
| SR | 1,908 | 51,632 | 533,596 | 53,540 | 90.9% |
| QA | 35 | 78,572 | 1,355,228 | 78,607 | 94.5% |
| DC | 44 | 22,524 | 69,269 | 22,568 | 75.4% |
| FN | 1,619 | 35,164 | 371,762 | 36,783 | 91.0% |
| ST | 12 | 17,625 | 150,863 | 17,637 | 89.5% |
| **TOTAL** | **19,119** | **556,891** | **6,399,059** | **576,010** | **91.74%** |

## Credited diff (baseline → post)

**Independently recomputed by DV from both raw records; not copied from any summary.**

| Metric | Baseline | Post | Delta | % Change |
|--------|---------:|-----:|------:|--------:|
| `fresh_in` total | 20,703 | 19,119 | -1,584 | **-7.7%** |
| `cache_creation` total | 517,626 | 556,891 | +39,265 | +7.6% |
| `cache_read` total | 5,036,233 | 6,399,059 | +1,362,826 | +27.1% |
| `out` total | 152,601 | 174,633 | +22,032 | +14.4% |
| **paid slice** (`fresh_in + cache_creation`) | 538,329 | 576,010 | +37,681 | **+7.0%** |
| **cache-hit %** | 90.34% | 91.74% | +1.40 pp | **+1.40 pp** |
| **cost_usd** (attributed) | $10.32 | $11.73 | +$1.41 | **+13.6%** |

## Honest measurement conclusion (REQ-4)

**Do not spin this positive.** The result is mixed and must be reported with limits
stated:

1. **`fresh_in` direction is credible for that one metric only:** The -7.7% drop
   matches the static Batch-5 byte-delta estimate (-1,363 tokens / -7.7%) closely.
   This is meaningful because the static measurement (file size diffs, offline,
   deterministic, reproducible) already predicted this *before* any live run
   happened. It is the one number in this diff with a credible offline ground truth.

2. **The credited AC-5 metric (paid slice) moved in the WRONG direction:** Paid
   slice rose +7.0%, and attributed cost rose +13.6%. Taking this single
   comparison at face value, the combined Batch 3+5 changes made the pipeline
   more expensive, not less — the opposite of the intended direction.

3. **A single n=1 baseline-vs-post pair cannot distinguish real effect from
   ordinary run-to-run variance.** The swings in `cache_read` (+27.1%) and `out`
   (+14.4%) — metrics that the levers do NOT directly control — are larger than
   the effect anyone is trying to measure (~0.25% of paid slice: 1,363 / 538,329).
   If pipeline variance is in the 10–20% range (consistent with the `cache_read`
   and `out` swings observed here), then a genuine ~0.25% effect is statistically
   invisible in an n=1 comparison — it is smaller than the noise floor.

4. **Per-stage directional pattern is ambiguous:** DC (the only stage that got a
   genuinely NEW Diff-Only Read Rule, not a tightening of an existing one)
   improved on both paid-slice and fresh_in (-16.8% paid, -46.3% fresh). But DR
   and QA (2 of P2's 3 explicit targets, which got tightened rules) moved
   *opposite* the predicted direction (+24.7% paid / +1.0% fresh for DR; +18.9%
   paid / +25% fresh for QA, though QA's tiny 28→35 token base makes the % noisy).

5. **Credible evidence tier for this worktask is:**
   - **(a)** The static Batch-5 byte-delta measurement (-1,363 tokens, offline,
     deterministic, reproducible) for claims about agent/skill token reduction.
   - **(b)** The fixture-suite regression proofs (test_prompt_assembly.py,
     test_credential_probe.py, cache-lint.bats, test_stage_table_ssot.py — all
     green, proving no capability/behavior loss from any lever).
   - **NOT** the single live baseline-vs-post pair. It is presented here in full
     with its contradictions intact, rather than cherry-picked into a success
     narrative. This pair cannot credit or deny a live token-reduction claim at
     the scale the levers operate on (~0.25% of paid slice).

## Next step

**Proposed follow-up worktask (REQ-4 measurement gap):** Run `live[baseline]`-shaped
and `live[post]`-shaped invocations N≥3 times each (holding the tree fixed per arm) to
establish this pipeline's ordinary run-to-run variance envelope for `cache_read`,
`out`, and paid slice. Without that envelope, single-sample comparisons like this
remain ambiguous — see point 3 above. This is the single most important follow-up for
turning this worktask's directional claims into credited ones.

---

## Related

- development-0.md § post-measurement — full detailed analysis with per-stage breakout
- development-0.md § measurement-methodology — paid-slice and cache-hit % formulas
- development-0.md § deviations — Batch 1b/1c/4 remedial work, frontmatter-template-lint extension
- development-0.md § follow-ups — proposed N-run variance study + future reconciliation tasks
- token-findings-1.md — foundational findings from run 1 (cache_read dominance, reframed reduction target)
