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
const contextPath = workspacePath ? `${workspacePath}/.context` : `.context`;
```

### Path Resolution

| Mode | Base Path |
|------|-----------|
| Standard | `.context/` |
| Workspace | `.workspaces/milestone-{N}/{issue#}/.context/` |

### Task ID Namespacing

| Track | Task IDs |
|-------|----------|
| Track 1 | `t1-1`, `t1-2`, ... |
| Track N | `t{N}-1`, `t{N}-2`, ... |

See `milestone-workflow.md` for full workspace documentation.

## Milestone Initialization

When `--milestone:N` is specified:

### 1. Fetch Milestone Issues

```bash
# Get milestone info
gh api repos/:owner/:repo/milestones/{N} --jq '.title'

# Get all open issues
gh issue list --milestone "{title}" --json number,title,labels,body
```

### 2. Filter Issues with Existing PRs

Skip issues that already have linked PRs:

```bash
# Check for linked PRs on each issue
gh api /repos/:owner/:repo/issues/{issue#}/timeline --jq '[.[] | select(.event == "cross-referenced" and .source.issue.pull_request)] | length'
```

If count > 0, mark issue as `skipped_has_pr` and exclude from workflow.

### 3. Sort by Priority

| Priority | Label | Order |
|----------|-------|-------|
| Critical | P0, priority:critical | 1 |
| High | P1, priority:high | 2 |
| Medium | P2, priority:medium | 3 |
| Low | P3, priority:low | 4 |
| None | (unlabeled) | 5 |

### 4. Per-Issue Workspace Setup

For each issue in priority order:

```bash
# Create isolated workspace
mkdir -p .workspaces/milestone-{N}/{issue#}/.context

# CRITICAL: Create branch from base (using remote to avoid worktree conflicts)
git fetch origin develop  # or base branch from issue body
git checkout -b feature/{issue#}-{slug} origin/develop
```

### 5. Initialize Orchestrator

Create `.workspaces/orchestrator.json` to track all issues:

```json
{
  "milestone_number": 1,
  "milestone_title": "Sprint 2025-W05",
  "parallel_tracks": 2,
  "base_branch": "develop",
  "created_at": "2026-01-31T10:00:00Z",
  "issues": [
    {
      "number": 27,
      "title": "feat: Add watermark support",
      "priority": "P0",
      "status": "pending",
      "track": null,
      "branch": "feature/27-watermark-support",
      "workspace": ".workspaces/milestone-1/27"
    }
  ]
}
```

### 6. Execute Per-Issue Workflow

Each issue runs the full staged workflow independently:

```
Issue #27 → feature/27-watermark → PL→AR→TL→DV→QA→DC→FN→ST → PR → complete
Issue #26 → feature/26-font-family → PL→AR→TL→DV→QA→DC→FN→ST → PR → complete
```

See `shared/milestone-helpers.md` for helper functions.

## Workflow Initialization

```typescript
const workflowId = "dark-mode-2025";
const stages = ["PL", "AR", "TL", "DV", "QA", "DC", "FN", "ST"];
const stageNames = { PL: "Planning", AR: "Architecture", TL: "Team Lead", DV: "Development", QA: "QA Testing", DC: "Documentation", FN: "Finalization", ST: "Stakeholder" };

// Create tasks
stages.forEach((code, i) => {
  TaskCreate({
    subject: `${code}: ${stageNames[code]}`,
    description: `Stage ${i + 1}`,
    activeForm: `Working on ${stageNames[code]}`,
    metadata: { stage: code, workflow_id: workflowId, priority: "medium" }
  });
});

// Chain dependencies: 2←1, 3←2, ..., 8←7
for (let i = 2; i <= 8; i++) {
  TaskUpdate({ taskId: String(i), addBlockedBy: [String(i - 1)] });
}

// Start first task
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
```

## PL3 Approval Gate

**CRITICAL**: Standard workflow MUST stop after Planning for user approval.

1. Planning completes, PL stage deletes unnecessary tasks
2. Mark approved: `TaskUpdate({ taskId: "1", status: "completed", metadata: { p3_approved: true } })`
3. **STOP AND ASK**: "Planning complete. Please review planning.md. Approve? [Y/n]"
4. User approves → Continue to next stage

AR stage verifies: `if (!pTask.metadata?.p3_approved) throw new Error("PL3 approval required");`

## Agent Responsibilities

| Stage | Agent | Key Tasks |
|-------|-------|-----------|
| PL | product-manager | Requirements, acceptance criteria, test strategy, dynamic sizing |
| AR | software-architector | Technical design, test architecture, validate PL sizing |
| TL | team-lead | Coordinate approach, allocate resources |
| DV | developer | Implement solution, run formatter, verify build |
| SR | security-reviewer | OWASP audit, vulnerability scan |
| QA | qa-engineer | Test plan, execute tests, all tests pass |
| DC | technical-writer | Update docs, README, ARCHITECTURE |
| RE | release-engineer | Version bump, changelog, deployment readiness |
| FN | project-manager | Final builds, deployment |
| ST | stakeholder | Final acceptance |
| IR | incident-responder | Triage, classify severity, coordinate response |

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
| Tests Pass | QA → DC |

## Optimization Hooks

### Pre-Stage

| Check | Threshold | Action |
|-------|-----------|--------|
| Context size | > 50% window | Compress previous stages |
| Budget usage | > 75% | Alert user |

### Post-Stage

- Compress context for handoff (50-100 tokens)
- Log token usage in task metadata
- Validate artifacts created

## Constitutional Integration

Use `--ethics-review` for high-risk features:

```
PL → ET → AR → TL → DV → QA → DC → FN → ST
```

**High-risk indicators**: User tracking, algorithmic recommendations, financial transactions, content moderation, AI/ML decisions, children/vulnerable populations.

See `claude-constitution.md` for full principles.

## Agent Teams Integration (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, the workflow system can leverage agent teams for milestone mode parallel execution.

### Enabling

Add to project `settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### Hook Events for Workflow Monitoring

| Hook Event | Use Case |
|------------|----------|
| `SubagentStart` | Log stage agent activation |
| `SubagentStop` | Detect stage agent completion |
| `TeammateIdle` | Assign next task to idle teammate (agent teams only) |
| `TaskCompleted` | Trigger dependent stages, update orchestrator (agent teams only) |

See `agent-coordination.md § Hook-Based Stage Monitoring` for configuration patterns.

### Limitations

- Teammates cannot spawn sub-agents or teams
- No session resumption for in-process teammates
- Higher token cost than Task-based orchestration
- Maximum one team per session

See `milestone-workflow.md § Agent Teams Mode` for parallel execution patterns.
See `agent-coordination.md § Agent Teams vs Subagents` for comparison.

## Related

- `milestone-workflow.md` - GitHub milestone integration
- `agent-coordination.md` - Multi-agent coordination
- `cost-optimization.md` - Budget management
- `context-compression.md` - Context compression
