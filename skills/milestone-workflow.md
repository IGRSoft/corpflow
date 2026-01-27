# Milestone Workflow

**Category**: Task Management
**Priority**: High
**Applies to**: All milestone-based workflows

## Purpose

This skill defines how the workflow system integrates with GitHub milestones to execute issues by priority.

## Parameter Format

```
--milestone:N              # Execute all open issues in milestone N by priority
--milestone:N:ISSUE        # Execute specific issue ISSUE from milestone N only
--parallel:N               # Run N issues in parallel (default: 2, max: 5)
--auto-continue            # Skip per-issue approval gates (trusted workflows)
```

## GitHub CLI Commands

```bash
# Fetch milestone metadata
gh api /repos/{owner}/{repo}/milestones/{N}

# Fetch all open issues in milestone
gh api "/repos/{owner}/{repo}/issues?milestone={N}&state=open&per_page=100"

# Fetch specific issue
gh api /repos/{owner}/{repo}/issues/{ISSUE}
```

## Milestone Context File

**Location:** `.context/milestone.json`

```json
{
  "version": "1.0",
  "fetched_at": "2025-01-27T12:00:00Z",
  "milestone": {
    "number": 1,
    "title": "Sprint 1",
    "description": "...",
    "state": "open",
    "due_on": "2025-02-01T00:00:00Z",
    "html_url": "https://github.com/owner/repo/milestone/1"
  },
  "issues": [
    {
      "number": 42,
      "title": "Implement login flow",
      "state": "open",
      "priority": 1,
      "priority_label": "P1",
      "slug": "implement-login-flow",
      "branch_name": "feature/42-implement-login-flow",
      "labels": ["feature", "P1"],
      "body_preview": "As a user, I want to login...",
      "status": "pending"
    }
  ],
  "execution": {
    "parallel_tracks": 2,
    "active_issues": [],
    "current_issue": null,
    "completed_issues": [],
    "pending_issues": [42],
    "started_at": null,
    "auto_continue": false
  },
  "summary": {
    "total_issues": 1,
    "completed": 0,
    "pending": 1
  }
}
```

### Issue Status Values

- `pending` - Not yet started
- `in_progress` - Currently being worked on
- `completed` - PR created, issue done
- `skipped` - Manually skipped by user

## Priority Sorting

Issues are sorted by priority labels before execution:

**Priority Order (highest first):**
1. `P0` or `priority:critical`
2. `P1` or `priority:high`
3. `P2` or `priority:medium`
4. `P3` or `priority:low`
5. No priority label (lowest)

**Sorting Algorithm:**
```typescript
const priorityOrder = {
  'P0': 0, 'priority:critical': 0,
  'P1': 1, 'priority:high': 1,
  'P2': 2, 'priority:medium': 2,
  'P3': 3, 'priority:low': 3
};

issues.sort((a, b) => {
  const aPriority = Math.min(...a.labels.map(l => priorityOrder[l.name] ?? 99));
  const bPriority = Math.min(...b.labels.map(l => priorityOrder[l.name] ?? 99));
  return aPriority - bPriority;
});
```

## Branch Naming Convention

**Format:** `feature/{issue#}-{slug}`

**Slug Generation Rules:**
1. Lowercase title
2. Replace spaces with hyphens
3. Remove special characters (except hyphens)
4. Truncate to 50 characters max
5. Remove trailing hyphens

**Examples:**
| Issue # | Title | Branch |
|---------|-------|--------|
| 42 | Implement login flow | `feature/42-implement-login-flow` |
| 43 | Fix password reset | `feature/43-fix-password-reset` |
| 44 | [URGENT] Fix critical bug!!! | `feature/44-urgent-fix-critical-bug` |

## Execution Flow

### All Issues Mode: `/workflow --milestone:N`

```
1. FETCH MILESTONE
   gh api /repos/{owner}/{repo}/milestones/N
   gh api "/repos/{owner}/{repo}/issues?milestone=N&state=open"

2. CREATE MILESTONE.JSON
   - Sort issues by priority
   - Generate branch names and slugs
   - Set pending_issues array
   - Set parallel_tracks from --parallel:N (default: 2)
   - Set auto_continue from --auto-continue flag

3. FOR EACH ISSUE (by priority):
   a. Create branch: feature/{issue#}-{slug}
   b. Update current_issue in milestone.json
   c. Run workflow stages (P → ... → Q)
   d. Create PR linking to issue (Closes #N)
   e. Move issue to completed_issues
   f. [APPROVAL GATE] Unless --auto-continue:
      - STOP AND ASK: "Issue #N complete. Continue to next? [Y/n/skip]"
      - Wait for user confirmation
   g. Proceed to next pending issue

4. COMPLETION
   - All open issues processed
   - PRs created for each
```

