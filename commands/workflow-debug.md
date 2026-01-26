# Workflow Debug Command

Diagnose and troubleshoot workflow issues, state inconsistencies, and stage transitions.

## Usage

```
/workflow-debug
/workflow-debug --check [state|tasks|transitions]
/workflow-debug --fix
```

## Options

- `--check <type>` - Check specific aspect
- `--fix` - Attempt automatic fixes
- `--verbose` - Show detailed diagnostics
- `--history` - Show transition history

## Examples

```
/workflow-debug
/workflow-debug --check state --verbose
/workflow-debug --fix
```

## Output Format

```markdown
# Workflow Diagnostics

## Health Check

| Component | Status | Details |
|-----------|--------|---------|
| workflow-state.json | ✅ Valid | Properly formatted |
| Task System | ⚠️ Desync | Mismatch with state |
| Transitions | ✅ Valid | No orphan states |
| Context Folder | ✅ Present | All required files |

---

## Issues Found

### 🔴 Critical Issues

#### Task System State Mismatch
**Problem**: Task shows `in_progress` but workflow-state.json shows `completed`
**Impact**: Workflow progress unclear to user
**Location**: `.context/workflow-state.json:12`

**workflow-state.json**:
```json
{
  "state": {
    "current": "development:done",
    "statusCode": "3",
    "agent": "D"
  }
}
```

**Task System**:
```typescript
TaskGet({ taskId: "4" })
// Returns: { status: "in_progress", subject: "D: Development" }
```

**Fix**: Sync Task System to match workflow-state.json

### ⚠️ Warnings

#### Missing Transition Log
**Problem**: Transition from A to T not logged
**Impact**: Audit trail incomplete
**Recommendation**: Add missing transition entry

#### Retry Counter Not Reset
**Problem**: D stage retry counter is 2 but stage completed
**Impact**: May cause incorrect escalation on next error
**Recommendation**: Reset retry counter

---

## State Analysis

### Current State
```
Stage: D (Development)
Status: completed
Next Expected: Q (QA - in_progress)
```

### Transition History
| From | To | Timestamp | Notes |
|------|-----|-----------|-------|
| P | A | 2025-01-10 09:15 | User approved |
| A | T | 2025-01-10 10:05 | ⚠️ Not logged |
| T | D | 2025-01-10 10:35 | Development started |
| D | Q | 2025-01-10 16:00 | Development complete |

### Expected Next Actions
1. Transition to Q (QA Testing)
2. Update task: `TaskUpdate({ taskId: "5", status: "in_progress" })`
3. qa-engineer begins test execution

---

## Context Folder Audit

| File | Status | Notes |
|------|--------|-------|
| workflow-state.json | ✅ | Valid JSON |
| planning.md | ✅ | Complete |
| analyzing.md | ✅ | Complete |
| development.md | ✅ | Complete |
| testing.md | ❌ Missing | Expected for Q stage |
| images/ | ✅ | Directory exists |

---

## Task System Analysis

### Current State
```typescript
TaskList()
// Returns:
[
  { taskId: "1", subject: "P: Planning", status: "completed" },      // ✅ Correct
  { taskId: "2", subject: "A: Architecture", status: "completed" },  // ✅ Correct
  { taskId: "3", subject: "T: Team Lead", status: "completed" },     // ✅ Correct
  { taskId: "4", subject: "D: Development", status: "in_progress" }, // ❌ Should be completed
  { taskId: "5", subject: "Q: QA Testing", status: "pending" },      // ⚠️ Should be in_progress
  { taskId: "6", subject: "W: Documentation", status: "pending" },   // ✅ Correct
  { taskId: "7", subject: "F: Finalization", status: "pending" },    // ✅ Correct
  { taskId: "8", subject: "S: Stakeholder", status: "pending" }      // ✅ Correct
]
```

### Recommended Fix
```typescript
// Fix Development task status
TaskUpdate({ taskId: "4", status: "completed" });

// Start QA task
TaskUpdate({ taskId: "5", status: "in_progress", owner: "qa-engineer" });
```

---

## Auto-Fix Results

### Fixes Applied
| Issue | Action | Status |
|-------|--------|--------|
| Task status mismatch | Synced with state | ✅ Fixed |
| Missing transition | Added to log | ✅ Fixed |
| Retry counter | Reset to 0 | ✅ Fixed |

### Manual Actions Required
| Issue | Action Required |
|-------|-----------------|
| Q stage start | Invoke qa-engineer agent |

---

## Prevention Recommendations

1. Always update Task System AND workflow-state.json together
2. Log transitions immediately after state change
3. Reset retry counters when stage completes successfully
4. Validate state before starting new stage
```

## Common Issues

| Issue | Symptoms | Fix |
|-------|----------|-----|
| State desync | Progress shows wrong | `/workflow-debug --fix` |
| Stuck at P3 | No progress after planning | User must approve |
| Missing files | Stage can't find artifacts | Create required files |
| Infinite retry | Stage keeps failing | Check escalation chain |

## Integration

This command supports:
- `/workflow` - Workflow initialization
- `/workflow-reset` - Reset workflow state
- [workflow-engineer](../agents/workflow-engineer.md) - Troubleshooting

## Related

- [workflow-engineer](../agents/workflow-engineer.md) - Workflow expertise
- [workflow-reset](./workflow-reset.md) - Reset workflow
- [workflow](./workflow.md) - Initialize workflow
