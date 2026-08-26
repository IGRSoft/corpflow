---
name: ethics-review
description: Review tasks, features, or architecture for constitutional compliance; --lens harm runs a full stakeholder harm assessment
argument-hint: <feature or decision to review> [--lens harm|full]
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - agents/ethics-reviewer.md
  - skills/claude-constitution/SKILL.md
---

> **When to use**: `/ethics-review` for constitutional compliance (`--lens full`, default). Add `--lens harm` for a specialized stakeholder-impact harm-avoidance deep-dive.

# /ethics-review

Review tasks, features, or code for alignment with Claude's constitutional principles including safety, honesty, harm avoidance, and ethical guidelines. Principles canon: `skills/claude-constitution/SKILL.md`; analysis is performed by `agents/ethics-reviewer.md`.

## Lenses

| `--lens` | Mode |
|---|---|
| `full` (default) | Standard constitutional review across Safety, Honesty, Harm, Autonomy |
| `harm` | Harm-avoidance deep-dive: cost-benefit, stakeholder impact, harm matrix, mitigations |

> **`--lens harm` ≠ `--focus harm`.** `--lens harm` selects the deep-dive mode
> (stakeholder / probability / severity analysis). `--focus harm` merely scopes a
> standard `--lens full` review to the Harm category — a much lighter pass.

## Usage

```
/ethics-review [target] [options]
/ethics-review [target] --lens harm [harm options]
```

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| target | string | No (`--lens full`) / Yes (`--lens harm`) | Task, feature, file, or description to review |

## Options

### Shared

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| --lens | enum | full | Review lens: `full` (constitutional) or `harm` (harm-avoidance deep-dive) |
| --output | enum | summary | Output format: `summary`, `detailed`, `checklist`, `matrix`, `report` (`matrix` is harm-lens only) |

### `--lens full` options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| --scope | enum | task | Review scope: `task`, `feature`, `architecture`, `code` |
| --depth | enum | standard | Analysis depth: `quick`, `standard`, `comprehensive` |
| --focus | enum | all | Focus category: `safety`, `honesty`, `harm`, `autonomy`, `all` |

### `--lens harm` options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| --stakeholders | enum | all | Impact scope: `users`, `operators`, `society`, `all` |
| --include-benefits | bool | true | Include benefits in the cost-benefit analysis |
| --mitigation | bool | true | Include mitigation recommendations |

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

## Examples

```
/ethics-review --depth quick                                                  # current task
/ethics-review "user authentication system" --scope feature --depth comprehensive
/ethics-review src/payment.ts --scope code --focus safety --output checklist
/ethics-review "recommendation algorithm" --focus harm --depth comprehensive  # scoped standard pass
/ethics-review "AI-powered content recommendation" --lens harm
/ethics-review "auto-save feature" --lens harm --stakeholders users --mitigation false
/ethics-review "data collection expansion" --lens harm --output matrix --stakeholders all
/ethics-review "targeted advertising" --lens harm --include-benefits false
```

## Severity Levels

| Level | Icon | Meaning | Action |
|-------|------|---------|--------|
| Compliant | ✅ | Meets constitutional requirements | Proceed |
| Advisory | 💡 | Could be improved | Consider improvements |
| Concern | ⚠️ | Potential issues identified | Address before proceeding |
| Violation | ❌ | Hard constraint violated | Must fix before proceeding |

## Hard Constraint Violations

The following always result in ❌ Violation (never acceptable regardless of benefits):
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

- Analysis runs through the `ethics-reviewer` agent; complex or critical cases
  escalate to human/stakeholder review.
