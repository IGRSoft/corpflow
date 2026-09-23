# Routing Matrix (alias → target)

Canonical for **alias-level** routing: which installed plugin serves each platform entry
point and functional role. Aliases are virtual `corpflow:*` identifiers — none collides with
a real corpflow agent `name:` (enforced by `tests/shell/skills/routing-matrix.bats`).
Consumers resolve per § Resolution; a project may override any row per § Project override.

Marker→platform detection and per-specialist tables: `skills/shared/platform-detection.md`.
Plugin-level metadata (version floors, command sets, evidence defaults):
`skills/shared/compatible-plugins.md`. Never keep a second unvalidated copy of this map
elsewhere — stage-agent inline tables are mandated copies validated by the bats test.

## Matrix

### Entry aliases (DV dispatch)

| Alias | Default target | Platform |
|-------|----------------|----------|
| `corpflow:apple-developer` | `apple-developer:apple-developer` | apple |
| `corpflow:system-developer` | `system-developer:system-developer` | systems |
| `corpflow:android-developer` | `android-developer:android-developer` | android |
| `corpflow:frontend-developer` | `frontend-developer:frontend-developer` | web |
| `corpflow:backend-developer` | `backend-developer:backend-developer` | backend |
| `corpflow:ai-engineer` | `ai-engineer:ai-engineer` | ai |

### Functional-role aliases (AR / SR / QA / DR)

Alias shape: `corpflow:<platform>-<role>`, role ∈ architect | security-auditor |
test-generator | code-fixer. One subsection per platform.

#### apple / systems roles

| Alias | Default target | Role | Platform |
|-------|----------------|------|----------|
| `corpflow:apple-architect` | `apple-developer:apple-architector` | architect | apple |
| `corpflow:apple-security-auditor` | `apple-developer:security-auditor` | security-auditor | apple |
| `corpflow:apple-test-generator` | `apple-developer:test-generator` | test-generator | apple |
| `corpflow:apple-code-fixer` | `apple-developer:code-fixer` | code-fixer | apple |
| `corpflow:systems-architect` | `system-developer:system-architector` | architect | systems |
| `corpflow:systems-security-auditor` | `system-developer:sys-security-auditor` | security-auditor | systems |
| `corpflow:systems-test-generator` | `system-developer:sys-test-generator` | test-generator | systems |
| `corpflow:systems-code-fixer` | `system-developer:sys-code-fixer` | code-fixer | systems |

#### android / web roles

| Alias | Default target | Role | Platform |
|-------|----------------|------|----------|
| `corpflow:android-architect` | `android-developer:kotlin-architector` | architect | android |
| `corpflow:android-security-auditor` | `android-developer:and-security-auditor` | security-auditor | android |
| `corpflow:android-test-generator` | `android-developer:and-test-generator` | test-generator | android |
| `corpflow:android-code-fixer` | `android-developer:and-code-fixer` | code-fixer | android |
| `corpflow:web-architect` | `frontend-developer:frontend-architector` | architect | web |
| `corpflow:web-security-auditor` | `frontend-developer:fe-security-auditor` | security-auditor | web |
| `corpflow:web-test-generator` | `frontend-developer:fe-test-generator` | test-generator | web |
| `corpflow:web-code-fixer` | `frontend-developer:fe-code-fixer` | code-fixer | web |

#### backend / ai roles

| Alias | Default target | Role | Platform |
|-------|----------------|------|----------|
| `corpflow:backend-architect` | `backend-developer:backend-architector` | architect | backend |
| `corpflow:backend-security-auditor` | `backend-developer:be-security-auditor` | security-auditor | backend |
| `corpflow:backend-test-generator` | `backend-developer:be-test-generator` | test-generator | backend |
| `corpflow:backend-code-fixer` | `backend-developer:be-code-fixer` | code-fixer | backend |
| `corpflow:ai-architect` | `ai-engineer:ai-architector` | architect | ai |
| `corpflow:ai-security-auditor` | `ai-engineer:ai-security-auditor` | security-auditor | ai |
| `corpflow:ai-test-generator` | `ai-engineer:ai-test-generator` | test-generator | ai |
| `corpflow:ai-code-fixer` | `ai-engineer:ai-code-fixer` | code-fixer | ai |

### Release-engineer aliases (publishing — apple and android only)

These targets are **RE-stage consultation**: corpflow's own `agents/release-engineer.md` retains the
stage and every `state.json` write, exactly as AR works. Only platforms with a store have a row —
a web, backend, systems, or ai alias would promise a target that does not exist.

