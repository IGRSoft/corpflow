# Estimation Run Reference

On-demand detail for a full estimation run (`/estimate --detailed`). The always-loaded rubric —
sizing, hours multipliers, 5-factor complexity, phase cap, test integration, buffer, tier
selection, PL0 stage sets — stays in `skills/estimation-methodology/SKILL.md`.

## Estimation Worktask

1. **Gather inputs**: scope.csv, design/, rate, platform, team size
2. **T-shirt sizing**: assign XS-XL per feature
3. **Complexity analysis**: score the 5 factors
4. **Feature breakdown**: subtasks with SP and hours
5. **Phase planning**: group into ≤4-week phases
6. **Risk assessment**: identify and mitigate
7. **Budget calculation**: hours × rate + buffer
8. **Senior review**: platform-specific adjustments
9. **Export**: CSVs for Google Sheets

## Phase Distribution Formula

Per phase, applied to Min and Max independently:

```
Duration (weeks) = Phase Hours / 40h
Cost             = Phase Hours × Rate
Share %          = Phase Hours / Total Hours × 100
```

## Re-estimation Triggers

Re-run the estimate — `/estimate --detailed` against the new scope, replacing the prior
estimate — when **any** of these occur:

- **Scope change > 20%** — added/removed features shift total SP by more than a fifth.
- **Complexity score change ≥ 3 points** — any of the 5 factors moves the score by 3 or more.
- **New external SDK** not in the baseline estimate.
- **Risk register adds a High-priority risk** — Probability × Impact crosses the High threshold
  per the `/pm-risk` risk matrix (`commands/pm-risk.md`).

## AI Cost Factors

Multipliers on the base token estimate (bands and formula: `SKILL.md § AI Agent Cost
Estimation`):

| Factor | Impact on Cost |
|--------|----------------|
| Codebase size | +50-200% |
| Files touched | +10% per file |
| Test requirements | +30-50% |
| Documentation depth | +20-40% |
| Iteration cycles | +20% per retry |
| Context window usage | +10-30% |

Scale check: a medium feature (`/worktask`, SP 3-5) is 18-30 hours × $150/hr = $2,700-$4,500 of
human time against ~100K tokens ≈ $0.35 of AI cost — AI adds <0.01% to total project cost.

## AI Cost vs Development Time Tradeoff

| Approach | Dev Time | AI Cost | Best For |
|----------|----------|---------|----------|
| Minimal AI | 100% | ~$0 | Simple, familiar tasks |
| Balanced | 70-80% | $0.20-0.50 | Standard features |
| AI-Heavy | 50-60% | $0.50-2.00 | Complex, exploratory |
