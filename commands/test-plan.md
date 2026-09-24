---
name: test-plan
description: Generate a comprehensive test plan from requirements or code changes with coverage analysis
argument-hint: '"<feature or requirement>" | --from-pr <number> | --from-file <path> [--coverage] [--automation] [--platform <p>]'
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/qa-engineer.md
  - skills/worktask/SKILL.md
  - commands/product-requirements.md
  - commands/test-coverage.md
---

# Test Plan Command

Generate a test plan with structured test cases and coverage targets from a requirement, a PR, or
a requirements file.

## Options

| Option | Values | Purpose |
|--------|--------|---------|
| `--from-pr <number>` | PR number | Plan from that PR's changes |
| `--from-file <path>` | requirements file, e.g. a PL `planning-N.md` | Plan from that file |
| `--coverage` | — | Include coverage targets |
| `--automation` | — | Focus on automation-ready test cases |
| `--platform <p>` | `apple`, `android`, `web`, `systems`, `backend`, `ai`, `all` | Target platform context (default: `all`; detected per `skills/shared/platform-detection.md`) |

```
/test-plan "<feature or requirement>" | --from-pr <number> | --from-file <path> [--coverage] [--automation] [--platform <p>]
/test-plan "User authentication with OAuth"
/test-plan --from-pr 123 --automation
/test-plan --from-file .context/planning-0.md --coverage
/test-plan "Payment refund flow" --platform backend
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
```

### Template — testing framework

Fill the table from the detected platform's row only (one framework per plan, not a survey): detect
per `skills/shared/platform-detection.md`, take the row from
`skills/shared/testing-strategy.md § Framework by platform`, which also carries the Apple-only
XCTest/XCUITest split. If the repo already uses a different framework, the repo wins; note the
deviation.

```markdown
<!-- …continued: testing framework -->
## Testing Framework

| Test Type | Framework | Example |
|-----------|-----------|---------|
| Unit Tests | <project unit framework> | <canonical syntax> |
| Integration Tests | <project integration framework> | <canonical syntax> |
| UI / E2E Tests | <project UI framework, or "n/a — no UI layer"> | <canonical syntax> |
```

### Template — test cases

Every case carries selection metadata so DV's parser can place it in the right Selected Tests
list, per `skills/shared/test-selection-syntax.md`: `@test-required` (smoke / critical-path),
`@depends-on: <Symbol>` (one symbol per marker), `@test-tag:` (`smoke`, `regression`, `perf`,
`ui`, `flaky`). Emit `Required?` and `Dependencies` on every case, empty when not applicable.

```markdown
<!-- …continued: test cases -->
## Test Cases

### Unit Tests

#### UT-001: Token Validation
- **Priority**: High
- **Required?**: Yes (`@test-required`)
- **Dependencies**: `TokenService`, `JWTValidator` (`@depends-on:`)
- **Tag**: `smoke`
- **Preconditions**: Valid JWT token available
- **Steps**: 1. Call `validateToken()` 2. Verify claims extracted 3. Verify expiry checked
- **Expected**: Token validated, claims returned
- **Automation**: Yes
```

#### Test case pattern

Repeat that field set under `### Integration Tests` (`IT-NNN`) and `### E2E Tests` (`E2E-NNN`).
Those cases also name the environment in Preconditions (mock OAuth provider, seeded test user)
and the driver in Automation (`Yes (mock provider)`, `Yes (Playwright)`). Critical user
journeys are `Priority: Critical`.

### Template — edge cases, security, test data

```markdown
<!-- …continued: edge cases, security, test data, dependencies -->
## Edge Cases

| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| EC-001 | Expired token on protected route | Redirect to login |
| EC-002 | OAuth provider unavailable | Show error, offer retry |
| EC-003 | Invalid callback state | Reject, log security event |

## Security Test Cases

| ID | Test | Pass Criteria |
|----|------|---------------|
| SEC-001 | Token stored securely | Not in localStorage/cookies |
| SEC-002 | CSRF protection | State parameter validated |

## Test Data Requirements

| Data | Source | Notes |
|------|--------|-------|
| Test OAuth tokens | Mock provider | Various states (valid, expired) |
| Test user accounts | Seed script | Different roles and permissions |

## Dependencies

- Mock OAuth provider for CI, test database with seed data, E2E automation setup
```
