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

### Opus 5

> **Opus 5** (`claude-opus-5`) is the **default Opus model** — the `opus` alias resolves here, so every opus-tier stage (PL, AR, DV, DR, SR, ET, IR, PE) gets it with no plugin change. It ships **1M context by default** with no plan qualifier and no usage-credit gate, and fast mode prices at **$10/$50 per Mtok**. Pull current steady-state pricing from `/model` or the `claude-api` skill.

#### Opus 5 effort levels

> `low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛. **Default effort is `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans; Pro plan retains `medium` default on older models. The keyword "ultrathink" still triggers high effort. `/effort auto` resets; `/effort` opens an interactive slider with **Faster/Smarter** labels. Use `/effort xhigh` for the hardest reasoning.

#### Fast mode & system prompt

> **Fast mode** (`/fast`) applies to Opus 5. It delivers a higher token rate for a higher price multiplier; pin it via `/model` selection.

> **Lean system prompt**: Opus 5 uses a lean (shorter) system prompt by default; Haiku and Sonnet use the standard one — a small standing input-token saving on opus-tier stages.

#### Prefer the alias over a pinned id

> Frontmatter and `metadata.model` should carry the **alias** (`opus`/`sonnet`/`haiku`/`fable`), not a full model id. An alias tracks the current default; a pinned id strands the stage on whatever it names once that model is superseded, and surfaces a deprecation warning at load (see § Frontmatter model-deprecation warnings).

### Fable 5 availability

> **Fable 5** (`claude-fable-5`) is the Mythos-class top reasoning model. The `fable` alias resolves on every supported CC. This plugin defaults its highest-reasoning stages (AR, DV, SR, ET, PE) to `opus`; `fable` remains a valid CC model alias for operators who choose to override. Pull the exact `$/1M` pricing from `/model` (or the `claude-api` skill) when needed.

### Fable 5 context & credits

> **Fable 5 = 1M context by default** (`[1m]`-suffixed model names normalize into the base id). On accounts **without 1M usage credits**, a fable-tier *dispatch* fails hard with `API Error: Usage credits required for 1M context` (observed live 2026-06-12); an *interactive* 1M session without credits instead auto-compacts back under the standard limit. Degrade path: set a session `fallbackModel` (`--fallback-model`) or pin the stage via a direct `Task({ model })` / `metadata.model` override.

### Fable-5 auto-mode Opus fallback

> **Fable-5 auto-mode Opus fallback**: in auto mode, when an org's allowlist lacks the current top Opus, a Fable-5 selection falls back to the **best available Opus** for that org rather than failing or down-resolving to a lower tier. So on restricted orgs, auto-mode `xhigh` stages land on the strongest Opus the org has instead of erroring.

### Managed model allowlists

> **Managed model allowlists**: a managed `availableModels` list constrains **subagent model overrides** and the dispatch model picker, and `enforceAvailableModels` extends the allowlist to the **Default model** — user/project settings cannot widen a managed list. Consequence for the worktask rule "always pass `metadata.model` to `Task({model})`": a valid alias may silently resolve to a different model under management. Pre-Stage Validation step 6 (`skills/worktask/SKILL.md`) emits an audit row instead of hard-blocking.

### Allowlist hardening + /fast refusal

> **Allowlist hardening + `/fast` refusal**: an alias that points at a model **outside** the managed list redirects to an allowed model deterministically rather than leaking the disallowed id. The `/fast` command is likewise constrained: if fast mode resolves to a model not on the allowlist, `/fast` is **refused** rather than silently switching. For worktasks this means a `metadata.model` alias under management resolves predictably (audit per step 6), and `/fast` cannot escape a managed list.

### Frontmatter model-deprecation warnings

> **Frontmatter model-deprecation warnings**: the model-deprecation warning covers models pinned in **agent frontmatter** (`model:` field), not just the interactive picker. A stage agent that frontmatter-pins a deprecated model id surfaces the deprecation at load — prefer aliases (`opus`/`sonnet`/`haiku`/`fable`) over hard-pinned ids in agent frontmatter so deprecations don't silently strand a stage.

### Sonnet 5

> **Sonnet 5**: the `sonnet` alias resolves to **Claude Sonnet 5** — the Claude Code default model, with a **native 1M-token context window** and promotional pricing ($2/$10 per Mtok through 2026-08-31; steady-state pricing via `/model` or the `claude-api` skill). Sonnet-tier stages (TL, QA, RE, FN, ST) get the capability uplift with no plugin change — this is exactly why the alias rule above exists. The `xhigh` rule is unchanged: route `xhigh` work to **Opus 5 or Fable 5**; do not assume Sonnet 5 accepts `xhigh` without verifying.

### Org default & model restrictions

