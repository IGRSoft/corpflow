---
name: csv-export-templates
description: 13-category CSV export structure for Google Sheets import. Use when generating CSV export files for estimates, budgets, timelines, or reports.
effort: low
---

# CSV Export Templates

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
