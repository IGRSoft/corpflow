---
name: docs-release-notes
description: Generate release notes from completed work, git history, or worktask artifacts
argument-hint: '[--version <v>] [--from <tag>] [--to <tag|HEAD>] [--from-commits] [--from-worktask] [--format markdown|html|slack] [--audience internal|external|all] [--platform <target>]'
allowed-tools: Read, Glob, Grep, Bash(git log:*)
related:
  - agents/project-manager.md
  - agents/technical-writer.md
  - commands/sprint.md
---

# Release Notes Command

Generate release notes from completed work, git history, or worktask artifacts.

## Options

| Option | Values | Purpose |
|--------|--------|---------|
| `--version <v>` | version string | Version these notes describe |
| `--from <tag>` / `--to <tag\|HEAD>` | git refs | Commit range to read (default: last tag → `HEAD`) |
| `--from-commits` | — | Source content from git commit history |
| `--from-worktask` | — | Source content from worktask artifacts |
| `--format <type>` | `markdown`, `html`, `slack` | Output format (default: `markdown`) |
| `--audience <who>` | `internal`, `external`, `all` | Which template to emit (default: `all`) |
| `--platform <target>` | `apple`, `android`, `web`, `systems`, `backend`, `ai`, `all` | Platform context (default: `all`) |

## Examples

```
/docs-release-notes [--version <v>] [--from <tag>] [--to <tag|HEAD>] [--from-commits] [--from-worktask] [--format markdown|html|slack] [--audience internal|external|all] [--platform <target>]
/docs-release-notes
/docs-release-notes --version 2.1.0 --format markdown
/docs-release-notes --from-commits --audience external
/docs-release-notes --from v2.0.0 --to HEAD --from-worktask --platform apple
```

## Output Format

Markdown by default. `--audience all` emits the external notes first, then the internal notes, separated by `---`.

### External notes

Audience: customers. Benefit-first language; no ticket IDs, PR numbers, or code internals.

| Section | Shape |
|---------|-------|
| Title | `# Release Notes v<version>` plus `**Release Date**` |
| `## Highlights` | 3–5 emoji-led one-liners, each a user-visible benefit |
| `## New Features` | Per feature: H3 name, what the user can now do, capability bullets, and how to enable it |
| `## Improvements` | Bullets shaped `**Area**: measurable change` |
| `## Bug Fixes` | Plain bullets in symptom phrasing ("Fixed an issue where …") |
| `## Known Issues` | Bullets with the workaround inline |
| `## Getting Started` | Numbered steps per newly shipped feature |
| `## Feedback` | Contact channel |

### Internal notes

Audience: engineering and release management. Every claim traceable to a ticket, PR, or config key.

| Section | Shape |
|---------|-------|
| Title | `# Release Notes v<version> (Internal)` plus release date, sprint ID, release manager |
| `## Summary` | `Metric \| Value` — features, improvements, bug fixes, story points, contributors |
| `## Features` | Per ticket: `### <ID>: <title> (<points> pts)` with author, PR, tests, docs, config/design notes |
| `## Technical Changes` | Sub-sections Database, API Changes, Configuration (`Variable \| Required \| Default \| Description`), Dependencies Updated (`old → new` plus removals) |
| `## Deployment Notes` | Numbered Pre-deployment, Post-deployment, and Rollback Plan lists |
| `## Metrics to Monitor` | `Metric \| Baseline \| Target \| Alert Threshold` |
| `## Known Issues` | `ID \| Issue \| Workaround \| Fix ETA` |
| `## Contributors` | `Name — area of contribution` |

### Slack format

```
*🚀 Release v<version> is live!*

*Highlights:*
• <emoji> <benefit one-liner>

*Full release notes:* <link|Release Notes>

cc @engineering @product
```

Highlights mirror the external Highlights section, trimmed to three bullets.
