---
name: estimation-methodology
description: Standardized complexity scoring (0-50 scale) and T-shirt sizing for project estimation. Use when estimating task complexity, effort, or determining worktask tier.
version: 0.1.0
effort: low
related:
  - cost-optimization.md
  - worktask.md
---

# Estimation Methodology

Standardized project estimation for Claude Code worktasks.

## Calculator Script (canonical math path)

`scripts/estimate-calc.py` implements the complete fixed arithmetic chain. Use it instead of
reasoning through the formulas manually — the model supplies judgment inputs (T-shirt size,
factor scores); the script does all arithmetic and emits compact JSON.

**One-line invocation contract:**

```
python3 skills/estimation-methodology/scripts/estimate-calc.py \
  --size <XS|S|M|L|XL> [--level <junior|mid|senior|expert>] [--multiplier <h>] \
  [--rate <hourly>] \
  [--factors <f1> <f2> <f3> <f4> <f5>] \
  [--tokens <n>] [--model <haiku|sonnet|opus>] \
  [--retry-complexity <low|medium|high>] [--codebase-type <standard|large|novel>] \
  [--phase-hours <min> <max>]
```

### Output & Self-Test

Outputs a single-line JSON object with keys: `sp`, `multiplier_h`, `base_hours`,
`buffer_pct`, `total_hours`, `budget` (if `--rate`), `phase`, `ai_cost` (if `--tokens`),
`complexity` (if `--factors`). No large text blocks — just the numbers.

Self-test (no network, no external deps):
```
python3 skills/estimation-methodology/scripts/estimate-calc.py --self-test
```

The reference sections below remain as the authoritative specification the script
implements. They are no longer needed in the happy path — read the script output instead.

Note: `commands/estimate.md` should cite this script as the canonical math path for its
`### Budget Calculation` and `### AI Cost` sections.

## T-Shirt Sizing → Story Points (Range)

| Size | SP Min | SP Max | Hours Min | Hours Max | Entry point |
|------|--------|--------|-----------|-----------|-------------|
| XS | 1 | 1 | 6 | 6 | `/worktask` |
| S | 2 | 3 | 12 | 18 | `/worktask` |
| M | 4 | 5 | 24 | 30 | `/worktask` |
| L | 6 | 10 | 36 | 60 | `/worktask` |
| XL | 13 | 21 | 78 | 126 | Split first |

## Story Points to Hours

**Formula**: `Hours Min = SP Min × 6h`, `Hours Max = SP Max × 6h` (senior developer)

**Multiplier Variants**:
| Level | Multiplier | Use When |
|-------|------------|----------|
| Junior | SP Min/Max × 10h | New to platform/domain |
| Mid-level | SP Min/Max × 8h | Familiar with stack |
| Senior | SP Min/Max × 6h | **Default** |
| Expert | SP Min/Max × 4h | Deep specialization |

## 5-Factor Complexity Analysis

Score each factor 1-5:

| Factor | Description | Score 5 = |
|--------|-------------|-----------|
| Technical Complexity | Algorithm difficulty, new tech | AR/ML/real-time |
| Integration Points | APIs, SDKs, databases | 4+ external SDKs |
| Risk Level | Security, data, user impact | Financial/health data |
| Unknowns | Unclear requirements | R&D heavy |
| Domain Expertise | Specialized knowledge | Niche specialty |

**Overall Score**: Sum of all factors (0-25)
- 0-10: LOW complexity
- 11-17: MEDIUM complexity
- 18-25: HIGH complexity

## Phase Constraints

**Rule**: Maximum 4 weeks (~160 hours) per phase

If a phase exceeds 160h:
1. Split into sub-phases
2. Redistribute features
3. Create dependency chain

**Rationale**: 4-week phases enable predictable delivery and risk management.

## Test Integration

**Rule**: Tests MUST be included in each subtask, not separate phases.

**Format**: `[Task description] + tests`

| Wrong | Correct |
|-------|---------|
| "Implement login" (20h) + "Write login tests" (8h) | "Implement login + tests" (28h) |
| Separate "Unit Tests" phase | Tests in each subtask |

**Rationale**: Tests developed alongside features catch issues early.

## Buffer Calculation

**Rule**: Add 15% buffer to both Min and Max base hours.

