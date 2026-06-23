---
name: estimate
description: Estimate task complexity, effort, and resources to determine appropriate worktask tier
argument-hint: '<task description> [--quick|--detailed]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - skills/worktask/SKILL.md
  - agents/product-manager.md
  - agents/project-manager.md
---

# Estimate Command

Estimate task complexity, effort, and resources before starting a worktask. Helps determine the appropriate worktask tier and provides sizing guidance.

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
- `--compare` - Accepts `"opt1 | opt2 | opt3"`; emits a comparison table with size, SP range, hours range, complexity score, and recommended worktask per option. See Output Format below.
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
**Recommended Worktask**: `/worktask` (Standard)
**Estimated Effort**: 2-3 days
```

### Detailed Estimation

Emit `## Detailed Estimate: <task>` with these sections, in order:

| Section | Content |
|---------|---------|
| `### Sizing` | T-Shirt Size, SP Min/Max, Hours Min/Max (SP × multiplier) |
| `### Complexity Analysis` | The 5 factors scored 1–5 each, with notes (see Sizing Guide below) |
| `### Recommended Worktask` | Tier + rationale (see Worktask Recommendation Logic below) |
| `### Resource Requirements` | Skills needed, dependencies, blockers |
| `### Breakdown` | Per-component table: Component, Size, SP Min, SP Max, Notes — tests included per component |
| `### Risk Assessment` | Risk, Probability, Impact, Mitigation |
| `### Budget Calculation` | Base Hours (SP × multiplier), Buffer (15%), Total Hours, Budget = Total × `--dev-rate` |
| `### AI Cost` | Est. tokens, AI cost, % of total budget — formula + per-task-type token bands: `skills/estimation/SKILL.md § AI Agent Cost Estimation` |

If `--dev-rate` is omitted, the Budget row is replaced by
`[budget skipped: --dev-rate not set]` and only Base/Buffer/Total Hours are emitted.

### Comparison Output (`--compare`)

```markdown
## Comparison: Auth implementation options

| Option | Size | SP Range | Hours Range | Complexity | Entry point |
|--------|------|----------|-------------|------------|-------------|
| OAuth2 | L    | 6–10     | 36–60       | 14         | `/worktask` |
| Magic-link | M | 4–5    | 24–30       | 9          | `/worktask` |
| Password+TOTP | M | 4–5 | 24–30       | 11         | `/worktask` |
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

See `skills/estimation/SKILL.md § T-Shirt Sizing → Story Points (Range) and § Story Points to Hours.`

Worked-example header (canonical values live in the skill):

| Size | SP Min | SP Max | Hours Min | Hours Max | Entry point |
|------|--------|--------|-----------|-----------|-------------|
| XS | 1 | 1 | 6 | 6 | `/worktask` |
| S | 2 | 3 | 12 | 18 | `/worktask` |
| M | 4 | 5 | 24 | 30 | `/worktask` |
| L | 6 | 10 | 36 | 60 | `/worktask` |
| XL | 13 | 21 | 78 | 126 | split first |

All sizes use the single `/worktask` entry point; PL0 dynamic sizing drops stages for low-complexity work.

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

## Worktask Recommendation Logic

```
size       = T-shirt size from sizing table
complexity = sum of 5 factors (0–25)

IF size == XL:
  → split into ≤ L sub-tasks before recommending a worktask
ELSE:
  → /worktask   (PL0 dynamic sizing drops stages for low-complexity work)
```

See `skills/estimation/SKILL.md § Worktask Tier Selection` for the canonical definition.

## Integration

This command works well with:
- `/worktask` - Use estimate to choose correct worktask tier
- `/pm-prioritize` - Estimation feeds into RICE calculations
- `/sprint-plan` - Story points for capacity planning
- `/export-estimate` - Generate CSVs from estimation
- `/senior-review` - Platform-specific review adjustments

