# Estimate Command

Estimate task complexity, effort, and resources before starting a workflow. Helps determine the appropriate workflow tier and provides sizing guidance.

## Usage

```
/estimate "Task description"
/estimate --quick "Small task"
/estimate --detailed "Complex feature"
```

## Options

- `--quick` - Quick estimation (T-shirt size only)
- `--detailed` - Detailed estimation with full breakdown
- `--compare` - Compare multiple approaches
- `--export` - Generate 13 CSV files for Google Sheets
- `--platform <apple|android|web|all>` - Platform-specific templates (default: all)
- `--multiplier <hours>` - Override SP multiplier (default: 6)

## Examples

```
/estimate "Add dark mode support"
/estimate --detailed "Implement user authentication with OAuth"
/estimate --quick "Fix button alignment on login page"
```

## Output Format

### Quick Estimation
```markdown
## Quick Estimate: Add dark mode support

**Size**: M (Medium)
**Recommended Workflow**: `workflow:` (Standard)
**Estimated Effort**: 2-3 days
```

### Detailed Estimation
```markdown
## Detailed Estimate: Implement user authentication

### Sizing
| Metric | Value | Notes |
|--------|-------|-------|
| T-Shirt Size | L | Multiple components affected |
| Story Points | 8 | Based on complexity and unknowns |
| Effort | 5-8 days | Including testing and docs |

### Complexity Analysis
| Factor | Score (1-5) | Notes |
|--------|-------------|-------|
| Technical Complexity | 4 | OAuth integration, token management |
| Integration Points | 3 | Backend API, storage, UI |
| Risk Level | 3 | Security-sensitive feature |
| Unknowns | 2 | Well-documented OAuth providers |

### Recommended Workflow
**Tier**: `workflow:` (Full 8-stage)
**Rationale**: Security-sensitive, multiple files, requires architecture review

### Resource Requirements
- **Skills Needed**: Backend, Security, Frontend
- **Dependencies**: API endpoints, OAuth provider setup
- **Blockers**: None identified

### Breakdown
| Component | Size | Notes |
|-----------|------|-------|
| OAuth Provider Setup | S | Configuration only |
| Token Management | M | Storage, refresh logic |
| Login UI | S | Form and error handling |
| Session Management | M | State persistence |
| Tests | M | Security tests critical |
| Documentation | S | API docs, user guide |

### Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Token security issues | Medium | High | Security review in A stage |
| OAuth provider changes | Low | Medium | Abstract provider interface |

### Budget Calculation
| Metric | Value |
|--------|-------|
| Base Hours | [SP × 6h] |
| Buffer (15%) | [Base × 0.15] |
| Total Hours | [Base + Buffer] |
| Budget | $[Total × Rate] |
```

## Sizing Guide

### T-Shirt Sizes
| Size | Story Points | Hours (SP × 6h) | Workflow |
|------|--------------|-----------------|----------|
| XS | 1 | 6 | `micro:` |
| S | 2-3 | 12-18 | `quick:` |
| M | 5 | 30 | `workflow:` |
| L | 8-10 | 48-60 | `workflow:` |
| XL | 13+ | 78+ | `workflow:` (consider splitting) |

### Complexity Factors
- **Technical Complexity**: Algorithm difficulty, new technologies
- **Integration Points**: APIs, services, databases affected
- **Risk Level**: Security, data integrity, user impact
- **Unknowns**: Unclear requirements, new domain
- **Domain Expertise**: Specialized knowledge required (5 = niche specialty)

### Story Points to Hours

**Formula**: Hours = Story Points × 6h (senior developer)

| Level | Multiplier |
|-------|------------|
| Junior | SP × 10h |
| Mid-level | SP × 8h |
| Senior | SP × 6h (default) |
| Expert | SP × 4h |

### Phase Constraints

- Maximum 4 weeks (~160h) per phase
- If exceeds, split into sub-phases or redistribute
- Each phase should be independently deliverable

### Test Integration

- Tests MUST be included in subtasks
- Format: "[Task] + tests"
- No separate testing phases allowed

### Buffer Calculation

- Add 15% buffer to base hours
- Total = Base × 1.15
- Budget = Total Hours × Hourly Rate

## Workflow Recommendation Logic

```
IF size = XS AND no security concerns:
  → micro: (direct edit)
ELSE IF size <= S AND single component:
  → quick: (P → D → Q)
ELSE IF size <= L:
  → workflow: (full 8-stage)
ELSE:
  → Consider splitting into smaller tasks
```

## Integration

This command works well with:
- `/workflow` - Use estimate to choose correct workflow tier
- `/pm-prioritize` - Estimation feeds into RICE calculations
- `/sprint-plan` - Story points for capacity planning
- `/export-estimate` - Generate CSVs from estimation
- `/senior-review` - Platform-specific review adjustments

## Related

- [Workflow System](../skills/workflow.md) - Workflow tier selection
- [product-manager](../agents/product-manager.md) - RICE prioritization
- [project-manager](../agents/project-manager.md) - Sprint planning
