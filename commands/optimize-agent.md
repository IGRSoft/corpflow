---
name: optimize-agent
description: Analyze and optimize existing agent definitions for clarity, efficiency, and consistency
version: 0.3.0
argument-hint: <agent name or path>
model: opus
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/prompt-engineer.md
  - commands/create-agent.md
  - commands/prompt-audit.md
---

# Optimize Agent Command

Optimize existing agent definitions using prompt-engineering best practices.

## Usage

```
/optimize-agent <agent-file> [--focus <area>] [--dry-run] [--report]
/optimize-agent --all [--focus <area>] [--dry-run] [--report]
```

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--all` | — | Every agent in `agents/` |
| `--focus <area>` | see § Focus Areas | One area only (default: all) |
| `--dry-run` | — | Recommend without editing files |
| `--report` | — | Emit the full optimization report |

## Examples

```
/optimize-agent agents/developer.md
/optimize-agent agents/qa-engineer.md --focus model
/optimize-agent --all --dry-run
/optimize-agent agents/workflow-engineer.md --focus efficiency --report
```

## Output Format

Sections in order below. `--dry-run` omits Changes Applied.

### Report skeleton

~~~markdown
# Agent Optimization Report — <agent>

## Frontmatter Findings
| Field | Observed | Required | Severity | Suggested edit |

## Current State
| Metric | Score | Status |
**Overall Score**: n/10

## Model Analysis
| Current | Recommended | Rationale | Cost delta | Quality impact |

## Findings by Area
## Recommendations
## Changes Applied
| Section | Change | Impact |

## Summary
| Metric | Before | After | Change |
~~~

### Report content rules

- **Current State** metrics, n/10 each: clarity, efficiency, consistency, model fit, tool config. Glyphs `✅ Good` / `⚠️ Improvable` / `🔴 Suboptimal`.
- **Findings by Area**: issue → before/after snippet → one-line rationale. Efficiency findings state tokens before → after (−N%).
- **Recommendations**: `Must Apply` / `Should Apply` / `Consider`; every frontmatter finding is Must Apply.
- **Summary**: Current State metrics plus token count, before vs after.

## Focus Areas

- **clarity**: purpose, capabilities, boundaries, instructions
- **efficiency**: token count, redundancy, instruction density
- **consistency**: format, terminology, structure, conventions
- **tools**: tool access, permissions, integration
- **model**: model selection (haiku/sonnet/opus/fable)
- **frontmatter**: description length, hooks, effort, model, tools least-privilege — see § Frontmatter Audit
- **body**: information hierarchy, completion criteria, negation form, no-op pruning — see § Body doctrine
- **failure-modes**: see § Failure Mode Analysis

## Optimization Criteria

### Clarity

Unambiguous purpose; defined capability boundaries; explicit behavioral expectations; no overlap with another agent's responsibilities.

### Efficiency

Dense actionable instructions; no redundancy; one canonical example per behavior instead of repeated variants.

### Body doctrine

Runs on every agent regardless of `--focus`; findings land in Findings by Area. Normative source:
`agents/prompt-engineer.md § Prompt-body doctrine`; measurement procedure:
`commands/prompt-audit.md § Body Rules`.

| Check | Finding when | Fix line states |
|---|---|---|
| **Disclosure** | An H2 subtree over 200 lines whose body only *some* branches reach | The reference file it belongs behind, and which branch reaches it |
| **Completion criteria** | A criterion fails *clarity* (done indistinguishable from not-done) or *demand* (no artifact named to check it against) | The artifact it is checked against |
| **Negation form** | A `DO NOT` aimed at any `§ Form to failure` row but "knows the rule, skips it under pressure" | The correct form — positive recipe, REQUIRED template slot, or observable-predicate conditional |
| **No-op pruning** | An instruction this agent's own `model:` already obeys by default | Deletion of the whole sentence, never a rewording |

#### Body doctrine — the model-conditioned rows

These three read the agent's own `model:` before they can fire at all.

| Check | Finding when | Fix line states |
|---|---|---|
| **Model-conditioned** | An instruction collides with a documented behaviour of this `model:` — per-alias list in `skills/shared/model-prompting.md` | Deletion, citing the vendor page that canon file names |
| **Scope explicitness** | On a `sonnet` agent, an instruction names one item where the agent's scope covers a set | The scope — `every`, `each`, the named set — never added emphasis |
| **Emphasis inflation** | An emphasised rule with no recorded failure behind it | Downgrade to the plain imperative; the rule itself stays |

#### Body doctrine — three guards

An existing `## Constraints (DO NOT)` block is **reported, never rewritten in place** — recasting
constraint blocks under the negation rule is its own worktask, so the finding is advisory and
`--dry-run` semantics apply to it even without the flag.

A disclosure finding against a section every run executes end to end is a **false positive**: length
is the symptom that makes you look, branching is what decides, and inline is the correct tier for
work every branch reaches.

