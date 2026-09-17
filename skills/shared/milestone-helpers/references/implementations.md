# Milestone Helper Implementations

> **This file is a specification.** The executable implementation lives in
> `scripts/milestone-helpers.sh`. Invoke that script; do not re-implement from this pseudocode.
> Slug max length is **50 characters**.

## Branch Name Generation

`type` is derived by `branch-lib.sh`'s `derive_type` (sourced, never re-implemented); the
pseudocode covers the slug only.

```typescript
function generateBranchName(issue: { number: number; title: string }, type: string): string {
  const body = issue.title
    .replace(/\n/g, ' ').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')   // non-alphanumeric → hyphen
    .replace(/^-+|-+$/g, '');      // trim leading/trailing hyphens
  return capSlug(body, type, issue.number);
}
```

### Slug capping

```typescript
function capSlug(body: string, type: string, number: number): string {
  // Cap at 50, dropping the trailing PARTIAL word; one whole word always survives.
  let slug = body;
  if (body.length > 50) {
    slug = body[50] === '-' ? body.slice(0, 50) : body.slice(0, 50).replace(/-[^-]*$/, '');
    if (!slug.includes('-')) slug = body.split('-')[0];
  }
  return `${type}/${number}-${slug}`;
}
```

**Examples**: `"Add login flow"` → `feature/42-add-login-flow`; `"Fix: crash on startup!!!"` →
`bugfix/43-fix-crash-on-startup`; `"Build multiplatform leaderboard"` →
`feat/7-build-multiplatform-leaderboard`; `"Fix the reconstruction scan flow blinking before the first
frame renders"` → `bugfix/164-fix-the-reconstruction-scan-flow-blinking-before` (word boundary,
not `…-before-t`).

## PR Detection

```typescript
function hasExistingPR(issueNumber: number): boolean {
  // gh api /repos/:owner/:repo/issues/{issueNumber}/timeline
  return getIssueTimeline(issueNumber).some(event =>
    event.event === 'cross-referenced' && event.source?.issue?.pull_request);
}

// Partition: issues with a linked PR are skipped, tagged status 'skipped_has_pr'.
function filterIssuesWithPRs(issues: Issue[]): { toProcess: Issue[]; skipped: Issue[] } {
  return {
    toProcess: issues.filter(i => !hasExistingPR(i.number)),
    skipped: issues.filter(i => hasExistingPR(i.number))
                   .map(i => ({ ...i, status: 'skipped_has_pr' }))
  };
}
```

## Priority Sorting

Sort ascending by score; no priority label scores 99 (last).

```typescript
const PRIORITY_ORDER = {
  'P0': 0, 'priority:critical': 0,
  'P1': 1, 'priority:high': 1,
  'P2': 2, 'priority:medium': 2,
  'P3': 3, 'priority:low': 3,
  'P4': 4, 'priority:backlog': 4
};

function getPriorityScore(labels: string[]): number {
  for (const label of labels) if (label in PRIORITY_ORDER) return PRIORITY_ORDER[label];
  return 99;
}
```

## Orchestrator Updates

```typescript
function updateOrchestratorIssue(
  orchestratorPath: string, issueNumber: number, updates: Partial<IssueState>
): void {
  const orchestrator = JSON.parse(readFile(orchestratorPath));
  const issue = orchestrator.issues.find(i => i.number === issueNumber);
  if (!issue) throw new Error(`Issue ${issueNumber} not found in orchestrator`);
  Object.assign(issue, updates);

  const count = (s) => orchestrator.issues.filter(i => i.status === s).length;
  orchestrator.progress = {
    total: orchestrator.issues.length,
    completed: count('completed'),
    in_progress: count('in_progress'),
    pending: count('pending')
  };
  writeFile(orchestratorPath, JSON.stringify(orchestrator, null, 2));
}
```

## Base Branch Resolution

```typescript
function resolveBaseBranch(issueBody: string): { branch: string; source: string } {
  // 1. Explicit base branch in the issue body
  const match = issueBody.match(/base_branch:\s*(\S+)/);
  if (match) return { branch: match[1], source: 'issue_body' };
  // 2. develop, if it exists on the remote (git ls-remote --heads origin develop)
  if (checkRemoteBranchExists('develop')) return { branch: 'develop', source: 'develop_fallback' };
  // 3. Default
  return { branch: 'master', source: 'master_default' };
}
```

