# Workflow System

Single source of truth for task workflow management using the Task System for UI visibility and workflow-state.json for structured persistence.

## Task System Tools

| Tool | Purpose |
|------|---------|
| `TaskCreate` | Create new tasks with subject, description, activeForm, metadata |
| `TaskUpdate` | Update status, owner, add/remove blockedBy |
| `TaskGet` | Retrieve current task state |
| `TaskList` | View all tasks and their statuses |

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
    workflow_id: "dark-mode-2025"
  }
});
```

**Standard metadata fields:**
- `priority` - Task priority (high, medium, low)
- `stage` - Workflow stage code (P, A, T, D, Q, W, F, S)
- `workflow_id` - Links task to specific workflow instance

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

## CRITICAL: Trigger Behavior (MUST EXECUTE)

**When you see user input starting with these prefixes, you MUST immediately invoke the corresponding slash command using the SlashCommand tool:**

| User Input Prefix | SlashCommand to Invoke |
|-------------------|------------------------|
| `workflow: [task]` | `/company-workflow:workflow "[task]"` |
| `fworkflow: [task]` | `/company-workflow:workflow "[task]" --fast` |
| `quick: [task]` | `/company-workflow:workflow "[task]" --quick` |

**Execution Order:**
1. **Detect prefix** - Check if user message starts with `workflow:`, `fworkflow:`, or `quick:`
2. **Extract task** - Everything after the prefix (including any embedded slash commands like `/apple-developer:...`)
3. **Invoke workflow FIRST** - Use SlashCommand tool to run `/company-workflow:workflow "[extracted task]"`
4. **Workflow handles the rest** - The workflow command sets up the context, then orchestrates the stages including any embedded commands

**Example Flow:**
```
User: workflow: /apple-developer:code-legacy-modernize migrate @StateObject to @Environment

