---
name: docs-audit
description: Audit documentation for gaps, outdated content, and quality issues
argument-hint: '[--path dir] [--scope full|section]'
# tools: Write takes no path predicate, so the bound is stated here and in `## Options`:
# the only file this command creates is `.context/audits/docs-audit-<YYYYMMDD-HHMMSS>.md`.
# Edit exists solely for `--fix`, bounded to the rows under `## Auto-Fix Available`.
allowed-tools: Read, Glob, Grep, Write, Edit
related:
  - agents/technical-writer.md
  - commands/docs-readme.md
---

# Documentation Audit Command

Audit documentation for gaps, outdated content, and quality issues.

## Usage

```
/docs-audit [--path <dir>] [--type code|readme|api|architecture] [--scope full|section] [--fix] [--report]
```

## Options

| Option | Values | Purpose |
|--------|--------|---------|
| `--path <dir>` | any directory | Audit that subtree only (default: repo root) |
| `--type <type>` | `code`, `readme`, `api`, `architecture` | Restrict to one doc type (default: all four) |
| `--scope <scope>` | `full`, `section` | Whole-file audit vs. the addressed section only (default: `full`) |
| `--fix` | — | Apply the mechanical fixes listed under Auto-Fix Available, in place, to files this run already read |
| `--report` | — | Emit every report section and write it to `.context/audits/docs-audit-<YYYYMMDD-HHMMSS>.md`, the only file this command creates; without it, emit Summary + Critical Issues only |

## Examples

```
/docs-audit
/docs-audit --path src/auth --type code
/docs-audit --type api --report
/docs-audit --path packages/shared --scope section --fix
```

## Output Format

One markdown report, sections in the order below. Issue tables sort by severity, then path.
Report only what the audit found — omit a section with no findings rather than emitting an empty table.

### Report sections — findings

| Section | Shape |
|---------|-------|
| `## Summary` | `Category \| Files \| Issues \| Score`, one row per audit category plus a bold **Total** row |
| `## Critical Issues 🔴` | Per issue: H3 title, `**Files Affected**`, `**Impact**` (who is blocked), an evidence table, `**Recommendation**` |
| `## High Priority Issues ⚠️` | Undocumented functions (`File \| Function \| Lines \| Complexity`) and README gaps (`Directory \| Issue`) |
| `## Medium Priority Issues` | Incomplete comments (`File:line \| Issue`) and inconsistent formatting (`Type \| Count \| Issue`) |

### Report sections — scores and actions

| Section | Shape |
|---------|-------|
| `## Code Documentation Score` | By module (`Module \| Functions \| Documented \| Score`) and quality metrics (`Metric \| Value \| Target \| Status`) |
| `## Recommended Actions` | Numbered lists under Immediate (this sprint), Short-term (next sprint), Long-term (backlog) |
| `## Auto-Fix Available` | `Issue \| Count \| Command` — only rows `--fix` can actually resolve (missing `@returns`, trailing whitespace, broken relative links) |
| `## Documentation Health Trend` | `Month \| Score \| Change`, newest first |
| `## Next Review` | Schedule, next date, owner (Technical Writer) |

Quality-metric targets: doc coverage 80%, example coverage 60%, link health 100%, freshness 90%. Status is ✅ at or above target, ⚠️ below.

## Audit Criteria

| Category | Checks |
|----------|--------|
| Code | JSDoc presence, @param, @returns, examples |
| README | Sections, examples, installation, usage |
| API | Endpoints, params, responses, examples |
| Architecture | Currency, diagrams, decisions |

## Integration

- `/docs-readme` — fix the README issues this audit reports
- `/worktask` DC stage — documentation phase
- `agents/technical-writer.md` — owning agent
