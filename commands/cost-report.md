# Cost Report

Generate cost analysis for completed or in-progress workflows with token usage breakdown and optimization recommendations.

## Usage

```
/cost-report
/cost-report --stage D
/cost-report --budget-alert 80%
/cost-report --export
/cost-report --optimize
```

## Options

- `--stage <code>` - Show costs for specific stage only (P, A, T, D, Q, W, F, S)
- `--budget-alert <percent>` - Set alert threshold (default: 75%)
- `--export` - Export cost data to CSV
- `--optimize` - Include optimization recommendations
- `--detailed` - Show per-operation token breakdown
- `--compare <task-id>` - Compare costs with another task

## Output Format

### Summary Report (Default)

```
## Cost Report: [Task Name]

### Overview
| Metric | Value |
|--------|-------|
| Total Tokens | 45,000 |
| Estimated Cost | $0.28 |
| Budget Used | 56% |
| Workflow Type | standard |

### By Stage
| Stage | Tokens | Model | Cost | % of Total |
|-------|--------|-------|------|------------|
| P | 7,500 | sonnet | $0.023 | 17% |
| A | 15,000 | opus | $0.225 | 33% |
| T | 4,000 | sonnet | $0.012 | 9% |
| D | 18,500 | sonnet | $0.056 | 41% |
| Q | - | - | - | - |
| W | - | - | - | - |
| F | - | - | - | - |
| S | - | - | - | - |

### Status
Current Stage: D (in_progress)
Stages Complete: P, A, T
Estimated Remaining: ~$0.15
```

### Optimization Report (`--optimize`)

```
## Optimization Recommendations

### High Impact
1. **A Stage: Consider sonnet for non-critical decisions**
   - Current: opus ($0.225)
   - Recommended: sonnet for research, opus for final decision only
   - Potential Savings: ~$0.15 (67%)

2. **Context Compression Opportunity**
   - Current context size: 35,000 tokens
   - After compression: ~20,000 tokens
   - Potential Savings: ~$0.05 (15%)

### Medium Impact
3. **Batch File Reads**
   - Detected: 12 separate file read operations
   - Recommendation: Batch into 3 groups
   - Potential Savings: ~$0.02

### Model Usage Summary
| Model | Invocations | Tokens | Cost |
|-------|-------------|--------|------|
| haiku | 5 | 3,000 | $0.001 |
| sonnet | 12 | 27,000 | $0.081 |
| opus | 3 | 15,000 | $0.225 |
```

### Stage Detail (`--stage D`)

```
## D Stage Cost Detail

### Summary
| Metric | Value |
|--------|-------|
| Total Tokens | 18,500 |
| Model | sonnet |
| Cost | $0.056 |
| Duration | 8 minutes |

### Operation Breakdown
| Operation | Tokens | Cost |
|-----------|--------|------|
| Code analysis | 5,000 | $0.015 |
| Implementation | 8,500 | $0.026 |
| Self-review | 3,000 | $0.009 |
| Formatting | 2,000 | $0.006 |

### Context Usage
- Input context: 12,000 tokens
- Output generated: 6,500 tokens
- Overhead: ~2,000 tokens (system, formatting)
```

## Cost Calculation

### Formula

```
Stage Cost = (Input Tokens + Output Tokens) × Model Rate

Model Rates (per 1M tokens):
- haiku: $0.25 input, $1.25 output
- sonnet: $3.00 input, $15.00 output
- opus: $15.00 input, $75.00 output
```

### Budget Tracking

```json
{
  "cost_tracking": {
    "total_estimated_tokens": 45000,
    "total_cost": 0.28,
    "budget_limit": 0.50,
    "budget_used_percent": 56,
    "by_stage": {
      "P": { "tokens": 7500, "model": "sonnet", "cost": 0.023 },
      "A": { "tokens": 15000, "model": "opus", "cost": 0.225 }
    },
    "alerts": []
  }
}
```

## Alert Thresholds

| Threshold | Action | Visual |
|-----------|--------|--------|
| < 50% | Normal | Green |
| 50-74% | Warning logged | Yellow |
| 75-89% | User notified | Orange |
| 90-99% | Compression suggested | Red |
| 100% | Workflow paused | Critical |

## Examples

### Basic Cost Report
```
/cost-report
```
Shows summary for current workflow.

### Stage-Specific Analysis
```
/cost-report --stage A
```
Detailed breakdown for Architecture stage.

### With Optimization Suggestions
```
/cost-report --optimize
```
Includes actionable recommendations for cost reduction.

### Set Budget Alert
```
/cost-report --budget-alert 60%
```
Alert when 60% of budget is consumed.

### Export for Tracking
```
/cost-report --export
```
Generates `cost-report.csv` in `.context/`.

### Compare Tasks
```
/cost-report --compare previous-task-id
```
Side-by-side comparison with another workflow.

## Integration

This command is used:
- Throughout workflow for cost monitoring
- At stage transitions for optimization checks
- At workflow completion for final analysis
- By project-manager (F stage) for budget reporting

## Related

- `skills/cost-optimization.md` - Cost optimization strategies
- `skills/context-compression.md` - Context compression techniques
- `/estimate` - Pre-workflow cost estimation
- `/context-status` - Context window analysis
