---
name: prompt-audit
description: Audit agents, commands, and skills for prompt quality, consistency, and best practices; run for periodic health checks, before a release, or after adding assets
argument-hint: '[--agents|--commands|--skills] [--report] [--fix] [--severity info|warning|error]'
# tools: Write takes no path predicate, so the bound is stated here and in `## Options`:
# the only file this command creates is `.context/audits/prompt-audit-<YYYYMMDD-HHMMSS>.md`.
# Edit exists solely for `--fix`, bounded to files this same run already read.
allowed-tools: Read, Glob, Grep, Write, Edit
related:
  - agents/prompt-engineer.md
  - commands/optimize-agent.md
  - commands/optimize-command.md
  - commands/create-agent.md
---

# Prompt Audit Command

Audit agents, commands, and skill manifests against § Audit Rules and report each finding with a fix.

## Options

With no scope flag, all three asset classes are audited.

| Option | Values | Effect |
|--------|--------|--------|
| `--agents` | — | Audit agents only |
| `--commands` | — | Audit commands only |
| `--skills` | — | Audit skill manifests only (`skills/**/SKILL.md`) |
| `--report` | — | Write the report to `.context/audits/prompt-audit-<YYYYMMDD-HHMMSS>.md`, the only file this command creates |
| `--fix` | — | Auto-fix minor issues (formatting, links) in place, only in files this run already read; never inside a `## Constraints (DO NOT)` block |
| `--severity <level>` | `info`, `warning`, `error` | Minimum severity shown |

## Examples

```
/prompt-audit [--agents|--commands|--skills] [--report] [--fix] [--severity info|warning|error]

/prompt-audit
/prompt-audit --agents --report
/prompt-audit --commands --fix
/prompt-audit --skills --report
/prompt-audit --severity warning
```

## Output Format

Report skeleton — sections in this order:

~~~markdown
# Prompt Ecosystem Audit

## Summary
| Category | Total | Pass | Warn | Fail |   (rows: Agents, Commands, Skills, **Total**)
**Health Score**: N/100 (label)

## Critical Issues 🔴        (numbered; each: Issue / Location `file:line` / Details / Fix)
## Warnings ⚠️              (same schema, continuing the numbering)

## Agent Analysis
| Agent | Model | Clarity | Efficiency | Consistency |    + Model Distribution table

## Command Analysis
| Metric | Commands | Percentage |   (has Options table / synopsis-first Examples / 3+ Examples / Output Format / `related:` / platform param)

