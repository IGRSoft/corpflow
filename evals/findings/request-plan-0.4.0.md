# request-plan — 0.4.0 batch 6, pin, and pre-capture gate

**No capture has run.** This document records the work that precedes one: the 26-case
`adjacent` analysis, the batch-6 composition it produced, the atomic pin, and the
pre-capture gate with its three recorded outputs. It carries **no harness rate, no
corrected rate and no TNR**, because none has been measured at 0.4.0. § The captures did
not run states why, with the evidence.

Every number below is either read off the tree today or derived from the committed 0.3.0
labels. Nothing here is projected forward from a capture that has not happened.

## Pre-capture gate — recorded before any spend

Per `.context/architecture-0.md § spend-boundary` and `.context/team-lead-0.md § DV2 brief`.

| clause | check | result |
|---|---|---|
| 1 — floor pinned, atomic-pin step 5 | `jq -e '.held_out_from == 213'` + full step-5 chain | **`true`, `pin ok` (rc 0)** |
| 2 — batch-6 size ceiling ≤ 58 | `jq -r '[.splits\|keys[]\|tonumber]\|map(select(.>212))\|length'` | **58** |
| 3 — projected pair cost < $500 | 259 cases × $0.82/case × 2 sweeps | **$424.76** |
| 4 — explicit `--budget` per invocation | `--budget 220` per sweep (ceiling $440 pair) | prepared, not invoked |

$0.82/case is the rate the 0.3.0 capture actually recorded ($164.08 / 201). The pair
projects to $424.76, leaving ~$75 against the approved $500. The case-count ceiling binds
first here: the cost ceiling would permit up to ~103 new cases, so at 58 the two
constraints do not disagree and no re-size was required (sw-TL0-1 did not fire).

**One deviation from clause 1 as written.** AR words it "the pin commit exists". DV2 is
forbidden to commit — FN owns every git write — so the pin exists as a complete, verified
**working tree**, and step 5 was run against the files on disk exactly as specified. The
grouping FN must honour is in § The pin is one commit.

## The 26-case `adjacent` analysis

This overturns the reading in `request-plan-0.3.0.md § Batch 5 by cell`, which calls
`adjacent` at 5/10 = 50% "the standout" against a corpus 81%. That is a **harness** count.
The human labels committed alongside it do not support it.

### Batch 5's `adjacent` failures, per case

Of batch 5's ten `adjacent` cases (186-195), the harness passed 5 and failed 5. Three of
the five were drawn into the label sample:

| case | split | harness failed on | human | what it is |
|---|---|---|---|---|
| 187 | test | `asked-instead-of-planning` | **defer** | the stream-json capture defect; the plan was never stored |
| 191 | dev | 6 template assertions | **pass** | grader too strict |
| 193 | dev | `finds-the-real-surface` | **pass** | grader too strict |

**Zero genuine negatives.** Two are false fails — consistent with § Every disagreement is a
false fail, which establishes that this capture's grader errs strict and never lenient —
and one is a known capture defect. The other two of the five (among 188, 190, 195) went
unlabelled and are undecided.

The one genuine `adjacent` negative in the whole capture is **case 33**, and it is
**pre-existing**, not batch 5.

### The confound, and it is checkable

| pool | batch 5's 10 | pre-existing 16 |
|---|--:|--:|
| capability-registry.sh **excluded** (`tests/`, `skills/*/references/`, `skills/shared/*.md`) | **10** | 3 |
| capability-registry.sh **enumerated** (`SKILL.md`, `commands/`, `agents/`, `hooks/`, `skills/*/scripts/`) | **0** | 13 |

An `adjacent` case asks whether the plan **names** the near-miss surface. Ground it on a
surface the plan cannot look up and the case stops testing adjacency and starts testing
search — it is a `buried` case wearing the wrong label, and `finds-the-real-surface` then
fails for a discovery reason. Batch 5 applied one surface pool uniformly to both cells. For
`buried` that is on-design. For `adjacent` it collapses the cell.

So neither the 50% nor the 73% corpus figure is evidence about `adjacent`, and the 0.3.0
open question — "case difficulty or a real regression" — was **unanswerable as posed**.
Batch 6 answers it by removing the confound rather than re-running the bet.

### Where the negatives actually come from

All 13 human negatives in the 0.3.0 sample, by cell. The sample is enriched toward harness
failures, so these are **not** corpus rates; the composition is what the weighting reads.

| grounding | human negatives | of labelled | batch-5 cases in cell | batch-5 genuine yield |
|---|--:|--:|--:|--:|
| buried | **8** | 25 | 8 | **2 (199, 203) = 25%** |
| absent | 4 | 16 | 18 | 1 (168, `dev`) = 5.6% |
| adjacent | 1 | 9 | 10 | **0** |
| obvious | 0 | 10 | 0 | — |

`buried` is the engine, measured rather than nominated, and case **199** — the only genuine
held-out negative the tranche produced — is `buried`. `finds-the-real-surface` carries 7 of
the 13, which is the assertion `buried` and `adjacent` both exercise and `obvious` and
`absent` do not.