### Per-Issue Approval Gate

**DEFAULT BEHAVIOR**: Stop between issues for user approval.

```typescript
// After completing issue, before starting next:
TaskCreate({
  subject: "Issue Gate: #42 → #43",
  metadata: {
    completed_issue: 42,
    next_issue: 43,
    requires_approval: true
  }
});

// STOP AND ASK: "Issue #42 complete. Continue to #43? [Y/n/skip]"
// Wait for user response:
// - Y/yes → Continue to next issue
// - n/no → Stop milestone execution
// - skip → Skip next issue, continue to following
```

**`--auto-continue` flag**: Skip approval gates for trusted workflows.

### Multi-Issue Parallelism: `--parallel:N`

Default is 2 parallel tracks (max 5). Run multiple issues concurrently:

```
Milestone Setup: P(prep) for all issues
├─ Track 1: Issue #42 (P0) → P → A → D → Q
├─ Track 2: Issue #43 (P1) → P → A → D → Q
├─ Track 3: Issue #44 (P1) → P → A → D → Q  (with --parallel:3+)
├─ Track 4: Issue #45 (P2) → P → A → D → Q  (with --parallel:4+)
└─ Track 5: Issue #46 (P2) → P → A → D → Q  (with --parallel:5)
Final: Merge PRs in priority order
```

**Extended milestone.json for parallel execution:**

```json
{
  "execution": {
    "parallel_tracks": 5,
    "active_issues": [42, 43, 44, 45, 46],
    "tracks": {
      "track_1": { "issue": 42, "stage": "D", "task_prefix": "t1" },
      "track_2": { "issue": 43, "stage": "A", "task_prefix": "t2" },
      "track_3": { "issue": 44, "stage": "P", "task_prefix": "t3" },
      "track_4": { "issue": 45, "stage": "P", "task_prefix": "t4" },
      "track_5": { "issue": 46, "stage": "P", "task_prefix": "t5" }
    },
    "completed_issues": [],
    "pending_issues": [47, 48]
  }
}
```

**Task ID prefixing for parallel tracks:**
- Track 1: task IDs `t1-1`, `t1-2`, etc.
- Track 2: task IDs `t2-1`, `t2-2`, etc.
- Track 3-5: task IDs `t3-1`, `t4-1`, `t5-1`, etc.

**Time savings:**
| Tracks | 5 issues | Time | Savings |
|--------|----------|------|---------|
| 1 (sequential) | 5 × 1h = 5h | 5 hours | — |
| 2 (default) | 3 × 1h = 3h | 3 hours | 40% |
| 5 (max) | 1 × 1h = 1h | 1 hour | 80% |

### Single Issue Mode: `/workflow --milestone:N:ISSUE`

```
1. FETCH MILESTONE + SPECIFIC ISSUE
   gh api /repos/{owner}/{repo}/milestones/N
   gh api /repos/{owner}/{repo}/issues/ISSUE

2. VALIDATE
   - Confirm issue.milestone.number === N
   - Error if issue not in milestone

3. CREATE MILESTONE.JSON
   - Single issue in issues array
   - Set current_issue to ISSUE

4. EXECUTE SINGLE ISSUE
   a. Create branch: feature/{ISSUE}-{slug}
   b. Run workflow stages (P → ... → Q)
   c. Create PR linking to issue (Closes #ISSUE)

5. COMPLETION
   - Single issue processed
   - PR created
```

## Error Handling

| Error | Handling |
|-------|----------|
| Milestone not found (404) | Error: "Milestone N not found" |
| Issue not found (404) | Error: "Issue ISSUE not found" |
| Issue not in milestone | Error: "Issue ISSUE is not part of milestone N" |
| Rate limit (403) | Retry with backoff, warn user |
| No repo detected | Error: "Not in git repo. --milestone requires GitHub" |
| Invalid format | Error: "Invalid format. Use --milestone:N or --milestone:N:ISSUE" |

## Stage Integration

### P Stage (Planning)

When milestone context exists:
- Read issue body as requirements input
- Use issue labels for type/priority classification
- Reference issue number in planning.md

### D Stage (Development)

When milestone context exists:
- Create feature branch from milestone.json
- Update `execution.current_issue`
- Reference issue in commit messages (`#N`)

### F Stage (Finalization)

When milestone context exists:
- Create PR with "Closes #N" in body
- Update issue status to `completed`
- Move to next pending issue (if any)

## Related

- [Workflow Command](../commands/workflow.md) - Main workflow command
- [Workflow System](workflow.md) - Core workflow documentation
- [Task Folder Organization](task-folder-organization.md) - Folder structure
