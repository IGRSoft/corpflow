---
name: three-stage-planning
---

# 3-Stage Sequential Planning Model

## Stage Definition

| Stage | Priority | Criteria | When |
|-------|----------|----------|------|
| **Required** | P0 | Critical for MVP/deadline | Weeks 1-N |
| **Nice-to-have** | P1 | Adds value, not critical | After Required complete |
| **Not Required (v1.1)** | P2 | Deferred to future version | After Nice-to-have |

## Sequential Rules

1. No parallel development between stages — each starts only after the previous completes
2. Gates must pass before a stage transition
3. Buffer is calculated per stage (10%)
4. Track calendar months for AI billing — minimize month overlap

## Calendar Month Billing (AI Agents)

$200 per calendar month, triggered by any AI agent usage in that month; a partial month
bills the full $200 (1 day in May = $200 for May).

## Stage Budget Template

| Stage | SP Min | SP Max | Hours Min | Hours Max | Weeks | New Months | AI Cost | Dev Cost Min | Dev Cost Max | Buffer | Total Min | Total Max |
|-------|--------|--------|-----------|-----------|-------|------------|---------|-------------|-------------|--------|-----------|-----------|
| Required | - | - | - | - | 1-N | N | $200×N | hMin×rate | hMax×rate | 10% | - | - |
| Nice-to-have | - | - | - | - | N+1 to M | +X | $200×X | hMin×rate | hMax×rate | 10% | - | - |
| v1.1 | - | - | - | - | M+1 to K | +Y | $200×Y | hMin×rate | hMax×rate | 10% | - | - |
| **TOTAL** | - | - | - | - | K | N+X+Y | - | - | - | - | - | - |

## Gate Template

| Gate | Week | Criteria | Pass Action | Fail Action |
|------|------|----------|-------------|-------------|
| DEMO | N | All Required working | Proceed to Nice-to-have | Extend MVP |
| NICE-TO-HAVE | M | All Nice-to-have working | Proceed to v1.1 | Ship MVP only |
| v1.1 RELEASE | K | All v1.1 working | Ship v1.1 | Extend or defer |

## Team Allocation by Stage

These planning stages, not the worktask pipeline's stages, run one after another (§ Sequential
Rules), so allocate the whole team to one at a time: Required (weeks 1-N, MVP) → Nice-to-have
(weeks N-M, stretch) → v1.1 (weeks M-K, deferred) → Release. For an AI agent team, emit a
story-point table: one row per agent, columns `Required` / `Nice-to-have` / `v1.1` / `Total`, each
cell a `Min-Max SP` range. Report each gate review (§ Gate Template) as `Gate`, `Week`,
`Attendees`, `Criteria Review` (Pass/Fail), `Decision` (Proceed/Extend/Defer), `Action Items`.

## ROI by Stage

| Stage | Investment | Expected Return | ROI | Risk |
|-------|------------|-----------------|-----|------|
| Required | $X | MVP launch | High | Low |
| Nice-to-have | $Y | User engagement | Medium | Medium |
| v1.1 | $Z | Market expansion | Variable | High |
