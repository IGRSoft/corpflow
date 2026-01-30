# Workflow System

Single source of truth for task workflow management using the Task System for state management, UI visibility, and cross-session persistence.

## Task System Tools

| Tool | Purpose |
|------|---------|
| `TaskCreate` | Create new tasks with subject, description, activeForm, metadata |
| `TaskUpdate` | Update status, owner, add/remove blockedBy, **delete tasks** |
| `TaskGet` | Retrieve current task state |
| `TaskList` | View all tasks and their statuses |

### Task Deletion (Claude Code v2.1.20+)

TaskUpdate supports `delete: true` to remove tasks dynamically:

```typescript
TaskUpdate({ taskId: "6", delete: true });  // Delete task 6
```

This enables dynamic workflow sizing during P and A stages.

### Metadata Field

TaskCreate supports a `metadata` field for storing workflow-specific information:

```typescript
TaskCreate({
  subject: "P: Planning",
  description: "Define requirements and acceptance criteria",
  activeForm: "Planning task requirements",
  metadata: {
    priority: "high",
    stage: "P",
    workflow_id: "dark-mode-2025",
    milestone_number: 1,
    issue_number: 42
  }
});
```

**Standard metadata fields:**
- `priority` - Task priority (high, medium, low)
- `stage` - Workflow stage code (P, A, T, D, Q, W, F, S)
- `workflow_id` - Links task to specific workflow instance
- `milestone_number` - GitHub milestone number (when using `--milestone`)
- `issue_number` - GitHub issue number being worked on

## Cross-Session Persistence

By default, tasks persist within a session. For cross-session persistence, set `CLAUDE_CODE_TASK_LIST_ID`:

```bash
# Per-session
CLAUDE_CODE_TASK_LIST_ID="my-project" claude

# Or in .claude/settings.json
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "project-workflow"
  }
}
```

**Storage location:** `~/.claude/tasks/<list-id>/`

Each task is stored as a JSON file with full state including blockedBy relationships.

## Workflow Invocation

### Milestone-Based Workflow (Recommended)

Execute GitHub issues by priority using the milestone parameter:

```bash
/workflow --milestone:1       # Work through milestone 1 issues by priority
/workflow --milestone:2:123   # Work on issue #123 from milestone 2 only
```

**Execution Flow:**
1. Fetch milestone and issues from GitHub
2. Create `.context/milestone.json` with issues sorted by priority
3. Start working on highest priority issue (or specified issue)
4. Create branch `feature/{issue#}-{slug}` for each issue
5. Continue through issues until milestone complete

See [Milestone Workflow](milestone-workflow.md) for full documentation.

## Workspace Mode

When using `--milestone:N`, the workflow operates in **workspace mode** where each ticket executes in an isolated workspace directory.

### Workspace Detection

Agents detect workspace context by checking task metadata:

```typescript
// Check if running in workspace mode
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;

if (workspacePath) {
  // Running in workspace mode - use workspace paths
  const artifactPath = `${workspacePath}/.context/planning.md`;
} else {
  // Standard mode - use project root .context/
  const artifactPath = `.context/planning.md`;
}
```

### Workspace Metadata Fields

Tasks in workspace mode include additional metadata:

```typescript
TaskCreate({
  taskId: `t${track}-1`,  // Track-prefixed ID
  subject: `P: Planning - Issue #${issueNumber}`,
  metadata: {
    stage: "P",
    workflow_id: `milestone-${milestoneNumber}-issue-${issueNumber}`,
    issue_number: issueNumber,
    milestone_number: milestoneNumber,
    track: track,
    workspace_path: `.workspaces/milestone-${milestoneNumber}/${issueNumber}`
  }
});
```

### Path Resolution

**Artifact paths** are relative to workspace when in workspace mode:

| Mode | Base Path | Example |
|------|-----------|---------|
| Standard | `.context/` | `.context/planning.md` |
| Workspace | `{workspace_path}/.context/` | `.workspaces/milestone-1/42/.context/planning.md` |

### Task ID Namespacing

Workspace mode uses **track-prefixed task IDs** to enable parallel execution:

| Track | Task IDs |
|-------|----------|
| Track 1 | `t1-1`, `t1-2`, `t1-3`, `t1-4`, ... |
| Track 2 | `t2-1`, `t2-2`, `t2-3`, `t2-4`, ... |
| Track N | `t{N}-1`, `t{N}-2`, ... |

### Workspace-Aware Agent Pattern

Agents should use this pattern for workspace awareness:

```typescript
// Get current task and extract workspace context
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const issueNumber = task.metadata?.issue_number;

