---
name: arch-decision
description: Create or update Architecture Decision Records (ADRs) or Technology Decision Records (TDRs) to document significant technical decisions
argument-hint: <decision topic or context> [--type adr|tdr]
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/software-architector.md
  - agents/technical-lead.md
  - commands/arch-review.md
  - commands/arch-debt.md
---

# Architecture / Technology Decision Record Command

Create or update decision records: Architecture Decision Records (`--type adr`, default) and
Technology Decision Records (`--type tdr`); they differ in scope, owner, and output path — see
§ TDR vs ADR.

## Usage

```
/arch-decision "Decision title"                  # ADR (default)
/arch-decision --type tdr "Decision title"       # TDR
/arch-decision --list
/arch-decision --update <ADR-or-TDR-number>
/arch-decision --type tdr --evaluate "Technology name"
```

## Options

| Option | Values | Effect |
|---|---|---|
| `--type` | `adr` \| `tdr` (default `adr`) | Record type and output directory |
| `--list` | flag | List existing records of that type |
| `--update <number>` | record number | Update an existing record |
| `--supersede <number>` | record number | Create a record superseding another |
| `--status` | `proposed` \| `accepted` \| `deprecated` \| `superseded` | Set record status |
| `--evaluate "name"` | technology name | Run the § Evaluation Framework (TDR-oriented) |
| `--compare "t1" "t2"` | two technology names | Compare two technologies (TDR-oriented) |

## Examples

```
/arch-decision "Use PostgreSQL for primary database"
/arch-decision --list
/arch-decision --update ADR-005 --status deprecated
/arch-decision "Switch to Redis for caching" --supersede ADR-003
/arch-decision --type tdr "Use Zod for runtime validation"
/arch-decision --type tdr --evaluate "Zod vs Yup vs Joi"
/arch-decision --type tdr --compare "Vitest" "Jest"
```

## Gate — is a record warranted? (run before any template)

Run this first, on `--type adr` and `--type tdr` alike. The three conditions are **conjunctive**:
miss any one and the command **declines**, names the condition that failed, and writes no file.

| # | Condition | It fails when |
|---|---|---|
| W1 | **Hard to reverse** — undoing it later costs more than making it did: accrued dependent code, a data migration, a published contract, or a social cost once contributors have paid for it. | Reversal is a one-line change with nothing accrued against it. |
| W2 | **Surprising without context** — a competent reader of the resulting code would guess wrong about why it is this way. | It is the obvious default for the stack, and the code reads as such. |
| W3 | **The result of a real trade-off** — two or more options were viable and something was actually given up. | Only one option was ever viable, or nothing was surrendered. |

### Short-circuit and exemptions

Evaluation short-circuits: stop at the first condition that fails and decline on it.

`--list`, `--update <number>`, `--supersede <number>`, `--status`, `--evaluate`, and `--compare`
bypass the gate — the record already exists, or none is being emitted, so warrantedness is settled.

### Declining — the required output

Emit exactly this, and no file:

~~~markdown
**No record warranted** — <topic>

| Gate | Verdict | Why |
|---|---|---|
| W1 Hard to reverse | ❌ | <the reversal cost, in one line> |
| W2 Surprising without context | ✅ | <one line> |
| W3 Real trade-off | ✅ | <one line> |

**Record it as a plain decision instead**: <destination> — a `key_decisions[]` entry in the stage
artifact, a "decisions that did not clear the bar" list beside the accepted records, or a source
comment stating the WHY.
~~~

A declined topic is not a rejected decision. The decision is still made and still written down; it
just does not become a numbered record every future reader has to maintain, reconcile, and supersede.

### Worked decline — an easy-to-reverse change

*Topic*: "Raise the HTTP client timeout from 10s to 30s."

W1 fails: reverting is a one-line constant change with nothing accrued against it. W2 and W3 are
arguable, but the gate is conjunctive and short-circuits, so the command declines on W1, names W1 as
the failed condition, and creates no file under `docs/adr/`. The rationale goes in the commit
message.

## Output Format (ADR — `--type adr`)

Creates `docs/adr/ADR-XXX-title.md`, sections in order:

~~~markdown
# ADR-015: Use PostgreSQL for Primary Database

## Status
Accepted

## Date
[Date]

## Context
Why the decision is needed; requirements it must satisfy (bulleted).

## Options Considered
### Option N: <name>
- **Pros**: <strengths against those requirements>
- **Cons**: <costs, risks, gaps>
~~~

### Output Format (ADR) — Decision through References

~~~markdown
## Decision
We will use **<selected option>**.

### Rationale
Numbered reasons, each tied to a Context requirement.

