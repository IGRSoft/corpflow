# PL0 Procedure — the complete planning-stage worktask integration

Read this file **first, before any other action**, when `corpflow:product-manager` is dispatched as
the PL stage agent (PL0). It is the whole planning procedure and the only place it exists — the
agent file carries identity and a pointer here, nothing that substitutes for this document.
Non-PL0 invocations (`/estimate`, `/product-requirements`, `/roadmap`,
`/milestone`) never need it.

Every `skills/…` and `commands/…` path below is relative to the **corpflow plugin root**, not the
worktask repo — resolve per `agents/product-manager.md § Plugin paths`. `<plan_file>`: see § Notation.

## Test Strategy Definition

Define the test strategy in the plan file: scope (unit/integration/E2E), framework, acceptance criteria, existing tests to update, new test files, effort estimate by stage.

### Key Rules

1. **DV writes unit tests** as part of implementation; QA validates integration/E2E
2. **Framework selection is platform-derived**: adopt whatever the repo's test targets already use; with no existing tests, take the detected platform's test-generator default (`skills/shared/routing-matrix.md § Functional-role aliases`). Name it in the plan. Never carry one platform's framework into another — the Apple Swift Testing (unit) / XCTest (UI) split in `skills/shared/testing-strategy.md` is Apple-only.
3. **Coverage expectations**: new features 3+ unit scenarios; bug fixes regression tests; refactors must identify all affected existing tests

### Required Metadata: Test Selection Gate

Every plan file (`planning-N.md`) MUST declare four frontmatter `metadata` fields. They drive DV (step D2), QA (step Q1), the Visual Comparison subsection, and the screenshot capture gate.

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

The complexity-score → default `test_mode` table lives in `skills/estimation-methodology/SKILL.md § PL0 Stage-Set & Test-Mode by Complexity Score`. Uncertain between `scoped` and `full`? Choose `scoped` — the auto-promotion safety net (DV warns, QA promotes on an empty Selected list) catches under-selection.

##### Comment/doc-only diffs

When the planned diff is entirely comments, prose files, or non-executable strings, `build-only` is **selected, not merely available**: nothing executable changed, so the marker-coverage precondition does not apply. Record the reason in `§ Test Strategy`. Canonical rule (including the "no QA re-run for a post-QA doc-only change" consequence): `skills/shared/testing-strategy.md § Comment/doc-only diffs`.

#### `always_required_tests` — explicit override

Test IDs that always run (every mode, every run). ID grammar is per-platform and canonical in `skills/shared/test-selection-syntax.md § Platform handlers`. Platforms whose selective-test handler is a stub auto-promote the run to module-scope at DV (never `full` — QA remains the sole full-suite authority), so entries are recorded but unused for DV selection. Use sparingly, for cross-cutting smoke tests not annotated `@test-required` in source.

#### `ui_visual_check` — Visual QA gate

Independent of `test_mode`. Set `true` when any applies:
- New views/screens/UI components in the platform's view layer (SwiftUI/UIKit, Compose, React/Vue/Svelte/Angular, …)
- `.context/designs/` holds visual artifacts (Figma registry, mockups) needing verification
- Layout, styling, or animation changes need screen capture to validate
- Stakeholder explicitly requests UI verification

When `true` AND `.context/designs/` has artifacts, QA performs Design Comparison during Q1.

#### `requires_screenshots` — DV screenshot capture gate (REQUIRED)

Drives `dv-screenshot-capture` and its SubagentStop gate (`hooks/dv-screenshot-gate.sh`). `true` ⇒ DV MUST produce `.context/images/<worktask_id>/screenshots.md`, whose captures are embedded in BOTH the PR body and the GitHub issue (binding user directive). `false` ⇒ DV writes a skip-rationale manifest and the gate passes.

**PL0 is the sole WRITER of this flag.** The downstream `?? true` defaults are defense-in-depth for ad-hoc runs only — stamp it deterministically per the steps below.

##### Detector run (step 1)

1. Run the detector against the draft plan:
   ```bash
   skills/worktask/scripts/detect-ui-change.sh <draft-plan> --platform <platform>
   ```
   It emits `{requires_screenshots, signals, rationale}`. Signals (ANY true ⇒ true): **S1** `ui_visual_check: true`; **S2** `.context/designs/` has `figma-registry.md`/`*.png`; **S3** `## scope`/`## requirements` matches the UI keyword set; **S4** platform ∈ {apple, web, android} AND scope names UI path classes (`Views/`, `Screens/`, `*.storyboard`, `*.tsx`, …). Exits 0 always; any error ⇒ `true` (`fail_safe_default`).

##### Stamp, override, propagate (steps 2–3)

