---
name: export-estimate
description: Generate CSV files from estimation data for Google Sheets import
argument-hint: <task or milestone reference>
allowed-tools: Read, Write, Glob
model: haiku
related:
  - skills/csv-export-templates/SKILL.md
  - skills/estimation-methodology/SKILL.md
---

# Export Estimate Command

Generate 13 CSV files from estimation for Google Sheets import.

## Usage

```
/export-estimate
/export-estimate --dir exports/
/export-estimate --platform apple
```

## Options

- `--dir <path>` - Output directory (default: exports/)
- `--platform <apple|android|web|all>` - Platform-specific templates (default: all)
- `--delimiter <char>` - CSV delimiter (default: ;)
- `--validate` - Validate totals across files

## Examples

```
/export-estimate
/export-estimate --dir exports/ --platform apple
/export-estimate --validate
```

## Output

Creates 13 CSV files in the specified directory:

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

## Prerequisites

Requires completed estimation artifacts. Run after:
- `/estimate --detailed "Project"`
- `/pm-roadmap`
- `/risk-assess`

## CSV Format

| Setting | Value |
|---------|-------|
| Delimiter | Semicolon (;) |
| Encoding | UTF-8 |
| Headers | First row always |
| Multiline | Quote cells with line breaks |

For per-file column schemas, see skills/csv-export-templates/references/templates.md.

## Validation

Canonical validation rules live in `skills/csv-export-templates/SKILL.md § Validation Rules`. The `--validate` mode flag additionally:

- Aborts the export with a non-zero exit and a row-level diff if any rule fails (the skill defines the rules; this command defines the failure mode).
- Emits a `validation_report.csv` alongside the 13 files listing each rule and pass/fail status.
- Is idempotent: re-running `--validate` against an existing export directory revalidates without rewriting files.

## Google Sheets Import

1. Open Google Sheets
2. File → Import → Upload CSV
3. Select semicolon (;) as delimiter
4. Import each file to separate sheet

## Integration

This command works with:
- `/estimate --detailed` - Source estimation data
- `/pm-roadmap` - Roadmap milestones
- `/risk-assess` - Risk register
- `/senior-review` - Adjustment data

