---
name: estimate
description: Estimate task complexity, effort, and resources; optionally review an estimate or export it to CSV
argument-hint: '["<task description>"] [--quick|--detailed] [--stages] [--sequential] [--compare "<opt1> | <opt2>"] [--multiplier <hours>] [--ai-rate <amount>] [--dev-rate <amount>] [--no-review] [--review [--focus <areas>] [--update]] [--export csv [--dir <path>] [--delimiter <char>] [--validate]] [--platform <p>]'
# tools: the Budget and AI Cost rows order `estimate-calc.py` as the canonical math and `--validate`
# runs `validate-export.sh`, so the grant names those two scripts; every other number is read, not computed.
allowed-tools: Read, Glob, Grep, Write, Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/estimation-methodology/scripts/estimate-calc.py *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/csv-export-templates/scripts/validate-export.sh *)
related:
  - skills/worktask/SKILL.md
  - skills/estimation-methodology/SKILL.md
  - skills/estimation-methodology/references/estimate-review.md
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
| **Estimate** (default) | no mode flag | Produce a sizing/effort/budget estimate | `--quick`, `--detailed`, `--stages`, `--sequential`, `--compare`, `--multiplier`, `--ai-rate`, `--dev-rate`, `--no-review` |
| **Review** | `--review` | Senior/platform-specialist review of an existing estimate | `--focus`, `--update` |
| **Export** | `--export csv` | Emit the 13-CSV estimation pack for Google Sheets | `--dir`, `--delimiter`, `--validate` |

`--platform` is shared by all three modes — see § Options → Shared.

## Options

### Estimate mode (default)

| Option | Values | Effect |
|--------|--------|--------|
| `--quick` | — | Quick estimation (T-shirt size only) |
| `--detailed` | — | Detailed estimation with full breakdown |
| `--stages` | — | Emit the 3-stage breakdown (Required, Nice-to-have, v1.1) using `skills/shared/three-stage-planning.md § Stage Budget Template` |
| `--sequential` | — | Record that stages cannot run in parallel; rules in `skills/shared/three-stage-planning.md` |
| `--compare "<opt1> \| <opt2>"` | two or more options | Comparison table with size, SP range, hours range, complexity score and recommended worktask per option |

#### Estimate mode — rates and review

| Option | Values | Effect |
|--------|--------|--------|
| `--multiplier <hours>` | hours per SP | Override the SP multiplier (default: 6) |
| `--ai-rate <amount>` | monthly rate | AI agent monthly rate; no default — without it the AI cost row shows `[ai-cost skipped: --ai-rate not set]` |
| `--dev-rate <amount>` | hourly rate | Developer hourly rate; no default — without it the estimate runs with no budget |
| `--no-review` | — | Skip the inline review step even when its trigger fires (§ Review Step) |

### Review mode (`--review`)

| Option | Values | Effect |
|--------|--------|--------|
| `--review` | — | Review an existing estimate |
| `--focus <areas>` | comma-separated: `ar`, `ble`, `vision`, `api`, `camera`, `sync` | Focus areas (default: all) |
| `--update` | — | Auto-update estimation files with the review's adjustments |

### Export mode (`--export csv`)

