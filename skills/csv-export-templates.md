# CSV Export Templates

13-category export structure for Google Sheets import.

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

---

## Template: 01_project_overview.csv

```csv
Category;Value;Notes
Project Name;[NAME];[DESCRIPTION]
Platform;[PLATFORM];[TECH STACK]
Team Size;[N];[ROLE]
Hourly Rate;$[RATE];
Total Story Points;[SP];[NOTES]
Base Hours;[HOURS];SP × 6h multiplier
Buffer (15%);[BUFFER];Contingency
Total Hours;[TOTAL];Base + buffer
Timeline;[WEEKS];[PHASES] + buffer
Budget;$[BUDGET];Total hours × rate
T-Shirt Size;[SIZE];[N]-phase delivery
Complexity Score;[SCORE]/25;[LEVEL]
Risk Level;[LEVEL];[REASONS]
Backend;[STATUS];[NOTES]
Test Coverage Target;[%]+;Integrated with development
```

---

## Template: 02_complexity_analysis.csv

```csv
Factor;Score;Max;Rationale
Technical Complexity;[1-5];5;[REASON]
Integration Points;[1-5];5;[REASON]
Risk Level;[1-5];5;[REASON]
Unknowns;[1-5];5;[REASON]
Domain Expertise;[1-5];5;[REASON]
TOTAL;[SUM];25;[LEVEL: LOW/MEDIUM/HIGH]
```

---

## Template: 03_technology_stack.csv

```csv
Category;Technology;Version;Purpose
Language;[LANG];[VERSION];Primary development
Framework;[FRAMEWORK];[VERSION];UI/Application
Platform;[PLATFORM];[VERSION];Target OS
SDK;[SDK];[VERSION];[PURPOSE]
API;[API];[VERSION];[PURPOSE]
Database;[DB];[VERSION];Data persistence
```

---

## Template: 04_features_breakdown.csv

```csv
Feature Group;Feature;Subtask;Size;Story Points;Hours;Priority;Phase
[GROUP];[FEATURE];[SUBTASK] + tests;[XS-XL];[SP];[HOURS];[P0-P3];[N]
```

**Rules**:
- Every subtask includes "+ tests"
- Hours = SP × 6
- Phase number matches roadmap

---

## Template: 05_roadmap_milestones.csv

```csv
Phase;Week;Milestone;Deliverables;Story Points;Hours;Dependencies
[N];[START]-[END];[MILESTONE];[DELIVERABLES];[SP];[HOURS];[DEPS]
Buffer;[START]-[END];Contingency;Risk mitigation, feedback;;[BUFFER];All phases
TOTAL;;;[SP];[HOURS];
```

---

## Template: 06_risk_assessment.csv

```csv
Risk ID;Risk;Category;Probability;Impact;Score;Mitigation
R-[N];[DESCRIPTION];[CATEGORY];[H/M/L];[H/M/L];[1-10];[STRATEGY]
```

**Categories**: Technical, Schedule, Resource, External

---

## Template: 07_budget_estimate.csv

```csv
Category;Subcategory;Story Points;Hours;Rate;Cost;Percentage;Notes
Phase [N];[NAME];[SP];[HOURS];$[RATE];$[COST];[%];[NOTES]
Subtotal;Development;[TOTAL_SP];[BASE_HOURS];$[RATE];$[BASE_COST];[%];
Buffer;Contingency (15%);;[BUFFER];$[RATE];$[BUFFER_COST];[%];Risk mitigation
TOTAL;;;[TOTAL_HOURS];$[RATE];$[TOTAL_COST];100%;
```

---

## Template: 08_success_metrics.csv

```csv
Category;Metric;Target;Measurement;Priority
Performance;[METRIC];[TARGET];[HOW];[P0-P3]
Quality;[METRIC];[TARGET];[HOW];[P0-P3]
User Experience;[METRIC];[TARGET];[HOW];[P0-P3]
Business;[METRIC];[TARGET];[HOW];[P0-P3]
```

---

## Template: 09_competitive_analysis.csv

```csv
Competitor;Category;Feature;Product;Differentiation
[NAME];[CATEGORY];[FEATURE];[HOW PRODUCT DIFFERS];[ADVANTAGE]
```

---

## Template: 10_ios_specifics.csv

```csv
Category;Feature;Version;Implementation;Notes
Permissions;[PERMISSION];iOS [VERSION];[APPROACH];[NOTES]
Framework;[FRAMEWORK];iOS [VERSION];[APPROACH];[NOTES]
API;[API];iOS [VERSION];[APPROACH];[NOTES]
```

---

## Template: 11_swiftui_specifics.csv

```csv
Category;Component;Feature;Implementation;Complexity
View;[COMPONENT];[FEATURE];[APPROACH];[L/M/H]
State;[COMPONENT];[FEATURE];[APPROACH];[L/M/H]
Navigation;[COMPONENT];[FEATURE];[APPROACH];[L/M/H]
```

---

## Template: 12_integration_specifics.csv

```csv
SDK;Type;Documentation;Effort;Features;Risks
[SDK NAME];[Internal/External];[Quality];[Size];[FEATURES];[RISKS]
```

---

## Template: 13_phase_summary.csv

```csv
Phase;Name;Duration;Weeks;Story Points;Hours;Cost;Key Deliverables;Dependencies
[N];[NAME];[N.N] weeks;[START]-[END];[SP];[HOURS];$[COST];[DELIVERABLES];[DEPS]
Buffer;Contingency;[N] weeks;[START]-[END];;[BUFFER];$[BUFFER_COST];Risk mitigation;All
TOTAL;;[RANGE];;[TOTAL_SP];[TOTAL_HOURS];$[TOTAL_COST];;
```

---

## Validation Rules

After export, verify:

1. **Totals match**:
   - 04 features SP = 13 phase summary SP
   - 07 budget hours = 13 phase summary hours
   - 01 overview matches 13 summary

2. **Phase constraints**:
   - No phase > 160 hours
   - Week ranges continuous
   - Dependencies valid

3. **Format valid**:
   - Semicolon delimiter
   - UTF-8 encoding
   - Headers present
