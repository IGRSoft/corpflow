---
name: business-report
description: Generate business reporting — strategic business case, ROI analysis, or executive summary — via --type case|roi|summary
argument-hint: <initiative description> [--type case|roi|summary]
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/stakeholder.md
  - agents/project-manager.md
  - commands/pm-prioritize.md
---

> **When to use**: one command, three report types via `--type`. `--type case` (default) for strategic justification + financial analysis; `--type roi` for focused ROI metrics (NPV, IRR, payback period); `--type summary` for an executive-level stakeholder summary.

# Business Report Command

Generate business reporting for features or initiatives. The report type is
selected with `--type`:

- `--type case` (default) — full **business case**: problem, solution, financial
  analysis, strategic alignment, risk, recommendation.
- `--type roi` — focused **ROI analysis**: NPV, IRR, payback, sensitivity, and
  risk-adjusted returns.
- `--type summary` — **executive summary** for stakeholder communication.

## Usage

```
/business-report "Initiative description"                     # business case (default)
/business-report --type roi "Initiative" --investment 150000
/business-report --type summary "Q1 Release" --audience board
```

## Options

### Shared (all types)

- `--type <case|roi|summary>` - Report type (default: `case`)
- `--compare` - Compare multiple options / scenarios
- `--export` - Export to presentation format

### `--type case` options

- `--template <full|executive|lean>` - Business case template (default: full)
- `--include-financials` - Add detailed financial analysis

### `--type roi` options

- `--investment <amount>` - Initial investment amount
- `--period <years>` - Analysis period (default: 3)
- `--discount-rate <rate>` - Discount rate for NPV (default: 10%)

### `--type summary` options

- `--format <brief|detailed|presentation>` - Summary format (default: brief)
- `--audience <c-suite|board|investors|team>` - Target audience
- `--include <metrics|timeline|risks|financials>` - Include specific sections

## Examples

```
/business-report "Implement enterprise SSO"
/business-report "Mobile app development" --template full --include-financials
/business-report "Cloud migration" --compare
/business-report --type roi "SSO Implementation" --investment 150000 --period 5
/business-report --type roi "Mobile App" --compare
/business-report --type summary "Q1 Product Release" --format presentation --audience board
```

## Output Format — `--type case` (default)

### Case template — sections 1–3

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
```

### Case template — sections 4–10

```markdown
<!-- …continued: business case sections 4–10 -->
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

### Business Case Template Types

| Template | Use Case | Sections |
|----------|----------|----------|
| full | Major initiatives | All sections |
| executive | Quick decisions | Summary, financials, recommendation |
| lean | Small features | Problem, solution, metrics |

## Output Format — `--type roi`

Calculate Return on Investment with NPV, IRR, and payback period.

### ROI template — investment & cash flow

```markdown
# ROI Analysis: SSO Implementation

## Investment Summary

| Category | Amount |
|----------|--------|
| Initial Investment | $150,000 |
| Annual Operating Cost | $36,000 |
| Analysis Period | 3 years |
| Discount Rate | 10% |

## Cash Flow Projection

| Year | Investment | Benefits | Net Cash Flow | Cumulative |
|------|------------|----------|---------------|------------|
| 0 | -$150,000 | $0 | -$150,000 | -$150,000 |
| 1 | -$36,000 | $898,000 | $862,000 | $712,000 |
| 2 | -$36,000 | $1,327,000 | $1,291,000 | $2,003,000 |
| 3 | -$36,000 | $1,756,000 | $1,720,000 | $3,723,000 |
```

### ROI template — financial metrics

```markdown
<!-- …continued: financial metrics -->
## Financial Metrics

### Primary Metrics

| Metric | Value | Status |
|--------|-------|--------|
| **ROI** | 1,443% | ✅ Excellent |
| **NPV** | $2,891,000 | ✅ Positive |
| **IRR** | 485% | ✅ Exceeds hurdle |
| **Payback Period** | 8 months | ✅ Within target |

### Detailed Calculations

#### ROI (Return on Investment)
    ROI = (Total Benefits - Total Costs) / Total Costs × 100

#### NPV (Net Present Value)
    NPV = Σ (Cash Flow / (1 + r)^t)

#### IRR (Internal Rate of Return)
    IRR: The discount rate at which NPV = 0

#### Payback Period
    Payback = Time to recover initial investment
```