// Resolve context path
const contextPath = workspacePath
  ? `${workspacePath}/.context`
  : `.context`;

// Read workspace state if in workspace mode
if (workspacePath) {
  const workspaceJson = readFile(`${workspacePath}/workspace.json`);
  const workspace = JSON.parse(workspaceJson);
  // Use workspace.issue.body for requirements
  // Use workspace.git.branch_name for branch context
}

// Write artifacts to correct location
writeFile(`${contextPath}/planning.md`, planningContent);

// Update workspace state after stage completion
if (workspacePath) {
  updateWorkspaceJson(workspacePath, {
    execution: { current_stage: "A" },
    artifacts: { "planning.md": true }
  });
}
```

### Task-Based Workflow

For tasks not linked to GitHub issues:

```
workflow: [task description]   # Standard workflow
```

**Example:**
- `workflow: Add dark mode to settings` - Creates full 8-stage workflow

**Auto-detection from keywords:**
- Priority: `critical`, `urgent`, `blocker` → High; `minor`, `optional` → Low
- Platform: `ios`, `macos`, `tvos`, `watchos`, `visionos` → Specific platform

### Micro Tasks

For simple changes that don't need workflow tracking:

```
micro: [task description]
```

- **No folder creation** - Work directly in codebase
- **No task tracking** - Single task, immediate execution
- **Use for**: Typos, small refactors, simple config changes

---

## Dynamic Workflow Sizing

Instead of predefined workflow tiers (quick, fast), workflows are dynamically sized during P and A stages using task deletion.

### Unified Complexity Assessment

**Single Source of Truth** - Both P and A stages use this assessment framework:

| Factor | Low (0-2) | Medium (3-5) | High (6-10) |
|--------|-----------|--------------|-------------|
| **New patterns** | None | 1-2 new | 3+ new |
| **Integration points** | 1-2 | 3-5 | 6+ |
| **Cross-cutting concerns** | None | 1 area (security OR perf) | Multiple areas |
| **Risk level** | Minimal, reversible | Moderate, testable | High, hard to rollback |
| **Documentation needs** | Inline only | README update | ADR + API docs |

**Scoring**: Sum factor scores (0-50 total)

**Decision Rules**:

| Score | Complexity | P Stage Deletes | A Stage Deletes | Resulting Stages |
|-------|------------|-----------------|-----------------|------------------|
| 0-10 | Low | A, T, W, F, S | — | P → D → Q |
| 11-20 | Medium | T, W, F, S | (validate P decision) | P → A → D → Q |
| 21-30 | Moderate | W, F, S | (validate P decision) | P → A → T → D → Q |
| 31+ | High | None | None | All 8 stages |

### Model Routing by Complexity

Based on complexity score, suggest model for each stage:

| Complexity | P Stage | A Stage | D Stage | Q Stage | W Stage |
|------------|---------|---------|---------|---------|---------|
| Low (0-10) | haiku | — | sonnet | haiku | — |
| Medium (11-20) | sonnet | sonnet | sonnet | haiku | — |
| Moderate (21-30) | sonnet | sonnet | sonnet | sonnet | haiku |
| High (31+) | sonnet | opus | opus | sonnet | sonnet |

**Add to task metadata:**
```typescript
TaskCreate({
  subject: "A: Architecture",
  metadata: {
    stage: "A",
    complexity_score: 18,  // From unified assessment
    model_hint: "sonnet",  // Suggested model
    token_budget: 15000    // Soft limit
  }
});
```

### Safe Task Deletion Pattern

**ALWAYS** use this pattern to prevent dangling blockedBy references:

```typescript
// Safe deletion with dependency cleanup
function deleteTaskSafely(taskId: string) {
  // 1. Get all tasks to find dependents
  const allTasks = TaskList();

  // 2. Find tasks that reference this task in blockedBy
  const dependents = allTasks.filter(t =>
    t.blockedBy?.includes(taskId)
  );

  // 3. Update dependents to remove reference
  for (const dep of dependents) {
    TaskUpdate({
      taskId: dep.id,
      removeBlockedBy: [taskId]
    });
  }

  // 4. Delete the task
  TaskUpdate({ taskId, delete: true });
}
```

**Example: Delete T (id: 3) safely:**
```typescript
// D (id: 4) is blocked by T (id: 3)
// Step 1: Remove T from D's blockedBy
TaskUpdate({ taskId: "4", removeBlockedBy: ["3"] });
// Step 2: D should now be blocked by A
TaskUpdate({ taskId: "4", addBlockedBy: ["2"] });
// Step 3: Delete T
TaskUpdate({ taskId: "3", delete: true });
```

### P Stage Task Deletion

Product Manager deletes stages based on LOW complexity (score 0-10):

```typescript
// Complexity score: 8 (Low) - keep only P → D → Q
deleteTaskSafely("2");  // Delete Architecture
deleteTaskSafely("3");  // Delete Team Lead
deleteTaskSafely("6");  // Delete Documentation
deleteTaskSafely("7");  // Delete Finalization
deleteTaskSafely("8");  // Delete Stakeholder

