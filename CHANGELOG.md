# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [3.37.2] - 2026-07-29

Visual evidence reaches the PR again. Min CC unchanged at **2.1.220**.

Found by running a worktask against an **internal** repo: DV captured screenshots, the completion gate passed on file presence, and the PR shipped with no evidence and no warning. Three compounding defects.

### Fixed

- **The gist tier could never host an image, on any repo.** `gh gist create` rejects binary content outright (`binary file not supported` — the gists API is UTF-8 only), yet `select_host_tier` documented it as *"the EFFECTIVE PRIMARY tier for PRIVATE/INTERNAL repos"*. `host_one_asset` now detects binary input and fails fast instead of burning a guaranteed-failure round-trip, and the false primary-tier claim is corrected. The guard sits **ahead of** the mock/dry-run short-circuits deliberately: a dry run that reports a working embed for a binary is lying about the one thing being dry-run — that exact behaviour masked this bug during diagnosis.
- **A non-conforming manifest was indistinguishable from "no screenshots taken."** `parse_manifest` requires the canonical 9-column table with a **two-digit** index (`01`, not `1`); any other shape yields zero rows, which was audited as `reason:"no_captures"` — the same path as a run that captured nothing. New `manifest_diagnosis()` reports `manifest_unparseable` when a manifest exists *and* image files sit beside it, and warns on stderr with the expected schema and a pointer to `skills/dv-screenshot-capture/references/examples/README.md`. Silent evidence loss becomes a loud, actionable failure.
- **Gist visibility defaulted to public even on closed repos.** `ASSET_GIST_PUBLIC` is now tri-state — `1` forces public, `0` forces secret/unlisted, and **empty (the default) derives from repo visibility** via `gist_public_effective()`: PRIVATE/INTERNAL → secret, PUBLIC/unknown → public. Both gist kinds are anonymously fetchable (camo requires it), so on a closed repo `--public` cannot improve rendering — it only adds search indexing and a listing on the author's public gist profile. This narrows discoverability; it does not make the bytes confidential, and the AC1 privacy note now says so plainly and points at `ASSET_HOST_MODE=none` for material that must not leave the org.
- **Degradation messages are actionable.** The generic `inline hosting unavailable` bullet read like a transient blip rather than a structural impossibility; the reason is now stated once per block (not repeated per capture) and names the remedy.

### Added

