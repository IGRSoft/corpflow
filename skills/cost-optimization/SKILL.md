---
name: cost-optimization
description: Apply for budget management, model selection, and efficiency analysis. Cost tracking and optimization strategies for AI agent worktasks.
version: 0.3.0
related:
  - skills/worktask/SKILL.md
  - skills/agent-coordination/SKILL.md
  - skills/claude-constitution/SKILL.md
---

# Cost Optimization

Model right-sizing, token discipline, per-stage tracking, budget gates. Per-stage budgets and typical token ranges: `${CLAUDE_SKILL_DIR}/../context-compression/SKILL.md § Stage Budget Table`. CC context-efficiency knobs and caps, and ethics cost budgeting: `${CLAUDE_SKILL_DIR}/references/token-baselines.md`.

## Model Cost Tiers & Selection Matrix

Canonical tables: `${CLAUDE_SKILL_DIR}/../shared/model-selection.md` (§ Cost Tiers, § Selection Criteria); a worktask stage's model and effort are its row in `${CLAUDE_SKILL_DIR}/../shared/stage-codes.md`. Two settings pay for themselves: explicit `effort: medium` on cost-sensitive stages (QA, DC, RE) — non-Pro plans default to `high` — and `ENABLE_PROMPT_CACHING_1H=1` when stages outlast the 5-minute default cache TTL.

## Per-Effort Thinking-Budget Ceilings

