# Workflow Debug Command

Diagnose and troubleshoot workflow issues, state inconsistencies, and stage transitions.

## Usage

```
/workflow-debug
/workflow-debug --check [state|todowrite|transitions]
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
| task-state.json | ✅ Valid | Properly formatted |
| TodoWrite | ⚠️ Desync | Mismatch with state |
| Transitions | ✅ Valid | No orphan states |
| Context Folder | ✅ Present | All required files |

---

## Issues Found

### 🔴 Critical Issues

#### TodoWrite State Mismatch
**Problem**: TodoWrite shows D1 but task-state.json shows D3
**Impact**: Workflow progress unclear to user
**Location**: `.context/task-state.json:12`

**task-state.json**:
```json
{
  "state": {
    "current": "development:done",
    "statusCode": "3",
    "agent": "D"
  }
}
```

**TodoWrite**:
```typescript
{ content: "D1: Development", status: "in_progress" }
```

**Fix**: Sync TodoWrite to match task-state.json

### ⚠️ Warnings

#### Missing Transition Log
**Problem**: Transition from A3 to T1 not logged
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
Status: 3 (Done)
Next Expected: Q1 (QA - Executing)
```

### Transition History
| From | To | Timestamp | Notes |
|------|-----|-----------|-------|
| P1 | P3 | 2025-01-10 09:00 | Planning complete |
| P3 | A1 | 2025-01-10 09:15 | User approved |
| A1 | A3 | 2025-01-10 10:00 | Architecture complete |
| A3 | T1 | 2025-01-10 10:05 | ⚠️ Not logged |
| T1 | T3 | 2025-01-10 10:30 | Team lead approved |
| T3 | D1 | 2025-01-10 10:35 | Development started |
| D1 | D2 | 2025-01-10 14:00 | Build error |
| D2 | D1 | 2025-01-10 14:15 | Retry 1 |
| D1 | D3 | 2025-01-10 16:00 | Development complete |

### Expected Next Actions
1. Transition to Q1 (QA Testing)
2. Update TodoWrite to show Q1 in_progress
3. qa-engineer begins test execution

---

## Context Folder Audit

| File | Status | Notes |
|------|--------|-------|
| task-state.json | ✅ | Valid JSON |
| planning.md | ✅ | Complete |
| analyzing.md | ✅ | Complete |
| development.md | ✅ | Complete |
| testing.md | ❌ Missing | Expected for Q stage |
| images/ | ✅ | Directory exists |

---

## TodoWrite Analysis

### Current State
```typescript
todos: [
  { content: "P3: Planning", status: "completed" },      // ✅ Correct
  { content: "A3: Architecture", status: "completed" },  // ✅ Correct
  { content: "T3: Team Lead", status: "completed" },     // ✅ Correct
  { content: "D1: Development", status: "in_progress" }, // ❌ Should be D3, completed
  { content: "Q0: QA Testing", status: "pending" },      // ⚠️ Should be Q1, in_progress
  { content: "W0: Documentation", status: "pending" },   // ✅ Correct
  { content: "F0: Finalization", status: "pending" },    // ✅ Correct
  { content: "S0: Stakeholder", status: "pending" }      // ✅ Correct
]
```

### Recommended Fix
```typescript
TodoWrite({
  todos: [
    { content: "P3: Planning", status: "completed", activeForm: "Planning complete" },
    { content: "A3: Architecture", status: "completed", activeForm: "Architecture complete" },
    { content: "T3: Team Lead", status: "completed", activeForm: "Team lead approved" },
    { content: "D3: Development", status: "completed", activeForm: "Development complete" },
    { content: "Q1: QA Testing", status: "in_progress", activeForm: "Testing solution" },
    { content: "W0: Documentation", status: "pending", activeForm: "Writing documentation" },
    { content: "F0: Finalization", status: "pending", activeForm: "Finalizing release" },
    { content: "S0: Stakeholder", status: "pending", activeForm: "Awaiting approval" }
  ]
});
```

---

## Auto-Fix Results

### Fixes Applied
| Issue | Action | Status |
|-------|--------|--------|
| TodoWrite mismatch | Synced with state | ✅ Fixed |
| Missing transition | Added to log | ✅ Fixed |
| Retry counter | Reset to 0 | ✅ Fixed |

### Manual Actions Required
| Issue | Action Required |
|-------|-----------------|
| Q stage start | Invoke qa-engineer agent |

---

## Prevention Recommendations

1. Always update TodoWrite AND task-state.json together
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
