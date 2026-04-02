---
name: swift-arch-select
description: Select best Swift architecture pattern based on project constraints and team context
argument-hint: '<feature description> [--team-size N] [--complexity low|medium|high] [--ui swiftui|uikit|mixed]'
model: sonnet
allowed-tools: Read, Glob, Grep
---

# Swift Architecture Selection Command

Select the best Swift architecture pattern for a project or feature based on constraints.

## Usage

```
/swift-arch-select <feature description>
/swift-arch-select --ui swiftui --complexity high
/swift-arch-select --team-size 3 --ui mixed
```

## Options

- `--team-size <N>` — Number of developers (affects boilerplate tolerance)
- `--complexity <low|medium|high>` — State complexity level
- `--ui <swiftui|uikit|mixed>` — UI stack
- `--pattern <name>` — Validate a specific pattern instead of selecting

## Process

1. **Load** the `swift-architecture` skill
2. **Gather constraints** from arguments and codebase analysis:
   - UI stack (SwiftUI, UIKit, or mixed)
   - State complexity (simple screen state vs complex state machine)
   - Effect orchestration needs (manual, structured, built-in)
   - Team familiarity and dependency tolerance
   - Existing codebase conventions
3. **Run selection guide** — Quick Decision Flow from skill
4. **Validate** — If `--pattern` specified, run fit check against constraints

## Output Format

```markdown
# Architecture Recommendation

## Recommendation: {Pattern Name}
**Fit**: {fit | mismatch}
**Reasons**: {1-2 concise reasons grounded in constraints}
**Reference**: `skills/swift-architecture/references/{pattern}.md`

## Constraints Analyzed
| Factor | Value |
|--------|-------|
| UI Stack | {SwiftUI / UIKit / mixed} |
| State Complexity | {Low / Medium / High} |
| Team Size | {N} |
| Existing Patterns | {detected or none} |

## Recommended Structure
{Directory layout from pattern reference}

## Hybrid Considerations
{If applicable — e.g., "Pair with Coordinator for navigation decoupling"}

## Alternative
{If mismatch or close call — name alternative pattern and trade-off}

## Draft ADR
{ADR template pre-filled with recommendation, context, and consequences}
```

## Integration

- **AR stage** — Architect uses this to select pattern for new features
- **PL stage** — Product manager references for complexity assessment
- **Pre-project** — Team alignment on architecture before development

## Related

- [swift-architecture skill](../skills/swift-architecture/SKILL.md) — Pattern references
- [arch-decision](./arch-decision.md) — Create full ADRs
- [swift-arch-review](./swift-arch-review.md) — Review code against chosen pattern