### ROI template — sensitivity & break-even

```markdown
<!-- …continued: sensitivity analysis -->
## Sensitivity Analysis

### Optimistic Scenario (+20% benefits) / Pessimistic Scenario (-30% benefits)

| Metric | Base | Optimistic | Pessimistic |
|--------|------|------------|-------------|
| ROI | 1,443% | 1,792% | 981% |
| NPV | $2,891,000 | $3,589,000 | $1,896,000 |
| Payback | 8 months | 6 months | 11 months |

### Break-Even Analysis

| Scenario | Benefits Required | % of Base |
|----------|-------------------|-----------|
| Break-even | $258,000 | 6% |
| 100% ROI | $516,000 | 13% |
| Target ROI (200%) | $774,000 | 19% |
```

### ROI template — risk-adjusted returns & comparison

```markdown
<!-- …continued: risk-adjusted returns -->
## Risk-Adjusted Returns

| Risk Factor | Probability | Impact on NPV |
|-------------|-------------|---------------|
| Development delays | 30% | -$200,000 |
| Lower adoption | 20% | -$500,000 |
| Competition response | 10% | -$300,000 |

**Risk-Adjusted NPV**: $2,541,000 · **Risk-Adjusted ROI**: 885%

## Comparison (`--compare`)

| Metric | Option A: Build | Option B: Buy | Option C: Delay |
|--------|-----------------|---------------|-----------------|
| Investment | $150,000 | $50,000 | $0 |
| 3-Year TCO | $258,000 | $410,000 | $0 |
| NPV | $2,891,000 | $2,743,000 | -$1,200,000 |
| ROI | 1,443% | 870% | N/A |
| **Recommendation** | ✅ Best | Good | ❌ Avoid |
```

### ROI Calculation Methods

| Metric | Formula | Use |
|--------|---------|-----|
| ROI | (Benefits - Costs) / Costs | Simple return |
| NPV | Σ CF/(1+r)^t | Time value of money |
| IRR | Rate where NPV = 0 | Compare to hurdle rate |
| Payback | Time to recover investment | Liquidity risk |

## Output Format — `--type summary`

Executive-level summary of projects, initiatives, or completed work for
stakeholder communication.

### Brief Format (Default)
```markdown
# Executive Summary: [Project/Release]

## TL;DR (one sentence: what delivered, key outcome)

## Key Outcomes (table: Metric | Target | Actual | Status)

## Highlights
### Delivered (checklist)
### Business Impact (bullet metrics)
### Next Quarter Focus (bullet list)

## Action Required (checklist)
```

### Detailed Format
```markdown
# Executive Summary: [Project/Release]

## Executive Overview (Mission, Outcome, Recommendation)

## Strategic Alignment (table: Goal | Contribution | Impact)

## Delivery Summary
### Features Delivered (table: Feature | Status | Business Value)
### Quality Metrics (table: Metric | Target | Actual | Trend)

## Financial Summary (table: Category | Budget | Actual | Variance + ROI update)

## Risk Status (table: Risk | Status | Mitigation)

## Customer Impact (quotes + metrics table)

## Q2/Next Period Outlook (initiatives, resources, risks)

## Decisions Requested (table: Decision | Deadline | Owner)

## Appendix (links)
```

### Presentation Format
Three slides: Key Wins, Business Impact, Next Focus + Ask.

### Audience Customization

| Audience | Focus | Detail Level | Tone |
|----------|-------|--------------|------|
| C-Suite | Strategy, ROI | High-level | Business |
| Board | Governance, Risk | Summary | Formal |
| Investors | Growth, Metrics | Data-driven | Confident |
| Team | Achievement, Next | Detailed | Celebratory |

## Integration

This command supports:
- `/pm-prioritize` - Business value scoring / input
- `/docs-release-notes` - Technical details source for `--type summary`
- `/estimate` - Investment and effort inputs for `--type case` / `--type roi`