```
Base Hours Min = Total SP Min × 6h    |  Base Hours Max = Total SP Max × 6h
Buffer Min = Base Hours Min × 0.15    |  Buffer Max = Base Hours Max × 0.15
Total Hours Min = Base Hours Min + Buffer Min  |  Total Hours Max = Base Hours Max + Buffer Max
Budget Min = Total Hours Min × Rate   |  Budget Max = Total Hours Max × Rate
```

**Buffer Uses**:
- SDK integration surprises
- Third-party API changes
- Client feedback cycles
- Bug fixes and polish

## Phase Distribution Formula

```
Phase Duration Min (weeks) = Phase Hours Min / 40h  |  Phase Duration Max (weeks) = Phase Hours Max / 40h
Phase Cost Min = Phase Hours Min × Rate  |  Phase Cost Max = Phase Hours Max × Rate
Phase % Min = Phase Hours Min / Total Hours Min × 100  |  Phase % Max = Phase Hours Max / Total Hours Max × 100
```

## Estimation Worktask

1. **Gather inputs**: scope.csv, design/, rate, platform, team size
2. **T-shirt sizing**: Assign XS-XL to each feature
3. **Complexity analysis**: Score 5 factors
4. **Feature breakdown**: Subtasks with SP and hours
5. **Phase planning**: Group into ≤4-week phases
6. **Risk assessment**: Identify and mitigate
7. **Budget calculation**: Hours × rate + buffer
8. **Senior review**: Platform-specific adjustments
9. **Export**: Generate CSVs for Google Sheets

## Worktask Tier Selection

Canonical tier-selection logic. `commands/estimate.md` cites this section instead of duplicating it.

```
size = T-shirt size from sizing table

IF size == XL:
  → split into ≤ L sub-tasks first
ELSE:
  → /worktask   (PL0 dynamic sizing selects which of the 9 stages run)
```

Notes:
- XL must be split into ≤ L sub-tasks before tier selection runs.
- Security-sensitive work still routes through the full pipeline — request `--secure` for the 11-stage worktask.

## PL0 Stage-Set & Test-Mode by Complexity Score

PL0 (`agents/product-manager.md § Dynamic Worktask Sizing` and `§ Test Selection Gate`) uses the 0–50 complexity score to pick the stage set and the default `test_mode`.

**Stage set by score** — each created stage task carries `metadata.agent`; stamp `metadata.skipped_stages` (`{stage, reason}`) for every stage of the full `PL→AR→TL→DV→DR→QA→DC→FN→ST` pipeline the tier does NOT create, and the symmetric `metadata.added_stages` (same `{stage, reason}` shape) for every stage PL0 includes beyond the tier default. Both lists are measured against the full nine-stage reference pipeline, so a stage PL0 declines always appears in `skipped_stages` with a reason.

### Stage set table

| Score | Tier | Stages created |
|-------|------|----------------|
| 0–10 | Low | DV0, DR0, QA0 |
| 11–20 | Medium | AR0 (default — PL0 may override per Stage Inclusion Criteria), DV0, DR0, QA0 |
| 21–30 | Moderate | AR0 (default — PL0 may override per Stage Inclusion Criteria), DV0, DR0, QA0 |
| 31–40 | High | AR0 (default — PL0 may override per Stage Inclusion Criteria), DV0, DR0, QA0, DC0, FN0, ST0 |
| 41–50 | Critical | AR0 (default — PL0 may override per Stage Inclusion Criteria), DV0, DR0, SR0, QA0, DC0, RE0, FN0, ST0 |

+ TL0 — only when PL0 splits the work across ≥2 developers (see Stage Inclusion Criteria)

### Stage Inclusion Criteria (PL0 authority)

Both decisions are made by PL0 DURING PLANNING, before the plan-approval gate,
and surfaced in the gate summary. DV0, DR0, QA0 are the floor and are never
removable. Every decision MUST be recorded as metadata.skipped_stages /
metadata.added_stages entries ({stage, reason}) on the PL0 task.

AR0 — tier default with PL0 override. The tier table includes AR0 by default at
score ≥11. PL0 MAY exclude it when ALL hold: change follows existing patterns;
no new interfaces or schemas; confined to one module; no open design questions.
PL0 MUST include it (any tier, incl. Low) when ANY holds: new module/service/
public API/schema surface; ≥2 viable design approaches needing a recorded
decision; cross-cutting integration (≥3 files across ≥2 subsystems); patterns
novel to this codebase; security- or data-model-relevant structure.

