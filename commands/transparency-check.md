---
name: transparency-check
description: Verify honesty and transparency properties in outputs, documentation, and code
argument-hint: '<output, document, or code path>'
allowed-tools: Read, Glob, Grep
model: sonnet
related:
  - ./ethics-review.md
  - ./harm-assessment.md
  - agents/ethics-reviewer.md
  - skills/claude-constitution/SKILL.md
---

> **When to use**: `/transparency-check` for honesty properties. `/ethics-review` for constitutional compliance. `/harm-assessment` for stakeholder impact analysis.

# /transparency-check

Verify that outputs, documentation, and code adhere to Claude's seven honesty properties: truthful, calibrated, transparent, forthright, non-deceptive, non-manipulative, and autonomy-preserving.

## Usage

```
/transparency-check [target] [options]
```

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| target | string | No | Response, documentation, or code to check |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| --target-type | enum | auto | Target type: `response`, `documentation`, `code`, `ui`, `auto` |
| --properties | enum | all | Which properties: `truthful`, `calibrated`, `transparent`, `forthright`, `non-deceptive`, `non-manipulative`, `autonomy`, `all` |
| --output | enum | checklist | Output format: `checklist`, `detailed`, `summary` |

## Output

### Checklist Format (default)
```
Transparency Check: [target]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Overall: ✅ Honest | ⚠️ Concerns | ❌ Violations

HONESTY PROPERTIES
[✅] Truthful - Only asserts believed truths
[✅] Calibrated - Uncertainty properly expressed
[⚠️] Transparent - Limitations disclosed
[✅] Forthright - Relevant info proactively shared
[✅] Non-deceptive - No false impressions created
[✅] Non-manipulative - No psychological exploitation
[✅] Autonomy-preserving - Supports rational agency

Concerns:
⚠️ Transparent: Missing disclosure of data retention policy

Recommendations:
1. Add data retention disclosure to privacy section
```

### Summary Format
```
Transparency Check: ✅ PASS (6/7 properties met)
⚠️ 1 concern: Transparency - missing limitation disclosure
```

### Detailed Format
Full analysis of each property with evidence, examples, and specific recommendations.

## Honesty Properties

### 1. Truthful
Only sincerely asserts things believed to be true.

**Check for:**
- Factual accuracy of claims
- No known falsehoods
- Honest representations
- Verified information sources

**Red flags:**
- Unverified claims stated as fact
- Known errors not corrected
- Misleading statistics

### 2. Calibrated
Expresses appropriate uncertainty based on evidence and reasoning.

**Check for:**
- Proper use of hedging language
- Confidence aligned with evidence
- Acknowledgment of limitations
- Clear distinction between certain and uncertain

**Red flags:**
- Overconfident claims
- False precision
- Missing uncertainty indicators
- Treating speculation as fact

### 3. Transparent
Doesn't pursue hidden agendas or lie about reasoning.

**Check for:**
- Clear explanation of reasoning
- Disclosed motivations
- Visible decision criteria
- Open about constraints

**Red flags:**
- Hidden objectives
- Unexplained recommendations
- Undisclosed conflicts of interest
- Secret data collection

### 4. Forthright
Proactively shares relevant information.

**Check for:**
- Important context provided
- Relevant caveats included
- Material information disclosed
- User-relevant details shared

**Red flags:**
- Buried important information
- Missing material disclosures
- Relevant warnings omitted
- Key context hidden

### 5. Non-deceptive
Doesn't create false impressions through any means.

**Check for:**
- Accurate overall impressions
- No misleading framing
- Honest presentation
- Clear communication

**Red flags:**
- True but misleading statements
- Cherry-picked evidence
- Misleading visualizations
- Deceptive formatting

### 6. Non-manipulative
Relies only on legitimate epistemic actions.

**Check for:**
- Evidence-based persuasion
- Rational arguments
- Respectful communication
- Fair presentation of options

**Red flags:**
- Emotional exploitation
- Fear-based messaging
- Guilt manipulation
- Social pressure tactics

### 7. Autonomy-preserving
Protects the epistemic autonomy and rational agency of users.

**Check for:**
- Balanced information
- User empowerment
- Independent decision support
- Respect for user judgment

**Red flags:**
- One-sided presentation
- Dependency creation
- Decision pressure
- Thinking substitution

## Target-Specific Checks

### Response Check
- Accuracy of claims
- Appropriate uncertainty
- Complete information
- Balanced perspective

### Documentation Check
- Accurate descriptions
- Honest limitations
- Clear caveats
- Complete information

### Code Check
- Honest comments
- Accurate error messages
- Transparent logging
- Non-deceptive UX

### UI Check
- Honest affordances
- Clear consent flows
- Non-manipulative patterns
- Accurate feedback

## Examples

### Check Current Response
```
/transparency-check
```

### Check Documentation
```
/transparency-check README.md --target-type documentation
```

### Check Code Honesty
```
/transparency-check src/auth.ts --target-type code
```

### Check Specific Properties
```
/transparency-check --properties non-deceptive,non-manipulative
```

### Detailed Analysis
```
/transparency-check "marketing copy" --output detailed
```

### UI Pattern Check
```
/transparency-check "checkout flow" --target-type ui
```

## Severity Levels

| Level | Icon | Meaning |
|-------|------|---------|
| Pass | ✅ | Property fully satisfied |
| Advisory | 💡 | Could be improved |
| Concern | ⚠️ | Property partially violated |
| Violation | ❌ | Property clearly violated |

## Common Violations

### In Documentation
- Overstated capabilities
- Hidden limitations
- Misleading comparisons
- Buried important information

### In Code
- Deceptive error messages
- Hidden tracking
- Misleading variable names
- Undocumented side effects

### In UI
- Dark patterns
- Manipulative copy
- Confusing consent flows
- Hidden costs/terms

## Integration

### Worktask Integration
- **P Stage**: Check requirements for honesty
- **D Stage**: Review implementation transparency
- **W Stage**: Verify documentation honesty
- **Q Stage**: Include transparency in QA

### Agent Coordination
- Uses `ethics-reviewer` for complex cases
- Integrates with technical-writer for documentation
- Coordinates with designer for UI checks

