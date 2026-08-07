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

## Reading `without_arm="skip"` placeholders

A WITHOUT arm run in `skip` mode is a byte-stable placeholder, not a measurement:
`stage_count: 1`, null tokens and cost, `app_path: null`, and `pass_fail: "pass"`.
The `pass` there means "not run" — it has never been a claim about output quality.
Discriminate on `app_path: null` together with `stage_count == 1`.
