---
name: three-stage-planning
description: 3-stage sequential project planning model (Required/Nice-to-have/v1.1), calendar month billing, stage budget template, and gate criteria. Reference for project planning and budget approval.
effort: low
---

# 3-Stage Sequential Planning Model

## Stage Definition

| Stage | Priority | Criteria | When |
|-------|----------|----------|------|
| **Required** | P0 | Critical for MVP/deadline | Weeks 1-N |
| **Nice-to-have** | P1 | Adds value, not critical | After Required complete |
| **Not Required (v1.1)** | P2 | Deferred to future version | After Nice-to-have |

## Sequential Rules

1. **No parallel development** between stages
2. Each stage starts only after previous stage completes
3. Gates must pass before stage transition
4. Buffer calculated per stage (10%)
5. Track calendar months for AI billing — minimize month overlap

## Calendar Month Billing (AI Agents)

| Rule | Description |
|------|-------------|
| Rate | $200 per calendar month |
| Trigger | Any AI agent usage in month |
| Billing | Full $200 charged for partial month |
| Example | 1 day in May = $200 for May |

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

## ROI by Stage

| Stage | Investment | Expected Return | ROI | Risk |
|-------|------------|-----------------|-----|------|
| Required | $X | MVP launch | High | Low |
| Nice-to-have | $Y | User engagement | Medium | Medium |
| v1.1 | $Z | Market expansion | Variable | High |
