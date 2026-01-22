# Optimize Agent Command

Analyze and optimize existing agent definitions for clarity, efficiency, and consistency. Uses prompt engineering best practices.

## Usage

```
/optimize-agent <agent-file>
/optimize-agent --all
/optimize-agent agents/qa-engineer.md --focus clarity
```

## Options

- `--all` - Optimize all agents in the agents directory
- `--focus <area>` - Focus area: clarity, efficiency, consistency, tools, model
- `--dry-run` - Show recommendations without making changes
- `--report` - Generate detailed optimization report

## Examples

```
/optimize-agent agents/developer.md
/optimize-agent agents/qa-engineer.md --focus model
/optimize-agent --all --dry-run
/optimize-agent agents/workflow-engineer.md --focus efficiency --report
```

## Output Format

```markdown
# Agent Optimization Report

## Agent: qa-engineer

### Current State

| Metric | Score | Status |
|--------|-------|--------|
| Clarity | 7/10 | ⚠️ Improvable |
| Efficiency | 6/10 | ⚠️ Improvable |
| Consistency | 8/10 | ✅ Good |
| Model Fit | 5/10 | 🔴 Suboptimal |
| Tool Config | 9/10 | ✅ Excellent |

**Overall Score**: 7.0/10

### Model Analysis

| Current | Recommended | Rationale |
|---------|-------------|-----------|
| sonnet | haiku | Task is procedural with clear checklists |

**Cost Savings**: ~60% per invocation
**Quality Impact**: Minimal - task doesn't require complex reasoning

### Clarity Improvements

#### 1. Purpose Statement
**Before**:
```markdown
You are a QA engineer who tests things and finds bugs.
```

**After**:
```markdown
You are a QA engineer specializing in test strategy, test case design, and quality validation. You ensure code meets acceptance criteria through systematic testing approaches.
```

**Rationale**: More specific scope and clearer responsibilities

#### 2. Capability Boundaries
**Issue**: Overlapping responsibilities with developer agent
**Recommendation**: Add explicit boundary statement

```markdown
## Boundaries
- Focus on test design and validation, not implementation fixes
- Escalate implementation issues to developer agent
- Do not modify production code directly
```

### Efficiency Improvements

#### Token Reduction
**Current**: ~2,400 tokens
**Optimized**: ~1,800 tokens (-25%)

**Changes**:
- Removed redundant capability descriptions
- Consolidated similar sections
- Simplified examples

#### Instruction Density
**Before**: Verbose explanations with examples for obvious points
**After**: Concise instructions with examples only for complex behaviors

### Consistency Checks

| Check | Status |
|-------|--------|
| YAML frontmatter format | ✅ Valid |
| Section structure | ✅ Standard |
| Terminology | ⚠️ Inconsistent ("test" vs "testing") |
| Workflow integration | ✅ Proper Q stage references |

### Recommendations

#### Must Apply
1. Update model from sonnet to haiku
2. Clarify purpose statement
3. Add capability boundaries

#### Should Apply
1. Reduce token count by 25%
2. Standardize terminology
3. Add anti-patterns section

#### Consider
1. Add example interactions
2. Link to related commands

### Changes Applied

| Section | Change | Impact |
|---------|--------|--------|
| Frontmatter | model: sonnet → haiku | Cost reduction |
| Purpose | Expanded and clarified | Better routing |
| Capabilities | Consolidated redundant items | Token efficiency |
| Boundaries | Added new section | Clearer scope |

## Summary

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Clarity | 7/10 | 9/10 | +2 |
| Efficiency | 6/10 | 8/10 | +2 |
| Model Fit | 5/10 | 9/10 | +4 |
| Token Count | 2,400 | 1,800 | -25% |
```

## Focus Areas

- **clarity**: Purpose, capabilities, boundaries, instructions
- **efficiency**: Token count, redundancy, instruction density
- **consistency**: Format, terminology, structure, conventions
- **tools**: Tool access, permissions, integration
- **model**: Model selection optimization (haiku/sonnet/opus)

## Optimization Criteria

### Clarity
- Specific, unambiguous purpose statement
- Well-defined capability boundaries
- Clear behavioral expectations
- No overlapping responsibilities

### Efficiency
- Minimal token usage
- No redundant information
- Dense, actionable instructions
- Efficient examples

### Model Selection
- haiku: Procedural, checklist-based, formatting tasks
- sonnet: Analysis, implementation, coordination tasks
- opus: Architecture, strategy, complex reasoning tasks

## Integration

This command is used by:
- prompt-engineer agent for optimization tasks
- During agent ecosystem maintenance
- After workflow changes require agent updates

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [create-agent](./create-agent.md) - Create new agents
- [prompt-audit](./prompt-audit.md) - Audit all prompts