2. Stamp the returned value on the plan frontmatter `metadata.requires_screenshots` and record the `rationale` line in the plan (satisfies AC-2's "recorded rationale" when false).
3. **Override asymmetry**: force `true` freely, no justification needed. Forcing `false` against a `true` detector needs an explicit user directive quoted in the plan rationale — the detector never silently downgrades.

Propagate the flag on all three writer surfaces (see Downstream propagation): plan frontmatter, DV+QA task metadata, and `state.json .metadata.requires_screenshots` (the channel the gate reads — SubagentStop stdin carries no task metadata in live runs).

Plans declare `test_mode` + `ui_visual_check`; the marker grammar DV parses is canonical in `skills/shared/test-selection-syntax.md`.

4. **Test effort estimate is required** (not optional) — by type, hours, and stage (DV/QA)

## Worktask Integration

**Stage**: PL (Planning, 1/11) — see `skills/shared/worktask-stage-context.md` for pipeline context. The product-manager handles:

### Plan File & Run Index Naming

Each PL invocation produces a numbered plan file and stamps a shared run index on every downstream task: **first plan** `.context/planning-0.md`; **subsequent** `.context/planning-N.md` where N = max existing index + 1.

Both are **new runs**. A plan-gate revision is not a new run and allocates nothing — see § Revision of the run in flight below.

#### Algorithm (run as PL0 step 1)

1. Glob `.context/planning-*.md`. Extract the integer suffix from each match.
2. If matches exist, set `N = max(existing) + 1`. Otherwise `N = 0`.
3. Write `.context/planning-${N}.md`. Do **not** overwrite `planning-0.md`, ..., `planning-(N-1).md` — they remain as historical plans.

##### Write-target authority

> **PL0 is the authoritative writer.** Any `plan_file` / `run_index` in a pre-seeded `state.json` (the orchestrator's Phase-1 step 3a seed) is **provisional**: PL0 MUST recompute `N` via the step-1 glob and treat that as authoritative. **Never write to a `planning-${N}.md` that already exists** — if the computed target exists, the glob was stale; recompute. The reader resolution order below (`metadata.plan_file` first) governs *downstream stages* consuming a finalized plan, never PL0's own write target.

##### Revision of the run in flight (NOT a new index)

> **BINDING.** When the dispatch prompt carries `plan_revision: true` (a plan-gate rejection —
> `commands/worktask.md § Plan-revision re-dispatch`), this turn revises the run in flight, not a
> new run. **Skip algorithm steps 1–3**: `run_index` and `plan_file` are frozen — edit the current
> `.context/<plan_file>` in place. **Skip the Step-4 reset** below; patch `facts.*` additively so
> `facts.decisions[]` (the gate answers just given) and every other fact of this run survive.
> **Do not create stage tasks** — patch the existing chain in place when the revision changes
> subjects, ACs, or the stage set. The never-overwrite rule protects **finished** runs' historical
> plans; a plan under active revision is not history, and rewriting it is the point.

#### Step 4 — state.json reset

4. **state.json reset** (new run in existing `.context/`; **skipped on a `plan_revision` turn**):
   atomically rewrite `.context/state.json` with `"run_index": N`, `"tasks": {"PL0": {"status": "in_progress"}}`, `metadata.requires_screenshots` = the detector's value (the channel `hooks/dv-screenshot-gate.sh` and `attach-visual-evidence.sh` read), `metadata.base_ref` = the detected integration branch (below), and empty `facts.*` (preserving `version`, `worktask_id`, `platform`). Use `handoff-protocol.md#atomic-write`.

##### Step 4 — plan_file shape

Write the **path** shape into `state.json.plan_file` — `".context/planning-${N}.md"`, not the bare `<plan_file>` notation value, which is a **basename** everywhere in this document. Writing it unprefixed is exactly how the prefix goes missing and the issue-publish helper loses the plan. Rule: `handoff-protocol.md § plan_file shape boundary`.

#### Downstream propagation

When PL seeds downstream stage tasks via `state-patch.sh --task-create`, stamp **all** of the following on each (table continues across the two sub-sections below — every row is mandatory):

| Key | Value | Purpose |
|---|---|---|
| `metadata.plan_file` | `"planning-${N}.md"` | Pin active plan — **bare basename**, deliberately a different shape from `state.json.plan_file` (a workspace-relative path). See the `plan_file` shape boundary in `handoff-protocol.md § state.json schema`. |
| `metadata.run_index` | `N` (integer) | Resolve `<basename>-${N}.md` artifacts |
| `metadata.isolation` | `"worktree"` | File-writing stages (DV; megatask per-issue AR/DR/QA) always run in an isolated worktree (consumed by developer § D0.0, technical-lead DR check, workspace-modes.md). |

##### Propagation fields — dispatch pair

| Key | Value | Purpose |
|---|---|---|
| `metadata.model` | the stage's alias from `stage-codes.md § Primary Stages` | Passed to `Task()`; never inherited from frontmatter. |
| `metadata.effort` | that table's tier, or the override actually dispatched | **Mandatory, not optional** since Step C.0a began reading it. The resolver bumps it one rung, and frontmatter is the wrong fallback — DV sub-tasks dispatched at `xhigh` run at a tier `developer.md`'s `effort: high` never mentions. A row without it is skipped (`resolver_skipped`, `reason: "effort_unstamped"`) and its blocking items go back to asking a human. |

##### Propagation fields — gates

| Key | Value | Purpose |
|---|---|---|
| `metadata.fn_gate` | `"checkpoint"` (default) | Pre-FN human checkpoint; orchestrator STOPs before FN for approval. `"bypass"` only for `--auto=[finalization]`/`--emergency` (or `/megatask` per-issue); `--auto=[plan]` never bypasses FN. Stamp on PL0; read at the mid-loop FN gate. |
| `metadata.decision_gate` | `"user"` (default) | WHO answers `open_questions[]`. `"auto"` only for `--auto=[decision]` (or `/megatask` per-issue). PL0's go to the Fable-model decision pass (`commands/worktask.md § Step A.4`) instead of the plan-gate round-trip; every **other** stage's blocking `decision` items go to the Step C.0a resolver at its own boundary, and the FN-gate batch to Step C.3. Bypasses no gate. Stamp on PL0; consumed by § Plan-Gate Open-Question Batching, Step A.4, Step C.0a and Step C.3. |

##### Propagation fields — exploration & screenshots

| Key | Value | Purpose |
|---|---|---|
| `metadata.skip_exploration` | `true` if `.context/exploration.md` exists | Suppress redundant Glob/Grep in AR/TL/DV |
| `metadata.exploration_anchors` | `["exploration.md#facts", "exploration.md#refs", "planning-${N}.md#requirements"]` (when `skip_exploration: true`) | Authoritative pre-explored set |
| `metadata.requires_screenshots` | detector value (boolean) | Drives DV capture + gate; consumed by DV, QA (Q1.5), `attach-visual-evidence.sh`. Stamp on DV + QA tasks. |

#### Reader resolution order

Every **downstream reader** resolves its artifact path as `<basename>-${N}.md` from `run_index`. For `plan_file`: `metadata.plan_file` first, else newest `.context/planning-*.md` (highest N). Readers of a finalized plan only — PL0, the writer, never honors a pre-seeded `plan_file` and always glob-increments per the algorithm above.

Full propagation contract: `skills/agent-coordination/SKILL.md § metadata.skip_exploration Propagation`.

#### Optional dispatch metadata

PL0 MAY populate the remaining optional dispatch fields (`skills/shared/state-ledger.md § Dispatch metadata`); they map 1:1 to `claude agents run` flags (`headless-dispatch.md`), honoured in-process for `model` (always) and `permission_mode` (audited), advisory otherwise. `effort` has moved out of this set — it is mandatory above. It stays *advisory as a dispatch flag* (in-process `Task()` has no effort parameter), but it is no longer optional as a *ledger record*, because Step C.0a reads it.

##### Default writer rules

Apply on trigger match; leave unset otherwise so downstream falls back to agent frontmatter:

| Field | Set when | Value |
|---|---|---|
| `permission_mode` | Stage is `SR` or `FN` AND worktask flags include `--secure`/`--full` | `"default"` |
| `effort` | Stage is `DV` AND complexity score ≥ 35 | `"xhigh"` |
| `effort` | Stage is `DR` AND complexity score ≥ 35 | `"high"` |
| `dangerously_skip_permissions` | NEVER on `PL`/`SR`/`FN` tasks | (refuse) |

Reuse the complexity score from `### Dynamic Worktask Sizing`; stage code = the row being created, flags = the orchestrator invocation. Cheap, and gives every downstream dispatcher (in-process or CLI) one source of truth.

##### Notation

`<plan_file>` = the resolved plan **basename** for the current PL invocation (`planning-0.md`, `planning-3.md`), never a path. Where a path is needed write `.context/<plan_file>` — including `state.json.plan_file`, which stores the path shape (`skills/worktask/references/handoff-protocol.md § plan_file shape boundary`).

### Stage Artifact Naming

Every stage writes `<basename>-N.md`, N = this run's `planning-N.md` index. Canonical stage→basename map: `skills/worktask/references/handoff-protocol.md#stage-artifact-map` (mirrored in `skills/shared/stage-codes.md`). Two-step resolver: (1) `task.metadata.run_index` → `<basename>-${N}.md`; (2) newest glob `<basename>-*.md` when metadata is absent.

### PL0 Stage (Planning)
- **Detect workspace context** from task metadata — workspace mode: read the issue from `workspace.json`, write artifacts to the workspace's `.context/`; standard mode: create `.context/`, reading per-issue context from `milestone.json` when `/megatask` set one
- Compute `<plan_file>` per **Plan File Naming**, then write `.context/<plan_file>` with requirements and acceptance criteria
- **Define test strategy** (what to test, existing tests to update); define scope, priorities, dependencies
- **Detect the integration branch once** and stamp it (below) — DV must never silently fork from the wrong branch
- **Create subsequent stage tasks** from the complexity assessment (below), setting `metadata.plan_file` on each

#### Branch naming (already done by the orchestrator — do not re-run)

The **orchestrator** already named the branch once at `commands/worktask.md § Step 3c`, before this
PL0 turn began. PM MUST NOT invoke `branch-name.sh` **in rename mode**: the once-only rule
(`skills/shared/git-conventions.md § Branch Naming`) allows exactly one rename-mode run per
worktask, and it already happened.

#### Branch naming — query modes are free, refinement is not PM's

Query modes (`--check`, `--print-types`, `--print-target`) and `BRANCH_NAME_PRINT=1` write nothing
— no rename, no state, no audit row — so they are free. The one-shot refinement of the *planned*
name is an **orchestrator** step after PL0 returns (`commands/worktask.md § Step A.4b`); PM never
runs it, and a plan revision never re-refines.

PM only *reads* the result: `state.json facts.branch` holds what the orchestrator stamped from the
script's `branch=<name>` / `target_branch=<name>` stdout (`branch-name.sh` never writes
state.json). In a host workspace that name may not match the local branch on the opt-out and no-op
arms; on the default worktree path they agree —
`skills/worktask/references/workspace-modes.md § Host mapping — updated, not preserved`.
Full argv/env/exit-code contract: the script's own `--help`.

#### Integration-branch detection

Run once, at PL0, through the shared resolver rather than a private ladder — every reader must
agree on the ranks (canonical: `handoff-protocol.md § metadata.base_ref`):

| Rank | Source |
|---|---|
| 0 | `fork_base()` fork point — evidence, **opt-in**; reconciles by sweep item rather than overriding |
| 1 | `$FN_BASE_REF` — explicit operator/test override |
| 2 | `state.json .metadata.base_ref` — **where a host-declared target branch enters the order** |
| 3 | `workspace.json .git.base_branch` — `/megatask` per-issue record |
| 4 | `git symbolic-ref refs/remotes/origin/HEAD` — repository default branch |
| — | **unresolved** — reported, never guessed |

##### Calling the resolver

```bash
. skills/worktask/scripts/branch-lib.sh
BASE=$(resolve_base_ref); BASE="${BASE#origin/}"
```

There is **no literal fallback**: an unresolved base is reported and the caller degrades
non-blocking. A hardcoded `master` silently compares against a branch that may not exist, which is
the failure the ranked order exists to remove. PL0 does **not** pass `--with-fork-point`: an empty
answer here is a fact to report, and rank 0 reaches the plan through the reconcile stub below.

##### Reconcile a disagreeing fork point — never override it

With `$BASE` known, compute `fork_base "$BASE"` (its argument is the tie-break, and it is what keeps
rank 0 from recursing). When the answer is non-empty and differs from `$BASE` after stripping
`origin/`, emit **one** sweep stub — `class: decision`, `blocks_next_stage: false` — carrying both
branch names and both ahead-counts, fork point recommended:

> Base branch: `<configured>` (configured, source `<rank>`) vs `<fork>` (fork point). HEAD is `<n>`
> commits ahead of the first, `<m>` ahead of the second. Recommended: `<fork>`. A fork point is
> evidence, not intent — a branch deliberately rebased onto a release line is a legitimate reason
> to keep the configured value.

###### When no item is emitted

Agreement, an empty fork point, no remotes or a detached HEAD ⇒ **no item**. PL0 never rewrites
`metadata.base_ref` from the fork point; only a user answer at the plan gate does, and under
`--auto=[decision]` the default is to **keep the configured base** — an auto-adopted fork point
would be exactly the silent retarget this reconcile exists to prevent.

##### Where to stamp the detected branch

Stamp the result in **two** places:

- `task.metadata.base_ref` on PL0 and every downstream task — **only when `$BASE` is not `master`**. DV reads it as the authoritative per-task base override (`agents/developer.md § Worktree Mode`).
- `state.json .metadata.base_ref` — **unconditionally**, in the step-4 reset. Shell scripts cannot read Task-System metadata, so this mirror is the only way `branch-lib.sh resolve_base_ref` (rank 2) sees the value; stamping it even for `master` keeps the field present for every reader. On a turn that skips the step-4 reset (`plan_revision`), write it with `state-patch.sh --ledger-meta --set '{"base_ref":"<branch>"}'` rather than editing `state.json` by hand — a hand edit bypasses the lock and the bounds filter the single writer applies.

Reader resolution order is canonical in `handoff-protocol.md § metadata.base_ref`.

#### `--no-gh-issue` opt-out

Under `--no-gh-issue`, PL0 MUST stamp `metadata.no_gh_issue: true` on its own PL0 task and propagate it to every downstream task. The orchestrator's Step 6.5 reads it via `skills/worktask/scripts/publish-pl-issue.sh`, which exits 0 with no `gh` call, auditing `result: "deferred"`, `reason: "opted_out"`. The stage loop is unaffected.

##### Default publish path (flag absent) & megatask opt-out

Flag **absent** (default): leave the field unset and the helper runs the full pipeline (sanitise → `gh issue create` → state.json write → audit row). Canonical flag list: `commands/worktask.md`; runtime semantics: `skills/worktask/SKILL.md § PL Issue Publish`.

- Per-issue `/megatask` runs implicitly opt out — no flag needed. The helper detects batch per-issue context via `state.json:metadata.milestone` or `workspace.json` presence and exits `0` with `reason: "milestone_mode"` before any `gh` call.

#### Anchor-content hygiene (GitHub publish safety)

`publish-pl-issue.sh` **publishes** the `## requirements`, `## acceptance-criteria`, `## scope` and `## complexity` anchors of `<plan_file>` (plus `## summary`) to a GitHub issue once the user approves the plan. Keep them free of:

- `.context/` paths or numbered artifact filenames (`planning-N.md` … `ethics-review-N.md`);
- absolute/relative source paths (`/Users/`, `/home/`, `/tmp/`, `~/`, `./`, `../`, …) and Conductor workspace ids (`conductor/workspaces/<id>`);
- the literal tokens `workspace_path`, `plan_file`, `run_index`, `artifact_path`;
- raw plugin-qualified identifiers (token shape `lowercase-prefix:lowercase-name`, e.g. `corpflow:developer`) — rewrite to human-readable prose ("the iOS developer", "Complexity breakdown:").

##### Identifiers, backticks & the sanitiser

Identifiers/paths are allowed ONLY inside inline backticks / fenced code, or in the `## stages` anchor (orchestrator-only, never rendered). Keep file references narrative ("the AuthCoordinator class"), not path form. The `publish-pl-issue.sh` two-pass sanitiser (Pass-1 line-drop of `Routed to <prefix>:`/`.context/` lines + Pass-2 identifier strip over the known-prefix allow-list) is a **safety net, not a substitute** for authoring hygiene — it aborts with `reason: "sanitiser_aborted"` when >50% of the combined anchor bodies is stripped, costing a review round-trip.

##### Design Preview anchor (Figma URL capture)

When the task description contains a Figma URL — regex `https?://(?:www\.)?figma\.com/(?:file|design|proto)/[A-Za-z0-9]+(?:/[^?\s)]*)?(?:\?[^\s)]*)?` — PL0 MUST:

1. Extract every matching URL.
2. Author a new `## design-preview` anchor in `<plan_file>` containing the URL(s) on their own line (one URL per line if multiple). Empty/absent anchor when no Figma URL is present — the publish helper omits the rendered section entirely.
3. Self-patch `state.json:facts.design_url` with the URL (string for one URL, array for multiple).
4. Note the URL in the `## scope` "In" list for reviewer visibility.

###### Rendering & post-capture rewrite

This anchor is **excluded from the strip-ratio denominator** (short URL bodies would skew the guard) and renders between `## Scope` and `## Complexity` with a one-sentence reviewer instruction. Once `### Figma Design Capture` has persisted per-frame PNGs to `.context/designs/` (tracked in `figma-registry.md`), the PM's **Post-Capture Plan Update** rewrites `## design-preview` to name each frame via an asset-placeholder token + state mapping (`skills/shared/figma-capture.md § Post-Capture Plan Update`).

###### Asset-placeholder grammar (host-and-rewrite contract)

Name each persisted per-frame file with a **placeholder token**, never a `.context/...` path (sanitiser Pass-1 rule L1 drops any `.context/` line; tokens survive it). The helper greps this exact shape — keep it stable:

```
<figma-source-url-line(s)>

{{asset:figma-<screen>-<state>-<node-id>.png}}
- <description: state, badge/label text, build notes>
<!-- repeat token + bullet pair per frame -->
```

1. `{{asset:<basename>}}` on its **own line**; PNG **basename only**, no path part.
2. A `- <description>` line **immediately follows** each token (one-to-one, in document order).
3. Source URL line(s): kept verbatim above the token block.
4. Hosting belongs to `publish-pl-issue.sh`: post-`sanitise_body` it resolves `.context/designs/<basename>` (the only Figma asset source; `.context/images/` is DV-only) into a hosted `![<basename>](<https-url>)`. The PM never computes or embeds hosted URLs.

### PL0 Scaffolding (when invoked for worktask planning)

Steps 1–3 are the § PL0 Stage bullets in execution order, with the `plan_revision` carve-outs:

1. Compute `<plan_file>` and create it from the requirements template — **except on a `plan_revision` turn**, which reuses the frozen `plan_file` and rewrites in place (§ Revision of the run in flight)
2. Fill in requirements, acceptance criteria, success metrics
3. Assess complexity (0-50) and seed stage tasks via `state-patch.sh --task-create`, setting `metadata.plan_file` AND `metadata.run_index = N` on each — **except on a `plan_revision` turn**, which never creates a second chain: patch the existing tasks in place when the revision changes subjects, ACs, or the stage set

#### Post-publish verification (scaffolding step 4)

4. **Post-publish verification** (when `metadata.no_gh_issue` is unset and `publish-pl-issue.sh` ran): published ⇔ EITHER `.context/state.json:metadata.github_issue_url` is non-empty (first run — issue created) OR `.context/gh-issue.json` carries a `url` (a **later** run in this `.context/` commented on the existing context issue). `state.json` is re-seeded per run, so it will NOT hold the URL on a follow-up run — expected, not a failure.

##### Warn path when neither URL resolves

Only if NEITHER resolves: append one audit row `action: "pr_issue_link", result: "warn", reason: "github_issue_url_not_set_after_publish"` to `.context/logs/audit.jsonl` and surface it in the plan summary. Re-running `publish-pl-issue.sh` manually is safe — the run-independent `.context/gh-issue.json` anchor makes it resolve the existing issue and comment/skip rather than duplicate (`skills/gh-issue-dedup`). Do NOT block: the worktask proceeds and the FN validator falls back to rank-2/3/4 (`metadata.github_issue_number` → branch parse → `git log` `#NNN` token).

### Mandatory Plan-File Anchor Schema

`<plan_file>` MUST include all eight PL H2 anchors from `skills/worktask/references/handoff-protocol.md#anchor-allow-list § PL` plus the universal `## elicitation-sweep`. AR/TL/DV/DR read them selectively; a missing anchor forces expensive full-file re-reads (`stage-contracts § Required Inputs` step 3) and breaks the cache-friendly handoff layout.

#### Mandatory Plan-File Anchor Schema — the table

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
| `## summary` | Complexity/tier line, vetoable assumptions, gate-question preview | user (plan gate), FN (recap) |
| `## elicitation-sweep` | The plan-gate sweep items, or the explicit empty statement | orchestrator (§ Step C.4) |

#### Anchor-lint enforcement

PostToolUse anchor-lint (`handoff-protocol.md § Anchor Pre-Flight`) fires after the write and signals the agent to amend a missing anchor. Without the hook, validation falls to DR-stage `cache-lint.sh --anchor-lint` — same cost, discovered late; prefer the proactive check.

#### Workspace Mode

`task.metadata.workspace_path` is **not** a mode detector — `/worktask` stamps it on every run
(step 3a/4), so its presence says nothing about the mode. Detect workspace mode from
`workspace.json` / `.context/milestone.json` presence instead, and treat `workspace_path` as what
it is: the assigned tree, propagated verbatim onto every stage task you create. Read the issue
from `workspace.json` (megatask per-issue: `.context/milestone.json`) and write artifacts to the
workspace `.context/`. See `skills/megatask/SKILL.md § Orchestrator Pattern`.

### Dynamic Worktask Sizing (PL0 Stage)

Use the **Unified Complexity Assessment** from `skills/worktask/SKILL.md § Dynamic Worktask Sizing`:

1. **Assess complexity** using the 5-factor table (patterns, integration, concerns, risk, docs)
2. **Sum scores** (0-50 total)

#### Stage set by score (step 3)

3. **Create stage tasks** by score (each with `metadata.agent`), in three sub-steps:

   **3a — Resolve the tier default** from the tier table in `skills/estimation-methodology/SKILL.md § PL0 Stage-Set & Test-Mode by Complexity Score`.

   **3b — Decide AR0.** A tier default at score ≥11, not a mandate. Apply the override rules in `§ Stage Inclusion Criteria (PL0 authority)`: exclude only when ALL exclusion conditions hold; force-include at ANY tier (including Low) when ANY inclusion condition holds.

   **3c — Decide TL0.** No tier default; one test only — must this work be split across ≥2 developers/engineers (parallelizable workstreams, multiple DV specialists, or external-plugin fan-out needing coordination and merge)? Yes → include TL0 and record it in `added_stages`. No → omit at any score. A single workstream with a single DV agent never gets TL0.

#### Recording the decisions (step 3, continued)

Stamp `metadata.skipped_stages` (`{stage, reason}`) for every stage of the full `PL→AR→TL→DV→DR→QA→DC→FN→ST` pipeline NOT created, and `metadata.added_stages` (same shape) for every stage beyond the tier default, so `state.json` self-documents both directions. Reasons are one sentence and decision-shaped, never a restatement of the score. Record the AR0 and TL0 decisions with reasons in `planning-${N}.md ## stages`; the plan-approval gate summary surfaces both.

**context_refs seeding**: AR0 included ⇒ DV0's `metadata.context_refs` MUST name an `architecture-${N}.md` anchor, and DV0/DR0/QA0 dispatches carry `metadata.architecture_ref` once AR completes. AR0 excluded ⇒ `architecture-${N}.md` MUST NOT appear in any `context_refs` and no `architecture_ref` is stamped.

#### Announce the sizing decision

Say the classification out loud before the plan is read, so the human can override it. The **first
content of `## summary`** — above the problem statement — states the complexity score, the tier,
the resulting stage set, and one clause per added or skipped stage, phrased as a decision the
reader may veto ("…and any of them can be overridden at the plan gate"). The returned handoff
`summary` opens with the same sentence.

An unannounced classification cannot be overridden. `## complexity` and `## stages` are read after
the plan body, by which point the sizing has already shaped everything above them. This rule moves
where the information appears; it does not touch the gate — same single round-trip, same
`decision_gate` behaviour.

#### Stage-task right-sizing

A stage task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's
gate. Fold setup, configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully reject one task while
approving its neighbour.

This is the general form of the TL0 and DV-split tests above, which are phrased in terms of
routing authority and developer count. Where those disagree with the reviewer-gate test they are
the specific case and win; where they are silent — two DV streams over one file set, a doc step
with no deliverable of its own — the reviewer-gate test decides. A task no reviewer could reject
independently is not a task, it is a step inside one.

#### Mid-run escalation channel

The sizing recorded here is the input to a one-way ratchet: a downstream stage that discovers a
surface PL0 could not have seen returns `requests_stage_escalation` in its artifact frontmatter,
and the orchestrator adds the stage through the existing `--task-create` / `--task-block`
operations, recording `{stage, reason}` in `metadata.added_stages`. Nothing downgrades mid-run.

Two consequences for PL0's own writing. First, `skipped_stages[].reason` is the sentence an
escalation must quote and falsify, so write it as a decision about the surface ("no credentials,
tokens, PII, payments, authn, or untrusted input is read, written, or exposed"), never as a
restatement of the score. Second, every stage PL0 declines gets a `skipped_stages` entry — fire
condition 3 has nothing to quote without one. Conditions, caps, and validity are canonical in
`skills/estimation-methodology/SKILL.md § Mid-run re-sizing`, not restated here.


#### Dependency chain & run-index stamping (steps 4–5)

4. **Set dependency chain** between seeded tasks using `state-patch.sh --task-block <ID> --on <ID[,ID…]>`
5. **Mark PL0 completed** after creating all stage tasks

Every seeded downstream stage MUST include `metadata.run_index = N` and `metadata.plan_file = "planning-${N}.md"`. Stage artifact paths embedded in the task description use `<basename>-${N}.md` (e.g., `architecture-${N}.md`, `development-${N}.md`).

#### Agent mapping for `metadata.agent`

Always emit fully-qualified `plugin:agent` form — bare names are not accepted. The prefix follows the owning plugin: `corpflow:` for orchestration/process agents, the detected platform's dev-plugin prefix for platform work. Resolve platform agents from the routing matrix, never memory: entry and functional-role aliases (architect, security auditor, test generator, code fixer) in `skills/shared/routing-matrix.md` — project `CORPFLOW.md § Routing` override wins, and the resolved map persists as `state.routing`; DV specialists in `skills/shared/platform-detection.md`.

##### Stage → agent table

Platform variant = the same role from the detected platform's plugin, per the registry pointers above. Do not hardcode a platform roster here.

| Stage | Default agent | Platform variant |
|-------|---------------|------------------|
| AR0 | `corpflow:software-architector` | that platform's architect |
| TL0 | `corpflow:team-lead` | (same) |
| DV0 | `corpflow:developer` | that platform's entry agent or specialist |
| DR0 | `corpflow:technical-lead` | (same — invokes /tech-code-review) |
| SR0 | `corpflow:security-reviewer` | that platform's security auditor (or `security-scanning:security-scanning-security-auditor`) |
| QA0 | `corpflow:qa-engineer` | (same — may delegate to its test generator) |
| DC0 | `corpflow:technical-writer` | (same) |
| RE0 | `corpflow:release-engineer` | (same) |
| FN0 | `corpflow:project-manager` | (same) |
| ST0 | `corpflow:stakeholder` | (same) |

##### DV0 routing override — plugin worktask-infrastructure

Single source of truth — do NOT duplicate elsewhere. The DV0 default `corpflow:developer` routes *platform app-code*. Route DV to `metadata.agent: "corpflow:workflow-engineer"` (model `opus`, error_file `.context/errors/workflow-engineer.md`) when the change touches **executed** worktask-infrastructure in the plugin tree: `**/*.sh`, `**/*.bats`, `hooks/**`, and the JSON those scripts read. The anchor is that tree, never the extension alone — a product repo's shell or CI script is platform code and keeps the default route (bash → `system-developer` via `corpflow:developer`, per the registry). Platform/app code (Swift, server, web, product source) stays `corpflow:developer` or the `apple-developer:*` variant; a mixed worktask splits DV sub-tasks by scope and routes each independently. `stage-codes.md` keeps the unconditional DV default and points here.

###### Markdown routes by role, never by directory

Prompt prose under `skills/worktask/**` stays with the prompt-asset owner. The one exception is an `.md` that is the normative spec of a script's or the ledger's contract — ledger keys, CLI flags, exit codes — which is infrastructure regardless of extension.

###### Worked example

A `publish-pl-issue.sh` change → DV0 `workflow-engineer`, DR0 `technical-lead`, QA0 `qa-engineer`.

**See**: `skills/worktask/SKILL.md` (full assessment table); `skills/worktask/references/initialization-patterns.md § PL Creates Subsequent Tasks` (code pattern).

**State ledger**: Stage PL, Owner: product-manager. See `skills/shared/state-ledger.md`.

### PL Stage: Automatic Design Detection

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

**Flag gate**: invoke `corpflow:designer` ONLY under `--with-design` (`metadata.with_design == true`) — the keyword score is advisory. Without the flag, skip Designer even for UI apps and note the skip in `## summary`.

Threshold met AND flag set ⇒ `Task(subagent_type: "corpflow:designer")` requesting:
1. UX Assessment, Design Scope, Technical Design, Pencil Mockups, Effort Estimate
2. Mockups saved to `.context/designs/` as `mockup-[feature]-[screen]-[variant].pen`
3. Critical states: default, error, empty, loading

##### Combined Output

`<plan_file>` gets a Design Requirements section: Figma Design References (URLs + node descriptions → `.context/designs/figma-*.png`), Visual Mockups (`.context/designs/mockup-*.pen`), UX, UI Components, Accessibility.

##### Placement guard (non-negotiable)

> **Placement guard (non-negotiable):** persist Figma frames ONLY to `.context/designs/` with a `figma-registry.md` — the artifact QA's design-comparison gate consumes. NEVER write them to `.context/images/` (DV screenshots + user attachments only): a Figma PNG there disables the QA design gate (no `.context/designs/`) and masks an absent DV `screenshots.md`.

### Figma Design Capture

A Figma URL in the task description or user input triggers capture regardless of the keyword design-detection score.

**Trigger** — the task description contains a Figma URL matching:

```
figma\.com/(?:file|design|proto)/([a-zA-Z0-9]+)/([^?]+)(\?node-id=([0-9-]+))?
```

#### Trigger path forms & capture doc

`(?:file|design|proto)` is non-capturing (Group 1 `fileKey`, Group 4 `nodeId`) and must match both the `§ design-preview` trigger and `skills/shared/figma-capture.md § Figma URL Detection` — do not add `/board/` or `/slides/` (`get_metadata` is design-file-only). On trigger, **Read `skills/shared/figma-capture.md`** for the full mechanics (URL detection, auth probe, capture workflow, `figma-registry.md` schema, post-capture plan update, Pencil coexistence). A no-Figma PL run skips that Read.

### PL Stage: Automatic Ethics Gate Detection

PL0 scans the task for high-risk domain signals and inserts ET0 between PL0 and AR0 on threshold (same weighted score as design detection; negative indicators deduct to hold false positives down).

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

Before finalizing a plan draft, scan the task text for a **scope noun with multiple plausible referent domains** ("artifacts", "the system", "the tests"). When competing interpretations map to materially different file sets — swinging the complexity score by more than ~20% — PL0 MUST NOT silently take the broadest reading. Either **(a)** state the chosen interpretation in `## summary` as a vetoable assumption with one-line justification, OR **(b)** ask one clarifying question before drafting when the swing changes the stage set or tier.

## Plan-Gate Open-Question Batching

Every plan-gate question is a closing-sweep item like any other stage's: a full `SweepItem` under
`## elicitation-sweep` (`id: sw-PL<N>-<n>`, `class`, 2–4 `options[]` with exactly one
`recommended: true`, one-line `rationale`), with its stub in both `handoff.open_questions[]` and the
PL `--facts` payload. `## summary` keeps only a one-line-per-item preview so the reader meets the
questions before the plan body; the option bodies live under the anchor, never duplicated.

At most **4** items per stage — the ask tool's per-call ceiling. A surplus defers to a later round
per § Dependency ordering rather than spilling into a second call. Surface the batch in a single
gate round-trip and apply the user's amendments in one batch pass before marking PL0 complete — not
one PL resume per answer.

### Facts are PL0's job; decisions are the user's

A candidate question is a **fact** when some artifact already holds its answer — the filesystem, git
history, a manifest, a lint's exit code, `gh`, or any tool PL0 can run. Facts never reach the plan
gate: PL0 resolves them itself and records the resolved value in the plan, marked verified. A
candidate is a **decision** only when the answer turns on what the user *wants* rather than on what
is *true*. `open_questions[]` may carry decisions only. This rule is not PL-specific: every stage's closing sweep is bound by it (`skills/shared/stage-contracts.md § Closing Elicitation Sweep`, which points back here rather than restating it).

Apply the test to every candidate before writing it down: name the command, file, or tool that would
answer it. If you can name one, delete the question and run it. Worked example and its assertions:
`skills/worktask/references/fixtures/plan-gate-questions/01-facts-only-zero-questions.md`.

#### Cost is not an exemption

When the lookup is slow or wide — a repo-wide sweep, a cross-plugin check, a `gh` query over many
issues — dispatch a subagent to perform it and wait for the result. Expense promotes a fact to
delegated work, never to a gate item. "I did not look" and "the user must choose" are different
states, and only the second one belongs in front of a human.

A fact surfaced as a question costs a full gate round-trip and returns an answer PL0 could have had
for one tool call — and the user, lacking the repository in context, often answers it wrong.

### Dependency ordering across gate rounds

A question whose answer depends on another still-open question is **deferred to a later round**, not
batched beside it. Batching a dependent pair forces the user to answer the second question under
every branch of the first, which is how a gate list grows conditional sub-clauses nobody can answer
cleanly.

Emit only the independent questions this round. Record each deferred question in the plan text next
to the question it waits on, so the reader can see that a second list exists and why it is not in
front of them. After the batch pass applies the answers, re-evaluate every deferred question: the
answer usually resolves it outright — often into a fact, which is then PL0's to look up — and only
what survives becomes a second round.

### Assumption tagging for plan-shaping questions

A question whose answer would change the plan's *shape* — scope boundary, stage set, or target
file set — cannot wait for the gate, because the plan is written against some answer either way.
Write the plan against the stated recommended default and mark every section that answer would
invalidate with an inline `assumes qN` tag, so the reader sees each answer's blast radius before
answering it.

The gate itself is unchanged: same single round-trip, same batching rule, same `decision_gate`
behaviour. The tag is what turns an unvalidated assumption into a visible one — an untagged plan
built on a default reads as settled, and the reviewer approves the default without knowing they
did. A question whose answer invalidates no section needs no tag: it is not plan-shaping, and it
belongs in the ordinary numbered list above.


### Auto-decision path (`decision_gate: "auto"`)

Under `PL0.metadata.decision_gate == "auto"` (stamped by `--auto=[decision]`), do NOT hold the gate
round-trip: build the same numbered list with recommended defaults, return it in the typed
handoff's `open_questions[]`, and mark PL0 complete. The orchestrator's Step A.4 pre-pass
(`commands/worktask.md`) re-dispatches this agent as a **decision delegate on the Fable model** to
answer them.

#### Decision-delegate turn

Decide each question default-biased (deviate only with stated evidence) and apply the amendments
to the plan's EXISTING mandatory anchors (`## requirements` / `## acceptance-criteria` /
`## scope`) in ONE batch pass. Never add a `## decisions` anchor to `<plan_file>`, whose anchor set
is exact (`handoff-protocol.md#anchor-allow-list § PL`; `## decisions` belongs to AR's
`architecture-N.md`). Return every decision as a `key_decisions[]` entry prefixed
`(auto-decided)`; the orchestrator marks each answered `state.json facts.open_questions[]` item
`status: "resolved"` with its `resolution` — never deletes it, and never also appends it to
`facts.decisions[]` — and carries each rationale in its `auto_decision_resolved` audit row. Do NOT re-run `state-patch.sh` — PL0 is already `completed`,
so the plan amendments are your only writes.

#### Escalation-class questions (never auto-decided)

**Never auto-decide** irreversible or destructive actions, scope expansion beyond the task
description, security-posture-weakening changes, or spend authorization — return those as
`escalate` items. The orchestrator stops for the user on exactly those, even under
`plan_gate: "bypass"`; an unattended `/megatask` per-issue run parks the issue instead
(`commands/worktask.md § Step A.4 Escalation guard`).

## Version Bump Planning

When a worktask includes a version bump (release, tag, or `version:`/`CHANGELOG`/`MEMORY.md` change), run a **version-ordering check** before recommending a version in `<plan_file>`:

1. `max_released_version` = greater of the highest git tag (`git tag --list --sort=-v:refname | head -n1`, strip `v`) and the max `MEMORY.md` release-history entry.
2. Compare the proposed version by semver ordering.
3. **If `proposed_version < max_released_version`** (a regression): surface a **"Version ordering regression"** item in `## risks` naming both versions (`proposed 3.24.2 < released 3.25.0`) and **ask the user to confirm intent** before downstream stages, quoting the confirmation in the plan rationale. Non-blocking surface-and-confirm — an out-of-order bump is acceptable but MUST be visible at plan time. DC repeats this check as a second gate before FN commits.

## Completion Verification

### Verification Checklist Authoring

When writing grep-based verification steps in `<plan_file>` (e.g. AC validation commands):

- DO NOT use substring grep patterns; always use word-boundary anchors (`\b`) or full filename matches, or they false-positive against legitimate canonical names.
- DO NOT write an AC verification command into `<plan_file>` without executing it once against
  current repo state and recording its literal output (or, if it can only run post-edit, marking
  it inline `(unverified — dry-run required after theme lands)`). Naive `awk`/`grep`/`wc` forms
  break silently on folded YAML blocks, meta-index files, and other idiosyncrasies that surface
  only when run — catching that at PL0 is cheaper than a DR/QA re-diagnosis mid-pipeline.

#### The `(unverified)` mark never excuses an invalid command

That escape hatch covers **only** the representativeness of the RESULT (present-state data cannot
show the post-edit answer). It never covers the command's **validity**: before writing one, run it
against present-state data and confirm it executes without a usage/syntax error, on a plausible
input, with each flag doing what the prose claims.

A broken flag combination is a shipped defect, not an unverified one — `grep -viv -e A -e B`
(triple negation) reports everything "clean" and passes silently, and three downstream stages then
re-derive the correct form. If nothing can run before the edit, simplify until some form can.

#### Per-theme residual-grep completeness gate (REQUIRED)

An enumerated edit-file list goes stale: the repo evolves between plan authoring and DV execution, so files matching a theme's pattern appear that the list never named. Every enumerated file list is a **starting set**, not the known universe — the completeness gate is a repo-wide grep.

For **each edit theme** in `<plan_file>`, the acceptance criteria MUST include at least one repo-wide grep/verification command (a residual-grep) finding every live occurrence the theme must cover, listed as an **AC verification command** so DV can self-verify completeness without orchestrator rescue:

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

DV runs each theme's residual-grep before yielding (`agents/workflow-engineer.md § Batch-Completion Discipline`); a non-empty result means the theme is incomplete regardless of how many enumerated files were edited.

##### `file:line` citations are starting sets too

The same staleness applies to any `file:line` reference in a theme's prose (e.g. carried over from an exploration pass). Cite it as an **approximate locator** — "near line N as of planning time" — and require DV to re-locate the real anchor before editing: a function/section boundary, or a grep for the quoted text. By execution time the line number is never authoritative; the quoted text is.

##### PL0 completion checklist

Before marking PL0 complete, verify:
- [ ] Version bump in scope ⇒ version-ordering check ran; any `proposed_version < max_released_version` regression surfaced in `## risks` and user-confirmed
- [ ] `<plan_file>` written at the next free N — on a `plan_revision` turn, rewritten in place at the frozen N with `facts.*` preserved
- [ ] `<plan_file>` contains all acceptance criteria
- [ ] Test strategy section present with specific test scenarios and file paths
- [ ] Test effort estimate included (required, not optional)
- [ ] Complexity score calculated (0-50)
- [ ] Stage tasks created with `metadata.agent`, `metadata.model`, `metadata.effort`, `metadata.plan_file`, AND `metadata.run_index = N`
- [ ] Dependency chain set between created tasks
- [ ] No open questions blocking next stage

##### PL0 completion checklist — design & Figma items

- [ ] Design detected (score ≥ 5) ⇒ Designer invoked
- [ ] Figma URL detected ⇒ screenshots captured AND persisted (verified non-zero PNGs) to `.context/designs/figma-*.png`
- [ ] Container node captured ⇒ one overview PNG + one PNG per child frame persisted, one registry row each (REQ-A/REQ-B)
- [ ] Figma URL detected ⇒ per-frame design context summarized in `<plan_file> § Figma Design References` (one bullet per frame), and `§ design-preview` lists each persisted per-frame file with state mapping + build notes (REQ-D)

## Handoff Protocol

Inputs (anchor-first), completion checklist, run-index resolver, atomic-write rules: `skills/shared/stage-contracts.md` — reference only; this section is self-sufficient, so do not Read it in the steady path. Per-stage frontmatter template (paste verbatim at artifact top): `stage-contracts.md#tpl-pl`. Prev→this label: `USER→PL`.

### State Patch — REQUIRED before return

Run `state-patch.sh --stage PL --prev USER` (`skills/worktask/scripts/`) to atomically patch `tasks.PL0` + the `USER→PL` edge into `.context/state.json` from this artifact's `handoff:` frontmatter summary. Put the one-line goal (verb + object, ≤120 chars) in that summary — downstream stages read it as the worktask goal alongside `planning-N.md#requirements`. Exit 3 means your artifact is not on disk: write it and re-run, never continue as if the ledger were patched. If the tool cannot run at all, do NOT skip silently — apply the Edit-direct fallback in `handoff-protocol.md#layer-1-fallback`, which writes the `handoffs` edge the hook cannot.

#### Union this stage's facts in the same call

Pass `--facts` in the **same call** to union this stage's compressed facts into `state.json → facts.*` — the channel `stage-contracts.md` tells every downstream stage to read first, and its only scripted writer. PL owns both `key_decisions` and the `open_questions[]` a `--auto=[decision]` delegate later resolves:

```bash
state-patch.sh --stage PL --prev USER --facts '{
  "decisions": [{"id":"pl-1","summary":"≤160 chars","ref":"planning-0.md#stages"}],
  "open_questions": [{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep","blocks_next_stage":false}]}'
```

Union by `.id` (last writer wins, newest at the tail): never clobbers an upstream stage's entries, and a re-run is byte-identical. Omitting it loses the fact silently. Canonical rule: `handoff-protocol.md#facts-union`.

Stage-task seeding uses the same `state-patch.sh` grant and shares this fallback ladder — there is
no separate task tool to fall back to.

#### State Patch — `facts.goal` is part of the contract

`facts.goal` MUST be non-empty in `.context/state.json` when PL returns. The orchestrator seeds it from the task description at Step 3a, so the normal job here is to REFINE it to the one-line goal above — but verify it, and write it if the seed is missing (`jq '.facts.goal = "<goal>"'` through the same atomic temp+rename). Not bookkeeping: `publish-pl-issue.sh` reads it as the first rank of both the issue title and the `## Summary` chain, and its absence produced a kebab-slug title with an empty Summary in issue #375. Also write a `title:` line into the plan's frontmatter — the chain's next rank, and the plan's own record of what it is about.
