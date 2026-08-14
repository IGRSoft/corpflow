# Known-bad records

Stored measurements are never edited or deleted — a record that turned out to be
untrustworthy is listed here instead, so historical comparisons can exclude it
without the underlying data being rewritten.

## `live-20260721T190044Z-9bd7a47` — WITH arm `pass_fail` is meaningless

**In:** `results/history.json` (`live[1]`)

| field | value |
|---|---|
| `paths.with.cost_usd` | 17.4838 |
| `paths.with.loc_produced` | 0 |
| `paths.with.test_count` | 0 |
| `paths.with.app_path` | `null` |
| `paths.with.pass_fail` | **`pass`** |

Ten stages dispatched and $17.48 spent, but app measurement never produced a
result, so nothing about the generated artifact was actually graded. The record
reads `pass` because `build_live_record` defaulted an unmeasured arm to green.
That default is now fail-closed, so no record produced after this one can repeat
the shape — but this record predates the fix and its `pass_fail` must be read as
**unmeasured**, not as a passing run.

**Excluding it:** an arm is unmeasured when `app_path` is `null` while
`stage_count > 1`. Its token and cost figures are unaffected and remain usable.

## `live-20260807T114444Z-a0cdb43` — not a valid A/B

**In:** `results/runs/live/` only (partial records never enter `history.json`)

| field | value |
|---|---|
| `paths.with.stage_count` | 4 (of 10) |
| `paths.without.stage_count` | 10 |
| `paths.with.cost_usd` | 14.5912 |
| `paths.without.cost_usd` | 19.7329 |
| `budget_usd` | 30.00 (realized **34.32**) |

The arms ran off one shared tally, and the WITHOUT arm — dispatched first —
consumed $19.73 of a $30 cap before the WITH arm started. WITH was gated out
after 4 stages, so the two arms are not comparable on any axis: cost, tokens,
LOC, or quality. Both scored the oracle 20/20, which at the time was the whole
case set; that says the case set did not discriminate, not that the arms tied.

Two harness defects it exposed, both since fixed: a flat per-stage projection
that accepted a $30 budget for a run needing ~$40, and a shared purse that let
one arm starve the other. Budgets are now per-arm and projections per-stage.

The record is retained as the evidence for both fixes. Its per-stage cost
figures are real and are what `budget.STAGE_EXPECTED_TOKENS` is calibrated from;
nothing comparing the two arms should be read from it.

## `live-20260814T083428Z-cce3984` — not a valid A/B

**In:** `results/runs/live/` only (partial records never enter `history.json`)

| field | value |
|---|---|
| `paths.with.stage_count` | 10 |
| `paths.without.stage_count` | 4 (of 10) |
| `paths.with.cost_usd` | 20.8251 |
| `paths.without.cost_usd` | 21.4842 |
| `budget_usd` | 70.00 ($35.00/arm) |

The mirror image of the a0cdb43 entry above, and not a shared-purse failure —
budgets were already per-arm. The WITHOUT arm's DV cost $18.16, and the reserve
rule holds back the heaviest stage observed so far before every later stage, so
`21.48 spent + 18.16 reserved > 35.00` gated DR out with six cheap stages
(~$5 total in the WITH arm) still to run. One expensive DV locks out the tail.

Both arms scored the oracle 30/30 including `implied` 6/6. As above, that is a
statement about the case set, not a tie between the arms.

Its per-stage figures are real. Nothing comparing the two arms should be read
from it — use `live-20260814T102001Z-cce3984`, the complete run at the same sha.

**Sizing:** DV has ranged $7.54–$18.16 across five observed arm-runs, so a
per-arm share must clear `spend_through_DV + DV_cost`. $50/arm is the floor.

## Reading `without_arm="skip"` placeholders

A WITHOUT arm run in `skip` mode is a byte-stable placeholder, not a measurement:
`stage_count: 1`, null tokens and cost, `app_path: null`, and `pass_fail: "pass"`.
The `pass` there means "not run" — it has never been a claim about output quality.
Discriminate on `app_path: null` together with `stage_count == 1`.

**The placeholder itself is unchanged**, but the WITH half of a `skip`-mode record
changed shape once every dispatched arm began being measured and graded
unconditionally. Records written before that change have a WITH block with
`app_path: null`, `loc_produced: 0` and **no** `oracle` key at all; records written
after it have a real `app_path` and a full `oracle` payload. That is a shape
difference, not only a value difference, so a reader iterating `paths.with.oracle`
across stored records must tolerate its absence on the older ones. Nothing about the
WITHOUT placeholder moved.

## Telling arm, joined and paired records apart

Since the arm split, three record kinds coexist. Discriminate on root keys, never on
the run id:

| Kind | Root key | How to read it |
|---|---|---|
| **arm** | `arm: "with"` / `"without"` | Half a comparison — one `paths` entry, no `comparison` block. Nothing WITH-vs-WITHOUT may be read from it *at all*. Lives in `results/runs/live-arm/` and never enters `history.json`. |
| **joined** | `joined_from` (and no `arm`) | Two independent arm runs welded together after passing the comparability gate. Reads exactly like a paired record; `joined_from.observed_gap_s` records how far apart the two runs were. |
| **natively paired** | neither key | One dispatch, both arms, shared service conditions. |

A joined record is not the same evidence as a natively-paired one: its arms did not
share service conditions, only a commit, an era and a graded case set. The gate
refuses anything weaker than that, and the observed gap travels in the record so it
can be weighed rather than assumed away. When both exist for the same question, prefer
the paired run.
