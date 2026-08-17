---
name: cost-report
description: Generate cost analysis for worktasks with token usage breakdown and optimization recommendations
argument-hint: '[--worktask-id ID] [--json]'
allowed-tools: Read, Write
model: sonnet
related:
  - commands/agent-report.md
  - skills/cost-optimization/SKILL.md
  - skills/context-compression/SKILL.md
  - skills/csv-export-templates/SKILL.md
  - commands/estimate.md
  - commands/context-status.md
---

# Cost Report

Generate cost analysis for completed or in-progress worktasks with token usage breakdown and optimization recommendations.

## Usage

```
/cost-report
/cost-report --stage DV
/cost-report --budget-alert 80%
/cost-report --export
/cost-report --optimize
/cost-report --json
```

## Options

- `--stage <code>` - Show costs for specific stage only (PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR)
- `--budget-alert <percent>` - Set alert threshold (default: 75%)
- `--export` - Write the By Stage breakdown to `.context/cost-report.csv` (see § CSV Export)
- `--json` - Emit the summary as one JSON object on stdout instead of the markdown report (see § Budget Tracking JSON)
- `--optimize` - Include optimization recommendations
- `--detailed` - Show per-operation token breakdown (includes Background Activity)
- `--bg-activity` - Show Background Activity table only (default off to keep summary compact)
- `--compare <task-id>` - Compare costs with another task

## Output Format

### Summary Report (Default)

```
## Cost Report: [Task Name]

### Overview
| Metric | Value |
|--------|-------|
| Total Tokens | 45,000 |
| Estimated Cost | $0.41 |
| Budget Used | 81% |
| Worktask Type | standard |

### By Stage
| Stage | Tokens | Model | Cost | % of Total |
|-------|--------|-------|------|------------|
| PL | 7,500 | opus | $0.113 | 17% |
| AR | 15,000 | opus | $0.225 | 33% |
| TL | 4,000 | sonnet | $0.012 | 9% |
| DV | 18,500 | sonnet | $0.056 | 41% |
| DR | - | - | - | - |
| QA | - | - | - | - |
| DC | - | - | - | - |
| FN | - | - | - | - |
| ST | - | - | - | - |

### Status
Current Stage: DV (in_progress)
Stages Complete: PL, AR, TL
Estimated Remaining: ~$0.15
```

### Cache Performance (validates AC-14)

```
### Cache Performance
| Stage | input_tokens | cache_read | cache_create | hit_ratio |
|-------|--------------|------------|--------------|-----------|
| PL    |        7,500 |          0 |        7,200 |       0%  |
| AR    |       15,000 |      6,800 |        7,500 |      31%  |
| TL    |        4,000 |      3,100 |          200 |      78%  |
| DV    |       18,500 |     11,200 |        1,400 |      62%  |
| DR    |        6,200 |      4,900 |          150 |      79%  |
| QA    |        9,800 |      6,300 |          500 |      64%  |
| **Average** | — | — | — | **52% ⚠** |
```

#### Cache Performance — Field Notes

- `hit_ratio = cache_read_input_tokens / (input_tokens + cache_read_input_tokens)`.
- Row flagged with ⚠ when ratio < 60%. Cross-stage **average** is the AC-14 target (≥ 60%); flag the average row when below.
- PL is always 0% (cold cache); the average excludes PL once at least 3 downstream stages have data so a single cold prefix doesn't drag the headline.
- `n/a` appears when `CLAUDE_CACHE_READ_INPUT_TOKENS` was unset (older runtime); see `skills/cost-optimization/SKILL.md § Capture Script`.

### Effort Distribution (validates per-stage budget envelope)

```
### Effort Distribution
| Stage | low | medium | high | xhigh | max | unknown |
|-------|-----|--------|------|-------|-----|---------|
| PL    |   0 |      0 |    1 |     0 |   0 |       0 |
| AR    |   0 |      0 |    1 |     0 |   0 |       0 |
| TL    |   0 |      1 |    0 |     0 |   0 |       0 |
| DV    |   0 |      0 |    2 |     1 |   0 |       0 |
| DR    |   0 |      0 |    1 |     0 |   0 |       0 |
| QA    |   0 |      1 |    0 |     0 |   0 |       0 |
```