Claude MUST:
1. Detect "workflow:" prefix
2. Extract task: "/apple-developer:code-legacy-modernize migrate @StateObject to @Environment"
3. Invoke: SlashCommand("/company-workflow:workflow \"/apple-developer:code-legacy-modernize migrate @StateObject to @Environment\"")
4. Workflow creates .context/, workflow-state.json, planning.md
5. Planning stage (product-manager) captures requirements
6. Architecture stage can then invoke /apple-developer:code-legacy-modernize
```

**For `micro: [task]`**: No workflow initialization. Execute the task directly without stage management.

---

## Quick Start: Triggers

Start workflows with these prefixes:

```
workflow: [task description]   # Standard - stops at P3 for user approval
fworkflow: [task description]  # Fast - skips P3 approval, auto-continues
```

**Examples:**
- `workflow: Add dark mode to settings` - Stops at P3 for approval
- `fworkflow: Fix login button typo` - Runs through all stages automatically

**Auto-detection from keywords:**
- Priority: `critical`, `urgent`, `blocker` → High; `minor`, `optional` → Low
- Platform: `ios`, `macos`, `tvos`, `watchos`, `visionos` → Specific platform

## Workflow Tiers (Context Optimization)

Choose the appropriate tier based on task complexity:

| Trigger | Stages | Use For |
|---------|--------|---------|
| `micro: [task]` | Direct edit | Single-file fixes, typos, simple changes |
| `quick: [task]` | P → D → Q | Small features, bug fixes, focused changes |
| `workflow: [task]` | Full 8 stages | Multi-file features, architectural changes |
| `fworkflow: [task]` | Full 8 stages (no P3 gate) | Trusted full workflows |

### Micro Workflow
- **No folder creation** - Work directly in codebase
- **No task tracking** - Single task, immediate execution
- **Use for**: Typos, small refactors, simple config changes

### Quick Workflow (3 stages)
```
P → D → Q
```
- Creates task folder with minimal artifacts
- Skips Architecture (A), Team Lead (T), Documentation (W), Finalization (F)
- **Use for**: Bug fixes, small features, focused improvements

## 8-Stage Workflow (Full)

```
P → A → T → D → Q → W → F → S
```

| Code | Stage | Agent | Purpose | Artifact | Task ID |
|------|-------|-------|---------|----------|---------|
| P | Planning | product-manager | Define requirements | planning.md | 1 |
| E | Ethics (optional) | ethics-reviewer | Constitutional review | ethics.md | 2* |
| A | Architecture | software-architector | Design solution | analyzing.md | 2 or 3 |
| T | Team Lead | team-lead | Coordinate approach | workflow-state.json | 3 or 4 |
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

**Retry tracking** stored in workflow-state.json `retries` object

## Status Code Reference

This section defines the canonical status tracking system used throughout the workflow.

### Dual-Layer Status System

The workflow uses two complementary status tracking mechanisms:

| Layer | Location | Values | Purpose |
|-------|----------|--------|---------|
| **Task System** | TaskUpdate/TaskGet | `pending`, `in_progress`, `completed` | UI visibility, user-facing progress |
| **Workflow State** | workflow-state.json `statusCode` | `"0"`, `"1"`, `"2"`, `"3"` | Internal phase tracking within stages |

**CRITICAL**: Both systems must be updated together at every state transition.

### Workflow State Status Codes (statusCode)

| Code | Name | Description | Task Status |
|------|------|-------------|-------------|
| `"0"` | PREPARING | Stage initialized, setup in progress | `in_progress` |
| `"1"` | EXECUTING | Active work being performed | `in_progress` |
| `"2"` | ERROR | Stage failed, awaiting retry/escalation | `in_progress` |
| `"3"` | DONE | Stage completed successfully | `completed` |

**Note**: statusCode is stored as a string in JSON (`"1"` not `1`).

### Task Status to StatusCode Mapping

| Task Status | Valid statusCodes | When to Use |
|-------------|-------------------|-------------|
| `pending` | n/a | Task blocked by dependencies |
| `in_progress` | `"0"`, `"1"`, `"2"` | Stage active (preparing, executing, or error) |
| `completed` | `"3"` | Stage finished successfully |

### State String Format

**Canonical format**: `{stage}:{phase}`

| Component | Values |
|-----------|--------|
| stage | `planning`, `architecture`, `teamlead`, `development`, `qa`, `documentation`, `finalization`, `stakeholder` |
| phase | `preparing`, `executing`, `error`, `done` |

**Shorthand format**: `{STAGE_CODE}{STATUS_CODE}`

| Component | Values |
|-----------|--------|
| STAGE_CODE | P, A, T, D, Q, W, F, S |
| STATUS_CODE | 0, 1, 2, 3 |

**Format Mapping Examples**:

| Canonical | Shorthand | Description |
|-----------|-----------|-------------|
| `"development:executing"` | `D1` | Development stage actively working |
| `"qa:error"` | `Q2` | QA stage encountered error |
| `"finalization:done"` | `F3` | Finalization complete |
| `"planning:preparing"` | `P0` | Planning stage initializing |

### Stage Lifecycle State Machine

```
                    ┌──────────────────────────────────────────┐
                    │            Stage Started                 │
                    │     (TaskUpdate: in_progress)            │
                    └──────────────────┬───────────────────────┘
                                       ↓
                    ┌──────────────────────────────────────────┐
                    │     PREPARING (statusCode: "0")          │
                    │     Task: in_progress                    │
                    │     state.current: "{stage}:preparing"   │
                    └──────────────────┬───────────────────────┘
                                       ↓ Begin work
                    ┌──────────────────────────────────────────┐
                    │     EXECUTING (statusCode: "1")          │
                    │     Task: in_progress                    │
                    │     state.current: "{stage}:executing"   │
                    └─────────┬───────────────────┬────────────┘
                              │                   │
                      Error   ↓           Success ↓
         ┌──────────────────────────┐    ┌──────────────────────────┐
         │  ERROR (statusCode: "2") │    │   DONE (statusCode: "3") │
         │  Task: in_progress       │    │   Task: completed        │
         │  state: "{stage}:error"  │    │   state: "{stage}:done"  │
         └────────────┬─────────────┘    └────────────┬─────────────┘
                      │                               │
              Retry   ↓   Escalate                    ↓
         ┌────────────┴────────────┐         Next Stage Starts
         │ retries < max:          │         (PREPARING)
         │   → EXECUTING ("1")     │
         │ retries = max:          │
         │   → Previous Stage      │
         └─────────────────────────┘
```

### Transition Log Format

Transitions are logged in `state.transitions` array using shorthand notation:

```
"[FROM_SHORTHAND] → [TO_SHORTHAND]"              // Simple transition
"[FROM_SHORTHAND] → [TO_SHORTHAND] ([note])"     // With note
```

**Standard transition notes**:
- `(user approved)` - User approved P3 gate
- `(error)` - Error occurred
- `(retry)` - Retry after error
- `(A,T skipped)` - Stages skipped (quick workflow)
- `(escalated)` - Escalated to previous stage

**Examples**:
```json
"transitions": [
  "P0 → P1",
  "P1 → P3",
  "P3 → A1 (user approved)",
  "A1 → A3",
  "A3 → T1",
  "T1 → T3",
  "T3 → D1",
  "D1 → D2 (error)",
  "D2 → D1 (retry)",
  "D1 → D3",
  "D3 → Q1"
]
```

### Quick Workflow State Tracking

For quick workflows (P→D→Q), skipped stages have `null` task_ids:

```json
{
  "task_ids": {
    "planning": "1",
    "ethics": null,
    "architecture": null,
    "teamlead": null,
    "development": "2",
    "qa": "3",
    "documentation": null,
    "finalization": null,
    "stakeholder": null
  },
  "state": {
    "current": "development:executing",
    "statusCode": "1",
    "transitions": [
      "P0 → P1",
      "P1 → P3",
      "P3 → D1 (A,T skipped)"
    ]
  }
}
```

### Synchronization Rules

**ALWAYS update both systems together**:

```typescript
// Stage starts
TaskUpdate({ taskId: "4", status: "in_progress", owner: "developer" });
// Update workflow-state.json: statusCode = "0", current = "development:preparing"

