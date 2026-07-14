# Milestone Helper Implementations

> **This file is a specification.** The executable implementation lives in
> `scripts/milestone-helpers.sh`. Invoke that script; do not re-implement from this pseudocode.
> Slug max length is **50 characters** (was incorrectly stated as 30 here; resolved in favour of
> `megatask/SKILL.md §Branch Naming` which states 50).

Full TypeScript pseudocode implementations for all milestone helper functions.

## Branch Name Generation

```typescript
function generateBranchName(issue: { number: number; title: string }): string {
  const slug = issue.title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')  // Replace non-alphanumeric with hyphens
    .replace(/^-|-$/g, '')         // Trim leading/trailing hyphens
    .substring(0, 50);             // Max 50 chars for slug (canonical; see scripts/milestone-helpers.sh)

  return `feature/${issue.number}-${slug}`;
}
```

**Examples**:
- `"Add login flow"` → `feature/42-add-login-flow`
- `"Fix: crash on startup!!!"` → `feature/43-fix-crash-on-startup`

## PR Detection

Check if an issue already has a linked PR:

```typescript
function hasExistingPR(issueNumber: number): boolean {
  // Use: gh api /repos/:owner/:repo/issues/{issueNumber}/timeline
  // Filter for cross-referenced events with pull_request source
  const timeline = getIssueTimeline(issueNumber);

  const linkedPRs = timeline.filter(event =>
    event.event === 'cross-referenced' &&
    event.source?.issue?.pull_request
  );

  return linkedPRs.length > 0;
}

function filterIssuesWithPRs(issues: Issue[]): {
  toProcess: Issue[];
  skipped: Issue[];
} {
  const toProcess: Issue[] = [];
  const skipped: Issue[] = [];

  for (const issue of issues) {
    if (hasExistingPR(issue.number)) {
      skipped.push({ ...issue, status: 'skipped_has_pr' });
    } else {
      toProcess.push(issue);
    }
  }

  return { toProcess, skipped };
}
```

## Priority Sorting

```typescript
const PRIORITY_ORDER = {
  'P0': 0, 'priority:critical': 0,
  'P1': 1, 'priority:high': 1,
  'P2': 2, 'priority:medium': 2,
  'P3': 3, 'priority:low': 3,
  'P4': 4, 'priority:backlog': 4
};

function getPriorityScore(labels: string[]): number {
  for (const label of labels) {
    if (label in PRIORITY_ORDER) {
      return PRIORITY_ORDER[label];
    }
  }
  return 99;  // No priority label = lowest
}

function sortByPriority(issues: Issue[]): Issue[] {
  return issues.sort((a, b) =>
    getPriorityScore(a.labels) - getPriorityScore(b.labels)
  );
}
```

## Orchestrator Updates

```typescript
function updateOrchestratorIssue(
  orchestratorPath: string,
  issueNumber: number,
  updates: Partial<IssueState>
): void {
  const orchestrator = JSON.parse(readFile(orchestratorPath));
  const issue = orchestrator.issues.find(i => i.number === issueNumber);

  if (!issue) throw new Error(`Issue ${issueNumber} not found in orchestrator`);

  Object.assign(issue, updates);

  // Update progress counts
  orchestrator.progress = {
    total: orchestrator.issues.length,
    completed: orchestrator.issues.filter(i => i.status === 'completed').length,
    in_progress: orchestrator.issues.filter(i => i.status === 'in_progress').length,
    pending: orchestrator.issues.filter(i => i.status === 'pending').length
  };

  writeFile(orchestratorPath, JSON.stringify(orchestrator, null, 2));
}
```

## Base Branch Resolution

```typescript
function resolveBaseBranch(issueBody: string): { branch: string; source: string } {
  // 1. Check issue body for explicit base branch
  const match = issueBody.match(/base_branch:\s*(\S+)/);
  if (match) {
    return { branch: match[1], source: 'issue_body' };
  }

  // 2. Check if develop exists on remote
  // Use: git ls-remote --heads origin develop
  const developExists = checkRemoteBranchExists('develop');
  if (developExists) {
    return { branch: 'develop', source: 'develop_fallback' };
  }

  // 3. Default to master
  return { branch: 'master', source: 'master_default' };
}
```

## Workspace Initialization Pattern

