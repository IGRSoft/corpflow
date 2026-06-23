---
name: roi-analysis
description: Calculate Return on Investment for initiatives with NPV, IRR, and payback period
argument-hint: <initiative or investment>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/stakeholder.md
  - commands/business-case.md
  - commands/executive-summary.md
---

> **When to use**: `/roi-analysis` for focused ROI metrics (NPV, IRR, payback period). `/business-case` for strategic justification and financial analysis.

# ROI Analysis Command

Calculate Return on Investment for initiatives with NPV, IRR, and payback period.

## Usage

```
/roi-analysis "Initiative description"
/roi-analysis --investment <amount>
/roi-analysis --period [1|3|5] years
```

## Options

- `--investment <amount>` - Initial investment amount
- `--period <years>` - Analysis period (default: 3)
- `--discount-rate <rate>` - Discount rate for NPV (default: 10%)
- `--compare` - Compare multiple scenarios

## Examples

```
/roi-analysis "SSO Implementation"
/roi-analysis --investment 150000 --period 5
/roi-analysis "Mobile App" --compare
```

## Output Format

```markdown
# ROI Analysis: SSO Implementation

## Investment Summary

| Category | Amount |
|----------|--------|
| Initial Investment | $150,000 |
| Annual Operating Cost | $36,000 |
| Analysis Period | 3 years |
| Discount Rate | 10% |

---

## Cash Flow Projection

| Year | Investment | Benefits | Net Cash Flow | Cumulative |
|------|------------|----------|---------------|------------|
| 0 | -$150,000 | $0 | -$150,000 | -$150,000 |
| 1 | -$36,000 | $898,000 | $862,000 | $712,000 |
| 2 | -$36,000 | $1,327,000 | $1,291,000 | $2,003,000 |
| 3 | -$36,000 | $1,756,000 | $1,720,000 | $3,723,000 |

---

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
```
ROI = (Total Benefits - Total Costs) / Total Costs × 100
ROI = ($3,981,000 - $258,000) / $258,000 × 100
ROI = 1,443%
```

#### NPV (Net Present Value)
```
NPV = Σ (Cash Flow / (1 + r)^t)

Year 0: -$150,000 / 1.00 = -$150,000
Year 1: $862,000 / 1.10 = $783,636
Year 2: $1,291,000 / 1.21 = $1,067,769
Year 3: $1,720,000 / 1.33 = $1,293,233

NPV = $2,994,638
```

#### IRR (Internal Rate of Return)
```
IRR: The discount rate at which NPV = 0
Calculated IRR = 485%
```

#### Payback Period
```
Payback = Time to recover initial investment
Month 1-6: -$150,000 + ($862,000 × 6/12) = $281,000
Payback achieved in Month 8
```

---

## Benefit Breakdown

### Revenue Benefits

| Source | Year 1 | Year 2 | Year 3 | Confidence |
|--------|--------|--------|--------|------------|
| New Enterprise Sales | $800,000 | $1,200,000 | $1,600,000 | High |
| Reduced Churn | $50,000 | $75,000 | $100,000 | Medium |
| **Total Revenue** | **$850,000** | **$1,275,000** | **$1,700,000** | |

### Cost Savings

| Source | Year 1 | Year 2 | Year 3 | Confidence |
|--------|--------|--------|--------|------------|
| Support Reduction | $48,000 | $52,000 | $56,000 | High |
| **Total Savings** | **$48,000** | **$52,000** | **$56,000** | |

---

## Sensitivity Analysis

### Optimistic Scenario (+20% benefits)

| Metric | Base | Optimistic |
|--------|------|------------|
| ROI | 1,443% | 1,792% |
| NPV | $2,891,000 | $3,589,000 |
| Payback | 8 months | 6 months |

### Pessimistic Scenario (-30% benefits)

| Metric | Base | Pessimistic |
|--------|------|-------------|
| ROI | 1,443% | 981% |
| NPV | $2,891,000 | $1,896,000 |
| Payback | 8 months | 11 months |

### Break-Even Analysis

| Scenario | Benefits Required | % of Base |
|----------|-------------------|-----------|
| Break-even | $258,000 | 6% |
| 100% ROI | $516,000 | 13% |
| Target ROI (200%) | $774,000 | 19% |

---

## Risk-Adjusted Returns

| Risk Factor | Probability | Impact on NPV |
|-------------|-------------|---------------|
| Development delays | 30% | -$200,000 |
| Lower adoption | 20% | -$500,000 |
| Competition response | 10% | -$300,000 |

**Risk-Adjusted NPV**: $2,541,000
**Risk-Adjusted ROI**: 885%

---

## Comparison (if applicable)

| Metric | Option A: Build | Option B: Buy | Option C: Delay |
|--------|-----------------|---------------|-----------------|
| Investment | $150,000 | $50,000 | $0 |
| Year 1 Cost | $36,000 | $120,000 | $0 |
| 3-Year TCO | $258,000 | $410,000 | $0 |
| 3-Year Benefits | $3,981,000 | $3,981,000 | $0 |
| NPV | $2,891,000 | $2,743,000 | -$1,200,000 |
| ROI | 1,443% | 870% | N/A |
| **Recommendation** | ✅ Best | Good | ❌ Avoid |

---

## Recommendation

### Decision Criteria Met

| Criterion | Threshold | Actual | Status |
|-----------|-----------|--------|--------|
| ROI | > 100% | 1,443% | ✅ Pass |
| NPV | > $0 | $2,891,000 | ✅ Pass |
| IRR | > 15% | 485% | ✅ Pass |
| Payback | < 24 months | 8 months | ✅ Pass |

### Verdict: **Strong Investment**

The initiative significantly exceeds all financial hurdles even in pessimistic scenarios.

---

## Assumptions

| Assumption | Value | Basis |
|------------|-------|-------|
| New customer revenue | $800K Y1 | Sales pipeline |
| Revenue growth | 25% YoY | Historical trend |
| Support cost reduction | 40% | Industry benchmark |
| Discount rate | 10% | Company WACC |
```

## Calculation Methods

| Metric | Formula | Use |
|--------|---------|-----|
| ROI | (Benefits - Costs) / Costs | Simple return |
| NPV | Σ CF/(1+r)^t | Time value of money |
| IRR | Rate where NPV = 0 | Compare to hurdle rate |
| Payback | Time to recover investment | Liquidity risk |

## Integration

This command supports:
- `/business-case` - Financial section
- `/pm-prioritize` - Business value scoring
- `/executive-summary` - Key metrics