## Consequences
### Positive
### Negative
### Neutral
Outcomes per class — gains, costs, commitments.

## Implementation Notes
Follow-up actions the decision requires.

## Related Decisions
- ADR-0NN: <title> (<how it relates>)

## References
- <authoritative docs the decision rests on>
~~~

## Output Format (TDR — `--type tdr`)

Creates `docs/tdr/TDR-XXX-title.md`. Same Status/Date frame as an ADR, plus `## Category`
(see TDR Categories):

~~~markdown
## Context
Requirements for the technology, then a `### Problem Statement` naming the gap being closed.

## Evaluation
### Candidates Assessed

| Criterion | Weight | Zod | Yup | Joi |
|-----------|--------|-----|-----|-----|
| Team expertise | 20% | 3 | 4 | 5 |
| TypeScript integration | 20% | 5 | 3 | 2 |
| **Weighted Score** | | **4.3** | **3.7** | **3.4** |

Rows = Evaluation Framework criteria; scores 1–5.
~~~

### Output Format (TDR) — Analysis through References

~~~markdown
### Detailed Analysis
#### <Candidate> (Selected | Considered)
- **Pros**: … / - **Cons**: …

## Decision
We will use **<selected>**.

### Rationale
Numbered reasons referencing the weighted scores.

## Implementation Plan
### Phase 1: New Code (Week 1-2)
### Phase 2: Migration (Week 3-4)
Steps per phase, ending in removal of the superseded dependency.

## Consequences
### Positive
### Negative

## References
- <upstream docs and repository links>
~~~

## Record Numbering

Sequential per type (`ADR-001`, `TDR-001`, …). Numbers are never reused; superseded records
keep theirs.

## Lifecycle (ADR and TDR)

```
Proposed → Accepted → [Deprecated | Superseded]
```

| Status | Meaning |
|--------|---------|
| Proposed | Under discussion / evaluation, not yet decided |
| Accepted | Decision made and in effect |
| Deprecated | No longer recommended but not replaced |
| Superseded | Replaced by newer record |

## TDR vs ADR

| Aspect | TDR (Technology) | ADR (Architecture) |
|--------|------------------|-------------------|
| Scope | Libraries, tools, patterns | System design, structure |
| Level | Implementation | Architectural |
| Examples | Zod, React Query, Vitest | Database choice, API design |
| Owner | Technical Lead | Software Architect |
| Review | DV/QA stages | AR stage |
| `--type` | `tdr` → `docs/tdr/TDR-XXX` | `adr` → `docs/adr/ADR-XXX` |

## TDR Categories

| Category | Examples |
|----------|----------|
| **Library** | Validation, state management, utilities |
| **Framework** | Testing, UI components, API |
| **Tool** | Bundler, linter, formatter |
| **Pattern** | Error handling, logging, caching |
| **Standard** | Coding conventions, naming |

## Evaluation Framework

Weighted criteria for `--evaluate` / `--compare` (TDR-oriented):

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Team expertise | 20% | Current knowledge and learning curve |
| Community support | 15% | Docs, tutorials, Stack Overflow |
| Long-term viability | 15% | Maintenance status, adoption trends |
| Performance | 15% | Runtime performance, bundle size |
| Security posture | 15% | Known vulnerabilities, security updates |
| Integration ease | 10% | Compatibility with existing stack |
| Cost | 10% | Licensing, infrastructure requirements |

## Platform Architect Consultation

When an ADR turns on a platform-level decision — app architecture pattern, navigation, state
management, concurrency model, module or service boundaries — consult the detected platform's
architect for options evaluation. Detect the platform with
`skills/shared/platform-detection.md § Detection Rules`; resolve the agent and its plugin prefix
from `skills/shared/routing-matrix.md § Functional-role aliases` (`apple-architector`,
`kotlin-architector`, `frontend-architector`, `system-architector`, `backend-architector`,
`ai-architector`).

### What the architect contributes

- Platform-specific pros and cons per option
- Pattern fit for the use case (TCA vs. MVVM on Apple, Clean vs. MVI on Android, CSR/SSR/ISR
  on web, layered vs. hexagonal on systems)
- Implementation complexity relative to team expertise in that stack

Fold that analysis into "Options Considered" alongside the system-level evaluation from
`software-architector`. If the platform is ambiguous or its plugin is not installed, record the
ADR with the system-level evaluation only and note the missing consultation.

## Integration

- **AR stage** — architecture decisions (ADR)
- **DV stage / technical-debt discussions** — implementation choices (TDR)
- New patterns, technologies, libraries, or tools; any significant technical choice
- Platform architecture pattern selection (architect consulted)
