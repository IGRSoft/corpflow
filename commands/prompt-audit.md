---
name: prompt-audit
description: Comprehensive audit of agents, commands, and prompts for quality, consistency, and best practices
argument-hint: '[--scope agents|commands|all]'
allowed-tools: Read, Glob, Grep
model: sonnet
---

# Prompt Audit Command

Comprehensive audit of agents, commands, and prompts for quality, consistency, and best practices. Identifies issues and generates improvement recommendations.

## Usage

```
/prompt-audit
/prompt-audit --agents
/prompt-audit --commands
/prompt-audit --report
```

## Options

- `--agents` - Audit agents only
- `--commands` - Audit commands only
- `--report` - Generate detailed audit report file
- `--fix` - Auto-fix minor issues (formatting, links)
- `--severity <level>` - Minimum severity: info, warning, error

## Examples

```
/prompt-audit
/prompt-audit --agents --report
/prompt-audit --commands --fix
/prompt-audit --severity warning
```

## Output Format

```markdown
# Prompt Ecosystem Audit

## Summary

| Category | Total | Pass | Warn | Fail |
|----------|-------|------|------|------|
| Agents | 11 | 8 | 2 | 1 |
| Commands | 36 | 30 | 5 | 1 |
| **Total** | **47** | **38** | **7** | **2** |

**Health Score**: 81/100 (Good)
**Last Audit**: 2024-01-15

## Critical Issues 🔴

### 1. Agent: workflow-engineer
**Issue**: Outdated workflow stage references
**Location**: `agents/workflow-engineer.md:52`
**Details**: References removed stage "R" (Review)
**Fix**: Update to current 9-stage system (PL→AR→TL→DV→DR→QA→DC→FN→ST)

### 2. Command: estimate
**Issue**: Missing required section
**Location**: `commands/estimate.md`
**Details**: No "Output Format" section defined
**Fix**: Add output format specification

## Warnings ⚠️

### 3. Agent: qa-engineer
**Issue**: Suboptimal model selection
**Current**: sonnet
**Recommended**: haiku (procedural task)
**Impact**: ~60% cost reduction possible

### 4. Agent: technical-writer
**Issue**: Capability overlap with docs-architect
**Details**: Both claim "API documentation" capability
**Fix**: Clarify boundaries between agents

### 5. Command: workflow
**Issue**: Inconsistent option format
**Current**: `--platform [iOS|macOS|All]`
**Expected**: `--platform <apple|android|web|all>`
**Fix**: Standardize to ecosystem convention

### 6. Command: test-plan
**Issue**: Insufficient examples
**Current**: 1 example
**Required**: Minimum 3 examples
**Fix**: Add diverse usage examples

### 7. Commands: 5 files
**Issue**: Missing Related section
**Files**: api-docs, arch-decision, business-case, doc-audit, executive-summary
**Fix**: Add Related section with links

## Agent Analysis

| Agent | Model | Clarity | Efficiency | Consistency |
|-------|-------|---------|------------|-------------|
| designer | sonnet | 9/10 | 8/10 | 9/10 |
| developer | opus | 9/10 | 8/10 | 9/10 |
| product-manager | opus | 8/10 | 7/10 | 8/10 |
| project-manager | opus | 8/10 | 7/10 | 8/10 |
| prompt-engineer | opus | 9/10 | 8/10 | 9/10 |
| qa-engineer | sonnet | 8/10 | 7/10 | 9/10 |
| software-architector | opus | 9/10 | 8/10 | 9/10 |
| stakeholder | sonnet | 8/10 | 8/10 | 8/10 |
| team-lead | sonnet | 7/10 | 7/10 | 8/10 |
| technical-writer | haiku | 7/10 | 7/10 | 7/10 |
| workflow-engineer | sonnet | 6/10 | 8/10 | 7/10 |

### Model Distribution
| Model | Count | Percentage |
|-------|-------|------------|
| haiku | 2 | 18% |
| sonnet | 4 | 36% |
| opus | 5 | 45% |

## Command Analysis

| Metric | Commands | Percentage |
|--------|----------|------------|
| Has Usage section | 36/36 | 100% |
| Has Options section | 34/36 | 94% |
| Has Examples (3+) | 28/36 | 78% |
| Has Output Format | 30/36 | 83% |
| Has Related section | 31/36 | 86% |
| Platform param | 18/36 | 50% |

## Consistency Checks

| Check | Status | Issues |
|-------|--------|--------|
| YAML frontmatter | ✅ Pass | 0 |
| Section ordering | ⚠️ Warn | 3 files |
| Option format | ⚠️ Warn | 2 files |
| Platform values | ✅ Pass | 0 |
| Terminology | ⚠️ Warn | 5 inconsistencies |

### Terminology Inconsistencies
| Term A | Term B | Occurrences |
|--------|--------|-------------|
| "test" | "testing" | 12 |
| "check" | "validate" | 8 |
| "PR" | "pull request" | 5 |

## Recommendations

### Priority 1 (Fix Now)
1. Update workflow-engineer stage references
2. Add Output Format to estimate command
3. Standardize platform option format

### Priority 2 (Fix Soon)
1. Clarify qa-engineer/technical-writer boundaries
3. Add examples to test-plan command
4. Add Related sections to 5 commands

### Priority 3 (Consider)
1. Standardize terminology across all files
2. Add example interactions to all agents
3. Create command template for consistency

## Auto-Fixable Issues

With `--fix` flag, these issues can be automatically resolved:

| Issue | Files | Action |
|-------|-------|--------|
| Missing Related section | 5 | Add template section |
| Option format | 2 | Standardize syntax |
| Broken internal links | 3 | Update paths |

## Audit Metadata

| Field | Value |
|-------|-------|
| Audit Date | 2024-01-15 10:30:00 |
| Files Scanned | 47 |
| Rules Applied | 24 |
| Duration | 2.3s |
```

## Audit Rules

### Agent Rules
1. Valid YAML frontmatter (name, description, model)
2. Model appropriate for task complexity
3. Clear purpose statement
4. No capability overlap with other agents
5. Workflow stage integration documented
6. Example interactions provided

### Command Rules
1. Usage section with syntax
2. Options section with types and defaults
3. Minimum 3 diverse examples
4. Output format specification
5. Related section with links
6. Consistent option format

### Consistency Rules
1. Platform values: `<apple|android|web|all>`
2. Option syntax: `--option <value>` or `--flag`
3. Section ordering: Usage → Options → Examples → Output → Integration → Related
4. Terminology standardized

## Integration

This command is used:
- For periodic ecosystem health checks
- Before major releases
- After adding new agents/commands
- During prompt engineering reviews

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [optimize-agent](./optimize-agent.md) - Optimize agents
- [optimize-command](./optimize-command.md) - Optimize commands
- [create-agent](./create-agent.md) - Create new agents
- [create-command](./create-command.md) - Create new commands
- [create-skill](./create-skill.md) - Create new skills
