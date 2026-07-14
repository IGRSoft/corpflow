---
name: cost-report
description: Generate cost analysis for worktasks with token usage breakdown and optimization recommendations
argument-hint: '[--worktask-id ID] [--format table|csv]'
allowed-tools: Read, TaskList
model: sonnet
related:
  - skills/cost-optimization/SKILL.md
  - skills/context-compression/SKILL.md
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
```

## Options

- `--stage <code>` - Show costs for specific stage only (PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR)
- `--budget-alert <percent>` - Set alert threshold (default: 75%)
- `--export` - Export cost data to CSV
- `--optimize` - Include optimization recommendations
- `--detailed` - Show per-operation token breakdown (includes Background Activity)
- `--bg-activity` - Show Background Activity table only (default off to keep summary compact; v3.10.6+)
- `--compare <task-id>` - Compare costs with another task

## Output Format

### Summary Report (Default)

```
## Cost Report: [Task Name]

### Overview
| Metric | Value |
|--------|-------|
| Total Tokens | 45,000 |
| Estimated Cost | $0.28 |
| Budget Used | 56% |
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
| Stage | input_tokens | cache_read | cache_create | hit_ratio | F1 fallbacks |
|-------|--------------|------------|--------------|-----------|--------------|
| PL    |        7,500 |          0 |        7,200 |       0%  |            0 |
| AR    |       15,000 |      6,800 |        7,500 |      31%  |            0 |
| TL    |        4,000 |      3,100 |          200 |      78%  |            0 |
| DV    |       18,500 |     11,200 |        1,400 |      62%  |            0 |
| DR    |        6,200 |      4,900 |          150 |      79%  |            0 |
| QA    |        9,800 |      6,300 |          500 |      64%  |            0 |
| **Average** | — | — | — | **52% ⚠** | **0** |
```

#### Cache Performance — Field Notes

- `hit_ratio = cache_read_input_tokens / (input_tokens + cache_read_input_tokens)`.
- Row flagged with ⚠ when ratio < 60%. Cross-stage **average** is the AC-14 target (≥ 60%); flag the average row when below.
- PL is always 0% (cold cache); the average excludes PL once at least 3 downstream stages have data so a single cold prefix doesn't drag the headline.
- `F1 fallbacks` counts lines in `.context/logs/fallback-${N}.log` for that stage (zero in healthy runs). A non-zero count means the agent ran without `.context/state.json` and lost cache benefit silently — investigate even if the headline ratio looks OK.
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
- `unknown` rows are historical entries logged before effort capture (plugin v3.10.0) — current runtimes always export `CLAUDE_EFFORT`, so persistent new `unknown` rows indicate a broken hook environment.

### Background Activity (v3.10.6+, `--bg-activity` or `--detailed`)

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

- `bg_tasks_active` = max(`metadata.background_tasks_count`) observed across hook rows for that stage in `audit.jsonl` (writers: `hook:audit-subagent`, `hook:agent-stop`; field added v3.10.6).
- `session_crons` = same, for `metadata.session_crons_count`.
- `dispatch_depth` = computed from the `metadata.parent_agent_id` chain — 0 when `"none"`, otherwise `1 + depth(parent)`. Activates with CC ≥ 2.1.172 (sub-agents spawn sub-agents up to 5 levels deep) — depths ≥ 1 now appear whenever a stage agent delegates to a specialist; on older CC the column stays 0.

#### Background Activity — Notable Column & Dedup Mode

- `notable` = comma-joined `metadata.background_task_ids` and `metadata.session_cron_ids` when count > 0; otherwise `—`. Watch for the literal `"unknown"` string — signals the canonical ID-field name has shifted (see `skills/agent-coordination/references/hook-monitoring.md § BG-Task ID Schema Watch`).
- Aggregation MUST first call `hooks/audit-dedup.sh --check-mode` (plugin root: `${CLAUDE_PLUGIN_ROOT}` if available, else resolve per `skills/shared/plugin-root-resolution.md`) to pick the authoritative key (`base` or `extended`), then group rows by stage and compute max/sum/depth. Pinning the mode at startup avoids mixed-mode dedup (forbidden per `skills/agent-coordination/SKILL.md § Dedupe Key Migration`).

#### Background Activity — Version Requirements

Background activity columns require plugin v3.10.6+ audit rows. Earlier `audit.jsonl` rows lack these fields; values default to `0` / `—`. The helper `hooks/audit-dedup.sh --check-mode` decides whether to dedup on `dedupe_key` (base) or `dedupe_key_extended` (parent-aware) for correctness in multi-track parallel runs.

### Optimization Report (`--optimize`)

Emit `## Optimization Recommendations` grouped **High Impact** / **Medium Impact** — each item: current state, recommendation, estimated savings ($, %) — plus a `### Model Usage Summary` table (`Model | Invocations | Tokens | Cost`). Source the strategies from `skills/cost-optimization/SKILL.md` (model downgrade per task type, context compression at thresholds, batched reads).

