---
name: model-selection
effort: low
---

# Model Selection Guidelines

Canonical for tiers, selection criteria, and alias/model behaviour. The stage→model
assignment itself lives in `skills/shared/stage-codes.md` and is not restated here, and **how
to write a prompt for the model this file picks** lives in `skills/shared/model-prompting.md`
— that split is the reason neither file needs the other's tables.

## Cost Tiers

| Model | Relative Cost | Cost/1M Tokens | Use For |
|-------|---------------|----------------|---------|
| **haiku** | 1x (baseline) | ~$0.25 | Formatting, routing, checklists, status checks |
| **sonnet** | ~10x haiku | ~$3.00 | Implementation, analysis, code review, coordination |
| **opus** | ~50x haiku | ~$15.00 | Architecture decisions, complex reasoning, meta-optimization |

## Aliases and the models they resolve to

| Alias | Resolves to | Context | Pricing |
|-------|-------------|---------|---------|
| `opus` | **Opus 5** (`claude-opus-5`) — the default Opus | 1M by default; no plan qualifier, no usage-credit gate | fast mode $10/$50 per Mtok |
| `sonnet` | **Sonnet 5** — the Claude Code default model | native 1M | promo $2/$10 per Mtok through 2026-08-31 |
| `fable` | **Fable 5** (`claude-fable-5`) — Mythos-class top reasoning | 1M by default (`[1m]` names normalize to the base id) | via `/model` |
| `haiku` | current Haiku | standard | § Cost Tiers |

Pull steady-state pricing from `/model` or the `claude-api` skill. Opus-tier stages get
Opus 5 with no plugin change; `fable` is a valid operator override, never a plugin default.

### Prefer the alias over a pinned id

> Frontmatter and `metadata.model` carry the **alias**, never a full model id. An alias
> tracks the current default; a pinned id strands the stage once that model is superseded
> and surfaces a deprecation warning at load — that warning covers agent frontmatter
> `model:`, not just the interactive picker.

### Fable 5 credit gate

> Without 1M usage credits a fable-tier *dispatch* fails hard with `API Error: Usage
> credits required for 1M context` (observed live 2026-06-12); an *interactive* 1M session
> instead auto-compacts back under the standard limit. Degrade path: a session
> `fallbackModel` (`--fallback-model`), or a direct `Task({ model })` / `metadata.model`
> override on the stage.

### Fast mode and the lean system prompt

> `/fast` applies to Opus 5: higher token rate, higher price multiplier, pinned via
> `/model`. Opus 5 also uses a **lean system prompt** by default (Haiku and Sonnet use the
> standard one) — a small standing input-token saving on opus-tier stages.

## Effort Levels

