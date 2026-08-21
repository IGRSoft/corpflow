# The corpflow Plugin Contract

**This file is the sole normative source for integrating a plugin with corpflow.** `SKILL.md`,
`plugin-protocols.md`, and the registry in `skills/shared/compatible-plugins.md` either implement it
or record who has satisfied it; where any of them disagrees with this file, this file wins and the
other is the bug.

## The seam is one file

An integrating plugin exposes **exactly one** corpflow-facing file: `CORPFLOW.md` at its repository
root. Copy `../templates/CORPFLOW.md`, fill in the plugin-specific rows, and commit it. That file is
the whole contract surface.

### Why one file

Nothing else in the plugin names corpflow — not the agents, commands, skills, or hooks. That is what
makes the plugin *independent*: adopting it without corpflow leaves one inert file, deletable with no
other edit, and a contract change then moves exactly one file per plugin (the diffuse coupling made
the v4.0.0 and v4.0.13 renames sweep 20–40 files per sibling; here they touch six in total).

Agents need no "if `.context/state.json` exists, load the integration guide" preamble, because
**corpflow injects the instruction at dispatch time** (§ What corpflow guarantees). An agent carrying
its own corpflow preamble is carrying a second seam, and the second seam is the one that rots.

## A. What the plugin must satisfy

Six items. All six before the plugin is added to `skills/shared/compatible-plugins.md`.

### 1. Command set

Expose the 15 core-parity commands under the plugin namespace (list and naming grammar in
`compatible-plugins.md § Core-parity command set`). A plugin whose domain genuinely does not fit may
ship a documented exception — `ai-engineer` is the precedent — recorded in the registry, not implicit.

### 2. Agent roster

- One **entry router agent** named after the plugin (`<plugin>:<plugin>`), routing internally to its
  own specialists. The orchestrator targets the router when the specialist is ambiguous.
- Four **functional-role agents**: architect (AR consultation), security auditor (SR), test generator
  (QA), code fixer (DR remediation).
- Functional-role agents MUST carry a plugin-unique prefix (`sys-`, `and-`, `fe-`, `be-`, `ai-`). Bare
  names such as `test-generator` collide across plugins and break `error_file` derivation — see
  `compatible-plugins.md § Naming`.

### 3. Handoff schema

Agents taking over a stage adopt the **full** frontmatter schema from
`skills/worktask/references/handoff-protocol.md § frontmatter-schema` (per-stage required fields,
`state.json` patching). Artifacts land in `.context/`; error narratives in
`.context/errors/<agent-basename>.md`.

### 4. A root `CORPFLOW.md`

The plugin's single corpflow-facing file, from `../templates/CORPFLOW.md`, carrying the stage→agent
table, the evidence declaration, and the artifact contract *from the plugin's side*. It replaces the
former `workflow-integration` skill, whose skill-shaped packaging invited every agent in the plugin
to reference it by name.

### 5. Evidence declaration

Declare the plugin's `requires_screenshots` default and its Build Evidence adapter in `CORPFLOW.md`,
and add the row to `compatible-plugins.md § Handoff defaults`. UI platforms default `true` with a
capture adapter; non-UI platforms default `false` with `cli_fallback_adapter` transcripts.

### 6. AR consultation model

The architect agent is consulted, not handed ownership: it writes
`.context/<platform>-architecture.md` and returns a summary of ≤500 tokens.
`corpflow:software-architector` retains the stage and merges the result.

## B. What corpflow guarantees in return

The contract is bidirectional. A plugin satisfying § A can rely on all of the following, and should
file a bug against corpflow rather than working around any of them.

### Guarantees

| Guarantee | Detail |
|---|---|
| **Dispatch-time injection** | Every corpflow agent delegating to a plugin agent injects `Read <plugin-root>/CORPFLOW.md and follow it` into the prompt — the plugin's agents never have to remember. |
| **`.context/` ownership** | corpflow creates and owns `.context/`. The plugin writes its stage artifact and its own `errors/<agent>.md`, nothing else. |
| **`state.json` is orchestrator-owned** | The plugin patches only via `state-patch.sh` when its path is supplied, never a hand-rolled `jq` merge. If the patch fails it proceeds anyway — the `SubagentStop` hook repairs from the artifact frontmatter. |

### Guarantees — recovery and independence

| Guarantee | Detail |
|---|---|
| **Frontmatter is the safety net** | Unconditional `handoff:` frontmatter is what makes the three-layer recovery (agent → orchestrator fallback → hook) work. Artifact *filenames* are a backward-compat convenience; frontmatter is the contract. |
| **Standalone operation** | No runtime dependency on corpflow is ever required. With no `.context/` present the plugin behaves exactly as it does with corpflow uninstalled. |

## Project-level routing override

