---
name: swift-arch-review
description: Review Swift code for architecture pattern conformance, anti-patterns, and best practices
argument-hint: '[--pr N | --path dir] [--pattern mvvm|mvi|tca|clean|reactive|mvp|coordinator]'
model: sonnet
allowed-tools: Read, Glob, Grep
---

# Swift Architecture Review Command

Review Swift code for architecture pattern conformance, anti-patterns, and best practices.

## Usage

```
/swift-arch-review
/swift-arch-review --pr 42
/swift-arch-review --path Sources/Features/Profile
/swift-arch-review --pattern tca
/swift-arch-review --pr 42 --pattern mvvm
```

## Options

- `--pr <number>` — Review specific PR
- `--path <dir>` — Review specific directory/module
- `--pattern <name>` — Specify architecture pattern (auto-detected if omitted)
  - Values: `mvvm`, `mvi`, `tca`, `clean`, `reactive`, `mvp`, `coordinator`

## Process

1. **Load** the `swift-arch-review` skill
2. **Detect pattern** — from `--pattern` flag, `.context/analyzing.md`, or codebase signals
3. **Load checklist** — pattern-specific PR review checklist
4. **Scan anti-patterns** — check code against pattern-specific anti-pattern catalog
5. **Score** — rate 5 dimensions (pattern conformance, state management, DI quality, concurrency safety, testability)
6. **Report** — output findings with file:line references and fix suggestions

## Output Format

```markdown
# Swift Architecture Review

## Pattern: {pattern name}
Detection method: {--pattern flag | analyzing.md | code signals}

## Score
| Dimension | Score | Notes |
|-----------|-------|-------|
| Pattern Conformance | {0-1} | {brief note} |
| State Management | {0-1} | {brief note} |
| DI Quality | {0-1} | {brief note} |
| Concurrency Safety | {0-1} | {brief note} |
| Testability | {0-1} | {brief note} |
| **Total** | **{N}/5** | **{Excellent/Good/Usable/Needs rework}** |

## Checklist
{Pattern-specific checklist with pass/fail for each item}

## Findings

### Violations
{Numbered list with location, issue, and fix}

### Anti-Patterns Detected
{From anti-patterns catalog with detection signal and fix direction}

## Recommendations

### Must Fix (Before Merge)
{Critical violations}

### Should Fix (Soon)
{Important issues}

### Consider (Future)
{Improvement suggestions}
```

## Integration

- **DV stage** — Developer self-check before marking complete
- **QA stage** — Architecture conformance validation
- **Pre-merge** — Reviewer applies pattern-specific checklist
- **Tech debt** — Periodic architecture conformance audit

## Related

- [swift-arch-review skill](../skills/swift-arch-review/SKILL.md) — Scoring rubric and checklists
- [swift-architecture skill](../skills/swift-architecture/SKILL.md) — Pattern references
- [arch-review](./arch-review.md) — General architecture review
- [code-review-dev](./code-review-dev.md) — Platform-aware code review
