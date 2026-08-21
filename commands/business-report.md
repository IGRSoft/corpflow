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

Generate business reporting for features or initiatives; `--type` selects the
report, and each type's sections are specified under § Output Format below.

## Usage

```
/business-report <initiative> [--type case|roi|summary] [shared + per-type options]
```

## Options

### Shared (all types)

| Option | Values | Default | Purpose |
|---|---|---|---|
| `--type` | `case`, `roi`, `summary` | `case` | Report type |
| `--compare` | flag | off | Compare multiple options / scenarios |
| `--export` | flag | off | Export to presentation format |

### Per type

| Option | Type | Values | Default |
|---|---|---|---|
| `--template` | case | `full`, `executive`, `lean` | `full` |
| `--include-financials` | case | flag | off |
| `--investment` | roi | amount | — |
| `--period` | roi | years | `3` |
| `--discount-rate` | roi | rate | `10%` |
| `--format` | summary | `brief`, `detailed`, `presentation` | `brief` |
| `--audience` | summary | `c-suite`, `board`, `investors`, `team` | — |
| `--include` | summary | `metrics`, `timeline`, `risks`, `financials` | all |

## Examples

```
/business-report "Implement enterprise SSO"
/business-report "Mobile app development" --template full --include-financials
/business-report "Cloud migration" --compare --export
/business-report --type roi "SSO Implementation" --investment 150000 --period 5 --discount-rate 8%
/business-report --type summary "Q1 Product Release" --format presentation --audience board
/business-report --type summary "Q1 Release" --format detailed --include risks
```

## Output Format — `--type case` (default)

### Case template — sections 1–5

```markdown
# Business Case: [Initiative Name]

## Executive Summary (Attribute | Value — Initiative, Sponsor, Investment, ROI, Payback, Recommendation)
### One-Line Summary
## 1. Problem Statement — Current Situation · Impact of Inaction
## 2. Proposed Solution — Overview · Scope (In Scope | Out of Scope) · Success Criteria
## 3. Financial Analysis — Investment Required (Category | One-Time | Recurring) ·
   Expected Benefits (Benefit | Year 1..N) · ROI Calculation (Metric | Value: NPV, IRR, Payback)
## 4. Strategic Alignment — Company Objectives (Objective | Alignment | Contribution) ·
   Competitive Analysis (Competitor | Support | Our Position)
## 5. Risk Assessment (Risk | Probability | Impact | Mitigation | Residual) · Risk-Adjusted ROI
```

### Case template — sections 6–10

```markdown
## 6. Implementation Timeline (month-by-month phases)
## 7. Resource Requirements (Role | Allocation | Duration)
## 8. Alternatives Considered (Option A/B/C — pros, cons, cost)
## 9. Success Metrics (Metric | Baseline | Target | Timeline)
## 10. Recommendation — Requested Decision (checklist) · Next Steps (if approved)
```

### Business Case Template Types

| Template | Use Case | Sections |
|----------|----------|----------|
| full | Major initiatives | All sections |
| executive | Quick decisions | Summary, financials, recommendation |
| lean | Small features | Problem, solution, metrics |

## Output Format — `--type roi`

### ROI template — investment & metrics

Every figure derives from `--investment`, `--period`, and `--discount-rate`.

```markdown
# ROI Analysis: [Initiative]

## Investment Summary (Category | Amount — Initial Investment, Annual Operating Cost,
   Analysis Period, Discount Rate)
## Cash Flow Projection (Year | Investment | Benefits | Net Cash Flow | Cumulative; year 0..N)
## Financial Metrics
### Primary Metrics (Metric | Value | Status — ROI, NPV, IRR, Payback Period;
   status glyph ✅ / ⚠️ / ❌ against the hurdle rate and target payback)
```

### ROI template — sensitivity, risk, comparison

```markdown
## Sensitivity Analysis (Metric | Base | Optimistic +20% benefits | Pessimistic −30% benefits)
## Break-Even Analysis (Scenario | Benefits Required | % of Base — break-even, 100% ROI, target ROI)
## Risk-Adjusted Returns (Risk Factor | Probability | Impact on NPV), then
   **Risk-Adjusted NPV** and **Risk-Adjusted ROI**
## Comparison (`--compare` only: Metric | Option A: Build | Option B: Buy | Option C: Delay,
   ending in a **Recommendation** row)
```

### ROI Calculation Methods

| Metric | Formula | Use |
|--------|---------|-----|
| ROI | (Benefits − Costs) / Costs × 100 | Simple return |
| NPV | Σ CF/(1+r)^t | Time value of money |
| IRR | Rate where NPV = 0 | Compare to hurdle rate |
| Payback | Time to recover investment | Liquidity risk |

## Output Format — `--type summary`

Format per `--format`; depth and tone per `--audience` (see § Audience Customization).

### Brief Format (Default)

```markdown
# Executive Summary: [Project/Release]

## TL;DR (one sentence: what delivered, key outcome)
## Key Outcomes (Metric | Target | Actual | Status)
## Highlights — Delivered (checklist) · Business Impact (bullet metrics) · Next Quarter Focus
## Action Required (checklist)
```

### Detailed Format

```markdown
# Executive Summary: [Project/Release]

## Executive Overview (Mission, Outcome, Recommendation)
## Strategic Alignment (Goal | Contribution | Impact)
## Delivery Summary — Features Delivered (Feature | Status | Business Value) ·
   Quality Metrics (Metric | Target | Actual | Trend)
## Financial Summary (Category | Budget | Actual | Variance + ROI update)
## Risk Status (Risk | Status | Mitigation)
## Customer Impact (quotes + metrics table)
## Next Period Outlook (initiatives, resources, risks)
## Decisions Requested (Decision | Deadline | Owner)
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

- `/pm-prioritize` — business value scoring / input
- `/docs-release-notes` — technical details source for `--type summary`
- `/estimate` — investment and effort inputs for `--type case` / `--type roi`
