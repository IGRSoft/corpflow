---
name: tech-review
description: Perform deep technical review evaluating code quality, performance, and security practices
model: sonnet
---

# Technical Review Command

Perform deep technical review of implementation code. Evaluates code quality, performance, security practices, and implementation patterns beyond standard code review checklists.

> **See also**: For standard platform-specific code review (pre-merge), use `/code-review-dev`. For estimation accuracy reviews, use `/senior-review`.

## Usage

```
/tech-review
/tech-review --pr <number>
/tech-review --path <file-or-directory>
/tech-review --focus [quality|performance|security|debt]
```

## Options

- `--pr <number>` - Review specific PR
- `--path <path>` - Review specific file or directory
- `--focus [quality|performance|security|debt]` - Focus area (default: quality)
- `--depth [quick|standard|deep]` - Review depth (default: standard)
- `--output [summary|detailed]` - Output verbosity (default: detailed)

## Examples

```
/tech-review
/tech-review --pr 123 --focus performance
/tech-review --path src/services/auth.ts --depth deep
/tech-review --focus debt --output summary
```

## Output Format

```markdown
# Technical Review

## Summary

| Dimension | Score | Status |
|-----------|-------|--------|
| Correctness | 9/10 | ✅ Excellent |
| Readability | 7/10 | ⚠️ Needs attention |
| Maintainability | 8/10 | ✅ Good |
| Efficiency | 8/10 | ✅ Good |
| Security | 9/10 | ✅ Excellent |
| Testability | 7/10 | ⚠️ Needs attention |

**Overall**: 8.0/10 - Ready for merge with minor improvements

## Code Quality Analysis

### Complexity Assessment

| File | Cyclomatic | Cognitive | Status |
|------|------------|-----------|--------|
| `auth.ts` | 8 | 12 | ✅ OK |
| `validation.ts` | 15 | 22 | ⚠️ High |
| `handlers.ts` | 6 | 8 | ✅ OK |

### Duplication

| Pattern | Occurrences | Impact |
|---------|-------------|--------|
| Error handling block | 3 | Low |
| Validation logic | 2 | Medium |

### Naming & Clarity

| Issue | Location | Suggestion |
|-------|----------|------------|
| Vague name | `data` in line 45 | Use `userData` or `userRecord` |
| Acronym | `validateDTO` | Consider `validateDataTransfer` |

## Performance Analysis

### Hot Paths

| Path | Complexity | Concern |
|------|------------|---------|
| `processRequest()` | O(n) | ✅ Acceptable |
| `searchUsers()` | O(n²) | ⚠️ Consider optimization |

### Resource Management

| Check | Status | Notes |
|-------|--------|-------|
| Memory allocation | ✅ | No leaks detected |
| Connection handling | ✅ | Properly pooled |
| File handles | ⚠️ | Missing cleanup in error path |

### Caching Opportunities

- `getUserById()` - Consider memoization (called 12 times/request)
- `loadConfig()` - Should cache result (static data)

## Security Implementation

### OWASP Checklist

| Check | Status | Notes |
|-------|--------|-------|
| Input validation | ✅ | Comprehensive |
| Output encoding | ✅ | XSS protected |
| Authentication | ✅ | Properly implemented |
| Authorization | ⚠️ | Missing check on line 78 |
| Data protection | ✅ | Encrypted at rest |
| Logging | ⚠️ | Contains PII |

### Vulnerability Assessment

| Risk | Severity | Location | Remediation |
|------|----------|----------|-------------|
| Missing auth check | Medium | `admin.ts:78` | Add role verification |
| PII in logs | Low | `logger.ts:23` | Sanitize user data |

## Technical Debt Identified

### New Debt

| Item | Type | Interest | Effort |
|------|------|----------|--------|
| Complex validation | Code | Medium | M |
| Missing error types | Code | Low | S |

### Existing Debt Touched

| Item | Change | Recommendation |
|------|--------|----------------|
| Legacy API wrapper | Extended | Consider refactoring |

## Recommendations

### Must Fix (Before Merge)

1. **Add authorization check** - `admin.ts:78`
   ```typescript
   // Add before line 78
   if (!user.hasRole('admin')) {
     throw new UnauthorizedError('Admin access required');
   }
   ```

2. **Sanitize logs** - `logger.ts:23`
   ```typescript
   // Replace user object with sanitized version
   logger.info('User action', { userId: user.id, action: action });
   ```

### Should Fix (Within Sprint)

1. Reduce complexity in `validation.ts` - Extract helper functions
2. Add cleanup in error path for file handles

### Consider (Future)

1. Implement caching for `getUserById()`
2. Refactor O(n²) search to use index

## Test Coverage Impact

| Metric | Before | After | Status |
|--------|--------|-------|--------|
| Line coverage | 78% | 82% | ✅ Improved |
| Branch coverage | 65% | 71% | ✅ Improved |
| Changed code coverage | - | 85% | ✅ Good |

### Missing Test Cases

- Error path for file handle cleanup
- Edge case: empty user list in search

## Approval

| Status | Condition |
|--------|-----------|
| ⚠️ Conditional Approval | Fix security issues before merge |
| Blockers | Authorization check, log sanitization |
```

## Review Dimensions

The command evaluates:

### Quality
- Cyclomatic and cognitive complexity
- Code duplication and DRY violations
- Naming conventions and clarity
- Error handling completeness
- Documentation adequacy

### Performance
- Algorithm complexity (Big O)
- Resource management
- Caching opportunities
- Hot path optimization
- Memory efficiency

### Security
- OWASP Top 10 checklist
- Input validation
- Authentication/authorization
- Data protection
- Secure coding practices

### Debt
- New debt introduced
- Existing debt affected
- Interest rate assessment
- Remediation opportunities

## Integration

This command is used:
- In DV stage - Implementation review
- In QA stage - Quality deep dive
- Before merging complex PRs
- When evaluating technical debt

## Related

- [technical-lead](../agents/technical-lead.md) - Technical excellence expertise
- [code-review-dev](./code-review-dev.md) - Standard code review
- [tech-debt](./tech-debt.md) - Technical debt analysis
- [senior-review](./senior-review.md) - Senior developer review
