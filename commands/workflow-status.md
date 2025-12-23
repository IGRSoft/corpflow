# Workflow Status Command

Display the current status of a workflow task including stage, progress, and any blockers.

## Usage

```
/workflow-status [task-id]
```

If `task-id` is omitted, shows status of the most recent active task.

## Examples

```
/workflow-status
/workflow-status 20251223-add-dark-mode
```

## Output Format

```markdown
## Task Status: Add Dark Mode Support

**Task ID**: 20251223-add-dark-mode-support
**Current Stage**: D1 (Development - Executing)
**Progress**: 4/8 stages complete

### Stage Summary
| Stage | Status | Agent |
|-------|--------|-------|
| P Planning | Completed | project-manager |
| A Architecture | Completed | architect-review |
| T Team Lead | Completed | team-lead |
| D Development | In Progress | swift-pro |
| Q QA Testing | Pending | test-automator |
| W Documentation | Pending | docs-architect |
| F Finalization | Pending | project-manager |
| S Stakeholder | Pending | stakeholder |

### Blockers
- None

### Dependencies
- None

### Recent Transitions
- T3 → D1: 2025-12-23T14:30:00Z
- A3 → T1: 2025-12-23T14:15:00Z
- P3 → A1: 2025-12-23T14:00:00Z (Approved by user)
```

## Status Codes

| Code | Meaning | TodoWrite Status |
|------|---------|------------------|
| X0 | Preparing | pending |
| X1 | Executing | in_progress |
| X2 | Error (retry N/3) | in_progress |
| X3 | Done | completed |

## Error States

When a stage is in error state (X2):

```markdown
### Current Error

**Stage**: D2 (Development - Error)
**Retry**: 2/3
**Issue**: Build failure - missing dependency

**Attempted Solutions**:
1. Added missing import (failed)
2. Updated package version (in progress)

**Next Action**: If retry 3 fails, escalate to Team Lead (T)
```

## Escalation Chain

Shows the escalation path if current stage fails:

```
Current: D (Development)
Escalation: D → T → A → P → USER
```

## Related

- [Workflow System](../skills/workflow.md) - Complete workflow documentation
- [workflow-engineer](../agents/workflow-engineer.md) - Troubleshooting
