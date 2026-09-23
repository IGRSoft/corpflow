# CSV Templates

## Template: 01_project_overview.csv

```csv
Category;Value Min;Value Max;Notes
Project Name;[NAME];;[DESCRIPTION]
Platform;[PLATFORM];;[TECH STACK]
Team Size;[N];;[ROLE]
Hourly Rate;$[RATE];;
Total SP Min;[SP_MIN];;Optimistic estimate
Total SP Max;[SP_MAX];;Pessimistic estimate
Base Hours;[HOURS_MIN];[HOURS_MAX];SP Min/Max × 6h multiplier
Buffer (15%);[BUFFER_MIN];[BUFFER_MAX];Contingency
Total Hours;[TOTAL_MIN];[TOTAL_MAX];Base + buffer
Timeline;[WEEKS_MIN];[WEEKS_MAX];[PHASES] + buffer
Budget;$[BUDGET_MIN];$[BUDGET_MAX];Total hours × rate
T-Shirt Size;[SIZE];;[N]-phase delivery
Complexity Score;[SCORE]/25;;[LEVEL]
Risk Level;[LEVEL];;[REASONS]
Backend;[STATUS];;[NOTES]
Test Coverage Target;[%]+;;Integrated with development
```

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

## Template: 04_features_breakdown.csv

```csv
Feature Group;Feature;Subtask;Size;SP Min;SP Max;Hours Min;Hours Max;Priority;Phase
[GROUP];[FEATURE];[SUBTASK] + tests;[XS-XL];[SP_MIN];[SP_MAX];[HOURS_MIN];[HOURS_MAX];[P0-P3];[N]
```

**Rules**:
- Every subtask includes "+ tests"
- Hours Min = SP Min × 6, Hours Max = SP Max × 6
- Phase number matches roadmap

## Template: 05_roadmap_milestones.csv

```csv
Phase;Week;Milestone;Deliverables;SP Min;SP Max;Hours Min;Hours Max;Dependencies
[N];[START]-[END];[MILESTONE];[DELIVERABLES];[SP_MIN];[SP_MAX];[HOURS_MIN];[HOURS_MAX];[DEPS]
Buffer;[START]-[END];Contingency;Risk mitigation, feedback;;;[BUFFER_MIN];[BUFFER_MAX];All phases
TOTAL;;;[SP_MIN];[SP_MAX];[HOURS_MIN];[HOURS_MAX];
```

## Template: 06_risk_assessment.csv

```csv
Risk ID;Risk;Category;Probability;Impact;Score;Mitigation
R-[N];[DESCRIPTION];[CATEGORY];[H/M/L];[H/M/L];[1-10];[STRATEGY]
```

**Categories**: Technical, Schedule, Resource, External

## Template: 07_budget_estimate.csv

```csv
Category;Subcategory;SP Min;SP Max;Hours Min;Hours Max;Rate;Cost Min;Cost Max;Percentage;Notes
Phase [N];[NAME];[SP_MIN];[SP_MAX];[HOURS_MIN];[HOURS_MAX];$[RATE];$[COST_MIN];$[COST_MAX];[%];[NOTES]
Subtotal;Development;[TOTAL_SP_MIN];[TOTAL_SP_MAX];[BASE_HOURS_MIN];[BASE_HOURS_MAX];$[RATE];$[BASE_COST_MIN];$[BASE_COST_MAX];[%];
Buffer;Contingency (15%);;;[BUFFER_MIN];[BUFFER_MAX];$[RATE];$[BUFFER_COST_MIN];$[BUFFER_COST_MAX];[%];Risk mitigation
TOTAL;;;[TOTAL_HOURS_MIN];[TOTAL_HOURS_MAX];$[RATE];$[TOTAL_COST_MIN];$[TOTAL_COST_MAX];100%;
```

## Template: 08_success_metrics.csv

```csv
Category;Metric;Target;Measurement;Priority
Performance;[METRIC];[TARGET];[HOW];[P0-P3]
Quality;[METRIC];[TARGET];[HOW];[P0-P3]
User Experience;[METRIC];[TARGET];[HOW];[P0-P3]
Business;[METRIC];[TARGET];[HOW];[P0-P3]
```

## Template: 09_competitive_analysis.csv

```csv
Competitor;Category;Feature;Product;Differentiation
[NAME];[CATEGORY];[FEATURE];[HOW PRODUCT DIFFERS];[ADVANTAGE]
```

## Template: 10_ios_specifics.csv

```csv
Category;Feature;Version;Implementation;Notes
Permissions;[PERMISSION];iOS [VERSION];[APPROACH];[NOTES]
Framework;[FRAMEWORK];iOS [VERSION];[APPROACH];[NOTES]
API;[API];iOS [VERSION];[APPROACH];[NOTES]
```

## Template: 11_swiftui_specifics.csv

```csv
Category;Component;Feature;Implementation;Complexity
View;[COMPONENT];[FEATURE];[APPROACH];[L/M/H]
State;[COMPONENT];[FEATURE];[APPROACH];[L/M/H]
Navigation;[COMPONENT];[FEATURE];[APPROACH];[L/M/H]
```

## Template: 12_integration_specifics.csv

```csv
SDK;Type;Documentation;Effort;Features;Risks
[SDK NAME];[Internal/External];[Quality];[Size];[FEATURES];[RISKS]
```

## Template: 13_phase_summary.csv

```csv
Phase;Name;Duration;Weeks;SP Min;SP Max;Hours Min;Hours Max;Cost Min;Cost Max;Key Deliverables;Dependencies
[N];[NAME];[N.N] weeks;[START]-[END];[SP_MIN];[SP_MAX];[HOURS_MIN];[HOURS_MAX];$[COST_MIN];$[COST_MAX];[DELIVERABLES];[DEPS]
Buffer;Contingency;[N] weeks;[START]-[END];;;[BUFFER_MIN];[BUFFER_MAX];$[BUFFER_COST_MIN];$[BUFFER_COST_MAX];Risk mitigation;All
TOTAL;;[RANGE];;[TOTAL_SP_MIN];[TOTAL_SP_MAX];[TOTAL_HOURS_MIN];[TOTAL_HOURS_MAX];$[TOTAL_COST_MIN];$[TOTAL_COST_MAX];;
```