## Worktree Operations

Git worktree isolation for milestone worktasks. `worktreePath` is always
`.worktrees/milestone-${milestoneNumber}/${issueNumber}`.

> **Shared configuration**: project configs and auto-memory are automatically shared across all git
> worktrees of the same repo. No per-worktree configuration duplication needed.

### workspace.json — canonical shape

Written inside the worktree by every create path; `sparse_paths` is present only for sparse
checkouts.

```typescript
const workspace = {
  version: '2.0',
  isolation: 'worktree',
  sparse_paths: sparsePaths,   // createSparseWorktree only
  issue: { number: issue.number, title: issue.title, labels: issue.labels },
  git: { branch_name: branchName, base_branch: baseBranch, worktree_path: worktreePath },
  worktask: { track: null },
  execution: { current_stage: null, retry_count: 0 }
};
writeFile(`${worktreePath}/workspace.json`, JSON.stringify(workspace, null, 2));
```

### initializeWorkspace / createIssueWorktree

Same procedure — `initializeWorkspace` resolves the base branch itself via
`resolveBaseBranch(issue.body)`, `createIssueWorktree` takes it as an argument. Both return the
`workspace` object.

1. `git fetch origin ${baseBranch}`
2. `git worktree add -b ${branchName} ${worktreePath} origin/${baseBranch}` (branch from
   `generateBranchName(issue)`)
3. `mkdir -p ${worktreePath}/.context`
4. Write `workspace.json` (shape above)

### createSparseWorktree

For large monorepos, reduce worktree size with a sparse checkout: the steps above plus, between
worktree creation and `.context/`, `git -C ${worktreePath} sparse-checkout init --cone` and
`sparse-checkout set ${sparsePaths.join(' ')}` (e.g. `["src/", "tests/", "Package.swift"]`), and
record `sparse_paths` in `workspace.json`.

### removeIssueWorktree

```typescript
function removeIssueWorktree(
  milestoneNumber: number, issueNumber: number, force: boolean = false
): { removed: boolean; reason?: string } {
  // 1. Refuse on uncommitted changes unless forced
  const status = execFileNoThrow('git', ['-C', worktreePath, 'status', '--porcelain']);
  if (status.stdout.trim() && !force) {
    return { removed: false, reason: 'Worktree has uncommitted changes. Use force=true to remove.' };
  }
  // 2. git worktree remove [--force] ${worktreePath}
  const args = ['worktree', 'remove', ...(force ? ['--force'] : []), worktreePath];
  execFileNoThrow('git', args);
  // 3. Prune stale entries (interrupted runs are also auto-cleaned on startup)
  execFileNoThrow('git', ['worktree', 'prune']);
  return { removed: true };
}
```

### listMilestoneWorktrees

Parse `git worktree list --porcelain` and keep entries whose path contains
`.worktrees/milestone-${milestoneNumber}/`.

### resolveIssueWorkdir

Returns `{ workdir, contextPath, isWorktree }` — `workdir` is `worktreePath`, `contextPath` is
that path plus `/.context`, `isWorktree` is always `true`. Isolation is always `'worktree'`, so
the non-worktree branch is unreachable and is treated as a worktree for safety.

### completeIssue / completeIssueWorktree

Reads `${worktreePath}/workspace.json`, then:

1. `git -C ${worktreePath} add -A` and
   `commit -m "#${issueNumber} feat: ${workspace.issue.title}"`
2. `git -C ${worktreePath} push -u origin ${workspace.git.branch_name}`
3. `gh pr create --base ${workspace.git.base_branch} --title "#${issueNumber}
   ${workspace.issue.title}" --body "Closes #${issueNumber}"`
4. `updateOrchestratorIssue('.worktrees/orchestrator.json', issueNumber, { status: 'completed',
   track: null })` — the orchestrator file lives in the main repo root
5. Exit the worktree context (`ExitWorktree` if `EnterWorktree` was used), then
   `removeIssueWorktree(milestoneNumber, issueNumber)` — the branch persists on the remote
