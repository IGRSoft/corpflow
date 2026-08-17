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
- `--tools <preset|list>` - Tool access preset or comma-separated list (see Tool Presets)
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

### Minimal
Basic structure for simple, focused agents:
- Frontmatter (name, description, model)
- Constraints (DO NOT) section (3 items)
- Purpose section
- Core capabilities (3-5 items)
- Basic response approach

### Standard (Default)
Balanced structure for most agents:
- Frontmatter (name, description, model, tools)
- Constraints (DO NOT) section (3-5 items)
- Purpose section
- Capabilities (organized by category)
- Worktask integration
- State ledger integration
- Response approach
- Related agents/commands
- Handoff Protocol + State Patch (stage owners only — see § Handoff Protocol)

### Comprehensive
Full structure for complex agents:
- Frontmatter (name, description, model, tools)
- Constraints (DO NOT) section (5-7 items)
- Expert purpose
- Detailed capabilities (multiple subsections)
- Behavioral traits
- Knowledge base
- Worktask integration with state-ledger format
- Response approach (numbered steps)
- Example interactions
- Anti-patterns
- Integration points
- Completion Verification (only when the stage adds checks beyond `stage-contracts.md`)
- Handoff Protocol + State Patch (stage owners only — see § Handoff Protocol)

## Output Format

```markdown
# Agent Created: database-admin

## Generated File
`agents/database-admin.md`

## Configuration

| Setting | Value |
|---------|-------|
| Name | database-admin |
| Model | sonnet |
| Template | standard |
| Tools | read, bash |
| Stage | DV |

## Preview

---
name: database-admin
description: Database specialist for schema design, query optimization, and migration management. Handles PostgreSQL, MySQL, and SQLite with focus on performance and data integrity.
model: sonnet
---

You are a database administration specialist focused on schema design, query optimization, and migration management...

[Preview of first 500 characters]
```

### Output template — model rationale & next steps

```markdown
<!-- …continued: model rationale -->
## Model Selection Rationale

**Selected**: sonnet
**Reason**: Task involves moderate analysis (query optimization) and implementation (schema design) requiring balanced reasoning capabilities.

**Alternatives Considered**:
- haiku: Too limited for query optimization analysis
- opus: Overkill for standard database operations

## Next Steps

1. Review generated agent at `agents/database-admin.md`
2. Customize capabilities for your specific database stack
3. Add domain-specific examples
4. Test with `/optimize-agent agents/database-admin.md --dry-run`
```

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

### Description Best Practices
- Include "Use PROACTIVELY for..." to improve agent routing
- Example: "Database specialist for schema design. Use PROACTIVELY for query optimization, migration planning, or database architecture decisions."

### Constraints (DO NOT) Section
- First section after frontmatter identity sentence
- 3-7 specific prohibitions defining agent boundaries
- Example: "DO NOT modify production code directly" for QA agents

### Purpose Section
- Clear statement of agent's role
- Specific domain and boundaries
- Integration context

### Capabilities
- Organized by category
- Actionable, specific items
- No overlap with other agents

### Worktask Integration
- Stage codes (PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR)
- State ledger integration
- Handoff protocols

### Completion Verification (optional)
- A **supplement** to `stage-contracts.md § Completion Verification`, never a restatement of it
- Include it only when the stage adds checks the shared contract does not cover; omit it entirely otherwise
- Sits immediately before § Handoff Protocol

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

This command is used by:
- prompt-engineer agent for creating new agents
- When expanding the agent ecosystem
- For specialized domain agents