#### Effort Distribution — Field Notes

- Count of `cost-*.jsonl` rows grouped by `(stage, effort)` (effort source: `CLAUDE_EFFORT` env var and/or hook stdin `effort.level`).
- Mismatch with the per-stage `effort:` declared in the agent frontmatter (see `skills/shared/model-selection.md`) — flag as **budget drift**; common cause is operator `/effort` override mid-run or PL0 dispatch metadata writer setting a non-default effort.
- `unknown` rows mean `CLAUDE_EFFORT` was not exported; current runtimes always export it, so a persistent `unknown` indicates a broken hook environment.

### Background Activity (`--bg-activity` or `--detailed`)

```
### Background Activity
| Stage | bg_tasks_active | session_crons | dispatch_depth | notable                  |
|-------|-----------------|---------------|----------------|--------------------------|
| PL    |              0  |            0  |       0        | —                        |
| AR    |              0  |            0  |       1        | —                        |
| TL    |              0  |            0  |       1        | —                        |
| DV    |              2  |            1  |       2        | bg_task_ids: [bg1, bg2]  |
| DR    |              0  |            0  |       2        | —                        |
| QA    |              0  |            0  |       2        | —                        |
```

#### Background Activity — Counter Columns

- `bg_tasks_active` = max(`metadata.background_tasks_count`) observed across hook rows for that stage in `audit.jsonl` (writers: `hook:audit-subagent`, `hook:agent-stop`).
- `session_crons` = same, for `metadata.session_crons_count`.
- `dispatch_depth` = computed from the `metadata.parent_agent_id` chain — 0 when `"none"`, otherwise `1 + depth(parent)`. Sub-agents spawn sub-agents up to 3 levels deep by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`) — depths ≥ 1 appear whenever a stage agent delegates to a specialist. A `dispatch_depth` of 3 means the chain is on the default ceiling: the next delegation below it is refused unless the env override is raised.

#### Background Activity — Notable Column & Dedup Mode

- `notable` = comma-joined `metadata.background_task_ids` and `metadata.session_cron_ids` when count > 0; otherwise `—`. Watch for the literal `"unknown"` string — signals the canonical ID-field name has shifted (see `skills/agent-coordination/references/hook-monitoring.md § BG-Task ID Schema Watch`).
- Aggregation groups rows by stage on `metadata.dedupe_key` and computes max/sum/depth.

#### Background Activity — Version Requirements

Rows that lack the background-activity fields default to `0` / `—`.

### Optimization Report (`--optimize`)

Emit `## Optimization Recommendations` grouped **High Impact** / **Medium Impact** — each item: current state, recommendation, estimated savings ($, %) — plus a `### Model Usage Summary` table (`Model | Invocations | Tokens | Cost`). Source the strategies from `skills/cost-optimization/SKILL.md` (model downgrade per task type, context compression at thresholds, batched reads).

### Stage Detail (`--stage DV`)

