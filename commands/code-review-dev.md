# Developer Code Review Command

Perform platform-aware code review using specialized developer expertise. Reviews code quality, patterns, and platform-specific best practices.

## Usage

```
/code-review-dev
/code-review-dev --platform apple --path src/
/code-review-dev --pr 123
```

## Options

- `--platform <apple|android|web|all>` - Platform context (default: auto-detect)
- `--path <dir>` - Review specific directory
- `--pr <number>` - Review PR changes
- `--focus <areas>` - Focus areas: security, performance, patterns, tests
- `--severity <level>` - Minimum severity: info, warning, error

## Examples

```
/code-review-dev
/code-review-dev --platform apple --path Sources/
/code-review-dev --pr 42 --focus security,performance
/code-review-dev --path src/components --focus patterns
```

## Output Format

```markdown
# Developer Code Review

## Summary

| Category | Issues | Status |
|----------|--------|--------|
| Code Quality | 2 | ⚠️ Minor |
| Platform Patterns | 1 | ⚠️ Minor |
| Performance | 0 | ✅ Good |
| Security | 1 | 🔴 Critical |
| Tests | 1 | ⚠️ Minor |

**Platform**: Apple (Swift/iOS)
**Files Reviewed**: 12
**Lines Changed**: 234

## Critical Issues 🔴

### 1. Insecure Data Storage
**File**: `src/auth/TokenManager.swift:23`
**Severity**: Critical
**Issue**: Storing auth tokens in UserDefaults instead of Keychain

```swift
// Current (insecure)
UserDefaults.standard.set(token, forKey: "authToken")

// Recommended (secure)
try KeychainService.save(token, forKey: "authToken")
```

**Impact**: Sensitive data exposed to backup extraction
**Fix**: Migrate to Keychain storage

## Warnings ⚠️

### 2. Missing Error Handling
**File**: `src/api/NetworkClient.swift:45-52`
**Severity**: Warning
**Issue**: Force unwrapping optional without error handling

```swift
// Current
let data = try! await fetchData(from: url)

// Recommended
do {
    let data = try await fetchData(from: url)
} catch {
    logger.error("Fetch failed: \(error)")
    throw NetworkError.fetchFailed(error)
}
```

### 3. Non-Idiomatic Pattern
**File**: `src/models/User.swift:12`
**Severity**: Info
**Issue**: Using class where struct is more appropriate

```swift
// Current
class User { ... }

// Recommended (value semantics)
struct User { ... }
```

## Platform-Specific Findings

### Swift/iOS Patterns
- ✅ Proper use of async/await
- ✅ SwiftUI view composition
- ⚠️ Consider using `@MainActor` for UI updates
- ⚠️ Missing `Sendable` conformance on shared types

### Apple Guidelines
- ✅ Follows Human Interface Guidelines
- ✅ Accessibility labels present
- ⚠️ Missing Dynamic Type support in 2 views

## Recommendations

### Must Fix (Before Merge)
1. Move token storage to Keychain
2. Add proper error handling to network calls

### Should Fix (Soon)
1. Add `@MainActor` annotations
2. Convert User class to struct
3. Add Dynamic Type support

### Consider (Future)
1. Add unit tests for TokenManager
2. Implement retry logic for network failures

## Test Coverage

| Component | Coverage | Status |
|-----------|----------|--------|
| Auth | 45% | ⚠️ Below target |
| API | 72% | ✅ Good |
| Models | 88% | ✅ Excellent |

## Approval

| Status | Condition |
|--------|-----------|
| ⚠️ Changes Requested | Fix critical security issue |
```

## Focus Areas

- **security**: Authentication, data storage, input validation, secrets
- **performance**: Memory, CPU, network, battery impact
- **patterns**: Platform idioms, design patterns, architecture
- **tests**: Coverage, quality, edge cases

## Integration

This command is used:
- Before merging PRs
- In Q stage for code quality verification
- For periodic codebase health checks

## Related

- [developer](../agents/developer.md) - Platform developer agent
- [code-impl](./code-impl.md) - Implementation command
- [senior-review](./senior-review.md) - Senior developer review
- [arch-review](./arch-review.md) - Architecture review