// Update D to be blocked by P (since A is deleted)
TaskUpdate({ taskId: "4", addBlockedBy: ["1"] });
// Update Q to be blocked by D
TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });
```

### A Stage Task Deletion

Architect validates P's assessment and can further prune (for MODERATE complexity):

```typescript
// Complexity score: 25 (Moderate) - skip W, F, S
deleteTaskSafely("6");  // Delete Documentation
deleteTaskSafely("7");  // Delete Finalization
deleteTaskSafely("8");  // Delete Stakeholder

// Q now leads to completion (no changes to blockedBy needed)
```

**Important**: A stage should VALIDATE P's complexity assessment. If A disagrees, discuss with P before proceeding.

### Workflow Sizing Guidelines

| Task Complexity | Score | Stages Kept | Deleted |
|-----------------|-------|-------------|---------|
| Typo/micro | 0-10 | P → D → Q | A, T, W, F, S |
| Bug fix | 11-20 | P → A → D → Q | T, W, F, S |
| Small feature | 21-30 | P → A → T → D → Q | W, F, S |
| Full feature | 31+ | All 8 stages | None |

## 8-Stage Workflow (Full)

```
P → A → T → D → Q → W → F → S
```

| Code | Stage | Agent | Purpose | Artifact | Task ID |
|------|-------|-------|---------|----------|---------|
| P | Planning | product-manager | Define requirements | planning.md | 1 |
| E | Ethics (optional) | ethics-reviewer | Constitutional review | ethics.md | 2* |
| A | Architecture | software-architector | Design solution | analyzing.md | 2 or 3 |
| T | Team Lead | team-lead | Coordinate approach | Task System | 3 or 4 |
| D | Development | [language-pro] | Implement solution | development.md | 4 or 5 |
| Q | QA | qa-engineer | Test and validate | testing.md | 5 or 6 |
| W | Documentation | technical-writer | Write technical docs | documentation.md | 6 or 7 |
| F | Finalization | project-manager | Prepare release | complete.md | 7 or 8 |
| S | Stakeholder | stakeholder | Final approval | Terminal state | 8 or 9 |

*Task IDs shift when Ethics stage is included

## Task Status

| Status | Meaning |
|--------|---------|
| `pending` | Not started, may be blocked by dependencies |
| `in_progress` | Actively working |
| `completed` | Done |

## Task Tracking Integration (MANDATORY)

### Stage Code Format

**CRITICAL**: The subject field MUST use this format:

```
[STAGE]: [Description]
```

**Examples:**
- `P: Planning` - Planning stage
- `A: Architecture` - Architecture stage
- `D: Development` - Development stage
- `Q: QA Testing` - QA stage

### Initial State (Task Creation)

```typescript
// Create all 8 tasks with metadata
const workflowId = "dark-mode-2025";
const priority = "medium";

