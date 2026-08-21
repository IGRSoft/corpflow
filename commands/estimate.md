---
name: estimate
description: Estimate task complexity, effort, and resources; optionally review an estimate or export it to CSV
argument-hint: '<task description> [--quick|--detailed] [--review] [--export csv]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - skills/worktask/SKILL.md
  - skills/estimation-methodology/SKILL.md
  - skills/senior-developer-review/SKILL.md
  - skills/csv-export-templates/SKILL.md
  - agents/product-manager.md
  - agents/project-manager.md
---

# Estimate Command

Estimate task complexity, effort, and resources before starting a worktask. Helps determine the appropriate worktask tier and provides sizing guidance.

## Modes

`estimate` operates in three mutually-exclusive modes. Flags are scoped to their
mode — do not cross-apply them:

| Mode | Trigger | Purpose | Mode-scoped flags |
|------|---------|---------|-------------------|
| **Estimate** (default) | no mode flag | Produce a sizing/effort/budget estimate | `--quick`, `--detailed`, `--stages`, `--sequential`, `--compare`, `--multiplier`, `--ai-rate`, `--dev-rate` |
| **Review** | `--review` | Senior/platform-specialist review of an existing estimate | `--focus`, `--update` |
| **Export** | `--export csv` | Emit the 13-CSV estimation pack for Google Sheets | `--dir`, `--delimiter`, `--validate` |

Shared across modes: `--platform <apple|android|web|systems|backend|ai|all>` — the six
platform keys of `skills/shared/compatible-plugins.md § Registry`.

## Usage

```
/estimate "Task description"
/estimate --quick "Small task"
/estimate --detailed "Complex feature"
/estimate --review --platform apple --focus ar,ble
/estimate --detailed "Complex feature" --export csv --dir exports/
```

## Options

### Estimate mode (default)

- `--quick` - Quick estimation (T-shirt size only)
- `--detailed` - Detailed estimation with full breakdown
- `--stages` - Emits the 3-stage breakdown (Required, Nice-to-have, v1.1) using the template in `skills/shared/three-stage-planning.md § Stage Budget Template`. See Output Format below.
- `--sequential` - Flag-only; documents that stages cannot run in parallel. See `skills/shared/three-stage-planning.md` for the sequential-only rules.
- `--compare` - Accepts `"opt1 | opt2 | opt3"`; emits a comparison table with size, SP range, hours range, complexity score, and recommended worktask per option. See Output Format below.
- `--multiplier <hours>` - Override SP multiplier (default: 6)
- `--ai-rate <amount>` - AI agent monthly rate (no default — if omitted, AI cost row shows [ai-cost skipped: --ai-rate not set])
- `--dev-rate <amount>` - Developer hourly rate (no default — required for budget calculation; estimate runs without budget if omitted)

### Review mode (`--review`)

- `--review` - Run a senior/platform-specialist review of an existing estimate
- `--focus <areas>` - Comma-separated focus areas (ar, ble, vision, api, camera, sync)
- `--update` - Auto-update estimation files with the review's adjustments

### Export mode (`--export csv`)

- `--export csv` - After running the estimation, emit the 13 CSV files defined in `skills/csv-export-templates/SKILL.md`. Requires `--detailed` (quick estimates have no breakdown to export).
- `--dir <path>` - Output directory (default: `exports/`)
- `--delimiter <char>` - CSV delimiter (default: `;`)
- `--validate` - Validate totals across the emitted files (see Export Validation below)

### Shared

- `--platform <apple|android|web|systems|backend|ai|all>` - Platform-specific templates/context (default: all). Keys match `skills/shared/compatible-plugins.md § Registry`.

## Examples

```
/estimate "Add dark mode support"
/estimate --detailed "Implement user authentication with OAuth"
/estimate --quick "Fix button alignment on login page"
/estimate --review --platform apple --focus ar,ble
/estimate --review --platform android --update
/estimate --detailed "Build MVP" --export csv --dir exports/ --platform apple
/estimate --detailed "Build MVP" --export csv --validate
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

#### Detailed Estimation — Budget & AI Cost Sections

| Section | Content |
|---------|---------|
| `### Budget Calculation` | Base Hours (SP × multiplier), Buffer (15%), Total Hours, Budget = Total × `--dev-rate`. **Canonical math**: invoke `skills/estimation-methodology/scripts/estimate-calc.py --size <S> --rate <R>` and read `total_hours` + `budget` from the JSON output. |
| `### AI Cost` | Est. tokens, AI cost, % of total budget. **Canonical math**: pass `--tokens <n> --model <m>` to `skills/estimation-methodology/scripts/estimate-calc.py` and read `ai_cost.usd`. Formula + token bands: `skills/estimation-methodology/SKILL.md § AI Agent Cost Estimation`. |