> Admins can set an **org default model** (shows as "Org default"/"Role default" in `/model` when you haven't picked one), and org-configured model **restrictions** cover the picker, `--model`, `/model`, and `ANTHROPIC_MODEL` with a "restricted by your organization's settings" message — one more way a stage alias may resolve differently under management (audit per Pre-Stage Validation step 6).

### Context-window accounting

> Claude Code computes `/context` percentages against the **full 1M window** on models that have one (Opus 5, Sonnet 5, Fable 5) — no premature autocompacting on long opus-tier sessions. See `skills/context-compression/SKILL.md` for how the extended window changes stage handoff budgets, and for the without-credits caveat that applies to Fable 5.

### Hook effort visibility

> **Hook Effort Visibility**: hooks observe the active effort tier via `effort.level` (JSON payload) and the `$CLAUDE_EFFORT` env var. Cost/audit hooks can attribute spend per tier without parsing model metadata. See `skills/agent-coordination/references/hook-monitoring.md § Hook Effort Visibility`.

### Thinking-config inheritance

> **Thinking-config inheritance**: subagents and context compaction inherit the session's extended-thinking configuration — a stage dispatched without an explicit `effort` override now gets the orchestrator's thinking budget instead of a flat default, improving delegated output quality. Keep passing per-stage `metadata.model` + `effort` regardless: explicit beats inherited for stage determinism and cost attribution.

### xhigh routing

> Plugin agents that rely on `xhigh` effort require **Opus 5 or Fable 5** — Sonnet silently downgrades the thinking budget. Prefer the `opus` alias (→ Opus 5): Fable 5 carries the 1M-credit dispatch caveat above and hard-fails on credit-gated accounts.

### Auto mode on Bedrock/Vertex/Foundry

> **Auto mode on Bedrock/Vertex/Foundry**: auto model/effort selection is available on Bedrock, Vertex AI, and Foundry without an opt-in — disable it with `disableAutoMode` in settings. These providers (plus Claude-Platform-on-AWS) **default to the newest Opus they carry**, which lags the first-party default — do not assume `opus` resolves to Opus 5 on Bedrock/Vertex/Foundry; confirm via `/model`. Explicit `--model`/`--effort` (and `metadata.model`) overrides stay authoritative when set. Bedrock also resolves its region from `~/.aws` config when `AWS_REGION` is unset, and GovCloud inference profiles get the correct `us-gov` prefix — headless runners do not need to export region env explicitly on configured machines.

### Auto-mode permission classifier

> The auto-mode **permission classifier** (the small model that classifies permission decisions in auto mode) defaults to **Sonnet 5** for external sessions — validated on the session's first request and pinned for the session. This is a permission-classification detail, unrelated to the session-model defaults above.

## Selection Criteria

| Complexity | Model | Use Cases |
|------------|-------|-----------|
| Simple | haiku | Formatting, routing, checklists, status tracking |
| Moderate | sonnet | Implementation, analysis, coordination, reviews |
| Complex | opus | Planning (PL), Architecture (AR), complex development (DV), incident response (IR), high-stakes review gates (SR, ET), general high-complexity reasoning (DR/TC, PE) |

### Use haiku when
- Task is procedural with clear steps
- Output format is well-defined
- Limited reasoning required
- High volume, low latency needed
- Cost optimization is priority

### Use sonnet when
- Moderate reasoning required
- Multiple considerations to balance
- Creative but bounded output
- Code implementation tasks
- Standard analysis and reviews

### Use opus when
- Complex multi-step reasoning
- Planning and product scoping (PL) or incident response (IR)
- Novel problem solving
- Architectural decisions with tradeoffs (AR)
- High-stakes review gates: security (SR), ethics (ET)
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
| Architecture design | opus | Complex tradeoffs |
| System analysis | opus | Deep reasoning |
| Prompt optimization | opus | Meta-level thinking |

## Per-Invocation Override

Use `model` parameter on Task() calls to override per delegation:
```
Task({ subagent_type: "company-workflow:qa-engineer", model: "sonnet", prompt: "..." })
```

Team agents inherit leader's model by default. Override only when complexity warrants it. Teammates spawned via tmux/pane backends inherit the leader's `--effort` too. The built-in `Explore` agent inherits the main session's model **capped at opus** instead of running on haiku — exploration fan-outs cost sonnet/opus-tier tokens; budget accordingly or pass an explicit `model` override.

An explicit per-call model override **survives resume and follow-up `SendMessage`** — a stage pinned via `Task({model})` does not revert to the parent's model on reattach, so the "always pass `metadata.model`" discipline stays reliable across the stage's whole lifecycle, not just at initial dispatch (the `model_requested`/`model_resolved` pair in `dispatched_agents[]` should keep matching after reattach).
