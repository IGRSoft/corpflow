---
name: Git Conventions
description: Commit message format, PR format, and git safety overrides beyond CC defaults
category: git
priority: high
alwaysApply: true
---

# Git Conventions

## Commit Message Format

Based on [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

```
#<issue> <type>[optional scope][!]: <short summary>  (max 72 chars)

[Optional body: explain WHY and context, separated by blank line]

[Optional footer(s): git trailer format]
```

### Types

| Type     | Use for                                 | SemVer  |
|----------|-----------------------------------------|---------|
| feat     | New feature                             | MINOR   |
| fix      | Bug fix                                 | PATCH   |
| perf     | Performance improvement                 | PATCH   |
| refactor | Code restructuring (no behavior change) | —       |
| build    | Build system, dependencies              | —       |
| ci       | CI/CD configuration                     | —       |
| chore    | Non-functional cleanup                  | —       |
| docs     | Documentation only                      | —       |
| style    | Formatting, whitespace (no logic change)| —       |
| test     | Tests only                              | —       |

### Scope

Optional context in parentheses: `feat(auth): Add OAuth2 flow`

### Breaking Changes

Append `!` after type/scope for breaking API changes (SemVer MAJOR):

```
#PROJ-123 feat(api)!: Remove deprecated /v1 endpoints
```

Or use `BREAKING CHANGE:` footer (must be uppercase):

```
#PROJ-123 refactor(auth): Migrate to token-based auth

BREAKING CHANGE: session cookies are no longer supported
```

### Footers

Use git trailer format (`token: value` or `token #value`). Hyphens replace spaces in tokens (except `BREAKING CHANGE`).

### Rules

- Present tense, capitalize summary, no ending period
- Always prefix with issue code (#PROJ-123)
- Body must be separated from summary by a blank line
- Never add "Generated with" or "Co-Authored-By" footers

## Git Safety (beyond CC defaults)

- Never push directly to main/master without PR
- Never delete branches without explicit user instruction

## Pull Request Format

Title: `<type>[scope][!]: <summary>`

```markdown
## Motivation
[Why this change is needed]

## Changes
- [Change 1]
- [Change 2]

## Notes
[Additional context, testing instructions, etc.]
```

## GitHub Issue Types

| Type | Keywords                                  |
|------|-------------------------------------------|
| Bug           | Problems, errors, crashes        |
| Feature       | New functionality, enhancements  |
| Task          | Refactoring, technical debt      |
| Documentation | Missing or incorrect docs        |
| Configuration | Build system, CI/CD, setup       |
