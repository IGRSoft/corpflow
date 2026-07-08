---
name: arch-decision
description: Create or update Architecture Decision Records (ADRs) or Technology Decision Records (TDRs) to document significant technical decisions
argument-hint: <decision topic or context> [--type adr|tdr]
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/software-architector.md
  - agents/technical-lead.md
  - commands/arch-review.md
  - commands/arch-debt.md
---

# Architecture / Technology Decision Record Command

Create or update decision records. Two record types are supported via `--type`:

- `--type adr` (default) — **Architecture Decision Records (ADRs)**: system design,
  structure, and architectural choices. Output to `docs/adr/ADR-XXX-title.md`.
- `--type tdr` — **Technology Decision Records (TDRs)**: implementation-level
  technology choices such as libraries, frameworks, tools, and patterns. Output to
  `docs/tdr/TDR-XXX-title.md`.

## Usage

```
/arch-decision "Decision title"                  # ADR (default)
/arch-decision --type tdr "Decision title"       # TDR
/arch-decision --list
/arch-decision --update <ADR-or-TDR-number>
/arch-decision --type tdr --evaluate "Technology name"
```

## Options

- `--type [adr|tdr]` - Record type (default `adr`). `tdr` targets `docs/tdr/TDR-XXX`.
- `--list` - List all existing records (of the selected type)
- `--update <number>` - Update existing record
- `--supersede <number>` - Create record that supersedes another
- `--status [proposed|accepted|deprecated|superseded]` - Set record status
- `--evaluate "name"` - Run the evaluation framework for a technology (TDR-oriented)
- `--compare "tech1" "tech2"` - Compare two technologies (TDR-oriented)

`--evaluate` and `--compare` drive the weighted Evaluation Framework (see below)
and are primarily used with `--type tdr` technology assessments.

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

## Output Format (ADR — `--type adr`)

Creates file: `docs/adr/ADR-XXX-title.md`

```markdown
# ADR-015: Use PostgreSQL for Primary Database

## Status
Accepted

## Date
[Date]

## Context

We need to select a primary database for storing user data, transactions, and application state. The system requires:
- ACID compliance for financial transactions
- Complex querying capabilities
- Proven scalability to millions of records
- Strong ecosystem and tooling support

### Options Considered

#### Option 1: PostgreSQL
- **Pros**: ACID compliant, mature, excellent tooling, JSON support, strong community
- **Cons**: Requires more ops expertise than managed solutions

#### Option 2: MySQL
- **Pros**: Widely used, good performance, many managed options
- **Cons**: Less advanced features, weaker JSON support

#### Option 3: MongoDB
- **Pros**: Flexible schema, horizontal scaling
- **Cons**: Not ACID by default, eventual consistency concerns

## Decision

We will use **PostgreSQL** as our primary database.

### Rationale
1. **ACID compliance** is critical for our financial transactions
2. **JSON support** allows flexible schema where needed
3. **Strong ecosystem** with excellent ORMs and migration tools
4. **Proven at scale** by companies with similar requirements
5. **Team expertise** - team has PostgreSQL experience

## Consequences

### Positive
- Strong data integrity guarantees
- Powerful query capabilities with CTEs, window functions
- Excellent migration and schema management tools
- Good performance with proper indexing

### Negative
- Requires database administration expertise
- Horizontal scaling more complex than NoSQL options
- Need to manage connection pooling

### Neutral
- Will use Prisma as ORM for type safety
- Need to set up backup and replication strategy

## Implementation Notes

- Use connection pooling (PgBouncer or built-in)
- Implement read replicas for reporting queries
- Set up automated backups with point-in-time recovery
- Use database migrations for all schema changes

## Related Decisions

- ADR-010: API authentication strategy (uses PostgreSQL for user storage)
- ADR-012: Caching strategy (Redis for caching, PostgreSQL for persistence)

## References

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Prisma with PostgreSQL](https://www.prisma.io/docs/concepts/database-connectors/postgresql)
```

## Output Format (TDR — `--type tdr`)

Creates file: `docs/tdr/TDR-XXX-title.md`

