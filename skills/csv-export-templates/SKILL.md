---
name: csv-export-templates
description: Use when generating CSV export files for estimates, budgets, timelines, or reports. 13-category CSV export structure for Google Sheets import.
effort: low
---

# CSV Export Templates

Canonical 13-category export shape for Google Sheets import — `/estimate --export csv` and
`/cost-report --export` reference this file; never redefine the file list or format elsewhere.
Per-file column definitions: `${CLAUDE_SKILL_DIR}/references/templates.md`.

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
| 10 | `<platform>_specifics.csv` | Platform details — name resolves per `--platform` |
| 11 | `<framework>_specifics.csv` | Framework/runtime details — name resolves per `--platform` |
| 12 | integration_specifics.csv | SDK/API details |
| 13 | phase_summary.csv | Phase rollup |

### Platform Variants (files 10 and 11)

Files 10 and 11 have no fixed name — filename and column schema both resolve from `--platform`,
which has no default. Keys match `skills/shared/compatible-plugins.md § Registry`.

| `--platform` | File 10 | File 11 |
|--------------|---------|---------|
| `apple`      | `10_ios_specifics.csv` | `11_swiftui_specifics.csv` |
| `android`    | `10_android_specifics.csv` | `11_jetpack_specifics.csv` |
| `web`        | `10_web_specifics.csv` | `11_framework_specifics.csv` |
| `systems`    | `10_systems_specifics.csv` | `11_toolchain_specifics.csv` |
| `backend`    | `10_backend_specifics.csv` | `11_runtime_specifics.csv` |
| `ai`         | `10_ai_specifics.csv` | `11_model_stack_specifics.csv` |
| `all` (default) | one set per platform in scope | — |

### File 12 and column schemas

File 12 (`integration_specifics.csv`) keeps a stable filename across platforms; its rows enumerate
whatever that platform integrates against — Apple SDKs, Android/Jetpack APIs, web SDKs, system
libraries and toolchains, upstream services and datastores, or model/inference providers.

`references/templates.md` gives the column schema for files 10 and 11 using the `apple` variant as
its worked example; other platforms reuse that column shape with their own rows.

## Validator Script

```sh
bash skills/csv-export-templates/scripts/validate-export.sh --dir <export-dir> [--out <report.csv>]
```

- Emits `<export-dir>/validation_report.csv` (columns: `check;status;detail`).
- Exits `0` on full pass, `1` on any violation, `2` on usage/missing-file error.
- Columns are keyed by **header name**, not position — safe against column reordering.
- Semicolon-delimited CSVs with quoted semicolons parse correctly (embedded `python3 csv` heredoc).
- `--self-test` runs a no-network fixture check (matching set exits 0; mismatched set exits 1).

## Validation Rules

The spec the validator implements — in the happy path run the script instead of checking by hand.
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
