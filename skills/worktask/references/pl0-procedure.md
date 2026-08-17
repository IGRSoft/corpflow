# PL0 Procedure — the complete planning-stage worktask integration

Read this file **first, before any other action**, when `corpflow:product-manager` is dispatched as
the PL stage agent (PL0). It is the whole planning procedure and the only place it exists — the
agent file carries product-management identity and a pointer here, nothing that substitutes for
this document. Non-PL0 invocations (`/estimate`, `/pm-requirements`, `/pm-roadmap`,
`/pm-prioritize`, `/pm-milestone`) never need it.

Every `skills/…` and `commands/…` path below is relative to the **corpflow plugin root**, not to
the worktask repo — resolve it per `agents/product-manager.md § Plugin paths`. `<plan_file>` is
defined under § Notation.

## Test Strategy Definition

When planning features, define the test strategy in the plan file. Include: test scope (unit/integration/E2E), framework selection, acceptance criteria, existing tests to update, new test files needed, and effort estimate by stage.

### Key Rules

1. **DV writes unit tests** as part of implementation; QA validates integration/E2E
2. **Framework selection is platform-derived**: adopt whatever the repo's existing test targets already use; with no existing tests, take the default of the detected platform's test generator (`skills/shared/compatible-plugins.md § Test generator and code fixer`). Name the chosen framework in the plan. Never carry one platform's framework into another — Apple's Swift Testing (unit) / XCTest (UI) split is documented in `skills/shared/testing-strategy.md` and applies to Apple only.
3. **Coverage expectations**: New features require 3+ unit test scenarios; bug fixes require regression tests; refactors must identify all affected existing tests

### Required Metadata: Test Selection Gate

Every plan file (`planning-N.md`) MUST declare four fields in its frontmatter `metadata` block. These drive DV (step D2), QA (step Q1), the Visual Comparison subsection, and the screenshot capture gate.

```yaml
metadata:
  test_mode: scoped              # build-only | scoped | full
  always_required_tests: []      # explicit override list of test IDs
  ui_visual_check: false         # gate for QA's visual/design comparison
  requires_screenshots: false    # REQUIRED — drives DV screenshot capture + gate
```

#### `test_mode` — selection breadth

| Mode | When to choose | Effect |
|------|----------------|--------|
| `build-only` | Repo has marker coverage (`@test-required`/`@depends-on:` widely used) AND change is refactor/dep-update/doc-only. **Opt-in** — do not pick if uncertain. | DV builds + runs smoke set (`@test-required` + `always_required_tests`). QA runs Selected Tests only. |
| `scoped` (effective default if omitted) | Bug fixes, small features, anything touching a known set of modules. Default for untagged or partially-tagged repos. | DV + QA run Selected Tests + tests in any module the diff touches. |
| `full` | Release candidate, multi-module feature, post-major-dep-upgrade, stakeholder-requested full regression. | DV runs Selected Tests; QA runs the entire project test suite. |

##### Default `test_mode` by complexity score

The complexity-score → default `test_mode` table lives in `skills/estimation-methodology/SKILL.md § PL0 Stage-Set & Test-Mode by Complexity Score`. When uncertain between `scoped` and `full`, choose `scoped` — the auto-promotion safety net (DV warns, QA promotes on an empty Selected list) catches under-selection.

##### Comment/doc-only diffs

When the planned diff is entirely comments, prose files, or non-executable strings, `build-only` is **selected, not merely available** — the marker-coverage precondition in the table above does not apply, since nothing executable changed. Record the reason in `§ Test Strategy`. Canonical rule (including the "no QA re-run for a post-QA doc-only change" consequence): `skills/shared/testing-strategy.md § Comment/doc-only diffs`.

#### `always_required_tests` — explicit override

Test IDs that must always run (every mode, every run). The ID grammar is per-platform and canonical in `skills/shared/test-selection-syntax.md § Platform handlers`: Apple uses `<TargetName>/<SuiteName>` (suite-terminal — per-function IDs are rejected by the runner), Android the JUnit `<package>.<ClassName>#<methodName>` form, web a file-path + test-name pattern. Platforms whose selective-test handler is still a stub auto-promote the run to module-scope at DV (never `full` — QA remains the sole full-suite authority per the Constraints pointer above), so entries are recorded but not used for DV's selection. Use sparingly for cross-cutting smoke tests not annotated with `@test-required` in source.

#### `ui_visual_check` — Visual QA gate

Independent of `test_mode`. Set `true` when at least one applies:
- New views, screens, or UI components are introduced in the platform's view layer (SwiftUI/UIKit, Compose, React/Vue/Svelte/Angular components, …)
- Visual design artifacts exist in `.context/designs/` (Figma registry, mockups) that need verification
- Layout, styling, or animation changes require screen capture to validate
- Stakeholder explicitly requests UI verification

When `true` AND `.context/designs/` has artifacts, QA performs Design Comparison during Q1.

#### `requires_screenshots` — DV screenshot capture gate (REQUIRED)

Drives `dv-screenshot-capture` and its SubagentStop completion gate (`hooks/dv-screenshot-gate.sh`). When `true`, DV MUST produce `.context/images/<worktask_id>/screenshots.md`; the captures are later embedded in BOTH the PR body and the GitHub issue (binding user directive — UI changes always surface screenshots on both). When `false`, DV writes a skip-rationale manifest and the gate passes.

**PL0 is the sole WRITER of this flag.** Do not rely on the downstream `?? true` defaults — those are defense-in-depth for ad-hoc runs only. Stamp it deterministically per the steps below.

##### Detector run (step 1)

1. Run the detector against the draft plan:
   ```bash
   skills/worktask/scripts/detect-ui-change.sh <draft-plan> --platform <platform>
   ```
   It emits `{requires_screenshots, signals, rationale}`. Signals (ANY true ⇒ true): **S1** `ui_visual_check: true`; **S2** `.context/designs/` has `figma-registry.md`/`*.png`; **S3** `## scope`/`## requirements` matches the UI keyword set; **S4** platform ∈ {apple, web, android} AND scope names UI path classes (`Views/`, `Screens/`, `*.storyboard`, `*.tsx`, …). Exits 0 always; any error ⇒ `true` (`fail_safe_default`).