| Alias | Default target | Role | Platform |
|-------|----------------|------|----------|
| `corpflow:apple-release-engineer` | `apple-developer:apple-release-engineer` | release-engineer | apple |
| `corpflow:android-release-engineer` | `android-developer:and-release-engineer` | release-engineer | android |

Their own section, not rows in § Functional-role aliases, because that section's test loops all six
platforms × four roles and a fifth role there would demand a row per platform. There is also no bare
`corpflow:release-engineer` alias — corpflow ships an agent with that exact `name:`, and the
no-collision test in `routing-matrix.bats` rejects the clash.

### UI-verifier aliases (native UI legs — apple and android only)

These targets run QA's **native UI legs**: a UI test bundle, or a build driven live and captured on
a simulator or emulator. corpflow's `agents/qa-engineer.md` keeps the stage, the leg verdicts, and
every `state.json` write; the delegate returns logs and images (`§ Native UI legs` there).

| Alias | Default target | Platform |
|-------|----------------|----------|
| `corpflow:apple-ui-verifier` | `apple-developer:ios-developer` | apple |
| `corpflow:android-ui-verifier` | `android-developer:android-developer` | android |

#### The non-iOS Apple pick

Only Apple and Android have a native runtime to drive; a browser leg is not native, so there is no
systems, web, backend, or ai row.

The apple default names the iOS agent. When no override applies and the target is macOS, tvOS,
watchOS, or visionOS, QA dispatches the matching `apple-developer:<os>-developer` instead, the
same pick `skills/dv-screenshot-capture/SKILL.md` makes.

For these aliases § Resolution step 5 stops at the resolved target: an unreachable target,
override included, becomes a `not_delegated` leg, never a retry of the default target or a
direct Bash run.

### Support-plugin aliases (route only when installed)

| Alias | Default target | Role |
|-------|----------------|------|
| `corpflow:debugging-toolkit` | `debugging-toolkit:debugging-toolkit-debugger` | IR/DV debugging |
| `corpflow:security-scanning` | `security-scanning:security-scanning-security-auditor` | SR scanning |

The `claude-code-workflows` family doubles its slug in invocation ids
(`debugging-toolkit:debugging-toolkit-debugger`); exception:
`security-scanning:threat-modeling-expert`.

## Resolution

1. `state.routing` present in `.context/state.json` → use it (resolved once at worktask
   init; see `skills/worktask/SKILL.md § Routing resolution`).
2. Else read `CORPFLOW.md § Routing` at the **user project root**; its rows win over this
   matrix, alias by alias.
3. Else (or for aliases not overridden) use the Default target column above.
4. Dispatch injection is unchanged: if the target plugin ships a root `CORPFLOW.md`
   contract, open the prompt with the standard `Read CORPFLOW.md at the root of your
   plugin and follow it` line; otherwise point the target at
   `skills/worktask/references/handoff-protocol.md § frontmatter-schema` inline.
5. Target uninstalled or unknown → the `plugin_unavailable` degrade path
   (`agents/developer.md § Plugin unavailable`) with `alias` and `override_target` in the
   audit metadata: fall back override → default target → direct scoped-Bash build.

## Project override

`CORPFLOW.md` at the **user project root**, heading `## Routing`, same two-column table
(`| Alias | Target |`). Rows are explicit per alias — overriding an entry alias does not
implicitly override that platform's role aliases; swapping a platform's plugin normally
means overriding all five. Partial override (entry overridden, roles not) is legal but
audited (`routing_override_partial`).

### Creating the override file

Copy `skills/cross-plugin-handoff/templates/PROJECT-CORPFLOW.md` to the project root as
`CORPFLOW.md`, keep only the rows you override, then start a new worktask (or re-run init)
so `state.routing` re-resolves. Overrides never take effect mid-worktask.

## Two files named CORPFLOW.md

Location decides semantics: at a *sibling plugin's* root it is that plugin's stage
contract (`skills/cross-plugin-handoff/references/plugin-contract.md § A.4`); at the
*user project's* root it is project configuration, of which corpflow reads only
`## Routing`. A project that is itself an integrating plugin holds both in one file — the
headings are disjoint, and `## Routing` is reserved for the override.

## Grants

Stage-dispatching agents (`developer`, `software-architector`, `security-reviewer`,
`qa-engineer`) carry a bare `Task` grant so any override target dispatches. This matrix, not the
frontmatter, is the canonical record of intended targets; the guardrail for the wider spawn surface
is the mandatory routing audit row on every delegation (`agents/developer.md § Routing Audit`).
