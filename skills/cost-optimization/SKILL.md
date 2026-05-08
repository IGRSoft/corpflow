---
name: cost-optimization
description: Cost tracking and optimization strategies for AI agent workflows. Apply for budget management, model selection, and efficiency analysis.
effort: medium
---

# Cost Optimization

Comprehensive strategies for managing AI agent costs, tracking token usage, and optimizing workflow efficiency.

For per-stage token baselines, context window improvements, and ethics cost budgeting, see `${CLAUDE_SKILL_DIR}/references/token-baselines.md`

## Model Cost Tiers & Selection Matrix

Canonical tables live in `${CLAUDE_SKILL_DIR}/../shared/model-selection.md` (§ Cost Tiers, § Selection Matrix by Task Type). For non-Pro plans, prefer explicit `effort: medium` in frontmatter for cost-sensitive stages (QA, DC, RE). For long-running sessions that benefit from extended cache retention, set `ENABLE_PROMPT_CACHING_1H=1` to use a 1-hour prompt cache TTL (v2.1.108).

## Per-Effort Thinking-Budget Ceilings

Effort levels (`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛) map to thinking-token ceilings. Use these as a budget signal — Claude Code does not enforce them, but they justify per-agent `effort:` assignments and let reviewers calibrate complexity to cost.

| Effort  | Thinking Budget | Use For                                                       | Example Agents                                            |
|---------|-----------------|---------------------------------------------------------------|-----------------------------------------------------------|
| `low`     | ≤ 4K tokens     | Mechanical tasks, formatting, routing, status updates           | haiku-tier supports                                          |
| `medium`  | ≤ 16K tokens    | Standard implementation, code review, coordination             | qa-engineer, technical-writer, release-engineer              |
| `high`    | ≤ 32K tokens    | Multi-step reasoning, default for sonnet/opus on API/Team plans | developer, technical-lead, project-manager (default since v2.1.94) |
| `xhigh`   | ≤ 50K tokens    | Hard tradeoffs, meta-optimization, architecture                | software-architector, security-reviewer, prompt-engineer     |
| `max`     | ≤ 64K tokens    | Reserved for novel-domain research; cap risk of runaway thinking | (none assigned by default)                                   |

**Rule of thumb**: increase effort one tier when a stage repeatedly retries with `classification: logic`; decrease one tier when the stage trivially passes on first try across three consecutive runs.

## Cost Reduction Strategies

### 1. Model Right-Sizing

**Strategy**: Use the cheapest model capable of the task.

```
Before: All stages use sonnet
After:  Q and W use haiku for procedural tasks
Savings: ~30% on those stages
```

**Implementation Checklist**:
- [ ] Status checks → haiku
- [ ] Formatting operations → haiku
- [ ] Simple validation → haiku
- [ ] Code generation → sonnet
- [ ] Complex analysis → sonnet
- [ ] Architecture decisions → opus (only when needed)

### 2. Context Compression

**Strategy**: Reduce token count through intelligent summarization.

| Technique | Token Reduction | When to Apply |
|-----------|-----------------|---------------|
| Artifact references | 60-80% | Always - reference paths, not content |
| Decision summaries | 40-60% | Stage handoffs |
| Code path notation | 70-90% | When discussing code structure |
| Bullet vs prose | 30-50% | All documentation |

**Example**:
```
Before (500 tokens):
"In the analysis phase, we thoroughly examined the authentication
system and determined that we should implement JWT-based auth
because it provides stateless verification, works well with
microservices, and has excellent library support..."

After (80 tokens):
## AR3 Decision: JWT Auth
- Stateless verification
- Microservice compatible
- Good library support
See: .context/analyzing-N.md#auth-decision
```

### 3. Context Window Efficiency

**Strategy**: Leverage automatic Claude Code improvements that reduce context usage without agent changes.

See `${CLAUDE_SKILL_DIR}/references/token-baselines.md` for the full list of CC version improvements.

### 4. Batch Operations

**Strategy**: Combine related queries into single invocations.

```
Before: 5 separate file reads (5 API calls)
After:  1 batch read request (1 API call)
Savings: ~80% on overhead tokens
```

**Batch Patterns**:
- Group all file reads before analysis
- Combine related search queries
- Cache repeated lookups within session

### 5. Early Termination

**Strategy**: Exit stages early when completion criteria met.

| Scenario | Action |
|----------|--------|
| Simple bug fix | Skip AR stage, minimal TL stage |
| Documentation-only | Skip DV stage, minimal QA stage |
| Hotfix | Use `quick:` workflow (PL→DV→DR→QA only) |
| Trivial change | Use `micro:` (plan → approve → execute) |

**Workflow Selection Guide**:
```
Complexity → Workflow → Stages → Est. Cost
Trivial    → micro:   → 1      → $0.01-0.02
Simple     → quick:   → 4      → $0.05-0.10
Standard   → workflow:→ 9      → $0.20-0.40
Complex    → workflow:→ 9+iter → $0.50-1.00+
```

## Per-Stage Tracking

Hook-based capture of every subagent invocation produces a per-stage JSONL trail
for the `/cost-report` aggregator and the FN-stage timing recap.

### SubagentStop Hook

Add to project `settings.json`:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "igrsoft:.*",
        "command": ".claude/hooks/cost-log.sh",
        "if": "$CLAUDE_TASK_METADATA_STAGE != ''"
      }
    ]
  }
}
```

### Capture Script (`.claude/hooks/cost-log.sh`)

```bash
#!/usr/bin/env bash
mkdir -p .context/logs
STAGE="${CLAUDE_TASK_METADATA_STAGE:-unknown}"
TS=$(date -u +%Y%m%d-%H%M%S)
LOG=".context/logs/cost-${STAGE}-${TS}.jsonl"
jq -cn --arg ts "$(date -u +%FT%TZ)" '{
  ts: $ts,
  agent_type: env.CLAUDE_SUBAGENT_TYPE,
  task_id: env.CLAUDE_TASK_ID,
  stage: env.CLAUDE_TASK_METADATA_STAGE,
  model: env.CLAUDE_TASK_METADATA_MODEL,
  input_tokens: (env.CLAUDE_INPUT_TOKENS // "0" | tonumber),
  output_tokens: (env.CLAUDE_OUTPUT_TOKENS // "0" | tonumber),
  duration_ms: (env.CLAUDE_DURATION_MS // "0" | tonumber),
  status: env.CLAUDE_SUBAGENT_STATUS
}' >> "$LOG"
```

### Schema

```jsonc
{
  "ts": "ISO-8601 UTC",
  "agent_type": "e.g., igrsoft:developer",
  "task_id": "Task System ID",
  "stage": "PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET",
  "model": "opus|sonnet|haiku",
  "input_tokens": 0,
  "output_tokens": 0,
  "duration_ms": 0,
  "status": "completed|error|cancelled"
}
```

### Aggregation

`/cost-report` reads all `.context/logs/cost-*.jsonl` files, groups by `stage`,
and renders the `### By Stage` table. See `commands/cost-report.md` § Data Source.

## Prompt Caching (1h TTL) & Handoff Protocol

The handoff protocol (`skills/workflow/references/handoff-protocol.md`) is built around the Anthropic prompt cache. Two recommendations make the savings real:

### Recommended `settings.json` stanza

```json
{
  "env": {
    "ENABLE_PROMPT_CACHING_1H": "1"
  }
}
```

Why: the default 5-min TTL is shorter than many stage durations (especially DV/QA on complex features). The 1h TTL keeps the preamble cache warm across slow stages. Users without this flag still see savings on retries within a single stage but lose cross-stage cache hits on long stages. (RK-8 in `analyzing.md#risks`.)

### state-merge.sh SubagentStop hook

The handoff protocol uses an OPTIONAL `.claude/hooks/state-merge.sh` SubagentStop hook as a belt-and-suspenders layer for state.json updates. Add to project `settings.json`:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "igrsoft:.*",
        "command": ".claude/hooks/state-merge.sh",
        "if": "$CLAUDE_TASK_METADATA_STAGE != ''"
      }
    ]
  }
}
```

Hook contract (per `analyzing.md#integration-points § IP-2`):

