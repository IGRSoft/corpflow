---
name: milestone-helpers
description: Reusable helper function patterns for milestone workflow operations. Use when implementing milestone workspace initialization, PR detection, or worktree management.
---

# Milestone Helper Functions

Reusable patterns for milestone workflow operations.

> **Note**: Code examples below are pseudocode for conceptual clarity.
> In production, use secure command execution (e.g., `execFile` instead of shell).

## Function Index

| Function | Purpose |
|----------|---------|
| `generateBranchName(issue)` | Create `feature/{issue#}-{slug}` branch names |
| `hasExistingPR(issueNumber)` | Check if issue already has linked PR via timeline |
| `filterIssuesWithPRs(issues)` | Split issues into toProcess/skipped arrays |
| `getPriorityScore(labels)` / `sortByPriority(issues)` | Sort issues by P0-P4 labels |
| `updateOrchestratorIssue(path, number, updates)` | Update issue state in orchestrator.json |
| `resolveBaseBranch(issueBody)` | Resolve base branch: issue body → develop → master |
| `initializeWorkspace(milestone, issue)` | Create legacy workspace with .context/ |
| `completeIssue(milestone, issueNumber)` | Commit, push, create PR, update orchestrator |
| `isWorktreeEnabled(options)` | Check if git worktree support is available |
| `createIssueWorktree(milestone, issue, baseBranch)` | Create worktree with branch and .context/ |
| `removeIssueWorktree(milestone, issueNumber, force?)` | Remove worktree with uncommitted change check |
| `createSparseWorktree(milestone, issue, baseBranch, sparsePaths)` | Create worktree with sparse checkout |
| `listMilestoneWorktrees(milestoneNumber)` | List all worktrees for a milestone |
| `resolveIssueWorkdir(milestone, issueNumber, options)` | Abstract workdir path for legacy/worktree modes |
| `completeIssueWorktree(milestone, issueNumber)` | Complete issue workflow in worktree mode |

See references/ for full implementations with code examples.

## Git Commands Reference

| Operation | Legacy Command | Worktree Command |
|-----------|----------------|------------------|
| Fetch base | `git fetch origin develop` | `git fetch origin develop` |
| Create branch | `git checkout -b feature/{issue#}-{slug} origin/develop` | `git worktree add -b feature/{issue#}-{slug} .worktrees/milestone-{N}/{issue#} origin/develop` |
| Switch to issue | `git checkout feature/{issue#}-{slug}` | `cd .worktrees/milestone-{N}/{issue#}` (no checkout needed) |
| Stage changes | `git add -A` | `git -C .worktrees/milestone-{N}/{issue#} add -A` |
| Commit | `git commit -m "#{issue} feat: {title}"` | `git -C .worktrees/milestone-{N}/{issue#} commit -m "#{issue} feat: {title}"` |
| Push branch | `git push -u origin feature/{issue#}-{slug}` | `git -C .worktrees/milestone-{N}/{issue#} push -u origin feature/{issue#}-{slug}` |
| Create PR | `gh pr create --base develop --body "Closes #{issue}"` | `gh pr create --base develop --body "Closes #{issue}"` |
| Cleanup | `git checkout develop` | `git worktree remove .worktrees/milestone-{N}/{issue#} && git worktree prune` |

## Related

- `milestone-workflow.md` - Full workflow documentation
- `workflow.md` - Core workflow system
- `stage-codes.md` - Stage code reference
