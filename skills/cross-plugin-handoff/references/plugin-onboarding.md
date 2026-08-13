# Adding or Replacing a Dev Plugin

How to register a new development plugin with the corpflow orchestrator, or swap one out for a
different implementation of the same platform. Registry of currently compatible plugins:
`skills/shared/compatible-plugins.md`.

## A. Compatibility contract

A plugin must satisfy all six items before it is added to the registry.

### 1. Command set

Expose the 15 core-parity commands under the plugin namespace (list and naming grammar in
`compatible-plugins.md § Core-parity command set`). A plugin whose domain genuinely does not fit
the set may ship a documented exception instead — `ai-engineer` is the precedent — but the
exception is recorded in the registry, not left implicit.

### 2. Agent roster

- One **entry router agent** named after the plugin (`<plugin>:<plugin>`), which routes internally
  to its own specialists. The orchestrator targets the router, not the leaves, when the specialist
  is ambiguous.
- Four **functional-role agents**: architect (AR consultation), security auditor (SR), test
  generator (QA), code fixer (DR remediation).
- Functional-role agents MUST carry a plugin-unique prefix (`sys-`, `fe-`, `be-`, `ai-` pattern).
  Bare names such as `test-generator` collide across plugins and break `error_file` derivation —
  see `compatible-plugins.md § Naming`.

### 3. Handoff schema

Agents taking over a worktask stage adopt the **full** frontmatter schema from
`skills/worktask/references/handoff-protocol.md § frontmatter-schema` (per-stage required fields,
`state.json` patching). Artifacts land in `.context/`; error narratives in
`.context/errors/<agent-basename>.md`.

### 4. Workflow-integration skill

Ship a `workflow-integration` skill documenting the stage contract from the plugin's side
(`apple-developer:workflow-integration` and `system-developer:workflow-integration` are the
reference implementations).

### 5. Evidence declaration

Declare the plugin's `requires_screenshots` default and its Build Evidence adapter, and add the
row to `compatible-plugins.md § Handoff defaults`. UI platforms default `true` with a capture
adapter; non-UI platforms default `false` with `cli_fallback_adapter` transcripts.

### 6. AR consultation model

The architect agent is consulted, not handed ownership: it writes
`.context/<platform>-architecture.md` and returns a summary of ≤500 tokens.
`corpflow:software-architector` retains the stage and merges the result.

## B. Touchpoint checklist

Every file below must be updated in the same change. Ordered so that later edits can reference
earlier ones.

### Registry and routing

| # | File | What changes |
|---|------|--------------|
| 1 | `skills/shared/compatible-plugins.md` | Registry row, functional-role row, handoff-defaults row |
| 2 | `skills/shared/platform-detection.md` | Marker rows in § Detection Rules; a per-platform specialization section; precedence notes if markers overlap an existing platform |
| 3 | `agents/developer.md` | `tools:` `Task(...)` grants; `--platform` enum (Priority Order, Detection Logging, Routing Audit); common-rows table; UI/non-UI defaults sentence; agent `description` |

### Stage agents and handoff protocol

| # | File | What changes |
|---|------|--------------|
| 4 | `agents/software-architector.md` | `tools:` architect grant; per-platform architect table |
| 5 | `agents/security-reviewer.md` | `tools:` auditor grant; platform→auditor table and checklist |
| 6 | `agents/qa-engineer.md` | `tools:` test-generator grant; platform→generator table |
| 7 | `skills/cross-plugin-handoff/SKILL.md` | Binding-schema agent list; `error_file` examples; build-evidence defaults |
| 8 | `skills/cross-plugin-handoff/references/plugin-protocols.md` | Per-plugin stage→agent handoff table |

### Commands, scripts and release

| # | File | What changes |
|---|------|--------------|
| 9 | `skills/worktask/scripts/publish-pl-issue.sh` | Plugin-prefix regex (both occurrences) **and** the leak-check greps — all must stay identical |
| 10 | `commands/pm-milestone.md` | Implementation / Test / Review agent-assignment tables; `--platform` flag docs |
| 11 | `commands/dev-code-review.md` | `--platform` enum |
| 12 | `skills/agent-coordination/SKILL.md` | Sub-Task Delegation model table; AR-collaboration note |
| 13 | `README.md` | Plugin mentions and worktask examples |
| 14 | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `MEMORY.md` | MINOR version bump + release notes |

Registration note: a plain `skills/shared/*.md` reference needs no `marketplace.json` entry — only
directory skills with their own `SKILL.md` are listed in `skills[]`.

## C. Replacing an existing plugin

1. Work through the same checklist, swapping the old plugin's rows, grants, and agent IDs for the
   replacement's in a single change — a half-swapped registry routes DV to one plugin and SR to
   another.
2. Verify nothing references the removed plugin:

   ```bash
   grep -rn "old-plugin:" --include="*.md" --include="*.sh" . | grep -v "\.claude/worktrees"
   ```

   Expected: no output.
3. Confirm the replacement's command set covers every command the old one was invoked with —
   check embedded commands in `commands/worktask.md` and stage templates.
4. Bump MINOR. A replacement is a behavior change for every worktask targeting that platform, so
   it belongs in the CHANGELOG even though no corpflow command changed.

Always exclude `.claude/worktrees/` from edit sweeps — it holds stale working copies of `agents/`
and `skills/` that are not the source of truth.
