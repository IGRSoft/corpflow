---
name: create-command
description: Create new command definitions with proper structure, model selection, and best practices
argument-hint: <command name and purpose>
model: sonnet
---

# Create Command Command

Create new command definitions with proper structure, model selection, and best practices. Generates production-ready command files following established conventions.

## Usage

```
/create-command <name> --purpose <description>
/create-command "deploy-check" --purpose "Pre-deployment readiness verification"
/create-command "sprint-retro" --model sonnet --template comprehensive
```

## Options

- `--purpose <description>` - Command purpose (required)
- `--model <haiku|sonnet|opus>` - Model selection (default: auto-select)
- `--template <minimal|standard|comprehensive>` - Template style (default: standard)
- `--stage <code>` - Workflow stage: PL, AR, TL, DV, SR, QA, DC, RE, FN, ST
- `--agent <name>` - Primary agent that uses this command
- `--output <path>` - Output path (default: commands/<name>.md)

## Examples

```
/create-command "deploy-check" --purpose "Pre-deployment readiness verification checklist"
/create-command "api-docs" --purpose "Generate API documentation from source" --model haiku --template minimal
/create-command "security-scan" --purpose "Run security scanning analysis" --model sonnet --stage SR --agent security-reviewer
/create-command "sprint-retro" --purpose "Sprint retrospective facilitation and report generation" --template comprehensive
/create-command "code-metrics" --purpose "Analyze code complexity and quality metrics" --stage DV --agent developer
```

## Templates

### Minimal
Lean commands with focused scope:
- Frontmatter (name, description, model)
- Usage section (1-2 syntax variants)
- Options section (essential options only)
- Output Format (brief)
- Related section

### Standard (Default)
Balanced structure for most commands:
- Frontmatter (name, description, model)
- Usage section with multiple syntax variants
- Options section with types, defaults, valid values
- Examples section (3+ diverse)
- Output Format with markdown template
- Integration section (who uses this, when)
- Related section with links

### Comprehensive
Full structure for complex commands:
- Frontmatter (name, description, model)
- Usage section with full syntax variants
- Options section with complete documentation
- Examples section (5+ covering edge cases)
- Output Format with detailed markdown template
- Auto-Detection / Routing logic (if applicable)
- Integration section with workflow stage context
- Error Handling / Edge Cases
- Related section

## Output Format

```markdown
# Command Created: deploy-check

## Generated File
`commands/deploy-check.md`

## Configuration

| Setting | Value |
|---------|-------|
| Name | deploy-check |
| Model | haiku |
| Template | standard |
| Stage | FN |
| Agent | project-manager |

## Preview

---
name: deploy-check
description: Pre-deployment readiness verification checklist for ensuring build quality and release preparedness
model: haiku
---

[Preview of first 500 characters]

## Model Selection Rationale

**Selected**: haiku
**Reason**: Task is procedural with well-defined checklist steps requiring validation rather than complex reasoning.

**Alternatives Considered**:
- sonnet: Unnecessary for checklist validation
- opus: Significantly overkill for procedural verification

## Registration

Add to `.claude-plugin/marketplace.json` commands array:
"./commands/deploy-check.md"

## Next Steps

1. Review generated command at `commands/deploy-check.md`
2. Customize options for your specific use case
3. Add domain-specific examples
4. Test with `/optimize-command commands/deploy-check.md --dry-run`
5. Register in `.claude-plugin/marketplace.json`
```

## Model Auto-Selection

When `--model` is not specified, selection based on purpose and stage analysis:

### By Purpose Keywords

| Purpose Keywords | Model | Rationale |
|-----------------|-------|-----------|
| format, check, validate, list, export, status | haiku | Procedural, rule-based tasks |
| implement, review, analyze, design, plan, report, audit | sonnet | Balanced reasoning and generation |
| architect, strategize, optimize, research, compare, assess | opus | Complex multi-factor analysis |

### By Workflow Stage

| Stage | Default Model | Rationale |
|-------|--------------|-----------|
| QA, DC, RE | haiku | Procedural, checklist-based stages |
| PL, TL, DV, ST, FN | sonnet | Coordination and balanced reasoning |
| AR, SR | opus | Architecture and security analysis |

Stage-based selection takes precedence when `--stage` is provided.

## Command Structure Guidelines

### Frontmatter (Required)
```yaml
---
name: command-name
description: Brief purpose statement (1-2 sentences)
model: haiku|sonnet|opus
---
```

### Section Ordering (Required)
1. **Usage** - syntax examples
2. **Options** - flags, types, defaults
3. **Examples** - 3+ diverse scenarios
4. **Output Format** - markdown template of expected output
5. **Integration** - who uses this, when, workflow context
6. **Related** - links to agents, commands, skills

### Description Best Practices
- Focus on the action the command performs
- Include 1-2 key capabilities
- Keep under 100 characters
- Use active voice (e.g., "Generate...", "Analyze...", "Create...")

### Options Best Practices
- Document all options with types and defaults
- Use `<value>` for required values, `[value]` for optional
- Specify valid values for enums (e.g., `<haiku|sonnet|opus>`)
- Group related options together

### Examples Best Practices
- Minimum 3 diverse examples
- Cover common use cases and edge cases
- Show option combinations
- Include realistic values

## Integration

This command is used by:
- prompt-engineer agent for creating new commands
- workflow-engineer agent for expanding command capabilities
- When extending the command ecosystem

Completes the creation toolchain:
- `/create-agent` - create agents
- `/create-command` - create commands (this)
- `/create-skill` - create skills

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [create-agent](./create-agent.md) - Create new agents
- [create-skill](./create-skill.md) - Create new skills
- [optimize-command](./optimize-command.md) - Optimize existing commands
- [prompt-audit](./prompt-audit.md) - Audit command quality
