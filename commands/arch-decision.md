# Architecture Decision Record Command

Create or update Architecture Decision Records (ADRs) to document significant technical decisions.

## Usage

```
/arch-decision "Decision title"
/arch-decision --list
/arch-decision --update <ADR-number>
```

## Options

- `--list` - List all existing ADRs
- `--update <number>` - Update existing ADR
- `--supersede <number>` - Create ADR that supersedes another
- `--status [proposed|accepted|deprecated|superseded]` - Set ADR status

## Examples

```
/arch-decision "Use PostgreSQL for primary database"
/arch-decision --list
/arch-decision --update ADR-005 --status deprecated
/arch-decision "Switch to Redis for caching" --supersede ADR-003
```

## Output Format

Creates file: `docs/adr/ADR-XXX-title.md`

```markdown
# ADR-015: Use PostgreSQL for Primary Database

## Status
Accepted

## Date
2025-01-10

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

## ADR Numbering

ADRs are automatically numbered sequentially:
- `ADR-001`, `ADR-002`, etc.
- Numbers are never reused
- Superseded ADRs keep their number

## ADR Lifecycle

```
Proposed → Accepted → [Deprecated | Superseded]
```

| Status | Meaning |
|--------|---------|
| Proposed | Under discussion, not yet decided |
| Accepted | Decision made and in effect |
| Deprecated | No longer recommended but not replaced |
| Superseded | Replaced by newer ADR |

## Template Sections

| Section | Purpose |
|---------|---------|
| Status | Current lifecycle state |
| Date | When decision was made |
| Context | Why this decision is needed |
| Decision | What was decided |
| Consequences | Positive, negative, neutral outcomes |
| Implementation | How to implement |
| Related | Connected decisions |

## Integration

This command is used:
- During A stage - Document architecture decisions
- When introducing new patterns or technologies
- For significant technical choices

## Related

- [software-architector](../agents/software-architector.md) - Architecture expertise
- [arch-review](./arch-review.md) - Architecture review
- [tech-debt](./tech-debt.md) - Technical debt tracking
