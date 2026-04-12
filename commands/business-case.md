---
name: business-case
description: Generate business case documentation with financial analysis and strategic justification
argument-hint: <initiative description>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

> **When to use**: `/business-case` for strategic justification and financial analysis. `/roi-analysis` for focused ROI metrics (NPV, IRR, payback period).

# Business Case Command

Generate business case documentation for features or initiatives with financial analysis and strategic justification.

## Usage

```
/business-case "Initiative description"
/business-case --template [full|executive|lean]
/business-case --include-financials
```

## Options

- `--template <type>` - Business case template (default: full)
- `--include-financials` - Add detailed financial analysis
- `--compare` - Compare multiple options
- `--export` - Export to presentation format

## Examples

```
/business-case "Implement enterprise SSO"
/business-case "Mobile app development" --template full --include-financials
/business-case "Cloud migration" --compare
```

## Output Format

```markdown
# Business Case: [Initiative Name]

## Executive Summary (table: Attribute | Value — Initiative, Sponsor, Investment, ROI, Payback, Recommendation)
### One-Line Summary

## 1. Problem Statement
### Current Situation
### Impact of Inaction

## 2. Proposed Solution
### Overview
### Scope (table: In Scope | Out of Scope)
### Success Criteria

## 3. Financial Analysis
### Investment Required (table: Category | One-Time | Recurring)
### Expected Benefits (table: Benefit | Year 1 | Year 2 | Year 3)
### ROI Calculation (table: Metric | Value — NPV, IRR, Payback)

## 4. Strategic Alignment
### Company Objectives (table: Objective | Alignment | Contribution)
### Competitive Analysis (table: Competitor | Support | Our Position)

## 5. Risk Assessment (table: Risk | Probability | Impact | Mitigation | Residual)
### Risk-Adjusted ROI

## 6. Implementation Timeline (month-by-month phases)

## 7. Resource Requirements (table: Role | Allocation | Duration)

## 8. Alternatives Considered (Option A/B/C with pros/cons/cost)

## 9. Success Metrics (table: Metric | Baseline | Target | Timeline)

## 10. Recommendation
### Requested Decision (checklist)
### Next Steps (if approved)
```

## Template Types

| Template | Use Case | Sections |
|----------|----------|----------|
| full | Major initiatives | All sections |
| executive | Quick decisions | Summary, financials, recommendation |
| lean | Small features | Problem, solution, metrics |

## Integration

This command supports:
- `/roi-analysis` - Detailed financial analysis
- `/pm-prioritize` - Business value input
- `/executive-summary` - Summary generation

## Related

- [stakeholder](../agents/stakeholder.md) - Business stakeholder
- [roi-analysis](./roi-analysis.md) - ROI calculation
- [executive-summary](./executive-summary.md) - Summary generation
