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

Shared across modes: `--platform <apple|android|web|all>`.

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

- `--platform <apple|android|web|all>` - Platform-specific templates/context (default: all)

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

### Review Output (`--review`)

Senior/platform-specialist review of an existing estimate. Emit
`## Senior Developer Review: [Project]` with these sections (the fenced chunks below concatenate into one report):

#### Review Output — Adjustments & Impact

```markdown
## Senior Developer Review: [Project]

### Adjustment Summary
| Category | Original (Min-Max) | Adjusted (Min-Max) | Delta | Reason |
|----------|--------------------|--------------------|-------|--------|
| AR SDK | L (5-10) | XL (13-21) | +8-11 | Metal pipeline complexity |
| BLE | M (3-5) | L (5-10) | +2-5 | State machine handling |
| Vision | M (3-5) | L (5-10) | +2-5 | Face detection + landmarks |

### Total Impact
- Original SP: 120-152
- Adjusted SP: 150-193
- Delta: +30-41 SP (+25-27%)
- Hours Impact: +180-246h
```

#### Review Output — Risks & Recommendations

```markdown
### Risk Flags
1. Third-party SDK iOS version support uncertain
2. BLE background mode reliability concerns
3. App Store AR review requirements

### Recommendations
1. Request SDK documentation from vendor before Phase 3
2. Build BLE mock service for development testing
3. Prepare App Store demo video for AR features
```

With `--update`, the adjustments are written back into the estimation files.

## Review Mode Reference

### When to Use `--review`

- Projects with complexity score >= 15
- AR/ML/Vision framework integration
- BLE/Hardware SDK integration
- Real-time camera processing
- Third-party SDK integration

### Adjustment Matrix

| Category | Trigger | Min Increase | Max Increase |
|----------|---------|-------------|-------------|
| AR/Camera SDKs | Metal, AVFoundation, face tracking | +3 SP | +5 SP |
| API Integration | Image processing, async handling | +1 SP | +2 SP |
| BLE/Hardware | State machines, background modes | +2 SP | +3 SP |
| Vision Framework | Face detection, landmarks | +2 SP | +3 SP |
| Offline Sync | Conflict resolution, Core Data | +2 SP | +3 SP |
| Third-party SDKs | Unknown documentation quality | +15% buffer | +20% buffer |

### Platform-Specific Adjustments

#### iOS/SwiftUI
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| Metal rendering | +3 SP | +5 SP |
| ARKit integration | +5 SP | +8 SP |
| CoreBluetooth state machine | +3 SP | +5 SP |
| Vision face detection | +2 SP | +3 SP |
| App Store review prep | +2 SP | +3 SP |

#### Android/Kotlin
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| NDK/JNI integration | +3 SP | +5 SP |
| BLE background services | +3 SP | +5 SP |
| Camera2 API | +2 SP | +3 SP |
| Play Store compliance | +1 SP | +2 SP |

### Review Checklist

Before finalizing, verify:

- [ ] All SDK integrations identified
- [ ] Background mode requirements assessed
- [ ] Permissions flow complexity included
- [ ] Error handling for network failures
- [ ] Offline mode if required
- [ ] Analytics integration
- [ ] Push notification handling
- [ ] App Store/Play Store requirements

Review methodology detail: `skills/senior-developer-review/SKILL.md`.

## Sizing Guide

### T-Shirt Sizes

See `skills/estimation-methodology/SKILL.md § T-Shirt Sizing → Story Points (Range) and § Story Points to Hours.`

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

See `skills/estimation-methodology/SKILL.md § Story Points to Hours` for the canonical formula and multiplier variants (Junior/Mid/Senior/Expert). Do not redefine here.

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

## Export Mode Reference (`--export csv`)

`--export csv` runs the estimation, then writes 13 CSV files for Google Sheets
import. The canonical file list, column schemas, delimiter, and validation rules
live in `skills/csv-export-templates/SKILL.md` — do not redefine the export shape
here. Requires `--detailed`. Bare `--export` (no value) defaults to `csv`, the
only currently supported format.

### Export File Tree

Creates 13 CSV files in `--dir` (default `exports/`):

```
exports/
├── 01_project_overview.csv     # Metadata, sizing, totals
├── 02_complexity_analysis.csv  # 5-factor scoring
├── 03_technology_stack.csv     # Frameworks, SDKs
├── 04_features_breakdown.csv   # Subtasks with points/hours
├── 05_roadmap_milestones.csv   # Week-by-week plan
├── 06_risk_assessment.csv      # Risk register
├── 07_budget_estimate.csv      # Cost breakdown
├── 08_success_metrics.csv      # KPIs, acceptance criteria
├── 09_competitive_analysis.csv # Market positioning
├── 10_<platform>_specifics.csv     # Platform details (see --platform variants below)
├── 11_<framework>_specifics.csv    # Framework details (varies by platform)
├── 12_integration_specifics.csv    # SDK/API details (per-platform integrations)
└── 13_phase_summary.csv        # Phase rollup
```

### Platform Variants (files 10, 11, 12)

The naming and content of files 10–12 depend on `--platform`:

| `--platform` | File 10 | File 11 | File 12 |
|--------------|---------|---------|---------|
| `apple`      | `10_ios_specifics.csv` | `11_swiftui_specifics.csv` | `12_integration_specifics.csv` (Apple SDKs/APIs) |
| `android`    | `10_android_specifics.csv` | `11_jetpack_specifics.csv` | `12_integration_specifics.csv` (Android SDKs/APIs) |
| `web`        | `10_web_specifics.csv` | `11_framework_specifics.csv` | `12_integration_specifics.csv` (web SDKs/APIs) |
| `all` (default) | All three platform sets emitted side-by-side | — | — |

See `skills/csv-export-templates/SKILL.md` for the canonical column schemas of each variant.

### Export Validation (`--validate`)

Canonical validation rules live in `skills/csv-export-templates/SKILL.md § Validation Rules`. The `--validate` mode flag additionally:

- Aborts the export with a non-zero exit and a row-level diff if any rule fails (the skill defines the rules; this command defines the failure mode).
- Emits a `validation_report.csv` alongside the 13 files listing each rule and pass/fail status.
- Is idempotent: re-running `--validate` against an existing export directory revalidates without rewriting files.

### CSV Format

| Setting | Value |
|---------|-------|
| Delimiter | Semicolon (`;`), override with `--delimiter` |
| Encoding | UTF-8 |
| Headers | First row always |
| Multiline | Quote cells with line breaks |

### Google Sheets Import

1. Open Google Sheets
2. File → Import → Upload CSV
3. Select the delimiter matching `--delimiter` (default `;`)
4. Import each file to a separate sheet

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
