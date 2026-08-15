# Git Integration

> Paths below use `milestone-{N}` as the worktree `<group>` token. In array mode
> (`/megatask --issues …`) the group is `issues-{shortid}` instead; substitute accordingly.

## Workspace Setup

```bash
# Workspace initialization (parallel — each issue gets own worktree)
git fetch origin {base_branch}
git worktree add -b feature/{issue#}-{slug} \
  .worktrees/milestone-{N}/{issue#} origin/{base_branch}
mkdir -p .worktrees/milestone-{N}/{issue#}/.context

# All git operations use -C flag for worktree path
git -C .worktrees/milestone-{N}/{issue#} add -A
git -C .worktrees/milestone-{N}/{issue#} commit -m "#{issue} feat: {title}"
git -C .worktrees/milestone-{N}/{issue#} push -u origin feature/{issue#}-{slug}
gh pr create --base {base_branch} --body "Closes #{issue#}"

# Cleanup after PR
git worktree remove .worktrees/milestone-{N}/{issue#}
git worktree prune
```

## Stage Integration

| Stage | Workspace Actions |
|-------|-------------------|
| PL | Read issue from workspace.json, write `<plan_file>` (numbered `planning-N.md` per `agents/product-manager.md § Plan File Naming`) |
| DV | Branch checked out, commit to workspace branch |
| FN | Push branch, create PR, signal orchestrator |

## Context Lifecycle

| Event | Action |
|-------|--------|
| PR Created | Archive `.context/` to `.context.archive/{timestamp}/` |
| Issue Complete | Preserve workspace.json and handoff.md |
| Milestone Complete | `git worktree prune` to remove all stale worktree entries |

Fresh agent context per issue - orchestrator delegates via Task tool, each subagent starts clean.

## Worktree Lifecycle

### Creation

| Event | Action |
|-------|--------|
| Issue starts (PL) | `git worktree add -b {branch} {path} origin/{base}` |
| Context setup | `mkdir -p {worktree_path}/.context` |
| Metadata | Write `workspace.json` with `isolation: "worktree"`, `version: "2.0"` |

### During Execution

| Event | Action |
|-------|--------|
| Stage work | All file operations happen inside worktree path |
| Git operations | Use `git -C {worktree_path}` prefix |
| Context path | `{worktree_path}/.context/` |
| Builds/tests | Run from worktree directory |
| Commits | Committed to the worktree's branch automatically |
| Resume from background | SendMessage restores cwd to correct worktree |

### Cleanup

| Event | Action |
|-------|--------|
| PR created | `ExitWorktree` then `git worktree remove {path}` (branch persists on remote) |
| Uncommitted changes | Warn user, preserve worktree |
| Failed issue | Preserve worktree for debugging |
| Milestone complete | `git worktree prune` to remove all stale entries |

### Edge Cases

1. **Uncommitted changes**: `removeIssueWorktree()` checks `git status --porcelain` and refuses removal by default. Pass `force=true` to override.
2. **Failed issues**: Worktree preserved with `status: "failed"` in orchestrator. User can inspect and retry.
3. **Stale worktrees**: Worktrees from interrupted parallel runs are auto-cleaned on startup. Manual fallback: `git worktree prune`.
4. **Disk space**: Each worktree duplicates the working tree. For large repos, monitor with `du -sh .worktrees/`.

## Conflict Recovery

### Precondition — read this first

This playbook applies **only when the environment refuses destructive git**. Some hosts refuse
`git merge`, `git reset --hard` and `git push --force`: auto-mode guards (see
`../../shared/git-conventions.md § Auto-mode Git Safety`), a sandbox permission policy, or a CI
runner's own restrictions. **This plugin ships no deny list of its own** — the refusal belongs to
whatever host the batch runs on, so confirm you are actually being refused before taking this
path. Under a permissive host, resolve in place on the existing branch; the steps below are the
recovery for when you cannot, not the preferred route.

### The recovery — five ordered steps

Recover by replacing the pull request rather than rewriting the ref behind it.

```bash
WT=.worktrees/milestone-{N}/{issue#}
git -C "$WT" fetch origin {base_branch}
git -C "$WT" rebase origin/{base_branch}         # 1. resolve conflicts locally
# ... resolve, then build + test (see SKILL.md § Conflict Resolution) ...
git -C "$WT" rebase --continue                   # editor-driven: see the commentChar remedy below

git -C "$WT" push -u origin \
  HEAD:refs/heads/feature/{issue#}-{slug}-rebased # 2. NEW branch name — no force-push needed
gh pr create --base {base_branch} \
  --head feature/{issue#}-{slug}-rebased \
  --body "Closes #{issue#}"                      # 3. replacement PR
gh pr close {old_pr} \
  --comment "Superseded by #{new_pr} (rebased onto {base_branch})"   # 4. close the superseded PR
gh pr merge {new_pr} --merge                     # 5. merge the replacement
```

#### Why a new branch name

Step 2 is the whole point: pushing a rebased branch under its **original** name requires
`--force`, which is exactly what the host refuses. A new name is an ordinary fast-forward push.

### Why this does not contradict the merge strategy

`../../shared/git-conventions.md § Merge Strategy` requires integration by **merge commit** —
never `--squash`, never `--rebase`. Step 5 obeys it verbatim. The rebase in step 1 is a *local*
history operation on an unmerged feature branch, performed before review; the merge-strategy rule
governs how a PR is integrated into the base, not whether a branch may be rebased beforehand.
Per-commit boundaries survive the rebase, so the per-stage history the rule protects arrives
intact on the base branch.

### Two hard rules that apply during step 1

1. **Dependency-injection and coordinator-shaped conflicts are hand-resolved, never
   script-merged** — `../SKILL.md § Conflict Resolution`.
2. **Build and test after any conflict resolution, before pushing.** A mis-joined argument list
   compiles in the reviewer's head and nowhere else.

`rebase --continue` opens an editor, so an issue-prefixed subject (`#{issue#} feat: …`) is
silently destroyed by git's comment-character default. The trap and its per-invocation remedy are
stated once, in `../../shared/git-conventions.md § Comment-character trap`; do not restate them
here.
