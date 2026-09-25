---
name: sprint
description: Plan sprint with capacity analysis, task breakdown, and resource allocation
argument-hint: '[<sprint name or number>] [--capacity <points>] [--from-backlog <file>] [--duration 1|2|3|4] [--export]'
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/project-manager.md
  - skills/estimation-methodology/references/estimate-review.md
  - commands/docs-release-notes.md
  - commands/roadmap.md
  - commands/estimate.md
---

# Sprint Plan Command

Plan sprint with capacity analysis, task breakdown, and resource allocation.

## Options

| Option | Values | Purpose |
|--------|--------|---------|
| `<sprint name or number>` | text | Sprint ID for the plan title (`Sprint Plan: Sprint {ID}`) |
| `--capacity <points>` | — | Team capacity in story points |
| `--from-backlog <file>` | — | Import items from a backlog file |
| `--duration <weeks>` | `1`, `2`, `3`, `4` | Sprint length in weeks (default: `2`) |
| `--export` | — | Also write the plan to `.context/sprint-<ID>.md` (`<ID>` = the sprint name or number, else the start date `YYYYMMDD`), the only file this command creates |

```
/sprint [<sprint name or number>] [--capacity <points>] [--from-backlog <file>] [--duration 1|2|3|4] [--export]
/sprint
/sprint 14 --capacity 40 --duration 2
/sprint --from-backlog backlog.md
/sprint --capacity 30 --export
```

## Output Format

Emit in this order: overview, goals, capacity, backlog, daily breakdown, dependencies, risks, definition of done, ceremonies, notes. Point estimates are Min/Max pairs throughout — commit to Min, stretch to Max.

### Overview, goals, capacity

```markdown
# Sprint Plan: Sprint {ID}

## Sprint Overview
| Attribute | Min | Max |
|-----------|-----|-----|
| Duration | Jan 13 - Jan 24 (2 weeks) | |
| Team Capacity | 36 SP | 40 SP |
| Committed | 30 SP | 38 SP |
| Buffer | 2 points (5%) | 2 points (5%) |

## Goals
### Sprint Goals — 2-4 outcome statements
### Success Criteria — checkbox list, measurable, one per goal

## Capacity Planning
### Team Capacity
Per member: Available Days | Capacity Min | Capacity Max | Notes (PTO,
conference, part-time), closing on a bold Total row.

### Allocation
| Category | Pts Min | Pts Max | % | Notes |
|----------|---------|---------|---|-------|
| Features | 22 | 28 | 70% | Sprint goals |
| Tech Debt | 5 | 6 | 15% | Prioritized items |
| Bugs | 3 | 4 | 10% | Critical only |
| Buffer | 2 | 2 | 5% | Unexpected work |
```

### Backlog and schedule

~~~markdown
## Sprint Backlog

### Features (22-28 pts)
| ID | Story | SP Min | SP Max | Assignee | Priority |
|----|-------|--------|--------|----------|----------|
| FEAT-101 | SSO: Okta integration | 5 | 8 | Alice | P0 |

Same columns for `### Tech Debt (5-6 pts)` (TD-nnn) and `### Bugs (3-4 pts)` (BUG-nnn).

## Daily Breakdown
One table per week — Day | Focus | Key Activities. Week 1 Monday is sprint
start (planning); the final Friday is demo, retro, release prep.

## Dependencies
Indented tree, blocker above dependent:

```
FEAT-101 (SSO Okta)
    └── FEAT-102 (SSO Azure AD) - shares auth infrastructure
```

## Risks
Table Risk | Probability | Impact | Mitigation — top 3-5 only.
Score each risk per `skills/estimation-methodology/references/estimate-review.md § Risk Scoring`.
~~~

### Closing sections

```markdown
## Definition of Done
- [ ] Code complete and reviewed
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] Documentation updated
- [ ] QA approved
- [ ] No critical/high bugs

## Ceremonies
Table Ceremony | When | Duration — planning 2h, daily standup 15m,
mid-sprint backlog refinement 1h, review 1h, retrospective 1h.

## Notes
Who leads which workstream, who is pairing, who absorbs bugs and tech debt.
```

## Capacity Guidelines

| Team Size | 2-week Capacity Min | 2-week Capacity Max | Buffer |
|-----------|---------------------|---------------------|--------|
| 3 devs | 18 pts | 30 pts | 3 pts |
| 5 devs | 30 pts | 50 pts | 5 pts |
| 7 devs | 42 pts | 70 pts | 7 pts |
