---
name: milestone-helpers
description: Reusable helper function patterns for milestone worktask operations. Use when implementing milestone workspace initialization, PR detection, or worktree management.
effort: low
related:
  - ../../megatask/SKILL.md
  - ../../../commands/worktask.md
  - ../stage-codes.md
---

# Milestone Helper Functions

Reusable patterns for milestone worktask operations.

## Canonical Dispatcher

**`scripts/milestone-helpers.sh`** is the single executable home for all slug/branch/priority/base-branch logic. Megatask scripts MUST invoke it rather than reimplementing these operations.

```
bash scripts/milestone-helpers.sh <subcommand> [args...]
```

All subcommands accept pre-fetched JSON via `--file` so they are network-free and testable. Run `--self-test` to verify (26 checks, no network required).

### Subcommands

| Subcommand | Invocation | Output |
|---|---|---|
| `branch-name` | `bash milestone-helpers.sh branch-name 42 "Add login flow"` | `feature/42-add-login-flow` |
| `priority-score` | `bash milestone-helpers.sh priority-score P1 bug` | `1` |
| `base-branch` | `bash milestone-helpers.sh base-branch --file issue.json` | `develop` |
| `has-pr` | `bash milestone-helpers.sh has-pr 42 --file timeline.json` | `yes` or `no` |
| `filter-prs` | `bash milestone-helpers.sh filter-prs --file issues.json` | TSV: `<number> <status>` |
| `orchestrator-update` | `bash milestone-helpers.sh orchestrator-update --file in.json --path out.json --issue 42 status=completed` | writes updated JSON atomically |
| `workspace-init` | `bash milestone-helpers.sh workspace-init 42 "Add login flow"` | `branch=…` `worktree_path=…` `context_path=…` key=value lines |

### Slug-length canon: **50 characters**

`implementations.md` previously stated 30 chars; `megatask/SKILL.md §Branch Naming` states 50. The dispatcher implements **50** as the single source of truth. Both files now agree.

> **Constants are canonical in `megatask`** — with one exception: the branch **type** vocabulary (the accepted `<type>` tokens) is canonical in `skills/shared/git-conventions.md § Branch Naming`; `megatask` fixes the type to `feature` and owns only the number-interpolation format (`feature/{issue#}-{slug}`) and the slug cap. Priority labels (P0–P3 + none) and the base-branch resolution chain (issue body → develop → master) stay canonical here in `megatask`. This skill applies them via `scripts/milestone-helpers.sh`; do not redefine — reference the `megatask` skill (or `git-conventions.md` for the type vocabulary) to avoid drift.

## Function Index (pseudocode spec — implemented in scripts/milestone-helpers.sh)

`references/implementations.md` is the **specification** for each function. The dispatcher is the executable implementation — the happy path no longer requires reading the reference file.

| Function | Dispatcher subcommand |
|----------|----------------------|
| `generateBranchName(issue)` | `branch-name` |
| `hasExistingPR(issueNumber)` | `has-pr` |
| `filterIssuesWithPRs(issues)` | `filter-prs` |
| `getPriorityScore(labels)` | `priority-score` |
| `updateOrchestratorIssue(path, number, updates)` | `orchestrator-update` |
| `resolveBaseBranch(issueBody)` | `base-branch` |
| `initializeWorkspace(milestone, issue)` | `workspace-init` (paths only; no side effects) |
| Worktree operations | Not in dispatcher (git commands — run directly per git-integration.md) |

## Git Commands Reference

> **Orchestrator-side only.** The `git -C` forms below run from the **parent** session reaching *into* a worktree. Inside a worktree use plain `git` — the runtime blocks an isolated subagent from redirecting git at the shared checkout (`git -C`, `--git-dir`, `GIT_DIR`, `GIT_WORK_TREE`), so copying these there fails.

| Operation | Non-worktree Command | Worktree Command |
|-----------|----------------|------------------|
| Fetch base | `git fetch origin develop` | `git fetch origin develop` |
| Create branch | `git checkout -b feature/{issue#}-{slug} origin/develop` | `git worktree add -b feature/{issue#}-{slug} .worktrees/milestone-{N}/{issue#} origin/develop` |
| Switch to issue | `git checkout feature/{issue#}-{slug}` | `cd .worktrees/milestone-{N}/{issue#}` (no checkout needed) |
| Stage changes | `git add -A` | `git -C .worktrees/milestone-{N}/{issue#} add -A` |

### Commit, push, PR, cleanup

| Operation | Non-worktree Command | Worktree Command |
|-----------|----------------|------------------|
| Commit | `git commit -m "#{issue} feat: {title}"` | `git -C .worktrees/milestone-{N}/{issue#} commit -m "#{issue} feat: {title}"` |
| Push branch | `git push -u origin feature/{issue#}-{slug}` | `git -C .worktrees/milestone-{N}/{issue#} push -u origin feature/{issue#}-{slug}` |
| Create PR | `gh pr create --base develop --body "Closes #{issue}"` | `gh pr create --base develop --body "Closes #{issue}"` |
| Cleanup | `git checkout develop` | `git worktree remove .worktrees/milestone-{N}/{issue#} && git worktree prune` |
