# Change Categories — Classification Taxonomy

Each diff hunk is assigned exactly one category plus a confidence (`high | medium | low`). Low-confidence items go to Deferred; high/medium go to Proposed.

## Category Table

| Category | Signal | Typical proposal shape |
|----------|--------|-------------------------|
| `tone` | Reworded sentences preserving meaning | Prompt wording edit |
| `structure` | Sections added/removed/reordered; heading level changes | Add/remove/reorder section in target template |
| `accuracy` | Fact corrections: numbers, names, technical claims, typos | Add constraint or correct example |
| `completeness` | New content fills a genuine gap (missing edge case, new capability) | Add capability/responsibility/constraint bullet |
| `style` | Formatting, naming conventions, indentation, list style | Style-guide reference or explicit constraint |
| `domain-knowledge` | Project-specific rules the agent did not know (Swift 6 Sendable, internal API, naming) | Add domain reference, glossary, or explicit rule |

## Decision Tree

Run the hunk through these questions in order; first match wins:

1. **Is the meaning of the original text now factually different?** → `accuracy`
2. **Was information added that the target prompt could have supplied?** → `domain-knowledge` if project-specific, `completeness` if generic
3. **Did the text structure change (sections, hierarchy, ordering)?** → `structure`
4. **Did formatting/naming change without altering meaning?** → `style`
5. **Otherwise — reworded, same meaning?** → `tone`

## Confidence Calibration

The classifier must be conservative. Prefer `low` when in doubt — low-confidence items do not pester the user, high-confidence ones do.

| Signal | Confidence |
|--------|------------|
| ≥ 1 full sentence reworded, meaning preserved | `tone` high |
| ≤ 2 words swapped (e.g. `approach` → `strategy`) | `tone` low |
| Fact correction (any magnitude) | `accuracy` high |
| New section heading appears | `structure` high |
| Existing sections reordered only | `structure` medium |
| ≥ 1 paragraph of new content | `completeness` high |
| ≤ 1 paragraph of new content | `completeness` medium |
| Formatting/naming change, one-off | `style` low |
| Project-specific rule introduced | `domain-knowledge` high |
| Same change pattern appears ≥ 2 places | bump confidence +1 tier |
| Change appears only once in a low-traffic file | cap confidence at `medium` |

## Examples

| Observed diff | Classification | Proposal |
|---------------|----------------|----------|
| `30 seconds` → `60 seconds` | `accuracy` / high | Correct the rule in whichever prompt documented 30s; add a constraint if none exists |
| `extension User: @unchecked Sendable {}` added to a cross-actor type | `domain-knowledge` / high | Add a Sendable DO NOT constraint to the developer agent |
| `approach` → `strategy` | `tone` / low | Deferred — a single-word swap carries no systemic signal |
| New `## Risk Assessment` section in `.context/planning-0.md` | `structure` / high | Require that section in `agents/product-manager.md`'s planning template |
| `Tests Added:` → `## Tests Added` across 3 files | `style` / medium | Heading-hierarchy note to the producing agent (≥ 2 files is what lifts it above `low`) |

The pattern each row follows: read the diff, then propose against the *producing* prompt file — never against the artifact the user edited.

## Cross References

- `SKILL.md § Step 3` — where classification happens in the pipeline
- `references/retrospective-template.md` — how categories render in `learnings.md`
- `references/target-mapping.md` — mapping categorized diffs to target files
- `commands/optimize-agent.md § Focus Areas` — similar category taxonomy (clarity/efficiency/consistency/tools/model)