- Reads `CLAUDE_ARTIFACT_PATH` (or globs `.context/<artifact-name>.md` per stage code as fallback).
- Parses the artifact's `handoff:` frontmatter (yq if available; awk subset fallback).
- Idempotent: if state.json already reflects this frontmatter, exits 0 silently.
- Otherwise atomic-merges into state.json (read → merge → temp → fsync → rename per `handoff-protocol.md#atomic-write`).
- Exits 0 always — MUST NOT block stage transition. Failures log to `.context/logs/state-merge.log`.

### Expected cache_read_input_tokens ratio

Per `handoff-protocol.md#cache-prefix`:

- Stage 1 (PL): 0% (cold cache).
- Stage 2..N, no retry: ≈ 20% (cross-stage prefix [1]+[2] cached).
- Stage 2..N, retry within same stage: ≈ 80% (full preamble cached).
- Cross-stage average: ≈ 60% — meets AC-14 threshold.

CI lint (`skills/workflow/references/cache-lint.sh`) asserts byte-stability of preamble sections [1]+[2]+[4] across consecutive stages of the same `workflow_id`. Drift collapses cache-hit rate.

## Budget Tracking

### Cost Estimation Formula

```
Estimated Cost = Base Tokens × Model Cost × (1 + Retry Factor) × Complexity Multiplier

Where:
- Base Tokens: From per-stage baselines
- Model Cost: Per-token rate for selected model
- Retry Factor: 0.1 (low), 0.2 (medium), 0.5 (high complexity)
- Complexity Multiplier: 1.0 (standard), 1.5 (large codebase), 2.0 (novel domain)
```

