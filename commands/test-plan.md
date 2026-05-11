---
name: test-plan
description: Generate a comprehensive test plan from requirements or code changes with coverage analysis
argument-hint: <feature or module description>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

# Test Plan Command

Generate a comprehensive test plan from requirements or code changes. Creates structured test cases with coverage analysis.

## Usage

```
/test-plan "Feature or requirement description"
/test-plan --from-pr <PR number>
/test-plan --from-file <path to requirements>
```

## Options

- `--from-pr <number>` - Generate test plan from PR changes
- `--from-file <path>` - Generate from requirements file
- `--coverage` - Include coverage targets
- `--automation` - Focus on automation-ready test cases
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/test-plan "User authentication with OAuth"
/test-plan --from-pr 123
/test-plan --from-file .context/planning-0.md --coverage    # or any planning-N.md the PL produced
```

## Output Format

```markdown
# Test Plan: User Authentication

## Overview
| Attribute | Value |
|-----------|-------|
| Feature | User Authentication with OAuth |
| Test Types | Unit, Integration, E2E |
| Priority | High |
| Estimated Test Effort | 4 hours |

## Test Coverage Targets
| Type | Target | Current |
|------|--------|---------|
| Unit Tests | 80% | - |
| Integration Tests | 70% | - |
| E2E Critical Paths | 100% | - |

## Testing Framework

| Test Type | Framework | Example |
|-----------|-----------|---------|
| Unit Tests | Swift Testing | `@Suite`, `@Test`, `#expect` |
| UI Tests | XCTest | `XCUIApplication`, `XCTestCase` |

**Note**: XCUITest requires XCTest framework; all other tests should use Swift Testing.

## Test Cases

### Selection Markers (required for new test cases)

Each generated test case MUST include selection metadata so DV's parser can include the test in the right Selected Tests list. See `skills/shared/test-selection-syntax.md`.

| Field | Example | When |
|-------|---------|------|
| `@test-required` | comment marker on the test | Smoke / critical-path tests |
| `@depends-on:` | one symbol per marker, e.g. `@depends-on: TokenService` | Cross-file behavior coverage |
| `@test-tag:` | `smoke`, `regression`, `perf`, `ui`, `flaky` | Categorization |

The output table for each test case (below) gains two columns: `Required?` and `Dependencies`. Columns may be empty if not applicable, but should not be omitted.

### Unit Tests

#### UT-001: Token Validation
- **Priority**: High
- **Required?**: Yes (`@test-required`)
- **Dependencies**: `TokenService`, `JWTValidator` (`@depends-on:`)
- **Tag**: `smoke`
- **Preconditions**: Valid JWT token available
- **Steps**:
  1. Call `validateToken()` with valid token
  2. Verify token claims are extracted
  3. Verify expiration is checked
- **Expected**: Token validated, claims returned
- **Automation**: Yes

#### UT-002: Token Refresh
- **Priority**: High
- **Preconditions**: Expired access token, valid refresh token
- **Steps**:
  1. Call `refreshToken()` with expired access token
  2. Verify new token is requested
  3. Verify new token is stored
- **Expected**: New access token returned
- **Automation**: Yes

### Integration Tests

#### IT-001: OAuth Login Flow
- **Priority**: Critical
- **Preconditions**: OAuth provider configured
- **Steps**:
  1. Initiate OAuth login
  2. Complete provider authentication
  3. Verify callback handling
  4. Verify user session created
- **Expected**: User logged in, session active
- **Automation**: Yes (mock provider)

### E2E Tests

#### E2E-001: Complete Login Journey
- **Priority**: Critical
- **Preconditions**: Test user account exists
- **Steps**:
  1. Navigate to login page
  2. Click OAuth login button
  3. Complete authentication
  4. Verify redirect to dashboard
  5. Verify user info displayed
- **Expected**: User sees personalized dashboard
- **Automation**: Yes (Playwright)

## Edge Cases

| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| EC-001 | Expired token on protected route | Redirect to login |
| EC-002 | OAuth provider unavailable | Show error, offer retry |
| EC-003 | Invalid callback state | Reject, log security event |
| EC-004 | Concurrent login attempts | Handle gracefully |

## Security Test Cases

| ID | Test | Pass Criteria |
|----|------|---------------|
| SEC-001 | Token stored securely | Not in localStorage/cookies |
| SEC-002 | CSRF protection | State parameter validated |
| SEC-003 | XSS in OAuth flow | No script injection possible |

## Test Data Requirements

| Data | Source | Notes |
|------|--------|-------|
| Test OAuth tokens | Mock provider | Various states (valid, expired) |
| Test user accounts | Seed script | Different roles and permissions |

## Dependencies

- Mock OAuth provider for CI
- Test database with seed data
- E2E browser automation setup
```

## Integration

This command is typically used:
- After `/pm-requirements` - Generate tests from requirements
- Before `/workflow` Q stage - Prepare test strategy
- With `/test-coverage` - Identify gaps

## Related

- [qa-engineer](../agents/qa-engineer.md) - QA expertise
- [Workflow System](../skills/workflow.md) - Q stage details
