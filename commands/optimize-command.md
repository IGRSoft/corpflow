---
name: optimize-command
description: Analyze and optimize existing command definitions for usability, consistency, and completeness
argument-hint: <command name or path>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

# Optimize Command

Analyze and optimize existing command definitions for usability, consistency, and completeness. Improves command quality using prompt engineering best practices.

## Usage

```
/optimize-command <command-file>
/optimize-command --all
/optimize-command commands/estimate.md --focus examples
```

## Options

- `--all` - Optimize all commands in the commands directory
- `--focus <area>` - Focus area: usage, options, examples, output, integration
- `--dry-run` - Show recommendations without making changes
- `--report` - Generate detailed optimization report

## Examples

```
/optimize-command commands/workflow.md
/optimize-command commands/estimate.md --focus options
/optimize-command --all --dry-run
/optimize-command commands/test-plan.md --focus examples --report
```

## Output Format

```markdown
# Command Optimization Report

## Command: /estimate

### Current State

| Metric | Score | Status |
|--------|-------|--------|
| Usage Clarity | 7/10 | ⚠️ Improvable |
| Options | 8/10 | ✅ Good |
| Examples | 5/10 | 🔴 Insufficient |
| Output Format | 9/10 | ✅ Excellent |
| Integration | 6/10 | ⚠️ Improvable |

**Overall Score**: 7.0/10

### Usage Improvements

#### Current
```
/estimate
/estimate --scope full
```

#### Recommended
```
/estimate [feature-description]
/estimate --scope <quick|full|detailed> [feature-description]
/estimate --format <table|json|markdown>
```

**Changes**:
- Added positional argument for feature description
- Clarified scope options with valid values
- Added format option for flexibility

### Options Analysis

| Option | Status | Issue | Recommendation |
|--------|--------|-------|----------------|
| --scope | ⚠️ | Missing valid values | Add `<quick\|full\|detailed>` |
| --platform | ✅ | Well documented | None |
| --format | ❌ | Missing | Add output format option |
| --output | ❌ | Missing | Add file output option |

### Examples Improvements

**Before**: 2 examples (insufficient coverage)
**After**: 5 examples (good coverage)

#### Added Examples
```
# Quick estimate for small feature
/estimate --scope quick "add logout button"

# Detailed estimate with platform context
/estimate --scope detailed --platform apple "implement push notifications"

# Export estimate to file
/estimate --format markdown --output estimates/feature-x.md "user authentication"
```

### Output Format Review

| Element | Status |
|---------|--------|
| Summary table | ✅ Present |
| Time breakdown | ✅ Present |
| Risk factors | ✅ Present |
| Assumptions | ⚠️ Could be more prominent |
| Confidence level | ❌ Missing |

**Recommendation**: Add confidence level indicator (Low/Medium/High)

### Integration Improvements

#### Missing Links
- Related command: `/export-estimate`
- Related agent: `project-manager`

#### Workflow Integration
**Current**: Not documented
**Recommended**: Add PL stage usage note

### Recommendations

#### Must Apply
1. Add missing option values to documentation
2. Add 3 more diverse examples
3. Link to related commands

#### Should Apply
1. Add format and output options
2. Include confidence level in output
3. Document workflow integration

#### Consider
1. Add JSON schema for output
2. Add validation for scope values

### Changes Applied

| Section | Change | Impact |
|---------|--------|--------|
| Usage | Added positional arg | Clearer interface |
| Options | Added format, output | More flexibility |
| Examples | Added 3 examples | Better coverage |
| Related | Added links | Discoverability |

## Summary

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Usage Clarity | 7/10 | 9/10 | +2 |
| Examples | 5/10 | 8/10 | +3 |
| Integration | 6/10 | 8/10 | +2 |
| Overall | 7.0/10 | 8.4/10 | +1.4 |
```

## Focus Areas

- **usage**: Command syntax, positional arguments, clarity
- **options**: Option completeness, types, defaults, documentation
- **examples**: Coverage, diversity, practical scenarios
- **output**: Format specification, clarity, completeness
- **integration**: Related commands, agents, workflow stages

## Optimization Criteria

### Usage
- Clear syntax with all arguments shown
- Optional vs required clearly indicated
- Sensible defaults documented

### Options
- All options documented with types
- Valid values specified for enums
- Defaults stated explicitly
- Purpose clear from description

### Examples
- Minimum 3 diverse examples
- Cover common use cases
- Show option combinations
- Include realistic values

### Output Format
- Structured, parseable format
- All fields documented
- Status indicators consistent
- Actionable information

### Integration
- Related commands linked
- Agent relationships documented
- Workflow stage usage noted

## Integration

This command is used by:
- prompt-engineer agent for command optimization
- During command ecosystem maintenance
- After workflow changes require command updates

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [create-agent](./create-agent.md) - Create new agents
- [create-command](./create-command.md) - Create new commands
- [create-skill](./create-skill.md) - Create new skills
- [optimize-agent](./optimize-agent.md) - Optimize agents
- [prompt-audit](./prompt-audit.md) - Audit all prompts
