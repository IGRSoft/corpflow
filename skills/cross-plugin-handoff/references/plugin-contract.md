# The corpflow Plugin Contract

**This file is the sole normative source for integrating a plugin with corpflow.** Everything else
— `SKILL.md`, `plugin-protocols.md`, the registry in `skills/shared/compatible-plugins.md` — either
implements this contract or records who has satisfied it. Where any of them disagrees with this
file, this file wins and the other is the bug.

## The seam is one file

An integrating plugin exposes **exactly one** corpflow-facing file: `CORPFLOW.md` at its repository
root. Copy `../templates/CORPFLOW.md`, fill in the plugin-specific rows, and commit it. That file is
the whole contract surface.

Nothing else in the plugin names corpflow. Not the agents, not the commands, not the skills, not the
hooks. This is not a style preference — it is what makes the plugin *independent*:

- A user adopting the plugin without corpflow gets a plugin with one inert file in it, and can
  delete that file with no other edit.
- A user adopting corpflow later adds one file back.
- When corpflow changes a contract, exactly one file per plugin moves. The v4.0.0 and v4.0.13
  renames each had to sweep 20–40 files per sibling precisely because the coupling was diffuse;
  under this contract they would have touched six files total.

Agents do not need a "if `.context/state.json` exists, load the integration guide" preamble, because
**corpflow injects the instruction at dispatch time** (see § What corpflow guarantees). An agent that
carries its own corpflow preamble is carrying a second seam, and the second seam is the one that
rots.

## A. What the plugin must satisfy

Six items. All six before the plugin is added to `skills/shared/compatible-plugins.md`.

### 1. Command set

Expose the 15 core-parity commands under the plugin namespace (list and naming grammar in
`compatible-plugins.md § Core-parity command set`). A plugin whose domain genuinely does not fit the
set may ship a documented exception instead — `ai-engineer` is the precedent — but the exception is
recorded in the registry, not left implicit.

### 2. Agent roster

- One **entry router agent** named after the plugin (`<plugin>:<plugin>`), routing internally to its
  own specialists. The orchestrator targets the router, not the leaves, when the specialist is
  ambiguous.
- Four **functional-role agents**: architect (AR consultation), security auditor (SR), test generator
  (QA), code fixer (DR remediation).
- Functional-role agents MUST carry a plugin-unique prefix (`sys-`, `and-`, `fe-`, `be-`, `ai-`).
  Bare names such as `test-generator` collide across plugins and break `error_file` derivation — see
  `compatible-plugins.md § Naming`.

### 3. Handoff schema

Agents taking over a worktask stage adopt the **full** frontmatter schema from
`skills/worktask/references/handoff-protocol.md § frontmatter-schema` (per-stage required fields,
`state.json` patching). Artifacts land in `.context/`; error narratives in
`.context/errors/<agent-basename>.md`.

### 4. A root `CORPFLOW.md`

The plugin's single corpflow-facing file, from `../templates/CORPFLOW.md`. It carries the stage→agent
table, the evidence declaration, and the artifact contract *from the plugin's side*. This replaces the
former requirement to ship a `workflow-integration` skill, which put the same content behind a skill
name that only corpflow ever loaded — and which, being a skill, invited every agent in the plugin to
reference it by name.

### 5. Evidence declaration

Declare the plugin's `requires_screenshots` default and its Build Evidence adapter in `CORPFLOW.md`,
and add the row to `compatible-plugins.md § Handoff defaults`. UI platforms default `true` with a
capture adapter; non-UI platforms default `false` with `cli_fallback_adapter` transcripts.

### 6. AR consultation model

The architect agent is consulted, not handed ownership: it writes
`.context/<platform>-architecture.md` and returns a summary of ≤500 tokens.
`corpflow:software-architector` retains the stage and merges the result.

## B. What corpflow guarantees in return

The contract is bidirectional. A plugin that satisfies § A can rely on all of the following, and
should file a bug against corpflow rather than working around any of them.