TaskCreate({ subject: "P: Planning", description: "Define requirements and acceptance criteria", activeForm: "Planning task requirements", metadata: { stage: "P", workflow_id: workflowId, priority } });  // Returns id: "1"
TaskCreate({ subject: "A: Architecture", description: "Design technical solution and architecture", activeForm: "Architecting solution", metadata: { stage: "A", workflow_id: workflowId, priority } });  // Returns id: "2"
TaskCreate({ subject: "T: Team Lead", description: "Coordinate approach and allocate resources", activeForm: "Coordinating team", metadata: { stage: "T", workflow_id: workflowId, priority } });  // Returns id: "3"
TaskCreate({ subject: "D: Development", description: "Implement solution following architecture", activeForm: "Implementing code", metadata: { stage: "D", workflow_id: workflowId, priority } });  // Returns id: "4"
TaskCreate({ subject: "Q: QA Testing", description: "Test and validate implementation", activeForm: "Testing solution", metadata: { stage: "Q", workflow_id: workflowId, priority } });  // Returns id: "5"
TaskCreate({ subject: "W: Documentation", description: "Write technical documentation", activeForm: "Writing technical documentation", metadata: { stage: "W", workflow_id: workflowId, priority } });  // Returns id: "6"
TaskCreate({ subject: "F: Finalization", description: "Prepare release package", activeForm: "Finalizing release", metadata: { stage: "F", workflow_id: workflowId, priority } });  // Returns id: "7"
TaskCreate({ subject: "S: Stakeholder", description: "Final stakeholder approval", activeForm: "Awaiting approval", metadata: { stage: "S", workflow_id: workflowId, priority } });  // Returns id: "8"

// Set up sequential dependency chain
TaskUpdate({ taskId: "2", addBlockedBy: ["1"] });  // A blocked by P
TaskUpdate({ taskId: "3", addBlockedBy: ["2"] });  // T blocked by A
TaskUpdate({ taskId: "4", addBlockedBy: ["3"] });  // D blocked by T
TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });  // Q blocked by D
TaskUpdate({ taskId: "6", addBlockedBy: ["5"] });  // W blocked by Q
TaskUpdate({ taskId: "7", addBlockedBy: ["6"] });  // F blocked by W
TaskUpdate({ taskId: "8", addBlockedBy: ["7"] });  // S blocked by F

