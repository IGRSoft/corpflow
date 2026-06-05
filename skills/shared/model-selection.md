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

> **Opus 4.8 Effort Levels** (latest, v2.1.154+): `low` ○, `medium` ◐, `high` ●, `xhigh` ⬣ (v2.1.111+), `max` ⬛. **Default effort is `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans (v2.1.94). Pro/Max subscribers also get `high` default on **Opus 4.6 and Sonnet 4.6** (v2.1.117+ — was `medium`). Pro plan continues to retain medium default on older models. The keyword "ultrathink" still triggers high effort. Use `/effort auto` to reset; `/effort` opens an interactive slider with **Faster/Smarter** labels (v2.1.154; was arrow-key navigation in v2.1.111). Opus 4.6 and Opus 4.7 remain supported. Use `/effort xhigh` for hardest tasks requiring maximum reasoning.

> **Opus 4.8 context window** (v2.1.154+): Opus 4.8 has a native **1M context window** (same as Opus 4.7 — v2.1.117 fix originally applied to 4.7). Claude Code correctly computes `/context` percentages against the full 1M window — eliminates premature autocompacting on long Opus 4.8 sessions.

> **Hook Effort Visibility** (v2.1.133+): hooks observe the active effort tier via `effort.level` (JSON payload) and the `$CLAUDE_EFFORT` env var. Cost/audit hooks can attribute spend per tier without parsing model metadata. See `skills/agent-coordination/references/hook-monitoring.md § Hook Effort Visibility`.

> **Fast Mode on Opus 4.8** (v2.1.154): fast mode on Opus 4.8 delivers **2x rate for 2.5x speed**. `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE` was **removed in v2.1.160** (deprecated 2026-06-01) — pin fast mode via `/model` selection instead. Plugin agents that rely on `xhigh` effort now require Opus 4.8 (was Opus 4.7 in v2.1.111+).

> **Auto mode on Bedrock/Vertex/Foundry** (v2.1.158): `CLAUDE_CODE_ENABLE_AUTO_MODE=1` enables auto model/effort selection for Opus 4.7/4.8 on Bedrock, Vertex, and Foundry providers (previously first-party only). Opt-in; leaves explicit `--model`/`--effort` (and `metadata.model`) overrides authoritative when set.

> **Lean system prompt default** (v2.1.154): Opus 4.8 uses a lean (shorter) system prompt by default. Haiku, Sonnet, and Opus ≤4.7 continue to use the standard system prompt.

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
Task({ subagent_type: "igrsoft:qa-engineer", model: "sonnet", prompt: "..." })
```

Team agents inherit leader's model by default. Override only when complexity warrants it.
