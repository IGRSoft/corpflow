---
name: estimate
description: Estimate task complexity, effort, and resources to determine appropriate workflow tier
argument-hint: '<task description> [--quick|--detailed]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

# Estimate Command

Estimate task complexity, effort, and resources before starting a workflow. Helps determine the appropriate workflow tier and provides sizing guidance.

## Usage

```
/estimate "Task description"
/estimate --quick "Small task"
/estimate --detailed "Complex feature"
```

## Options

- `--quick` - Quick estimation (T-shirt size only)
- `--detailed` - Detailed estimation with full breakdown
- `--stages` - Emits the 3-stage breakdown (Required, Nice-to-have, v1.1) using the template in `skills/shared/three-stage-planning.md § Stage Budget Template`. See Output Format below.
- `--sequential` - Flag-only; documents that stages cannot run in parallel. See `skills/shared/three-stage-planning.md` for the sequential-only rules.
- `--compare` - Accepts `"opt1 | opt2 | opt3"`; emits a comparison table with size, SP range, hours range, complexity score, and recommended workflow per option. See Output Format below.
- `--export` - Runs the estimation, then invokes `/export-estimate` with the same `--platform`/`--dir` args to produce 13 CSV files defined in `skills/csv-export-templates/SKILL.md`. Requires `--detailed` (quick estimates have no breakdown to export).
- `--platform <apple|android|web|all>` - Platform-specific templates (default: all)
- `--multiplier <hours>` - Override SP multiplier (default: 6)
- `--ai-rate <amount>` - AI agent monthly rate (no default — if omitted, AI cost row shows [ai-cost skipped: --ai-rate not set])
- `--dev-rate <amount>` - Developer hourly rate (no default — required for budget calculation; estimate runs without budget if omitted)

## Examples

```
/estimate "Add dark mode support"
/estimate --detailed "Implement user authentication with OAuth"
/estimate --quick "Fix button alignment on login page"
```

## Output Format

### Quick Estimation
```markdown
## Quick Estimate: Add dark mode support

**Size**: M (Medium)
**Recommended Workflow**: `workflow:` (Standard)
**Estimated Effort**: 2-3 days
```

### Detailed Estimation
```markdown
## Detailed Estimate: Implement user authentication

### Sizing
| Metric | Value | Notes |
|--------|-------|-------|
| T-Shirt Size | L | Multiple components affected |
| SP Min | 5 | Optimistic estimate |
| SP Max | 10 | Pessimistic estimate |
| Hours Min | 30 | SP Min × 6h |
| Hours Max | 60 | SP Max × 6h |

### Complexity Analysis
| Factor | Score (1-5) | Notes |
|--------|-------------|-------|
| Technical Complexity | 4 | OAuth integration, token management |
| Integration Points | 3 | Backend API, storage, UI |
| Risk Level | 3 | Security-sensitive feature |
| Unknowns | 2 | Well-documented OAuth providers |

### Recommended Workflow
**Tier**: `workflow:` (Full 9-stage)
**Rationale**: Security-sensitive, multiple files, requires architecture review

### Resource Requirements
- **Skills Needed**: Backend, Security, Frontend
- **Dependencies**: API endpoints, OAuth provider setup
- **Blockers**: None identified

### Breakdown
| Component | Size | SP Min | SP Max | Notes |
|-----------|------|--------|--------|-------|
| OAuth Provider Setup | S | 2 | 3 | Configuration only |
| Token Management | M | 3 | 5 | Storage, refresh logic |
| Login UI | S | 2 | 3 | Form and error handling |
| Session Management | M | 3 | 5 | State persistence |
| Tests | M | 3 | 5 | Security tests critical |
| Documentation | S | 2 | 3 | API docs, user guide |

### Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Token security issues | Medium | High | Security review in AR stage |
| OAuth provider changes | Low | Medium | Abstract provider interface |

### Budget Calculation
| Metric | Min | Max |
|--------|-----|-----|
| Base Hours | [SP Min × 6h] | [SP Max × 6h] |
| Buffer (15%) | [Base Min × 0.15] | [Base Max × 0.15] |
| Total Hours | [Base Min + Buffer Min] | [Base Max + Buffer Max] |
| Budget | $[Total Min × Rate] | $[Total Max × Rate] |

If `--dev-rate` is omitted, the Budget row is replaced by:
`[budget skipped: --dev-rate not set]` and only Base/Buffer/Total Hours are emitted.

### AI Cost
| Metric | Value |
|--------|-------|
| Est. Tokens | 60K–120K (mixed haiku/sonnet/opus) |
| AI Cost | $0.20–$0.50 |
| % of Total Budget | <0.1% |

See `skills/estimation/SKILL.md § AI Agent Cost Estimation` for the formula and per-task-type token bands.
```

