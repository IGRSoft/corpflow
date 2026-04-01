---
name: export-estimate
description: Generate CSV files from estimation data for Google Sheets import
argument-hint: <task or milestone reference>
allowed-tools: Read, Write
model: haiku
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
├── 10_ios_specifics.csv        # Platform details (or android/web)
├── 11_swiftui_specifics.csv    # Framework details (varies by platform)
├── 12_integration_specifics.csv # SDK/API details
└── 13_phase_summary.csv        # Phase rollup
```

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

## Validation

With `--validate`, checks:
- SP Min sum matches across 04 and 13
- SP Max sum matches across 04 and 13
- Hours Min/Max sum matches across 07 and 13
- Overview Min/Max totals match phase summary Min/Max
- SP Min ≤ SP Max for every row
- No phase Hours Max exceeds 160 hours
- Week ranges are continuous

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

## Related

- [csv-export-templates](../skills/csv-export-templates/SKILL.md) - Template definitions
- [estimation-methodology](../skills/estimation/SKILL.md) - Methodology rules
