---
name: arch-review
description: Perform architecture review evaluating architectural integrity, scalability, and maintainability
argument-hint: '[--pr N | --path dir] [--scope full|focused]'
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - agents/software-architector.md
  - commands/arch-decision.md
  - commands/arch-debt.md
---

# Architecture Review Command

Perform architecture review for PRs, features, or system changes. Evaluates architectural integrity, scalability, and maintainability.

## Usage

```
/arch-review
/arch-review --pr <number>
/arch-review --path <directory>
/arch-review --scope [full|focused]
```

## Options

- `--pr <number>` - Review specific PR
- `--path <dir>` - Review specific directory/module
- `--scope [full|focused]` - Review depth (default: focused)
- `--checklist` - Use standard architecture checklist

## Examples

```
/arch-review
/arch-review --pr 123 --scope full
/arch-review --path src/auth
```

## Output Format

~~~markdown
# Architecture Review

## Summary
| Aspect | Score | Status |
|--------|-------|--------|
| Overall Architecture | 8/10 | ✅ Good |
| SOLID Compliance | 7/10 | ⚠️ Minor issues |
| Scalability | 9/10 | ✅ Excellent |
| Security | 8/10 | ✅ Good |
| Maintainability | 7/10 | ⚠️ Needs attention |

## Impact Assessment
| Factor | Level | Notes |
|--------|-------|-------|
| Architectural Impact | Medium | New service boundary |
| Risk Level | Low | Well-understood patterns |
| Breaking Changes | None | Backward compatible |
~~~

### Output Format — Pattern Analysis

~~~markdown
<!-- …continued: Pattern Analysis -->
## Pattern Analysis

### Positive Patterns ✅
- **Dependency Injection**: Properly implemented in auth module
- **Repository Pattern**: Clean data access abstraction
- **Interface Segregation**: Small, focused interfaces

### Concerns ⚠️

#### 1. Tight Coupling in UserService
**Location**: `src/services/UserService.ts:45-78`
**Issue**: Direct database calls bypassing repository
**Impact**: Medium - reduces testability
**Recommendation**: Inject UserRepository instead of direct DB access
~~~

#### Output Format — Concerns (continued)

~~~markdown
<!-- …continued: concern #1 code sample -->
```typescript
// Current (problematic)
class UserService {
  async getUser(id: string) {
    return await db.query('SELECT * FROM users WHERE id = ?', [id]);
  }
}

// Recommended
class UserService {
  constructor(private userRepo: UserRepository) {}

  async getUser(id: string) {
    return await this.userRepo.findById(id);
  }
}
```

#### 2. Missing Error Boundary
**Location**: `src/api/handlers/`
**Issue**: No centralized error handling
**Impact**: Low - inconsistent error responses
**Recommendation**: Add error middleware

### Anti-Patterns Found 🔴
- None critical
~~~

### Output Format — Scalability & Security

~~~markdown
<!-- …continued: Scalability Review -->
## Scalability Review

| Component | Current | At 10x Scale | Recommendation |
|-----------|---------|--------------|----------------|
| Auth Service | ✅ OK | ⚠️ Bottleneck | Add caching |
| Database | ✅ OK | ✅ OK | Indexes sufficient |
| API Gateway | ✅ OK | ✅ OK | Horizontal scaling ready |

## Security Architecture

| Check | Status | Notes |
|-------|--------|-------|
| Authentication | ✅ | JWT with proper validation |
| Authorization | ✅ | Role-based access control |
| Data Encryption | ✅ | AES-256 for sensitive data |
| Input Validation | ⚠️ | Missing in 2 endpoints |
| Secret Management | ✅ | Using environment variables |
~~~

### Output Format — Recommendations & Approval

~~~markdown
<!-- …continued: Recommendations -->
## Recommendations

### Must Fix (Before Merge)
1. Add input validation to `/api/users` endpoint

### Should Fix (Soon)
1. Refactor UserService to use repository pattern
2. Add centralized error handling

### Consider (Future)
1. Add caching layer for auth tokens
2. Consider event sourcing for audit trail

## Architecture Decision Records

### New ADRs Needed
- ADR-XXX: Authentication token storage strategy

### Existing ADRs Affected
- ADR-005: API versioning (compliant)
- ADR-012: Error handling (needs update)

## Approval

| Status | Condition |
|--------|-----------|
| ✅ Approved | With required fixes |
| Blockers | Input validation must be added |
~~~

## Architect Delegation (dual-pass)

Detect the platform using `skills/shared/platform-detection.md § Detection Rules`. Whenever
the detected platform has an architect agent, run a dual-pass review:

1. **General review** — SOLID, scalability, security, error handling (this command)
2. **Platform architecture review** — delegate to that platform's architect for pattern
   compliance, boundary violations, and language/runtime-specific concerns

### Resolving the architect agent

Read the architect from `skills/shared/compatible-plugins.md § Functional-role agents`
(`apple-architector`, `kotlin-architector`, `frontend-architector`, `system-architector`,
`backend-architector`, `ai-architector`) — take the plugin prefix from that table rather
than hardcoding it here.

If the platform is ambiguous, or its plugin is not installed, run the general pass alone and
say so in the output. Never silently downgrade to single-pass.

### Combining the passes

Merge both passes into one report. The architect's findings appear as a
`### <Platform> Architecture` subsection within Pattern Analysis, with its P0-P3 severities
mapped to Must Fix / Should Fix / Consider.

**Apple nuance**: for server-side Swift (`Package.swift` with no UI imports), skip the
apple-architector delegation — the work is backend-shaped, so `backend-architector` is the
correct second pass when that plugin is present.

## Review Checklist

The command evaluates against:
- [ ] SOLID principles compliance
- [ ] Design pattern appropriateness
- [ ] Dependency management
- [ ] Error handling strategy
- [ ] Security architecture
- [ ] Scalability considerations
- [ ] Testability
- [ ] Documentation
- [ ] Platform architecture pattern compliance (when the platform has an architect agent)

## Integration

This command is used:
- In AR stage - Formal architecture review
- Before merging large PRs
- When introducing new patterns
