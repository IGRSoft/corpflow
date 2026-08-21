---
name: release-engineering
description: Use when preparing releases, generating changelogs, or deployment readiness checks. Semantic versioning, changelog generation, and deployment readiness patterns for RE stage.
effort: high
---

# Release Engineering

Version management, changelog generation, and deployment readiness for the RE stage.

- Deployment and platform-specific checklists: `${CLAUDE_SKILL_DIR}/references/checklists.md`
- Rollback plan template: `${CLAUDE_SKILL_DIR}/references/rollback-template.md`

## Semantic Versioning (SemVer)

### Version Format

`MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]` — e.g. `1.0.0`, `2.1.3`, `3.0.0-alpha.1`, `1.2.3-beta.2+build.456`.

### Version Bump Determination

**Canonical tool**: `scripts/version-bump-from-git.sh`

```bash
# Prints exactly one of: major|minor|patch|none
bash "${CLAUDE_SKILL_DIR}/scripts/version-bump-from-git.sh" "v1.1.0..HEAD"

# Per-commit breakdown on stderr; stdout stays a single token
bash "${CLAUDE_SKILL_DIR}/scripts/version-bump-from-git.sh" "v1.1.0..HEAD" --explain

# From a pre-fetched capture (offline / testable)
bash "${CLAUDE_SKILL_DIR}/scripts/version-bump-from-git.sh" --file records.bin
```

#### Two rules the tables cannot express

1. **Highest severity wins across the range.** 3 × `fix:` plus 1 × `feat:` is MINOR, not PATCH. Never bump per commit.
2. **Breaking is independent of type.** `feat!:`, `fix!:`, and a `BREAKING CHANGE:` footer on any type — `chore:` included — all yield MAJOR.

`none` means the range holds nothing release-worthy; it exits 0, and only a non-zero exit is an error. The script shares `conventional-commits-lib.sh` with `changelog-from-git.sh`, so the two cannot disagree about which commits are breaking. Pre-release and build-metadata suffixes are out of scope — apply those by hand.

### Version Bump Rules (reference)

| Change Type | Bump | Before | After |
|-------------|------|--------|-------|
| Breaking API change | MAJOR | 1.2.3 | 2.0.0 |
| New feature (compatible) | MINOR | 1.2.3 | 1.3.0 |
| Bug fix (compatible) | PATCH | 1.2.3 | 1.2.4 |
| Pre-release | Suffix | 2.0.0 | 2.0.0-alpha.1 |

### Breaking Change Detection

Mark the commit itself — `!` after the type or a `BREAKING CHANGE:` footer — so the scripts can see it. A change is BREAKING if it removes a public API, changes a public method's return type, adds a required parameter, changes behavior clients depend on, removes or renames configuration options, or changes a database schema incompatibly.

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

Breaking example:

```
feat!: remove deprecated login endpoint

BREAKING CHANGE: The /api/v1/login endpoint has been removed.
Use /api/v2/auth instead.
```

### Types and Changelog Mapping

Per-commit impact only — the range's bump is the highest severity present, which `scripts/version-bump-from-git.sh` computes.

| Type | Description | Changelog (KCL) | Bump |
|------|-------------|-----------------|------|
| `feat` | New feature | Added | MINOR |
| `feat!` / any type with `BREAKING CHANGE` | Breaking change | Added, `**BREAKING**` prefix | MAJOR |
| `fix` | Bug fix | Fixed | PATCH |
| `refactor` | Code change | Changed | PATCH |
| `perf` | Performance | Changed | PATCH |
| `docs` | Documentation | — (suppressed) | — |
| `style` | Formatting | — (suppressed) | — |
| `test` | Tests | — (suppressed) | — |
| `chore` | Maintenance | — (suppressed) | — |
| `ci` | CI/CD | — (suppressed) | — |
| `build` | Build system | — (suppressed) | — |
| _(non-conventional)_ | — | Other | — |

## Changelog Generation

**Canonical tool**: `scripts/changelog-from-git.sh`

```bash
# From a git range (writes Keep-a-Changelog markdown to stdout)
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" "v1.1.0..HEAD" --version "1.2.0"

# From a pre-fetched capture (untrusted / offline / testable). A file with no
# NUL byte is read one subject per line; otherwise records are NUL-separated
# whole messages, as `git log -z --pretty=format:'%B'` writes them.
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" --file subjects.txt --version "1.2.0"

# Against a specific repo directory
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" "v1.1.0..HEAD" --repo /path/to/repo --version "1.2.0"
```

### Script Classification Behavior

The script classifies all 10 conventional-commit types into the Keep-a-Changelog sections of `§ Types and Changelog Mapping` above. Non-conventional commits are bucketed under "Other" — never dropped. Breaking changes are prefixed with `**BREAKING**`, detected from a `!` suffix or a `BREAKING CHANGE:` footer via the shared `conventional-commits-lib.sh`. Silent types (docs, style, test, chore, ci, build) are suppressed **unless breaking** — a MAJOR release must never ship notes that omit the break. Output is always compact markdown — no large echoes.

The format spec below is retained for the model and for human review; the happy path is the script.

### Keep a Changelog Format (spec / reference)

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.2.0] - 2024-01-15

### Added
- New user dashboard with analytics (#123)

### Changed
- Updated login flow for better security (#156)

### Deprecated
- Legacy API endpoints (removed in 2.0.0)

### Removed
- Support for iOS 14 (#178)

### Fixed
- Crash on large file uploads (#189)

### Security
- Fixed XSS vulnerability in comments (#200)

## [1.1.0] - 2024-01-01
...
```

## Integration Points

- **release-engineer agent**: Uses these patterns for RE stage
- **project-manager**: Uses release artifacts for deployment
- **apple-developer plugin**: iOS/macOS submission coordination
