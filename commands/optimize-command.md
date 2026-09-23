---
name: optimize-command
description: Analyze and optimize existing command definitions for usability, consistency, and completeness
version: 0.3.0
argument-hint: <command name or path>
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/prompt-engineer.md
  - commands/create-agent.md
  - commands/optimize-agent.md
  - commands/prompt-audit.md
---

# Optimize Command

Analyze and optimize existing command definitions for usability, consistency, and completeness. Improves command quality using prompt engineering best practices.

## Usage

```
/optimize-command <command-file>
/optimize-command --all
/optimize-command commands/estimate.md --focus examples
```

## Options

- `--all` - Optimize all commands in the commands directory
- `--focus <area>` - Focus area: usage, options, examples, output, integration, frontmatter
- `--dry-run` - Show recommendations without making changes
- `--report` - Generate detailed optimization report

## Examples

```
/optimize-command commands/worktask.md
/optimize-command commands/estimate.md --focus options
/optimize-command --all --dry-run
/optimize-command commands/test-plan.md --focus examples --report
```

## Output Format

Report skeleton — sections in this order:

~~~markdown
# Command Optimization Report — /<name>

## Frontmatter Findings
| Field | Observed | Required | Severity | Suggested edit |

## Current State
| Metric | Score | Status |
Rows: Usage Clarity, Options, Examples, Output Format, Integration. **Overall Score**: mean.

## <Area> Improvements        (one per scored area, Current → Recommended + **Changes** list)
Options / Output Format use `| Option | Status | Issue | Recommendation |`.

## Recommendations
Must Apply / Should Apply / Consider — numbered, most impactful first.

## Changes Applied
| Section | Change | Impact |

## Summary
| Metric | Before | After | Change |
~~~

### Output Format — content rules

- Score every area even when `--focus` narrows the edits; the reader needs the baseline.
- Scoring scale is n/10 with a status glyph: ✅ Good/Excellent (≥8), ⚠️ Improvable (6–7), 🔴 Insufficient (≤5).
- Quote the command's exact current text before the recommended replacement — never paraphrase it.
- Frontmatter findings come first and are blocking (Must Apply tier).
- `--dry-run` omits `## Changes Applied` and the Summary "After" column.

## Focus Areas

`--focus` values `usage`, `options`, `examples`, `output`, and `integration` each narrow the pass to the matching row of § Optimization Criteria. `--focus frontmatter` runs only § Frontmatter Audit (description length, model fit, allowed-tools precision, argument-hint alignment).

## Optimization Criteria

| Area (`--focus`) | Criteria |
|------|----------|
| `usage` | Clear syntax with all arguments shown; optional vs required indicated; sensible defaults documented |
| `options` | All options documented with types; valid values specified for enums; defaults stated explicitly; purpose clear from description |
| `examples` | Minimum 3 diverse examples; cover common use cases; show option combinations; realistic values |
| `output` | Output format structured and parseable; all fields documented; status indicators consistent; actionable information |
| `integration` | Related commands linked; agent relationships documented; worktask stage usage noted |
| `body` | Passes `commands/prompt-audit.md § Body Rules`. Rules 5–7 read the command's own `model:` — see `skills/shared/model-prompting.md` |

### Frontmatter Audit

Run on every command regardless of focus area. Treat findings here as blocking on the "Must Apply" tier. Reference rubric: `skills/shared/model-selection.md § Cost Tiers`.

#### Frontmatter Audit — P0 fields

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `description` | ≤250 characters. Same metric as agents. | P0 |
| `model` | Strict membership: ∈ {`haiku`, `sonnet`, `opus`}. Tier per `model-selection.md`: meta-tooling and orchestration → `opus`; analysis/summary → `sonnet`; one-shot scans → `haiku`. Flag commands that optimize other prompts (`/optimize-*`, `/create-*`, `/prompt-audit`) running on `sonnet` or below — meta-optimization is opus tier. | P0 |

#### Frontmatter Audit — P1 fields

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `allowed-tools` | Explicit list. Bash subcommand scoping required: `Bash(git:*)`, `Bash(gh:*)`, `Bash(swift test:*)` — never bare `Bash` unless the command's purpose is general shell access. Flag `Write` declared without `Read` (likely incomplete). | P1 |
| `argument-hint` | Must align with the `## Usage` positional/optional surface: count `--<flag>` mentions in Usage vs the hint and flag mismatch (hint says `<command name>` but Usage shows `--all`, `--focus`, `--dry-run`). Square brackets for optional positional, angle brackets for required. | P1 |

#### Frontmatter Audit — P1 description trigger phrase

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `description` trigger phrase | Include a recognised trigger phrase (`Use when …`, `Use after …`, `Use PROACTIVELY when …`, `Auto-loads when …`, `Reference when …`, `Apply for …`) so the model can decide whether to invoke. EXEMPT: `disable-model-invocation: true` (slash-only) or `paths:` frontmatter (path-triggered) — these bypass description-trigger auto-invocation and are not flagged. | P1 |

#### Frontmatter Audit — P2 consistency checks

| Field | Audit Rule | Severity |
|-------|------------|----------|
| `$ARGUMENTS` substitution | Body references `$ARGUMENTS` → `argument-hint` is non-empty. Body has no `$ARGUMENTS` but hint is set → suggest removing the hint. Unmatched `$1`/`$2` placeholders survive verbatim in bodies (not silently stripped), so positional forms are safe to audit literally. | P2 |
| Option-to-example coverage | Every `--option` in `## Options` should appear at least once in `## Examples`. Compute `set(options) − set(options-used-in-examples)`; flag each diff as "missing example for `--<flag>`". | P2 |
| Output-format consistency | Output samples must match the schema declared in prose — e.g. flag a command claiming "JSON output via `--format json`" whose Output Format shows only Markdown. | P2 |
| Related links | Cross-reference targets (`./create-agent.md`, `../agents/prompt-engineer.md`) must resolve. Flag dead links. | P2 |

#### Frontmatter Audit — reporting

Report failures as a `## Frontmatter Findings` table before the scoring tables in § Output Format. Row schema mirrors `/optimize-agent`: `| Field | Observed | Required | Severity | Suggested edit |`.

## Integration

Used by the `prompt-engineer` agent for command optimization, during command ecosystem maintenance, and after worktask changes that require command updates.
