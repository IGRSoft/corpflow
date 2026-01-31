# Documentation Audit Command

Audit documentation for gaps, outdated content, and quality issues.

## Usage

```
/doc-audit
/doc-audit --path <directory>
/doc-audit --type [code|readme|api|architecture]
```

## Options

- `--path <dir>` - Audit specific directory
- `--type <type>` - Focus on specific doc type
- `--fix` - Auto-fix simple issues
- `--report` - Generate detailed report

## Examples

```
/doc-audit
/doc-audit --path src/auth --type code
/doc-audit --type api --report
```

## Output Format

```markdown
# Documentation Audit Report

## Summary

| Category | Files | Issues | Score |
|----------|-------|--------|-------|
| Code Comments | 45 | 12 | 73% |
| README Files | 8 | 3 | 62% |
| API Docs | 15 | 5 | 67% |
| Architecture | 3 | 2 | 33% |
| **Total** | **71** | **22** | **65%** |

---

## Critical Issues 🔴

### Missing API Documentation
**Files Affected**: 5 endpoints
**Impact**: External developers cannot use API

| Endpoint | Method | Documentation |
|----------|--------|---------------|
| `/api/auth/sso` | POST | ❌ Missing |
| `/api/users/preferences` | GET | ❌ Missing |
| `/api/users/preferences` | PUT | ❌ Missing |
| `/api/export/csv` | POST | ❌ Missing |
| `/api/webhooks` | POST | ❌ Missing |

**Recommendation**: Add OpenAPI/Swagger documentation

### Outdated Architecture Docs
**File**: `docs/architecture/auth.md`
**Last Updated**: 6 months ago
**Issue**: Does not reflect SSO implementation

**Recommendation**: Update with current auth flow including OAuth

---

## High Priority Issues ⚠️

### Undocumented Functions

| File | Function | Lines | Complexity |
|------|----------|-------|------------|
| `src/auth/service.ts` | `refreshToken` | 112-145 | High |
| `src/api/handlers/export.ts` | `generateCSV` | 45-89 | Medium |
| `src/utils/crypto.ts` | `encryptData` | 23-45 | High |

**Impact**: Hard to maintain, onboarding difficulty

### README Gaps

| Directory | Issue |
|-----------|-------|
| `src/auth/` | Missing README |
| `src/api/handlers/` | No usage examples |
| `packages/shared/` | Outdated dependencies section |

---

## Medium Priority Issues

### Incomplete Code Comments

| File | Issue |
|------|-------|
| `src/auth/middleware.ts:34` | TODO without context |
| `src/api/routes.ts:78` | Commented code block |
| `src/utils/date.ts:12` | Outdated comment |

### Inconsistent Formatting

| Type | Count | Issue |
|------|-------|-------|
| JSDoc | 8 | Missing @returns |
| JSDoc | 5 | Missing @param types |
| Markdown | 3 | Broken links |

---

## Code Documentation Score

### By Module

| Module | Functions | Documented | Score |
|--------|-----------|------------|-------|
| auth | 24 | 18 | 75% |
| api | 32 | 20 | 62% |
| utils | 18 | 15 | 83% |
| ui | 45 | 38 | 84% |

### Quality Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Doc Coverage | 65% | 80% | ⚠️ |
| Example Coverage | 45% | 60% | ⚠️ |
| Link Health | 92% | 100% | ⚠️ |
| Freshness | 68% | 90% | ⚠️ |

---

## Recommended Actions

### Immediate (This Sprint)
1. Document 5 missing API endpoints
2. Add README to `src/auth/`
3. Update architecture docs for SSO

### Short-term (Next Sprint)
1. Add JSDoc to undocumented functions
2. Fix broken markdown links
3. Remove commented code blocks

### Long-term (Backlog)
1. Implement documentation linting
2. Add doc coverage to CI
3. Create documentation style guide

---

## Auto-Fix Available

The following can be auto-fixed with `--fix`:

| Issue | Count | Command |
|-------|-------|---------|
| Missing @returns | 8 | `/doc-audit --fix` |
| Trailing whitespace | 15 | `/doc-audit --fix` |
| Broken relative links | 2 | `/doc-audit --fix` |

---

## Documentation Health Trend

| Month | Score | Change |
|-------|-------|--------|
| Jan 2025 | 65% | - |
| Dec 2024 | 62% | +3% |
| Nov 2024 | 58% | +4% |
| Oct 2024 | 55% | +3% |

---

## Next Review

Schedule: Monthly
Next: February 10, 2025
Owner: Technical Writer
```

## Audit Criteria

| Category | Checks |
|----------|--------|
| Code | JSDoc presence, @param, @returns, examples |
| README | Sections, examples, installation, usage |
| API | Endpoints, params, responses, examples |
| Architecture | Currency, diagrams, decisions |

## Integration

This command works with:
- `/api-docs` - Generate missing API docs
- `/readme-update` - Fix README issues
- `/workflow` DC stage - Documentation phase

## Related

- [technical-writer](../agents/technical-writer.md) - Documentation expertise
- [api-docs](./api-docs.md) - API documentation
- [readme-update](./readme-update.md) - README maintenance
