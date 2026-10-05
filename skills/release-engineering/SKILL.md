---
name: release-engineering
description: Use when preparing releases, generating changelogs, or checking deployment readiness. Semantic versioning from conventional commits, Keep-a-Changelog generation, and rollback plans for the RE stage.
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

1. **Highest severity wins across the range.** 3 × `fix:` plus 1 × `feat:` is MINOR, not PATCH; bump the range, not each commit.
2. **Breaking is independent of type.** `feat!:`, `fix!:`, and a `BREAKING CHANGE:` footer on any type, `chore:` included, all yield MAJOR.

`none` means the range holds nothing release-worthy; it exits 0, and only a non-zero exit is an error. Both scripts detect breaking changes through the shared `conventional-commits-lib.sh`, so they agree. Pre-release and build-metadata suffixes are out of scope — apply those by hand.

### Version Bump Rules (reference)

| Change Type | Bump | Before | After |
|-------------|------|--------|-------|
| Breaking API change | MAJOR | 1.2.3 | 2.0.0 |
| New feature (compatible) | MINOR | 1.2.3 | 1.3.0 |
| Bug fix (compatible) | PATCH | 1.2.3 | 1.2.4 |
| Pre-release | Suffix | 2.0.0 | 2.0.0-alpha.1 |

### Breaking Change Detection

Mark the commit itself — `!` after the type or a `BREAKING CHANGE:` footer — so the scripts can see it. A change is breaking if it removes a public API, changes a public method's return type, adds a required parameter, changes behavior clients depend on, removes or renames configuration options, or changes a database schema incompatibly.

### Pre-release Labels

| Label | Use Case |
|-------|----------|
| `-alpha.N` | Internal testing, unstable |
| `-beta.N` | External testing, feature complete |
| `-rc.N` | Release candidate, production ready |

## Conventional Commits

### Types and Changelog Mapping

Per-commit impact; the range takes the highest.

| Type | Description | Changelog (KCL) | Bump |
|------|-------------|-----------------|------|
| `feat` | New feature | Added | MINOR |
| `fix` | Bug fix | Fixed | PATCH |
| `refactor` | Code change | Changed | PATCH |
| `perf` | Performance | Changed | PATCH |
| `docs` | Documentation | — (suppressed) | — |
| `style` | Formatting | — (suppressed) | — |
| `test` | Tests | — (suppressed) | — |
| `chore` | Maintenance | — (suppressed) | — |
| `ci` | CI/CD | — (suppressed) | — |
| `build` | Build system | — (suppressed) | — |
| any type + `!` or `BREAKING CHANGE:` | Breaking change | Its type's section, `**BREAKING**` prefix; suppressed types go to Changed | MAJOR |
| _(non-conventional)_ | — | Other | — |

A breaking commit is never suppressed, so a MAJOR release always names the break.

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

# From per-stream entries instead of commits (work still uncommitted in its DV trees)
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" --streams entries.tsv --version "1.2.0"
```

### Output shape

One `## [<version>] - <date>` block (`## [Unreleased]` without `--version`), then a
`### <Section>` per non-empty section in Keep-a-Changelog order: Added, Changed, Deprecated,
Removed, Fixed, Security, Other.

### Stream entries

- `--streams <tsv>` reads one `<stream><TAB><entry>` line per entry and renders `### <stream>` then
  `#### <Section>` blocks, streams in first-seen order. Each entry goes through the same
  conventional-commit parser as a commit subject, so `feat: …` lands in Added and a
  non-conventional entry in Other. It excludes a git range and `--file`.
- A stream name outside `^[a-z0-9]+(-[a-z0-9]+)*$` or over 40 characters, or a line with no TAB,
  exits 1.
- The RE stage's use of streams and tags (empty commit range, `metadata.release_tag`):
  `agents/release-engineer.md § Empty commit range` and `§ Release tag`.

### Tag line

`--tag <name>` adds a ``Tag: `<name>` `` line under the section header in every input mode; an empty
value adds nothing, and a value outside `[A-Za-z0-9._/+-]` exits 1. Pass the ledger's tag, so no tag
is named unless one was set:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/changelog-from-git.sh" "v1.1.0..HEAD" --version "1.2.0" --tag "$(jq -r '.metadata.release_tag // empty' .context/state.json)"
```
