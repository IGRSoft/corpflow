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
- `--stages` - 3-stage breakdown (Required, Nice-to-have, v1.1)
- `--sequential` - Force sequential stage planning (no parallel)
- `--compare` - Compare multiple approaches
- `--export` - Generate 8 CSV files for Google Sheets
- `--platform <apple|android|web|all>` - Platform-specific templates (default: all)
- `--multiplier <hours>` - Override SP multiplier (default: 6)
- `--ai-rate <amount>` - AI agent monthly rate (default: $200)
- `--dev-rate <amount>` - Developer hourly rate (default: $1)

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
| Token security issues | Medium | High | Security review in AR stage |
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

## 3-Stage Sequential Model

| Stage | Priority | Description | When |
|-------|----------|-------------|------|
| **Required** | P0 | Must complete by deadline | Weeks 1-N |
| **Nice-to-have** | P1 | Stretch goals | After Required complete |
| **Not Required** | P2 | Deferred features | After Nice-to-have (v1.1) |

### Sequential Rules

1. **No parallel development** between stages
2. Each stage starts only after previous stage completes
3. Gates must pass before stage transition
4. Buffer calculated per stage (10%)

### Calendar Month Billing (AI Agents)

| Rule | Description |
|------|-------------|
| Rate | $200 per calendar month |
| Trigger | Any AI agent usage in month |
| Billing | Full $200 charged for partial month |
| Example | 1 day in May = $200 for May |

### Stage Budget Template

| Stage | SP | Hours | Weeks | New Months | AI Cost | Dev Cost | Buffer | Total |
|-------|-----|-------|-------|------------|---------|----------|--------|-------|
| Required | - | - | 1-N | N | $200×N | h×rate | 10% | - |
| Nice-to-have | - | - | N+1 to M | +X | $200×X | h×rate | 10% | - |
| v1.1 | - | - | M+1 to K | +Y | $200×Y | h×rate | 10% | - |
| **TOTAL** | - | - | K | N+X+Y | - | - | - | - |

### Gate Template

| Gate | Week | Criteria | Pass Action | Fail Action |
|------|------|----------|-------------|-------------|
| DEMO | N | All Required working | Proceed to Nice-to-have | Extend MVP |
| NICE-TO-HAVE | M | All Nice-to-have working | Proceed to v1.1 | Ship MVP only |
| v1.1 RELEASE | K | All v1.1 working | Ship v1.1 | Extend or defer |

## Export Structure (8 Core Reports)

| # | File | Purpose |
|---|------|---------|
| 01 | project_summary.csv | Project metadata, timeline, team |
| 02 | features_by_stage.csv | Features grouped by stage |
| 03 | technology_stack.csv | Frameworks, SDKs, dependencies |
| 04 | schedule_and_milestones.csv | Week-by-week schedule by stage |
| 05 | budget_estimate.csv | Calendar month billing breakdown |
| 06 | risk_assessment.csv | Risk register with mitigations |
| 07 | agent_workflow.csv | Agent assignments and dependencies |
| 08 | stage_completion_gates.csv | Gates, decision points, criteria |

## Workflow Recommendation Logic

```
IF size = XS AND no security concerns:
  → micro: (direct edit)
ELSE IF size <= S AND single component:
  → quick: (PL → DV → QA)
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