- **Tier-0 user-attachments is LIVE**, via the [`drogers0/gh-image`](https://github.com/drogers0/gh-image) extension. The q1 spike's finding stands — a PAT still cannot authenticate `POST github.com/upload/policies/assets` — but that extension supplies the browser `_gh_sess` session token the flow needs, and prints `![base](url)`. This is the **only** tier that clears all three bars at once: it renders on PRIVATE/INTERNAL repos (GitHub rewrites the asset to `private-user-images.githubusercontent.com` with a short-lived scoped JWT), it accepts **binaries**, and it commits nothing to the repository. Selected automatically whenever `gh image check-token` succeeds; pin with `ASSET_GH_IMAGE=1/0`. Never a hard dependency — an absent extension or stale token falls through to the tiers below. Because both entry points share `host_one_asset`, this serves the PL-stage design assets → issue path and the DV captures → PR/issue path at once.
- Dry-run for tier-0 probes `check-token` (read-only) before claiming success, so it cannot report embeds an uploader isn't there to produce.

### Changed

- Self-tests **37 → 38 pass, 0 fail**. Three added: `12a0` (tier-0 live upload + URL extraction + degradation on unusable output), `12a2` (gist visibility auto-derivation across PRIVATE/INTERNAL/PUBLIC/unknown), `12a3` (gist binary refusal without invoking `gh`). Two existing tests encoded assumptions this release invalidates and were repaired: `11b` would have performed a **real upload** on any machine with `gh image` installed (now stubs `GH_BIN`), and `11c`/`11d`/`12c` now pin `ASSET_GH_IMAGE=0` so they keep exercising raw/gist selection instead of short-circuiting to tier-0.

## [3.37.1] - 2026-07-28

Model-name sweep. Min CC unchanged at **2.1.220**.

### Changed

- **No `Opus 4.x` or `Sonnet 4.x` string remains outside this file.** Live guidance substitutes directly to Opus 5 / Sonnet 5: the 1M-window gating sentences (`commands/context-status.md`, `skills/worktask/SKILL.md`, `context-compression/SKILL.md`), the `xhigh` routing rule (now **Opus 5 or Fable 5**), the `stage-codes.md` example model id, the `--fallback-model` example, and `/optimize-agent`'s reject-example.
- **Dated version-table rows are de-named rather than re-dated.** A row keyed to CC 2.1.75 cannot truthfully name a model that shipped ~145 releases later, so `token-baselines.md` rows 36/44/117/139/140/148 drop the model name and keep the subject — `1M context window on the top Opus | 2.1.75`, `Fast mode (/fast) defaults to the top Opus | 2.1.154`, and so on. Same treatment for the `MEMORY.md` band-index row (`v3.10.13 (top-Opus refresh)`).
- **`model-selection.md § Prior Opus models` deleted.** Its entire subject was naming superseded models. The operational rule it carried survives as `#### Prefer the alias over a pinned id`. The Bedrock/Vertex/Foundry note now says those providers default to "the newest Opus they carry" instead of naming one.

### Fixed

- **Benchmark SSOT repinned** — `benchmark/harness/benchmarklive/dispatch.py` `STAGE_TABLE` moves to `claude-opus-5` (PL, AR, DV, DR, SR) and `claude-sonnet-5` (TL, QA, FN, ST); `claude-haiku-4-5` is current and unchanged. `skills/agent-coordination/references/headless-dispatch.md` moves in lockstep so its parity claim stays true, and its alias note is rewritten: the pins now *coincide* with what the aliases resolve to, which is timing rather than a guarantee. Verified test-safe — `test_stage_table_ssot.py` asserts only the model **family** (`m.split("-")[1]`), no stored result file pins an id, and `benchmarklive/budget.py` keys on tier strings, not ids.
- `benchmark/README.md` gains a **Baseline cut-over (v3.37.1)** section: runs from this version are not comparable to the stored `results/history.json`, `results/analysis.md`, and `results/token-findings-*.md` baselines, which were measured on the prior pins.

## [3.37.0] - 2026-07-28

Claude Code **2.1.216→2.1.220** integration. Min CC → **2.1.220**.

### Changed

- **Nested-delegation budget corrected from 5 levels to 3.** CC 2.1.217 disabled nested subagent spawning by default; 2.1.219 restored it at **depth 3** (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; `=1` disables). The plugin asserted a 5-level budget in seven places, all of which were wrong for the whole band. Depth is counted from the session root, so the canonical DV chain (session → `developer` → platform router → Tier-2 specialist) sits exactly on the default ceiling. Corrected in `agent-coordination/SKILL.md`, `agent-coordination/references/hook-monitoring.md`, `worktask/references/resume.md`, `worktask/SKILL.md`, `commands/cost-report.md`.
- **`/megatask` spends one depth level before any stage runs**, because Phase 2 Step 3 dispatches a per-issue `/worktask` orchestrator as its own sub-agent — putting that same DV chain at depth 4, one past the default, where the Tier-2 specialist is simply never spawned. `skills/megatask/SKILL.md § Nesting-depth budget` documents the level-by-level arithmetic and both remediations (raise the env var — preferred, preserves routing; or flatten Tier-2 dispatch). The R1 gate now presents the projected max depth and the peak-concurrent projection alongside the existing total-spawn estimate.
- **Three independent spawn ceilings documented in one place** (`agent-coordination/SKILL.md § Three independent ceilings`): depth 3 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), **20 concurrent** (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, new in 2.1.217), and 200 total per session (`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`). The concurrent cap is the one background-by-default dispatch makes easy to hit; `parallel_tracks` derivation now bounds itself against it.
- **`skills/shared/model-selection.md` rewritten around Opus 5.** `claude-opus-5` is the default Opus — the `opus` alias resolves there — with 1M context carrying **no usage-credit gate** and fast mode at $10/$50 per Mtok. The four Opus-4.8-titled sections collapse into the Opus 5 section plus one `### Prior Opus models` note; `/fast` now covers Opus 5 and 4.8 (4.7 removed). The `xhigh` routing rule reads **Opus 5, Opus 4.8, or Fable 5** across `model-selection.md`, `stage-codes.md`, and `commands/optimize-agent.md`.
- Opus 5's ungated 1M window makes the extended handoff column unconditional for opus-tier stages (`context-compression/SKILL.md`) and gives the fable-credit-block fallback in worktask Step 5f a landing spot that keeps both the `xhigh` tier and the extended context.

