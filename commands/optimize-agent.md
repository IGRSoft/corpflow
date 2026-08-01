---
name: optimize-agent
description: Analyze and optimize existing agent definitions for clarity, efficiency, and consistency
version: 0.1.0
argument-hint: <agent name or path>
model: opus
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/prompt-engineer.md
  - commands/create-agent.md
  - commands/prompt-audit.md
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

~~~markdown
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
~~~

### Report template — clarity improvements

~~~markdown
<!-- …continued: clarity improvements -->
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
~~~

### Report template — efficiency & consistency

~~~markdown
<!-- …continued: efficiency & consistency -->
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
| Worktask integration | ✅ Proper QA stage references |
~~~

### Report template — recommendations & changes applied

~~~markdown
<!-- …continued: recommendations -->
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
~~~

### Report template — summary

~~~markdown
<!-- …continued: summary -->
## Summary

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Clarity | 7/10 | 9/10 | +2 |
| Efficiency | 6/10 | 8/10 | +2 |
| Model Fit | 5/10 | 9/10 | +4 |
| Token Count | 2,400 | 1,800 | -25% |
~~~

## Focus Areas

- **clarity**: Purpose, capabilities, boundaries, instructions
- **efficiency**: Token count, redundancy, instruction density
- **consistency**: Format, terminology, structure, conventions
- **tools**: Tool access, permissions, integration
- **model**: Model selection optimization (haiku/sonnet/opus)
- **frontmatter**: frontmatter audit (description length, hooks, effort, model, tools least-privilege) — see § Frontmatter Audit
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
Evaluate model fit against the canonical cost tiers and stage→model mapping: see `skills/shared/model-selection.md` and `skills/shared/stage-codes.md` (canonical).

### Frontmatter Audit

Run on every agent regardless of focus area; treat findings here as blocking on the "Must Apply" tier. Reference rubric: `skills/shared/model-selection.md § Cost Tiers` for model/effort matrix; `skills/agent-coordination/references/hook-monitoring.md` for hook events.

#### Frontmatter audit — description & model

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `description` | ≤250 characters total. Measure with `awk -F'description: ' '/^description:/{print length($2)}'`. Flag with exact char count if over. | P0 |
| `model` | Strict membership: ∈ {`haiku`, `sonnet`, `opus`, `fable`}. Reject `claude-*`, `claude-sonnet-5`, version aliases, or omission. | P0 |

#### Frontmatter audit — effort

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `effort` | Present on every stage agent. Validate against model: `xhigh` requires `model: opus` or `model: fable` (Opus 5 and Fable 5 honor xhigh; Sonnet silently downgrades — see `skills/cost-optimization/SKILL.md § Per-Effort Thinking-Budget Ceilings`). Effort matches role tier per the model-selection matrix. | P1 |

#### Frontmatter audit — tools

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `tools` | Least-privilege: explicit list, no bare wildcards. Flag bare `Bash` without scoped sub-matchers (`Bash(git:*)`, `Bash(swift test:*)`). Scoped pattern wildcards are fine — `WebFetch(domain:*.example.com)` subdomain rules and mid-pattern file rules (`Read(secrets-*/config.json)`) match correctly; still flag unscoped `Bash(*)`/`Read(*)`. Flag `Write`/`Edit` on review-only agents (DR/SR/QA). Cross-check against the agent's documented constraints. Also flag any single-segment `dir/**` allow-rule (cwd-anchored — require `**/dir/**` for any-depth) and any `Write(path)`/`NotebookEdit(path)`/`Glob(path)` rule (startup warning — use `Edit(path)`/`Read(path)`). | P1 |

#### Frontmatter audit — hooks, maxTurns, disallowedTools

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `hooks:` | Required on PL/FN/ST agents (gate notifications). Optional but recommended on stage agents that emit terminal artifacts (DV, DR, QA, SR, RE) once v3.11.0 ships the rollout. Until then, flag PL/FN/ST omissions only. **Trust precondition**: frontmatter hooks run only when the agent file's own folder has accepted workspace trust — otherwise they are silently skipped, so never treat a missing hook artifact as proof the hook passed (`skills/agent-coordination/references/hook-monitoring.md`). | P1 (PL/FN/ST) / P2 (others) |
| `maxTurns` | Present and proportional to role: coordinators (DV, AR) ≥60; reviewers (DR, QA, SR) 30–60; one-shot (haiku-tier) ≤30. | P2 |
| `disallowedTools` | Consider for review-only agents to harden the constraint contract (e.g., DR with `disallowedTools: Write, Edit, mcp__XcodeBuildMCP__test_*`). Suggest, do not block. | P2 |

#### Frontmatter audit — isolation, color, mcpServers

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `isolation: worktree` | Present on agents that mutate the working tree across split runs (DV, code-fixer). Flag missing on agents with both `Edit` and `git`-mutating Bash matchers. | P2 |
| `color` | Cosmetic; no enforcement. |
| `mcpServers` | Optional. If absent, MCP scope must be enforced via inline `mcp__<server>__*` entries in `tools`. Do not flag unless the agent both lists no `mcp__*` tools AND uses `Skill(*)` wildcards — that combination silently broadens scope. | P2 |

#### Frontmatter audit — name uniqueness

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `name` | Globally unique, and **must not contain `:`** — CC rejects the agent file outright, since `:` is reserved for plugin namespacing and only ever appears at the call site (`company-workflow:developer`), never in the file. Collision risk when generic (`developer`, `qa-engineer`, `incident-responder`, etc.) — CC keys installed agents by frontmatter `name`, so two plugins shipping the same name silently overwrite each other. Flag HIGH if company-workflow agent shares name with a known marketplace plugin (cross-check `apple-developer:`, `security-scanning:`, `debugging-toolkit:` agent stems). For new agents, prefer the hyphenated `<plugin>-<role>` form. Source: ai-research PR #554. | P0 (`:` present) / P1 (collision) |

#### Frontmatter audit — boolean & skill-execution forms

| Field | Audit Rule | Severity |
|-------|------------|----------|
| boolean fields | Skill and plugin frontmatter booleans accept `yes`/`no`/`on`/`off`/`1`/`0` (case-insensitive) alongside `true`/`false`. Do not flag a non-`true`/`false` spelling as invalid; do flag inconsistent spellings within one file. | P3 |
| `context: fork` | A skill declaring `context: fork` runs **in the background by default**; add `background: false` to opt out. Flag when a forked skill's caller depends on its result inline — the caller must handle a completion notification instead of a return value. | P2 |

#### Frontmatter findings report

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