A second file also carries the name `CORPFLOW.md`, with different semantics decided by
location: at a *sibling plugin's* root it is that plugin's stage contract (§ A.4); at the
*user project's* root it is project configuration, of which corpflow reads exactly one
heading — `## Routing`, a `| Alias | Target |` table whose rows win over the defaults in
`skills/shared/routing-matrix.md`. The heading `## Routing` is therefore **reserved**: a
plugin-side `CORPFLOW.md` must never use it (guard note in `../templates/CORPFLOW.md`).
Template and creation instructions: `../templates/PROJECT-CORPFLOW.md` and
`routing-matrix.md § Project override`. Resolution happens once at worktask init and
persists as `state.routing` (`skills/worktask/SKILL.md § Validation check 11`).

An override replaces a platform's plugin wholesale — the replacement must still satisfy
§ A; corpflow injects the same dispatch-time instruction and expects the same handoff
schema from it.

## C. corpflow-side touchpoints when adding or swapping a plugin

Every file below changes in the same commit. Ordered so later edits can reference earlier ones.

### Registry and routing

| # | File | What changes |
|---|------|--------------|
| 1 | `skills/shared/routing-matrix.md` | Entry-alias row + four functional-role alias rows (the only copy of the target ids) |
| 2 | `skills/shared/compatible-plugins.md` | Registry row (entry alias), command-set row, handoff-defaults row |
| 3 | `skills/shared/platform-detection.md` | Marker rows in § Detection Rules; a per-platform specialization section; precedence notes if markers overlap an existing platform |
| 4 | `agents/developer.md` | `--platform` enum (Priority Order, Detection Logging, Routing Audit); common-rows table; UI/non-UI defaults sentence; agent `description`. No `tools:` edit — stage agents carry a bare `Task` grant |

### Stage agents and handoff protocol

Rows 5–7 are mandated-copy edits validated by `tests/shell/skills/routing-matrix.bats` —
the test fails until each inline table matches the matrix.

| # | File | What changes |
|---|------|--------------|
| 5 | `agents/software-architector.md` | Per-platform architect table row |
| 6 | `agents/security-reviewer.md` | Platform→auditor subsection and checklist |
| 7 | `agents/qa-engineer.md` | Platform→generator list entry |
| 8 | `skills/cross-plugin-handoff/references/plugin-protocols.md` | Per-plugin stage→agent handoff table |
| 9 | `skills/worktask/scripts/publish-pl-issue.sh` | Plugin-prefix regex (both occurrences) **and** the leak-check greps — all four must stay byte-identical to each other and to the list in `compatible-plugins.md` |

### Commands, scripts and release

| # | File | What changes |
|---|------|--------------|
| 10 | `commands/pm-milestone.md` | Implementation / Test / Review agent-assignment tables; `--platform` flag docs |
| 11 | `commands/dev-code-review.md` | `--platform` enum |
| 12 | `skills/agent-coordination/SKILL.md` | Sub-Task Delegation model table; AR-collaboration note |
| 13 | `README.md` | Plugin mentions and worktask examples |
| 14 | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `MEMORY.md` | MINOR version bump + release notes. New entries always land in `CHANGELOG.md`; `CHANGELOG-3.x.md` is a frozen archive and is never appended to |

A plain `skills/shared/*.md` reference needs no `marketplace.json` entry — only directory skills with
their own `SKILL.md` are listed in `skills[]`.

### Packaging and validation

- `claude plugin validate` also checks a bare `.claude/skills` directory and reports `SKILL.md` files
  whose frontmatter fails to parse (CC 2.1.233). Run it before publishing — malformed frontmatter is
  otherwise a silent no-load.
- A plugin may declare `"."` as a `skills` path, meaning the plugin root itself (CC 2.1.221).
- The `archive` source installs from a zip over HTTPS with no git or npm and accepts an optional
  SHA-256 pin (CC 2.1.224). Pin the hash for any non-first-party marketplace entry.

## D. Replacing an existing plugin

1. Work through § C in one change, swapping the old plugin's rows, grants, and agent IDs for the
   replacement's. A half-swapped registry routes DV to one plugin and SR to another.
2. Verify nothing references the removed plugin:

   ```bash
   grep -rn "old-plugin:" --include="*.md" --include="*.sh" . | grep -v "\.claude/worktrees"
   ```

   Expected: no output.
3. Confirm the replacement's command set covers every command the old one was invoked with — including
   embedded commands in `commands/worktask.md` and stage templates.
4. Bump MINOR: a replacement changes behavior for every worktask on that platform, so it belongs in
   the CHANGELOG even though no corpflow command changed.

Always exclude `.claude/worktrees/` from edit sweeps — stale copies of `agents/` and `skills/` live
there and are not the source of truth.
