---
name: workflow
description: Complete staged workflow system with dynamic sizing, task initialization, and stage management. Use when executing multi-stage workflows, initializing tasks, or managing workflow state.
effort: high
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

**Stage codes and triggers**: See `${CLAUDE_SKILL_DIR}/../shared/stage-codes.md` and `${CLAUDE_SKILL_DIR}/../shared/workflow-triggers.md`

**Task System integration**: See `${CLAUDE_SKILL_DIR}/../shared/task-system.md`

## Dynamic Workflow Sizing

PL0 assesses complexity and creates only the stages needed. No pre-creation or deletion — PL builds the task list from scratch.

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

| Score | Complexity | PL0 Creates |
|-------|------------|-------------|
| 0-10 | Low | DV0, QA0 |
| 11-20 | Medium | AR0, DV0, QA0 |
| 21-30 | Moderate | AR0, TL0, DV0, QA0 |
| 31-40 | High | AR0, TL0, DV0, QA0, DC0, FN0, ST0 |
| 41-50 | Critical | AR0, TL0, DV0, SR0, QA0, DC0, RE0, FN0, ST0 |

**Security-sensitive features** auto-include SR0:
- Authentication/authorization, payment processing, PII handling
- Cryptographic operations, external API secrets, file uploads

Each task includes `metadata.agent` for executor resolution. See `initialization-patterns.md § PL Creates Subsequent Tasks`.

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

## Pre-Stage Validation

Before executing any workflow stage, the orchestrator MUST validate:

1. **TaskList check**: Call `TaskList()` and verify at least one task exists with `metadata.workflow_id` matching the current workflow
2. **PL0 exists**: Verify a task with subject starting with `PL0:` exists
3. **Stage tasks exist**: After PL0 completes, verify PL0 created subsequent stage tasks (at minimum DV0 and QA0 for any complexity level)

If validation fails:
- No tasks exist → Workflow not initialized. Re-run initialization (TaskCreate PL0)
- PL0 exists but no subsequent tasks → PL0 did not complete properly. Re-run PL0
- Tasks exist but are orphaned (no workflow_id) → Log warning and attempt to match by subject pattern

## Orchestrator Execution Loop

### PRECONDITION CHECK
Before entering this loop, verify:
- PL0 task status is "completed"
- The HUMAN USER has sent an explicit approval message
- PL0 completion alone is NOT approval — only human input counts
If the user has not approved, DO NOT enter this loop.

After PL0 completes and creates stage tasks, the orchestrator MUST:

1. **Present PL0 results** to the user: complexity score, stages created (with agents), dependency chain, and key planning decisions
2. **STOP IMMEDIATELY**. PL0 completing is NOT approval. The product-manager returning results is NOT approval. Only the HUMAN USER typing approval in chat counts. Do NOT call Write, Edit, Task, or Bash with any file-modifying commands. STOP generating your response entirely.
3. **Wait for EXPLICIT user approval**. The user must say "approve", "proceed", "go ahead", "looks good", "yes", or similar affirmative. Silence is NOT approval. Asking a question is NOT approval.
4. The user may adjust stages, re-prioritize, or skip stages before approving
5. Only after the user explicitly confirms, execute the stage loop below:

Unless `--auto-continue` flag was provided — in that case, skip the approval gate and proceed directly.

```typescript
// 1. Get all tasks for this workflow
let tasks = TaskList();

// 2. Loop until all tasks are completed
while (tasks.some(t => t.status !== "completed")) {
  // 3. Find unblocked pending tasks
  const ready = tasks.filter(t =>
    t.status === "pending" &&
    (t.blockedBy ?? []).every(dep => tasks.find(d => d.id === dep)?.status === "completed")
  );

  for (const task of ready) {
    // 4. Get full task details
    const full = TaskGet({ taskId: task.id });
    const agentType = full.metadata.agent;
    const model = full.metadata.model;

    // Resolve plugin: qualified names (e.g., "apple-developer:ios-developer") used as-is;
    // bare names (e.g., "developer") → "igrsoft:developer"
    const subagentType = agentType.includes(':') ? agentType : `igrsoft:${agentType}`;

    // 5. Mark in_progress
    TaskUpdate({ taskId: task.id, status: "in_progress" });

    // 6. Delegate to stage agent
    Task({ subagent_type: subagentType, model: model, prompt: full.description });

    // 7. Mark completed
    TaskUpdate({ taskId: task.id, status: "completed" });
  }

  // Refresh task list
  tasks = TaskList();
}
```

**Key rules**:
- NEVER skip TaskUpdate calls (both in_progress and completed)
- NEVER execute a stage without checking blockedBy dependencies are completed
- ALWAYS pass `model` from task metadata to the Agent tool — do NOT rely on agent frontmatter inheritance
- `metadata.agent` accepts bare names (`"developer"` → `igrsoft:developer`) or fully-qualified plugin names (`"apple-developer:ios-developer"` → used as-is). Detection: presence of `:`
- If a stage agent fails after 3 retries, escalate per the error handling chain
- The orchestrator owns the loop; stage agents own their stage's work

## Related

- `milestone-workflow.md` - GitHub milestone integration
- `agent-coordination.md` - Multi-agent coordination
- `cost-optimization.md` - Budget management
- `context-compression.md` - Context compression
