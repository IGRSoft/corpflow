---
name: pm-prioritize
description: Apply RICE, WSJF, or other prioritization frameworks to rank features and tasks
argument-hint: <feature list or backlog items>
model: sonnet
---

# PM Prioritize Command

Apply RICE, WSJF, or other prioritization frameworks to rank features and tasks.

## Usage

```
/pm-prioritize "Feature description"
/pm-prioritize --framework [rice|wsjf|ice|moscow]
/pm-prioritize --batch <file>
```

## Options

- `--framework <name>` - Prioritization framework (default: rice)
- `--batch <file>` - Prioritize multiple items from file
- `--compare` - Compare items side by side
- `--export` - Export prioritized list

## Examples

```
/pm-prioritize "Add dark mode support"
/pm-prioritize --framework wsjf "Implement SSO"
/pm-prioritize --batch backlog.md --compare
```

## Output Format

### RICE Framework (Default)
```markdown
# RICE Prioritization: Add Dark Mode Support

## Scores

| Factor | Value | Rationale |
|--------|-------|-----------|
| **Reach** | 5,000 users/quarter | 50% of active users requested |
| **Impact** | 2 (High) | Significant UX improvement |
| **Confidence** | 80% | Clear requirements, known patterns |
| **Effort** | 2 person-months | Frontend + design work |

## RICE Score Calculation

```
RICE = (Reach × Impact × Confidence) / Effort
RICE = (5000 × 2 × 0.8) / 2
RICE = 4,000
```

## Priority: **High**

### Ranking Context
| Item | RICE Score | Rank |
|------|------------|------|
| Dark Mode | 4,000 | #2 |
| SSO Integration | 6,500 | #1 |
| Export Feature | 2,100 | #3 |

## Recommendation

Prioritize for **Q1 [Year]** based on:
- High user demand (50% of feedback mentions this)
- Reasonable effort with clear scope
- Improves retention metrics

### Dependencies
- Design system color tokens (in progress)
- User preference storage (complete)

### Risks
- Testing across all screens (mitigate with component-based approach)
```

### WSJF Framework
```markdown
# WSJF Prioritization: Implement SSO

## Scores

| Factor | Value (1-10) | Rationale |
|--------|--------------|-----------|
| **User/Business Value** | 8 | Enterprise customers require it |
| **Time Criticality** | 9 | Losing deals without it |
| **Risk Reduction** | 6 | Reduces security burden |
| **Cost of Delay** | 23 | Sum of above |
| **Job Duration** | 5 | 2 sprints estimated |

## WSJF Score

```
WSJF = Cost of Delay / Job Duration
WSJF = 23 / 5
WSJF = 4.6
```

## Priority: **Critical**
```

### ICE Framework
```markdown
# ICE Prioritization: Export Feature

| Factor | Score (1-10) | Rationale |
|--------|--------------|-----------|
| **Impact** | 6 | Useful but not critical |
| **Confidence** | 9 | Well-understood feature |
| **Ease** | 7 | Straightforward implementation |

## ICE Score: 6 × 9 × 7 = 378

## Priority: **Medium**
```

### MoSCoW Classification
```markdown
# MoSCoW: Q1 Features

## Must Have
- User authentication (SSO)
- Data export (compliance requirement)

## Should Have
- Dark mode
- Performance improvements

## Could Have
- Advanced filtering
- Bulk operations

## Won't Have (this quarter)
- Mobile app
- AI features
```

## Batch Prioritization

Input file format:
```markdown
- Add dark mode support
- Implement SSO
- Data export feature
- Performance optimization
```

Output:
```markdown
# Prioritized Backlog

| Rank | Feature | RICE Score | Recommendation |
|------|---------|------------|----------------|
| 1 | SSO Integration | 6,500 | Q1 Sprint 1-2 |
| 2 | Dark Mode | 4,000 | Q1 Sprint 3-4 |
| 3 | Data Export | 2,100 | Q1 Sprint 5 |
| 4 | Performance | 1,800 | Q2 |
```

## Framework Selection Guide

| Framework | Best For |
|-----------|----------|
| RICE | Data-driven teams, measurable reach |
| WSJF | SAFe teams, time-sensitive features |
| ICE | Quick prioritization, early stage |
| MoSCoW | Fixed scope, release planning |

## Integration

This command works with:
- `/pm-requirements` - After prioritization, define requirements
- `/pm-roadmap` - Update roadmap with priorities
- `/sprint-plan` - Plan sprint based on priorities

## Related

- [product-manager](../agents/product-manager.md) - Product expertise
- [pm-requirements](./pm-requirements.md) - Requirements definition
- [pm-roadmap](./pm-roadmap.md) - Roadmap planning
