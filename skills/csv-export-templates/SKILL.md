---
name: csv-export-templates
description: Use when generating CSV export files for estimates, budgets, timelines, or reports. 13-category CSV export structure for Google Sheets import.
# G3: no standalone value — the layout is keyed to an /estimate --detailed breakdown a user does not have on hand.
disable-model-invocation: true
---

# CSV Export Templates

Canonical 13-file export pack for Google Sheets import, referenced by `/estimate --export csv`;
define the file list and format here only.
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
| 10 | `<platform>_specifics.csv` | Platform details |
| 11 | `<framework>_specifics.csv` | Framework/runtime details |
| 12 | integration_specifics.csv | SDK/API details |
| 13 | phase_summary.csv | Phase rollup |

### Platform Variants (files 10 and 11)

Filename and column schema of files 10 and 11 resolve from `--platform`; keys match
`skills/shared/compatible-plugins.md § Registry`.

| `--platform` | File 10 | File 11 |
|--------------|---------|---------|
| `apple`      | `10_ios_specifics.csv` | `11_swiftui_specifics.csv` |
| `android`    | `10_android_specifics.csv` | `11_jetpack_specifics.csv` |
| `web`        | `10_web_specifics.csv` | `11_framework_specifics.csv` |
| `systems`    | `10_systems_specifics.csv` | `11_toolchain_specifics.csv` |
| `backend`    | `10_backend_specifics.csv` | `11_runtime_specifics.csv` |
| `ai`         | `10_ai_specifics.csv` | `11_model_stack_specifics.csv` |
| `all` (default) | one file 10/11 pair per platform in scope | |

### File 12 and column schemas

File 12 (`integration_specifics.csv`) keeps its filename on every platform; its rows list whatever
that platform integrates against (SDKs, APIs, system libraries, upstream services, model providers).

`references/templates.md` shows files 10 and 11 for `apple` only; other platforms reuse that
column shape with their own rows.

## Validator Script

```sh
bash "${CLAUDE_SKILL_DIR}/scripts/validate-export.sh" --dir <export-dir> [--out <report.csv>]
```

- Writes `<export-dir>/validation_report.csv` (columns `check;status;detail`).
- Exits `0` on full pass, `1` on any violation, `2` on usage or missing-directory error.
- Finds columns by header name, so column order does not matter.
- `--self-test` runs a fixture check with no network.

## Validation Rules

The spec the validator implements; run the script rather than checking by hand.

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
