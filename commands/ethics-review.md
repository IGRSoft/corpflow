---
name: ethics-review
description: Review tasks, features, or architecture for constitutional compliance; --lens harm runs a full stakeholder harm assessment
argument-hint: '[<target>] [--lens full|harm] [--scope task|feature|architecture|code] [--depth quick|standard|comprehensive] [--focus safety|honesty|harm|autonomy|all] [--stakeholders users|operators|society|all] [--include-benefits true|false] [--mitigation true|false] [--output summary|detailed|checklist|matrix|report]'
allowed-tools: Read, Glob, Grep
related:
  - agents/ethics-reviewer.md
  - skills/claude-constitution/SKILL.md
---

# /ethics-review

Review a task, feature, or code for alignment with Claude's constitutional principles: safety,
honesty, harm avoidance, user autonomy. Principles canon: `skills/claude-constitution/SKILL.md`;
the analysis runs through `agents/ethics-reviewer.md`, which escalates complex or critical cases
to human/stakeholder review.

## Lenses

| `--lens` | Mode |
|---|---|
| `full` (default) | Standard constitutional review across Safety, Honesty, Harm, Autonomy |
| `harm` | Harm-avoidance deep-dive: cost-benefit, stakeholder impact, harm matrix, mitigations |

`--lens harm` selects the deep-dive mode (stakeholder / probability / severity analysis);
`--focus harm` only scopes a standard `--lens full` review to the Harm category — a lighter pass.

## Options

`target` — task, feature, file, or description. Optional under `--lens full` (the current
task), required under `--lens harm`.

| Option | Lens | Values | Default | Purpose |
|---|---|---|---|---|
| `--lens` | both | `full`, `harm` | `full` | Constitutional review or harm deep-dive |
| `--output` | both | `summary`, `detailed`, `checklist`, `matrix`, `report` | `summary` | Output format (`matrix` is harm-lens only) |
| `--scope` | full | `task`, `feature`, `architecture`, `code` | `task` | Review scope |
| `--depth` | full | `quick`, `standard`, `comprehensive` | `standard` | Analysis depth |
| `--focus` | full | `safety`, `honesty`, `harm`, `autonomy`, `all` | `all` | Focus category |
| `--stakeholders` | harm | `users`, `operators`, `society`, `all` | `all` | Impact scope |
| `--include-benefits` | harm | bool | `true` | Include benefits in the cost-benefit analysis |
| `--mitigation` | harm | bool | `true` | Include mitigation recommendations |

## Examples

```
/ethics-review [<target>] [--lens full] [--scope task|feature|architecture|code] [--depth quick|standard|comprehensive] [--focus safety|honesty|harm|autonomy|all] [--output <format>]
/ethics-review <target> --lens harm [--stakeholders users|operators|society|all] [--include-benefits true|false] [--mitigation true|false] [--output <format>]
/ethics-review --depth quick                                                  # current task
/ethics-review "user authentication system" --scope feature --depth comprehensive
/ethics-review src/payment.ts --scope code --focus safety --output checklist
/ethics-review "recommendation algorithm" --focus harm --depth comprehensive  # scoped standard pass
/ethics-review "AI-powered content recommendation" --lens harm
/ethics-review "data collection expansion" --lens harm --output matrix --stakeholders all
/ethics-review "auto-save feature" --lens harm --stakeholders users --mitigation false --include-benefits false
```

## Output (`--lens full`)

### Summary Format (default)
```
Ethics Review: [target]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall: ✅ Compliant | ⚠️ Concerns | ❌ Violations

Safety:    [✅|⚠️|❌] [brief assessment]
Honesty:   [✅|⚠️|❌] [brief assessment]
Harm:      [✅|⚠️|❌] [brief assessment]
Autonomy:  [✅|⚠️|❌] [brief assessment]

Concerns: [count]
Hard Violations: [count]

Recommendations:
1. [recommendation]
```

### Detailed Format

Adds per-category analysis, evidence from code/documentation with line references,
mitigation suggestions, and the related constitutional principles.

### Checklist Format

One `[ ]` line per dimension in § Review Categories, grouped under
`SAFETY` / `HONESTY` / `HARM AVOIDANCE` / `USER AUTONOMY`.

## Review Categories (`--lens full`)

Assessed dimensions per category — also the source of the checklist rows above:

