---
name: harm-assessment
description: Evaluate potential harms of features, decisions, or code using constitutional harm avoidance framework
argument-hint: '<feature, decision, or scenario>'
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - commands/ethics-review.md
  - commands/transparency-check.md
  - agents/ethics-reviewer.md
  - skills/claude-constitution/SKILL.md
---

> **When to use**: `/harm-assessment` for stakeholder impact analysis. `/ethics-review` for constitutional compliance. `/transparency-check` for honesty properties.

# /harm-assessment

Comprehensive evaluation of potential harms using Claude's constitutional harm avoidance framework, including cost-benefit analysis, stakeholder impact, and mitigation recommendations.

> **Broad screening first**: For general ethics screening, use `/ethics-review` first. This command provides a specialized deep-dive into harm analysis.

## Usage

```
/harm-assessment [target] [options]
```

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| target | string | Yes | Feature, decision, code, or description to assess |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| --stakeholders | enum | all | Impact scope: `users`, `operators`, `society`, `all` |
| --format | enum | summary | Output: `summary`, `detailed`, `matrix`, `report` |
| --include-benefits | bool | true | Include benefits in analysis |
| --mitigation | bool | true | Include mitigation recommendations |

## Output

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

### Matrix Format
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

## Harm Categories

### Direct Harms
Physical, psychological, financial, or reputational harm directly caused by the feature or action.

**Considerations:**
- Immediate negative impacts
- Health and safety effects
- Financial losses
- Reputation damage
- Emotional distress

### Indirect Harms
Downstream effects that may occur as a consequence of the primary action.

**Considerations:**
- Second-order effects
- Long-term consequences
- Cascading impacts
- Ecosystem effects

### Facilitated Harms
Harms that the feature could enable others to cause.

**Considerations:**
- Misuse potential
- Weaponization risk
- Amplification of bad actors
- Dual-use concerns

### Autonomy Harms
Harms to user agency, informed consent, and self-determination.

**Considerations:**
- Manipulation potential
- Choice architecture fairness
- Dependency creation
- Information asymmetry

## Probability Assessment

| Level | Probability | Description |
|-------|-------------|-------------|
| Unlikely | < 10% | Rare edge cases only |
| Possible | 10-40% | Could happen under specific conditions |
| Likely | 40-70% | Expected to occur regularly |
| Very Likely | > 70% | Will almost certainly occur |

## Severity Assessment

| Level | Description | Examples |
|-------|-------------|----------|
| Low | Minor inconvenience | Confusion, slight frustration |
| Medium | Meaningful negative impact | Data loss, financial cost, stress |
| High | Serious harm | Safety risk, major financial loss, trauma |
| Critical | Catastrophic harm | Life-threatening, irreversible damage |

## Cost-Benefit Framework

### Factors Increasing Acceptable Risk
- Strong benefit to users/society
- User consent and awareness
- Harm is reversible
- Good mitigation options exist
- Alternative would cause greater harm

### Factors Decreasing Acceptable Risk
- Vulnerable populations affected
- Harm is irreversible
- No user consent or awareness
- Disproportionate impact on disadvantaged
- Alternative exists with less harm

## Examples

### Feature Harm Assessment
```
/harm-assessment "AI-powered content recommendation"
```

### User-Focused Assessment
```
/harm-assessment "auto-save feature" --stakeholders users
```

### Detailed Matrix Report
```
/harm-assessment "data collection expansion" --format matrix --stakeholders all
```

### Society Impact Focus
```
/harm-assessment "viral sharing mechanism" --stakeholders society
```

### Assessment Without Benefits
```
/harm-assessment "targeted advertising" --include-benefits false
```

## Hard Constraints

These harms are NEVER acceptable regardless of benefits:

- Weapons of mass destruction assistance
- CSAM generation or facilitation
- Critical infrastructure attacks
- Undermining AI oversight mechanisms
- Enabling mass surveillance for oppression
- Biological weapon creation assistance

## Mitigation Strategies

### Prevention
- Input validation
- Access controls
- Rate limiting
- Content filtering

### Detection
- Monitoring systems
- Anomaly detection
- User reporting
- Audit logging

### Response
- Graceful degradation
- Incident response plans
- User notification
- Rollback capabilities

### Recovery
- Data restoration
- User support
- Compensation mechanisms
- Learning processes

## Integration

### Worktask Integration
- **P Stage**: Assess proposed features before design
- **A Stage**: Evaluate architectural harm implications
- **D Stage**: Review implementation for unintended harms
- **S Stage**: Stakeholder review of harm assessment

### Related Commands
- `/ethics-review` - Broader constitutional compliance
- `/transparency-check` - Honesty verification
- `/risk-assess` - Technical risk assessment

### Agent Coordination
- Uses `ethics-reviewer` agent for analysis
- Escalates critical harms to stakeholder review
- Integrates with security and safety worktasks