```markdown
# TDR-012: Use Zod for Runtime Validation

## Status
Accepted

## Date
[Date]

## Category
Library - Validation

## Context

We need a runtime validation library for validating API inputs, form data, and configuration. Requirements:
- TypeScript-first with excellent type inference
- Composable schema definitions
- Good error messages
- Active maintenance and community

### Problem Statement

Current validation is inconsistent across the codebase:
- Manual checks in some handlers
- Joi in legacy modules
- No validation in newer code

## Evaluation

### Candidates Assessed

| Criterion | Weight | Zod | Yup | Joi |
|-----------|--------|-----|-----|-----|
| Team expertise | 20% | 3 | 4 | 5 |
| TypeScript integration | 20% | 5 | 3 | 2 |
| Community support | 15% | 5 | 4 | 4 |
| Long-term viability | 15% | 5 | 4 | 3 |
| Performance | 15% | 4 | 4 | 3 |
| Bundle size | 10% | 4 | 3 | 2 |
| Error messages | 5% | 5 | 4 | 4 |
| **Weighted Score** | | **4.3** | **3.7** | **3.4** |

### Detailed Analysis

#### Zod (Selected)
- **Pros**:
  - First-class TypeScript support with type inference
  - Zero dependencies
  - Excellent composability
  - Growing ecosystem (trpc, react-hook-form)
  - Active development
- **Cons**:
  - Team needs to learn new syntax
  - Less battle-tested than Joi

#### Yup (Considered)
- **Pros**: Familiar syntax, good ecosystem
- **Cons**: TypeScript support is bolted on, larger bundle

#### Joi (Considered)
- **Pros**: Very mature, comprehensive validation
- **Cons**: Poor TypeScript support, large bundle, Node-focused

## Decision

We will use **Zod** for runtime validation across the codebase.

### Rationale

1. **TypeScript-first design** provides excellent DX and type safety
2. **Type inference** eliminates duplicate type definitions
3. **Composability** enables building complex schemas from simple ones
4. **Growing ecosystem** with integrations we already use (trpc)
5. **Zero dependencies** keeps bundle size manageable

## Implementation Plan

### Phase 1: New Code (Week 1-2)
- Use Zod for all new validation
- Create shared schema library in `src/schemas/`
- Document patterns and examples

### Phase 2: Migration (Week 3-4)
- Replace Joi in legacy modules
- Add validation to unvalidated endpoints
- Remove Joi dependency

## Consequences

### Positive
- Single source of truth for types and validation
- Consistent validation across codebase
- Better error messages for API consumers
- Reduced bundle size vs Joi

### Negative
- Learning curve for team members unfamiliar with Zod
- Migration effort for existing Joi schemas

## References

- [Zod Documentation](https://zod.dev/)
- [Zod GitHub](https://github.com/colinhacks/zod)
```

## Record Numbering

Records are automatically numbered sequentially per type:
- ADRs: `ADR-001`, `ADR-002`, … · TDRs: `TDR-001`, `TDR-002`, …
- Numbers are never reused
- Superseded records keep their number

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

When evaluating technologies (`--evaluate` / `--compare`, TDR-oriented), assess
these weighted criteria:

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Team expertise | 20% | Current team knowledge and learning curve |
| Community support | 15% | Documentation, tutorials, Stack Overflow |
| Long-term viability | 15% | Maintenance status, adoption trends |
| Performance | 15% | Runtime performance, bundle size |
| Security posture | 15% | Known vulnerabilities, security updates |
| Integration ease | 10% | Compatibility with existing stack |
| Cost | 10% | Licensing, infrastructure requirements |

## Template Sections (ADR)

| Section | Purpose |
|---------|---------|
| Status | Current lifecycle state |
| Date | When decision was made |
| Context | Why this decision is needed |
| Decision | What was decided |
| Consequences | Positive, negative, neutral outcomes |
| Implementation | How to implement |
| Related | Connected decisions |

## Apple Architecture Consultation

When an ADR involves Swift/Apple platform architecture decisions (app architecture pattern, navigation strategy, state management, Swift concurrency approach), consult `apple-developer:apple-architector` for options evaluation. The apple-architector provides:

- Swift-specific pros/cons for each architecture option
- Pattern compatibility assessment (e.g., TCA vs MVVM trade-offs for the specific use case)
- Implementation complexity estimates for the team's Swift expertise level

Include the apple-architector's analysis in the ADR's "Options Considered" section alongside system-level evaluation from software-architector.

## Integration

This command is used:
- During AR stage - Document architecture decisions (ADR)
- During DV stage / technical-debt discussions - Document implementation choices (TDR)
- When introducing new patterns, technologies, libraries, or tools
- For significant technical choices
- For Apple platform architecture pattern selection (with apple-architector consultation)
