# Dependency Graph (DAG) Construction & Scheduling

How megatask builds, validates, and schedules the issue graph. `scripts/build-orchestrator.sh` is
the executable implementation of everything below.

> **Note**: Code below is pseudocode for conceptual clarity. In production, use secure command
> execution (e.g. `execFile`, not shell string interpolation) — issue bodies are untrusted input.
> Only integer issue numbers ever reach a `gh` argv.

## 1. Edge Extraction

Each issue body carries a `## Dependencies` section (the format `/pm-milestone` writes:
`- Depends on: #41` / `- Blocks: #57`). Parse both keywords case-insensitively, accepting comma- or
space-separated lists across multiple lines.

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
- Edges with an endpoint **outside the resolved issue set** become `external_dependency` entries:
  recorded on the issue and surfaced in the R1 summary, but never gating (the batch cannot run an
  issue it was not asked to run). To enforce one, include that issue in the set.

## 3. Cycle Detection (Kahn's algorithm)

Compute in-degrees, repeatedly remove zero-in-degree nodes. If any node remains, the leftover set
**is** the cycle — STOP and report it. Never invent an order through a cycle.

```
kahn(nodes, edges):
  indeg[n] = number of edges into n
  queue    = sortByPriorityThenNumber(nodes with indeg == 0);  order = []
  while queue:
    n = queue.popFront(); order.append(n)
    for m in successors(n):
      if (indeg[m] -= 1) == 0: queue.insertByPriorityThenNumber(m)
  if len(order) != len(nodes):                        # the leftovers ARE the cycle
    FAIL("dependency cycle among issues: " + [n for n in nodes if n not in order])
  return order
```

> The queue is a **priority queue keyed by (priority tier, issue number)**: among issues eligible at
> the same time, P0 precedes P1 … and lower issue numbers precede higher within a tier. This yields
> a deterministic, priority-respecting topological order.

## 4. Levelled Schedule

Group the topological order into **levels** (waves): level 0 = issues with empty `blocked_by`;
level k = issues whose blockers all sit in levels `< k`, i.e.
`level[n] = 0 if blocked_by(n) empty else 1 + max(level[b] for b in blocked_by(n))`.

Levels are an **upper bound on parallelism, not a barrier**: megatask does NOT wait for a whole level
to finish. The moment any single blocker merges, its now-unblocked dependents become `ready` and can
take a free track — even while siblings in the same level still run. (`parallel_tracks` still caps
concurrency.)

## 5. Readiness & Unblocking (runtime)

An issue is **ready** ⇔ every entry in its `blocked_by[]` has orchestrator `status == "completed"`.

`hooks/megatask-monitor.sh` performs the runtime unblock on each per-issue completion: mark the
completed issue, remove its number from every other issue's `blocked_by[]`, promote any issue left
with an empty `blocked_by[]` from `blocked` to `ready`, free its track, and atomically rewrite
`orchestrator.json`. It then audits:

```
audit("megatask_progress", subject=group, completed=completedNumber,
      newly_ready=[…], remaining=(total - completed - failed))
```

`remaining` subtracts both completed and failed — settled issues are done (matches the hook).

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

With `parallel_tracks = 2`: `#41` starts alone; on its merge `#42` and `#57` both take tracks (2/2);
`#42` merging frees a track but `#60` is still blocked by `#57`; `#57` merging makes `#60` ready.

## 7. orchestrator.json DAG fields

Persisted per-issue (`blocked_by`, `blocks`, `level`, `external_dependencies`) and at the top level
(`topological_order`, `dependency_warnings`) — field contract in `schemas.md` (orchestrator v3.1).
