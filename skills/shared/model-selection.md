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
| **fable** | premium (see `/model`) | premium (see `/model`) | Max-reasoning stages: architecture, security/ethics review, agent optimization, complex development |

> **Fable 5** (`claude-fable-5`) is the Mythos-class top reasoning model (v2.1.170). It sits above `opus` as the new top tier and is the default for the highest-reasoning stages (AR, DR/TC, DV, SR, PE, ET). The `fable` alias only resolves on **CC ≥ 2.1.170**; on CC 2.1.169 (the current plugin minimum) the alias degrades to the provider default until the operator updates. Pull the exact `$/1M` pricing from `/model` (or the `claude-api` skill) when filling the Cost/1M cell.
>
> **Fable 5 = 1M context by default** (v2.1.173 — `[1m]`-suffixed model names normalized into the base id). On accounts **without 1M usage credits**, a fable-tier *dispatch* fails hard with `API Error: Usage credits required for 1M context` (observed live 2026-06-12); an *interactive* 1M session without credits instead auto-compacts back under the standard limit (v2.1.172). Degrade path: set a session `fallbackModel` (`--fallback-model`, v2.1.166) or pin the stage via a direct `Task({ model })` / `metadata.model` override — do **not** rely on the Workflow tool's per-`agent()` `opts.model` de-escalation, which was observed not to rescue dispatch under credit gating (see `skills/worktask/references/dynamic-workflow.md` risk R8).
>
> **Managed model allowlists** (v2.1.172/v2.1.175): a managed `availableModels` list now constrains **subagent model overrides** and the dispatch model picker too (v2.1.172), and `enforceAvailableModels` (v2.1.175) extends the allowlist to the **Default model** — user/project settings can no longer widen a managed list. Consequence for the worktask rule "always pass `metadata.model` to `Task({model})`": a valid alias may silently resolve to a different model under management. Pre-Stage Validation step 6 (`skills/worktask/SKILL.md`) emits an audit row instead of hard-blocking.

> **Opus 4.8 Effort Levels**: `low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛. **Default effort is `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans. Pro/Max subscribers also get `high` default on **Opus 4.6 and Sonnet 4.6**; Pro plan retains `medium` default on older models. The keyword "ultrathink" still triggers high effort. Use `/effort auto` to reset; `/effort` opens an interactive slider with **Faster/Smarter** labels. Opus 4.6 and Opus 4.7 remain supported. Use `/effort xhigh` for hardest tasks requiring maximum reasoning.

> **Opus 4.8 context window**: Opus 4.8 has a native **1M context window** (same as Opus 4.7). Claude Code computes `/context` percentages against the full 1M window — eliminates premature autocompacting on long Opus 4.8 sessions.

> **Hook Effort Visibility**: hooks observe the active effort tier via `effort.level` (JSON payload) and the `$CLAUDE_EFFORT` env var. Cost/audit hooks can attribute spend per tier without parsing model metadata. See `skills/agent-coordination/references/hook-monitoring.md § Hook Effort Visibility`.

> **Fast Mode on Opus 4.8**: fast mode on Opus 4.8 delivers **2x rate for 2.5x speed**; pin fast mode via `/model` selection (the `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE` env var has been removed). Plugin agents that rely on `xhigh` effort require **Opus 4.8 or Fable 5** — and Fable 5 carries the 1M-credit dispatch caveat above; on credit-gated accounts route `xhigh` work to Opus 4.8.

> **Auto mode on Bedrock/Vertex/Foundry**: `CLAUDE_CODE_ENABLE_AUTO_MODE=1` enables auto model/effort selection for Opus 4.7/4.8 on Bedrock, Vertex, and Foundry providers. Opt-in; leaves explicit `--model`/`--effort` (and `metadata.model`) overrides authoritative when set. Bedrock also resolves its region from `~/.aws` config when `AWS_REGION` is unset (v2.1.172), and GovCloud inference profiles get the correct `us-gov` prefix (v2.1.174) — headless runners no longer need to export region env explicitly on configured machines.

> **Lean system prompt default**: Opus 4.8 uses a lean (shorter) system prompt by default. Haiku, Sonnet, and Opus ≤4.7 continue to use the standard system prompt.

## Selection Criteria

| Complexity | Model | Use Cases |
|------------|-------|-----------|
| Simple | haiku | Formatting, routing, checklists, status tracking |
| Moderate | sonnet | Implementation, analysis, coordination, reviews |
| Complex | opus | Planning (PL), incident response (IR), general high-complexity reasoning |
| Max-reasoning | fable | Architecture, high-stakes review gates, meta-optimization, complex development (AR, DR/TC, DV, SR, PE, ET) |

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
- Complex multi-step reasoning below the max-reasoning bar
- Planning and product scoping (PL) or incident response (IR)
- Novel problem solving
- General high-complexity work where `fable` is not warranted

**Use fable when** (top tier — the `fable` alias resolves on **CC ≥ 2.1.170** and degrades to opus/provider default below that; caveat applies to every `fable` row in this file):
- Architectural decisions with tradeoffs (AR)
- High-stakes review gates: code review (DR/TC), security (SR), ethics (ET)
- Meta-level optimization, agents about agents (PE)
- Complex development stages (DV)

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
| Architecture design | fable | Complex tradeoffs |
| System analysis | fable | Deep reasoning |
| Prompt optimization | fable | Meta-level thinking |

## Per-Invocation Override

Use `model` parameter on Task() calls to override per delegation:
```
Task({ subagent_type: "igrsoft:qa-engineer", model: "sonnet", prompt: "..." })
```

Team agents inherit leader's model by default. Override only when complexity warrants it.
