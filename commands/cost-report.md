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

Worktask cost analysis: tokens by stage, cache/effort observability, recommendations.

## Usage

```
/cost-report [--worktask-id <id>] [--stage <code>] [--budget-alert <pct>]
             [--compare <task-id>] [--export] [--json] [--optimize]
             [--detailed] [--bg-activity]
```

## Options

| Option | Effect |
|--------|--------|
| `--worktask-id <id>` | Another worktask (default: `.context/state.json`) |
| `--stage <code>` | One stage — PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR (§ Stage Detail) |
| `--budget-alert <percent>` | Alert threshold (default 75%) |
| `--export` | By Stage → `.context/cost-report.csv` (§ CSV Export) |
| `--json` | JSON object on stdout, not markdown (§ Budget Tracking JSON) |
| `--optimize` | Add recommendations (§ Optimization Report) |
| `--detailed` | Per-operation breakdown + Background Activity |
| `--bg-activity` | Background Activity only (off by default) |
| `--compare <task-id>` | Side-by-side with another worktask |

## Output Format

### Summary Report (Default)

`## Cost Report: [Task Name]`, an `### Overview` table (Total Tokens, Estimated Cost, Budget Used, Worktask Type), then:

```
### By Stage
| Stage | Tokens | Model | Cost | % of Total |
|-------|--------|-------|------|------------|
| PL | 7,500 | opus | $0.113 | 17% |
| AR | 15,000 | opus | $0.225 | 33% |
| TL | 4,000 | sonnet | $0.012 | 9% |
| DV | 18,500 | sonnet | $0.056 | 41% |
| DR | - | - | - | - |
```

then a `### Status` block: Current Stage (with state), Stages Complete, Estimated Remaining.

### Cache Performance (validates AC-14)

Columns `Stage | input_tokens | cache_read | cache_create | hit_ratio`, one row per stage, then a bold **Average**.

- `hit_ratio = cache_read_input_tokens / (input_tokens + cache_read_input_tokens)`; ⚠ any row below 60%, and the Average, which is the AC-14 target.
- PL is always 0% (cold cache), so it leaves the average once 3+ downstream stages have data.
- `n/a` means `CLAUDE_CACHE_READ_INPUT_TOKENS` was unset (older runtime); see `skills/cost-optimization/SKILL.md § Capture Script`.

### Effort Distribution (budget envelope)

Columns `Stage | low | medium | high | xhigh | max | unknown`; cells count `cost-*.jsonl` rows by `(stage, effort)`, effort from `CLAUDE_EFFORT` (always exported by current runtimes, so persistent `unknown` means a broken hook) and/or hook stdin `effort.level`.

Mismatch with the stage's declared `effort:` (`skills/shared/model-selection.md`) is **budget drift** — an operator `/effort` override mid-run, or PL0 dispatch metadata setting a non-default effort.

### Background Activity (`--bg-activity` or `--detailed`)

Columns `Stage | bg_tasks_active | session_crons | dispatch_depth | notable`, one row per stage; rows lacking these fields default to `0` / `—`.

- `bg_tasks_active` / `session_crons` = max `metadata.background_tasks_count` / `metadata.session_crons_count` over that stage's `audit.jsonl` hook rows (`hook:audit-subagent`, `hook:agent-stop`).
- `dispatch_depth` = depth of the `metadata.parent_agent_id` chain — 0 when `"none"`, else `1 + depth(parent)`. A row at the ceiling means the next delegation is refused; ceiling and budget: `skills/agent-coordination/SKILL.md`.
- `notable` = comma-joined `metadata.background_task_ids` + `metadata.session_cron_ids`, else `—`; a literal `"unknown"` means the ID-field name shifted (`skills/agent-coordination/references/hook-monitoring.md § BG-Task ID Schema Watch`).

### Optimization Report (`--optimize`)

`## Optimization Recommendations`, grouped **High Impact** / **Medium Impact** — per item: current state, recommendation, estimated savings ($, %) — plus `### Model Usage Summary` (`Model | Invocations | Tokens | Cost`). Strategies: `skills/cost-optimization/SKILL.md`.

### Stage Detail (`--stage DV`)

`## <Stage> Cost Detail`: `### Summary` (Total Tokens, Model, Cost, Duration), `### Operation Breakdown` (per-operation tokens + cost), `### Context Usage` (input / output / overhead).

## Cost Calculation

```
Stage Cost = (Input Tokens × input rate) + (Output Tokens × output rate)
```

Rates: `skills/shared/model-selection.md § Cost Tiers`, never hardcoded here; when that table lags, pull `$/1M` from `/model`.

### Derived Quantities, Units, Rounding

**Single source** for every number both outputs print.

| Quantity | Definition | Unit |
|----------|------------|------|
| Stage tokens | `input_tokens + output_tokens` over that stage's rows | integer |
| Total tokens | Σ stage tokens | integer |
| Stage cost | Formula above, at that stage's `model` rate | USD, 3 dp |
| Total cost | Σ stage costs, rounded **after** summing | USD, 2 dp |
| Budget used | `total_cost / budget_limit × 100` | integer % |
| % of total | `stage_tokens / total_tokens × 100` — a **token** share, not cost | integer % |
| Estimated remaining | Baselines for stages not yet run (§ Missing-Data Fallback) | USD, 2 dp |

- Rounding is half-up on the exact decimal, not the binary float: `0.0555` → `0.056`, not IEEE-754's `0.055`.
- Stages with no rows have **no value**, not a zero: markdown renders `-`, `--json` omits them; alert levels from § Alert Thresholds.