If `--dev-rate` is omitted, the Budget row is replaced by
`[budget skipped: --dev-rate not set]` and only Base/Buffer/Total Hours are emitted.

### Comparison Output (`--compare`)

Emit `## Comparison: <topic>` with one row per option:

```markdown
| Option | Size | SP Range | Hours Range | Complexity | Entry point |
|--------|------|----------|-------------|------------|-------------|
| OAuth2 | L    | 6–10     | 36–60       | 14         | `/worktask` |
```

### Stages Output (`--stages`)

Emit `## 3-Stage Plan: <task>` — one row per stage (Required, Nice-to-have, v1.1)
with columns Stage, Scope, SP, Hours, Buffer (10%), Total. Column definitions:
`skills/shared/three-stage-planning.md § Stage Budget Template`.

### Review Output (`--review`)

Emit `## Senior Developer Review: [Project]` exactly as templated in
`skills/senior-developer-review/SKILL.md § Output Format` — sections Adjustment
Summary, Total Impact, Risk Flags, Recommendations. With `--update`, the
adjustments are written back into the estimation files.

## Review Mode Reference

`skills/senior-developer-review/SKILL.md` is canonical for review mode and is not
restated here: § When to Apply (trigger conditions), § Adjustment Matrix
(capability-keyed SP increases), § Platform-Specific Adjustments (per-platform API
tables — apply only the one matching `--platform`), § Review Process, § Review
Checklist, and § Risk Flags.

## Sizing Guide

Canonical in `skills/estimation-methodology/SKILL.md`: § T-Shirt Sizing → Story
Points (Range), § Story Points to Hours (formula and Junior/Mid/Senior/Expert
multiplier variants), § 5-Factor Complexity Analysis (Technical Complexity,
Integration Points, Risk Level, Unknowns, Domain Expertise), § Phase Constraints,
§ Test Integration, and § Buffer Calculation. Do not redefine any of them here.

Command-owned rules on top of the skill:

- Every size routes to the single `/worktask` entry point; PL0 dynamic sizing drops stages for low-complexity work. XL splits into ≤ L sub-tasks first.
- Buffer is 15% for single-stage estimates, but 10% per stage under `--stages` — compounding across stages gives equivalent contingency.

## 3-Stage Sequential Model

See `skills/shared/three-stage-planning.md` for stage definitions, sequential rules, calendar month billing, stage budget template, and gate criteria.

## Export Mode Reference (`--export csv`)

`--export csv` runs the estimation, then writes the 13 CSV files for Google Sheets
import. `skills/csv-export-templates/SKILL.md` is canonical and is not restated
here: § Export Structure (the 13-file list), § Platform Variants (how files 10–11
resolve from `--platform`), § File 12 and column schemas, § Format Specification
(delimiter, encoding, headers, multiline), and § Validation Rules.

Command-owned rules:

- Requires `--detailed`. Bare `--export` (no value) defaults to `csv`, the only currently supported format.
- Files land in `--dir` (default `exports/`); `--delimiter` overrides the skill's default `;`.

### Export Validation (`--validate`)

The skill defines the rules; this command defines the failure mode:

- Aborts the export with a non-zero exit and a row-level diff if any rule fails.
- Emits a `validation_report.csv` alongside the 13 files listing each rule and pass/fail status.
- Idempotent: re-running `--validate` against an existing export directory revalidates without rewriting files.

## Worktask Recommendation Logic

```
size       = T-shirt size from sizing table
complexity = sum of 5 factors (0–25)

IF size == XL:
  → split into ≤ L sub-tasks before recommending a worktask
ELSE:
  → /worktask   (PL0 dynamic sizing drops stages for low-complexity work)
```

See `skills/estimation-methodology/SKILL.md § Worktask Tier Selection` for the canonical definition.

## Integration

This command works well with:
- `/worktask` - Use estimate to choose correct worktask tier
- `/pm-prioritize` - Estimation feeds into RICE calculations
- `/pm-sprint` - Story points for capacity planning
- `/pm-roadmap` - Roadmap milestones feed the CSV export
- `/estimate --review` - Platform-specific review adjustments of an estimate
- `/estimate --export csv` - Generate CSVs from the estimation
