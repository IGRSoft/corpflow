# Workflow System

Single source of truth for task workflow management using TodoWrite for UI visibility and task-state.json for structured persistence.

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
- **No TodoWrite** - Single task, immediate execution
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

| Code | Stage | Agent | Purpose | Artifact |
|------|-------|-------|---------|----------|
| P | Planning | project-manager | Define requirements | planning.md |
| A | Architecture | architect-review | Design solution | analyzing.md |
| T | Team Lead | team-lead | Coordinate approach | task-state.json |
| D | Development | [language-pro] | Implement solution | development.md |
| Q | QA | test-automator | Test and validate | testing.md |
| W | Documentation | docs-architect | Write technical docs | documentation.md |
| F | Finalization | project-manager | Prepare release | complete.md |
| S | Stakeholder | stakeholder | Final approval | Terminal state |

## Status Codes

| Code | Name | TodoWrite Status | Description |
|------|------|------------------|-------------|
| 0 | preparing | pending | Agent preparing to work |
| 1 | executing | in_progress | Agent actively working |
| 2 | error | in_progress | Error occurred (retry or escalate) |
| 3 | done | completed | Agent completed work |

## TodoWrite Integration (MANDATORY)

### Stage Code Format

**CRITICAL**: The `content` field MUST use this format:

```
[STAGE][STATUS]: [Description]
```

**Examples:**
- `P1: Planning` - Planning stage, executing
- `A0: Architecture` - Architecture stage, preparing
- `D2: Development (retry 1/3)` - Development error with retry
- `Q3: QA Testing` - QA completed

### Initial State (Task Creation)

```typescript
TodoWrite({
  todos: [
    { content: "P1: Planning", status: "in_progress", activeForm: "Planning task requirements" },
    { content: "A0: Architecture", status: "pending", activeForm: "Architecting solution" },
    { content: "T0: Team Lead", status: "pending", activeForm: "Coordinating team" },
    { content: "D0: Development", status: "pending", activeForm: "Implementing code" },
    { content: "Q0: QA Testing", status: "pending", activeForm: "Testing solution" },
    { content: "W0: Documentation", status: "pending", activeForm: "Writing technical documentation" },
    { content: "F0: Finalization", status: "pending", activeForm: "Finalizing release" },
    { content: "S0: Stakeholder", status: "pending", activeForm: "Awaiting approval" }
  ]
});
```

### Stage Transitions

When a stage completes (code 3), auto-transition to next stage (code 1):

| From | To | Action |
|------|-----|--------|
| P3 | A1 | User approval → Architecture starts |
| A3 | T1 | Architecture done → Team Lead starts |
| T3 | D1 | Team Lead done → Development starts |
| D3 | Q1 | Development done → QA starts |
| Q3 | W1 | QA done → Documentation starts |
| W3 | F1 | Documentation done → Finalization starts |
| F3 | S1 | Finalization done → Stakeholder acceptance |

## P3 Approval Gate

### Standard Workflow (`workflow:`) - STOP at P3

**CRITICAL**: You MUST stop and wait for user approval.

1. Planning completes → Update TodoWrite: `P3: Planning (awaiting approval)`
2. **STOP AND ASK**: "Planning complete. Please review planning.md. Approve? [Y/n]"
3. **WAIT FOR USER RESPONSE** - Do NOT proceed automatically
4. User approves → Update to `P3: Planning Approved`, transition to A1

### Fast Workflow (`fworkflow:`) - SKIP P3

For fast workflow, immediately continue to Architecture:

```typescript
TodoWrite({
  todos: [
    { content: "P3: Planning Auto-approved", status: "completed", activeForm: "Planning task requirements" },
    { content: "A1: Architecture", status: "in_progress", activeForm: "Architecting solution" },
    // ... rest
  ]
});
```

## Agent Responsibilities

### Planning (P) - project-manager
- Create task folder and task-state.json
- Write planning.md with requirements, acceptance criteria
- **P3**: Wait for user approval (standard) or auto-continue (fast)

### Architecture (A) - architect-review
- Review requirements, design technical solution
- Create analyzing.md with architecture decisions
- **Skip path**: A0 → T0 for simple tasks (no architectural impact)

### Team Lead (T) - team-lead
- Review design, coordinate approach
- Update task-state.json with blockers/dependencies
- Allocate resources, define quality gates

### Development (D) - [language specialist]
- **D0**: Analyze task, create development.md with implementation plan
- **D1**: Implement solution following the plan
- **D2**: Run code formatter on modified files (pre-D3 check)
- **D3**: Verify build passes, complete implementation notes

### QA (Q) - test-automator
- **Q0**: Analyze requirements, discover existing tests, create test plan
- **Q1**: Implement/update tests, execute test suite
- **Q2**: Handle test failures (retry or escalate)
- **Q3**: All tests pass, document results

### Documentation (W) - docs-architect
- **W0**: Analyze artifacts, discover documentation needing updates
- **W1**: Update code docs, README, ARCHITECTURE files
- **W3**: All documentation updated

### Finalization (F) - project-manager
- Review all artifacts, run final builds/tests
- Create complete.md, release.md
- **F3**: Technical complete

### Stakeholder (S) - stakeholder
- Final acceptance review
- **S3**: Task complete (terminal state)

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

Each stage can retry up to 3 times:

```typescript
{ content: "D2: Development (retry 2/3)", status: "in_progress", activeForm: "Retrying after error" }
```

### Escalation Chain

After 3 retries, escalate to previous stage:

```
S → F → Q → D → T → A → P → USER
```

## task-state.json Structure

```json
{
  "task_id": "20250102-example-task",
  "title": "Example Task",
  "created_date": "2025-01-02T10:00:00Z",
  "updated_date": "2025-01-02T10:30:00Z",
  "execution_mode": "async",
  "priority": "medium",
  "platform": "all",
  "dependencies": [],
  "blockers": [],

  "state": {
    "current": "development:executing",
    "previous": "teamlead:done",
    "statusCode": "1",
    "agent": "D",
    "transitions": []
  },

  "retries": {
    "P": 0, "A": 0, "T": 0, "D": 0, "Q": 0, "W": 0, "F": 0, "S": 0,
    "max": 3
  },

  "approvals": {},
  "escalations": [],

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
| Code Format | D3 (before marking complete) |
| Build | D3 → Q1 |
| Tests | Q3 → W1 |
| Code Review | D3 → Q1 |

## Execution Modes

### Async (Default)
Tasks run independently, no waiting.

### Sync
Tasks wait for dependencies to complete (F3 or S1):

```json
{
  "execution_mode": "sync",
  "dependencies": ["20250114-database-setup"]
}
```

## Best Practices

### DO
- Create task folder before any work
- Initialize TodoWrite at task start
- Update TodoWrite at every stage transition
- Keep task-state.json synchronized
- Document errors in error.md (for escalation scenarios)
- Check dependencies before starting

### DON'T
- Skip state transitions
- Forget to update TodoWrite
- Bypass approval gates (standard workflow)
- Create circular dependencies
- Ignore rule check failures

## When to Use Workflow

| Use Full Workflow | Skip Workflow |
|-------------------|---------------|
| Multiple files/modules affected | Single-file edit |
| New feature or multi-step fix | Typo, rename, docs tweak |
| Security/permissions involved | One small test |
| Cross-team coordination needed | Mechanical change |