### Added

- **Budget-halt resume branch** (`worktask/references/resume.md`): `--max-budget-usd` now halts *running* background subagents, not just new spawns, so healthy in-flight stages die together at one timestamp with no per-stage failure row. Classified as a budget halt rather than a stage failure — re-dispatch without incrementing `metadata.retry_count`, since those 3 retries are reserved for genuine failures.
- **Workspace-trust precondition on agent-frontmatter hooks** (`agent-coordination/references/hook-monitoring.md`): frontmatter `hooks:` run only when the agent file's own folder has accepted workspace trust; otherwise they are **silently skipped**. `product-manager`, `project-manager`, and `stakeholder` declare them. Absence of a hook-emitted audit row is therefore not evidence the hook passed. Mirrored as a `/optimize-agent` audit rule.
- **Git isolation is runtime-enforced** (`agent-coordination/SKILL.md`, `shared/milestone-helpers/SKILL.md`): a worktree-isolated subagent can no longer redirect git at the shared checkout via `git -C`, `--git-dir`, `GIT_DIR`, or `GIT_WORK_TREE`. The milestone `git -C .worktrees/…` table is marked orchestrator-side only — the inverse direction is still allowed.
- `DirectoryAdded` hook event; `mcp_server_errors` in the headless stream-json init event; nested-subagent stream forwarding at depth 2+ under `--forward-subagent-text`, keyed by the spawning Agent `tool_use` id (`headless-dispatch.md`, `benchmark/README.md`).
- Claude Code sandbox & path settings section in `security-review-process/SKILL.md`: `sandbox.network.strictAllowlist`, `sandbox.filesystem.disabled`, `.claude`-symlink and `/rewind` hardening, managed-MCP `${VAR}` resolution scope.
- Frontmatter audit rules for boolean spellings (`yes`/`no`/`on`/`off`/`1`/`0`) and `context: fork` skills running in the background by default (`background: false` opts out). Agent `name` containing `:` is now a P0 — CC rejects the file.
- `token-baselines.md` gains a `v2.1.216–2.1.220` band table.

### Fixed

- A resumed background agent restores its own prompt and tool restrictions instead of reverting to the default agent, so a reattached stage row is still that stage's agent — `resume.md` now prefers reattach over defensive re-dispatch on identity grounds.
- Stale model id `claude-opus-4-5` in `cross-plugin-handoff/references/plugin-protocols.md`. The pinned ids in `headless-dispatch.md` are deliberately left alone (benchmark-parity snapshots against the live-dispatch `STAGE_TABLE`); the alias note now covers Opus 5 the same way it covered Sonnet 5, and states that re-pinning the SSOT invalidates stored baselines.
- `context-compression` trigger table distinguishes the credit-gated 1M case (Fable 5) from Opus 5's ungated window, and gains a context-overflow row now that `/context` warns explicitly and a failed `/compact` renders as an error.
- `/reload-plugins` note clarifies that mid-session slash-menu pickup of changed skills does **not** relax the version-keyed cache rule for installed consumers.

## [3.36.2] - 2026-07-27

### Added

- **FN body-composition gate — `fn-preflight.sh pr-body`** (REQ-4, REQ-5): a new subcommand that proves the composed PR body came out of the mandated pipeline rather than being hand-authored.
  - Sanitises the body **in place** by sourcing `publish-pl-issue.sh` under `PUBLISH_LIB_ONLY=1` and reusing its `sanitise_body` verbatim — no new or altered strip rules, so issue bodies and PR bodies strip identically. The pre-sanitise text is snapshotted to `.context/logs/pr-body-<run_index>.presanitise.md`.
  - Requires a `Test plan` heading (ATX, any level, case-insensitive).
  - On a `requires_screenshots` run, requires the `visual_evidence_pr_emitted` audit row for the **current** run index, matched on its full dedupe key so a row from an earlier run cannot satisfy the gate — and, when that row reports `result: "ok"`, a `## Visual evidence` section in the body.
  - Inserted into `all` **before** `validate-pr`, so the body whose `Closes #<n>` line is validated is byte-identical to the body that reaches `gh pr create`.
  - An unreachable sanitiser library is a blocking failure (exit 1), not a silent degrade; the diagnostic names the exact missing path.
