---
name: optimize-agent
description: Analyze and optimize existing agent definitions for clarity, efficiency, and consistency
argument-hint: <agent name or path>
model: opus
allowed-tools: Read, Glob, Grep, Write
---

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
| Worktask integration | ✅ Proper Q stage references |

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
- **frontmatter**: CC 2.1.86–2.1.142 frontmatter audit (description length, hooks, effort, model, tools least-privilege) — see § Frontmatter Audit (CC 2.1.86+)
- **failure-modes**: Classify common failures (instruction misunderstanding, output format, context loss, tool misuse, constraint violations)

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

### Frontmatter Audit (CC 2.1.86+)

Run on every agent regardless of focus area; treat findings here as blocking on the "Must Apply" tier. Reference rubric: `skills/shared/model-selection.md § Cost Tiers` for model/effort matrix; `skills/agent-coordination/references/hook-monitoring.md` for hook events.

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `description` | ≤250 characters total (CC 2.1.86 cap). Measure with `awk -F'description: ' '/^description:/{print length($2)}'`. Flag with exact char count if over. | P0 |
| `model` | Strict membership: ∈ {`haiku`, `sonnet`, `opus`, `fable`}. Reject `claude-*`, `claude-sonnet-4-6`, version aliases, or omission. | P0 |
| `effort` | Present on every stage agent. Validate against model: `xhigh` requires `model: opus` or `model: fable` (Opus 4.8 / Fable 5 honor xhigh; Sonnet silently downgrades — see `skills/shared/model-selection.md § Per-Effort Thinking-Budget Ceilings`). Effort matches role tier per the model-selection matrix. | P1 |
| `tools` | Least-privilege: explicit list, no bare wildcards. Flag bare `Bash` without scoped sub-matchers (`Bash(git:*)`, `Bash(swift test:*)`). Scoped pattern wildcards are fine — `WebFetch(domain:*.example.com)` subdomain rules and mid-pattern file rules (`Read(secrets-*/config.json)`) match correctly since CC 2.1.172; still flag unscoped `Bash(*)`/`Read(*)`. Flag `Write`/`Edit` on review-only agents (DR/SR/QA). Cross-check against the agent's documented constraints. | P1 |
| `hooks:` (v2.1.116+) | Required on PL/FN/ST agents (gate notifications). Optional but recommended on stage agents that emit terminal artifacts (DV, DR, QA, SR, RE) once v3.11.0 ships the rollout. Until then, flag PL/FN/ST omissions only. | P1 (PL/FN/ST) / P2 (others) |
| `maxTurns` | Present and proportional to role: coordinators (DV, AR) ≥60; reviewers (DR, QA, SR) 30–60; one-shot (haiku-tier) ≤30. | P2 |
| `disallowedTools` (v2.1.78) | Consider for review-only agents to harden the constraint contract (e.g., DR with `disallowedTools: Write, Edit, mcp__XcodeBuildMCP__test_*`). Suggest, do not block. | P2 |
| `isolation: worktree` (v2.1.98+) | Present on agents that mutate the working tree across split runs (DV, code-fixer). Flag missing on agents with both `Edit` and `git`-mutating Bash matchers. | P2 |
| `color` | Cosmetic; no enforcement. |
| `mcpServers` (v2.1.142) | Optional. If absent, MCP scope must be enforced via inline `mcp__<server>__*` entries in `tools`. Do not flag unless the agent both lists no `mcp__*` tools AND uses `Skill(*)` wildcards — that combination silently broadens scope. | P2 |
| `name` | Globally unique. Collision risk when generic (`developer`, `qa-engineer`, `incident-responder`, etc.) — CC keys installed agents by frontmatter `name`, so two plugins shipping the same name silently overwrite each other. Flag HIGH if igrsoft agent shares name with a known marketplace plugin (cross-check `apple-developer:`, `security-scanning:`, `debugging-toolkit:` agent stems). For new agents, prefer `<plugin>-<role>` form. Source: ai-research PR #554. | P1 |

Failures here are reported as a `## Frontmatter Findings` table before the existing scoring tables in § Output Format. Each row: `| Field | Observed | Required | Severity | Suggested edit |`. Append a one-line fix for `description` over-limit (with the truncated suggestion at 240 chars to leave headroom).

### Failure Mode Analysis
When `--focus failure-modes` is specified, classify observed failures:
- **Instruction misunderstanding**: Role or task confusion
- **Output format errors**: Structure or formatting issues
- **Context loss**: Long conversation degradation
- **Tool misuse**: Incorrect or inefficient tool selection
- **Constraint violations**: Safety or business rule breaches
- **Edge case handling**: Unusual input scenarios

Add constitutional self-check mechanisms where failures are common:
```markdown
Before responding, verify:
1. Output matches required format
2. All constraints satisfied
3. No conflicting information
```

## Integration

This command is used by:
- prompt-engineer agent for optimization tasks
- During agent ecosystem maintenance
- After worktask changes require agent updates

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [create-agent](./create-agent.md) - Create new agents
- [create-command](./create-command.md) - Create new commands
- [create-skill](./create-skill.md) - Create new skills
- [prompt-audit](./prompt-audit.md) - Audit all prompts
