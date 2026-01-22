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

## AI Agent Cost Estimation

### Token Estimation by Task Type

| Task Type | Typical Tokens | Model Mix | Est. AI Cost |
|-----------|----------------|-----------|--------------|
| Trivial (micro:) | 5,000-10,000 | haiku/sonnet | $0.01-0.03 |
| Simple (quick:) | 15,000-30,000 | sonnet | $0.05-0.10 |
| Standard (workflow:) | 60,000-120,000 | mixed | $0.20-0.50 |
| Complex (workflow:) | 150,000-300,000 | mixed | $0.50-1.50 |
| Large (workflow:) | 300,000+ | mixed | $1.50+ |

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

Where:
- Base Tokens: From task type baseline
- Model Rate: haiku ($0.25/1M), sonnet ($3/1M), opus ($15/1M)
- Retry Factor: 0.1 (low), 0.2 (medium), 0.5 (high complexity)
- Complexity Multiplier: 1.0 (standard), 1.5 (large codebase), 2.0 (novel domain)
```

### Combined Estimate Example

For a medium feature (`workflow:`):
```
Human Development: 30 hours × $150/hr = $4,500
AI Agent Cost: ~100K tokens × mixed = $0.35
Total: $4,500.35

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
| Hours | SP × 6 |
| Buffer | Base × 0.15 |
| Budget | Total Hours × Rate |
| Phase Max | 160 hours (4 weeks) |
| Complexity | Sum of 5 factors (25 max) |
| AI Cost | Base Tokens × Model Rate × Factors |

## Related Skills

- `cost-optimization.md` - Detailed AI cost strategies
- `workflow.md` - Workflow tier selection by complexity