### Budget Alert Thresholds

| Threshold | Alert Level | Action |
|-----------|-------------|--------|
| **50%** | Warning | Log to console |
| **75%** | Notify | Alert user, suggest optimizations |
| **90%** | Critical | Force context compression, recommend model downgrades |
| **100%** | Pause | Stop workflow, require explicit approval to continue |

## Optimization Checklist

Before starting workflow:
- [ ] Select appropriate workflow type (micro/quick/standard)
- [ ] Set budget limit if applicable
- [ ] Verify model assignments per stage

During workflow:
- [ ] Monitor token usage at stage transitions
- [ ] Apply context compression at handoffs
- [ ] Use haiku for sub-tasks where possible

After workflow:
- [ ] Review cost breakdown by stage
- [ ] Identify optimization opportunities
- [ ] Update baseline estimates if needed

## Quick Reference

### Cost-Effective Patterns

| Pattern | Description | Savings |
|---------|-------------|---------|
| **Reference, don't copy** | Point to artifacts instead of including | 60-80% |
| **Summarize decisions** | Bullet points over paragraphs | 40-60% |
| **Right-size models** | Haiku for simple, sonnet for moderate | 30-50% |
| **Batch operations** | Combine related queries | 20-40% |
| **Early termination** | Exit when criteria met | Variable |

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Including full file content | Wastes context | Reference by path |
| Opus for simple tasks | 50x cost increase | Use haiku/sonnet |
| Separate API calls for each file | Overhead tokens | Batch reads |
| Retrying without context compression | Compounds cost | Compress first |
| Full workflow for trivial changes | Unnecessary stages | Use micro/quick |

## Related Skills

- `${CLAUDE_SKILL_DIR}/../workflow/SKILL.md` - Workflow system documentation
- `${CLAUDE_SKILL_DIR}/../agent-coordination/SKILL.md` - Multi-agent coordination patterns
- `${CLAUDE_SKILL_DIR}/../claude-constitution/SKILL.md` - Constitutional principles and ethics framework
