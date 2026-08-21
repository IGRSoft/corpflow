---
name: create-agent
description: Create new agent definitions with proper structure, model selection, and best practices
argument-hint: <agent name and purpose>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/prompt-engineer.md
  - commands/optimize-agent.md
  - commands/prompt-audit.md
---

# Create Agent Command

Create new agent definitions with proper structure, model selection, and best practices. Generates production-ready agent files.

## Usage

```
/create-agent <name> --purpose <description>
/create-agent "database-admin" --purpose "Database administration and optimization"
/create-agent "api-designer" --model haiku --template minimal
```

## Options

- `--purpose <description>` - Agent purpose (required)
- `--model <haiku|sonnet|opus>` - Model selection (default: auto-select)
- `--template <minimal|standard|comprehensive>` - Template style (default: standard)
- `--tools <preset|list>` - Tool access preset or comma-separated list (see § Tool Presets)
- `--stage <code>` - Worktask stage integration: PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR
- `--output <path>` - Output path (default: agents/<name>.md)

## Examples

```
/create-agent "database-admin" --purpose "Database schema design, query optimization, and migration management"
/create-agent "api-designer" --purpose "REST/GraphQL API design" --model haiku --template minimal
/create-agent "security-reviewer" --purpose "Security code review and vulnerability assessment" --model opus --tools read
/create-agent "test-automator" --purpose "Automated test generation" --stage QA --template comprehensive
```

## Templates

| Section | minimal | standard (default) | comprehensive |
|---|---|---|---|
| Frontmatter | name, description, model | + tools | + tools |
| Constraints (DO NOT) | 3 items | 3-5 items | 5-7 items |
| Purpose | basic | basic | expert purpose |
| Capabilities | 3-5 items | by category | detailed subsections |
| Behavioral traits, knowledge base | — | — | ✅ |
| Worktask + state-ledger integration | — | ✅ | ✅ |
| Response approach | basic | ✅ | numbered steps |
| Related agents/commands | — | ✅ | ✅ + integration points |
| Example interactions, anti-patterns | — | — | ✅ |
| Completion Verification | — | — | optional (see § Completion Verification) |
| Handoff Protocol + State Patch | — | stage owners only | stage owners only |

## Output Format

~~~markdown
# Agent Created: <name>

## Generated File — `agents/<name>.md`
## Configuration — | Setting | Value | (Name, Model, Template, Tools, Stage)
## Preview — generated frontmatter block + first 500 characters of the body
## Model Selection Rationale — **Selected** + one-line reason; **Alternatives Considered**, one line per rejected tier
## Next Steps — review the file, customize capabilities for the stack, add domain examples, then `/optimize-agent agents/<name>.md --dry-run`
~~~

## Model Auto-Selection

When `--model` is not specified, selection is based on purpose analysis: procedural keywords (format, convert, validate) map to the lowest tier, balanced keywords (implement, review, design) to the mid tier, and complex-reasoning keywords (architect, optimize, research) to the top tier.

Model tiers and stage→model mapping: see `skills/shared/model-selection.md` and `skills/shared/stage-codes.md` (canonical).

## Tool Presets

When using `--tools`, specify a preset name or a comma-separated tool list:

| Preset | Expands To |
|--------|-----------|
| read-only | Read, Glob, Grep |
| standard | Read, Glob, Grep, Write, Edit, Bash |
| full | Read, Glob, Grep, Write, Edit, Bash |
| orchestrator | Read, Glob, Grep, Write, Edit, Bash, Bash(bash skills/worktask/scripts/state-patch.sh:*) |
| design | Read, Glob, Grep, Write, ToolSearch |

### Cross-Plugin Delegation

Add Task delegation syntax to any preset: `--tools full,Task(apple-developer:ios-developer)`

## Agent Structure Guidelines

### Frontmatter (Required)

Canonical field order — every agent in `agents/` follows it, and a new agent that deviates is drift, not style:

```yaml
---
name: agent-name
description: Brief description for routing (1-2 sentences). Use PROACTIVELY for...
model: haiku|sonnet|opus
color: blue
effort: medium
version: 0.1.0
maxTurns: 40
tools: Read, Glob, Grep, Write, Edit
---
```

Optional fields keep fixed slots: `isolation:` between `maxTurns:` and `tools:`; `hooks:` last, after `tools:`. An explanatory comment for a narrowly-scoped grant (`# tools: Bash(curl:*) is scoped to curl because …`) sits immediately above the `tools:` line it explains and moves with it.

### Body sections

| Section | Rule |
|---|---|
| `description` | Include "Use PROACTIVELY for..." to improve routing — e.g. "Database specialist for schema design. Use PROACTIVELY for query optimization or migration planning." |
| Constraints (DO NOT) | First section after the frontmatter identity sentence. 3-7 specific prohibitions defining boundaries ("DO NOT modify production code directly" for QA agents). |
| Purpose | Role, domain and boundaries, integration context. |
| Capabilities | By category; actionable and specific; no overlap with other agents. |
| Worktask Integration | Stage code, state ledger integration, handoff protocols. |

### Completion Verification (optional)

A **supplement** to `skills/shared/stage-contracts.md § Completion Verification`, never a restatement of it. Include it only when the stage adds checks the shared contract does not cover; omit it entirely otherwise. Sits immediately before § Handoff Protocol.

### Handoff Protocol (stage owners only)

- Last section of the file, followed only by its `### State Patch — REQUIRED before return` subsection
- Names the `stage-contracts.md#tpl-<code>` frontmatter template and the `Prev→this` edge label; does not restate the shared contract
- State Patch subsection gives the exact `state-patch.sh --stage <CODE> --prev <PREV>` call plus a `--facts` example

#### Handoff Protocol exemptions

**Do not add this section to a support agent.** It asserts a ledger-write responsibility, so an agent that owns no stage artifact must not carry it. Current exemptions, verified against `skills/shared/stage-codes.md`:

| Agent | Why exempt |
|---|---|
| `designer` | Support agent (DS). Invoked by PL/AR/DV/QA, writes no `.context/` stage artifact. |
| `prompt-engineer` | Support agent (PE). Agent-optimization work, outside the worktask ledger. |
| `product-manager` | Owns PL, but its handoff and completion checklist are canonical in `skills/worktask/references/pl0-procedure.md`. Duplicating them here would create a second source of truth. |

`workflow-engineer` is **not** exempt: it is a support agent by default, but PL0 routes DV0 to it for worktask-infrastructure changes, so it carries a DV-scoped Handoff Protocol gated on that mode.

## Integration

Used by the `prompt-engineer` agent to create new agents, when expanding the agent ecosystem, and for specialized domain agents.