- **Branch rename — `fn-preflight.sh branch-name`** (REQ-7): moves an anonymous worktree branch onto `<type>/<ticket>-<slug>`. Idempotent (a second run is a no-op), and a no-op on an already-conventional name, on an upstream-tracked branch, and on the integration branch itself. Deliberately **not** part of `all`, which runs after the push — it is called between pre-flight and push.
- **Batch/incident self-scoping** (REQ-6): both new subcommands begin with `fn_batch_scope`, a local five-signal mirror of `publish-pl-issue.sh`'s `is_milestone_mode` (`MILESTONE_MODE`, `INCIDENT_MODE`, `metadata.milestone`, a `stages.IR` entry, a `workspace.json` record). It depends on nothing but `jq` and the filesystem, so an unreachable library cannot fail the guard that exempts `/megatask` and `--emergency` from the fail-closed sanitiser. Those pipelines keep their behaviour byte-for-byte.
- New audit actions: `pr_body_gate` (`ok`/`blocked`/`skipped`), `pr_body_sanitised` (`ok`/`unchanged`), `branch_renamed` (`ok`/`noop`/`failed`/`skipped`).

### Fixed

- **`fn-preflight.sh continuity` no longer hardcodes `main`** (REQ-11): the `.git.base_branch // "main"` read and its re-default are replaced by one `resolve_base_ref` order — `$FN_BASE_REF`, `state.json .metadata.base_ref`, `state.json .git.base_branch`, `workspace.json .git.base_branch`, `git symbolic-ref refs/remotes/origin/HEAD`, then **unresolved**. There is no literal fallback: in a `master` repository the old default compared against a branch that did not exist, silently degrading the check to a no-op. An unresolved base now emits a `branch_continuity` `base_ref_unresolved` row and skips explicitly. A companion `resolve_git_ref` maps both the bare (`master`) and remote-qualified (`origin/release/v2`) stored shapes onto a ref git can resolve.
- **`publish-pl-issue.sh` resolves a bare-basename plan path** (REQ-1): when `state.json.plan_file` holds a basename rather than a workspace-relative path, the helper now retries it against the directory holding the state file — the same fallback `ISSUE_ANCHOR` already performed. A shape mismatch previously killed automatic GitHub issue creation silently.
- **`publish-pl-issue.sh` fatal path prints a diagnostic** (REQ-3): `fatal()` emitted only a machine-readable audit row. It now writes the reason plus an optional detail to stderr; the plan-readability check names every candidate path it tried.

### Changed

- **`plan_file` shape boundary documented** (REQ-2): `state.json.plan_file` holds a workspace-relative path, `task.metadata.plan_file` holds a bare basename. Both shapes stay legal; the boundary is now stated at the canonical schema site (`handoff-protocol.md`) and pointed at from `commands/worktask.md`, `agents/product-manager.md` (state reset, propagation table, notation), `publish-pl-issue.sh`, and `conductor-attachments.md`.
- **Integration-branch detection at PL0** (REQ-8): PL0 detects the branch once (`origin/HEAD` → `workspace.json` → `master`), stamps `task.metadata.base_ref` on itself and every downstream task when the branch is not `master`, and mirrors it to `state.json .metadata.base_ref` unconditionally — the only channel a shell helper can read.
- `conductor-attachments.md` now sources the conventional-commit type from `state.json § facts.goal`; the previously documented `.context/<plan_file> § Goal` anchor is emitted by no plan template.
- `agents/developer.md` names `task.metadata.base_ref` authoritative over the session-level `worktree.baseRef` (documentation only; no behaviour change).

### Tests

- `tests/shell/worktask/fn-preflight.bats`: 12 → 39 cases (`pr-body` sanitising/heading/visual-evidence/scope matrix, sanitiser-unavailable, `all` ordering, dedupe-key producer↔consumer parity, base-ref resolution ranks, `branch-name` guard ladder and idempotency).
- `tests/shell/worktask/publish-pl-issue.bats`: 7 → 9 cases (bare-basename plan resolution; absent plan naming both candidates on stderr).

## [3.36.1] - 2026-07-27

### Added