### Budget Tracking JSON

**Normative `--json` contract.** Exactly one JSON object on stdout — no markdown, no log lines, nothing else — with the markdown summary's numbers per § Derived Quantities, Units, Rounding.

#### JSON Schema Example

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

#### JSON Field Notes

- `worktask_id` from `.context/state.json` (`null` when unanchored); `worktask_type` is PL0 sizing; `budget_limit` the USD envelope — `null` when unset, making `budget_used_percent` `null`.
- `by_stage` omits stages without data; `current_stage` is `null` once complete; `stages_complete` is in execution order.
- `alerts`: one entry per crossed threshold, `level` and `action` verbatim from § Alert Thresholds; `[]` when none crossed.

**Flag composition**: summary-only. Composes with `--budget-alert` (shifts the `alerts[]` threshold) and `--export` (CSV still written). Refuses `--stage`, `--optimize`, `--detailed`, `--bg-activity`, `--compare` on stderr, writing nothing — no schema surface, and a partial object is worse than none.

## CSV Export

**Normative `--export` output contract.** Writes the `### By Stage` breakdown to `.context/cost-report.csv`, overwriting it — that table only: no rows from other tables, and no totals row, which sorting would scatter into the data; totals live in Overview and `--json`.

Delimiter, encoding, header row and multiline-cell quoting: `skills/csv-export-templates/SKILL.md § Format Specification`, the single source for this plugin's CSV shape — not restated here.

### CSV Column Schema

Header row exactly `stage;tokens;model;cost;% of total` — five columns in that order:

| # | Column | Value | Type / unit |
|---|--------|-------|-------------|
| 1 | `stage` | Stage code | string |
| 2 | `tokens` | Stage tokens | integer, no thousands separator |
| 3 | `model` | that stage's `model` | alias verbatim |
| 4 | `cost` | Stage cost | bare number, 3 dp, `.` point, **no `$`** |
| 5 | `% of total` | % of total | bare integer 0–100, **no `%`** |

Columns 2, 4 and 5 come from § Derived Quantities, Units, Rounding; cells equal the markdown `### By Stage` cells minus `$`, `%` and separators.

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

One row per stage **with data**, in execution order — `stages_complete`, the current stage, then any later stage with rows. Stages without rows are **omitted**, as in `by_stage`. `--stage <code>` narrows the export to that row but keeps the full-run `% of total` denominator, so it shows the stage's true share, not a self-referential 100.

### CSV Quoting

`csv-export-templates` covers line-break quoting; additionally quote any cell containing the delimiter or a double quote, per RFC 4180 — wrap in `"`, double every embedded `"`, as in `TL;4000;"sonnet;fallback";0.012;9`. `model` is free text out of `CLAUDE_TASK_METADATA_MODEL` and the realistic carrier of a stray `;`: unquoted it shifts every later column while the import still reports success.

### CSV Missing-Data Fallback

§ Missing-Data Fallback applies unchanged, with the hook-not-configured warning going to the report (stderr under `--json`) and never into the CSV — a comment or note row breaks the header contract on import. With no worktask anchored there is nothing to estimate from: write **no file** and report the error, rather than leave a stale `cost-report.csv` to be read as current.

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
/cost-report
/cost-report --worktask-id 20260816-dark-mode --stage AR
/cost-report --optimize --detailed        # + per-operation rows
/cost-report --budget-alert 60% --bg-activity
/cost-report --export --compare <task-id>
/cost-report --json | jq .cost_tracking.budget_used_percent
```

## Data Source

`.context/logs/cost-*.jsonl`, written by the `SubagentStop` hook (`skills/cost-optimization/SKILL.md § Per-Stage Tracking`) — one line per subagent invocation, aggregated by `stage` per § Derived Quantities, Units, Rounding. Cache Performance also reads `cache_read_input_tokens` / `cache_creation_input_tokens`; `effort` powers Effort Distribution.

### Audit Dedup Before Aggregation

`.context/logs/audit.jsonl` carries BOTH hook-emitted rows (`actor: "hook:audit-tooluse"`) and forward-compatible agent rows, so **deduplicate before aggregating** — each pair otherwise inflates an Effort Distribution count by 1:

```bash
skills/agent-coordination/scripts/audit-dedup.sh .context/logs/audit.jsonl \
  | jq -c 'select(.action == "tool_invoked")'   # then group_by stage+effort, both // "unknown"
```

Dedup is keyed on `metadata.dedupe_key`; singletons without one (`approval_received`, `stage_transition`) pass through. Hook authority: `skills/agent-coordination/SKILL.md § Writers`; verify with `audit-dedup.sh --self-test`.

### Missing-Data Fallback

No `cost-*.jsonl` → estimate from `skills/cost-optimization/references/token-baselines.md` and warn that the hook is not configured. Cache columns missing or zero → `n/a`, per § Cache Performance.

Under `--json` that warning cannot go to stdout without breaking the single-object contract, so emit the **full** baseline-populated schema plus a top-level `warning` string inside `cost_tracking` naming the missing glob and the unconfigured hook — never partial, never empty, never a failure. `warning` is absent, not `null`, on a normal run, so `has("warning")` is the estimated-vs-measured test.

## Integration

Cost monitoring mid-worktask, optimization checks at stage transitions, final analysis at completion, FN budget and timing recap by `agents/project-manager.md`. Costs group **by stage**; `/agent-report` names the agent behind each row from the same audit trail.