// Stage executing
// Update workflow-state.json: statusCode = "1", current = "development:executing"

// Stage completes
TaskUpdate({ taskId: "4", status: "completed" });
// Update workflow-state.json: statusCode = "3", current = "development:done"
```

**Error handling**:
```typescript
// Error detected - Task stays in_progress
// Update workflow-state.json: statusCode = "2", current = "development:error"
// Increment retries["4"]

// Retry - Task stays in_progress
// Update workflow-state.json: statusCode = "1", current = "development:executing"
```

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

### Standard Workflow (`workflow:`) - STOP at P3

**CRITICAL**: You MUST stop and wait for user approval.

1. Planning completes → `TaskUpdate({ taskId: "1", status: "completed" })`
2. **STOP AND ASK**: "Planning complete. Please review planning.md. Approve? [Y/n]"
3. **WAIT FOR USER RESPONSE** - Do NOT proceed automatically
4. User approves → `TaskUpdate({ taskId: "2", status: "in_progress", owner: "software-architector" })`

### Fast Workflow (`fworkflow:`) - SKIP P3

For fast workflow, immediately continue to Architecture:

```typescript
TaskUpdate({ taskId: "1", status: "completed" });
TaskUpdate({ taskId: "2", status: "in_progress", owner: "software-architector" });
```

## Agent Responsibilities

### Planning (P) - product-manager
- Create task folder and workflow-state.json
- Write planning.md with requirements, acceptance criteria
- **P3**: Wait for user approval (standard) or auto-continue (fast)

### Architecture (A) - software-architector
- Review requirements, design technical solution
- Create analyzing.md with architecture decisions
- **Skip path**: Simple tasks may skip to T

### Team Lead (T) - team-lead
- Review design, coordinate approach
- Update workflow-state.json with blockers/dependencies
- Allocate resources, define quality gates

### Development (D) - [language specialist]
- Analyze task, create development.md with implementation plan
- Implement solution following the plan
- Run code formatter on modified files
- Verify build passes, complete implementation notes

### QA (Q) - qa-engineer
- Analyze requirements, discover existing tests, create test plan
- Implement/update tests, execute test suite
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

Each stage can retry up to 3 times. Track retries in workflow-state.json:

```json
{
  "retries": { "4": 2, "max": 3 }
}
```

### Escalation Chain

After 3 retries, escalate to previous stage:

```
S → F → Q → D → T → A → P → USER
```

## workflow-state.json Structure

Located at `.context/workflow-state.json`:

```json
{
  "$schema": "workflow-state-v2",
  "workflow_id": "unique-workflow-id",
  "title": "Task Title",
  "created_at": "2025-01-26T10:00:00Z",
  "updated_at": "2025-01-26T10:30:00Z",
  "workflow_type": "standard|fast|quick",
  "options": {
    "with_design": false,
    "ethics_review": false,
    "priority": "medium",
    "platform": "all"
  },
  "task_ids": {
    "planning": "1",
    "ethics": null,
    "architecture": "2",
    "teamlead": "3",
    "development": "4",
    "qa": "5",
    "documentation": "6",
    "finalization": "7",
    "stakeholder": "8"
  },
  "state": {
    "current": "development:executing",
    "previous": "teamlead:done",
    "statusCode": "1",
    "agent": "D",
    "transitions": []
  },
  "retries": {
    "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0,
    "max": 3
  },
  "approvals": {},
  "escalations": [],
  "artifacts": {
    "planning": ".context/planning.md",
    "architecture": ".context/analyzing.md",
    "development": ".context/development.md",
    "testing": ".context/testing.md",
    "documentation": ".context/documentation.md",
    "complete": ".context/complete.md"
  },
  "rule_checks": {
    "build": "pending",
    "code_review": "pending",
    "testing": "pending"
  }
}
```

## Rule Checks

Required validations before certain transitions:

| Rule | Required Before |
|------|-----------------|
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

### Safe Parallel Combinations

| Combination | Condition | Time Savings |
|-------------|-----------|--------------|
| W + Q | W doesn't need test results | ~30-40% |
| Early W during D | Core API stable | Documentation ready sooner |

### Native Parallel Dependencies

```typescript
// W and Q can run in parallel after D completes
TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });  // Q blocked by D (not W)
TaskUpdate({ taskId: "6", addBlockedBy: ["4"] });  // W blocked by D (not Q)
TaskUpdate({ taskId: "7", addBlockedBy: ["5", "6"] });  // F blocked by BOTH Q AND W

// Both Q and W become unblocked when D completes
// F only starts when both Q and W are completed
```

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
| Log token usage | Update cost_tracking in workflow-state.json |
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
- Keep workflow-state.json synchronized
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

- `cost-optimization.md` - Cost tracking and budget management
- `context-compression.md` - Context compression techniques
- `agent-coordination.md` - Multi-agent coordination patterns
- `estimation-methodology.md` - Task estimation framework
- `claude-constitution.md` - Constitutional principles and ethics framework