- **Test-selection grammar clarification (Apple platforms)**:
  - Apple test identifiers are now explicitly documented as **suite-terminal** — end at a type name, never per-function. Swift Testing's `@Test` function identifiers carry parentheses (`testFoo()`) and parameterized variants append a per-argument suffix, making the three-segment `Target/Type/method` form match zero tests and silently degrade to a full-suite run.
  - Nested `@Suite` types legitimately yield three segments; the rule is suite-terminal, not two-segment.
  - Added cross-repo divergence note: upstream apple-developer plugin still documents per-function grammar — this divergence will be resolved in a follow-up.

- **DV dispatch test-scope enforcement**:
  - New Step 4.8a in `skills/worktask/SKILL.md` mirrors the structure of Step 4.8, injecting test-scope enforcement into the composed DV prompt surface.
  - `dv_test_scope_enforced` audit row makes the three enforcement layers observable (prohibition in constraints, banner in the loop, metric in the dispatch).
  - New advisory reader in `agents/technical-lead.md` § Test-Scope Check (before Visual Evidence Review) — never `verdict: fail`, documents the stale-cache rationale for deferring hard-gate enforcement.

- **Flake classification: `environmental_contention`**:
  - New classification added to `skills/agent-coordination/SKILL.md` § Error Documentation enum and retry/escalate matrix.
  - Signals resource contention (CPU/memory/IO thrashing on a loaded machine), not a defect. QA handles by re-baselining once on a quiet machine with a note in `testing-N.md § Notes` — no escalation.
  - If the re-baseline fails with the same failing members, the classification is void; reclassify as `logic` and escalate normally.

- **Context-compression wiring**:
  - Skill `igrsoft:context-compression` integrated into DR and QA agent prompts as a reference for output-budget strategies.
  - Helps coordinate cross-agent token usage when dispatch artifact budgets are tight.

- **Audit-only test-run counters**:
  - `full_test_run` and `scoped_test_run` counters added — keyed on invocation shape, audit-only, never a gate.
  - Both appear in stage agents' dispatch records; neither influences completion checklists or verdict.
  - Invocation shape is deterministic: `scoped_test_run` when carrying ≥1 `-only-testing:` flag; `full_test_run` when carrying none.

### Changed

- **Test-selection documentation alignment**: `agents/product-manager.md` scope-table now shows `<TargetName>/<SuiteName>` format for `always_required_tests` (suite-terminal, no per-function entries).
- **Testing strategy — Selected Tests granularity**: `skills/shared/testing-strategy.md` now clarifies suite collapse at the flag layer ("one per owning suite, deduplicated") with per-function examples in the schema for reference.

### Known Divergences

- **Apple test identifiers**: This release documents suite-terminal grammar (Swift Testing `@Test` parentheses prevent per-function matching). The upstream `apple-developer` plugin (sourced in separate follow-up worktask) still documents per-function form. Readers hitting both contracts should use suite-terminal; the upstream will converge in a follow-up.

---

## [3.36.0] - 2026-07-22

### Added

- **Benchmark harness improvements (Track 1)**:
  - Layer-1 capture persistence with `persist_capture()` — writes raw stage stdout before parsing with 25MB truncation and byte-stable defaults
  - Coverage attribution — deterministic `--agent` binding, nested spawns deduped from canonical audit rows, injectable clock
  - DV file-landing tripwire (`dv_file_gate()`) stops doomed spend before costly operations
  - Generated-project output sections in analysis Markdown and HTML reports (per-arm Swift file tree, LOC, arm folder path)
  
- **Paired ±agent benchmark runner (Track 1, amendments U3–U5)**:
  - Symmetric `with/` and `without/` arm folders with isolated cwd and stage contexts per arm
  - Both arms execute identical 10-stage prompt sequence (pl→ar→tl→dv→dr→sr→qa→dc→fn→st)
  - Per-call input/output token accounting persisted in run records and analysis reports
  - Prompt-surface neutralization (plugin-specific agent IDs and commands removed for fairness)
  
- **Deny-list enforcement (Track 1)**:
  - New `benchmark-settings.json` with deny-list for `git push`, `gh`, `curl`, `wget`, `WebFetch`, `WebSearch`
  - Applied to both WITH and WITHOUT arms for safety

- **Worktask infrastructure (Track 2, Phase 2.0)**:
  - `state-patch.sh --prev <CODE>` flag for atomic handoff-summary merge (additive, no breaking change)
  - `fn-preflight.sh` validator extracted from agent prose (new `validators.sh` entry point)
  