A model-conditioned finding against a **completion criterion** is a false positive. "Confirm the
manifest exists on disk" names an artifact and is graded under the completion-criteria row; only a
re-read of the agent's own reasoning is a verification instruction in the sense
`model-prompting.md` means. Deleting the artifact gates lowers demand on exactly the axis this
rubric raises.

### Model Selection

Evaluate model fit against the canonical cost tiers and stage→model mapping: `skills/shared/model-selection.md`, `skills/shared/stage-codes.md`.

### Frontmatter Audit

Runs on every agent regardless of `--focus`; findings block on the Must Apply tier. Rubrics: `skills/shared/model-selection.md § Cost Tiers`, `skills/agent-coordination/references/hook-monitoring.md`.

#### Frontmatter audit — identity (P0)

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `name` | Globally unique and **must not contain `:`** — CC rejects the file (`:` is reserved for call-site namespacing, `corpflow:developer`). CC keys agents by this field, so generic stems (`developer`, `qa-engineer`, `incident-responder`) silently overwrite across plugins: cross-check `apple-developer:`, `security-scanning:`, `debugging-toolkit:` stems, prefer `<plugin>-<role>`. | P0 (`:`) / P1 (collision) |
| `description` | ≤250 characters, measured with `awk -F'description: ' '/^description:/{print length($2)}'`; report exact count, suggest a 240-char rewrite for headroom. | P0 |
| `model` | Strict membership: ∈ {`haiku`, `sonnet`, `opus`, `fable`}. Reject `claude-*` ids, version aliases, omission. | P0 |

#### Frontmatter audit — tools & effort (P1)

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `tools` | Least-privilege explicit list, cross-checked against the agent's documented constraints. Flag: bare `Bash` (needs sub-matchers like `Bash(git:*)`); `Bash(*)`/`Read(*)`; `Write`/`Edit` on review-only agents (DR/SR/QA); single-segment `dir/**` (cwd-anchored — any-depth needs `**/dir/**`); `Write(path)`/`NotebookEdit(path)`/`Glob(path)` (startup warning — use `Edit(path)`/`Read(path)`). Scoped wildcards are fine: `WebFetch(domain:*.example.com)`, `Read(secrets-*/config.json)`. | P1 |
| `effort` | Present on every stage agent, matching role tier in the model-selection matrix. `xhigh` requires `model: opus` or `model: fable` — Sonnet silently downgrades (`skills/cost-optimization/SKILL.md § Per-Effort Thinking-Budget Ceilings`). | P1 |

#### Frontmatter audit — hooks (P1)

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `hooks:` | Required on PL/FN/ST (gate notifications); recommended on DV/DR/QA/SR/RE but flag PL/FN/ST omissions only. **Trust precondition**: hooks run only when the agent file's own folder has accepted workspace trust — otherwise silently skipped, so a missing hook artifact never proves the hook passed. | P1 (PL/FN/ST) / P2 (others) |

#### Frontmatter audit — execution scope (P2)

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `maxTurns` | Proportional to role: coordinators (DV, AR) ≥60; reviewers (DR, QA, SR) 30–60; one-shot haiku-tier ≤30. | P2 |
| `disallowedTools` | Suggest (never block) on review-only agents, e.g. DR with `Write, Edit, mcp__XcodeBuildMCP__test_*`. | P2 |
| `isolation: worktree` | Required on agents that mutate the working tree across split runs (DV, code-fixer). Flag if the agent has both `Edit` and git-mutating Bash matchers. | P2 |

#### Frontmatter audit — optional fields

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `mcpServers` | Optional; if absent, MCP scope comes from inline `mcp__<server>__*` entries in `tools`. Flag only when no `mcp__*` tools AND `Skill(*)` wildcards — that pair silently broadens scope. | P2 |
| `context: fork` | A forked skill runs **in the background by default**; `background: false` opts out. Flag when the caller needs its result inline rather than a completion notification. | P2 |
| booleans | Frontmatter booleans accept `yes`/`no`/`on`/`off`/`1`/`0` (case-insensitive) alongside `true`/`false`. Flag only inconsistent spellings within one file. | P3 |
| `color` | Cosmetic; no enforcement. | — |

### Failure Mode Analysis

With `--focus failure-modes`, classify observed failures: instruction misunderstanding (role/task confusion), output format errors, context loss (long-conversation drift), tool misuse, constraint violations, edge-case handling.

Where a class recurs, fix it in the form that class takes — `agents/prompt-engineer.md
§ Form to failure`. A wrong output shape takes a positive recipe; a missing element takes a
REQUIRED slot in the template being filled in.

Do **not** answer a recurring class with a generic self-check block ("Before responding, verify:
output matches format, constraints satisfied, no conflicting information"). It reads as diligence
and is the instruction `skills/shared/model-prompting.md § opus` names as compounding into
over-verification, and 8 of this plugin's 16 agents are `model: opus`. A criterion that names an
artifact is a different thing and stays — that is the completion-criteria row, not this one.

## Integration

Used by `prompt-engineer` for agent-ecosystem maintenance and post-worktask agent updates.
