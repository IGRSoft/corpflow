---
name: arch-review
description: Perform architecture review evaluating architectural integrity, scalability, and maintainability
argument-hint: '[--pr <number> | --path <dir>] [--scope full|focused] [--checklist]'
allowed-tools: Read, Glob, Grep
related:
  - agents/software-architector.md
  - commands/arch-decision.md
  - commands/arch-debt.md
---

# Architecture Review Command

Review architectural integrity, scalability, and maintainability for a PR, a directory, or the
current working tree.

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--pr <number>` | PR number | Review that PR |
| `--path <dir>` | directory or module | Review that directory (default: the current working tree) |
| `--scope <depth>` | `full`, `focused` | Review depth (default: `focused`) |
| `--checklist` | — | Score against § Review Checklist |

```
/arch-review [--pr <number> | --path <dir>] [--scope full|focused] [--checklist]
/arch-review
/arch-review --pr 123 --scope full --checklist
/arch-review --path src/auth
```

## Output Format

One markdown report; emit every section below, in this order.

### Report skeleton — assessment & patterns

~~~markdown
# Architecture Review

## Summary
| Aspect | Score | Status |
Rows: Overall Architecture, SOLID Compliance, Scalability, Security,
Maintainability. Score `N/10`; status ✅ / ⚠️ / 🔴.

## Impact Assessment
| Factor | Level | Notes |
Rows: Architectural Impact, Risk Level, Breaking Changes.

## Pattern Analysis
### Positive Patterns ✅
- **<Pattern>**: where it is applied well

### Concerns ⚠️
#### N. <Title>
**Location**: `file:line` — **Issue** — **Impact**: High|Medium|Low + why —
**Recommendation**. Add a current-vs-recommended code snippet when the fix is
structural.

### Anti-Patterns Found 🔴
Same shape as Concerns, or "None critical".
~~~

### Report skeleton — scale, security & verdict

~~~markdown
## Scalability Review
| Component | Current | At 10x Scale | Recommendation |

## Security Architecture
| Check | Status | Notes |
Rows: Authentication, Authorization, Data Encryption, Input Validation,
Secret Management.

## Recommendations
### Must Fix (Before Merge)
### Should Fix (Soon)
### Consider (Future)
Numbered, most impactful first.

## Architecture Decision Records
### New ADRs Needed
`ADR-XXX: <topic>`
### Existing ADRs Affected
`ADR-NNN: <topic>` + (compliant | needs update)

## Approval
| Status | Condition |
One row: ✅ Approved / ⚠️ Approved with required fixes / 🔴 Blocked, plus the
blocking condition.
~~~

## Architect Delegation (dual-pass)

Detect the platform per `skills/shared/platform-detection.md § Detection Rules`. When that
platform has an architect agent, run both passes:

1. **General review** — SOLID, scalability, security, error handling (this command)
2. **Platform architecture review** — delegate to that architect for pattern compliance,
   boundary violations, and language/runtime-specific concerns

### Resolving and combining

Take the architect and its plugin prefix from `skills/shared/routing-matrix.md §
Functional-role aliases` rather than hardcoding either here. If the platform is ambiguous, or its
plugin is not installed, run the general pass alone and say so in the output.

Merge both passes into one report: architect findings become a `### <Platform> Architecture`
subsection of Pattern Analysis, its P0-P3 severities mapped to Must Fix / Should Fix / Consider.

**Apple nuance**: server-side Swift (`Package.swift` with no UI imports) is backend-shaped —
skip apple-architector and use `backend-architector` as the second pass when installed.

## Review Checklist

- [ ] SOLID principles compliance
- [ ] Design pattern appropriateness
- [ ] Dependency management
- [ ] Error handling strategy
- [ ] Security architecture
- [ ] Scalability considerations
- [ ] Testability
- [ ] Documentation
- [ ] Platform architecture pattern compliance (when the platform has an architect agent)
