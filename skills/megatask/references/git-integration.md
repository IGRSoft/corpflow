# Git Integration

> Paths below use `milestone-{N}` as the worktree `<group>` token. In array mode
> (`/megatask --issues …`) the group is `issues-{shortid}` instead; substitute accordingly.

## Workspace Setup

```bash
# Workspace initialization (parallel — each issue gets own worktree)
git fetch origin {base_branch}
git worktree add -b <type>/{issue#}-{slug} \
  .worktrees/milestone-{N}/{issue#} origin/{base_branch}
mkdir -p .worktrees/milestone-{N}/{issue#}/.context

# All git operations use -C flag for worktree path
git -C .worktrees/milestone-{N}/{issue#} add -A
git -C .worktrees/milestone-{N}/{issue#} commit -m "#{issue} feat: {title}"
git -C .worktrees/milestone-{N}/{issue#} push -u origin <type>/{issue#}-{slug}
gh pr create --base {base_branch} --body "Closes #{issue#}"

# Cleanup after PR
git worktree remove .worktrees/milestone-{N}/{issue#}
git worktree prune
```

## Stage Integration

| Stage | Workspace Actions |
|-------|-------------------|
| PL | Read issue from workspace.json, write `<plan_file>` (numbered `planning-N.md` per `skills/worktask/references/pl0-procedure.md § Plan File & Run Index Naming`) |
| DV | Branch checked out, commit to workspace branch |
| FN | Push branch, create PR, signal orchestrator |

Fresh agent context per issue — the orchestrator delegates via Task, each subagent starts clean.

## Worktree Lifecycle

### Creation

| Order | Action |
|-------|--------|
| 1 — before `worktree add` | Append `/workspace.json` and `/.worktrees/` to the git **common dir**'s `info/exclude` (idempotent, exact-line matched) |
| 2 — issue starts (PL) | `worktree add -b {branch}` → `mkdir -p {path}/.context` → write `workspace.json` (`isolation: "worktree"`, `version: "2.0"`) per § Workspace Setup |

The exclusion runs **first** so the scratch file is never visible to a `git add -A`, and it goes in
the common dir because git does not consult a per-worktree `info/exclude` — so, stated rather than
hidden, it covers every worktree of the checkout. It cannot mask a *tracked* file, so a repo that
legitimately tracks a root `workspace.json` still sees its diffs. The repository's own `.gitignore`
is deliberately not touched: that would commit the exclusion to every future branch, the exact
mistake this prevents.

### During Execution

Everything happens inside the worktree: file operations, `.context/` artifacts, builds and tests
(run from that directory), commits (landing on its branch automatically). Git commands issued from
elsewhere take a `git -C {worktree_path}` prefix; `SendMessage` restores the cwd to the correct
worktree when resuming from background.

### Cleanup

| Event | Action |
|-------|--------|
| PR created | `ExitWorktree` then `git worktree remove {path}` (branch persists on remote) |
| Uncommitted changes | Warn user, preserve worktree |
| Failed issue | Preserve worktree for debugging |
| Milestone complete | `git worktree prune` to remove all stale entries |
| PR created (context) | Archive `.context/` to `.context.archive/{timestamp}/`; keep workspace.json + handoff.md |

### Edge Cases

1. **Uncommitted changes**: `removeIssueWorktree()` checks `git status --porcelain` and refuses removal by default; `force=true` overrides.
2. **Failed issues**: worktree preserved with `status: "failed"` in orchestrator — inspect and retry.
3. **Stale worktrees**: interrupted parallel runs are auto-cleaned on startup; manual fallback `git worktree prune`.
4. **Disk space**: each worktree duplicates the working tree — on large repos monitor `du -sh .worktrees/`.

## Conflict Recovery

### Precondition — read this first

This playbook applies **only when the environment refuses destructive git** — auto-mode guards
(`../../shared/git-conventions.md § Auto-mode Git Safety`), a sandbox policy, or a CI runner can
refuse `git merge`, `git reset --hard` and `git push --force`. **This plugin ships no deny list of
its own**, so confirm you are actually being refused first: under a permissive host, resolve in
place on the existing branch.

### The recovery — five ordered steps

Recover by replacing the pull request rather than rewriting the ref behind it.

```bash
WT=.worktrees/milestone-{N}/{issue#}
git -C "$WT" fetch origin {base_branch}
git -C "$WT" rebase origin/{base_branch}         # 1. resolve conflicts locally
# ... resolve, then build + test (see SKILL.md § Conflict Resolution) ...
git -C "$WT" rebase --continue                   # editor-driven: see the commentChar remedy below

git -C "$WT" push -u origin \
  HEAD:refs/heads/<type>/{issue#}-{slug}-rebased # 2. NEW branch name — no force-push needed
gh pr create --base {base_branch} \
  --head <type>/{issue#}-{slug}-rebased \
  --body "Closes #{issue#}"                      # 3. replacement PR
gh pr close {old_pr} \
  --comment "Superseded by #{new_pr} (rebased onto {base_branch})"   # 4. close the superseded PR
gh pr merge {new_pr} --merge                     # 5. merge the replacement
```

#### Why a new branch name

Step 2 is the whole point: pushing a rebased branch under its **original** name requires `--force`,
which is exactly what the host refuses. A new name is an ordinary fast-forward push.

### Why this does not contradict the merge strategy

`../../shared/git-conventions.md § Merge Strategy` requires integration by **merge commit** — never
`--squash`, never `--rebase` — and step 5 obeys it verbatim. Step 1's rebase is a *local* history
operation on an unmerged feature branch before review; the rule governs how a PR is integrated into
the base, not whether a branch may be rebased beforehand. Per-commit boundaries survive the rebase,
so the per-stage history the rule protects arrives intact.

### Two hard rules that apply during step 1

1. **Dependency-injection and coordinator-shaped conflicts are hand-resolved, never
   script-merged** — `../SKILL.md § Conflict Resolution`.
2. **Build and test after any conflict resolution, before pushing.** A mis-joined argument list
   compiles in the reviewer's head and nowhere else.

`rebase --continue` opens an editor, so an issue-prefixed subject (`#{issue#} feat: …`) is silently
destroyed by git's comment-character default — trap and per-invocation remedy stated once in
`../../shared/git-conventions.md § Comment-character trap`; do not restate them here.