// Start first task
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
```

### Stage Transitions

When a stage completes, transition to the next stage:

| From | To | Action |
|------|-----|--------|
| P (completed) | A (in_progress) | User approval → Architecture starts |
| A (completed) | T (in_progress) | Architecture done → Team Lead starts |
| T (completed) | D (in_progress) | Team Lead done → Development starts |
| D (completed) | Q (in_progress) | Development done → QA starts |
| Q (completed) | W (in_progress) | QA done → Documentation starts |
| W (completed) | F (in_progress) | Documentation done → Finalization starts |
| F (completed) | S (in_progress) | Finalization done → Stakeholder acceptance |

```typescript
// Complete current stage and start next
TaskUpdate({ taskId: "1", status: "completed" });
TaskUpdate({ taskId: "2", status: "in_progress", owner: "software-architector" });
```

## P3 Approval Gate

### Standard Workflow - STOP at P3

**CRITICAL**: After Planning completes, you MUST stop and wait for user approval.

1. Planning completes
2. P stage deletes unnecessary tasks (if applicable)
3. **Mark P approved in metadata:**
   ```typescript
   TaskUpdate({
     taskId: "1",
     status: "completed",
     metadata: { p3_approved: true, approved_at: new Date().toISOString() }
   });
   ```
4. **STOP AND ASK**: "Planning complete. Please review planning.md. Approve? [Y/n]"
5. **WAIT FOR USER RESPONSE** - Do NOT proceed automatically
6. User approves → Continue to next stage (A or D depending on deletions)

### P3 Enforcement (A Stage Check)

A stage MUST verify P3 approval before proceeding:

```typescript
// A stage startup check
const pTask = TaskGet({ taskId: "1" });
if (!pTask.metadata?.p3_approved) {
  throw new Error("P3 approval required before starting A stage");
}
```

## Agent Responsibilities

### Planning (P) - product-manager
- Create .context folder and initialize Task System
- **If milestone context exists**: Read issue body as requirements input
- Write planning.md with requirements, acceptance criteria
- **Define test strategy**: what to test, existing tests to update
- **Dynamic sizing**: Delete unnecessary stages for simple tasks
- **P3**: Wait for user approval before proceeding

### Architecture (A) - software-architector
- Review requirements (including test strategy), design technical solution
- **Design test architecture**: testability patterns, test doubles strategy
- Create analyzing.md with architecture decisions and **test architecture**
- **Dynamic sizing**: Can delete W, F, S stages based on complexity assessment

### Team Lead (T) - team-lead
- Review design, coordinate approach
- Manage task dependencies via Task System
- Allocate resources, define quality gates

### Development (D) - [language specialist]
- Analyze task, create development.md with implementation plan
- Implement solution following the plan
- **Testing Framework**: Use Swift Testing (`@Suite`, `@Test`, `#expect`) for unit tests; XCTest for UI tests only
- Run code formatter on modified files
- Verify build passes, complete implementation notes

### QA (Q) - qa-engineer
- Analyze requirements, discover existing tests, create test plan
- Implement/update tests, execute test suite
- **Framework Enforcement**: All new unit tests MUST use Swift Testing framework
- Handle test failures (retry or escalate)
- All tests pass, document results

### Documentation (W) - technical-writer
- Analyze artifacts, discover documentation needing updates
- Update code docs, README, ARCHITECTURE files
- All documentation updated

### Finalization (F) - project-manager
- Review all artifacts, run final builds/tests
- Create complete.md, release.md
- Technical complete

### Stakeholder (S) - stakeholder
- Final acceptance review
- Task complete (terminal state)

## Error Handling

### error.md File

When errors occur that require escalation, create/update `error.md` in the task folder root.

```markdown
# Error Log

## [STAGE] Error - [TIMESTAMP]

**Stage**: [P/A/T/D/Q/W/F/S]
**Retry Count**: [X/3]
**Status**: [active|resolved|escalated]

### Problem Description
[Clear description of what went wrong]

### Root Cause Analysis
[Why did this happen?]

### Attempted Solutions
1. [First attempt and result]
2. [Second attempt and result]
3. [Third attempt and result]

### Escalation Details (if escalated)
- **Escalated To**: [Previous stage agent]
- **Escalation Reason**: [Why escalation was needed]
- **Required Action**: [What the escalated agent needs to do]
```

### Retry Logic

Each stage can retry up to 3 times. Track retries via task metadata or error.md.

### Escalation Chain

After 3 retries, escalate to previous stage:

```
S → F → Q → D → T → A → P → USER
```

## Rule Checks

Required validations before certain transitions:

| Rule | Required Before |
|------|-----------------|
| Test Strategy | P → A (must be in planning.md) |
| Test Architecture | A → T (must be in analyzing.md) |
| Code Format | D (before marking complete) |
| Build | D → Q |
| Tests | Q → W |
| Code Review | D → Q |

## Execution Modes

### Async (Default)
Tasks run independently, no waiting.

