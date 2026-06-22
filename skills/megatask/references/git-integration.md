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
