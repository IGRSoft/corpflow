---
name: model-selection
---

# Model Selection Guidelines

Canonical for tiers, selection criteria, and alias/model behaviour. The stage→model assignment
lives in `skills/shared/stage-codes.md`; how to write a prompt for the chosen model lives in
`skills/shared/model-prompting.md`.

## Cost Tiers

| Model | Relative Cost | Cost/1M Tokens | Use For |
|-------|---------------|----------------|---------|
| **haiku** | 1x (baseline) | ~$0.25 | Formatting, routing, checklists, status checks |
| **sonnet** | ~10x haiku | ~$3.00 | Implementation, analysis, test design, coordination |
| **opus** | ~50x haiku | ~$15.00 | Architecture decisions, review gates, complex reasoning, meta-optimization |

## Aliases

| Alias | Resolves to | Context | Pricing |
|-------|-------------|---------|---------|
| `opus` | Opus 5.5 (`claude-opus-5-5`), the default Opus | 1M by default, no usage-credit gate | $4/$20 per Mtok, $0.20/Mtok cache reads; fast mode multiplier on top |
| `sonnet` | Sonnet 5, the Claude Code default model | native 1M | `/model` or the `claude-api` skill |
| `fable` | Fable 5.1 (`claude-fable-5-1`), Mythos-class top reasoning. Claude apps gateway sessions still resolve `fable` and `best` to Fable 5 | 1M by default (`[1m]` names normalize to the base id) | $10/$50 per Mtok, $0.25/Mtok cache reads |
| `haiku` | current Haiku | standard | § Cost Tiers |

Opus-tier stages follow the `opus` alias to each new default Opus with no plugin change. `fable` is
a valid operator override, never a plugin default.

### Prefer the alias over a pinned id

Frontmatter and `metadata.model` carry the alias, never a full model id. An alias tracks the
current default; a pinned id strands the stage once that model is superseded and raises a
deprecation warning at load, agent frontmatter `model:` included.

### Fable 5 credit gate

Without 1M usage credits a fable-tier dispatch fails hard with `API Error: Usage credits required
for 1M context`; an interactive 1M session instead auto-compacts back under the standard limit.
Degrade via a session `fallbackModel` (`--fallback-model`) or a `Task({ model })` /
`metadata.model` override on the stage.

### Fast mode and the lean system prompt

`/fast` applies to Opus: higher token rate and price multiplier, pinned via `/model`. Opus 5 also
uses a lean system prompt by default (Haiku and Sonnet use the standard one), a small standing
input-token saving on opus-tier stages.

## Effort Levels

