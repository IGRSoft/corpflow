---
name: cost-optimization
description: Cost tracking and optimization strategies for AI agent workflows. Apply for budget management, model selection, and efficiency analysis.
---

# Cost Optimization

Comprehensive strategies for managing AI agent costs, tracking token usage, and optimizing workflow efficiency.

## Model Cost Tiers

| Model | Relative Cost | Cost/1M Tokens | Use For |
|-------|---------------|----------------|---------|
| **haiku** | 1x (baseline) | ~$0.25 | Formatting, routing, checklists, status checks |
| **sonnet** | ~10x haiku | ~$3.00 | Implementation, analysis, code review, coordination |
| **opus** | ~50x haiku | ~$15.00 | Architecture decisions, complex reasoning, meta-optimization |

### Model Selection Matrix

| Task Type | Recommended Model | Rationale |
|-----------|-------------------|-----------|
| Status checks | haiku | Simple validation |
| TodoWrite formatting | haiku | Mechanical operation |
| Code formatting | haiku | Rule-based transformation |
| Platform routing | haiku | Pattern matching |
| Code implementation | sonnet | Balanced complexity |
| Code review | sonnet | Analysis + suggestions |
| Test design | sonnet | Coverage analysis |
| Team coordination | sonnet | Multi-factor decisions |
| Architecture design | opus | Complex tradeoffs |
| System analysis | opus | Deep reasoning |
| Prompt optimization | opus | Meta-level thinking |

## Per-Stage Token Baselines

Typical token usage by workflow stage (sonnet model):

| Stage | Code | Typical Range | Estimated Cost | Notes |
|-------|------|---------------|----------------|-------|
| **P** (Planning) | P | 5,000-10,000 | $0.015-0.03 | Requirements, prioritization |
| **A** (Architecture) | A | 10,000-20,000 | $0.03-0.06 | Design decisions, ADRs |
| **T** (Team Lead) | T | 3,000-5,000 | $0.01-0.015 | Coordination, assignment |
| **D** (Development) | D | 20,000-50,000 | $0.06-0.15 | Code implementation |
| **Q** (QA) | Q | 10,000-20,000 | $0.03-0.06 | Test design, validation |
| **W** (Writing) | W | 5,000-10,000 | $0.015-0.03 | Documentation |
| **F** (Finalization) | F | 3,000-5,000 | $0.01-0.015 | Release prep |
| **S** (Stakeholder) | S | 2,000-3,000 | $0.006-0.01 | Approval review |

**Total Workflow Range**: 58,000-123,000 tokens (~$0.17-0.37 for sonnet)

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
## A3 Decision: JWT Auth
- Stateless verification
- Microservice compatible
- Good library support
See: .context/analyzing.md#auth-decision
```

### 3. Batch Operations

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

### 4. Early Termination

**Strategy**: Exit stages early when completion criteria met.

| Scenario | Action |
|----------|--------|
| Simple bug fix | Skip A stage, minimal T stage |
| Documentation-only | Skip D stage, minimal Q stage |
| Hotfix | Use `quick:` workflow (P→D→Q only) |
| Trivial change | Use `micro:` (direct execution) |

**Workflow Selection Guide**:
```
Complexity → Workflow → Stages → Est. Cost
Trivial    → micro:   → 1      → $0.01-0.02
Simple     → quick:   → 3      → $0.05-0.10
Standard   → workflow:→ 8      → $0.20-0.40
Complex    → workflow:→ 8+iter → $0.50-1.00+
```

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
| **50%** | Warning | Log to task-state.json |
| **75%** | Notify | Alert user, suggest optimizations |
| **90%** | Critical | Force context compression, recommend model downgrades |
| **100%** | Pause | Stop workflow, require explicit approval to continue |

### Calendar Month Billing

Claude Code billing occurs per calendar month. Optimization strategies:

1. **Track month boundaries** in task-state.json
2. **Plan large workflows** to complete within single month
3. **Defer non-urgent work** if near month end with budget concerns
4. **Front-load complex stages** early in billing cycle

## Cost Tracking Schema

Add to `task-state.json`:

```json
{
  "cost_tracking": {
    "total_estimated_tokens": 45000,
    "by_stage": {
      "P": { "tokens": 7500, "model": "sonnet", "cost": 0.023 },
      "A": { "tokens": 15000, "model": "opus", "cost": 0.225 },
      "T": { "tokens": 4000, "model": "sonnet", "cost": 0.012 },
      "D": { "tokens": 0, "model": "sonnet", "cost": 0 },
      "Q": { "tokens": 0, "model": "haiku", "cost": 0 },
      "W": { "tokens": 0, "model": "haiku", "cost": 0 },
      "F": { "tokens": 0, "model": "sonnet", "cost": 0 },
      "S": { "tokens": 0, "model": "sonnet", "cost": 0 }
    },
    "budget_limit": 1.00,
    "budget_used_percent": 26,
    "alerts": [
      { "level": "info", "message": "A stage used opus model", "timestamp": "..." }
    ],
    "billing_month": "2025-01"
  }
}
```

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
