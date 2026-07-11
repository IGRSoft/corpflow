---
name: ethics-review
description: Review tasks, features, or architecture for constitutional compliance; --lens harm runs a full stakeholder harm assessment
argument-hint: <feature or decision to review> [--lens harm|full]
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - commands/pm-risk.md
  - agents/ethics-reviewer.md
  - skills/claude-constitution/SKILL.md
---

> **When to use**: `/ethics-review` for constitutional compliance (`--lens full`, default). Add `--lens harm` for a specialized stakeholder-impact harm-avoidance deep-dive.

# /ethics-review

Review tasks, features, or code for alignment with Claude's constitutional principles including safety, honesty, harm avoidance, and ethical guidelines.

## Lenses

`ethics-review` runs under one of two lenses (`--lens`):

- `--lens full` (default) — standard constitutional review across Safety, Honesty,
  Harm, and Autonomy categories.
- `--lens harm` — a comprehensive harm-avoidance deep-dive: cost-benefit analysis,
  stakeholder impact, harm-category matrix, and mitigation recommendations.

> **`--lens harm` vs `--focus harm` — do not confuse the two:**
> `--lens harm` selects the *full harm-avoidance deep-dive mode* (the ported
> harm-avoidance framework below). `--focus harm` (a `--lens full` option) merely
> *scopes the standard review to the Harm category* — a much lighter pass. Use
> `--lens harm` when you want the stakeholder/probability/severity analysis; use
> `--focus harm` to narrow a standard review.

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
| --output | enum | summary | Output format: `summary`, `detailed`, `checklist`, `matrix`, `report` |

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

(`matrix` is the harm-lens-specific value of `--output`.)

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
2. [recommendation]
```

### Detailed Format
Includes:
- Full analysis by category
- Evidence from code/documentation
- Specific line references
- Mitigation suggestions
- Related constitutional principles

### Checklist Format
```
Constitutional Compliance Checklist
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SAFETY
[ ] No physical harm potential
[ ] No information security risks
[ ] No dual-use concerns
[ ] Appropriate safeguards in place

HONESTY
[ ] Outputs are truthful
[ ] Uncertainty properly calibrated
[ ] No deceptive patterns
[ ] Transparent about limitations

HARM AVOIDANCE
[ ] User wellbeing prioritized
[ ] No manipulative patterns
[ ] Vulnerable populations considered
[ ] Privacy protected

USER AUTONOMY
[ ] Informed consent supported
[ ] User control preserved
[ ] No autonomy undermining
[ ] Fair choice presentation
```

## Review Categories (`--lens full`)

### Safety Assessment
- Physical harm potential
- Information security risks
- Dual-use concerns
- Safeguard adequacy
- Hard constraint violations

### Honesty Assessment
- Truthfulness of outputs
- Calibration of uncertainty
- Transparency about limitations
- Deception potential
- Forthright information sharing

### Harm Assessment
- Direct harm potential
- Indirect harm risks
- Cumulative impacts
- Vulnerable population effects
- Privacy implications

### Autonomy Assessment
- User control preservation
- Informed consent support
- Manipulation avoidance
- Fair choice presentation
- Dependency creation risks

## Output (`--lens harm`)

Comprehensive harm-avoidance evaluation: cost-benefit analysis, stakeholder impact,
and mitigation recommendations.

### Summary Format (default)
```
Harm Assessment: [target]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Risk Level: [Low|Medium|High|Critical]

Potential Harms:
• [harm 1] - [probability] / [severity]
• [harm 2] - [probability] / [severity]

Affected Stakeholders:
• Users: [impact summary]
• Operators: [impact summary]
• Society: [impact summary]

Benefits (if any):
• [benefit 1]
• [benefit 2]

Cost-Benefit: [favorable|unfavorable|requires mitigation]

Top Mitigations:
1. [mitigation]
2. [mitigation]
```

### Matrix Format (`--output matrix`)
```
Harm Assessment Matrix
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    │ Low    │ Medium │ High   │ Critical
─────────────────────────────────────────────────────────
Unlikely (< 10%)    │        │ [H1]   │        │
Possible (10-40%)   │        │        │ [H2]   │
Likely (40-70%)     │ [H3]   │        │        │
Very Likely (> 70%) │        │        │        │

Legend:
[H1] Privacy data exposure
[H2] Manipulation potential
[H3] Minor usability harm
```

### Harm Categories

#### Direct Harms
Physical, psychological, financial, or reputational harm directly caused by the feature or action.

**Considerations:** immediate negative impacts, health and safety effects, financial losses, reputation damage, emotional distress.

#### Indirect Harms
Downstream effects that may occur as a consequence of the primary action.

**Considerations:** second-order effects, long-term consequences, cascading impacts, ecosystem effects.

#### Facilitated Harms
Harms that the feature could enable others to cause.

**Considerations:** misuse potential, weaponization risk, amplification of bad actors, dual-use concerns.

#### Autonomy Harms
Harms to user agency, informed consent, and self-determination.

**Considerations:** manipulation potential, choice architecture fairness, dependency creation, information asymmetry.

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

**Factors Increasing Acceptable Risk:** strong benefit to users/society, user consent and awareness, harm is reversible, good mitigation options exist, alternative would cause greater harm.

**Factors Decreasing Acceptable Risk:** vulnerable populations affected, harm is irreversible, no user consent or awareness, disproportionate impact on disadvantaged, alternative exists with less harm.

### Mitigation Strategies

- **Prevention**: input validation, access controls, rate limiting, content filtering.
- **Detection**: monitoring systems, anomaly detection, user reporting, audit logging.
- **Response**: graceful degradation, incident response plans, user notification, rollback capabilities.
- **Recovery**: data restoration, user support, compensation mechanisms, learning processes.

## Examples

### Quick Review of Current Task
```
/ethics-review --depth quick
```

### Comprehensive Feature Review
```
/ethics-review "user authentication system" --scope feature --depth comprehensive
```

### Safety-Focused Code Review
```
/ethics-review src/payment.ts --scope code --focus safety
```

### Standard Review Scoped to the Harm Category
```
/ethics-review "recommendation algorithm" --focus harm --depth comprehensive
```

### Full Harm-Avoidance Deep-Dive
```
/ethics-review "AI-powered content recommendation" --lens harm
/ethics-review "auto-save feature" --lens harm --stakeholders users
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

### Worktask Integration
Can be invoked at any worktask stage:
- **PL Stage**: Review planned features for ethical concerns / assess harms before design
- **AR Stage**: Review architecture for safety and harm implications
- **DV Stage**: Review implementation for harm potential
- **QA Stage**: Include ethics in quality criteria
- **ST Stage**: Stakeholder review of harm assessment (`--lens harm`)

### Related Commands
- `/pm-risk` - Technical risk assessment

### Agent Coordination
- Uses `ethics-reviewer` agent for analysis
- Can escalate to human/stakeholder review for complex or critical cases
- Integrates with risk assessment and security worktasks