Effort (`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣, `max` ⬛) maps to a thinking-token ceiling. Claude Code does not enforce these — they justify per-agent `effort:` assignments and let reviewers calibrate complexity against cost.

### Budget Ceilings by Effort

| Effort | Thinking Budget | Use For |
|--------|-----------------|---------|
| `low` | ≤ 4K | Formatting, routing, status updates |
| `medium` | ≤ 16K | Implementation, code review, coordination |
| `high` | ≤ 32K | Multi-step reasoning; sonnet/opus default on API/Team plans |
| `xhigh` | ≤ 50K | Hard tradeoffs, meta-optimization, ethics/security review |
| `max` | ≤ 64K | Novel-domain research only; unassigned by default |

**Tuning**: +1 tier when a stage repeatedly retries with `classification: logic`; −1 tier when it passes first try three runs running.

## Cost Reduction Strategies

### 1. Model Right-Sizing

Cheapest model that can do the task (mapping: `../shared/model-selection.md § Selection Criteria`; worktask stages take theirs from `../shared/stage-codes.md`). Moving procedural work — status checks, formatting, simple validation — off sonnet saves ~30% on those stages; reserve opus for architecture-grade reasoning.

### 2. Context Compression

| Technique | Token Reduction | When to Apply |
|-----------|-----------------|---------------|
| Artifact references | 60-80% | Always — reference paths, not content |
| Decision summaries | 40-60% | Stage handoffs |
| Code path notation | 70-90% | When discussing code structure |
| Bullet vs prose | 30-50% | All documentation |

Worked before/after examples and per-content-type techniques: `skills/context-compression/`.

### 3. Context Window Efficiency

Automatic in CC; the knobs, caps, and visibility surfaces still worth acting on are in `${CLAUDE_SKILL_DIR}/references/token-baselines.md`.

`/skill-doctor` lists loaded skills that go unused and what each costs in context — use it to prune.

### 4. Batch Operations

Group file reads before analysis, combine related searches, cache repeated lookups. One batched request instead of five sequential ones drops ~80% of per-call overhead.

### 4a. Git Search Strategy (MANDATORY)

One combined command per question, never `git log` → `git show --stat` → `git show` → `git diff` (4 commands, 1 answer):

```bash
git log --oneline -10 --all -p -S '<term>' -- '*.swift'   # symbol history + diffs
git log --oneline -5 -p -- <file>                         # one file's history + diffs
git log --oneline --stat <base>..HEAD                     # everything on the branch
```

### 4b. Grep Batching (MANDATORY)

Combine related patterns with `|` alternation — `Grep("dismissCompleted|completedScan|stopScanning")`, not three calls.

**Zero-result protocol**: after 2 consecutive zero-result searches on one topic, stop searching. Ask for the correct symbol/path, or Glob for candidate files first and grep within those.

### 4c. Targeted Reads (MANDATORY for large files)

When the location is known (grep hit, error line, prior read), pass `offset`/`limit` instead of reading the whole file — `Read(file_path: "path/to/large.swift", offset: 340, limit: 40)`. Mandatory above 200 lines; a full read is fine at or below that. After a Grep hit at line N: `offset: max(1, N-10), limit: 30`.

### 5. Early Termination

| Scenario | Action |
|----------|--------|
| Simple bug fix | Skip AR stage, minimal TL stage |
| Documentation-only | Skip DV stage, minimal QA stage |
| Hotfix / trivial change | `/worktask` — PL0 dynamic sizing drops AR/TL/DC for low complexity |

Cost by size (PL0-sized): trivial ~1-4 stages $0.01-0.10 · standard 9 stages $0.20-0.40 · complex 9 + iterations $0.50-1.00+.

## Prompt Caching (1h TTL) & Handoff Protocol

The handoff protocol (`skills/worktask/references/handoff-protocol.md`) is built around the Anthropic prompt cache. Its `state-merge.sh` SubagentStop hook needs no wiring — it ships default-on in `.claude-plugin/plugin.json`, contract in the handoff protocol.

### Recommended `settings.json` stanza

```json
{
  "env": {
    "ENABLE_PROMPT_CACHING_1H": "1"
  }
}
```

Why: the 5-min default is shorter than many stages (DV/QA on complex features), so the preamble cache goes cold mid-pipeline — retries inside a stage still save, cross-stage hits are lost. (RK-8 in `analyzing.md#risks`.)

### Finer-grained TTL controls

Three knobs, narrowest first — reach for the narrowest that solves the problem:

| Knob | Scope | Use when |
|---|---|---|
| `experimental.cacheTtl` (`"5m"`/`"1h"`) | One agent, via its frontmatter | A single long-running stage needs the longer TTL and the rest do not. Applies only when no subagent TTL setting is configured |
| `promptCacheTtl` / `subagentPromptCacheTtl` | Settings, main conversation vs subagents separately | The orchestrator's own context is worth holding for an hour while stage agents stay at 5 minutes |
| `ENABLE_PROMPT_CACHING_1H` | Session-wide | The whole pipeline is long enough that everything benefits |

Two upstream cache-miss bugs are fixed and no longer need working around: tool definitions re-rendered after an OAuth token refresh (roughly hourly in long sessions, which also lost extended-thinking context), and the `ScheduleWakeup` tool definition changing between a session and its `--resume` under usage overage.

### Expected cache_read_input_tokens ratio

0% at PL (cold) → ≈20% cross-stage → ≈80% on retries within a stage → ≈60% cross-stage average, meeting AC-14 (`handoff-protocol.md#cache-prefix`).

**Verify rather than assume**: `/cost` carries a per-session prompt-cache line (hit ratio, misses, tokens re-cached, warm/cold) and exposes a matching `prompt_cache` object for status-line scripts. Both name a likely cause for each miss (e.g. tool definitions or system prompt changed, idle past the TTL), which separates preamble drift from an idle gap. That is the measurement for the ≈60% target above — before it, the figure could only be inferred.

Preamble drift collapses that rate: `skills/worktask/scripts/cache-lint.sh` asserts byte-stability of sections [1]+[2] across consecutive stages of one `worktask_id`, and of [4]+[4b] within a stage type. Manual-only — no CI runs it, and nothing emits the `prompt-log.jsonl` it consumes.

### Sibling fan-out staggering

CC 2.1.229 staggers same-prefix siblings on a fan-out so later ones read the cached prefix instead of each re-paying to write it — the runtime complement to `cache-lint.sh` (lint keeps the prefix byte-identical, the stagger makes a simultaneous fan-out hit it). Widest fan-out: TL-split DVN tracks, `/megatask`. `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS=0` disables it when a run is latency-bound, not token-bound.

## Budget Tracking

### Cost Estimation Formula

```
Estimated Cost = Base Tokens × Model Cost × (1 + Retry Factor) × Complexity Multiplier
```

- **Base Tokens**: per-stage baselines (`${CLAUDE_SKILL_DIR}/references/token-baselines.md`)
- **Model Cost**: haiku $0.25/1M · sonnet $3/1M (Sonnet 5 promo $2/$10 per Mtok through 2026-08-31) · opus $15/1M · fable (Fable 5.1) $10/$50 per Mtok, $0.25/Mtok cache reads
- **Retry Factor**: 0.1 low · 0.2 medium · 0.5 high complexity
- **Complexity Multiplier**: 1.0 standard · 1.5 large codebase · 2.0 novel domain

### Budget Alert Thresholds

Canonical ladder — `level` and `action` are these strings verbatim:

| Threshold | Level | Action | Visual |
|-----------|-------|--------|--------|
| < 50% | normal | Normal | Green |
| 50-74% | warning | Warning logged | Yellow |
| 75-89% | notify | User notified | Orange |
| 90-99% | critical | Compression suggested | Red |
| 100% | pause | Worktask paused | Critical |

## Optimization Checklist

- **Before**: confirm PL0 sizing dropped unneeded stages · set a budget limit if applicable · verify per-stage model assignments
- **During**: watch token use at stage transitions · compress at handoffs · push sub-tasks to haiku where possible
- **After**: review the per-stage cost breakdown · record optimization opportunities · update baselines if they drifted

## Anti-Patterns to Avoid

Each wastes context or money for no gain — do the right-hand thing instead.

- Full file content inline → reference by path
- Opus for simple tasks (50x cost) → haiku/sonnet
- One API call per file → batch reads (§4)
- Retrying without compressing first → compress, then retry (§2)
- Full pipeline for a trivial change → trust PL0 dynamic sizing
- Reading whole large files → offset/limit after Grep (§4c)
- Sequential git log/show/diff → one combined command (§4a)
- Separate greps for related symbols → `|` alternation (§4b)
