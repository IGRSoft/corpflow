---
name: test-coverage
description: Analyze test coverage gaps and generate recommendations for improving test quality
argument-hint: '[--path dir] [--threshold N]'
allowed-tools: Read, Glob, Grep, Bash(swift test:*), Bash(xcodebuild:*), Bash(gradle:*), Bash(./gradlew:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(yarn:*), Bash(jest:*), Bash(vitest:*), Bash(pytest:*), Bash(uv:*), Bash(go test:*), Bash(cargo:*), Bash(ctest:*), Bash(bats:*)
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
- `--platform <apple|android|web|systems|backend|ai|all>` - Target platform context (default: all; detected per `skills/shared/platform-detection.md`)

## Examples

```
/test-coverage
/test-coverage --path src/auth --threshold 90
/test-coverage --critical-only
```

## Running the suite

Coverage numbers need a run. Prefer delegating to `/<plugin>:build-test` for the detected
platform — it knows the repo's build system, coverage flags, and report location. Fall back to
the scoped runners in `allowed-tools` (`swift test`, `./gradlew`, `vitest`, `pytest`, `go test`,
`ctest`, …) only when no plugin covers the repo. Never assume a Swift toolchain.

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
```

### Template — critical gaps

```markdown
<!-- …continued: critical gaps -->
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
```

#### Medium priority gaps and recommended actions

```markdown
<!-- …continued: medium priority gaps, recommended actions -->
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
```

### Template — untested files and quality metrics

```markdown
<!-- …continued: files without tests, test quality metrics -->
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
```

### Template — selection marker coverage

```markdown
<!-- …continued: selection marker coverage -->
## Selection Marker Coverage

Reports the percentage of test files annotated with markers from `skills/shared/test-selection-syntax.md`. Low marker coverage means selective execution defaults to `covers-changed-files` (filename-correlation only) — degrading to `scoped` mode automatically.

| Marker | Tests Annotated | % of Total | Status |
|--------|-----------------|------------|--------|
| `@test-required` | 5 | 10% | — |
| `@depends-on:` | 18 | 36% | ⚠️ Below 50% target |
| `@test-tag:` | 12 | 24% | — |
| **Any marker** | **22** | **44%** | ⚠️ Below 50% target — `test_mode: build-only` will warn |
```

#### Untagged tests

```markdown
<!-- …continued: untagged tests -->
### Untagged Tests (warn-only on first release; block once project sets `selective_tests_ready: true`)

| File | Tests | Recommendation |
|------|-------|----------------|
| tests/test_user_repository.py | 8 | Add `@depends-on: UserRepository` |
| src/net/networkClient.test.ts | 12 | Add `@depends-on: NetworkClient` and `@test-tag: regression` |
| Tests/AppLaunchTests.swift | 1 | Add `@test-required` (smoke test) |
```

#### Framework compliance

```markdown
<!-- …continued: framework compliance -->
## Testing Framework Compliance

"Required" means **the project's established framework** for that layer — resolved from
`skills/shared/testing-strategy.md § Framework by platform` and from what the repo already uses.
Flag divergence from it, never divergence from a specific vendor's framework.

| Layer | Expected (this repo) | Found | Status |
|-------|----------------------|-------|--------|
| Unit | <e.g. Vitest / Swift Testing / JUnit 5 / pytest> | <actual> | ✅ / ⚠️ mixed frameworks |
| Integration | <e.g. Testcontainers / Robolectric / MSW> | <actual> | ✅ |
| UI / E2E | <e.g. Playwright / XCUITest / Compose UI test> | <actual> | ✅ |
```

#### Framework compliance — per-platform expectations

```markdown
<!-- …continued: expected frameworks by platform -->
| Platform | Unit | UI / E2E | Common divergence to flag |
|----------|------|----------|---------------------------|
| apple | Swift Testing | XCTest / XCUITest | New unit tests still written in XCTest |
| android | JUnit 5 + MockK | Espresso / Compose UI test | JUnit 4 runner left on new modules |
| web | Vitest or Jest | Playwright | Both Vitest and Jest present in one package |
| systems | GoogleTest/Catch2, pytest, bats | n/a | Ad-hoc `main()` test binaries outside `ctest` |
| backend | Stack-native + Testcontainers | Contract tests | Integration tests hitting a shared live DB |
| ai | pytest | Eval harness with thresholds | Evals with no recorded threshold to regress against |
```

## Integration

Use this command:
- Before `/test-plan` - Identify what needs testing
- During QA stage - Verify coverage goals
- In `/test-report` - Include coverage metrics

