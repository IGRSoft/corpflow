# Change Categories — Classification Taxonomy

Each diff hunk is assigned exactly one category plus a confidence (`high | medium | low`). Low-confidence items go to Deferred; high/medium go to Proposed.

## Category Table

| Category | Signal | Confidence heuristic | Typical proposal shape |
|----------|--------|----------------------|-------------------------|
| `tone` | Reworded sentences preserving meaning | **high** if ≥ 1 sentence reworded; **low** if ≤ 2 words swapped | Prompt wording edit |
| `structure` | Sections added/removed/reordered; heading level changes | **high** if a new section appears; **medium** if reordered | Add/remove/reorder section in target template |
| `accuracy` | Fact corrections: numbers, names, technical claims, typos | **high** always (factual correctness is critical) | Add constraint or correct example |
| `completeness` | New content fills a genuine gap (e.g., missing edge case, new capability) | **high** if ≥ 1 paragraph added; **medium** if ≤ 1 paragraph | Add capability/responsibility/constraint bullet |
| `style` | Formatting, naming conventions, indentation, list style | **medium** if consistent change across ≥ 2 places; **low** if one-off | Style-guide reference or explicit constraint |
| `domain-knowledge` | Introduces project-specific rules the agent did not know (Swift 6 Sendable, project naming, internal API) | **high** always (knowledge gaps repeat) | Add domain reference, glossary, or explicit rule |

## Decision Tree

Run the hunk through these questions in order; first match wins:

1. **Is the meaning of the original text now factually different?** → `accuracy`
2. **Was new information added that the target prompt could have prevented (missing rule, missing capability)?** → `domain-knowledge` if project-specific; `completeness` if generic.
3. **Did the text structure change (sections, hierarchy, ordering)?** → `structure`
4. **Did formatting/naming change without altering meaning?** → `style`
5. **Otherwise — wording reword, same meaning?** → `tone`

## Confidence Calibration

The classifier must be conservative. Prefer `low` when in doubt — low-confidence items do not pester the user, high-confidence ones do.

| Signal | Confidence |
|--------|------------|
| ≥ 1 full sentence reworded, meaning preserved | `tone` high |
| ≤ 2 words swapped (e.g., `approach` → `strategy`) | `tone` low |
| Fact correction (any magnitude) | `accuracy` high |
| New section heading appears | `structure` high |
| Existing sections reordered only | `structure` medium |
| ≥ 1 paragraph of new content | `completeness` high |
| ≤ 1 paragraph of new content | `completeness` medium |
| Same change pattern appears ≥ 2 places | bump confidence +1 tier |
| Change appears only once in a low-traffic file | cap confidence at `medium` |

## Examples

### Example 1 — `accuracy/high`

Diff:
```diff
-  The default timeout is 30 seconds.
+  The default timeout is 60 seconds.
```

Classification: `accuracy` / `high`.
Proposal: update corresponding rule in source agent/skill/command that documented 30s; add constraint if missing.

### Example 2 — `domain-knowledge/high`

Diff:
```diff
 class User {
+    // Sendable conformance required for cross-actor use
+    extension User: @unchecked Sendable {}
 }
```

Classification: `domain-knowledge` / `high`.
Proposal: add DO NOT constraint to developer agent about Sendable conformance.

### Example 3 — `tone/low`

Diff:
```diff
- This approach delivers the feature.
+ This strategy delivers the feature.
```

Classification: `tone` / `low`.
Proposal: deferred (single-word swap, no systemic signal).

### Example 4 — `structure/high`

Diff (in `.context/planning-0.md`):
```diff
+ ## Risk Assessment
+ - Risk 1 ...
+ - Risk 2 ...

  ## Scope
  ...
```

Classification: `structure` / `high`.
Proposal: add "Risk Assessment" as required section in `agents/product-manager.md` planning template.

### Example 5 — `style/medium`

Diff across 3 files:
```diff
- Tests Added:
+ ## Tests Added
```

Classification: `style` / `medium` (consistent across multiple files).
Proposal: add heading-hierarchy note to the producing agent.

## Cross References

- `SKILL.md § Step 3` — where classification happens in the pipeline
- `references/retrospective-template.md` — how categories render in `learnings.md`
- `references/target-mapping.md` — mapping categorized diffs to target files
- `commands/optimize-agent.md § Focus Areas` — similar category taxonomy (clarity/efficiency/consistency/tools/model)