### Stage Detail (`--stage DV`)

Emit `## <Stage> Cost Detail` with: `### Summary` (Total Tokens, Model, Cost, Duration), `### Operation Breakdown` (per-operation tokens + cost from that stage's cost-*.jsonl rows), `### Context Usage` (input context / output generated / overhead).

## Cost Calculation

```
Stage Cost = (Input Tokens × input rate) + (Output Tokens × output rate)
```

Model rates: canonical table in `skills/shared/model-selection.md § Cost Tiers` — do not hardcode rates here; pull current `$/1M` from `/model` when the table lags.

### Budget Tracking

```json
{
  "cost_tracking": {
    "total_estimated_tokens": 45000,
    "total_cost": 0.28,
    "budget_limit": 0.50,
    "budget_used_percent": 56,
    "by_stage": {
      "PL": { "tokens": 7500, "model": "opus", "cost": 0.113 },
      "AR": { "tokens": 15000, "model": "opus", "cost": 0.225 }
    },
    "alerts": []
  }
}
```

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
/cost-report --export                 # writes cost-report.csv to .context/
/cost-report --compare <task-id>      # side-by-side with another worktask
```

## Data Source

Reads `.context/logs/cost-*.jsonl` written by the `SubagentStop` hook (see
`skills/cost-optimization/SKILL.md` § Per-Stage Tracking). Each JSONL line is
one subagent invocation — the aggregator groups by `stage`, sums `input_tokens`
+ `output_tokens`, and applies the `model` rate.

### Audit Dedup Before Aggregation

**Audit-trail input is deduplicated before aggregation** (v3.10.1+). The
`### Effort Distribution` table sources `(stage, effort)` counts from
`.context/logs/audit.jsonl`, which since v3.10.0 carries BOTH hook-emitted rows
(`actor: "hook:audit-tooluse"`) and forward-compatible agent-emitted rows. Pipe
through the canonical dedup filter before counting:

```bash
skills/agent-coordination/scripts/audit-dedup.sh .context/logs/audit.jsonl \
  | jq -c 'select(.action == "tool_invoked")' \
  | jq -s 'group_by([.metadata.stage // "unknown", .metadata.effort // "unknown"]) | …'
```

#### Dedup Key & Verification

Without the dedup step, every hook+agent paired row inflates the `(stage, effort)`
count by 1 — most visibly on stages where both writers fire (Write/Edit, TaskCreate/
TaskUpdate). Dedup is keyed on `metadata.dedupe_key`; rows without one (singletons
such as `approval_received`, `stage_transition`) pass through unchanged. See
`skills/agent-coordination/SKILL.md § Writers` for the hook-authority rule and
`skills/agent-coordination/scripts/audit-dedup.sh --self-test` to verify the
filter against a synthetic fixture.

### Cache Performance Inputs

The Cache Performance table additionally reads:

- `cache_read_input_tokens` / `cache_creation_input_tokens` columns from the same JSONL (added in plugin v3.9.0; exported by Claude Code on `SubagentStop` as `CLAUDE_CACHE_READ_INPUT_TOKENS` / `CLAUDE_CACHE_CREATION_INPUT_TOKENS`).
- `effort` column added in plugin v3.10.0; sourced from `CLAUDE_EFFORT` and powers `### Effort Distribution`.
- `.context/logs/fallback-*.log` line counts for the F1 fallback column (one line per agent that fell back to legacy `metadata.context_files` mode; see `skills/shared/stage-contracts.md § F1`).

### Missing-Data Fallback

If `.context/logs/cost-*.jsonl` is absent, the command falls back to estimated
baselines from `skills/cost-optimization/references/token-baselines.md` and
prints a warning that the hook is not configured. If the JSONL exists but the
cache columns are missing or zero, the Cache Performance table renders `n/a`
and prints a note pointing at the Capture Script update.

## Integration

This command is used:
- Throughout worktask for cost monitoring
- At stage transitions for optimization checks
- At worktask completion for final analysis
- By project-manager (FN stage) for budget reporting and timing recap

