---
name: model-selection
description: Model selection guidelines for haiku/sonnet/opus tier selection, cost tiers, and selection criteria. Reference when choosing models for agent delegation or task routing.
effort: low
---

# Model Selection Guidelines

## Cost Tiers

| Model | Relative Cost | Cost/1M Tokens | Use For |
|-------|---------------|----------------|---------|
| **haiku** | 1x (baseline) | ~$0.25 | Formatting, routing, checklists, status checks |
| **sonnet** | ~10x haiku | ~$3.00 | Implementation, analysis, code review, coordination |
| **opus** | ~50x haiku | ~$15.00 | Architecture decisions, complex reasoning, meta-optimization |

> **Opus 4.7 Effort Levels**: `low` ○, `medium` ◐, `high` ●, `xhigh` ⬣ (v2.1.111+), `max` ⬛. **Default effort is `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans (v2.1.94). Pro plan retains medium default. The keyword "ultrathink" still triggers high effort. Use `/effort auto` to reset; `/effort` opens an interactive slider with arrow-key navigation (v2.1.111). Opus 4.6 remains supported.

## Selection Criteria

| Complexity | Model | Use Cases |
|------------|-------|-----------|
| Simple | haiku | Formatting, routing, checklists, status tracking |
| Moderate | sonnet | Implementation, analysis, coordination, reviews |
| Complex | opus | Architecture, strategy, meta-optimization, research |

**Use haiku when**:
- Task is procedural with clear steps
- Output format is well-defined
- Limited reasoning required
- High volume, low latency needed
- Cost optimization is priority

**Use sonnet when**:
- Moderate reasoning required
- Multiple considerations to balance
- Creative but bounded output
- Code implementation tasks
- Standard analysis and reviews

**Use opus when**:
- Complex multi-step reasoning
- Architectural decisions with tradeoffs
- Meta-level optimization (agents about agents)
- Novel problem solving
- High-stakes decisions

## Selection Matrix by Task Type

| Task Type | Recommended Model | Rationale |
|-----------|-------------------|-----------|
| Status checks | haiku | Simple validation |
| Task status updates | haiku | Mechanical operation |
| Code formatting | haiku | Rule-based transformation |
| Platform routing | haiku | Pattern matching |
| Code implementation | sonnet | Balanced complexity |
| Code review | sonnet | Analysis + suggestions |
| Test design | sonnet | Coverage analysis |
| Team coordination | sonnet | Multi-factor decisions |
| Architecture design | opus | Complex tradeoffs |
| System analysis | opus | Deep reasoning |
| Prompt optimization | opus | Meta-level thinking |

## Per-Invocation Override

Use `model` parameter on Task() calls to override per delegation:
```
Task({ subagent_type: "igrsoft:qa-engineer", model: "haiku", prompt: "..." })
```

Team agents inherit leader's model by default. Override only when complexity warrants it.