### Sync
Tasks wait for dependencies to complete (F or S):

```json
{
  "execution_mode": "sync",
  "dependencies": ["20250114-database-setup"]
}
```

## Parallel Execution Patterns

### W + Q Parallel (DEFAULT)

**W and Q run in parallel by default** - This saves 30-40% wall-clock time.

| Condition | Dependencies | Time Savings |
|-----------|--------------|--------------|
| Default (parallel) | Q blocked by D, W blocked by D, F blocked by Q AND W | ~30-40% |
| Sequential (use `--sequential`) | Q blocked by D, W blocked by Q, F blocked by W | — |

### Default Parallel Dependencies (Use This)

```typescript
// DEFAULT: W and Q run in parallel after D completes
TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });  // Q blocked by D (not W)
TaskUpdate({ taskId: "6", addBlockedBy: ["4"] });  // W blocked by D (not Q)
TaskUpdate({ taskId: "7", addBlockedBy: ["5", "6"] });  // F blocked by BOTH Q AND W

// Both Q and W become unblocked when D completes
// F only starts when both Q and W are completed
```

### Sequential Dependencies (Only When Needed)

Use `--sequential` flag when W requires test results:

```typescript
// SEQUENTIAL: W waits for Q (only use when W needs test output)
TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });  // Q blocked by D
TaskUpdate({ taskId: "6", addBlockedBy: ["5"] });  // W blocked by Q
TaskUpdate({ taskId: "7", addBlockedBy: ["6"] });  // F blocked by W
```

### Other Parallel Opportunities

| Combination | Condition | Time Savings |
|-------------|-----------|--------------|
| Early W during D | Core API stable | Documentation ready sooner |
| Multi-issue milestone | See milestone-workflow.md | 40-50% for 3+ issues |

### Never Parallelize

| Combination | Reason |
|-------------|--------|
| A before P | Architecture needs requirements |
| D before T | Development needs coordination |
| Q before D | Can't test unwritten code |
| S before F | Approval needs release package |

## Optimization Hooks

### Pre-Stage Hooks

Before starting any stage, perform these checks:

| Check | Threshold | Action |
|-------|-----------|--------|
| Context size | > 50% window | Compress previous stages |
| Budget usage | > 75% | Alert user, suggest optimizations |
| Required artifacts | Missing | Block until available |

### Post-Stage Hooks

After completing any stage:

| Action | Purpose |
|--------|---------|
| Compress context | Prepare handoff summary (50-100 tokens) |
| Log token usage | Track cost via task metadata |
| Validate artifacts | Ensure required files created |

### Stage-Specific Optimizations

| Stage | Model | Optimization |
|-------|-------|--------------|
| P | sonnet | Use haiku for simple formatting |
| A | opus | Full opus for decisions, haiku for diagrams |
| T | sonnet | Brief coordination, reference artifacts |
| D | opus | Sonnet for implementation, opus for complex logic |
| Q | haiku | Haiku for test execution, sonnet for test design |
| W | haiku | Template-based documentation |
| F | sonnet | Brief validation checks |
| S | sonnet | Concise approval review |

## Best Practices

### DO
- Create `.context/` folder before any work
- Initialize tasks with proper dependencies at workflow start
- Update task status at every stage transition
- Document errors in error.md (for escalation scenarios)
- Check dependencies before starting
- Compress context at stage handoffs
- Use appropriate model tier for each task
- Reference artifacts instead of duplicating content

### DON'T
- Skip state transitions
- Forget to update task status
- Bypass approval gates (standard workflow)
- Create circular dependencies
- Ignore rule check failures
- Include full file content in handoffs (reference paths instead)
- Use opus for simple formatting tasks
- Duplicate context across stages

## When to Use Workflow

| Use Full Workflow | Skip Workflow |
|-------------------|---------------|
| Multiple files/modules affected | Single-file edit |
| New feature or multi-step fix | Typo, rename, docs tweak |
| Security/permissions involved | One small test |
| Cross-team coordination needed | Mechanical change |

