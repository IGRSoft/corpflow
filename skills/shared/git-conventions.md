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

## Test plan
- [How this was verified]

## Visual evidence
[UI runs only — inserted verbatim from `attach-visual-evidence.sh --emit pr`]

## Notes
[Additional context, testing instructions, etc.]

Closes #<N>
```

`Test plan` and the `Closes #<N>` trailer are **required**, not optional: `fn-preflight.sh`
blocks a body without a `Test plan` heading, and `pr-body-lint.sh` reports a missing closing
keyword. `Visual evidence` appears only on runs that captured screenshots. Listing them here
so the three enforcement points and this spec agree on one shape.

**Never paste a local path into a PR body** — `.context/`, `/Users/…`, `~/…` and `../…` are
per-workspace and gitignored, so they are meaningless to a reviewer and leak host layout. This
holds inside backticks too: a code span is not an escape hatch. `pr-body-lint.sh` checks it.

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
<type>/[<ticket>-]<slug>
```

The ticket segment is **optional**, and both shapes are equally conventional —
`bugfix/ov-156-reconstruction-scan-flow` and `feature/add-dark-mode` alike.
`branch_is_conventional` accepts both, so adopting the ticket segment never turns an
existing branch non-conventional and never churns it.

#### Ticket derivation

The ticket is read from the **goal text only** — the first `\b[A-Z]{2,}-\d+\b` token,
lowercased (`derive_ticket` in `skills/worktask/scripts/branch-lib.sh`). No issue lookup
happens: the branch is named before any issue-linked commit exists. A goal carrying no
such key produces the ticket-less shape, which is the unchanged prior behaviour. The key
is stripped from the slug body so it appears exactly once in the branch name, and its
length is budgeted **inside** the 48-character cap (see § Slug budget).

#### Ticket vs. the PR closing keyword — complementary, not alternatives

A ticket in the branch name does **not** replace the closing keyword in the pull-request
body, and the closing keyword does not make the ticket segment redundant. The branch
segment is a human-readable locator carried by every ref, log line, and PR URL; the
closing keyword is the machine-actionable link that actually closes the issue on merge
(see `skills/worktask/references/handoff-protocol.md § branch`). Emit both when the goal
supplies a key.

#### Slug budget

`<ticket>-<slug>` fits within 48 characters. Truncation drops the trailing **partial**
segment rather than cutting mid-word — `bugfix/ov-164-…-blinking-before`, never
`…-blinking-before-r`. At least one whole word always survives, even a word longer than
the remaining budget, so a long issue key can never starve the slug to nothing.

### Type vocabulary (13 tokens, accepted by the already-conventional check)

`feat`, `feature`, `bugfix`, `hotfix`, `refactor`, `perf`, `docs`, `chore`, `test`, `ci`,
`build`, `style`, `revert`. **No `fix`** — removed cleanly, not kept as a compatibility
token; a pre-existing `fix/<slug>` branch is treated as non-conventional and renamed
onto the derived `bugfix/`/`hotfix/` target. Generated branches use the long form
`feature` (never `feat`); `feat` and `style` stay accepted so a pre-existing short-form
or style branch is never churned, but neither is ever generated. The single
machine-readable copy is `BRANCH_TYPES` in `skills/worktask/scripts/branch-lib.sh` — both
the generator (`derive_type`) and the already-conventional predicate
(`branch_is_conventional`) derive from it, so the two cannot drift.

This list is branch-only. Do **not** add `feature` to the commit-type table above —
that would legitimize `feature:` commits, which is out of scope here.

#### Type derivation

`derive_type` matches `fix` as a **word** (start, end, or surrounded by punctuation) —
"…investigate and fix" and "…and fix." are bug reports, while `prefix`/`fixture` are not
— and additionally recognises the defect vocabulary `blink`, `flicker`, `glitch`,
`broken`, `regression`, `incorrect`, `wrong`, `fails`, `failing` for reports that never
use the word "fix" at all. `hotfix` is tested before all of them, since it contains
`fix` itself.

### Conventionality is a predicate, never a judgement (BINDING)

The **sole** authority on whether a branch name is conventional is
`branch_is_conventional()` in `skills/worktask/scripts/branch-lib.sh` (queryable as
`branch-name.sh --check <name>`). No agent, orchestrator, or reviewer may decide by eye
that a name "looks conventional" and skip the naming step on that basis — that judgement
is exactly how a `fix/<slug>` branch survived after `fix` was removed from the
vocabulary. A plausible-looking name is not a checked name.

### Guard ladder (every arm is a no-op or a refusal, never a failure)

Two names come back from every run: `branch=` is the LOCAL branch after it (the final
stdout line), `target_branch=` is what the **remote** branch — the PR head — should carry.
Blocking the local rename never blocks the target.

| Guard | Local branch | `target_branch=` |
|---|---|---|
| Name already conventional | no-op — a deliberate name is never churned | empty — `branch=` is the answer |
| Upstream already tracked | no-op — a rename orphans the remote ref | derived |
| On the integration branch | refuses | empty — never a PR head |
| Target name already exists | no-op | derived |
| Host workspace (linked worktree) | no rename — the host's name is kept | derived |
| Detached HEAD / not a repo | skipped | empty |

The host-workspace arm keeps a host's branch↔workspace mapping intact while the PR still
gets a conventional head — `workspace-modes.md § Host mapping — handled, not just noted`.

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
