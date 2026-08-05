# Dependency Graph (DAG) Construction & Scheduling

Megatask executes issues as a directed acyclic graph, not a flat priority list. This reference
specifies how the graph is built, validated, and scheduled.

> **Note**: Code below is pseudocode for conceptual clarity. In production, use secure command
> execution (e.g. `execFile`, not shell string interpolation) — issue bodies are untrusted input.
> Only integer issue numbers ever reach a `gh` argv.

## 1. Edge Extraction

Each issue body carries a `## Dependencies` section (the format `/pm-milestone` writes):

```markdown
## Dependencies

- Depends on: #41 (if applicable)
- Blocks: #57 (if applicable)
```

Parse, case-insensitively, two relationship keywords. Accept comma- or space-separated lists and
multiple lines:

| Keyword (regex, case-insensitive) | Produces |
|-----------------------------------|----------|
| `Depends on:` / `Depends-on:` / `Blocked by:` `#(\d+)` | edge `thisIssue.blocked_by += N` |
| `Blocks:` / `Blocked:` `#(\d+)` | edge `N.blocked_by += thisIssue` (reverse) |

### Extraction pseudocode

```
extractEdges(issue):
  deps   = regexAll(issue.body, /(?:depends[ -]on|blocked[ -]by)\s*:?\s*((?:#\d+[,\s]*)+)/i)
  blocks = regexAll(issue.body, /blocks?\s*:?\s*((?:#\d+[,\s]*)+)/i)
  for n in numbers(deps):   addEdge(from=n, to=issue.number)        # n must finish before issue
  for m in numbers(blocks): addEdge(from=issue.number, to=m)        # issue must finish before m
```

An edge `from=A, to=B` means **A must complete before B starts** (B `blocked_by` A).

## 2. Normalization

- `A Blocks B` and `B Depends on A` are the same edge `A→B` — collapse duplicates.
- Self-edges (`A depends on A`) are dropped with a warning.
- Edges whose endpoint is **outside the resolved issue set** become `external_dependency` entries:
  recorded on the issue, surfaced in the R1 summary, but they do **not** gate scheduling (the batch
  cannot run an issue it was not asked to run). If you want them enforced, include that issue in the set.

```
normalize(edges, resolvedSet):
  edges = dedupe(edges)
  edges = drop(e where e.from == e.to)              # warn on self-edge
  external = [e for e in edges if e.from ∉ resolvedSet or e.to ∉ resolvedSet]
  internal = [e for e in edges if e.from ∈ resolvedSet and e.to ∈ resolvedSet]
  return internal, external
```

## 3. Cycle Detection (Kahn's algorithm)

Compute in-degrees, repeatedly remove zero-in-degree nodes. If any node remains, the leftover set
**is** the cycle — STOP and report it. Never invent an order through a cycle.

```
kahn(nodes, edges):
  indeg = { n: 0 for n in nodes }
  for e in edges: indeg[e.to] += 1
  queue = sortByPriorityThenNumber([n for n in nodes if indeg[n] == 0])
  order = []
  while queue:
    n = queue.popFront()
    order.append(n)
    for m in successors(n):
      indeg[m] -= 1
      if indeg[m] == 0: queue.insertByPriorityThenNumber(m)
  if len(order) != len(nodes):
    cycle = [n for n in nodes if n not in order]
    FAIL("dependency cycle among issues: " + cycle)   # megatask STOPs
  return order
```

### Queue ordering

> The queue is a **priority queue keyed by (priority tier, issue number)** so that, among issues
> that become eligible at the same time, P0 precedes P1 … and lower issue numbers precede higher
> within a tier. This yields a deterministic, priority-respecting topological order.

## 4. Levelled Schedule

For parallel execution, group the topological order into **levels** (a.k.a. waves):

- **Level 0**: issues with empty `blocked_by` — start immediately.
- **Level k**: issues all of whose blockers are in levels `< k`.

```
levels(nodes, edges):
  level = {}
  for n in topoOrder:
    level[n] = 0 if blocked_by(n) is empty
               else 1 + max(level[b] for b in blocked_by(n))
  return groupBy(level)
```

Levels are an **upper bound on parallelism**, not a barrier: megatask does NOT wait for a whole level
to finish. The moment any single blocker merges, its now-unblocked dependents become `ready` and can
take a free track — even while siblings in the same level are still running. (Track count still caps
concurrency at `parallel_tracks`.)

## 5. Readiness & Unblocking (runtime)

An issue is **ready** ⇔ every entry in its `blocked_by[]` has orchestrator `status == "completed"`.

The monitor hook (`hooks/megatask-monitor.sh`) performs the runtime unblock on each per-issue
completion:

```
onIssueCompleted(group, completedNumber):
  orch = readJson(.worktrees/<group>/orchestrator.json)
  mark(orch, completedNumber, status="completed")
  for issue in orch.issues:
    issue.blocked_by = remove(issue.blocked_by, completedNumber)
    if issue.status == "blocked" and issue.blocked_by is empty:
      issue.status = "ready"
  freeTrackOf(orch, completedNumber)
  writeJsonAtomic(orch)
  // remaining = total - completed - failed  (settled issues are done; matches hooks/megatask-monitor.sh)
  audit("megatask_progress", subject=group, completed=completedNumber,
        newly_ready=[…], remaining=(total - completed - failed))
```

### Failed blockers

A **failed** blocker is NOT removed from dependents' `blocked_by[]` — its dependents stay `blocked`
permanently and are reported to the user (retry the blocker, drop the edge, or re-scope).

## 6. Worked Example

Issues (priority): `#41 P0`, `#42 P1`, `#57 P1`, `#60 P2`. Bodies declare:
`#42 Depends on #41`, `#57 Depends on #41`, `#60 Depends on #42, #57`.

```
Edges:  41→42, 41→57, 42→60, 57→60
Levels: L0 = {41}            (P0)
        L1 = {42, 57}        (both P1; FIFO by number: 42 then 57)
        L2 = {60}            (P2)
Topo order (priority queue): 41, 42, 57, 60
```

Execution with `parallel_tracks = 2`:
1. `#41` starts (only ready issue) → 1 track used.
2. `#41` merges → `#42`, `#57` become ready → both take tracks (2/2).
3. `#42` merges → `#60` still blocked by `#57`; track freed but no ready issue except after `#57`.
4. `#57` merges → `#60` ready → takes a track.
5. `#60` merges → done.

## 7. orchestrator.json DAG fields

The DAG is persisted on each issue and at the top level — see `schemas.md` (orchestrator v3.1) for
`issues[].blocked_by`, `issues[].blocks`, `issues[].level`, `issues[].external_dependencies`,
`topological_order`, and `dependency_warnings`.
