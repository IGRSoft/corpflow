---
name: prompt-audit
description: Comprehensive audit of agents, commands, skills, and prompts for quality, consistency, and best practices
argument-hint: '[--scope agents|commands|skills|all]'
# tools: Write takes no path predicate, so the bound is stated here and in `## Options`:
# the only file this command creates is `.context/audits/prompt-audit-<YYYYMMDD-HHMMSS>.md`.
# Edit exists solely for `--fix`, bounded to files this same run already read under `--scope`.
allowed-tools: Read, Glob, Grep, Write, Edit
related:
  - agents/prompt-engineer.md
  - commands/optimize-agent.md
  - commands/optimize-command.md
  - commands/create-agent.md
---

# Prompt Audit Command

Comprehensive audit of agents, commands, skills, and prompts for quality, consistency, and best practices. Identifies issues and generates improvement recommendations.

## Usage

```
/prompt-audit
/prompt-audit --agents
/prompt-audit --commands
/prompt-audit --skills
/prompt-audit --report
```

## Options

- `--agents` - Audit agents only
- `--commands` - Audit commands only
- `--skills` - Audit skill manifests only (`skills/**/SKILL.md`)
- `--report` - Write the audit report to `.context/audits/prompt-audit-<YYYYMMDD-HHMMSS>.md`; the only file this command creates
- `--fix` - Auto-fix minor issues (formatting, links) in place, only in files this run already read under `--scope`; never inside a `## Constraints (DO NOT)` block
- `--severity <level>` - Minimum severity: info, warning, error

## Examples

```
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
| Metric | Commands | Percentage |   (has Usage / Options / 3+ Examples / Output Format / Related / platform param)

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
- Model-Conditioned Findings are a *view*, not a second list: every row there is also a numbered entry under Critical or Warnings. The section exists because these findings are only legible next to the asset's resolved model (agents: `skills/shared/stage-codes.md § Agent Model Matrix`; commands/skills carry no model at all now), which the numbered lists do not carry.

## Audit Rules

### Agent Rules

1. Valid YAML frontmatter (name, description) and **no** `model:`/`effort:` key — those are no
   longer frontmatter fields; flag either as a finding, fix line: delete, the pair lives solely in
   `skills/shared/stage-codes.md § Agent Model Matrix`
2. Resolved model (matrix, not frontmatter) appropriate for task complexity
3. Clear purpose statement
4. No capability overlap with other agents
5. Worktask stage integration documented, and every stage code referenced still exists in `skills/shared/stage-codes.md` (removed/renamed stages are a critical finding)
6. Example interactions provided
7. `description` follows the trigger-first grammar (G1-G7) and the guidance form matches the failure class — both normative in `agents/prompt-engineer.md § Description grammar` and `§ Form to failure`
8. Body passes § Body Rules (disclosure, completion criteria, negation form, no-op pruning, model-conditioned anti-patterns, scope explicitness, emphasis inflation)

### Command Rules

1. Usage section with syntax
2. Options section with types and defaults
3. Minimum 3 diverse examples
4. Output format specification
5. Related section with links
6. Consistent option format
7. Body passes § Body Rules — the same seven checks agents get

### Body Rules (agents, commands, skills)

Normative source: `agents/prompt-engineer.md § Prompt-body doctrine`. These seven run on every asset
class — a `SKILL.md` is a prompt body with frontmatter on top, so its body is audited here even
though its frontmatter is audited under § Frontmatter Parsing Convention.

#### Body rule 1 — disclosure (information hierarchy)

Measure H2 subtree spans: `grep -n '^## ' <asset>`, difference consecutive line numbers, last span
runs to EOF. A span over **200 lines** is a *candidate*, not yet a finding.

Confirm each candidate with the doctrine's branching test. A candidate whose body is reached only on
*some* branches is a **disclosure finding**: report `<file>:<line>`, the span in lines, the branch
that reaches it, and a Fix line naming the reference file it belongs behind. A candidate every run
executes end to end is correctly inline and is not a finding.

Worked example, the plugin's largest manifest: `skills/worktask/SKILL.md`'s
`## Orchestrator Execution Loop` spans ~935 lines and is reached branch-wise (auto-decision path,
megatask mode, screenshot gate), so the audit reports it as a disclosure finding.

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
   `## Constraints (DO NOT)` blocks are reported, never auto-fixed: `--fix` must not touch them.
4. **No-op instructions.** Flag an instruction the asset's resolved model already obeys by default —
   the test is model-relative, so the same sentence can be load-bearing in one asset and waste in
   another. The Fix line is deletion of the whole sentence; a reworded no-op is still a no-op.

#### Body rule 5 — model-conditioned anti-patterns

Resolve the asset's model (agents: the matrix row; commands/skills carry no model at all, so this
rule does not fire on them), then check its body against that alias's row in
`skills/shared/model-prompting.md`. An instruction that collides with a documented behaviour of
that model is a finding whose Fix line is deletion, and whose evidence is the vendor page the canon
file cites — not the auditor's judgement.

##### Body rule 5 — the reliable greps

Run against the asset body. They are kept out of a table so the `|` alternations survive a
verbatim copy:

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

On an agent whose resolved model is `sonnet`, flag an instruction that names one item where the asset's
own scope covers a set, with no statement of which. Sonnet 5 follows instructions literally and does
not generalise from one item to the next, so "add a verdict line to the finding" leaves the other
findings unverdicted where "add a verdict line to every finding" does not.

The Fix line states the scope, never the emphasis: `every`, `each`, `all N`, or the named set. It is
not a finding on `opus` or `fable` assets, where the behaviour is not documented.

#### Body rule 7 — emphasis inflation

Count `CRITICAL`, `MUST`, `MANDATORY`, `BINDING`, `NEVER`, `ALWAYS` per asset:
`grep -coE '\b(CRITICAL|MUST|MANDATORY|BINDING|NEVER|ALWAYS)\b' <asset>`.

The finding is per-rule, not per-count: for each emphasised rule, name the failure class it targets
against `agents/prompt-engineer.md § Form to failure`. Emphasis is earned by row 1 — knows the rule,
skips it under pressure — and by nothing else. A rule with no recorded failure behind it is an
inflation finding whose Fix line downgrades the framing to the plain imperative.

Report the per-asset count alongside the findings, because the count is what makes the trend
visible across a sweep; do not raise a finding on the count alone. **`--fix` must not touch this
rule** — the same guard `## Constraints (DO NOT)` blocks carry, and for the same reason: a
mechanical downgrade cannot tell an earned emphasis from an inflated one.

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