## Constitutional Integration

### Ethics Checkpoints

Optional ethics review can be integrated at workflow stages:

| Checkpoint | Stage | Trigger | Purpose |
|------------|-------|---------|---------|
| **Pre-Planning** | Before P | `--ethics-review` flag | Assess feature for harm potential |
| **Design Review** | After A | High-risk features | Validate architecture safety |
| **Implementation Review** | After D | Safety-critical code | Verify no harmful implementations |
| **Pre-Release** | After F | All major releases | Final constitutional compliance check |

### Adding Ethics Review to Workflow

Use the `--ethics-review` flag with workflow command:

```
workflow: Add user tracking feature --ethics-review
```

This adds ethics checkpoint after P stage:

```
P → E → A → T → D → Q → W → F → S
```

### Ethics Stage (Optional E Stage)

For high-risk features, insert explicit ethics review:

```typescript
TaskCreate({ subject: "P: Planning", description: "Define requirements", activeForm: "Planning..." });  // id: "1"
TaskCreate({ subject: "E: Ethics Review", description: "Constitutional compliance", activeForm: "Reviewing ethics..." });  // id: "2"
TaskCreate({ subject: "A: Architecture", description: "Design solution", activeForm: "Architecting..." });  // id: "3"
// ... rest of stages

TaskUpdate({ taskId: "2", addBlockedBy: ["1"] });  // E blocked by P
TaskUpdate({ taskId: "3", addBlockedBy: ["2"] });  // A blocked by E
// ... rest of chain
```

### Constitutional Escalation

Ethics concerns escalate differently from technical issues:

```
Ethics Escalation Chain:
Feature Concern → ethics-reviewer → stakeholder → USER

Hard Constraint Violation → IMMEDIATE STOP → USER
```

### High-Risk Feature Indicators

Features requiring mandatory ethics review:

- User data collection or tracking
- Algorithmic recommendations or personalization
- Financial transactions or sensitive data
- Content moderation or filtering
- AI/ML decision-making
- Children or vulnerable populations
- Health or safety implications

## Task System Features

### Persistence
Tasks persist across sessions, accessible via `Ctrl+T` task view.

### Native Dependencies
Use `blockedBy` arrays for explicit dependency management:

```typescript
TaskUpdate({ taskId: "4", addBlockedBy: ["3"] });  // D blocked by T
TaskUpdate({ taskId: "4", removeBlockedBy: ["3"] });  // Remove blocker
```

### Sub-agent Visibility
Sub-agents can see and update the main task list:

```typescript
// Main agent creates task
TaskCreate({ subject: "D: Development", ... });  // id: "4"

// Sub-agent (swift-pro) can see and update
const task = TaskGet({ taskId: "4" });
TaskUpdate({ taskId: "4", status: "in_progress", owner: "swift-pro" });
```

### Multi-Workflow Coordination

Track multiple workflows with cross-workflow dependencies:

```typescript
// Workflow A
TaskCreate({ subject: "WF-A: D: Development", ... });  // id: "wfa-dev"
TaskCreate({ subject: "WF-A: F: Finalization", ... });  // id: "wfa-final"

// Workflow B depends on Workflow A completing
TaskCreate({ subject: "WF-B: P: Planning", ... });  // id: "wfb-plan"
TaskUpdate({ taskId: "wfb-plan", addBlockedBy: ["wfa-final"] });
```

### Task Ownership
Use the `owner` field to track which agent owns each task:

```typescript
TaskUpdate({ taskId: "4", status: "in_progress", owner: "swift-pro" });
```

## Related Skills

- `milestone-workflow.md` - GitHub milestone integration and priority-based execution
- `cost-optimization.md` - Cost tracking and budget management
- `context-compression.md` - Context compression techniques
- `agent-coordination.md` - Multi-agent coordination patterns
- `estimation-methodology.md` - Task estimation framework
- `claude-constitution.md` - Constitutional principles and ethics framework
