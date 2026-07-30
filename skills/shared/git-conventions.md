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
- Set `attribution.sessionUrl` to omit the claude.ai session link from commits/PRs — keeps the no-AI-footer rule above enforced at the tooling layer

## Git Safety (beyond CC defaults)

- Never push directly to main/master without PR
- Never delete branches without explicit user instruction

### Auto-mode Git Safety

In auto mode the runtime enforces these guards independently of the rules above:

- **Destructive git is blocked unless discard is explicitly requested** — `git reset --hard`, `git checkout -- .`, `git clean -fd`, and `git stash drop` are refused unless the prompt explicitly asks to discard those changes.
- **`commit --amend` is blocked unless the commit was made by the agent this session** — a pre-existing commit cannot be rewritten. This enforces the plugin's existing "prefer new commits over `--amend`" rule with a runtime rationale: after a failed hook the commit did not happen, so amend would destroy prior work.

#### IaC destroy and denial transparency

- **IaC `destroy` is blocked unless the specific stack is named** — a bare `destroy` is refused; the target stack must be specified.
- **Denials are self-explanatory** — auto-mode denial reasons surface in the transcript, the denial toast, and `/permissions` recent denials, so a blocked git guard documents itself in the audit trail. Stricter installs can set `autoMode.classifyAllShell` to route ALL shell commands through the classifier, not just arbitrary-code-execution patterns.

FN-stage commit/cleanup therefore runs under this guard. None of the worktask flows rely on amending a non-agent commit, so the guard is documentation-forward (it reinforces, rather than changes, current behavior).

#### Broadened destructive-removal guards

CC guards destructive removals broadly: auto mode asks before `rm -rf` on an unresolvable variable; catastrophic removals inside `$(…)`/backticks/`<(…)` prompt even under `--dangerously-skip-permissions` and auto mode; and an auto-mode rule blocks tampering with session transcript files. FN-stage cleanup is unaffected — it never expands unresolved variables into `rm` targets.

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

## Merge Strategy

Integrate PRs with a **merge commit** — never squash, never rebase-merge.

```bash
gh pr merge <number> --merge
```

- `--squash` and `--rebase` are forbidden: they collapse or rewrite the branch history that carries per-stage worktask context.
- Individual commit boundaries (one per stage/logical change) must survive on the target branch.
- Keep the auto-generated merge commit subject (`Merge pull request #N from <branch>`); the PR title/body carries the summary.

## Branch Naming

Canonical single source of truth for worktask branch grammar. Every other file
(`agents/product-manager.md`, `agents/project-manager.md`, `skills/worktask/references/*`)
references this section instead of restating the rules.

### Grammar

```
<type>/<slug>
```

No ticket number: the branch carries no issue reference (a worktask branch is named
before any issue-linked commit exists, and the pull request body carries the closing
keyword instead — see `skills/worktask/references/handoff-protocol.md § branch`).

### Type vocabulary (12 tokens, accepted by the already-conventional check)

`feat`, `feature`, `fix`, `refactor`, `perf`, `docs`, `chore`, `test`, `ci`, `build`,
`style`, `revert`. Generated branches use the long form `feature` (never `feat`); `feat`
stays accepted so a pre-existing short-form branch is never churned. The single
machine-readable copy is `BRANCH_TYPES` in `skills/worktask/scripts/branch-lib.sh` — both
the generator (`derive_type`) and the already-conventional predicate
(`branch_is_conventional`) derive from it, so the two cannot drift.

This list is branch-only. Do **not** add `feature` to the commit-type table above —
that would legitimize `feature:` commits, which is out of scope here.

### Guard ladder (every arm is a no-op or a refusal, never a failure)

| Guard | Behaviour |
|---|---|
| Name already conventional | no-op — a deliberate name is never churned |
| Upstream already tracked | no-op — renaming a pushed branch orphans the remote ref |
| On the integration branch | refuses |
| Target name already exists | no-op |
| Detached HEAD / not a repo | skipped |

### Once-only rule

The branch is named exactly once, at the start of the planning stage
(`skills/worktask/scripts/branch-name.sh`), before any commit exists, and never renamed
again. `facts.branch` on the run ledger records the planned name; finalization reads it
from there rather than re-deriving it from a live `git` query.

### Goal text becomes a public, durable branch name

The task description feeds `derive_slug` and survives (truncated, kebab-cased) into the
branch name, an `audit.jsonl` row, and — once pushed — a remote ref and the pull-request
URL. On a public repository that is world-readable and effectively permanent. **Never
put a live credential, secret, or other sensitive value in the task description** — treat
it the same as you would a commit message or a PR title.

## GitHub Issue Types

| Type | Keywords                                  |
|------|-------------------------------------------|
| Bug           | Problems, errors, crashes        |
| Feature       | New functionality, enhancements  |
| Task          | Refactoring, technical debt      |
| Documentation | Missing or incorrect docs        |
| Configuration | Build system, CI/CD, setup       |
