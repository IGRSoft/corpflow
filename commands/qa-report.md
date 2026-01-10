# QA Report Command

Generate a comprehensive QA summary report for completed work, including test results, coverage, and quality metrics.

## Usage

```
/qa-report
/qa-report --format [markdown|html|json]
/qa-report --include-screenshots
```

## Options

- `--format <type>` - Output format (default: markdown)
- `--include-screenshots` - Include test failure screenshots
- `--verbose` - Include all test details
- `--summary-only` - Executive summary only

## Examples

```
/qa-report
/qa-report --format html --include-screenshots
/qa-report --summary-only
```

## Output Format

```markdown
# QA Report: User Authentication Feature

## Executive Summary

| Metric | Value | Status |
|--------|-------|--------|
| Overall Quality | 92% | ✅ Pass |
| Tests Passed | 47/50 | ⚠️ 3 failures |
| Coverage | 82% | ✅ Above threshold |
| Critical Bugs | 0 | ✅ None |
| Release Ready | Yes | Conditional |

## Test Execution Summary

### By Type
| Type | Total | Passed | Failed | Skipped |
|------|-------|--------|--------|---------|
| Unit | 35 | 35 | 0 | 0 |
| Integration | 12 | 10 | 2 | 0 |
| E2E | 3 | 2 | 1 | 0 |

### By Priority
| Priority | Total | Passed | Failed |
|----------|-------|--------|--------|
| Critical | 8 | 8 | 0 |
| High | 15 | 14 | 1 |
| Medium | 20 | 18 | 2 |
| Low | 7 | 7 | 0 |

## Failed Tests

### IT-005: Token Refresh Under Load
- **Type**: Integration
- **Priority**: High
- **Error**: Timeout after 30s
- **Root Cause**: Race condition in token refresh
- **Status**: Known issue, non-blocking
- **Ticket**: #456

### E2E-003: Login with Slow Network
- **Type**: E2E
- **Priority**: Medium
- **Error**: Element not found within timeout
- **Root Cause**: Flaky test, needs retry logic
- **Status**: Test improvement needed
- **Ticket**: #457

## Coverage Report

| Module | Line | Branch | Target | Status |
|--------|------|--------|--------|--------|
| auth | 85% | 78% | 80% | ✅ |
| api | 88% | 82% | 80% | ✅ |
| ui | 72% | 65% | 70% | ✅ |
| **Total** | **82%** | **75%** | **80%** | ✅ |

## Quality Metrics

| Metric | Value | Trend | Notes |
|--------|-------|-------|-------|
| Defect Density | 0.5/KLOC | ↓ | Improved from 0.8 |
| Test Stability | 94% | ↑ | 3 flaky tests remaining |
| Avg Test Time | 2.3s | → | Stable |
| Code Complexity | 12 avg | → | Within limits |

## Bugs Found

| ID | Severity | Summary | Status |
|----|----------|---------|--------|
| BUG-123 | Medium | Token not cleared on logout | Fixed |
| BUG-124 | Low | Typo in error message | Fixed |
| BUG-125 | Medium | Race condition in refresh | Open |

## Regression Testing

| Area | Tests | Status |
|------|-------|--------|
| Existing Auth | 15 | ✅ All pass |
| User Management | 8 | ✅ All pass |
| API Endpoints | 12 | ✅ All pass |

## Recommendations

### Release Blockers
- None

### Pre-Release Actions
1. Fix flaky E2E test (E2E-003)
2. Monitor token refresh in staging

### Post-Release Monitoring
- Watch for token refresh errors in logs
- Monitor authentication latency

## Sign-Off

| Role | Name | Status | Date |
|------|------|--------|------|
| QA Lead | - | ✅ Approved | - |
| Dev Lead | - | Pending | - |
| Product | - | Pending | - |

## Attachments

- [Full Test Results](./test-results.json)
- [Coverage Report](./coverage/index.html)
- [Performance Metrics](./performance.md)
```

## Integration

This command is typically used:
- At end of Q stage - Document test results
- Before F stage - Quality gate check
- For stakeholder review - S stage input

## Related

- [qa-engineer](../agents/qa-engineer.md) - QA expertise
- [test-plan](./test-plan.md) - Test planning
- [test-coverage](./test-coverage.md) - Coverage analysis
