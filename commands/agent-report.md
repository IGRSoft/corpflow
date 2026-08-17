---
name: agent-report
description: Report which agents actually executed during a worktask, from the audit trail rather than from planned stage assignments
argument-hint: '[--worktask-id ID] [--vs-assigned] [--json]'
allowed-tools: Read, Bash, Glob
model: sonnet
related:
  - commands/cost-report.md
  - skills/agent-coordination/SKILL.md
  - skills/agent-coordination/references/hook-monitoring.md
  - skills/cost-optimization/SKILL.md
---

# Agent Report

List every agent that **actually ran** during a worktask — stage, agent name,
dispatch parent, model, duration, effort, result — sourced from the audit trail.

## Assignment Is Not Execution

`.context/state.json` records the agent each stage was **assigned**
(`metadata.agent`). Retries, escalations and cross-plugin routing mean a
different agent frequently **ran**. This command never reads `metadata.agent` as
its Agent column; doing so would look correct in the common case and be silently
wrong in exactly the cases the report exists for. `--vs-assigned` puts the two
side by side, and a divergence there is a finding, not a defect.

`/cost-report` answers *what did it cost*, grouped by stage. This answers *who
ran*, per invocation. Neither restates the other.

## Usage

```
/agent-report
/agent-report --worktask-id 20260816-agent-report
/agent-report --vs-assigned
/agent-report --json
```

## Options

- `--worktask-id <id>` — report on a specific worktask instead of the anchored one
- `--vs-assigned` — add the `Assigned` column and mark rows where it differs from the executed agent
- `--json` — emit the summary as one JSON object on stdout instead of the markdown report

## Output Format

```
## Agents Executed: [Task Name]

| # | Stage: Agent | agent_id | Parent | Model | Duration | Effort | Result |
|---|--------------|----------|--------|-------|----------|--------|--------|
| 1 | PL: corpflow:product-manager | agt_pl | none | opus | 42.1s | high | ok |
| 2 | AR: corpflow:software-architector | agt_ar | none | opus | 1m 08s | high | ok |
| 3 | DV: corpflow:developer | agt_dv | none | sonnet | 3m 22s | high | ok |
| 4 | DV: apple-developer:ios-developer | agt_ios | agt_dv | sonnet | 2m 51s | high | ok |
| 5 | QA: corpflow:qa-engineer | agt_qa | none | sonnet | 55.3s | medium | ok |

### Distinct Agents
5 agents ran: corpflow:product-manager, corpflow:software-architector,
corpflow:developer, apple-developer:ios-developer, corpflow:qa-engineer
```

### Row Rendering

| Column | Source | Rule |
|--------|--------|------|
| `Stage: Agent` | `metadata.stage` + `subject` | `unknown: <agent>` when the stage is unstamped — never guessed from position |
| `agent_id` | `metadata.agent_id` | `unknown` when absent |
| `Parent` | `metadata.parent_agent_id` | `none` at depth 0; a value here means a sub-dispatch |
| `Model` / tokens | `cost-*.jsonl` join | **blank** when unmatched — see § Cost Enrichment |
| `Duration` | `metadata.duration_ms` | `< 60s` as `NN.Ns`, else `Nm NNs`; `—` when 0 |
| `Effort` | `metadata.effort` | verbatim, `unknown` included |
| `Result` | `result` | verbatim |

#### Ordering, Qualifiers, Counts

Rows are ordered by `ts`, ascending — execution order, not stage order, so a
retry appears after the run it retried.

**A cross-plugin agent keeps its plugin qualifier.** `DV: apple-developer:ios-developer`
never collapses to `DV: ios-developer`: the qualifier distinguishes the routed
specialist from a same-named local agent, and the two are distinguishable in the
source data.

The distinct-agent count is `unique(subject)` over the rendered rows, so it is
always ≤ the row count. One agent invoked at three stages is one distinct agent
and three rows.

### Assignment Comparison (`--vs-assigned`)

Adds `Assigned` from `state.json` `stages.<CODE>.metadata.agent`, and marks the
row `≠` where it differs from the executed agent. Stages with no assignment
render `—`. An executed agent with no matching stage assignment (a sub-dispatch,
which is never assigned) also renders `—`, not `≠`.

## Data Source

Reads `.context/logs/audit.jsonl` — the authoritative execution record, written
by `hooks/audit-subagent.sh` on `SubagentStop`. Rows are selected on
`action == "subagent_stopped"`, plus `action == "stage_completion_hook"`
(`hooks/agent-stop.sh`, PL/FN/ST boundary agents only).

### Dedup Before Rendering