| Option | Values | Effect |
|--------|--------|--------|
| `--export csv` | `csv` (bare `--export` means `csv`) | After the estimation, emit the 13 CSV files defined in `skills/csv-export-templates/SKILL.md`. Requires `--detailed` (quick estimates have no breakdown to export). |
| `--dir <path>` | directory | Output directory (default: `exports/`) |
| `--delimiter <char>` | one character | CSV delimiter (default: the skill's `;`) |
| `--validate` | — | Validate totals across the emitted files (§ Export Validation) |

### Shared

| Option | Values | Effect |
|--------|--------|--------|
| `--platform <p>` | `apple`, `android`, `web`, `systems`, `backend`, `ai`, `all` | Platform-specific templates and context (default: `all`); keys match `skills/shared/compatible-plugins.md § Registry` |

## Examples

```
/estimate ["<task description>"] [--quick|--detailed] [--stages] [--sequential] [--compare "<opt1> | <opt2>"] [--multiplier <hours>] [--ai-rate <amount>] [--dev-rate <amount>] [--no-review] [--review [--focus <areas>] [--update]] [--export csv [--dir <path>] [--delimiter <char>] [--validate]] [--platform <p>]
/estimate "Add dark mode support"
/estimate --detailed "Implement user authentication with OAuth"
/estimate --quick "Fix button alignment on login page"
/estimate --review --platform apple --focus ar,ble
/estimate --review --platform android --update
/estimate --detailed "Build MVP" --export csv --dir exports/ --delimiter , --validate
/estimate --detailed --stages --sequential "Offline sync"   # 3-stage budget, no parallelism
/estimate --compare "SwiftData | GRDB | Core Data"
/estimate --detailed "Payments" --multiplier 8 --dev-rate 95 --ai-rate 200
/estimate --detailed "Payments" --no-review                 # skip the inline review step
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
| `### Review Adjustments` | Emitted only when the inline review step fires (see Review Step below); omitted entirely otherwise |

#### Detailed Estimation — Budget & AI Cost Sections

| Section | Content |
|---------|---------|
| `### Budget Calculation` | Base Hours (SP × multiplier), Buffer (15%), Total Hours, Budget = Total × `--dev-rate`. **Canonical math**: run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/estimation-methodology/scripts/estimate-calc.py --size <S> --rate <R>` and read `total_hours` + `budget` from the JSON output. |
| `### AI Cost` | Est. tokens, AI cost, % of total budget. **Canonical math**: run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/estimation-methodology/scripts/estimate-calc.py --tokens <n> --model <m>` (add `--input-tokens`/`--output-tokens` when the split is known) and read `ai_cost.usd`. Formula + token bands: `skills/estimation-methodology/SKILL.md § AI Agent Cost Estimation`. |

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
with columns Stage, Scope, SP, Hours, Buffer (10%), Total. Column definitions, stage
definitions, sequential rules, calendar month billing and gate criteria:
`skills/shared/three-stage-planning.md § Stage Budget Template`.

## Review Step (inline, `--detailed`)

`--detailed` runs the platform review as part of the estimate, not behind a flag, when the
trigger in `skills/estimation-methodology/references/estimate-review.md § When to Apply` fires:
complexity ≥ 15, or the scope names AR/ML/Vision, BLE/hardware, real-time camera, third-party
SDKs of unknown quality, or background processing. `--no-review` suppresses it; `--quick` never
reviews, having no breakdown to adjust.

### Applying the adjustment

When it fires: select the one platform table matching `--platform` (`--platform all` → the table
for the platform the scope's markers indicate; ambiguous → say so and skip the adjustment rather
than picking one), apply the per-feature SP deltas, and emit `### Review Adjustments` with the
Adjustment Summary and Total Impact tables from § Output Format.

The adjusted SP Min/Max are what `### Budget Calculation` consumes, so the budget, hours and
timeline are all post-adjustment.

### Review Output (`--review`)

Emit `## Estimate Review: [Project]` exactly as templated in
`skills/estimation-methodology/references/estimate-review.md § Output Format` — sections Adjustment
Summary, Total Impact, Risk Flags, Recommendations. With `--update`, the
adjustments are written back into the estimation files.

## Review Mode Reference

`skills/estimation-methodology/references/estimate-review.md` is canonical for both the inline
review step and `--review` mode, and is not restated here: § When to Apply, § Adjustment Matrix
(capability-keyed SP increases), § Platform-Specific Adjustments (per-platform API tables — apply
only the one matching `--platform`), § Review Process, § Review Checklist, and § Risk Flags.

## Sizing Guide

Canonical in `skills/estimation-methodology/SKILL.md`: § T-Shirt Sizing → Story
Points (Range), § Story Points to Hours (formula and Junior/Mid/Senior/Expert
multiplier variants), § 5-Factor Complexity Analysis (Technical Complexity,
Integration Points, Risk Level, Unknowns, Domain Expertise), § Phase Constraints,
§ Test Integration, and § Buffer Calculation.

Command-owned rule on top of the skill: buffer is 15% for single-stage estimates, but 10% per
stage under `--stages` — compounding across stages gives equivalent contingency.

## Export Mode Reference (`--export csv`)

`skills/csv-export-templates/SKILL.md` is canonical for the CSV pack and is not restated here:
§ Export Structure (the 13-file list), § Platform Variants (how files 10–11 resolve from
`--platform`), § File 12 and column schemas, § Format Specification (delimiter, encoding,
headers, quoting), and § Validation Rules.

### Export Validation (`--validate`)

The skill defines the rules; this command defines the failure mode. Run
`bash ${CLAUDE_PLUGIN_ROOT}/skills/csv-export-templates/scripts/validate-export.sh --dir <dir> --delimiter <char>`
with the same `--dir` and `--delimiter` the export used.

- Aborts the export with a non-zero exit and a row-level diff if any rule fails.
- Emits a `validation_report.csv` alongside the 13 files listing each rule and pass/fail status.
- Idempotent: re-running `--validate` against an existing export directory revalidates without rewriting files.

## Worktask Recommendation Logic

XL splits into ≤ L sub-tasks before a worktask is recommended; every other size routes to the
single `/worktask` entry point, where PL0 dynamic sizing drops stages for low-complexity work.
Canonical: `skills/estimation-methodology/SKILL.md § Worktask Tier Selection`.
