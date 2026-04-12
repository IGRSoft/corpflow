---
name: estimate
description: Estimate task complexity, effort, and resources to determine appropriate workflow tier
argument-hint: '<task description> [--quick|--detailed]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

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
- `--export` - Generate CSV files for Google Sheets (see `/export-estimate` for full 13-file export)
- `--platform <apple|android|web|all>` - Platform-specific templates (default: all)
- `--multiplier <hours>` - Override SP multiplier (default: 6)
- `--ai-rate <amount>` - AI agent monthly rate (default: current billing rate)
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
| SP Min | 5 | Optimistic estimate |
| SP Max | 10 | Pessimistic estimate |
| Hours Min | 30 | SP Min × 6h |
| Hours Max | 60 | SP Max × 6h |

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
| Component | Size | SP Min | SP Max | Notes |
|-----------|------|--------|--------|-------|
| OAuth Provider Setup | S | 2 | 3 | Configuration only |
| Token Management | M | 3 | 5 | Storage, refresh logic |
| Login UI | S | 2 | 3 | Form and error handling |
| Session Management | M | 3 | 5 | State persistence |
| Tests | M | 3 | 5 | Security tests critical |
| Documentation | S | 2 | 3 | API docs, user guide |

### Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Token security issues | Medium | High | Security review in AR stage |
| OAuth provider changes | Low | Medium | Abstract provider interface |

### Budget Calculation
| Metric | Min | Max |
|--------|-----|-----|
| Base Hours | [SP Min × 6h] | [SP Max × 6h] |
| Buffer (15%) | [Base Min × 0.15] | [Base Max × 0.15] |
| Total Hours | [Base Min + Buffer Min] | [Base Max + Buffer Max] |
| Budget | $[Total Min × Rate] | $[Total Max × Rate] |
```

## Sizing Guide

### T-Shirt Sizes
| Size | SP Min | SP Max | Hours Min | Hours Max | Workflow |
|------|--------|--------|-----------|-----------|----------|
| XS | 1 | 1 | 6 | 6 | `micro:` |
| S | 2 | 3 | 12 | 18 | `quick:` |
| M | 3 | 5 | 18 | 30 | `workflow:` |
| L | 5 | 10 | 30 | 60 | `workflow:` |
| XL | 13 | 21 | 78 | 126 | `workflow:` (consider splitting) |

### Complexity Factors
- **Technical Complexity**: Algorithm difficulty, new technologies
- **Integration Points**: APIs, services, databases affected
- **Risk Level**: Security, data integrity, user impact
- **Unknowns**: Unclear requirements, new domain
- **Domain Expertise**: Specialized knowledge required (5 = niche specialty)

### Story Points to Hours

**Formula**: `Hours Min = SP Min × 6h`, `Hours Max = SP Max × 6h` (senior developer)

| Level | Multiplier |
|-------|------------|
| Junior | SP Min/Max × 10h |
| Mid-level | SP Min/Max × 8h |
| Senior | SP Min/Max × 6h (default) |
| Expert | SP Min/Max × 4h |

### Phase Constraints

- Maximum 4 weeks (~160h) per phase
- If exceeds, split into sub-phases or redistribute
- Each phase should be independently deliverable

### Test Integration

- Tests MUST be included in subtasks
- Format: "[Task] + tests"
- No separate testing phases allowed

### Buffer Calculation

- Add 15% buffer to both Min and Max base hours
- Total Min = Base Min × 1.15, Total Max = Base Max × 1.15
- Budget Min = Total Min × Rate, Budget Max = Total Max × Rate

## 3-Stage Sequential Model

See `skills/shared/three-stage-planning.md` for stage definitions, sequential rules, calendar month billing, stage budget template, and gate criteria.

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
