# Orchestrator & Workspace Schemas

## Orchestrator State (Required Schema)

### Orchestrator (version 3.1)

> v3.1 adds the dependency DAG. `configuration.parallel_tracks` is orchestrator-derived at init
> (`min(count(ready issues), 5)`, reduced by disk capacity; single explicit issue ⇒ 1), not
> user-supplied — the literal below is an illustrative recorded runtime value. `group` is
> `milestone-{N}` (milestone mode) or `issues-{shortid}` (array mode).

#### Top-level fields

```json
{
  "version": "3.1",
  "group": "milestone-1",
  "milestone": { "number": 1, "title": "Sprint 1" },
  "configuration": {
    "parallel_tracks": 2,
    "isolation": "worktree"
  },
  "base_branch": "develop",
  "created_at": "2026-06-22T10:00:00Z",
  "topological_order": [41, 42, 57, 60],
  "dependency_warnings": [
    { "issue": 42, "external_dependency": 99, "note": "#99 not in resolved set — not gating" }
  ],
```

#### `issues[]` — completed entry (example)

```json
  // …continued: issues[] array of the same orchestrator.json
  "issues": [
    {
      "number": 41,
      "title": "feat: Core theme system",
      "priority": "P0",
      "status": "completed",
      "track": 1,
      "level": 0,
      "blocked_by": [],
      "blocks": [42, 57],
      "external_dependencies": [],
      "current_stage": "ST",
      "branch": "feature/41-core-theme-system",
      "workspace": ".worktrees/milestone-1/41",
      "isolation": "worktree",
      "pr": "https://github.com/owner/repo/pull/120"
    },
```

#### `issues[]` — blocked entry (example)

```json
    // …continued: second issues[] entry
    {
      "number": 60,
      "title": "feat: Settings integration",
      "priority": "P2",
      "status": "blocked",
      "track": null,
      "level": 2,
      "blocked_by": [42, 57],
      "blocks": [],
      "external_dependencies": [],
      "current_stage": null,
      "branch": null,
      "workspace": ".worktrees/milestone-1/60",
      "isolation": "worktree"
    }
  ],
```

#### `tracks` & `progress`

```json
  // …continued: closing keys of the same orchestrator.json
  "tracks": {
    "1": { "issue_number": 41, "task_prefix": "t1" },
    "2": { "issue_number": null, "status": "available" }
  },
  "progress": {
    "total": 4,
    "completed": 1,
    "in_progress": 0,
    "ready": 0,
    "blocked": 3,
    "failed": 0
  }
}
```

#### DAG field contract — per-issue fields

| Field | Type | Meaning |
|-------|------|---------|
| `issues[].blocked_by` | `int[]` | Issue numbers that must be `completed` before this issue starts. Mutated at runtime: the monitor removes a number when its issue completes. |
| `issues[].blocks` | `int[]` | Reverse edges — issues this one blocks. Informational (handy for the R1 summary and audits); the runtime unblock works purely by subtracting the completed issue from each dependent's `blocked_by[]`, so the monitor never needs to read `blocks`. |
| `issues[].level` | `int` | Topological wave (0 = no blockers). Upper bound on when it can start, not a barrier. |
| `issues[].external_dependencies` | `int[]` | Declared `Depends on` targets outside the resolved set — surfaced, not gating. |

#### DAG field contract — top-level fields

| Field | Type | Meaning |
|-------|------|---------|
| `topological_order` | `int[]` | Deterministic priority-respecting topological order from Kahn's algorithm. |
| `dependency_warnings` | `object[]` | External-dependency and dropped-self-edge notes for the R1 summary. |

`status ∈ {pending, blocked, ready, in_progress, completed, failed, skipped, skipped_has_pr}`.

## Workspace State

### Workspace (version 2.0)

```json
{
  "version": "2.0",
  "isolation": "worktree",
  "issue": { "number": 42, "title": "Add login flow", "labels": ["feature", "P1"] },
  "git": {
    "branch_name": "feature/42-add-login-flow",
    "base_branch": "develop",
    "base_branch_source": "develop_fallback",
    "worktree_path": ".worktrees/milestone-1/42"
  },
  "worktask": { "track": 1, "task_prefix": "t1", "complexity_score": 18 },
  "dependency": { "blocked_by": [41], "blocks": [60] },
  "execution": { "current_stage": "DV", "retry_count": 0, "status": "in_progress", "pr": null },
  "task_ids": { "PL": "t1-1", "AR": "t1-2", "DV": "t1-3", "DR": "t1-4", "QA": "t1-5" }
}
```

#### Completion contract

**Completion contract (read by `hooks/megatask-monitor.sh`).** The per-issue worktask MUST write its
terminal outcome into `workspace.json.execution`:

| Field | Written by | Values | Read by |
|-------|-----------|--------|---------|
| `execution.status` | the per-issue FN/ST stage (`agents/project-manager.md § FN Stage`), or the per-issue orchestrator when parking on escalate-class questions (`commands/worktask.md § Step A.4 Escalation guard`) | `in_progress` (default) → `completed` (PR created) \| `failed` (max retries, or parked escalation) | `hooks/megatask-monitor.sh` — the reconciliation sweep marks the orchestrator issue and unblocks dependents |
| `execution.reason` | the per-issue orchestrator on parking only | `"parked_escalation"` (absent otherwise) | the batch summary — distinguishes a parked issue from a genuine failure |
| `execution.pr` | the per-issue FN stage on PR creation | PR URL (`null` until then) | recorded onto `orchestrator.json issues[].pr` |

The monitor hook is idempotent: it acts only on `in_progress` orchestrator issues whose `workspace.json`
reports `status ∈ {completed, failed}`, so re-firing on later SubagentStops is a no-op. Until FN (or
the Step A.4 parking guard) writes `status`, the issue stays `in_progress` and its dependents stay
`blocked`.