```typescript
function initializeWorkspace(
  milestoneNumber: number,
  issue: Issue
): WorkspaceState {
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issue.number}`;
  const branchName = generateBranchName(issue);
  const baseBranch = resolveBaseBranch(issue.body);

  // 1. Create worktree with new branch
  // git worktree add -b ${branchName} ${worktreePath} origin/${baseBranch.branch}

  // 2. Create .context/ inside the worktree
  // mkdir -p ${worktreePath}/.context
```

### initializeWorkspace — workspace.json write

```typescript
  // …continued: initializeWorkspace body
  // 3. Write workspace.json inside the worktree
  const workspace = {
    version: '2.0',
    isolation: 'worktree',
    issue: { number: issue.number, title: issue.title, labels: issue.labels },
    git: {
      branch_name: branchName,
      base_branch: baseBranch.branch,
      worktree_path: worktreePath
    },
    worktask: { track: null, task_prefix: null },
    execution: { current_stage: null, retry_count: 0 }
  };

  writeFile(`${worktreePath}/workspace.json`, JSON.stringify(workspace, null, 2));

  return workspace;
}
```

## Issue Completion Pattern

```typescript
function completeIssue(
  milestoneNumber: number,
  issueNumber: number
): void {
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issueNumber}`;
  const workspace = JSON.parse(readFile(`${worktreePath}/workspace.json`));

  // 1. Commit all changes (from inside worktree)
  // git -C ${worktreePath} add -A
  // git -C ${worktreePath} commit -m "#${issueNumber} feat: ${workspace.issue.title}"

  // 2. Push branch
  // git -C ${worktreePath} push -u origin ${workspace.git.branch_name}

  // 3. Create PR
  // gh pr create --base ${workspace.git.base_branch} \
  //   --title "#${issueNumber} ${workspace.issue.title}" \
  //   --body "Closes #${issueNumber}"

  // 4. Update orchestrator
  updateOrchestratorIssue('.worktrees/orchestrator.json', issueNumber, {
    status: 'completed',
    track: null
  });
}
```

## Worktree Operations

Git worktree isolation for milestone worktasks. Requires Claude Code 2.1.51+.

> **Shared configuration (2.1.63+)**: Project configs and auto-memory are automatically shared across all git worktrees of the same repo. No per-worktree configuration duplication needed.

### createIssueWorktree

```typescript
function createIssueWorktree(
  milestoneNumber: number,
  issue: Issue,
  baseBranch: string
): WorkspaceState {
  const branchName = generateBranchName(issue);
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issue.number}`;

  // 1. Fetch latest base
  // git fetch origin ${baseBranch}

  // 2. Create worktree with new branch
  // git worktree add -b ${branchName} ${worktreePath} origin/${baseBranch}

  // 3. Create .context/ inside the worktree
  // mkdir -p ${worktreePath}/.context
```

#### createIssueWorktree — workspace.json write

```typescript
  // …continued: createIssueWorktree body
  // 4. Write workspace.json inside the worktree
  const workspace = {
    version: '2.0',
    isolation: 'worktree',
    issue: { number: issue.number, title: issue.title, labels: issue.labels },
    git: {
      branch_name: branchName,
      base_branch: baseBranch,
      worktree_path: worktreePath
    },
    worktask: { track: null, task_prefix: null },
    execution: { current_stage: null, retry_count: 0 }
  };

  writeFile(`${worktreePath}/workspace.json`, JSON.stringify(workspace, null, 2));
  return workspace;
}
```

### removeIssueWorktree

```typescript
function removeIssueWorktree(
  milestoneNumber: number,
  issueNumber: number,
  force: boolean = false
): { removed: boolean; reason?: string } {
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issueNumber}`;

  // 1. Check for uncommitted changes
  // git -C ${worktreePath} status --porcelain
  const status = execFileNoThrow('git', ['-C', worktreePath, 'status', '--porcelain']);
  if (status.stdout.trim() && !force) {
    return {
      removed: false,
      reason: 'Worktree has uncommitted changes. Use force=true to remove.'
    };
  }

  // 2. Remove the worktree
  const args = ['worktree', 'remove'];
  if (force) args.push('--force');
  args.push(worktreePath);
  // git worktree remove [--force] ${worktreePath}
  execFileNoThrow('git', args);
```

#### removeIssueWorktree — prune and return