| Category | Dimensions |
|---|---|
| Safety | Physical harm potential · information security risks · dual-use concerns · safeguard adequacy · hard constraint violations |
| Honesty | Truthfulness of outputs · calibration of uncertainty · transparency about limitations · deception potential · forthright information sharing |
| Harm avoidance | Direct and indirect harm · cumulative impacts · vulnerable populations · privacy implications · user wellbeing |
| User autonomy | User control preservation · informed consent · manipulation avoidance · fair choice presentation · dependency creation risks |

## Output (`--lens harm`)

### Summary Format (default)
```
Harm Assessment: [target]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Risk Level: [Low|Medium|High|Critical]

Potential Harms:
• [harm] - [probability] / [severity]

Affected Stakeholders:
• Users / Operators / Society: [impact summary each, per --stakeholders]

Benefits (--include-benefits):
• [benefit]

Cost-Benefit: [favorable|unfavorable|requires mitigation]

Top Mitigations (--mitigation):
1. [mitigation]
```

### Matrix Format (`--output matrix`)

Plot each harm as `[Hn]` in the probability × severity cell, then legend the
`[Hn]` labels beneath.

```
                    │ Low    │ Medium │ High   │ Critical
─────────────────────────────────────────────────────────
Unlikely (< 10%)    │        │ [H1]   │        │
Possible (10-40%)   │        │        │ [H2]   │
Likely (40-70%)     │ [H3]   │        │        │
Very Likely (> 70%) │        │        │        │
```

### Harm Categories

| Category | Definition | Considerations |
|---|---|---|
| Direct | Physical, psychological, financial, or reputational harm caused by the feature itself | Immediate negative impacts, health and safety, financial loss, reputation damage, emotional distress |
| Indirect | Downstream consequences of the primary action | Second-order effects, long-term consequences, cascading impacts, ecosystem effects |
| Facilitated | Harm the feature enables others to cause | Misuse potential, weaponization risk, amplification of bad actors, dual-use concerns |
| Autonomy | Harm to agency, informed consent, self-determination | Manipulation potential, choice-architecture fairness, dependency creation, information asymmetry |

### Probability Assessment

| Level | Probability | Description |
|-------|-------------|-------------|
| Unlikely | < 10% | Rare edge cases only |
| Possible | 10-40% | Could happen under specific conditions |
| Likely | 40-70% | Expected to occur regularly |
| Very Likely | > 70% | Will almost certainly occur |

### Severity Assessment

| Level | Description | Examples |
|-------|-------------|----------|
| Low | Minor inconvenience | Confusion, slight frustration |
| Medium | Meaningful negative impact | Data loss, financial cost, stress |
| High | Serious harm | Safety risk, major financial loss, trauma |
| Critical | Catastrophic harm | Life-threatening, irreversible damage |

### Cost-Benefit Framework

| Direction | Factors |
|---|---|
| Increases acceptable risk | Strong benefit to users/society · user consent and awareness · harm is reversible · good mitigations exist · the alternative causes greater harm |
| Decreases acceptable risk | Vulnerable populations affected · harm is irreversible · no consent or awareness · disproportionate impact on the disadvantaged · a less harmful alternative exists |

### Mitigation Strategies

- **Prevention**: input validation, access controls, rate limiting, content filtering.
- **Detection**: monitoring systems, anomaly detection, user reporting, audit logging.
- **Response**: graceful degradation, incident response plans, user notification, rollback capabilities.
- **Recovery**: data restoration, user support, compensation mechanisms, learning processes.

## Severity Levels

| Level | Icon | Meaning | Action |
|-------|------|---------|--------|
| Compliant | ✅ | Meets constitutional requirements | Proceed |
| Advisory | 💡 | Could be improved | Consider improvements |
| Concern | ⚠️ | Potential issues identified | Address before proceeding |
| Violation | ❌ | Hard constraint violated | Must fix before proceeding |

## Hard Constraint Violations

Always ❌ Violation, regardless of benefits:
- Weapons of mass destruction assistance
- CSAM generation or assistance
- Critical infrastructure attacks
- Undermining AI oversight mechanisms
- Malware or cyberweapon creation
- Identity theft or fraud facilitation
- Enabling mass surveillance for oppression
- Biological weapon creation assistance

## Integration

Invokable at any worktask stage — PL: planned features / harms before design ·
AR: architecture safety and harm implications · DV: implementation harm potential ·
QA: ethics in quality criteria · ST: stakeholder review of the harm assessment
(`--lens harm`).