Emit `## <Stage> Cost Detail` with: `### Summary` (Total Tokens, Model, Cost, Duration), `### Operation Breakdown` (per-operation tokens + cost from that stage's cost-*.jsonl rows), `### Context Usage` (input context / output generated / overhead).

## Cost Calculation

```
Stage Cost = (Input Tokens × input rate) + (Output Tokens × output rate)
```

Model rates: canonical table in `skills/shared/model-selection.md § Cost Tiers` — do not hardcode rates here; pull current `$/1M` from `/model` when the table lags.

### Derived Quantities, Units, Rounding

This subsection is the **single source** for every number both the markdown report
and the `--json` object print. Neither output restates these rules.

| Quantity | Definition | Unit / rounding |
|----------|------------|-----------------|
| Stage tokens | `input_tokens + output_tokens` summed over that stage's `cost-*.jsonl` rows | integer |
| Total tokens | Sum of stage tokens across all stages with data | integer |
| Stage cost | Formula above, at that stage's `model` rate | USD, 3 decimals, half-up |
| Total cost | Sum of stage costs, rounded **after** summing | USD, 2 decimals, half-up |
| Budget used | `total_cost / budget_limit × 100` | integer percent, half-up |
| % of total | `stage_tokens / total_tokens × 100` — a **token** share, not a cost share | integer percent, half-up |
| Estimated remaining | Baseline cost of stages not yet run, from `skills/cost-optimization/references/token-baselines.md` | USD, 2 decimals, half-up |

#### Stages without data

Stages with no `cost-*.jsonl` rows have **no value**, not a zero: the markdown
`### By Stage` table renders them as `-`, and `--json` omits them from `by_stage`.
Alert levels come from § Alert Thresholds — not restated in either output.

#### Rounding mode

Half-up on the exact decimal value, not on a binary float: `0.0555` rounds to
`0.056`, which IEEE-754 nearest-even gives as `0.055`.

### Budget Tracking JSON

**Normative `--json` output contract.** With `--json`, the command writes exactly one
JSON object to stdout — no markdown, no log lines, nothing else — carrying the same
numbers as the default markdown summary, computed per § Derived Quantities, Units,
Rounding.

#### Example object

```json
{
  "cost_tracking": {
    "worktask_id": "20260816-json-cost-summary",
    "worktask_type": "standard",
    "total_estimated_tokens": 45000,
    "total_cost": 0.41,
    "budget_limit": 0.5,
    "budget_used_percent": 81,
    "by_stage": {
      "PL": { "tokens": 7500, "model": "opus", "cost": 0.113, "percent_of_total": 17 },
      "AR": { "tokens": 15000, "model": "opus", "cost": 0.225, "percent_of_total": 33 },
      "TL": { "tokens": 4000, "model": "sonnet", "cost": 0.012, "percent_of_total": 9 },
      "DV": { "tokens": 18500, "model": "sonnet", "cost": 0.056, "percent_of_total": 41 }
    },
    "status": {
      "current_stage": "DV",
      "current_stage_state": "in_progress",
      "stages_complete": ["PL", "AR", "TL"],
      "estimated_remaining_cost": 0.15
    },
    "alerts": [
      { "threshold_percent": 75, "level": "orange", "action": "user_notified" }
    ]
  }
}
```

#### Field Contract

| Field | Type | Source |
|-------|------|--------|
| `worktask_id` | string | `.context/state.json`; `null` when no worktask is anchored |
| `worktask_type` | string | Sizing from PL0 — mirrors the markdown Overview row |
| `total_estimated_tokens` | integer | Total tokens |
| `total_cost` | number | Total cost |
| `budget_limit` | number | Budget envelope in USD; `null` when unset |
| `budget_used_percent` | integer | Budget used; `null` when `budget_limit` is `null` |
| `by_stage` | object | Stage code → `{tokens, model, cost, percent_of_total}`; stages without data are absent |

##### `status` and `alerts`

| Field | Type | Source |
|-------|------|--------|
| `status.current_stage` | string | Stage code, or `null` when the worktask is complete |
| `status.current_stage_state` | string | Ledger stage state (`in_progress`, `blocked`, …) |
| `status.stages_complete` | array of string | Stage codes, in execution order |
| `status.estimated_remaining_cost` | number | Estimated remaining |
| `alerts` | array of object | One entry per crossed threshold: `{threshold_percent, level, action}`, levels and actions verbatim from § Alert Thresholds; `[]` when none crossed |

#### Flag composition

`--json` is **summary-only**. It composes with `--budget-alert` (which shifts the
`alerts[]` threshold) and with `--export` (the CSV is still written; the JSON still
goes to stdout). It does not compose with `--stage`, `--optimize`, `--detailed`,
`--bg-activity`, or `--compare` — those have no schema surface here, so the command
refuses the combination on stderr and writes nothing to stdout rather than emitting a
partial object.

## CSV Export

**Normative `--export` output contract.** `--export` writes the `### By Stage`
breakdown to `.context/cost-report.csv`, overwriting any file already there. That
table and nothing else: no Overview, Cache Performance, Effort Distribution or
Background Activity rows, and no totals row — totals live in the Overview table and
in `--json`, and a totals row inside the data is what breaks a spreadsheet the first
time someone sorts the sheet.

Delimiter, encoding, header row and multiline-cell quoting are **not restated here**.
They come from `skills/csv-export-templates/SKILL.md § Format Specification`, the
single source for this plugin's CSV shape; when that convention moves, this export
moves with it.

### CSV Column Schema

Five columns in this order, header row exactly `stage;tokens;model;cost;% of total`:

| # | Column | Value | Type / unit |
|---|--------|-------|-------------|
| 1 | `stage` | Stage code (`PL`, `AR`, `TL`, …) | string |
| 2 | `tokens` | Stage tokens | integer, no thousands separator |
| 3 | `model` | `model` field of that stage's rows | string, alias verbatim |
| 4 | `cost` | Stage cost | bare number, 3 decimals, `.` point, **no `$`** |
| 5 | `% of total` | % of total | bare integer 0–100, **no `%`** |

Definitions, rounding and units for columns 2, 4 and 5 are § Derived Quantities,
Units, Rounding; the CSV restates none of them. Its numbers therefore equal the
markdown `### By Stage` cells digit for digit, minus the `$`, `%` and thousands
separators markdown adds for readability — those are presentation, and a spreadsheet
reads them as text.

### CSV Example

```csv
stage;tokens;model;cost;% of total
PL;7500;opus;0.113;17
AR;15000;opus;0.225;33
TL;4000;sonnet;0.012;9
DV;18500;sonnet;0.056;41
```

Same run as the § Summary Report example: same stages, same figures.

### CSV Rows and Ordering

One row per stage **with data**, in execution order — `status.stages_complete` order,
then the current stage, then any later stage that has rows. Stages with no
`cost-*.jsonl` rows are **omitted**: the markdown `-` placeholder has no CSV
equivalent, and `--json` omits them from `by_stage` for the same reason. Four rows out
of nine stages is the correct rendering of four stages having run.

With `--stage <code>` the export narrows to that stage's row. `% of total` keeps the
full-run denominator, so the narrowed row still shows that stage's true share rather
than a self-referential 100.

### CSV Quoting

`csv-export-templates` quotes cells containing line breaks; this export also quotes
any cell containing the delimiter or a double quote, per RFC 4180 — wrap the cell in
`"` and double every embedded `"`. `model` is free text out of
`CLAUDE_TASK_METADATA_MODEL` and is the realistic carrier of a stray `;`: unquoted, it
shifts every later column by one and the import still reports success.

```csv
stage;tokens;model;cost;% of total
TL;4000;"sonnet;fallback";0.012;9
```

### CSV Missing-Data Fallback

`--export` reuses § Missing-Data Fallback unchanged: with no
`.context/logs/cost-*.jsonl` it writes the same five columns populated from
`token-baselines.md`, and prints the same hook-not-configured warning to the report
(to stderr under `--json`). The warning never enters the CSV — a comment or note row
would break the header contract on import.

With no worktask anchored there is nothing to estimate from. The command then writes
**no file** and reports the error, rather than leaving a header-only or stale
`cost-report.csv` on disk for a spreadsheet to pick up as current.

## Alert Thresholds

| Threshold | Action | Visual |
|-----------|--------|--------|
| < 50% | Normal | Green |
| 50-74% | Warning logged | Yellow |
| 75-89% | User notified | Orange |
| 90-99% | Compression suggested | Red |
| 100% | Worktask paused | Critical |

## Examples

```bash
/cost-report                          # summary for current worktask
/cost-report --stage AR               # per-stage detail
/cost-report --optimize               # + actionable recommendations
/cost-report --budget-alert 60%      # alert at 60% budget consumption
/cost-report --export                 # writes .context/cost-report.csv (§ CSV Export)
/cost-report --json                   # one JSON summary object on stdout
/cost-report --json | jq .cost_tracking.budget_used_percent
/cost-report --compare <task-id>      # side-by-side with another worktask
```

## Data Source

Reads `.context/logs/cost-*.jsonl` written by the `SubagentStop` hook (see
`skills/cost-optimization/SKILL.md` § Per-Stage Tracking). Each JSONL line is
one subagent invocation — the aggregator groups by `stage`, sums `input_tokens`
+ `output_tokens`, and applies the `model` rate.

### Audit Dedup Before Aggregation

**Audit-trail input is deduplicated before aggregation.** The
`### Effort Distribution` table sources `(stage, effort)` counts from
`.context/logs/audit.jsonl`, which carries BOTH hook-emitted rows
(`actor: "hook:audit-tooluse"`) and forward-compatible agent-emitted rows. Pipe
through the canonical dedup filter before counting:

```bash
skills/agent-coordination/scripts/audit-dedup.sh .context/logs/audit.jsonl \
  | jq -c 'select(.action == "tool_invoked")' \
  | jq -s 'group_by([.metadata.stage // "unknown", .metadata.effort // "unknown"]) | …'
```

#### Dedup Key & Verification

Without the dedup step, every hook+agent paired row inflates the `(stage, effort)`
count by 1 — most visibly on stages where both writers fire (Write/Edit and the
ledger patch). Dedup is keyed on `metadata.dedupe_key`; rows without one (singletons
such as `approval_received`, `stage_transition`) pass through unchanged. See
`skills/agent-coordination/SKILL.md § Writers` for the hook-authority rule and
`skills/agent-coordination/scripts/audit-dedup.sh --self-test` to verify the
filter against a synthetic fixture.

### Cache Performance Inputs

The Cache Performance table additionally reads:

- `cache_read_input_tokens` / `cache_creation_input_tokens` columns from the same JSONL (exported by Claude Code on `SubagentStop` as `CLAUDE_CACHE_READ_INPUT_TOKENS` / `CLAUDE_CACHE_CREATION_INPUT_TOKENS`).
- `effort` column — sourced from `CLAUDE_EFFORT`; powers `### Effort Distribution`.

### Missing-Data Fallback

If `.context/logs/cost-*.jsonl` is absent, the command falls back to estimated
baselines from `skills/cost-optimization/references/token-baselines.md` and
prints a warning that the hook is not configured. If the JSONL exists but the
cache columns are missing or zero, the Cache Performance table renders `n/a`
and prints a note pointing at the Capture Script update.

#### Fallback under `--json`

Under `--json` the same fallback fires on the same condition, but the warning cannot
go to stdout — it would break the single-object contract. Instead the command emits
the **full** schema, populated from the baselines, plus a top-level `warning` string
inside `cost_tracking`. It never fails, and never emits a partial or empty object.

##### Fallback object

```json
{
  "cost_tracking": {
    "warning": "no .context/logs/cost-*.jsonl — figures estimated from token-baselines.md; SubagentStop hook not configured",
    "worktask_id": "20260816-json-cost-summary",
    "worktask_type": "standard",
    "total_estimated_tokens": 21000,
    "total_cost": 0.32,
    "budget_limit": 0.5,
    "budget_used_percent": 63,
    "by_stage": {
      "PL": { "tokens": 7000, "model": "opus", "cost": 0.105, "percent_of_total": 33 },
      "AR": { "tokens": 14000, "model": "opus", "cost": 0.21, "percent_of_total": 67 }
    },
    "status": {
      "current_stage": "AR",
      "current_stage_state": "in_progress",
      "stages_complete": ["PL"],
      "estimated_remaining_cost": 0.18
    },
    "alerts": [
      { "threshold_percent": 50, "level": "yellow", "action": "warning_logged" }
    ]
  }
}
```

`warning` is absent — not `null` — on a normal run, so `has("warning")` is the
consumer's estimated-vs-measured test.

## Integration

This command is used:
- Throughout worktask for cost monitoring
- At stage transitions for optimization checks
- At worktask completion for final analysis
- By project-manager (FN stage) for budget reporting and timing recap

Costs are grouped **by stage**; the agent identity behind each stage row lives in
`/agent-report`, which reads the same audit trail per invocation.