By type: feature 6, incident 3, docs 2, refactor 1, bug 1, migration **0 of 6**. By route:
std 10, emerg 3 of 9 labelled (33%), secure 0 of 1. Both agree with the corpus harness
table (docs 65%, incident 69%, feature 79%; migration 100%; emerg 70%, secure 90%).

## Batch 6

**58 cases, ids 213-270**, taking the corpus from 201 to 259 (182 plan / 45 clarify / 32
refute). `eval_set_version` and `SKILL.md version:` both stay **0.4.0** (AD-2) — load-bearing,
since AC-10 needs the pair at one spec version.

| cell | n | surfaces | why |
|---|--:|---|---|
| buried | **30** | registry-**excluded** | the measured engine; 8 of 13 negatives, 25% batch-5 yield, source of the only held-out negative |
| adjacent | **18** | registry-**enumerated** | the confound repair; the configuration case 33's negative came from |
| absent | **10** | none | control on the unresolved "are the new absent cases easier" question (p ≈ 0.17) |
| obvious | **0** | — | 92% harness, 0 negatives from 10 labels; buys no measurement |
| refute | **0** | — | `disputes-the-premise` has a measured false-negative floor and every repair was rejected, so a refute failure is uninterpretable as a negative |

The 10 `absent` cases are written in the shape of the genuine negatives **36, 95, 120** —
plausible for a repo like this one, ungroundable in this one — not batch 5's generic-SaaS
template, per the 0.3.0 instruction to *"sample the existing prompts for difficulty rather
than writing fresh ones from the same template."*

Route: 11 emerg of 58 (19%) against a corpus 11%. `secure`: none.

**Held out: 23 of the 58** stratify to `test` (12 buried / 7 adjacent / 4 absent; 19 plan /
4 clarify), against batch 5's 18 with only 8 `buried` in the entire batch. At batch 5's
measured 25% `buried` yield, 12 held-out `buried` cases project ~3 genuine held-out
negatives against batch 5's 1. That arithmetic is the case for 58 over ~45; it is a
projection of yield, not of a result.

**Lints:** all 23 in `tests/python/test_skill_evals.py` pass over the grown corpus. One
caught a real defect during authoring — case 232's prompt contained a phrase that also
appears in `CHANGELOG.md`, i.e. inside the searched tree, which would have made it a
lookup. Reworded, re-run green. No existing id changed tranche and ids 1-212 are
byte-identical in `evals.json`.

## The pin is one commit

FN must land these four together. `evals/README.md` is **not** among them — it asserts
nothing about the key (AD-1) and belongs to DV1/DV3.

1. `evals/scripts/gen-request-plan-cases.py` — batch 6 authored, ids 213-270
2. `skills/request-plan/evals/evals.json` — regenerated (no `--restratify`), plus the dated
   `CORPUS GROWN, NOT SPEC (batch 6, 2026-09-05)` provenance entry
3. `evals/splits/request-plan.json` — `held_out_from: 213`, the 58 split assignments
   appended by hand, and the note's absence paragraph rewritten
4. `evals/labelling.md` — the floor prose corrected from absent to pinned

Splitting them re-opens the invariant that broke at the 4→5 transition. Nothing downstream
detects a floor left on a spent tranche.

## The captures did not run

Two of the three reasons have been answered by the user and are closed. The third is
mechanical, was not foreseeable from the spend model, and is what actually stopped the sweep.
**Zero dispatches were made. Nothing was spent. No response record exists.**

### 1. Resource substitution — ANSWERED, closed

The approval was for $500 of *metered* capture spend, but this host carries no
`ANTHROPIC_API_KEY`: `eval-capture.py:has_credential()` falls through to its CLI probe, which
returns `authMethod: "claude.ai"`, `subscriptionType: "max"`. The `--budget` guard still sums
`total_cost_usd`, but that field is a list-price imputation — one 4-token probe reported
`0.2766656` with `costBasis: "list"`, almost all of it 68,234 cache-creation tokens. So
**$424.76 is imputed, not money**, and the resource 518 dispatches consume is the operator's
subscription allowance.

**Answered (user): run on the Max subscription allowance**, with the substitution understood —
that it is a different resource from the one approved, and that it draws down the allowance
they use for their own work. This is an accepted decision, not a silent one.

### 2. No human labelling pass — ANSWERED, and it bounds what may be published

**Answered (user): finish without human labels.** No labelling pass, no review page, and no
`evals/labels/request-plan-0.4.0-*` file is produced by this run.

That is a hard constraint on the output, not a footnote. When the pair runs it may report the
**harness pass rate** per capture and the **paired same-version comparison** between them — a
harness-level noise band, which is a real deliverable and the thing the 0.3.0 findings' § Next
item 4 asked for. It may **not** report a corrected rate, TPR, TNR, or a human-negative count.
There are no labels underneath those numbers and nothing may be estimated in their place.

**So: no calibrated rate will be measured at 0.4.0**, by design of this run rather than by
oversight. The 0.3.0 calibration block remains the most recent calibrated figure this corpus
has, and it describes 0.3.0, not the shipping spec.