The same completion is written by the canonical hook and mirrored by every
installed sibling plugin. Pipe through the canonical filter — do not re-derive
the rule:

```bash
skills/agent-coordination/scripts/audit-dedup.sh .context/logs/audit.jsonl \
  | jq -c 'select(.action == "subagent_stopped" or .action == "stage_completion_hook")'
```

Dedup is keyed on `metadata.dedupe_key`, and within a key the canonical writer
outranks an `advisory: true` plugin mirror. The mirrors carry thinner metadata,
so taking the wrong one silently blanks the agent name. See
`skills/agent-coordination/SKILL.md § Writers`.

### Cost Enrichment (Optional, Never Gating)

`audit.jsonl` and `cost-*.jsonl` share **no invocation id**. The join is
best-effort on `(metadata.stage, subject)` ↔ `(stage, agent_type)`, disambiguated
by nearest `ts` when a stage ran the same agent more than once.

The audit log is authoritative; cost data is enrichment. **An audit row with no
cost match still renders**, with `Model` and any token columns blank. A cost row
with no audit match is not a row in this report — nothing executed that the
audit trail did not see.

### Missing-Data Fallback

The command **degrades, never errors**. Ladder, most severe first:

| Condition | Behavior |
|-----------|----------|
| No `.context/logs/audit.jsonl` | No table. Warning: `SubagentStop hook not configured — no execution record`. Exit 0. |
| File present, no matching rows | No table. Same warning, noting the file exists but holds only tool rows. |
| Rows present, `subject == "unknown"` | Row still renders as `<stage>: unknown`. Footnote counts them: identity was unrecoverable at capture time, or the row predates the identity fix in `hooks/audit-subagent.sh`. |
| No `cost-*.jsonl` | Table renders; `Model` blank. Note points at `skills/cost-optimization/SKILL.md § Capture Script` — that hook is operator-installed, so its absence is expected, not a fault. |
| No worktask anchored | Report the error and write nothing. There is nothing to scope the log to. |

#### Filter Exit Codes

Test for `audit.jsonl` **before** invoking the filter: `audit-dedup.sh` exits 1
on an unreadable source, and that exit code must not surface as a command
failure — the top row of the ladder above is a warning, not an error.

#### Unknown Agent Names

An `unknown` agent name is reported as a **capture gap**, never silently dropped
and never back-filled from `state.json` — a back-filled name is an assignment
wearing an execution's clothes.

## Budget Tracking JSON

**Normative `--json` output contract.** Exactly one JSON object on stdout — no
markdown, no log lines.

```json
{
  "agent_report": {
    "worktask_id": "20260816-agent-report",
    "invocations": [
      {
        "ts": "2026-08-16T09:14:02Z",
        "stage": "DV",
        "agent": "apple-developer:ios-developer",
        "agent_id": "agt_ios",
        "parent_agent_id": "agt_dv",
        "model": "sonnet",
        "duration_ms": 171000,
        "effort": "high",
        "result": "ok",
        "assigned_agent": null
      }
    ],
    "distinct_agents": ["apple-developer:ios-developer"],
    "distinct_agent_count": 1,
    "unnamed_invocation_count": 0
  }
}
```

### Field Contract

| Field | Type | Source |
|-------|------|--------|
| `worktask_id` | string | `.context/state.json`; `null` when none anchored |
| `invocations` | array | One entry per deduped audit row, `ts` ascending |
| `invocations[].model` | string \| null | `null` when the cost join found no match |
| `invocations[].assigned_agent` | string \| null | Populated only under `--vs-assigned`; `null` otherwise and for sub-dispatches |
| `distinct_agents` | array of string | `unique(agent)`, plugin qualifiers intact, `"unknown"` excluded |
| `distinct_agent_count` | integer | `distinct_agents | length` |
| `unnamed_invocation_count` | integer | Rows whose agent resolved to `unknown` |
| `warning` | string | Present only when a § Missing-Data Fallback row fired; absent — not `null` — otherwise |

#### Composition

`--json` composes with `--worktask-id` and `--vs-assigned`. It never fails and
never emits a partial object: on any fallback it emits the full schema with an
empty `invocations` array plus `warning`.

## Deferred

- `--stage <code>` filter and a `--tree` view over `parent_agent_id`. The tree
  needs a populated chain; `parent_agent_id` is `"none"` on every row the current
  runtime writes, so the view would render a flat list with extra ceremony.
- `--compare <task-id>` across worktasks.

## Integration

- After a worktask completes, to confirm the pipeline routed as intended
- When a stage's output does not look like the assigned agent's work
- Beside `/cost-report` at FN — that one prices the run, this one names it
