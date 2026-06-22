---
name: tech-decision
description: Create or update Technology Decision Records (TDRs) for implementation-level technology choices
argument-hint: <technology choice or question>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - ../agents/technical-lead.md
  - ./arch-decision.md
  - ./tech-review.md
  - ./tech-debt.md
---

# Technology Decision Record Command

Create or update Technology Decision Records (TDRs) to document implementation-level technology choices such as libraries, frameworks, tools, and patterns.

## Usage

```
/tech-decision "Decision title"
/tech-decision --list
/tech-decision --update <TDR-number>
/tech-decision --evaluate "Technology name"
```

## Options

- `--list` - List all existing TDRs
- `--update <number>` - Update existing TDR
- `--supersede <number>` - Create TDR that supersedes another
- `--status [proposed|accepted|deprecated|superseded]` - Set TDR status
- `--evaluate "name"` - Run evaluation framework for technology
- `--compare "tech1" "tech2"` - Compare two technologies

## Examples

```
/tech-decision "Use Zod for runtime validation"
/tech-decision --list
/tech-decision --evaluate "Zod vs Yup vs Joi"
/tech-decision --update TDR-007 --status deprecated
/tech-decision "Switch to Vitest for testing" --supersede TDR-003
```

## Output Format

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

### Adoption Guidelines

```typescript
// Define schema
const UserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  age: z.number().int().positive().optional(),
});

// Infer type from schema
type User = z.infer<typeof UserSchema>;

// Validate
const result = UserSchema.safeParse(input);
if (!result.success) {
  return { errors: result.error.flatten() };
}
```

## Consequences

### Positive
- Single source of truth for types and validation
- Consistent validation across codebase
- Better error messages for API consumers
- Reduced bundle size vs Joi

### Negative
- Learning curve for team members unfamiliar with Zod
- Migration effort for existing Joi schemas
- Some edge cases may require workarounds

### Risks to Monitor
- Breaking changes in minor versions (monitor changelog)
- Performance at scale (profile if issues arise)

## Review Date

[Review Date] - Review adoption and consider v4 migration if available

## Related Decisions

- TDR-008: API response format (uses Zod for response validation)
- ADR-015: API design principles (validation requirements)

## References

- [Zod Documentation](https://zod.dev/)
- [Zod GitHub](https://github.com/colinhacks/zod)
- [tRPC + Zod](https://trpc.io/docs/server/validators)
```

## TDR vs ADR

| Aspect | TDR (Technology) | ADR (Architecture) |
|--------|------------------|-------------------|
| Scope | Libraries, tools, patterns | System design, structure |
| Level | Implementation | Architectural |
| Examples | Zod, React Query, Vitest | Database choice, API design |
| Owner | Technical Lead | Software Architect |
| Review | DV/QA stages | AR stage |

## TDR Categories

| Category | Examples |
|----------|----------|
| **Library** | Validation, state management, utilities |
| **Framework** | Testing, UI components, API |
| **Tool** | Bundler, linter, formatter |
| **Pattern** | Error handling, logging, caching |
| **Standard** | Coding conventions, naming |

## Evaluation Framework

When evaluating technologies, assess these criteria:

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Team expertise | 20% | Current team knowledge and learning curve |
| Community support | 15% | Documentation, tutorials, Stack Overflow |
| Long-term viability | 15% | Maintenance status, adoption trends |
| Performance | 15% | Runtime performance, bundle size |
| Security posture | 15% | Known vulnerabilities, security updates |
| Integration ease | 10% | Compatibility with existing stack |
| Cost | 10% | Licensing, infrastructure requirements |

## TDR Lifecycle

```
Proposed → Accepted → [Deprecated | Superseded]
```

| Status | Meaning |
|--------|---------|
| Proposed | Under evaluation, not yet decided |
| Accepted | Decision made, implementation in progress or complete |
| Deprecated | No longer recommended, migration encouraged |
| Superseded | Replaced by newer TDR |

## Integration

This command is used:
- During DV stage - Document implementation choices
- During tech debt discussions - Evaluate alternatives
- When introducing new libraries or tools
- For standardizing patterns across the codebase