`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛. Default effort is `high` on API-key, Bedrock,
Vertex, Foundry, Team and Enterprise plans; Pro keeps `medium` on older models. "ultrathink" still
triggers high effort, and `/effort auto` resets. `/effort` stores its default per model, a saved
level never carries onto a newly released model, and an explicit level set anywhere (`-p`, Agent
SDK, `effortLevel` in project/managed/`--settings`) beats a model's launch default. None of that
is under the pipeline's control, so every stage passes `effort` explicitly.

### xhigh routing

`xhigh` requires **Opus 5 or Fable 5.x**. Sonnet silently downgrades the thinking budget; do not
assume Sonnet 5 accepts `xhigh` without verifying. Prefer the `opus` alias; `fable` carries the credit gate above.

Thinking disabled silently costs a tier: `xhigh`/`max` requested with thinking off is sent as
`high` rather than failing. A stage pinned to `xhigh` (`agents/ethics-reviewer.md`,
`agents/prompt-engineer.md`, `agents/security-reviewer.md`) then runs one tier down with no error;
the step-6 audit row is the only place it shows, so check it before trusting an `xhigh` stage's
depth. The output artifacts this configuration also causes on Opus 5:
`skills/shared/model-prompting.md § xhigh with thinking disabled`.

### Effort visibility and inheritance

Hooks read the active tier from `effort.level` (JSON payload) and `$CLAUDE_EFFORT`, so cost/audit
hooks attribute spend per tier without parsing model metadata
(`skills/agent-coordination/references/hook-monitoring.md § Hook Effort Visibility`). Subagents
and compaction inherit the session's extended-thinking config; pass per-stage `metadata.model` +
`effort` anyway, because explicit beats inherited for stage determinism and cost attribution.

### Effort frontmatter and caps

`effort:` frontmatter on subagents, commands and skills works on every model, but no corpflow
agent, command or skill sets it: `skills/shared/stage-codes.md § Agent Model Matrix` is the sole
source for a stage agent's tier. A managed or user `maxEffortLevel` (top-level, or per model
under `modelSettings`) caps effort on every provider: a stage pinned above the cap runs at the
cap with no error. `metadata.effort` keeps the requested tier, so read the hook-reported
`effort.level` before trusting a stage's depth.

## Managed Allowlists and Org Restrictions

Under management a valid alias may silently resolve to a different model, which is why Pre-Stage
Validation step 6 (`skills/worktask/SKILL.md`) emits an audit row rather than blocking the
dispatch.

### Allowlist mechanics

| Control | Behaviour |
|---------|-----------|
| `availableModels` | Constrains subagent model overrides and the dispatch model picker; `enforceAvailableModels` extends it to the Default model. User/project settings cannot widen a managed list. |
| Alias outside the list | Redirects deterministically to an allowed model rather than leaking the disallowed id. |
| `/fast` | Refused when fast mode resolves to a non-allowlisted model, never a silent switch. |

### Restriction signals and fallbacks

| Control | Behaviour |
|---------|-----------|
| Family step-down | A restricted `model: opus` steps down to the newest org-allowed model in that family, not to the parent's model. |
| Restriction warning | Workflow agents, forked skills, slash commands and resumed background agents warn when the parent runs instead of the requested restricted subagent model; check the step-6 audit row rather than assuming the alias resolved. |
| Org default / restrictions | "Org default"/"Role default" shows in `/model`; restrictions cover the picker, `--model`, `/model` and `ANTHROPIC_MODEL` ("restricted by your organization's settings"). |
| Auto-mode fallback | In auto mode, an org allowlist lacking the current top Opus falls back to the best available Opus rather than failing or down-tiering, so restricted-org `xhigh` still lands on the strongest Opus available. |

#### Restriction signals — model resolution

| Control | Behaviour |
|---------|-----------|
| First-call 404 fallback | A subagent whose model 404s on its first call falls through the session's fallback-model chain; the parent's error names type, HTTP status, request id and model. The stage ran on a model `metadata.model` never asked for, so trust `dispatched_agents[].model_resolved`, not `model_requested`, when attributing cost. |
| `modelPicker` / `modelPricing` | Managed settings: `modelPicker` curates the `/model` list; `modelPricing` applies an org's contracted rates to `/cost`, the status line and telemetry, so a cost figure read under it is org-rated, not list-rated. |

## Provider Defaults (Bedrock / Vertex / Foundry)

Auto model/effort selection is on there with no opt-in; disable via `disableAutoMode`. These
providers and Claude-Platform-on-AWS default to the newest Opus they carry, which lags the
first-party default, so confirm what `opus` resolves to via `/model`. Explicit
`--model`/`--effort`/`metadata.model` stay authoritative. Bedrock resolves its region from
`~/.aws` when `AWS_REGION` is unset and prefixes GovCloud inference profiles `us-gov`, so headless
runners need no region env.

### Auto-mode permission classifier

The small model classifying permission decisions in auto mode defaults to Sonnet 5 for external
sessions, validated on the first request and then pinned for the session. It is unrelated to the
session model.

## Context-Window Accounting

`/context` percentages are computed against the full 1M window on models that have one (Opus 5.x,
Sonnet 5, Fable 5.x). How the extended window changes stage handoff budgets, plus the fable
without-credits caveat: `skills/context-compression/SKILL.md`.

## Selection Criteria

A worktask stage never reads this table: its model and effort are its row in
`skills/shared/stage-codes.md`. The table sizes everything else — ad-hoc delegations, support
work, a new agent's default.

| Complexity | Model | Signals |
|------------|-------|---------|
| Simple | haiku | Procedural steps, well-defined output format, little reasoning, high volume / low latency, cost-first: status checks, formatting, platform routing |
| Moderate | sonnet | Moderate reasoning, several considerations to balance, bounded creative output: test design, team coordination |
| Complex | opus | Multi-step or novel reasoning, tradeoff-heavy decisions, high-stakes gates such as code review, meta-level work (agents about agents, prompt optimization), architecture and system analysis |

## Per-Invocation Override

Use the `model` parameter on `Task()` to override per delegation:

```
Task({ subagent_type: "corpflow:qa-engineer", model: "sonnet", prompt: "..." })
```

### Task delegation and inheritance

#### Team and Explore agents

- Team agents inherit the leader's model and, for tmux/pane-backed teammates, the leader's
  `--effort`. There is no default-teammate-model setting, so a lane's tier is pinned at
  `Agent(name: …, model: …)` or not at all.
- The built-in `Explore` agent inherits the session model capped at opus, not haiku: budget
  fan-outs at sonnet/opus rates or pass an explicit `model`.

#### Persistence across resume and auto mode

- An explicit per-call override survives resume and follow-up `SendMessage`, so
  `model_requested`/`model_resolved` in `dispatched_agents[]` keep matching for the stage's whole
  lifecycle.
- Command and skill frontmatter `model:` is honoured in interactive sessions (no corpflow command
  or skill sets one). In auto mode, a command or skill naming a model auto mode does not support
  keeps the session model for that turn.

### Worktask stages: explicit, never inherited

A worktask stage is always dispatched with an explicit `model`: the orchestrator reads
`task.metadata.model` from the ledger, resolved from `skills/shared/stage-codes.md § Agent Model
Matrix`, and passes it as a short alias — `Task({ model: "opus" })`. No corpflow agent carries a
`model:` key, so there is no frontmatter to fall back to.

A dispatch that skips this fails silently: the stage runs on the parent session's model,
`model_requested` and `model_resolved` disagree in `dispatched_agents[]`, and the sized effort
tier is lost (an inherited Sonnet downgrades `xhigh`, § xhigh routing).

## Default Subagent Model (`CLAUDE_CODE_SUBAGENT_MODEL`)

`CLAUDE_CODE_SUBAGENT_MODEL` sets the default subagent model, not an override: an agent's
frontmatter `model:` and an explicit per-spawn `model` both take precedence over it.

Ledger-dispatched stages are safe: `metadata.model` is required there and validated at step 6.
The exposure is any dispatch that bypasses the ledger, such as a stage agent's ad-hoc nested
`Task()` to a Tier-2 specialist. Omit the model there and the spawn falls through to
`CLAUDE_CODE_SUBAGENT_MODEL`, or the session model if that is unset.

A mid-worktask switch away from a pinned model is gated by `hooks/model-switch-gate.sh`
(`agent-coordination/references/hook-monitoring.md § Model-Switch Hooks`).

### Forced subagent model overrides every pin

`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` inverts that precedence. When set, every subagent runs on
`CLAUDE_CODE_SUBAGENT_MODEL`, or the main session model when that is unset, ignoring both the
per-spawn `model` and the agent's `model:`. Ledger-dispatched stages lose their safety:
`Task({ model: "opus" })` still passes step 6, then runs on the forced model with no error.

Two controls cover it. PL0 reads the variable before any spend and raises a plan-gate sweep item
(`skills/worktask/references/pl0-procedure.md § Subagent model-force preflight — detection`), and
Step 6.5b backfills `dispatched_agents[].model_resolved` when the runtime surfaces the model that
ran, so cost follows the forced tier rather than the pin. The force applies at spawn, so there is
no mid-stage switch for `hooks/model-switch-gate.sh` to refuse.
