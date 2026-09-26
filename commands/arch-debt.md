---
name: arch-debt
description: Analyze, document, and prioritize technical debt in the codebase
argument-hint: '[--path <dir>] [--add "<description>"] [--report] [--prioritize] [--category code|architecture|testing|docs|security] [--platform <p>]'
allowed-tools: Read, Glob, Grep, Write, Edit
related:
  - agents/software-architector.md
  - commands/arch-review.md
  - commands/sprint.md
---

# Technical Debt Command

Analyze, document, and prioritize technical debt in the codebase. Analysis is the default mode;
`--add`, `--report`, and `--prioritize` write under `.context/audits/`.

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--path <dir>` | any directory | Analyze that directory only (default: whole codebase) |
| `--add "<description>"` | text | Append a tech debt item to the register `.context/audits/tech-debt.md` |
| `--report` | — | Write the full tech debt report to `.context/audits/arch-debt-<YYYYMMDD-HHMMSS>.md` |
| `--prioritize` | — | Re-prioritize existing debt in place, in the register `.context/audits/tech-debt.md` |
| `--category <c>` | `code`, `architecture`, `testing`, `docs`, `security` | Filter by category (default: all) |
| `--platform <p>` | `apple`, `android`, `web`, `systems`, `backend`, `ai`, `all` | Target platform context (default: `all`) |

## Examples

```
/arch-debt [--path <dir>] [--add "<description>"] [--report] [--prioritize] [--category code|architecture|testing|docs|security] [--platform <p>]
/arch-debt
/arch-debt --path src/legacy --prioritize
/arch-debt --add "Migrate from callbacks to async/await in api module"
/arch-debt --report --category security --platform apple
```

## Output Format

Analysis mode (the default) emits every section below, in this order.

### Report skeleton — summary & inventory

```markdown
# Technical Debt Analysis

## Summary
| Metric | Value | Trend |
Rows: Total Debt Items, Critical, High, Medium, Low, Estimated Effort (days).
Trend ↑ / ↓ / → against the previous run.

## Debt by Category
| Category | Count | Effort | Priority |
One row per § Debt Categories entry; effort in days.

## Critical Items 🔴   (then: ## High Priority Items ⚠️)
### TD-NNN: <title>
- **Category**, **Location** (`path`), **Impact**, **Effort** (Nd)
- **Interest**: rate + why it compounds — see § Interest Rate Guide
- **Recommendation**: fix immediately | next sprint | during related work
```

### Report skeleton — economics & plan

```markdown
## Debt Interest Calculation
| Item | Principal | Interest Rate | Total Cost if Delayed 6mo |
Principal in days; total cost = principal x (1 + rate).

## Recommended Actions
### This Sprint
### Next Sprint
### Backlog
Numbered `TD-NNN: <action> (Nd)`, highest impact-per-day first.

## Tracking
| Quarter | Added | Resolved | Net Change |
Last 3-4 quarters, newest first.
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