### 3. The capture tree is HEAD, and batch 6 is not committed — OPEN, and it is the live blocker

`eval-capture.py` was invoked and **refused at pre-flight** (exit 2):

```
eval-capture: working tree has uncommitted changes; commit them first — a capture
from a detached HEAD worktree would not contain them, and plugin_sha would describe
a tree that never ran
```

This is `assert_clean_tree()`, and the reason is structural rather than fussy.
`make_capture_tree()` builds the tree under test with `git worktree add --detach HEAD` —
**tracked-at-HEAD only**. Batch 6 exists solely as uncommitted working-tree changes, so it is
physically absent from the tree the model would search, and `plugin_sha` would stamp a state
that never ran. The 0.0.1 capture recorded `9e2cda9-dirty` for exactly this reason.

**The refusal prevented a wasted spend, and that is worth stating plainly.** Had it not fired,
the sweep would have dispatched the 259-case eval set from the working tree against a HEAD tree
containing none of the three workstreams' changes, and stamped a provenance describing a tree
that never existed — spending the now-authorized allowance on an uninterpretable result.

The only bypass is `--no-isolate`, whose own contract forbids it here: *"It must never be used
for a capture whose number will be quoted."* It would also reintroduce both defects isolation
exists to prevent — the ambient plugin answering instead of the tree, and the answer key
reachable inside the searched tree. It was not used and must not be.

**What clears it: one commit.** This is exactly `architecture-0.md § spend-boundary` gate clause
1 — *"the pin commit exists"* — which is a mechanical precondition of the capture, not a wording
choice. DV2 is forbidden every git write, so DV2 cannot clear it.

**It is not enough to commit the pin group alone.** The predicate is repo-wide
(`git status --porcelain --untracked-files=no` must be empty), and the tree currently carries
nine tracked modifications from all three workstreams:

| owner | files |
|---|---|
| DV2 (the pin group, § The pin is one commit) | `gen-request-plan-cases.py`, `evals.json`, `splits/request-plan.json`, `labelling.md` |
| DV1 | `skills/self-improvement/SKILL.md`, `references/target-mapping.md`, `scripts/map-and-filter.sh`, `tests/shell/skills/map-and-filter.bats` |
| DV1 + DV3 (shared) | `evals/README.md` |

Untracked files are ignored by the check, so this document and `evals/failure-labels.jsonl` do
not block it. All nine tracked files must land before the first dispatch — which makes the
capture a **post-FN** step, or one requiring an explicit commit authorization that no DV agent
holds.

### The binding condition, recorded now so it survives

Carried from **sw-AR0-1** and restated in the `evals.json` grading entry: when these captures
run, **no delta may be attributed to the 0.4.0 drifted-rule reconciliations.** `evals.json §
THREE DRIFTED RULE COPIES REPAIRED` stands unamended, including *"NO re-capture should be
commissioned to prove it"*. The pair is commissioned on two independent grounds — no recorded
number describes the shipping spec, and the same-version noise band is undelivered and was
prescribed by the 0.3.0 findings' own § Next item 4. Capture #2 is unconditional (sw-PL0-1):
it runs whether or not the tranche yields negatives, spec and eval set byte-identical, only the
out-dir differing.

### What was verified instead, free of charge

`eval-capture.py --dry-run --split test` exits 0 and resolves the full dispatch plan over the
new tranche: isolated capture tree under `$TMPDIR`, `--plugin-dir` pinned to it, `--settings`
pinned, answer key stripped, `/corpflow:request-plan "<prompt>"` in `command` mode. The capture
path is wired and reaches batch 6's held-out cases.

Scale, for whoever runs it: **259 dispatches per sweep, 518 for the pair, at `--concurrency 1`**
— the default, and the header records that concurrency 4 lost 38 consecutive cases to the rate
limiter. Records are written per case and existing ones are skipped without `--force`, so a
sweep that aborts partway is resumable and loses nothing already paid for.

### The invocations, ready to run once the tree is clean

Eval set at the moment of writing: `sha256 c18e3226…63b62d`, 259 cases, `eval_set_version 0.4.0`,
`SKILL.md version: 0.4.0`. Both captures must see this same file (AC-10).

```sh
python3 evals/scripts/eval-capture.py --eval-set skills/request-plan/evals/evals.json \
  --concurrency 1 --budget 220 --out-dir skills/request-plan/evals/responses-0.4.0-a
# record the result of #1 before starting #2
python3 evals/scripts/eval-capture.py --eval-set skills/request-plan/evals/evals.json \
  --concurrency 1 --budget 220 --out-dir skills/request-plan/evals/responses-0.4.0-b
python3 evals/scripts/eval-grade.py   # harness pass rate per capture, then the paired diff
```

Report the harness pass rate for each and the paired same-version spread between them. Report
any sweep that aborts, rate-limits or returns fewer records than dispatched, with the counts.
Do **not** publish a corrected rate, TPR or TNR: there are no labels under them this run.
