<!--
TEMPLATE. Copy to the root of a USER PROJECT as CORPFLOW.md to override corpflow's
default plugin routing. corpflow reads exactly one heading from this file — `## Routing`
— everything else is yours (or delete everything else). Not to be confused with the
plugin-side CORPFLOW.md stage contract (templates/CORPFLOW.md), which sits at a sibling
plugin's root and must NOT contain a `## Routing` heading.

How overrides apply: rows here win over skills/shared/routing-matrix.md § Matrix, alias
by alias, resolved ONCE at worktask init into `state.routing` — edits mid-worktask take
effect on the next worktask. Overriding an entry alias does not implicitly override that
platform's role aliases; swapping a platform's plugin normally means overriding all five
(entry + architect + security-auditor + test-generator + code-fixer). A target that is
not installed falls back per routing-matrix.md § Resolution step 5 with a
`plugin_unavailable` audit row.
-->

# corpflow Project Configuration

## Routing

Keep only the rows you override; delete the rest. Targets are fully-qualified
`plugin:agent` ids. The full alias list and every default target live in corpflow
`skills/shared/routing-matrix.md § Matrix` — deliberately not copied here, so this file
never drifts from the matrix. Aliases follow `corpflow:<plugin-role>` for entry points
(`corpflow:apple-developer`, `corpflow:ai-engineer`, …) and `corpflow:<platform>-<role>`
for functional roles (`corpflow:web-code-fixer`, `corpflow:systems-security-auditor`, …).

| Alias | Target |
|-------|--------|
| `corpflow:apple-developer` | `my-org-apple:apple-developer` |
| `corpflow:apple-code-fixer` | `my-org-apple:code-fixer` |

### Contract

An override target must satisfy the plugin contract
(`corpflow skills/cross-plugin-handoff/references/plugin-contract.md § A`): entry router,
functional-role agents, handoff frontmatter schema, and — ideally — its own root
CORPFLOW.md stage contract.
