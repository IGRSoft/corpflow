---
name: workflow
description: Complete staged workflow system with dynamic sizing, task initialization, and stage management. Use when executing multi-stage workflows, initializing tasks, or managing workflow state.
---

# Workflow System

Single source of truth for task workflow management using the Task System.

## Workflow Evolution (v2.0)

```
8-stage:  PL → AR → TL → DV → QA → DC → FN → ST
10-stage: PL → AR → TL → DV → SR → QA → DC → RE → FN → ST
                             ↑              ↑
                       Security Review    Release Engineering
```

**Stage codes and triggers**: See `shared/stage-codes.md` and `shared/workflow-triggers.md`

**Task System integration**: See `shared/task-system.md`

## Dynamic Workflow Sizing

Workflows are dynamically sized during PL and AR stages using task deletion.

### Complexity Assessment

| Factor | Low (0-2) | Medium (3-5) | High (6-10) |
|--------|-----------|--------------|-------------|
| **New patterns** | None | 1-2 new | 3+ new |
| **Integration points** | 1-2 | 3-5 | 6+ |
| **Cross-cutting concerns** | None | 1 area | Multiple |
| **Risk level** | Minimal | Moderate | High |
| **Documentation needs** | Inline | README | ADR + API docs |

**Scoring**: Sum factor scores (0-50 total)

### Decision Rules

| Score | Complexity | Resulting Stages |
|-------|------------|------------------|
| 0-10 | Low | PL → DV → QA |
| 11-20 | Medium | PL → AR → DV → QA |
| 21-30 | Moderate | PL → AR → TL → DV → QA |
| 31-40 | High | All 8 stages |
| 41-50 | Critical | All 10 stages (with SR, RE) |

**Security-sensitive features** auto-include SR stage:
- Authentication/authorization, payment processing, PII handling
- Cryptographic operations, external API secrets, file uploads

### Safe Task Deletion

```typescript
// Remove task and update dependents
function deleteTaskSafely(taskId: string) {
  const allTasks = TaskList();
  const dependents = allTasks.filter(t => t.blockedBy?.includes(taskId));
  for (const dep of dependents) {
    TaskUpdate({ taskId: dep.id, removeBlockedBy: [taskId] });
  }
  TaskUpdate({ taskId, status: "deleted" });
}
```

## Workspace Mode

When using `--milestone:N`, each ticket executes in an isolated workspace.

### Workspace Detection

```typescript
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const isolation = task.metadata?.isolation;  // 'worktree' or undefined

if (isolation === 'worktree') {
  // WORKTREE MODE: workspace_path IS the worktree directory
  // All git operations happen inside the worktree
  // .context/ lives inside the worktree alongside source files
  const contextPath = `${workspacePath}/.context`;
} else if (workspacePath) {
  // LEGACY WORKSPACE MODE: directory-based artifact isolation only
  const contextPath = `${workspacePath}/.context`;
} else {
  // STANDARD MODE: project root
  const contextPath = '.context';
}
```

### Path Resolution

| Mode | Base Path | Git Operations | Source Isolation |
|------|-----------|----------------|------------------|
| Standard | `.context/` | Main working directory | None |
| Workspace (legacy) | `.workspaces/milestone-{N}/{issue#}/.context/` | Shared working directory | Artifacts only |
| Worktree | `.worktrees/milestone-{N}/{issue#}/.context/` | Dedicated worktree | Full (git + artifacts) |

### Task ID Namespacing

| Track | Task IDs |
|-------|----------|
| Track 1 | `t1-1`, `t1-2`, ... |
| Track N | `t{N}-1`, `t{N}-2`, ... |

See `milestone-workflow.md` for full workspace documentation.

## Parallel Execution

### W + Q Parallel (Default)

```typescript
TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });  // QA ← DV
TaskUpdate({ taskId: "6", addBlockedBy: ["4"] });  // DC ← DV
TaskUpdate({ taskId: "7", addBlockedBy: ["5", "6"] });  // FN ← QA AND DC
```

Use `--sequential` when DC requires test results.

### Never Parallelize

- AR before PL (needs requirements)
- DV before TL (needs coordination)
- QA before DV (can't test unwritten code)

## Error Handling

### Retry Logic

Each stage: max 3 retries. Track via task metadata or error.md.

### Escalation Chains

```
10-stage: ST → FN → RE → DC → QA → SR → DV → TL → AR → PL → USER
8-stage:  ST → FN → DC → QA → DV → TL → AR → PL → USER
Emergency: FN → RE → QA → DV → IR → USER
```

Document errors in `.context/error.md` with problem, root cause, attempted solutions.

## Rule Checks

| Rule | Required Before |
|------|-----------------|
| Test Strategy | PL → AR |
| Test Architecture | AR → TL |
| Code Format | DV complete |
| Build Pass | DV → QA |
| Unit Tests Written + Pass | DV → QA |
| All Tests Pass (Unit + Integration + E2E) | QA → DC |

## Optimization Hooks

### Pre-Stage

| Check | Threshold | Action |
|-------|-----------|--------|
| Context size | > 50% window (standard) or > 30% (1M window) | Compress previous stages |
| Budget usage | > 75% | Alert user |

### Post-Stage

- Compress context for handoff (50-100 tokens)
- Log token usage in task metadata
- Validate artifacts created
- `PostCompact` hook fires after auto-compaction — use to re-inject critical workflow state

> On Opus 4.6 with Max/Team/Enterprise, context window is 1M tokens. Compression still recommended at stage boundaries for cost efficiency even with larger windows.

See references/ for initialization code, stage details, and agent teams integration.

## Related

- `milestone-workflow.md` - GitHub milestone integration
- `agent-coordination.md` - Multi-agent coordination
- `cost-optimization.md` - Budget management
- `context-compression.md` - Context compression
