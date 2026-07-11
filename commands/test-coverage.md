---
name: test-coverage
description: Analyze test coverage gaps and generate recommendations for improving test quality
argument-hint: '[--path dir] [--threshold N]'
allowed-tools: Read, Glob, Grep, Bash(swift test:*)
model: haiku
related:
  - agents/qa-engineer.md
  - commands/test-plan.md
  - commands/test-report.md
---

# Test Coverage Command

Analyze test coverage gaps and generate recommendations for improving test quality.

## Usage

```
/test-coverage
/test-coverage --path <directory>
/test-coverage --threshold <percentage>
```

## Options

- `--path <dir>` - Analyze specific directory (default: entire project)
- `--threshold <n>` - Set coverage threshold (default: 80)
- `--report` - Generate detailed HTML report
- `--critical-only` - Focus on critical/high-risk areas
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/test-coverage
/test-coverage --path src/auth --threshold 90
/test-coverage --critical-only
```

## Output Format

```markdown
# Test Coverage Analysis

## Summary
| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Line Coverage | 72% | 80% | ⚠️ Below |
| Branch Coverage | 65% | 75% | ⚠️ Below |
| Function Coverage | 85% | 80% | ✅ Met |

## Coverage by Module

| Module | Lines | Branches | Functions | Risk |
|--------|-------|----------|-----------|------|
| src/auth | 45% | 38% | 60% | 🔴 High |
| src/api | 78% | 72% | 88% | 🟡 Medium |
| src/utils | 92% | 88% | 95% | 🟢 Low |
| src/ui | 68% | 55% | 75% | 🟡 Medium |

## Critical Gaps

### 🔴 High Priority

#### src/auth/oauth.ts (45% coverage)
**Untested Functions:**
- `handleCallback()` - Lines 45-78
- `refreshToken()` - Lines 112-145
- `validateState()` - Lines 156-170

**Risk**: Security-critical authentication logic without tests

**Recommendation**: Add integration tests for OAuth flow

#### src/auth/session.ts (52% coverage)
**Untested Branches:**
- Error handling in `createSession()` - Line 34
- Timeout logic in `validateSession()` - Lines 67-72

**Risk**: Session management edge cases untested

### 🟡 Medium Priority

#### src/api/endpoints.ts (78% coverage)
**Untested:**
- Error responses for 4xx/5xx status codes
- Rate limiting behavior

**Recommendation**: Add error scenario tests

## Recommended Actions

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| 1 | Add OAuth flow integration tests | M | High |
| 2 | Test session error handling | S | Medium |
| 3 | Add API error response tests | S | Medium |
| 4 | Increase UI component coverage | L | Low |

## Files Without Tests

| File | Lines | Risk Assessment |
|------|-------|-----------------|
| src/auth/oauth.ts | 180 | 🔴 Critical - needs tests |
| src/utils/crypto.ts | 45 | 🔴 Critical - security |
| src/ui/Toast.tsx | 32 | 🟢 Low - simple UI |

## Test Quality Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Assertion Density | 2.3/test | ✅ Good |
| Test Isolation | 95% | ✅ Good |
| Flaky Tests | 3 | ⚠️ Needs attention |
| Avg Test Duration | 45ms | ✅ Good |

## Selection Marker Coverage

Reports the percentage of test files annotated with markers from `skills/shared/test-selection-syntax.md`. Low marker coverage means selective execution defaults to `covers-changed-files` (filename-correlation only) — degrading to `scoped` mode automatically.

| Marker | Tests Annotated | % of Total | Status |
|--------|-----------------|------------|--------|
| `@test-required` | 5 | 10% | — |
| `@depends-on:` | 18 | 36% | ⚠️ Below 50% target |
| `@test-tag:` | 12 | 24% | — |
| **Any marker** | **22** | **44%** | ⚠️ Below 50% target — `test_mode: build-only` will warn |

### Untagged Tests (warn-only on first release; block once project sets `selective_tests_ready: true`)

| File | Tests | Recommendation |
|------|-------|----------------|
| Tests/UserRepositoryTests.swift | 8 | Add `@depends-on: UserRepository` |
| Tests/NetworkClientTests.swift | 12 | Add `@depends-on: NetworkClient` and `@test-tag: regression` |
| Tests/AppLaunchTests.swift | 1 | Add `@test-required` (smoke test) |

## Testing Framework Compliance

| Framework | Usage | Status |
|-----------|-------|--------|
| Swift Testing | Unit tests | ✅ Required |
| XCTest | UI tests only | ✅ Allowed |
| XCTest | Unit tests | ⚠️ Migrate to Swift Testing |
```

## Integration

Use this command:
- Before `/test-plan` - Identify what needs testing
- During QA stage - Verify coverage goals
- In `/test-report` - Include coverage metrics

