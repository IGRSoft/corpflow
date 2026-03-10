---
name: create-skill
description: Create new skill definitions with proper structure, knowledge patterns, and best practices
argument-hint: <skill name and purpose>
model: sonnet
---

# Create Skill Command

Create new skill definitions with proper structure, knowledge patterns, and best practices. Generates production-ready skill files as reusable knowledge modules.

## Usage

```
/create-skill <name> --purpose <description>
/create-skill "api-patterns" --purpose "REST API design patterns and anti-patterns"
/create-skill "stage-transitions" --type shared --purpose "Stage transition rules"
```

## Options

- `--purpose <description>` - Skill purpose (required)
- `--type <regular|shared>` - Skill type (default: regular)
- `--template <minimal|standard|comprehensive>` - Template style (default: standard)
- `--user-invocable` - Mark as user-invocable (adds `(user)` to description)
- `--output <path>` - Output path (default: `skills/<name>.md` or `skills/shared/<name>.md`)

## Examples

```
/create-skill "api-patterns" --purpose "REST API design patterns, versioning strategies, and error handling conventions"
/create-skill "git-workflow" --purpose "Git branching strategies and merge patterns" --user-invocable
/create-skill "stage-transitions" --type shared --purpose "Stage transition rules and validation logic"
/create-skill "performance-tuning" --purpose "Performance optimization patterns for mobile applications" --template comprehensive
/create-skill "error-handling" --purpose "Error classification, retry strategies, and escalation patterns" --template minimal
```

## Skill Types

### Regular Skills (`skills/<name>.md`)
- Have YAML frontmatter with `name` and `description`
- Registered individually in marketplace.json
- Can be referenced by agents and commands
- Contain domain knowledge, patterns, and guidelines

### Shared Skills (`skills/shared/<name>.md`)
- NO frontmatter (pure markdown)
- NOT registered in marketplace.json
- Referenced by other skills and agents via relative path
- Act as canonical reference documents (single source of truth)

### When to Use Each

| Scenario | Type |
|----------|------|
| Domain knowledge (security patterns, testing strategies) | Regular |
| Process guidelines (five-whys, estimation methodology) | Regular |
| Canonical reference data (stage codes, task system API) | Shared |
| Helper functions referenced by multiple skills | Shared |
| Workflow configuration data | Shared |

## Templates

### Minimal
Focused reference for a single topic (target: under 50 lines):
- Frontmatter (name, description) or no frontmatter for shared
- H1 title
- Core principles or process (3-5 items)
- Quick reference or checklist
- Related section

### Standard (Default)
Balanced knowledge module (target: 100-200 lines):
- Frontmatter (name, description) or no frontmatter for shared
- H1 title with one-sentence summary
- Core Principles / Process (organized subsections)
- Patterns or Techniques (with examples)
- Checklist or Quick Reference
- Anti-Patterns (common mistakes)
- Related section

### Comprehensive
Deep reference document (target: 200-400 lines):
- Frontmatter (name, description) or no frontmatter for shared
- H1 title with context paragraph
- Core Principles (numbered, detailed)
- Patterns / Techniques (with before/after examples)
- Decision Matrices or Selection Guides
- Implementation Examples (code or markdown)
- Anti-Patterns with fixes
- Quick Reference Card
- Related section

## Output Format

```markdown
# Skill Created: api-patterns

## Generated File
`skills/api-patterns.md`

## Configuration

| Setting | Value |
|---------|-------|
| Name | api-patterns |
| Type | regular |
| Template | standard |
| User-Invocable | No |

## Preview

---
name: api-patterns
description: REST API design patterns, versioning strategies, and error handling conventions
---

# API Patterns

[Preview of first 500 characters]

## Key Principle

**Skills are knowledge, not execution.** This skill contains reference patterns and guidelines. It has no `model` field because it does not execute — agents and commands consume it.

## Registration

Add to `.claude-plugin/marketplace.json` skills array:
"./skills/api-patterns.md"

(Shared skills do not need marketplace registration.)

## Next Steps

1. Review generated skill at `skills/api-patterns.md`
2. Customize patterns for your specific domain
3. Add concrete examples and anti-patterns
4. Link from relevant agents and commands
5. Register in `.claude-plugin/marketplace.json` (regular skills only)
```

## Guardrails

1. **No model field**: Skills MUST NOT have a `model` field in frontmatter. Skills are knowledge modules consumed by agents/commands that have their own model selection.

2. **Size limit**: Target under 500 lines. If content exceeds this, recommend splitting into a primary skill plus shared reference files.

3. **No execution logic**: Skills should not contain instructions like "execute", "run", "implement". They describe patterns, not actions.

4. **Single responsibility**: Each skill should cover one coherent domain. If the purpose spans multiple domains, recommend separate skills.

5. **Shared skill criteria**: Only use `--type shared` when the content is canonical reference data used by multiple other skills/agents.

## Skill Structure Guidelines

### Regular Skill Format
```yaml
---
name: skill-name
description: Brief purpose statement. (user) suffix if user-invocable.
---

# Skill Title

One-sentence summary.

## Core Principles / Process
[Organized subsections with knowledge]

## Patterns / Techniques
[Practical guidance with examples]

## Quick Reference / Checklist
[Condensed reference card]

## Related
[Links to related skills, agents, commands]
```

### Shared Skill Format (NO frontmatter)
```markdown
# Title

[Pure reference content — tables, code blocks, canonical data]

## Related
[Links to related docs]
```

### Description Best Practices
- Focus on what knowledge the skill provides
- Include when/why an agent would need this knowledge
- Append `(user)` if the skill is designed for direct user invocation
- Keep under 100 characters

## Integration

This command is used by:
- prompt-engineer agent for creating new skills
- workflow-engineer agent for expanding the knowledge base
- When adding domain knowledge to the ecosystem

Completes the creation toolchain:
- `/create-agent` - create agents
- `/create-command` - create commands
- `/create-skill` - create skills (this)

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [create-agent](./create-agent.md) - Create new agents
- [create-command](./create-command.md) - Create new commands
- [optimize-command](./optimize-command.md) - Optimize existing commands
- [prompt-audit](./prompt-audit.md) - Audit quality