#### TL0 criterion

TL0 — decision-only, never a tier default. Include TL0 ONLY when the work must
be split across ≥2 developers/engineers: parallelizable workstreams, multiple
DV specialists (mixed-platform DV), or external-plugin fan-out requiring
coordination/merge. Single workstream + single DV agent → no TL0, at any score.

Constraint: TL0 without AR0 is allowed (prev edge PL→TL); AR0 at Low tier is
allowed (added_stages). Reasons are one sentence, decision-shaped, not scores.

### Default test_mode by score

Combine with marker coverage; PL0 stamps `metadata.test_mode`:

| Score | Default `test_mode` | Override |
|-------|---------------------|----------|
| 0–10 (Low) | `build-only` if marker coverage ≥ 50%, else `scoped` | `full` only if stakeholder requests |
| 11–25 (Medium) | `scoped` | `full` if multi-module diff |
| 26–50 (High/Critical) | `full` | — |

When uncertain between `scoped` and `full`, choose `scoped` and let the auto-promotion safety net (DV warns, QA promotes if the Selected list is empty) catch under-selection.

## Re-estimation Triggers

Re-run the estimate (e.g. via `/estimate --update`, an out-of-scope follow-up command) when **any** of the following occur:

- **Scope change > 20%** — features added/removed shift total SP by more than a fifth.
- **Complexity score change ≥ 3 points** — any of the 5 factors moves enough to bump the score by 3 or more.
- **New external SDK introduced** — a dependency that was not in the baseline estimate now appears.
- **Risk register adds a High-priority risk** — Probability × Impact crosses the High threshold per the `/pm-risk` risk matrix (`commands/pm-risk.md`).

Until `/estimate --update` exists, re-running `/estimate --detailed` against the new scope and replacing the prior estimate is acceptable.

## AI Agent Cost Estimation

### Token Estimation by Task Type

| Task Type | Typical Tokens | Model Mix | Est. AI Cost |
|-----------|----------------|-----------|--------------|
| Trivial | 5,000-10,000 | haiku/sonnet | $0.01-0.03 |
| Simple | 15,000-30,000 | sonnet | $0.05-0.10 |
| Standard | 60,000-120,000 | mixed | $0.20-0.50 |
| Complex | 150,000-300,000 | mixed | $0.50-1.50 |
| Large | 300,000+ | mixed | $1.50+ |

### Cost Factors

| Factor | Impact on Cost | Example |
|--------|----------------|---------|
| Codebase size | +50-200% | Large monorepo vs small project |
| Files touched | +10% per file | Multi-file refactoring |
| Test requirements | +30-50% | Comprehensive test coverage |
| Documentation depth | +20-40% | Full API documentation |
| Iteration cycles | +20% per retry | Error recovery |
| Context window usage | +10-30% | Large context requirements |

### AI Budget Planning Formula

```
AI Cost = Base Tokens × Model Rate × (1 + Retry Factor) × Complexity Multiplier
```

The factor values (Model Rate, Retry Factor, Complexity Multiplier) are defined canonically in the **cost-optimization** skill (§Cost Estimation Formula). Reference them there rather than restating — single source of truth, avoids drift.

### Combined Estimate Example

For a medium feature (`/worktask`, SP 3-5):
```
Human Development: 18-30 hours × $150/hr = $2,700-$4,500
AI Agent Cost: ~100K tokens × mixed = $0.35
Total: $2,700.35-$4,500.35

AI adds: <0.01% to total project cost
```

### AI Cost vs Development Time Tradeoff

| Approach | Dev Time | AI Cost | Best For |
|----------|----------|---------|----------|
| Minimal AI | 100% | ~$0 | Simple, familiar tasks |
| Balanced | 70-80% | $0.20-0.50 | Standard features |
| AI-Heavy | 50-60% | $0.50-2.00 | Complex, exploratory |

## Quick Reference

| Metric | Formula |
|--------|---------|
| Hours Min | SP Min × 6 |
| Hours Max | SP Max × 6 |
| Buffer | Base Min/Max × 0.15 |
| Budget | Total Hours Min/Max × Rate |
| Phase Max | 160 hours (4 weeks) per Max |
| Complexity | Sum of 5 factors (25 max) |
| AI Cost | Base Tokens × Model Rate × Factors |