`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛. **Default effort is `high`** for
API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans; Pro plan retains `medium`
on older models. "ultrathink" still triggers high effort; `/effort auto` resets, and bare
`/effort` opens the interactive Faster/Smarter slider. `/effort` now stores its default
**per model**, so switching model no longer carries the previous model's effort — a user
setting the pipeline does not control, which is why every stage still passes `effort`
explicitly.

### xhigh routing

> `xhigh` requires **Opus 5 or Fable 5** — Sonnet silently downgrades the thinking budget,
> and Sonnet 5 does not change that: do not assume it accepts `xhigh` without verifying.
> Prefer the `opus` alias; `fable` carries the credit gate above and hard-fails on
> credit-gated accounts.

> **Thinking disabled silently costs a tier**: `xhigh`/`max` requested in a session with
> thinking turned off is sent as `high` rather than failing. A stage pinned to `xhigh`
> (`agents/ethics-reviewer.md`, `agents/prompt-engineer.md`, `agents/security-reviewer.md`)
> then runs one tier down with no error anywhere — the step-6 audit row is the only place
> it shows. Verify there before trusting an `xhigh` stage's depth. The lost tier is not the
> only cost on Opus 5: `skills/shared/model-prompting.md § xhigh with thinking disabled` names
> the two output artifacts that appear in that configuration.

### Effort visibility and inheritance

> Hooks read the active tier from `effort.level` (JSON payload) and `$CLAUDE_EFFORT`, so
> cost/audit hooks attribute spend per tier without parsing model metadata
> (`skills/agent-coordination/references/hook-monitoring.md § Hook Effort Visibility`).
> Subagents and compaction inherit the session's extended-thinking config; keep passing
> per-stage `metadata.model` + `effort` regardless — explicit beats inherited for stage
> determinism and cost attribution.

## Managed Allowlists and Org Restrictions

Under management a valid alias may silently resolve to a different model, which is why
Pre-Stage Validation step 6 (`skills/worktask/SKILL.md`) emits an audit row rather than
hard-blocking the dispatch.

### Allowlist mechanics

| Control | Behaviour |
|---------|-----------|
| `availableModels` | Constrains subagent model overrides and the dispatch model picker; `enforceAvailableModels` extends it to the **Default model**. User/project settings cannot widen a managed list. |
| Alias outside the list | Redirects deterministically to an allowed model rather than leaking the disallowed id. |
| `/fast` | **Refused** when fast mode resolves to a non-allowlisted model — never a silent switch. |

### Restriction signals and fallbacks

| Control | Behaviour |
|---------|-----------|
| Family step-down (CC 2.1.222) | A restricted `model: opus` steps down to the newest org-allowed model **in that family**, not to the parent's model. |
| Restriction warning (CC 2.1.223) | Workflow agents, forked skills, slash commands, and resumed background agents warn when the parent runs instead of the requested restricted subagent model — check the step-6 audit row rather than assuming the alias resolved. |
| Org default / restrictions | "Org default"/"Role default" shows in `/model`; restrictions cover the picker, `--model`, `/model`, and `ANTHROPIC_MODEL` ("restricted by your organization's settings"). |
| Fable-5 auto-mode fallback | In auto mode, an org allowlist lacking the current top Opus falls back to the **best available Opus** rather than failing or down-tiering — restricted-org `xhigh` still lands on the strongest Opus available. |

#### Restriction signals — model resolution

| Control | Behaviour |
|---------|-----------|
| First-call 404 fallback | A subagent whose model 404s on its first call falls through the session's fallback-model chain instead of dying; the parent's error names type, HTTP status, request id and model. The stage then ran on a model `metadata.model` never asked for, so `dispatched_agents[].model_resolved` is the only trustworthy record — re-check it before attributing cost, never assume `model_requested` held. |
| `modelPicker` / `modelPricing` | Managed settings: `modelPicker` curates which models the `/model` list offers; `modelPricing` applies an org's contracted rates to `/cost`, the status line, and telemetry — so a cost figure read under it is org-rated, not list-rated. |

## Provider Defaults (Bedrock / Vertex / Foundry)

Auto model/effort selection is available there with no opt-in — disable via
`disableAutoMode`. These providers plus Claude-Platform-on-AWS **default to the newest
Opus they carry**, which lags the first-party default: do not assume `opus` resolves to
Opus 5; confirm via `/model`. Explicit `--model`/`--effort`/`metadata.model` stay
authoritative. Bedrock resolves its region from `~/.aws` when `AWS_REGION` is unset and
prefixes GovCloud inference profiles `us-gov`, so headless runners need no region env.

### Auto-mode permission classifier

> The small model classifying permission decisions in auto mode defaults to **Sonnet 5**
> for external sessions — validated on the session's first request, then pinned for the
> session. Permission classification only; unrelated to session-model defaults.

## Context-Window Accounting

`/context` percentages are computed against the **full 1M window** on models that have one
(Opus 5, Sonnet 5, Fable 5) — no premature autocompacting on long opus-tier sessions. How
the extended window changes stage handoff budgets, plus the Fable 5 without-credits
caveat: `skills/context-compression/SKILL.md`.

## Selection Criteria

| Complexity | Model | Signals |
|------------|-------|---------|
| Simple | haiku | Procedural steps, well-defined output format, little reasoning, high volume / low latency, cost-first |
| Moderate | sonnet | Moderate reasoning, several considerations to balance, bounded creative output |
| Complex | opus | Multi-step or novel reasoning, tradeoff-heavy decisions, high-stakes gates, meta-level work (agents about agents) |

## Selection Matrix by Task Type

| Model | Task types | Rationale |
|-------|------------|-----------|
| haiku | Status checks, task status updates, code formatting, platform routing | Mechanical, rule-based, pattern matching |
| sonnet | Code implementation, code review, test design, team coordination | Balanced complexity; analysis + suggestions |
| opus | Architecture design, system analysis, prompt optimization | Complex tradeoffs, deep and meta-level reasoning |

## Per-Invocation Override

Use the `model` parameter on `Task()` to override per delegation:

```
Task({ subagent_type: "corpflow:qa-engineer", model: "sonnet", prompt: "..." })
```

- Team agents inherit the leader's model — and, for tmux/pane-backed teammates, the
  leader's `--effort`. Override only when complexity warrants it. The "Default teammate
  model" setting was removed, so inheritance is the only path: there is no config knob to
  check instead, and a lane's tier is pinned at `Agent(name: …, model: …)` or not at all.
- The built-in `Explore` agent inherits the session model **capped at opus**, not haiku:
  fan-outs cost sonnet/opus-tier tokens, so budget for it or pass an explicit `model`.
- An explicit per-call override **survives resume and follow-up `SendMessage`** — a pinned
  stage does not revert to the parent's model on reattach, so `model_requested`/
  `model_resolved` in `dispatched_agents[]` keep matching for the stage's whole lifecycle.

### Worktask stages: explicit, never inherited

A worktask stage is **always** dispatched with an explicit `model`. The orchestrator reads
`task.metadata.model` from the ledger and passes it as a short alias — `Task({ model: "opus" })` —
never relying on the agent file's frontmatter to supply it.

Frontmatter inheritance is silent when it fails: the stage runs on whatever the parent session had,
`model_requested` and `model_resolved` disagree in `dispatched_agents[]`, and the effort tier the
stage was sized for is gone with no error anywhere. `xhigh` in particular needs Opus 5 or Fable 5
(§ xhigh routing) — a stage that inherits Sonnet is downgraded, not refused.

## Default Subagent Model (`CLAUDE_CODE_SUBAGENT_MODEL`)

`CLAUDE_CODE_SUBAGENT_MODEL` sets the **default** subagent model, not an override: an agent
definition's frontmatter `model:` and an explicit per-spawn `model` both take precedence over it.

This is what makes "always pass `metadata.model` explicitly" load-bearing rather than advisory.
Ledger-dispatched stages are safe — `metadata.model` is required there and validated at step 6.
The exposure is any dispatch that bypasses the ledger, such as the ad-hoc nested `Task()` calls a
stage agent makes for a Tier-2 specialist: omit the model there and the spawn no longer falls back
to the agent's own tier, it falls through to whatever an operator or CI runner exported.

A mid-worktask switch away from a pinned model is separately gated by `hooks/model-switch-gate.sh`
(`agent-coordination/references/hook-monitoring.md § Model-Switch Hooks`).
