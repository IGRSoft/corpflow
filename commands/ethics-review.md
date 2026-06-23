---
name: ethics-review
description: Review tasks, features, or architecture for constitutional compliance with Claude's ethical principles
argument-hint: <feature or decision to review>
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - commands/harm-assessment.md
  - commands/transparency-check.md
  - commands/risk-assess.md
  - agents/ethics-reviewer.md
  - skills/claude-constitution/SKILL.md
---

> **When to use**: `/ethics-review` for constitutional compliance. `/harm-assessment` for stakeholder impact analysis. `/transparency-check` for honesty properties.

# /ethics-review

Review tasks, features, or code for alignment with Claude's constitutional principles including safety, honesty, harm avoidance, and ethical guidelines.

> **For deeper analysis**: Use `/harm-assessment` for comprehensive harm evaluation, or `/transparency-check` for detailed honesty property verification.

## Usage

```
/ethics-review [target] [options]
```

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| target | string | No | Task, feature, file, or description to review |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| --scope | enum | task | Review scope: `task`, `feature`, `architecture`, `code` |
| --depth | enum | standard | Analysis depth: `quick`, `standard`, `comprehensive` |
| --focus | enum | all | Focus area: `safety`, `honesty`, `harm`, `autonomy`, `all` |
| --output | enum | summary | Output format: `summary`, `detailed`, `checklist`, `report` |

## Output

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

## Review Categories

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

### Architecture Review with Report
```
/ethics-review --scope architecture --output report
```

### Harm Assessment Focus
```
/ethics-review "recommendation algorithm" --focus harm --depth comprehensive
```

## Severity Levels

| Level | Icon | Meaning | Action |
|-------|------|---------|--------|
| Compliant | ✅ | Meets constitutional requirements | Proceed |
| Advisory | 💡 | Could be improved | Consider improvements |
| Concern | ⚠️ | Potential issues identified | Address before proceeding |
| Violation | ❌ | Hard constraint violated | Must fix before proceeding |

## Hard Constraint Violations

The following always result in ❌ Violation:
- Weapons of mass destruction assistance
- CSAM generation or assistance
- Critical infrastructure attacks
- Undermining AI oversight mechanisms
- Malware or cyberweapon creation
- Identity theft or fraud facilitation

## Integration

### Worktask Integration
Can be invoked at any worktask stage:
- **P Stage**: Review planned features for ethical concerns
- **A Stage**: Review architecture for safety implications
- **D Stage**: Review implementation for harm potential
- **Q Stage**: Include ethics in quality criteria

### Agent Coordination
- Uses `ethics-reviewer` agent for analysis
- Can escalate to human review for complex cases
- Integrates with risk assessment worktasks

