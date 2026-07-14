---
name: arch-debt
description: Analyze, document, and prioritize technical debt in the codebase
argument-hint: '[--path dir] [--severity critical|high|medium|low]'
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - agents/software-architector.md
  - commands/arch-review.md
  - commands/pm-sprint.md
---

# Technical Debt Command

Analyze, document, and prioritize technical debt in the codebase.

## Usage

```
/arch-debt
/arch-debt --path <directory>
/arch-debt --add "Description of debt"
/arch-debt --report
```

## Options

- `--path <dir>` - Analyze specific directory
- `--add "description"` - Add new tech debt item
- `--report` - Generate full tech debt report
- `--prioritize` - Re-prioritize existing debt
- `--category [code|architecture|testing|docs|security]` - Filter by category
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/arch-debt
/arch-debt --path src/legacy
/arch-debt --add "Migrate from callbacks to async/await in api module"
/arch-debt --report --category security
```

## Output Format

### Analysis Mode (Default)
```markdown
# Technical Debt Analysis

## Summary
| Metric | Value | Trend |
|--------|-------|-------|
| Total Debt Items | 23 | ↑ +2 |
| Critical | 3 | → |
| High | 8 | ↓ -1 |
| Medium | 10 | ↑ +2 |
| Low | 2 | ↑ +1 |
| Estimated Effort | 45 days | ↑ |

## Debt by Category

| Category | Count | Effort | Priority |
|----------|-------|--------|----------|
| Code Quality | 12 | 15d | Medium |
| Architecture | 5 | 20d | High |
| Testing | 4 | 5d | Medium |
| Documentation | 2 | 3d | Low |
| Security | 0 | 0d | - |
```

#### Analysis template — critical items

```markdown
<!-- …continued: critical items -->
## Critical Items 🔴

### TD-001: Legacy Authentication Module
- **Category**: Architecture
- **Location**: `src/auth/legacy/`
- **Impact**: Security risk, maintenance burden
- **Effort**: 5 days
- **Interest**: Growing - blocks new features
- **Recommendation**: Prioritize in next sprint

### TD-002: Untyped API Responses
- **Category**: Code Quality
- **Location**: `src/api/handlers/`
- **Impact**: Runtime errors, poor DX
- **Effort**: 3 days
- **Interest**: Moderate - causes debugging time
- **Recommendation**: Address during related work

### TD-003: Missing Database Indexes
- **Category**: Architecture
- **Location**: `prisma/schema.prisma`
- **Impact**: Performance degradation at scale
- **Effort**: 1 day
- **Interest**: Growing with data volume
- **Recommendation**: Fix immediately
```

#### Analysis template — high priority & debt interest

```markdown
<!-- …continued: high priority items -->
## High Priority Items ⚠️

### TD-004: Callback Hell in Data Import
- **Location**: `src/import/processor.ts`
- **Impact**: Hard to maintain, error-prone
- **Effort**: 2 days
- **Recommendation**: Refactor to async/await

### TD-005: Duplicated Validation Logic
- **Location**: `src/api/`, `src/services/`
- **Impact**: Inconsistent validation
- **Effort**: 3 days
- **Recommendation**: Create shared validation module

## Debt Interest Calculation

| Item | Principal | Interest Rate | Total Cost if Delayed 6mo |
|------|-----------|---------------|---------------------------|
| TD-001 | 5d | High (50%) | 7.5d |
| TD-002 | 3d | Medium (25%) | 3.75d |
| TD-003 | 1d | High (50%) | 1.5d |
```

#### Analysis template — recommended actions & tracking

```markdown
<!-- …continued: recommended actions -->
## Recommended Actions

### This Sprint
1. TD-003: Database indexes (1 day, high impact)
2. TD-001: Begin auth module migration (2 days)

### Next Sprint
1. TD-001: Complete auth migration (3 days)
2. TD-004: Async/await refactor (2 days)

### Backlog
1. TD-002: Type API responses (3 days)
2. TD-005: Consolidate validation (3 days)

## Tracking

| Quarter | Added | Resolved | Net Change |
|---------|-------|----------|------------|
| Q4 2024 | 8 | 5 | +3 |
| Q3 2024 | 6 | 9 | -3 |
| Q2 2024 | 10 | 7 | +3 |
```

## Debt Categories

| Category | Description | Examples |
|----------|-------------|----------|
| Code Quality | Code smells, complexity | Duplicated code, long methods |
| Architecture | Structural issues | Tight coupling, missing layers |
| Testing | Test gaps | Low coverage, flaky tests |
| Documentation | Missing/outdated docs | No API docs, stale README |
| Security | Security concerns | Deprecated deps, weak crypto |

## Interest Rate Guide

| Rate | Meaning | Examples |
|------|---------|----------|
| High | Compounds quickly | Security issues, blocking features |
| Medium | Steady cost | Maintenance burden, slower dev |
| Low | Minimal ongoing cost | Style issues, minor improvements |

## Integration

This command supports:
- Sprint planning - Allocate debt reduction time
- Architecture reviews - Identify new debt
- Prioritization - Balance features vs debt

