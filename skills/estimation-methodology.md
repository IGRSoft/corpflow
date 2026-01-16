# Estimation Methodology

Standardized project estimation for Claude Code workflows.

## T-Shirt Sizing → Story Points

| Size | Story Points | Hours (SP × 6h) | Workflow |
|------|--------------|-----------------|----------|
| XS | 1 | 6 | `micro:` |
| S | 2-3 | 12-18 | `quick:` |
| M | 5 | 30 | `workflow:` |
| L | 8-10 | 48-60 | `workflow:` |
| XL | 13+ | 78+ | Split first |

## Story Points to Hours

**Formula**: `Hours = Story Points × 6h (senior developer)`

**Multiplier Variants**:
| Level | Multiplier | Use When |
|-------|------------|----------|
| Junior | SP × 10h | New to platform/domain |
| Mid-level | SP × 8h | Familiar with stack |
| Senior | SP × 6h | **Default** |
| Expert | SP × 4h | Deep specialization |

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

**Rule**: Add 15% buffer to total base hours.

```
Base Hours = Total SP × 6h
Buffer = Base Hours × 0.15
Total Hours = Base Hours + Buffer
Budget = Total Hours × Hourly Rate
```

**Buffer Uses**:
- SDK integration surprises
- Third-party API changes
- Client feedback cycles
- Bug fixes and polish

## Phase Distribution Formula

```
Phase Duration (weeks) = Phase Hours / 40h per week
Phase Cost = Phase Hours × Hourly Rate
Phase Percentage = Phase Hours / Total Hours × 100
```

## Estimation Workflow

1. **Gather inputs**: scope.csv, design/, rate, platform, team size
2. **T-shirt sizing**: Assign XS-XL to each feature
3. **Complexity analysis**: Score 5 factors
4. **Feature breakdown**: Subtasks with SP and hours
5. **Phase planning**: Group into ≤4-week phases
6. **Risk assessment**: Identify and mitigate
7. **Budget calculation**: Hours × rate + buffer
8. **Senior review**: Platform-specific adjustments
9. **Export**: Generate CSVs for Google Sheets

## Quick Reference

| Metric | Formula |
|--------|---------|
| Hours | SP × 6 |
| Buffer | Base × 0.15 |
| Budget | Total Hours × Rate |
| Phase Max | 160 hours (4 weeks) |
| Complexity | Sum of 5 factors (25 max) |
