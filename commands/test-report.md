---
name: test-report
description: Generate a comprehensive QA summary report with test results, coverage, and quality metrics
argument-hint: '[--worktask-id ID]'
model: sonnet
allowed-tools: Read, Glob, Grep, TaskList
related:
  - agents/qa-engineer.md
  - commands/test-plan.md
  - commands/test-coverage.md
---

# QA Report Command

Generate a comprehensive QA summary report for completed work, including test results, coverage, and quality metrics.

## Usage

```
/test-report
/test-report --format [markdown|html|json]
/test-report --include-screenshots
```

## Options

- `--format <type>` - Output format (default: markdown)
- `--include-screenshots` - Include test failure screenshots
- `--verbose` - Include all test details
- `--summary-only` - Executive summary only
- `--platform <apple|android|web|systems|backend|ai|all>` - Target platform context (default: all; detected per `skills/shared/platform-detection.md`)

## Examples

```
/test-report
/test-report --format html --include-screenshots
/test-report --summary-only
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
```

### Template — test execution summary

```markdown
<!-- …continued: test execution summary -->
## Test Execution Summary

### Test Selection Mode

| Field | Value |
|-------|-------|
| `test_mode` (PL) | <build-only / scoped / full> |
| Effective mode (after auto-promotion) | <same or promoted> |
| Auto-promotion reason | <e.g., "Selected list empty under build-only" or "—"> |
| Selected Tests count | N (DV) + M (QA additions) |
| `ui_visual_check` | <true / false> |

### By Type
| Type | Total | Passed | Failed | Skipped (with reason) |
|------|-------|--------|--------|------------------------|
| Unit | 35 | 35 | 0 | 0 |
| Integration | 12 | 10 | 2 | 0 |
| E2E | 3 | 2 | 1 | 0 |
| Visual Comparison | — | — | — | <"skipped — ui_visual_check=false" if applicable> |
```

#### Execution — selected tests breakdown

```markdown
<!-- …continued: selected tests breakdown -->
### Selected Tests Breakdown

| Source | Count | Examples |
|--------|-------|----------|
| `@test-required` | N | AppLaunchTests.testLaunchSucceeds |
| `metadata.always_required_tests` | N | test_auth_smoke.py::test_login_roundtrip |
| `@depends-on:` matches | N | PaymentRefundTests.testRefundFlow ← `PaymentService` |
| `covers-changed-files` | N | userRepository.test.ts ← `userRepository.ts` |
| Module-level (scoped only) | N | All `:core:networking` tests |
| QA additions | N | <new edge-case tests> |
| **Excluded** | N | <reason summary; e.g., "no marker, mode=build-only"> |
```

#### Execution — selection warnings and by priority

```markdown
<!-- …continued: selection warnings, by priority -->
### Selection Warnings

Quote any `WARN:` lines from `.context/logs/test-selection-warnings.md`. Empty section means clean run.

### By Priority
| Priority | Total | Passed | Failed |
|----------|-------|--------|--------|
| Critical | 8 | 8 | 0 |
| High | 15 | 14 | 1 |
| Medium | 20 | 18 | 2 |
| Low | 7 | 7 | 0 |
```

### Template — failed tests

```markdown
<!-- …continued: failed tests -->
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
```

### Template — coverage and quality metrics

```markdown
<!-- …continued: coverage report, quality metrics -->
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
```

### Template — bugs and regression

```markdown
<!-- …continued: bugs found, regression testing -->
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
```

### Template — recommendations, sign-off, attachments

```markdown
<!-- …continued: recommendations, sign-off, attachments -->
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
- At end of QA stage - Document test results
- Before FN stage - Quality gate check
- For stakeholder review - ST stage input

