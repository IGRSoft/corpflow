---
name: prompt-audit
description: Comprehensive audit of agents, commands, and prompts for quality, consistency, and best practices
argument-hint: '[--scope agents|commands|all]'
allowed-tools: Read, Glob, Grep
model: sonnet
related:
  - agents/prompt-engineer.md
  - commands/optimize-agent.md
  - commands/optimize-command.md
  - commands/create-agent.md
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

Report skeleton — sections in this order:

~~~markdown
# Prompt Ecosystem Audit

## Summary
| Category | Total | Pass | Warn | Fail |   (rows: Agents, Commands, **Total**)
**Health Score**: N/100 (label)

## Critical Issues 🔴        (numbered; each: Issue / Location `file:line` / Details / Fix)
## Warnings ⚠️              (same schema, continuing the numbering)

## Agent Analysis
| Agent | Model | Clarity | Efficiency | Consistency |    + Model Distribution table

## Command Analysis
| Metric | Commands | Percentage |   (has Usage / Options / 3+ Examples / Output Format / Related / platform param)

## Consistency Checks
| Check | Status | Issues |   + Terminology Inconsistencies (| Term A | Term B | Occurrences |)

## Recommendations         (Priority 1 Fix Now / 2 Fix Soon / 3 Consider)
## Auto-Fixable Issues     (| Issue | Files | Action | — only with `--fix`)
## Audit Metadata          (Audit Date, Files Scanned, Rules Applied, Duration)
~~~

### Output Format — content rules

- Every finding cites a concrete location (`agents/<name>.md:<line>` or the command path) and an actionable Fix line.
- Scores are n/10; status glyphs ✅ Pass / ⚠️ Warn / 🔴 Fail.
- `--severity` filters which findings appear; the Summary counts stay unfiltered.
- Group identical findings across files into a single numbered entry listing the files.

## Audit Rules

### Agent Rules

1. Valid YAML frontmatter (name, description, model)
2. Model appropriate for task complexity
3. Clear purpose statement
4. No capability overlap with other agents
5. Worktask stage integration documented, and every stage code referenced still exists in `skills/shared/stage-codes.md` (removed/renamed stages are a critical finding)
6. Example interactions provided
7. `description` follows the trigger-first grammar (G1-G7) and the guidance form matches the failure class — both normative in `agents/prompt-engineer.md § Description grammar` and `§ Form to failure`

### Command Rules

1. Usage section with syntax
2. Options section with types and defaults
3. Minimum 3 diverse examples
4. Output format specification
5. Related section with links
6. Consistent option format

### Consistency Rules

1. Platform values: `<apple|android|web|systems|backend|ai|all>` — the canonical set, matching `skills/shared/platform-detection.md`. A command whose scope genuinely excludes some platforms may list a subset (the `design-*` commands are UI-only, so `<apple|android|web|all>` is correct there); what is flagged is Apple sub-platforms leaking in (`iOS|macOS`) or a platform advertised with no content path behind it.
2. Option syntax: `--option <value>` or `--flag`
3. Section ordering: Usage → Options → Examples → Output → Integration → Related
4. Terminology standardized

### Frontmatter Parsing Convention

Definition files (`agents/*.md`, `commands/*.md`, `skills/*/SKILL.md`) are matched by the `---`-delimited YAML block at the top of the file. When detecting or extracting that block:

1. **Tolerate CRLF and trailing whitespace on the delimiter lines.** Match `---` even when followed by spaces/tabs and `\r\n`, not only a bare `---\n`. Never report "missing frontmatter" for a file whose only difference is line endings.
2. **Distinguish absent from malformed.** *Absent frontmatter* → error (the file has no metadata at all). *Present but empty/malformed `description:`* → error reported as `<file> — missing or malformed description`, because an empty description silently breaks skill/command triggering even though the block parses.
3. **`description` is required and non-empty.** A `description:` with no value, only whitespace, or an unparseable value is a violation — reported distinctly from a wholly missing field so the fix is unambiguous.

## Integration

Run for periodic ecosystem health checks, before major releases, after adding new agents/commands, and during prompt engineering reviews.
