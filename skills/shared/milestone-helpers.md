# Milestone Helper Functions

Reusable patterns for milestone workflow operations.

> **Note**: Code examples below are pseudocode for conceptual clarity.
> In production, use secure command execution (e.g., `execFile` instead of shell).

## Branch Name Generation

```typescript
function generateBranchName(issue: { number: number; title: string }): string {
  const slug = issue.title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')  // Replace non-alphanumeric with hyphens
    .replace(/^-|-$/g, '')         // Trim leading/trailing hyphens
    .substring(0, 30);             // Max 30 chars for slug

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
  const workspacePath = `.workspaces/milestone-${milestoneNumber}/${issue.number}`;
  const branchName = generateBranchName(issue);
  const baseBranch = resolveBaseBranch(issue.body);

  // 1. Create directory structure
  // mkdir -p ${workspacePath}/.context

  // 2. Create branch from base (CRITICAL: checkout base first)
  // git checkout ${baseBranch.branch}
  // git checkout -b ${branchName}

  // 3. Write workspace.json
  const workspace = {
    version: '1.0',
    issue: { number: issue.number, title: issue.title, labels: issue.labels },
    git: { branch_name: branchName, base_branch: baseBranch.branch },
    workflow: { track: null, task_prefix: null },
    execution: { current_stage: null, retry_count: 0 }
  };

  writeFile(`${workspacePath}/workspace.json`, JSON.stringify(workspace, null, 2));

  return workspace;
}
```

## Issue Completion Pattern

```typescript
function completeIssue(
  milestoneNumber: number,
  issueNumber: number
): void {
  const workspacePath = `.workspaces/milestone-${milestoneNumber}/${issueNumber}`;
  const workspace = JSON.parse(readFile(`${workspacePath}/workspace.json`));

  // 1. Commit all changes
  // git add -A
  // git commit -m "#${issueNumber} feat: ${workspace.issue.title}"

  // 2. Push branch
  // git push -u origin ${workspace.git.branch_name}

  // 3. Create PR
  // gh pr create --base ${workspace.git.base_branch} \
  //   --title "#${issueNumber} ${workspace.issue.title}" \
  //   --body "Closes #${issueNumber}"

  // 4. Update orchestrator
  updateOrchestratorIssue('.workspaces/orchestrator.json', issueNumber, {
    status: 'completed',
    track: null
  });
}
```

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

## Worktree Operations

Git worktree isolation for milestone workflows. Requires Claude Code 2.1.51+ and `--worktree` flag.

> **When to use**: `--worktree` enables true parallel issue execution by giving each issue its own working directory and branch. Without it, issues share a single worktree and must be processed sequentially via `git checkout`.

> **Shared configuration (2.1.63+)**: Project configs and auto-memory are automatically shared across all git worktrees of the same repo. No per-worktree configuration duplication needed.

### isWorktreeEnabled

```typescript
function isWorktreeEnabled(options: WorkflowOptions): boolean {
  if (!options.worktree) return false;

  // Verify git supports worktrees (git 2.5+)
  // Use: git worktree list --porcelain
  const result = execFileNoThrow('git', ['worktree', 'list', '--porcelain']);
  return result.status === 0;
}
```

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
    workflow: { track: null, task_prefix: null },
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

  // 4. Write workspace.json (same as createIssueWorktree)
  const workspace = {
    version: '2.0',
    isolation: 'worktree',
    sparse_paths: sparsePaths,
    issue: { number: issue.number, title: issue.title, labels: issue.labels },
    git: { branch_name: branchName, base_branch: baseBranch, worktree_path: worktreePath },
    workflow: { track: null, task_prefix: null },
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
  options: WorkflowOptions
): { workdir: string; contextPath: string; isWorktree: boolean } {
  if (options.worktree) {
    const workdir = `.worktrees/milestone-${milestoneNumber}/${issueNumber}`;
    return {
      workdir,
      contextPath: `${workdir}/.context`,
      isWorktree: true
    };
  }
  // Legacy: all issues share the main repo working directory
  const workdir = '.';
  return {
    workdir,
    contextPath: `.workspaces/milestone-${milestoneNumber}/${issueNumber}/.context`,
    isWorktree: false
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

## Related

- `milestone-workflow.md` - Full workflow documentation
- `workflow.md` - Core workflow system
- `stage-codes.md` - Stage code reference