##### Stamp, override, propagate (steps 2–3)

2. Stamp the returned value on the plan frontmatter `metadata.requires_screenshots` and record the `rationale` line in the plan (this satisfies AC-2's "recorded rationale" when false).
3. **Override asymmetry**: you may force `true` at any time without justification. Forcing `false` when the detector said `true` requires an explicit user directive quoted in the plan rationale — the detector never silently downgrades.

Propagate the flag on all three writer surfaces (see Downstream propagation): plan frontmatter, DV+QA task metadata, and `state.json .metadata.requires_screenshots` (the channel the gate reads — SubagentStop stdin carries no task metadata in live runs).

Plans declare `test_mode` + `ui_visual_check`; the marker grammar DV parses is canonical in `skills/shared/test-selection-syntax.md`.

4. **Test effort estimate is required** (not optional) — broken down by type, hours, and stage (DV/QA)

## Worktask Integration

**Stage**: PL (Planning, 1/11) — see `skills/shared/worktask-stage-context.md` for pipeline context. The product-manager handles:

### Plan File & Run Index Naming

Each PL invocation produces a numbered plan file in `.context/` and stamps a shared run index on every downstream task:

- **First plan**: `.context/planning-0.md`
- **Subsequent plans**: `.context/planning-N.md` where N = max existing index + 1

Both rows describe a **new run**. A plan-gate revision is not a new run and allocates nothing — see § Revision of the run in flight below.

#### Algorithm (run as PL0 step 1)

1. Glob `.context/planning-*.md`. Extract the integer suffix from each match.
2. If matches exist, set `N = max(existing) + 1`. Otherwise `N = 0`.
3. Write `.context/planning-${N}.md`. Do **not** overwrite `planning-0.md`, ..., `planning-(N-1).md` — they remain as historical plans.

##### Write-target authority

> **PL0 is the authoritative writer.** Any `plan_file` / `run_index` already present in a pre-seeded `state.json` (the orchestrator's Phase-1 step 3a seed) is **provisional** — PL0 MUST recompute `N` via the step-1 glob and treat that result as authoritative, regardless of the seeded value. **Never write to a `planning-${N}.md` that already exists on disk**; if the computed target exists, the glob was stale — recompute `N`. The reader resolution order in the note below (`metadata.plan_file` first) applies to *downstream stages* consuming a finalized plan; it does **not** govern PL0's own write-target selection.

##### Revision of the run in flight (NOT a new index)

> **BINDING.** When the dispatch prompt carries `plan_revision: true` (a plan-gate rejection —
> `commands/worktask.md § Plan-revision re-dispatch`), this turn revises the run in flight, not a
> new run. **Skip algorithm steps 1–3**: `run_index` and `plan_file` are frozen, so edit the
> current `.context/<plan_file>` in place. **Skip the Step-4 reset** below — patch `facts.*`
> additively instead, so `facts.decisions[]` (the answers just given at the gate) and every other
> fact gathered this run survive. **Do not create stage tasks** — patch the existing chain
> in place when the revision changes subjects, ACs, or the stage set. The never-overwrite rule
> above protects the historical plans of **finished** runs; a plan under active revision is not
> history, and rewriting it is the point.

#### Step 4 — state.json reset

4. **state.json reset** (new run in existing `.context/`; **skipped on a `plan_revision` turn** —
   see above): atomically rewrite `.context/state.json` with `"run_index": N`, `"tasks": {"PL0": {"status": "in_progress"}}`, `metadata.requires_screenshots` set to the detector's value (the channel `hooks/dv-screenshot-gate.sh` and `attach-visual-evidence.sh` read), `metadata.base_ref` set to the detected integration branch (see **Integration-branch detection** below), and empty `facts.*` (preserves `version`, `worktask_id`, `platform`). Use the atomic-write pattern from `handoff-protocol.md#atomic-write`.

##### Step 4 — plan_file shape

Write the **path** shape into `state.json.plan_file` — `".context/planning-${N}.md"`, not the bare `<plan_file>` notation value. `<plan_file>` is a **basename** everywhere in this document; writing it here unprefixed is exactly how the prefix goes missing and the issue-publish helper loses the plan. See the `plan_file` shape boundary in `handoff-protocol.md`.

#### Downstream propagation

When PL seeds downstream stage tasks via `state-patch.sh --task-create`, stamp **all** of the following on each (table continues across the two sub-sections below — every row is mandatory):

| Key | Value | Purpose |
|---|---|---|
| `metadata.plan_file` | `"planning-${N}.md"` | Pin active plan — **bare basename**, deliberately a different shape from `state.json.plan_file` (a workspace-relative path). See the `plan_file` shape boundary in `handoff-protocol.md § state.json schema`. |
| `metadata.run_index` | `N` (integer) | Resolve `<basename>-${N}.md` artifacts |
| `metadata.isolation` | `"worktree"` | File-writing stages (DV; megatask per-issue AR/DR/QA) always run in an isolated worktree (consumed by developer § D0.0, technical-lead DR check, workspace-modes.md). |

##### Propagation fields — gates

| Key | Value | Purpose |
|---|---|---|
| `metadata.fn_gate` | `"checkpoint"` (default) | Pre-FN human checkpoint; orchestrator STOPs before FN for approval. `"bypass"` only for `--auto=[finalization]`/`--emergency` (or `/megatask` per-issue); `--auto=[plan]` never bypasses FN. Stamp on PL0; read at the mid-loop FN gate. |
| `metadata.decision_gate` | `"user"` (default) | WHO answers PL0's `open_questions[]`. `"auto"` only for `--auto=[decision]` (or `/megatask` per-issue): orchestrator resolves them via the Fable-model decision pass (`commands/worktask.md § Step A.4`) instead of the plan-gate round-trip. Bypasses no gate. Stamp on PL0; consumed by § Plan-Gate Open-Question Batching and Step A.4. |

##### Propagation fields — exploration & screenshots

| Key | Value | Purpose |
|---|---|---|
| `metadata.skip_exploration` | `true` if `.context/exploration.md` exists | Suppress redundant Glob/Grep in AR/TL/DV |
| `metadata.exploration_anchors` | `["exploration.md#facts", "exploration.md#refs", "planning-${N}.md#requirements"]` (when `skip_exploration: true`) | Authoritative pre-explored set |
| `metadata.requires_screenshots` | detector value (boolean) | Drives DV capture + gate; consumed by DV, QA (Q1.5), `attach-visual-evidence.sh`. Stamp on DV + QA tasks. |

#### Reader resolution order

Every **downstream reader** stage uses `run_index` to resolve its artifact path as `<basename>-${N}.md`. Reader resolution order for `plan_file`: `metadata.plan_file` first, then newest `.context/planning-*.md` (highest N) if metadata is absent. This order is for *readers* of an already-finalized plan only — PL0, the writer, never honors a pre-seeded `plan_file`; it always glob-increments per the algorithm above.

See `skills/agent-coordination/SKILL.md § metadata.skip_exploration Propagation` for the full propagation contract.

#### Optional dispatch metadata

PL0 MAY populate the optional dispatch fields (`skills/shared/state-ledger.md § Dispatch metadata`); they map 1:1 to `claude agents run` flags (`headless-dispatch.md`), honoured in-process for `model` (always) and `permission_mode` (audited), advisory otherwise.

##### Default writer rules

Apply when the trigger matches; leave unset otherwise so downstream falls back to agent frontmatter:

| Field | Set when | Value |
|---|---|---|
| `permission_mode` | Stage is `SR` or `FN` AND worktask flags include `--secure`/`--full` | `"default"` |
| `effort` | Stage is `DV` AND complexity score ≥ 35 | `"xhigh"` |
| `effort` | Stage is `DR` AND complexity score ≥ 35 | `"high"` |
| `dangerously_skip_permissions` | NEVER on `PL`/`SR`/`FN` tasks | (refuse) |

Reuse the complexity score from `### Dynamic Worktask Sizing`; stage code = the row being created, flags = the orchestrator invocation. Cheap to set and gives every downstream dispatcher (in-process or CLI) one source of truth.

##### Notation

Throughout this document, `<plan_file>` denotes the resolved plan **basename** for the current PL invocation (e.g. `planning-0.md`, `planning-3.md`) — never a path. Wherever a path is needed, write `.context/<plan_file>`; that includes `state.json.plan_file`, which stores the path shape. See the `plan_file` shape boundary in `skills/worktask/references/handoff-protocol.md § state.json schema`.

### Stage Artifact Naming

Every stage writes `<basename>-N.md` where N = the `planning-N.md` index for this run. Canonical stage→basename map: `skills/worktask/references/handoff-protocol.md#stage-artifact-map` (mirrored in `skills/shared/stage-codes.md`). Two-step resolver: (1) `task.metadata.run_index` → `<basename>-${N}.md`; (2) newest glob `<basename>-*.md` (highest N) when metadata is absent.

### PL0 Stage (Planning)
- **Detect workspace context** from task metadata
- **If workspace mode**: Read issue from `workspace.json`, write artifacts to workspace's `.context/`
- **If standard mode**: Create `.context/` folder, read per-issue context from `milestone.json` if exists (set by `/megatask` per-issue runs)
- Compute `<plan_file>` per **Plan File Naming** above
- Write `.context/<plan_file>` with requirements and acceptance criteria
- **Define test strategy** (what needs to be tested, existing tests to update)
- Define scope, priorities, and dependencies
- **Detect the integration branch once** and stamp it (see below) — DV must never silently fork from the wrong branch
- **Create subsequent stage tasks** based on complexity assessment (see below) — set `metadata.plan_file` on each

#### Branch naming (already done by the orchestrator — do not re-run)

The branch was already named once, by the **orchestrator**, at `commands/worktask.md § Step 3c` —
before this PL0 turn began, immediately after the state.json seed and before seeding
PL0 itself. PM MUST NOT invoke `branch-name.sh` **in rename mode** at any point; the once-only
rule (`skills/shared/git-conventions.md § Branch Naming`) means exactly one rename-mode run per
worktask, and that run already happened.

#### Branch naming — query modes are free, refinement is not PM's

The query modes (`--check`, `--print-types`, `--print-target`) and `BRANCH_NAME_PRINT=1` write
nothing — no rename, no state, no audit row — and are free to use. The one-shot refinement of
the *planned* name is an **orchestrator** step after PL0 returns
(`commands/worktask.md § Step A.4b`); PM never runs it, and a plan revision never re-refines.

PM only *reads* the result: `state.json facts.branch` carries the
name the orchestrator stamped from the script's `branch=<name>` / `target_branch=<name>`
stdout lines (`branch-name.sh` itself never writes state.json). In a host workspace that name
may not match the local branch on the opt-out and no-op arms; on the default worktree path the
two agree — see
`skills/worktask/references/workspace-modes.md § Host mapping — handled, not just noted`.
Full argv/env/exit-code contract: the script's own `--help`.

#### Integration-branch detection

Run once, at PL0. Detection order — the remote's default-branch pointer, then the batch workspace record, then `master`:

```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -z "$BASE" ] && BASE=$(jq -r '.git.base_branch // ""' workspace.json 2>/dev/null)
[ -z "$BASE" ] && BASE=master
```

##### Where to stamp the detected branch

Stamp the result in **two** places:

- `task.metadata.base_ref` on PL0 and on every downstream task — **only when `$BASE` is not `master`**. DV reads this as the authoritative per-task base override (`agents/developer.md § Worktree Mode`).
- `state.json .metadata.base_ref` — **unconditionally**, in the step-4 state reset. No shell script can read Task-System metadata, so this mirror is the only way `fn-preflight.sh resolve_base_ref` (rank 2) sees the value. Stamping it even in the `master` case keeps the field present for every reader.

Reader resolution order is canonical in `handoff-protocol.md § metadata.base_ref`.

#### `--no-gh-issue` opt-out

When the orchestrator's `/worktask` invocation carries `--no-gh-issue`, PL0 MUST stamp `metadata.no_gh_issue: true` on its own PL0 task and propagate the field through every downstream task it creates. The orchestrator's Step 6.5 reads the field via `skills/worktask/scripts/publish-pl-issue.sh`; the helper exits 0 immediately without any `gh` API call, auditing `result: "deferred"`, `reason: "opted_out"`. Worktask execution is unaffected — the stage loop proceeds as normal.

##### Default publish path (flag absent) & megatask opt-out

When the flag is **absent** (default), PL0 leaves the field unset and the helper runs the full publish pipeline (sanitise → `gh issue create` → state.json write → audit row). See `commands/worktask.md` for the canonical flag list and `skills/worktask/SKILL.md § PL Issue Publish` for the runtime semantics.

- Per-issue `/megatask` runs implicitly opt out of GH publish — no additional flag needed; the helper detects the batch per-issue context via `state.json:metadata.milestone` or `workspace.json` presence and exits `0` with `reason: "milestone_mode"` before any `gh` call (no create, no comment).

#### Anchor-content hygiene (GitHub publish safety)

The `## requirements`, `## acceptance-criteria`, `## scope`, and `## complexity` anchors of `<plan_file>` (plus `## summary`) are **published to a GitHub issue** by `publish-pl-issue.sh` after the user approves the plan. PL0 authors MUST keep them free of:

- `.context/` paths or numbered artifact filenames (`planning-N.md` … `ethics-review-N.md`);
- absolute/relative source paths (`/Users/`, `/home/`, `/tmp/`, `~/`, `./`, `../`, …) and Conductor workspace ids (`conductor/workspaces/<id>`);
- the literal tokens `workspace_path`, `plan_file`, `run_index`, `artifact_path`;
- raw plugin-qualified identifiers (token shape `lowercase-prefix:lowercase-name`, e.g. `corpflow:developer`) — rewrite to human-readable prose ("the iOS developer", "Complexity breakdown:").

##### Identifiers, backticks & the sanitiser

Identifiers/paths are allowed ONLY inside inline backticks / fenced code, or in the `## stages` anchor (consumed by the orchestrator, never rendered to the issue). Keep file references narrative ("the AuthCoordinator class"), not path form. The `publish-pl-issue.sh` two-pass sanitiser (Pass-1 line-drop of `Routed to <prefix>:`/`.context/` lines + Pass-2 identifier strip over the known-prefix allow-list) is a **safety net, not a substitute** for authoring hygiene — it aborts with `reason: "sanitiser_aborted"` when >50% of the combined anchor bodies is stripped, costing a review round-trip.

##### Design Preview anchor (Figma URL capture)

When the user's task description contains a Figma URL — regex `https?://(?:www\.)?figma\.com/(?:file|design|proto)/[A-Za-z0-9]+(?:/[^?\s)]*)?(?:\?[^\s)]*)?` — PL0 MUST:

1. Extract every matching URL.
2. Author a new `## design-preview` anchor in `<plan_file>` containing the URL(s) on their own line (one URL per line if multiple). Empty/absent anchor when no Figma URL is present — the publish helper omits the rendered section entirely.
3. Self-patch `state.json:facts.design_url` with the URL (string for one URL, array for multiple).
4. Note the URL in the `## scope` "In" list for reviewer visibility.

###### Rendering & post-capture rewrite

This anchor is **excluded from the strip-ratio denominator** (short URL bodies would skew the guard) and renders between `## Scope` and `## Complexity` with a one-sentence reviewer instruction. After the `### Figma Design Capture` step persists per-frame PNGs to `.context/designs/` (tracked in `figma-registry.md`), the PM's **Post-Capture Plan Update** rewrites `## design-preview` to name each persisted frame via an asset-placeholder token + state mapping (see `skills/shared/figma-capture.md § Post-Capture Plan Update`).

###### Asset-placeholder grammar (host-and-rewrite contract)

The PM MUST name each persisted per-frame file with a **placeholder token**, never a `.context/...` path (sanitiser Pass-1 rule L1 drops any `.context/` line; tokens survive it). The helper greps this exact shape — keep it stable:

```
<figma-source-url-line(s)>

{{asset:figma-<screen>-<state>-<node-id>.png}}
- <description: state, badge/label text, build notes>
<!-- repeat token + bullet pair per frame -->
```

1. `{{asset:<basename>}}` on its **own line**; PNG **basename only**, no path part.
2. A `- <description>` line **immediately follows** each token (one-to-one, in document order).
3. Source URL line(s): kept verbatim above the token block.
4. Hosting is owned by `publish-pl-issue.sh`: post-`sanitise_body` it resolves `.context/designs/<basename>` (the only Figma asset source; `.context/images/` is DV-only, never consulted) into a hosted `![<basename>](<https-url>)`. The PM never computes or embeds hosted URLs.

### PL0 Scaffolding (when invoked for worktask planning)
When invoked as PL0 stage agent:
1. Compute `<plan_file>` per **Plan File Naming** (glob `.context/planning-*.md`, pick next N) and create `.context/<plan_file>` with the requirements template — **except on a `plan_revision` turn**, which reuses the frozen `plan_file` and rewrites it in place (§ Revision of the run in flight)
2. Fill out `<plan_file>` with requirements, acceptance criteria, success metrics
3. Assess complexity (0-50 scale) and seed stage tasks via `state-patch.sh --task-create`, setting `metadata.plan_file = "<plan_file>"` AND `metadata.run_index = N` on each — **except on a `plan_revision` turn**, which never creates a second chain: patch the existing stage tasks in place when the revision changes subjects, ACs, or the stage set (§ Revision of the run in flight)

#### Post-publish verification (scaffolding step 4)

4. **Post-publish verification** (if `metadata.no_gh_issue` is NOT set and `publish-pl-issue.sh` ran): the run is published if EITHER `.context/state.json:metadata.github_issue_url` is non-empty (first run — issue created) OR `.context/gh-issue.json` carries a `url` (a **later** run in this `.context/` commented on the existing context issue; `state.json` is re-seeded per run so it will NOT hold the URL on a follow-up run — that is expected, not a failure).

##### Warn path when neither URL resolves

Only if NEITHER resolves, append one audit row `action: "pr_issue_link", result: "warn", reason: "github_issue_url_not_set_after_publish"` to `.context/logs/audit.jsonl` and surface the warning in the plan summary. A manual re-run of `publish-pl-issue.sh` is safe (idempotent): the run-independent `.context/gh-issue.json` anchor makes it resolve the existing issue and comment/skip instead of opening a duplicate (see `skills/gh-issue-dedup`). Do NOT block — worktask proceeds but the FN validator will fall back to rank-2/3/4 (`metadata.github_issue_number` → branch parse → `git log` `#NNN` token).

### Mandatory Plan-File Anchor Schema

`<plan_file>` MUST include all seven H2 anchors from `skills/worktask/references/handoff-protocol.md#anchor-allow-list § PL`. Downstream stages (AR, TL, DV, DR) read these anchors selectively; missing anchors trigger expensive full-file re-reads (see `stage-contracts § Required Inputs` step 3) and break the cache-friendly handoff layout.

Required anchors (kebab-case, no underscores, no spaces):

| Anchor | Content | Reader stage(s) |
|--------|---------|-----------------|
| `## requirements` | User-facing requirements, with IDs | AR, TL, DV |
| `## acceptance-criteria` | Given/When/Then per requirement | DV, DR, QA |
| `## scope` | What's included | TL, DV |
| `## out-of-scope` | What's explicitly excluded | DV, DR |
| `## risks` | Known unknowns, mitigations | AR, TL |
| `## complexity` | Score 0–50 + factor breakdown | TL (sizing), FN (recap) |
| `## stages` | Per-stage task list | TL, FN |

#### Anchor-lint enforcement

PostToolUse anchor-lint (when configured per `handoff-protocol.md § Anchor Pre-Flight`) fires after the write and signals the agent to amend the artifact if any anchor is missing. Without the hook, validation falls through to DR-stage `cache-lint.sh --anchor-lint`; the cost is the same but discovered late — prefer the proactive check.

#### Workspace Mode

`task.metadata.workspace_path` is **not** a mode detector — `/worktask` stamps it on every run
(step 3a/4), so its presence says nothing about which mode you are in. Detect workspace mode from
`workspace.json` / `.context/milestone.json` presence instead, and treat `workspace_path` as what
it is: the assigned tree, to be propagated verbatim onto every stage task you create. Read the
issue from `workspace.json`, write artifacts to workspace `.context/`. For megatask per-issue mode,
read the issue from `.context/milestone.json`. See `skills/megatask/SKILL.md § Orchestrator Pattern`.

### Dynamic Worktask Sizing (PL0 Stage)

Use the **Unified Complexity Assessment** from `skills/worktask/SKILL.md § Dynamic Worktask Sizing`:

1. **Assess complexity** using the 5-factor table (patterns, integration, concerns, risk, docs)
2. **Sum scores** (0-50 total)

#### Stage set by score (step 3)

3. **Create stage tasks** by score (each with `metadata.agent`), in three sub-steps:

   **3a — Resolve the tier default** from the tier table in `skills/estimation-methodology/SKILL.md § PL0 Stage-Set & Test-Mode by Complexity Score`.

   **3b — Decide AR0.** AR0 is a tier default at score ≥11, not a mandate. Apply the AR0 override rules in `§ Stage Inclusion Criteria (PL0 authority)` — exclude it only when ALL of the exclusion conditions hold, and force-include it at ANY tier (including Low) when ANY of the inclusion conditions holds.

   **3c — Decide TL0.** TL0 has no tier default; it is included on one test only — must this work be split across ≥2 developers/engineers (parallelizable workstreams, multiple DV specialists, or external-plugin fan-out needing coordination and merge)? Yes → include TL0 and record it in `added_stages`. No → omit it, at any score. A single workstream served by a single DV agent never gets TL0.

#### Recording the decisions (step 3, continued)

Stamp `metadata.skipped_stages` (`{stage, reason}`) for every stage of the full `PL→AR→TL→DV→DR→QA→DC→FN→ST` pipeline that is NOT created, and `metadata.added_stages` (same `{stage, reason}` shape) for every stage included beyond the tier default — so `state.json` self-documents both directions of the decision. Reasons are one sentence and decision-shaped, never a restatement of the score. Record the AR0 and TL0 decisions with their reasons in `planning-${N}.md ## stages`; the plan-approval gate summary surfaces both.

**context_refs seeding**: when AR0 is included, the DV0 task's `metadata.context_refs` MUST name an `architecture-${N}.md` anchor, and the DV0/DR0/QA0 dispatches carry `metadata.architecture_ref` once AR completes. When AR0 is excluded, `architecture-${N}.md` MUST NOT appear in any `context_refs` list and no `architecture_ref` is stamped.

#### Dependency chain & run-index stamping (steps 4–5)

4. **Set dependency chain** between seeded tasks using `state-patch.sh --task-block <ID> --on <ID[,ID…]>`
5. **Mark PL0 completed** after creating all stage tasks

Every seeded downstream stage MUST include `metadata.run_index = N` and `metadata.plan_file = "planning-${N}.md"`. Stage artifact paths embedded in the task description use `<basename>-${N}.md` (e.g., `architecture-${N}.md`, `development-${N}.md`).

#### Agent mapping for `metadata.agent`

Always emit fully-qualified `plugin:agent` form. The prefix follows the agent's owning plugin: `corpflow:` for orchestration/process agents (product-manager, software-architector, developer, qa-engineer, …), and the detected platform's own dev-plugin prefix for platform work. Resolve platform agents from the registry, never from memory: entry agents in `skills/shared/compatible-plugins.md § Registry`, functional roles (architect, security auditor, test generator, code fixer) in `§ Functional-role agents`, DV specialists in `skills/shared/platform-detection.md`. Bare names are not accepted — always emit the qualified form.

##### Stage → agent table

Platform variant = the same role from the detected platform's plugin, per the registry pointers above. Do not hardcode a platform roster here.

| Stage | Default agent | Platform variant |
|-------|---------------|------------------|
| AR0 | `corpflow:software-architector` | that platform's architect |
| TL0 | `corpflow:team-lead` | (same) |
| DV0 | `corpflow:developer` | that platform's entry agent or specialist |
| DR0 | `corpflow:technical-lead` | (same — invokes /dev-code-review) |
| SR0 | `corpflow:security-reviewer` | that platform's security auditor (or `security-scanning:security-scanning-security-auditor`) |
| QA0 | `corpflow:qa-engineer` | (same — may delegate to its test generator) |
| DC0 | `corpflow:technical-writer` | (same) |
| RE0 | `corpflow:release-engineer` | (same) |
| FN0 | `corpflow:project-manager` | (same) |
| ST0 | `corpflow:stakeholder` | (same) |

##### DV0 routing override — plugin worktask-infrastructure

Single source of truth — do NOT duplicate elsewhere. The DV0 default `corpflow:developer` routes *platform app-code*. Route DV to `metadata.agent: "corpflow:workflow-engineer"` (model `opus`, error_file `.context/errors/workflow-engineer.md`) when the change touches worktask infrastructure — `skills/worktask/scripts/*.sh`, the state-machine / Task-System glue under `skills/worktask/**`, or `hooks/**`. Platform/app code (Swift, server, web, product source) stays `corpflow:developer` (or the `apple-developer:*` variant); a mixed worktask splits DV sub-tasks by scope and routes each independently. `stage-codes.md` keeps the unconditional DV default and points here.

###### Worked example

Example: a `publish-pl-issue.sh` change → DV0 `workflow-engineer`, DR0 `technical-lead`, QA0 `qa-engineer`.

**See**: `skills/worktask/SKILL.md` for full assessment table. `skills/worktask/references/initialization-patterns.md § PL Creates Subsequent Tasks` for code pattern.

**State ledger**: Stage PL, Owner: product-manager. See `skills/shared/state-ledger.md`.

### PL Stage: Automatic Design Detection

PM detects design tasks and invokes Designer when appropriate.

#### Design Detection Criteria

Weighted-score the task description for design indicators:

| Category | Weight | Keywords |
|----------|--------|----------|
| UI Components | 2 | button, form, screen, layout, modal, dialog, menu, navigation, tab, card, list, table, grid |
| User Experience | 3 | user flow, accessibility, a11y, usability, interaction, gesture, wireframe, prototype |
| Visual Design | 2 | color, theme, dark mode, typography, font, icon, animation, responsive |
| Platform UI | 2 | view, widget, swiftui, uikit, navigationstack, tabview, compose, @composable, jetpack, material3, react, vue, svelte, angular, jsx, tsx, dom |
| High-Confidence | 5 | "redesign", "new ui", "ui/ux", "design system", "user interface", "visual refresh" |

**Negative Indicators** (-3 each): backend, api only, database, migration, infrastructure, no ui

**Threshold**: Score >= 5 triggers Designer invocation

#### Designer Invocation

**Flag gate**: invoke `corpflow:designer` ONLY when `--with-design` (`metadata.with_design == true`) is set — the keyword score is advisory. Without the flag, skip Designer even for UI apps and note the skip in `## summary`.

When the threshold is met AND the flag is set, invoke `Task(subagent_type: "corpflow:designer")` requesting:
1. UX Assessment, Design Scope, Technical Design, Pencil Mockups, Effort Estimate
2. Mockups saved to `.context/designs/` using `mockup-[feature]-[screen]-[variant].pen` naming
3. Include critical states: default, error, empty, loading

##### Combined Output

`<plan_file>` gets a Design Requirements section: Figma Design References (URLs + node descriptions → `.context/designs/figma-*.png`), Visual Mockups (`.context/designs/mockup-*.pen`), UX, UI Components, Accessibility.

##### Placement guard (non-negotiable)

> **Placement guard (non-negotiable):** persist Figma frames ONLY to `.context/designs/` with a `figma-registry.md` — that is the artifact QA's design-comparison gate consumes. NEVER write them to `.context/images/` (DV screenshots + user attachments only): a Figma PNG there disables the QA design gate (no `.context/designs/`) and masks an absent DV `screenshots.md`.

### Figma Design Capture

When a Figma URL is provided in the task description or user input, capture design screenshots regardless of the keyword-based design detection score.

**Trigger** — the task description contains a Figma URL matching:

```
figma\.com/(?:file|design|proto)/([a-zA-Z0-9]+)/([^?]+)(\?node-id=([0-9-]+))?
```

#### Trigger path forms & capture doc

`(?:file|design|proto)` is non-capturing (Group 1 `fileKey`, Group 4 `nodeId`); it must match both the `§ design-preview` trigger and `skills/shared/figma-capture.md § Figma URL Detection` — do not add `/board/` or `/slides/` (`get_metadata` is design-file-only). When the trigger fires, **Read `skills/shared/figma-capture.md`** for the full capture mechanics (URL detection, auth probe, capture workflow, `figma-registry.md` schema, post-capture plan update, Pencil coexistence). A no-Figma PL run never fires it and skips the Read.

### PL Stage: Automatic Ethics Gate Detection

PL0 scans the task for high-risk domain signals and inserts ET0 between PL0 and AR0 when the threshold is met (same weighted-score approach as design detection; negative indicators deduct to keep false positives low).

#### Ethics Risk Keyword Table

| Category | Weight | Keywords |
|----------|--------|----------|
| User Tracking | 4 | analytics, tracking, telemetry, user behavior, location, device fingerprint, cross-site, session recording |
| Financial | 4 | payment, billing, subscription, charge, refund, price discrimination, dynamic pricing, fee |
| Content Moderation | 3 | moderation, filter, ban, block user, content policy, takedown, flag content, shadowban |
| AI-Driven Decisions | 5 | automated decision, ai recommendation, algorithmic, ranking, personalization, model output |
| Vulnerable Populations | 5 | minor, child, elderly, disability, accessibility-critical, mental health, medical, protected class |
| Data Collection | 3 | PII, personal data, consent, GDPR, CCPA, HIPAA, biometric, sensitive data |
| High-Confidence Terms | 6 | "dark pattern", "addictive", "surveillance", "bias audit", "adversarial", "deepfake" |

##### Ethics thresholds & override

**Negative Indicators** (-3 each): internal-only, admin dashboard, test harness, dev-only, no user impact, synthetic data

**Threshold**: Score >= 5 triggers ET0 insertion AND `error_escalated_to: "ET"` reservation.

**Manual override**: `/worktask --ethics-review "..."` always creates ET0 regardless of score.

#### ET0 Insertion Pattern

When threshold met, PL0: (1) seed an `ET0` ethics-review task *before* AR0 with `metadata` `{stage: ET, agent: "corpflow:ethics-reviewer", model: "opus", error_file: ".context/errors/ethics-reviewer.md", plan_file, run_index: N, worktask_id}`; its description asks for `.context/ethics-review-${N}.md` with `Decision ∈ {pass, block, conditional}`. (2) `state-patch.sh --task-block AR0 --on ET0` so AR0 additionally blocks on ET0 (PL0 completes first, so ET0 is the effective gate).
**Decision cascade**:
- `Decision: pass` → AR0 unblocks, worktask continues
- `Decision: conditional` → AR0 unblocks with ethics constraints injected into prompt
- `Decision: block` → AR0 remains blocked, worktask halts, user notified

### Output Budget (PL)

The plan is WRITTEN to `planning-N.md` (≤350 lines, tiered detail), never emitted in the final chat text. Final return ≤250 tok.

## Scope-Term Disambiguation

Before finalizing a plan draft, scan the task text for a **scope noun with multiple plausible referent domains** ("artifacts", "the system", "the tests"). When competing interpretations map to materially different file sets — swinging the complexity score by more than ~20% — PL0 MUST NOT silently commit to the broadest reading. Either **(a)** state the chosen interpretation in `## summary` as a vetoable assumption with one-line justification, OR **(b)** ask one clarifying question before drafting when the swing changes the stage set or tier.

## Plan-Gate Open-Question Batching

When PL0 surfaces more than two open questions for the plan gate (explicit `open_questions[]` + unprompted refinements), consolidate them into ONE numbered elicitation list in `## summary`, each item carrying a concrete recommended default (e.g. `1. Ship dark mode as an opt-in toggle? (default: yes, opt-in)`). Surface the whole list in a single gate round-trip; apply the user's amendments in one batch pass before marking PL0 complete — not one PL resume per answer.

### Auto-decision path (`decision_gate: "auto"`)

When `PL0.metadata.decision_gate == "auto"` (stamped by `--auto=[decision]`), do NOT hold the gate
round-trip for the questions: still build the same numbered list with recommended defaults, but
return it in the typed handoff's `open_questions[]` and mark PL0 complete — the orchestrator's
Step A.4 pre-pass (`commands/worktask.md`) re-dispatches this agent as a **decision delegate on
the Fable model** to answer them.

#### Decision-delegate turn

Decide each question default-biased (deviate from the recommended default only with stated
evidence) and apply the amendments to the plan's EXISTING mandatory anchors (`## requirements` /
`## acceptance-criteria` / `## scope`) in ONE batch pass — never add a `## decisions` anchor to
`<plan_file>`, whose anchor set is exact (`handoff-protocol.md#anchor-allow-list § PL`; `## decisions`
belongs to AR's `architecture-N.md`). Return every decision as a `key_decisions[]` entry prefixed
`(auto-decided)`; the orchestrator merges those into `state.json facts.decisions[]`, drops the
resolved `facts.open_questions[]` entries, and carries each rationale in its
`auto_decision_resolved` audit row. Do NOT re-run `state-patch.sh` — PL0 is already `completed`,
so the plan amendments are your only writes.

#### Escalation-class questions (never auto-decided)

**Never auto-decide** irreversible or destructive actions, scope expansion beyond the task
description, security-posture-weakening changes, or spend authorization — return those as
`escalate` items; the orchestrator stops for the user on exactly those, even under
`plan_gate: "bypass"` (under an unattended `/megatask` per-issue run it instead parks the issue —
`commands/worktask.md § Step A.4 Escalation guard`).

## Version Bump Planning

When a worktask includes a version bump (release, tag, or `version:`/`CHANGELOG`/`MEMORY.md` change), PL0 MUST run a **version-ordering check** before recommending a version in `<plan_file>`:

1. `max_released_version` = greater of the highest git tag (`git tag --list --sort=-v:refname | head -n1`, strip `v`) and the max `MEMORY.md` release-history entry.
2. Compare the proposed version against it with semver ordering.
3. **If `proposed_version < max_released_version`** (a regression): surface a **"Version ordering regression"** item in `## risks` naming both versions (e.g. `proposed 3.24.2 < released 3.25.0`), and **ask the user to confirm intent** before downstream stages (quote the confirmation in the plan rationale). Non-blocking surface-and-confirm — the user may accept an out-of-order bump, but it MUST be visible at plan time. DC repeats this check as a second gate before FN commits.

## Completion Verification

### Verification Checklist Authoring

When writing grep-based verification steps in `<plan_file>` (e.g., AC validation commands):

- DO NOT use substring grep patterns in verification checklists; always use word-boundary anchors (`\b`) or full filename matches to avoid false positives against legitimate canonical names.
- DO NOT write an AC verification command into `<plan_file>` without executing it once against
  the current repo state and recording its literal output in the plan (or, if the command can
  only run post-edit, mark it inline `(unverified — dry-run required after theme lands)`).
  Naive `awk`/`grep`/`wc` forms silently break on folded YAML blocks, meta-index files, and
  other repo idiosyncrasies that only show up when actually run — catching this at PL0 is
  cheaper than a DR/QA re-diagnosis mid-pipeline.

#### The `(unverified)` mark never excuses an invalid command

The `(unverified — dry-run required after theme lands)` escape hatch covers **only** the
representativeness of the RESULT (present-state data cannot yet show the post-edit answer). It
never covers the command's **validity**. Before writing any such command into `<plan_file>`, run
it once against present-state data and confirm it executes without a usage/syntax error, on a
plausible input, with each flag doing what the prose claims.

A broken flag combination is a shipped defect, not an unverified one: `grep -viv -e A -e B`
(triple negation) reports everything "clean" and passes silently — three downstream stages then
re-derive the correct form. If the command cannot run at all before the edit, simplify it until
some form of it can.

#### Per-theme residual-grep completeness gate (REQUIRED)

An enumerated edit-file list goes stale: the repo evolves between plan authoring and DV execution, so files matching a theme's pattern can appear that the list never named. Treat every enumerated file list as a **starting set**, not the known universe — the completeness gate is a repo-wide grep, not the list.

For **each edit theme** in `<plan_file>`, the acceptance criteria MUST include at least one repo-wide grep/verification command (a residual-grep) that finds every live occurrence the theme must cover, listed as an **AC verification command** so DV can self-verify completeness without orchestrator rescue:

##### Residual-grep authoring rules

- Author the command so a clean diff yields **zero residuals** (`grep` returns no unhandled matches) once the theme is fully applied.
- Use word-boundary anchors (`\b`) or full-filename matches per the rule above.
- Pair each residual-grep with its theme; one theme may need more than one pattern.

##### Residual-grep worked example

Example AC verification command (theme: rename a hypothetical `legacy_flag` → `flag_mode`):

```bash
# Completeness gate — MUST return no unhandled matches after the theme is applied.
grep -rn '\blegacy_flag\b' --include='*.md' --include='*.sh' . || echo "clean: no residuals"
```

DV runs each theme's residual-grep before yielding (see `agents/workflow-engineer.md § Batch-Completion Discipline`); a non-empty result means the theme is incomplete regardless of how many enumerated files were edited.

##### `file:line` citations are starting sets too

The same staleness applies to any `file:line` reference cited in a theme's prose (e.g. carried over from an exploration pass). Cite it as an **approximate locator** — "near line N as of planning time" — and require DV to re-locate the real anchor before editing: a function/section boundary, or a grep for the quoted text. A line number is never authoritative by execution time; the quoted text is.

##### PL0 completion checklist

Before marking PL0 complete, verify:
- [ ] If a version bump is in scope, the version-ordering check ran; any `proposed_version < max_released_version` regression is surfaced in `## risks` and user-confirmed (per Version Bump Planning)
- [ ] `<plan_file>` written to `.context/planning-N.md` with the next free N (per Plan File Naming) — on a `plan_revision` turn, rewritten in place at the frozen N, with `facts.*` preserved (§ Revision of the run in flight)
- [ ] `<plan_file>` contains all acceptance criteria
- [ ] Test strategy section present with specific test scenarios and file paths
- [ ] Test effort estimate included (required, not optional)
- [ ] Complexity score calculated (0-50)
- [ ] Subsequent stage tasks created with `metadata.agent`, `metadata.plan_file = "<plan_file>"`, AND `metadata.run_index = N` per complexity score
- [ ] Dependency chain set between created tasks
- [ ] No open questions blocking next stage

##### PL0 completion checklist — design & Figma items

- [ ] If design detected (score >= 5), Designer was invoked
- [ ] If Figma URL detected, screenshots captured AND persisted (verified non-zero PNGs) to `.context/designs/figma-*.png`
- [ ] If a container node was captured, one overview PNG + one PNG per child frame were persisted, with one registry row each (REQ-A/REQ-B)
- [ ] If Figma URL detected, per-frame design context summarized in `<plan_file> § Figma Design References` (one bullet per frame)
- [ ] If Figma URL detected, `<plan_file> § design-preview` lists each persisted per-frame file with state mapping + per-frame build notes (REQ-D)

## Handoff Protocol

Inputs (anchor-first), completion checklist, run-index resolver, atomic-write rules: `skills/shared/stage-contracts.md` — reference only; this section is self-sufficient, do not Read stage-contracts.md in the steady path. Per-stage frontmatter template (paste verbatim at artifact top): `stage-contracts.md#tpl-pl`. Prev→this label: `USER→PL`.

### State Patch — REQUIRED before return

Run `state-patch.sh --stage PL --prev USER` (`skills/worktask/scripts/`) to atomically patch `tasks.PL0` + the `USER→PL` handoff edge into `.context/state.json` from this artifact's `handoff:` frontmatter summary. Put the one-line goal (verb + object, ≤120 chars) in that summary — downstream stages read it as the worktask goal alongside `planning-N.md#requirements`. Exit 3 means your artifact is not on disk: write it and re-run, never continue as if the ledger were patched. If the tool cannot run at all, do NOT skip silently — apply the Edit-direct fallback in `handoff-protocol.md#layer-1-fallback`, which writes the `handoffs` edge the hook cannot.

#### Union this stage's facts in the same call

Pass `--facts` in the **same call** to union this stage's compressed facts into `state.json → facts.*` — the channel `stage-contracts.md` tells every downstream stage to read first, and the only scripted writer for it. PL owns both `key_decisions` and the `open_questions[]` a `--auto=[decision]` delegate later resolves:

```bash
state-patch.sh --stage PL --prev USER --facts '{
  "decisions": [{"id":"pl-1","summary":"≤160 chars","ref":"planning-0.md#stages"}],
  "open_questions": [{"id":"q1","summary":"…","stage":"PL"}]}'
```

Union by `.id` (last writer wins, newest at the tail): it never clobbers an upstream stage's entries and a re-run is byte-identical. Omitting it loses the fact silently. Canonical rule: `handoff-protocol.md#facts-union`.

Stage-task seeding uses the same `state-patch.sh` grant, so it shares this fallback ladder —
there is no separate task tool to fall back to.

#### State Patch — `facts.goal` is part of the contract

`facts.goal` MUST be non-empty in `.context/state.json` when PL returns. The orchestrator seeds it from the task description at Step 3a, so the normal job here is to REFINE it to the one-line goal above — but verify it, and write it if the seed is missing (`jq '.facts.goal = "<goal>"'` through the same atomic temp+rename). It is not a bookkeeping field: `publish-pl-issue.sh` reads it as the first rank of both the issue title and the `## Summary` chain, and its absence is what produced a kebab-slug title with an empty Summary in issue #375. Also write a `title:` line into the plan's frontmatter — that is the chain's next rank and the plan's own record of what it is about.
