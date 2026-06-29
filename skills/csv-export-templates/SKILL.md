---
name: csv-export-templates
description: 13-category CSV export structure for Google Sheets import. Use when generating CSV export files for estimates, budgets, timelines, or reports.
effort: low
---

# CSV Export Templates

These 13 templates are the canonical export shape. /estimate and /export-estimate both reference this file; do not redefine the file list elsewhere.

13-category export structure for Google Sheets import.

For all 13 CSV template definitions, see `${CLAUDE_SKILL_DIR}/references/templates.md`

## Format Specification

| Setting | Value |
|---------|-------|
| Delimiter | Semicolon (;) |
| Encoding | UTF-8 |
| Headers | First row always |
| Multiline | Quote cells with line breaks |
| Empty cells | Leave empty, no placeholder |

## Export Structure

| # | File | Purpose |
|---|------|---------|
| 01 | project_overview.csv | Project metadata, sizing, totals |
| 02 | complexity_analysis.csv | 5-factor complexity scoring |
| 03 | technology_stack.csv | Frameworks, SDKs, tools |
| 04 | features_breakdown.csv | Subtasks with SP/hours |
| 05 | roadmap_milestones.csv | Week-by-week plan |
| 06 | risk_assessment.csv | Risk register |
| 07 | budget_estimate.csv | Cost breakdown |
| 08 | success_metrics.csv | KPIs, acceptance criteria |
| 09 | competitive_analysis.csv | Market positioning |
| 10 | ios_specifics.csv | Platform details |
| 11 | swiftui_specifics.csv | Framework details |
| 12 | integration_specifics.csv | SDK/API details |
| 13 | phase_summary.csv | Phase rollup |

### Platform Variants (files 10 and 11)

Files 10 and 11 are platform-specific. The exact filename and column schema depend on `--platform`:

| `--platform` | File 10 | File 11 |
|--------------|---------|---------|
| `apple`      | `10_ios_specifics.csv` | `11_swiftui_specifics.csv` |
| `android`    | `10_android_specifics.csv` | `11_jetpack_specifics.csv` |
| `web`        | `10_web_specifics.csv` | `11_framework_specifics.csv` |
| `all` (default) | All three platform sets emitted side-by-side | — |

File 12 (`integration_specifics.csv`) keeps a stable filename across platforms but its rows enumerate platform-relevant SDKs/APIs (Apple SDKs for `apple`, Android/Jetpack APIs for `android`, web SDKs for `web`).

## Validator Script

**Canonical path**: `scripts/validate-export.sh`

**One-line invocation**:
```sh
bash scripts/validate-export.sh --dir <export-dir> [--out <report.csv>]
```

- Emits `<export-dir>/validation_report.csv` (columns: `check;status;detail`).
- Exits `0` on full pass, `1` on any violation, `2` on usage/missing-file error.
- Columns are keyed by **header name**, not position — safe against column reordering.
- Semicolon-delimited CSVs with quoted semicolons are parsed correctly via an embedded `python3 csv` heredoc.
- Run `--self-test` for a no-network fixture verification (matching set exits 0; mismatched set exits 1).

The validation rules below are the **spec** this script implements. In the happy path, invoke the script rather than re-reading them manually.

## Validation Rules

After export, verify:

1. **Totals match**:
   - 04 features SP Min sum = 13 phase summary SP Min sum
   - 04 features SP Max sum = 13 phase summary SP Max sum
   - 07 budget hours Min/Max = 13 phase summary hours Min/Max
   - 01 overview Min/Max matches 13 summary Min/Max

2. **Range consistency**:
   - SP Min ≤ SP Max for every row
   - Hours Min ≤ Hours Max for every row
   - No phase Hours Max > 160 hours

3. **Phase constraints**:
   - Week ranges continuous
   - Dependencies valid

4. **Format valid**:
   - Semicolon delimiter
   - UTF-8 encoding
   - Headers present