```typescript
  // …continued: removeIssueWorktree body
  // 3. Prune stale worktree entries
  // Note: Stale worktrees from interrupted runs are auto-cleaned on startup (2.1.76+)
  // Manual prune as fallback:
  // git worktree prune
  execFileNoThrow('git', ['worktree', 'prune']);

  return { removed: true };
}
```

### createSparseWorktree (2.1.76+)

For large monorepos, use sparse checkout to reduce worktree size:

```typescript
function createSparseWorktree(
  milestoneNumber: number,
  issue: Issue,
  baseBranch: string,
  sparsePaths: string[]  // e.g., ["src/", "tests/", "Package.swift"]
): WorkspaceState {
  const branchName = generateBranchName(issue);
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issue.number}`;

  // 1. Create worktree
  // git worktree add -b ${branchName} ${worktreePath} origin/${baseBranch}

  // 2. Enable sparse checkout (2.1.76+)
  // git -C ${worktreePath} sparse-checkout init --cone
  // git -C ${worktreePath} sparse-checkout set ${sparsePaths.join(' ')}

  // 3. Create .context/ inside worktree
  // mkdir -p ${worktreePath}/.context
```

#### createSparseWorktree — workspace.json write

```typescript
  // …continued: createSparseWorktree body
  // 4. Write workspace.json (same as createIssueWorktree)
  const workspace = {
    version: '2.0',
    isolation: 'worktree',
    sparse_paths: sparsePaths,
    issue: { number: issue.number, title: issue.title, labels: issue.labels },
    git: { branch_name: branchName, base_branch: baseBranch, worktree_path: worktreePath },
    worktask: { track: null, task_prefix: null },
    execution: { current_stage: null, retry_count: 0 }
  };

  writeFile(`${worktreePath}/workspace.json`, JSON.stringify(workspace, null, 2));
  return workspace;
}
```

### listMilestoneWorktrees

```typescript
function listMilestoneWorktrees(milestoneNumber: number): WorktreeInfo[] {
  // git worktree list --porcelain
  const output = execFileNoThrow('git', ['worktree', 'list', '--porcelain']);
  return parseWorktreeList(output.stdout)
    .filter(wt => wt.path.includes(`.worktrees/milestone-${milestoneNumber}/`));
}
```

### resolveIssueWorkdir

Key abstraction that allows all code to work transparently in both modes.

```typescript
function resolveIssueWorkdir(
  milestoneNumber: number,
  issueNumber: number,
  options: WorktaskOptions
): { workdir: string; contextPath: string; isWorktree: boolean } {
  if (options.worktree) {
    const workdir = `.worktrees/milestone-${milestoneNumber}/${issueNumber}`;
    return {
      workdir,
      contextPath: `${workdir}/.context`,
      isWorktree: true
    };
  }
  // Fallback: should not be reached — isolation is always 'worktree'.
  // Treat as worktree at repo root for safety.
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issueNumber}`;
  return {
    workdir: worktreePath,
    contextPath: `${worktreePath}/.context`,
    isWorktree: true
  };
}
```

### completeIssueWorktree

```typescript
function completeIssueWorktree(
  milestoneNumber: number,
  issueNumber: number
): void {
  const worktreePath = `.worktrees/milestone-${milestoneNumber}/${issueNumber}`;
  const workspace = JSON.parse(readFile(`${worktreePath}/workspace.json`));

  // 1. Commit all changes (inside worktree)
  // git -C ${worktreePath} add -A
  // git -C ${worktreePath} commit -m "#${issueNumber} feat: ${workspace.issue.title}"

  // 2. Push branch (from worktree)
  // git -C ${worktreePath} push -u origin ${workspace.git.branch_name}

  // 3. Create PR
  // gh pr create --base ${workspace.git.base_branch} \
  //   --title "#${issueNumber} ${workspace.issue.title}" \
  //   --body "Closes #${issueNumber}"
```

#### completeIssueWorktree — orchestrator update and cleanup

```typescript
  // …continued: completeIssueWorktree body
  // 4. Update orchestrator (in main repo root)
  updateOrchestratorIssue('.worktrees/orchestrator.json', issueNumber, {
    status: 'completed',
    track: null
  });

  // 5. Exit worktree context (2.1.72+)
  // If EnterWorktree was used, call ExitWorktree tool before removal

  // 6. Remove worktree (branch persists on remote)
  // Note: Stale worktrees from interrupted runs are auto-cleaned on startup (2.1.76+)
  removeIssueWorktree(milestoneNumber, issueNumber);
}
```