### Comparison Output (`--compare`)

```markdown
## Comparison: Auth implementation options

| Option | Size | SP Range | Hours Range | Complexity | Workflow |
|--------|------|----------|-------------|------------|----------|
| OAuth2 | L    | 6–10     | 36–60       | 14         | `workflow:` |
| Magic-link | M | 4–5    | 24–30       | 9          | `workflow:` |
| Password+TOTP | M | 4–5 | 24–30       | 11         | `workflow:` |
```

### Stages Output (`--stages`)

```markdown
## 3-Stage Plan: Build MVP

| Stage | Scope | SP | Hours | Buffer (10%) | Total |
|-------|-------|----|-------|--------------|-------|
| 1. Required | Core features | 20 | 120 | 12 | 132 |
| 2. Nice-to-have | Polish | 10 | 60  | 6  | 66  |
| 3. v1.1 | Roadmap items | 8  | 48  | 4.8 | 52.8 |

See `skills/shared/three-stage-planning.md § Stage Budget Template` for column definitions.
```

## Sizing Guide

### T-Shirt Sizes

See `skills/estimation/SKILL.md § T-Shirt Sizing and § Story Points to Hours.`

Worked-example header (canonical values live in the skill):

| Size | SP Min | SP Max | Hours Min | Hours Max | Workflow |
|------|--------|--------|-----------|-----------|----------|
| XS | 1 | 1 | 6 | 6 | `micro:` |
| S | 2 | 3 | 12 | 18 | `quick:` |
| M | 4 | 5 | 24 | 30 | `workflow:` |
| L | 6 | 10 | 36 | 60 | `workflow:` |
| XL | 13 | 21 | 78 | 126 | split first |

### Complexity Factors
- **Technical Complexity**: Algorithm difficulty, new technologies
- **Integration Points**: APIs, services, databases affected
- **Risk Level**: Security, data integrity, user impact
- **Unknowns**: Unclear requirements, new domain
- **Domain Expertise**: Specialized knowledge required (5 = niche specialty)

### Story Points to Hours

See `skills/estimation/SKILL.md § Story Points to Hours` for the canonical formula and multiplier variants (Junior/Mid/Senior/Expert). Do not redefine here.

### Phase Constraints

- Maximum 4 weeks (~160h) per phase
- If exceeds, split into sub-phases or redistribute
- Each phase should be independently deliverable

### Test Integration

- Tests MUST be included in subtasks
- Format: "[Task] + tests"
- No separate testing phases allowed

### Buffer Calculation

- Add 15% buffer to both Min and Max base hours
- Total Min = Base Min × 1.15, Total Max = Base Max × 1.15
- Budget Min = Total Min × Rate, Budget Max = Total Max × Rate

Default buffer is 15% for single-stage estimates and 10% per stage for /estimate --stages (compounded across stages provides equivalent contingency).

## 3-Stage Sequential Model

See `skills/shared/three-stage-planning.md` for stage definitions, sequential rules, calendar month billing, stage budget template, and gate criteria.

## Export Structure

`--export` delegates to `/export-estimate`, which writes 13 CSV files defined in
`skills/csv-export-templates/SKILL.md`. See that skill for the full file list,
delimiter, and validation rules. Do not redefine the export shape here.

## Workflow Recommendation Logic

```
size       = T-shirt size from sizing table
complexity = sum of 5 factors (0–25)
security   = true if Risk Level ≥ 4 OR feature touches auth/PII/payments

IF size == XS AND complexity ≤ 5 AND NOT security:
  → micro:
ELSE IF size == S AND NOT security:
  → quick:
ELSE IF size ∈ {M, L} OR security:
  → workflow:
ELSE IF size == XL:
  → split before workflow tier selection
```

See `skills/estimation/SKILL.md § Workflow Tier Selection` for the canonical definition.

## Integration

This command works well with:
- `/workflow` - Use estimate to choose correct workflow tier
- `/pm-prioritize` - Estimation feeds into RICE calculations
- `/sprint-plan` - Story points for capacity planning
- `/export-estimate` - Generate CSVs from estimation
- `/senior-review` - Platform-specific review adjustments

## Related

- [Workflow System](../skills/workflow.md) - Workflow tier selection
- [product-manager](../agents/product-manager.md) - RICE prioritization
- [project-manager](../agents/project-manager.md) - Sprint planning
