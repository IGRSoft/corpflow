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
- Set `attribution.sessionUrl` to omit the claude.ai session link from commits/PRs (CC ≥ 2.1.183) — keeps the no-AI-footer rule above enforced at the tooling layer

## Git Safety (beyond CC defaults)

- Never push directly to main/master without PR
- Never delete branches without explicit user instruction

### Auto-mode Git Safety (CC ≥ 2.1.183)

In auto mode the runtime enforces these guards independently of the rules above:

- **Destructive git is blocked unless discard is explicitly requested** — `git reset --hard`, `git checkout -- .`, `git clean -fd`, and `git stash drop` are refused unless the prompt explicitly asks to discard those changes.
- **`commit --amend` is blocked unless the commit was made by the agent this session** — a pre-existing commit cannot be rewritten. This enforces the plugin's existing "prefer new commits over `--amend`" rule with a runtime rationale: after a failed hook the commit did not happen, so amend would destroy prior work.
- **IaC `destroy` is blocked unless the specific stack is named** — a bare `destroy` is refused; the target stack must be specified.

FN-stage commit/cleanup and `create-pr` therefore run under this guard. None of the worktask flows rely on amending a non-agent commit, so the guard is documentation-forward (it reinforces, rather than changes, current behavior).

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