| Guarantee | Detail |
|---|---|
| **Dispatch-time injection** | Every corpflow agent that delegates to a plugin agent injects `Read <plugin-root>/CORPFLOW.md and follow it` into the delegation prompt. The plugin never has to make its agents remember. |
| **`.context/` ownership** | corpflow creates and owns `.context/`. The plugin writes its stage artifact and its own `errors/<agent>.md`, and nothing else. |
| **`state.json` is orchestrator-owned** | The plugin patches only via `state-patch.sh` when its path is supplied, and never hand-rolls a `jq` merge. If the patch fails the plugin proceeds — corpflow's `SubagentStop` hook repairs from the artifact frontmatter. |
| **Frontmatter is the safety net** | Emitting `handoff:` frontmatter is unconditional and is what makes the three-layer recovery (agent → orchestrator fallback → hook) work. Artifact *filenames* are a backward-compat convenience; frontmatter is the contract. |
| **Standalone operation** | corpflow never requires the plugin to depend on it at runtime. With no `.context/` present, the plugin behaves exactly as it does with corpflow uninstalled. |

## C. corpflow-side touchpoints when adding or swapping a plugin

Every file below changes in the same commit. Ordered so later edits can reference earlier ones.

| # | File | What changes |
|---|------|--------------|
| 1 | `skills/shared/compatible-plugins.md` | Registry row, functional-role row, handoff-defaults row |
| 2 | `skills/shared/platform-detection.md` | Marker rows in § Detection Rules; a per-platform specialization section; precedence notes if markers overlap an existing platform |
| 3 | `agents/developer.md` | `tools:` `Task(...)` grants; `--platform` enum (Priority Order, Detection Logging, Routing Audit); common-rows table; UI/non-UI defaults sentence; agent `description` |
| 4 | `agents/software-architector.md` | `tools:` architect grant; per-platform architect table |
| 5 | `agents/security-reviewer.md` | `tools:` auditor grant; platform→auditor table and checklist |
| 6 | `agents/qa-engineer.md` | `tools:` test-generator grant; platform→generator table |
| 7 | `skills/cross-plugin-handoff/references/plugin-protocols.md` | Per-plugin stage→agent handoff table |
| 8 | `skills/worktask/scripts/publish-pl-issue.sh` | Plugin-prefix regex (both occurrences) **and** the leak-check greps — all four must stay byte-identical to each other and to the list in `compatible-plugins.md` |
| 9 | `commands/pm-milestone.md` | Implementation / Test / Review agent-assignment tables; `--platform` flag docs |
| 10 | `commands/dev-code-review.md` | `--platform` enum |
| 11 | `skills/agent-coordination/SKILL.md` | Sub-Task Delegation model table; AR-collaboration note |
| 12 | `README.md` | Plugin mentions and worktask examples |
| 13 | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `MEMORY.md` | MINOR version bump + release notes |

A plain `skills/shared/*.md` reference needs no `marketplace.json` entry — only directory skills with
their own `SKILL.md` are listed in `skills[]`.

## D. Replacing an existing plugin

1. Work through § C swapping the old plugin's rows, grants, and agent IDs for the replacement's in a
   single change. A half-swapped registry routes DV to one plugin and SR to another.
2. Verify nothing references the removed plugin:

   ```bash
   grep -rn "old-plugin:" --include="*.md" --include="*.sh" . | grep -v "\.claude/worktrees"
   ```

   Expected: no output.
3. Confirm the replacement's command set covers every command the old one was invoked with — check
   embedded commands in `commands/worktask.md` and stage templates.
4. Bump MINOR. A replacement changes behavior for every worktask targeting that platform, so it
   belongs in the CHANGELOG even though no corpflow command changed.

Always exclude `.claude/worktrees/` from edit sweeps — it holds stale working copies of `agents/` and
`skills/` that are not the source of truth.
