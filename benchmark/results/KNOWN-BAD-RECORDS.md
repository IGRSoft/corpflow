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

## Reading `without_arm="skip"` placeholders

A WITHOUT arm run in `skip` mode is a byte-stable placeholder, not a measurement:
`stage_count: 1`, null tokens and cost, `app_path: null`, and `pass_fail: "pass"`.
The `pass` there means "not run" — it has never been a claim about output quality.
Discriminate on `app_path: null` together with `stage_count == 1`.
