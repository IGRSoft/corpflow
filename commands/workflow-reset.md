# Workflow Reset Command

Reset stuck workflow to specific stage or clean state.

## Usage

```
/workflow-reset
/workflow-reset --to <stage>
/workflow-reset --clean
```

## Options

- `--to <stage>` - Reset to specific stage (P, A, T, D, Q, W, F, S)
- `--clean` - Full reset, remove all artifacts
- `--preserve-artifacts` - Keep files, reset state only
- `--force` - Skip confirmation

## Examples

```
/workflow-reset
/workflow-reset --to D
/workflow-reset --clean --force
```

## Output Format

### Interactive Reset
```markdown
# Workflow Reset

## Current State
- **Stage**: D2 (Development - Error, statusCode: "2")
- **Retries**: 3/3 (Max reached)
- **Issue**: Build failure after escalation

**Status Code Reference**: 0=preparing, 1=executing, 2=error, 3=done

## Reset Options

1. **Reset to D1** - Retry development from start (statusCode: "1" = executing)
2. **Reset to T1** - Go back to Team Lead coordination
3. **Reset to A1** - Re-architecture the solution
4. **Reset to P1** - Start over from planning
5. **Clean Reset** - Remove all artifacts, fresh start

**Shorthand**: `{STAGE}{CODE}` - e.g., D1 = Development:executing, T1 = TeamLead:executing

## Recommendation
Given 3 failed retries with build errors, recommend:
- Option 2 (Reset to T1) to review approach with Team Lead

Select option [1-5]:
```

### Reset to Stage
```markdown
# Workflow Reset to D1

## Pre-Reset State
Shorthand: **D2** (Development:error)
```json
{
  "current": "development:error",
  "statusCode": "2",
  "agent": "D",
  "retries": { "4": 3 }
}
```
Note: `retries` uses task ID ("4") as key, not stage code

## Actions Taken
1. ✅ Reset stage to D1 (Development - Executing)
2. ✅ Reset retry counter for D stage
3. ✅ Updated Task System
4. ✅ Preserved existing artifacts
5. ✅ Logged reset in transitions

## Post-Reset State
Shorthand: **D1** (Development:executing)
```json
{
  "current": "development:executing",
  "statusCode": "1",
  "agent": "D",
  "retries": { "4": 0 }
}
```

## Task System Updated
```typescript
// Tasks after reset
TaskList()
// Returns:
[
  { taskId: "1", subject: "P: Planning", status: "completed" },
  { taskId: "2", subject: "A: Architecture", status: "completed" },
  { taskId: "3", subject: "T: Team Lead", status: "completed" },
  { taskId: "4", subject: "D: Development", status: "in_progress" },  // Reset
  { taskId: "5", subject: "Q: QA Testing", status: "pending" },
  { taskId: "6", subject: "W: Documentation", status: "pending" },
  { taskId: "7", subject: "F: Finalization", status: "pending" },
  { taskId: "8", subject: "S: Stakeholder", status: "pending" }
]
```

## Next Steps
1. Review error.md for previous failure context
2. Address root cause before retrying
3. Continue development with fresh retry counter
```

### Clean Reset
```markdown
# Clean Workflow Reset

## Warning
This will remove all workflow artifacts and start fresh.

## Files to Remove
- [ ] .context/task-state.json
- [ ] .context/planning.md
- [ ] .context/analyzing.md
- [ ] .context/development.md
- [ ] .context/testing.md
- [ ] .context/error.md

## Preserved
- [ ] .context/images/ (user assets)

Proceed? [y/N]

---

## Reset Complete

All workflow state cleared. To start new workflow:
```
/workflow "Your task description"
```
```

## Reset Scenarios

### Scenario 1: Build Failure Loop
```
Current: D2 (3/3 retries)
Problem: Dependency conflict causing build failures
Action: Reset to A1 to reconsider architecture
```

### Scenario 2: Wrong Approach
```
Current: Q2 (tests failing)
Problem: Implementation doesn't match requirements
Action: Reset to P1 to clarify requirements
```

### Scenario 3: External Blocker Resolved
```
Current: T1 (blocked on dependency)
Problem: Dependency was blocking, now resolved
Action: Reset to T1 to re-evaluate and continue
```

### Scenario 4: Scope Change
```
Current: D1 (mid-development)
Problem: Stakeholder changed requirements
Action: Reset to P1 with new requirements
```

## Stage Reset Matrix

| Reset To | Clears | Preserves |
|----------|--------|-----------|
| P | All stages | Nothing |
| A | A, T, D, Q, W, F, S | P stage artifacts |
| T | T, D, Q, W, F, S | P, A artifacts |
| D | D, Q, W, F, S | P, A, T artifacts |
| Q | Q, W, F, S | P, A, T, D artifacts |
| W | W, F, S | P, A, T, D, Q artifacts |
| F | F, S | P, A, T, D, Q, W artifacts |
| S | S | All previous artifacts |

## Safety Features

- **Confirmation Required**: Unless --force is used
- **Artifact Backup**: Creates .backup/ before clean reset
- **Audit Trail**: All resets logged in transitions
- **Retry Reset**: Only resets counter for target stage

## Integration

This command supports:
- `/workflow-debug` - Diagnose before reset
- `/workflow` - Start fresh after clean reset
- [workflow-engineer](../agents/workflow-engineer.md) - Complex recoveries

## Related

- [workflow-engineer](../agents/workflow-engineer.md) - Workflow expertise
- [workflow-debug](./workflow-debug.md) - Diagnostics
- [workflow](./workflow.md) - Initialize workflow
