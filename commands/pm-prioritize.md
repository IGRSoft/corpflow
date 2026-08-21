---
name: pm-prioritize
description: Apply RICE, WSJF, or other prioritization frameworks to rank features and tasks
argument-hint: <feature list or backlog items>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/product-manager.md
  - commands/pm-requirements.md
  - commands/pm-roadmap.md
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
/pm-prioritize --batch backlog.md --framework ice --export
```

## Frameworks

| Framework | Score | Best for |
|-----------|-------|----------|
| RICE (default) | `(Reach × Impact × Confidence) / Effort` | Data-driven teams, measurable reach |
| WSJF | `Cost of Delay / Job Duration`, Cost of Delay = user/business value + time criticality + risk reduction (each 1-10) | SAFe teams, time-sensitive features |
| ICE | `Impact × Confidence × Ease` (each 1-10) | Quick prioritization, early stage |
| MoSCoW | Must / Should / Could / Won't-this-quarter buckets | Fixed scope, release planning |

RICE inputs: Reach in users per quarter, Impact on the 0.25-3 scale (2 = High), Confidence as a percentage, Effort in person-months.

## Output Format

### Single item — RICE (default)

~~~markdown
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
RICE = (5000 × 2 × 0.8) / 2 = 4,000
```

## Priority: **High**

### Ranking Context
| Item | RICE Score | Rank |
|------|------------|------|
| SSO Integration | 6,500 | #1 |
| Dark Mode | 4,000 | #2 |

## Recommendation
Target quarter and why (demand, effort, metric moved), then **Dependencies**
and **Risks** with mitigations.
~~~

### Other frameworks

Same shape — swap the Scores table for that framework's factors and the calculation for its formula. WSJF and ICE close on the same `## Priority: **{level}**` line (WSJF 4.6 → Critical; ICE 6 × 9 × 7 = 378 → Medium). MoSCoW drops scoring entirely and lists items under `## Must Have`, `## Should Have`, `## Could Have`, `## Won't Have (this quarter)`.

### Batch mode

`--batch <file>` reads a markdown list of one item per line and returns the ranked table:

```markdown
# Prioritized Backlog

| Rank | Feature | RICE Score | Recommendation |
|------|---------|------------|----------------|
| 1 | SSO Integration | 6,500 | Q1 Sprint 1-2 |
| 2 | Dark Mode | 4,000 | Q1 Sprint 3-4 |
```

## Integration

This command works with:
- `/pm-requirements` - After prioritization, define requirements
- `/pm-roadmap` - Update roadmap with priorities
- `/pm-sprint` - Plan sprint based on priorities
