---
name: release-engineering
description: Semantic versioning, changelog generation, and deployment readiness patterns for RE stage. Use when preparing releases, generating changelogs, or deployment readiness checks.
effort: high
---

# Release Engineering

Guidelines for version management, changelog generation, and deployment readiness.

For deployment and platform-specific checklists, see `${CLAUDE_SKILL_DIR}/references/checklists.md`

For rollback plan template, see `${CLAUDE_SKILL_DIR}/references/rollback-template.md`

## Semantic Versioning (SemVer)

### Version Format

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]

Examples:
1.0.0
2.1.3
3.0.0-alpha.1
1.2.3-beta.2+build.456
```

### Version Bump Rules

| Change Type | Bump | Before | After |
|-------------|------|--------|-------|
| Breaking API change | MAJOR | 1.2.3 | 2.0.0 |
| New feature (compatible) | MINOR | 1.2.3 | 1.3.0 |
| Bug fix (compatible) | PATCH | 1.2.3 | 1.2.4 |
| Pre-release | Suffix | 2.0.0 | 2.0.0-alpha.1 |

### Breaking Change Detection

A change is BREAKING if it:
- Removes a public API
- Changes return type of public method
- Adds required parameter to public method
- Changes behavior that clients depend on
- Removes or renames configuration options
- Changes database schema incompatibly

### Pre-release Labels

| Label | Use Case |
|-------|----------|
| `-alpha.N` | Internal testing, unstable |
| `-beta.N` | External testing, feature complete |
| `-rc.N` | Release candidate, production ready |

## Conventional Commits

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types and Changelog Mapping

| Type | Description | Changelog | Bump |
|------|-------------|-----------|------|
| `feat` | New feature | Added | MINOR |
| `fix` | Bug fix | Fixed | PATCH |
| `docs` | Documentation | - | - |
| `style` | Formatting | - | - |
| `refactor` | Code change | Changed | PATCH |
| `perf` | Performance | Changed | PATCH |
| `test` | Tests | - | - |
| `chore` | Maintenance | - | - |
| `ci` | CI/CD | - | - |
| `build` | Build system | - | - |

### Breaking Changes

```
feat!: remove deprecated login endpoint

BREAKING CHANGE: The /api/v1/login endpoint has been removed.
Use /api/v2/auth instead.
```

## Changelog Generation

**Canonical tool**: `scripts/changelog-from-git.sh`

One-line invocation contract:

```bash
# From a git range (writes Keep-a-Changelog markdown to stdout)
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" "v1.1.0..HEAD" --version "1.2.0"

# From a pre-fetched subjects file (untrusted / offline / testable)
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" --file subjects.txt --version "1.2.0"

# Against a specific repo directory
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" "v1.1.0..HEAD" --repo /path/to/repo --version "1.2.0"
```

### Script Classification Behavior

The script classifies all 10 conventional-commit types (feat, fix, docs, style, refactor, perf, test, chore, ci, build) into Keep-a-Changelog sections (Added / Changed / Fixed / Other). Non-conventional commits are bucketed under "Other" — never dropped. Breaking changes (`!` suffix) are prefixed with `**BREAKING**` in Added. Silent types (docs, style, test, chore, ci, build) are suppressed. Output is always compact markdown — no large echoes.

The spec below (Keep a Changelog Format + Commit-to-Section mapping) is retained as reference for the model and for human review; the happy path is the script above.

### Keep a Changelog Format (spec / reference)

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.2.0] - 2024-01-15

### Added
- New user dashboard with analytics (#123)
- Dark mode support (#145)

### Changed
- Updated login flow for better security (#156)
- Improved error messages (#167)

### Deprecated
- Legacy API endpoints (removed in 2.0.0)

### Removed
- Support for iOS 14 (#178)

### Fixed
- Crash on large file uploads (#189)
- Memory leak in image processing (#190)

### Security
- Fixed XSS vulnerability in comments (#200)

## [1.1.0] - 2024-01-01
...
```

### Commit-to-Section Mapping (spec / reference)

| Type | KCL Section | Notes |
|------|-------------|-------|
| `feat` | Added | MINOR bump |
| `feat!` / `BREAKING CHANGE` | Added (BREAKING prefix) | MAJOR bump |
| `fix` | Fixed | PATCH bump |
| `refactor` | Changed | PATCH bump |
| `perf` | Changed | PATCH bump |
| `docs` | — (suppressed) | no bump |
| `style` | — (suppressed) | no bump |
| `test` | — (suppressed) | no bump |
| `chore` | — (suppressed) | no bump |
| `ci` | — (suppressed) | no bump |
| `build` | — (suppressed) | no bump |
| _(non-conventional)_ | Other | never dropped |

## Integration Points

- **release-engineer agent**: Uses these patterns for RE stage
- **project-manager**: Uses release artifacts for deployment
- **apple-developer plugin**: iOS/macOS submission coordination