## Model-Conditioned Findings
| Asset | Model | Rule | Finding | Fix |   (body rules 5-7, plus rule 7's per-asset count)

## Consistency Checks
| Check | Status | Issues |   + Terminology Inconsistencies (| Term A | Term B | Occurrences |)

~~~

### Report skeleton — closing sections

Continuing the same order, after Consistency Checks:

~~~markdown
## Recommendations         (Priority 1 Fix Now / 2 Fix Soon / 3 Consider)
## Auto-Fixable Issues     (| Issue | Files | Action | — only with `--fix`)
## Audit Metadata          (Audit Date, Files Scanned, Rules Applied, Duration)
~~~

### Output Format — content rules

- Every finding cites a concrete location (`agents/<name>.md:<line>` or the command path) and an actionable Fix line.
- Scores are n/10; status glyphs ✅ Pass / ⚠️ Warn / 🔴 Fail.
- `--severity` filters which findings appear; the Summary counts stay unfiltered.
- Group identical findings across files into a single numbered entry listing the files.
- Skill-manifest findings share the same numbered Critical/Warnings lists and the same `<file>:<line>` locators; the Summary carries a Skills row.
- Model-Conditioned Findings are a view, not a second list: every row there is also a numbered entry under Critical or Warnings, shown next to the asset's resolved model (`skills/shared/stage-codes.md § Agent Model Matrix`), which the numbered lists do not carry.

## Audit Rules

### Agent Rules

1. Valid YAML frontmatter (name, description) with no `model:`/`effort:` key — flag either; Fix:
   delete it, the pair is set only in `skills/shared/stage-codes.md § Agent Model Matrix`
2. Resolved model (matrix, not frontmatter) appropriate for task complexity
3. Clear purpose statement
4. No capability overlap with other agents
5. Worktask stage integration documented, and every stage code referenced still exists in `skills/shared/stage-codes.md` (removed/renamed stages are a critical finding)
6. Example interactions provided
7. `description` follows the trigger-first grammar (G1-G7) and the guidance form matches the failure class — both normative in `agents/prompt-engineer.md § Description grammar` and `§ Form to failure`
8. Body passes § Body Rules

### Command Rules

1. § Examples opens on the synopsis line (`/<name> <args>`), which replaces a separate `## Usage`
2. § Options is a table giving each option's values and default
3. Minimum 3 diverse examples
4. Output format specification
5. `related:` frontmatter lists the commands and agents it works with, and every entry resolves
6. Consistent option format
7. Body passes § Body Rules

### Body Rules (agents, commands, skills)

Normative source: `agents/prompt-engineer.md § Prompt-body doctrine`. All seven run on every asset
class; a `SKILL.md` body is audited here, its frontmatter under § Frontmatter Parsing Convention.

#### Body rule 1 — disclosure (information hierarchy)

Measure H2 subtree spans: `grep -n '^## ' <asset>`, difference consecutive line numbers, last span
runs to EOF. A span over 200 lines is a candidate, not yet a finding.

Confirm each candidate with the doctrine's branching test. A candidate reached only on *some*
branches is a disclosure finding: report `<file>:<line>`, the span in lines, the branch that
reaches it, and a Fix line naming the reference file it belongs behind. A candidate every run
executes end to end is correctly inline.

Example: `skills/worktask/SKILL.md § Orchestrator Execution Loop` is reached branch-wise
(auto-decision path, megatask mode, screenshot gate), so it is a disclosure finding.

#### Body rule 2 — completion criteria

Every numbered step ends on a criterion. Flag a criterion that fails either axis:

- **clarity** — done is not distinguishable from not-done ("reviewed the diff");
- **demand** — satisfiable by a plausible assertion because no artifact is named to check it against
  ("produce a change list").

The Fix line names the artifact the criterion is checked against; it never adds adjectives.

#### Body rules 3–4 — negation form and no-op pruning

3. **Negation form.** For each `DO NOT` / "never" rule, name the failure class it targets against
   `agents/prompt-engineer.md § Form to failure`. A prohibition aimed at any row but "knows the
   rule, skips it under pressure" is a warning whose Fix line names the correct form — positive
   recipe, REQUIRED template slot, or conditional on an observable predicate. Existing
   `## Constraints (DO NOT)` blocks are reported, never auto-fixed.
4. **No-op instructions.** Flag an instruction the asset's resolved model already obeys by default;
   the test is model-relative, so the same sentence can be load-bearing in one asset and waste in
   another. The Fix line deletes the whole sentence; a reworded no-op is still a no-op.

#### Body rule 5 — model-conditioned anti-patterns

Agents only: commands and skills carry no model, so the rule does not fire on them. Resolve the
agent's matrix row, then check its body against that alias's row in
`skills/shared/model-prompting.md`. An instruction that collides with a documented behaviour of
that model is a finding whose Fix line is deletion, and whose evidence is the vendor page the canon
file cites, not the auditor's judgement.

##### Body rule 5 — the reliable greps

Run against the asset body (kept out of a table so the `|` alternations copy verbatim):

- `opus` — over-verification; Opus 5 already does this, and the instruction compounds it:

  ```
  grep -niE 'double.?check|re-?verify|verify (your|the) (answer|work|reasoning)|final verification step' <asset>
  ```

- `opus` — the same, in its most expensive form:

  ```
  grep -niE 'use a subagent to (verify|double)|delegate.*verif' <asset>
  ```

- any model — recall suppression at a detection step; see `commands/tech-code-review.md § Phase 2`:

  ```
  grep -niE 'only report (high|critical)|be conservative|do ?n.?t nitpick|only.*if you are (sure|certain)' <asset>
  ```

##### Body rule 5 — the two guards

Skip either and the rule manufactures findings:

- **A completion criterion is not a verification instruction.** "The screenshot manifest exists on
  disk", "the audit row is present", "`git status` is clean" name an artifact and are graded under
  body rule 2. Only a re-read of the model's own reasoning is a rule-5 finding.
- **A filtering step is allowed to filter.** The anti-pattern is a confidence bar on a *detection*
  step. A ranking, verification, or triage phase that says "drop what you can disprove" is correct
  and is not a finding.

#### Body rule 6 — scope explicitness

On an agent whose resolved model is `sonnet`, flag an instruction that names one item where the
asset's own scope covers a set, with no statement of which. Sonnet 5 does not generalise from one
item to the next, so "add a verdict line to the finding" leaves the other findings unverdicted.
The Fix line states the scope, never the emphasis: `every`, `each`, `all N`, or the named set.

#### Body rule 7 — emphasis inflation

Count per asset: `grep -coE '\b(CRITICAL|MUST|MANDATORY|BINDING|NEVER|ALWAYS)\b' <asset>`, and
report the count alongside the findings so the trend shows across a sweep.

The finding is per rule, never on the count alone: for each emphasised rule, name the failure class
it targets against `agents/prompt-engineer.md § Form to failure`. Emphasis is earned by row 1 —
knows the rule, skips it under pressure — and nothing else; any other emphasised rule is an
inflation finding whose Fix line downgrades it to the plain imperative.

`--fix` leaves this rule alone, as it does `## Constraints (DO NOT)` blocks: a mechanical
downgrade cannot tell earned emphasis from inflated.

### Consistency Rules

1. Platform values: `<apple|android|web|systems|backend|ai|all>`, matching `skills/shared/platform-detection.md`. A command whose scope excludes some platforms may list a subset (the UI-only `design-*` commands use `<apple|android|web|all>`). Flag Apple sub-platforms (`iOS|macOS`) or a platform advertised with no content path behind it.
2. Option syntax: `--option <value>` or `--flag`
3. Section ordering: Options → Examples → Output Format, then the command's own sections
4. Terminology standardized

### Frontmatter Parsing Convention

Definition files (`agents/*.md`, `commands/*.md`, `skills/*/SKILL.md`) are matched by the `---`-delimited YAML block at the top of the file. When detecting or extracting that block:

1. Match the delimiter lines with trailing spaces/tabs and `\r\n` too, so a file that differs only in line endings is not reported as missing frontmatter.
2. Absent frontmatter is an error.
3. `description:` is required and non-empty. A value that is empty, whitespace-only, or unparseable is an error reported as `<file> — missing or malformed description`, distinct from a wholly missing field so the fix is unambiguous: an empty description silently breaks skill/command triggering even though the block parses.