- **Governance & bounds (Track 2, Phases 2.1–3; Track 3)**:
  - Schema bounds enforcement: `facts.decisions` ≤ 8, `facts.dispatched_agents` ≤ 6
  - Subagents governance: `subagents_spawned` maxItems 5, no background nested in headless mode
  - Output-budget blocks in 6 agents (DR, PL, FN, QA, DV, AR)
  
- **Progressive-disclosure reference files (Track 2, Phase 4)**:
  - `skills/worktask/references/visual-qa.md` — QA design-comparison procedure
  - `skills/shared/platform-detection.md` — platform specialization routing
  - `skills/worktask/references/workspace-modes.md` — worktree mode detection and isolation rules

### Changed

- **Effort and model right-sizing (Track 2, Phase 1)**:
  - AR effort: `xhigh` → `high` (cost optimization)
  - ST effort: (no change) → `low` (alignment)
  - FN model: (no change) → `sonnet` (cost optimization; SSOT sync with stage-codes.md)
  - QA, DV, DR reconciled to STAGE_TABLE (medium, high, high)
  
- **Boilerplate dedup & section diet (Track 2, Phases 2–5)**:
  - 13 agents: inline jq `state-merge` blocks → `state-patch.sh --stage <CODE> --prev <PREV>` pointer (eliminates jq drift, sync hazard)
  - Handoff-preamble merge: duplicate expansion text collapsed to single copy (save ~1KB per agent)
  - Diff-Only Read Rule: centralized rule definition in `stage-contracts.md`, agents point via reference
  - Section-lint debt: 15 over-cap sections → 0 (all agents ≤ 1000 chars per section)
  - Plugin prose diet: agents/ byte reduction 283,888 → 245,987 B
  
- **Worktask Integration section (Track 2, Phase 4)** — Progressive-disclosure for complex topics:
  - `qa-engineer.md`: visual-comparison details → `visual-qa.md`
  - `developer.md`: platform-detection routing → `platform-detection.md`
  - `product-manager.md`, `technical-lead.md`, `project-manager.md`: streamlined with reference links
  
- **FN reader circuit (Track 3, B4)**:
  - Frontmatter-first reads (limit: 30 chars), deep-read only on anchor-miss/flagged verdict/retry
  - Added `deep_reads: []` optional array for audit trail

- **DV Validation cell (Track 3, B1)**:
  - DV stage-contracts row now includes file-landing check guidance

### Fixed

- **Permission mode (Track 1, A1)**:
  - Fixed `bypassPermissions` constant in `dispatch.py` and `baseline.py` (no cross-import, frozen-seam degrade when settings absent)
  - `--settings <benchmark-settings.json>` threaded into both arm argvs
  
- **Stale model cells (Track 2, Phase 1)**:
  - Removed 5 pre-existing fable/placeholder cells in stage-contracts model tables
  - Harmonized all STAGE_TABLE + stage-codes.md model references to SSOT single source

### Security

- Deny-list enforcement prevents accidental spend/network calls in benchmark harness (both arms)
- `bypassPermissions` mode with deny-list in settings file for transparent safety validation
- **SR-M1 fail-closed**: live dispatch now raises `BenchmarkSettingsMissing` before any `claude -p` call when `benchmark-settings.json` is absent, instead of silently dropping the deny-list under `bypassPermissions`.

### Known Considerations

- **SR-M1 resolved**: the prior fail-open frozen-seam degrade is now fail-closed (`require_settings` guard); a missing `benchmark-settings.json` refuses to dispatch rather than running with no deny-list.

---

## [3.35.0] - 2026-07-09

### Added

- MCP auto-background await protocol integration
- Worktree-lock sweep for orphaned artifact cleanup
- Background-agent guarantees (200-spawn cap guidance)
- SendMessage-replay dedup for cross-session resume
- `agents --json` "Needs input" resume branch

### Changed

- Removed all pre-2.1.215 conditional/degrade branches (Claude Code 2.1.215+ required)
- Version-gate cleanup: consolidated CC feature detection to OTEL additions only
- Plugin minimum version now pinned to CC 2.1.215

---

**[Older versions archived in git history; view via `git log --grep="v3\\."`]**
