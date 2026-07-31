# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [3.41.2] - 2026-07-31

Shell was the one gap in the comment-enforcement hooks: both the blocking density gate and the
per-edit reminder hook gated on a file-extension allow-list that omitted `sh`/`bash`, so the
repo's dominant language — every piece of worktask infrastructure under `hooks/` and `tests/` is
bash — was structurally invisible to both. `hooks/test-execution-gate.sh` is 327 of 773
non-blank-and-non-comment-skipped lines of comment, measured the way the gate itself measures
(blank lines excluded, per `hooks/dv-comment-density-gate.sh` lines 111/123): **42 percent**,
above the 40 percent ceiling, and it would never have been measured before this change. Suite
green: both `--self-test` suites exit 0 (9 density-gate cases), the vendored `hooks/` bats module
is 106/106, and `shellcheck` holds at the single pre-existing SC2016 baseline.

### Added

- **Shell coverage for both comment-enforcement hooks.** `hooks/dv-comment-density-gate.sh` and
  `hooks/comment-standard-context.sh` now accept `sh`/`bash` in their source-extension allow-lists,
  and the density gate's `comment_style_for` routes shell files through the existing `hash`
  comment-style arm instead of falling through to the C-family default that scored them at
  effectively zero. The density gate's self-test gains a bloated- and a lean-shell fixture pair
  (mirroring the existing hash-language pair, the lean fixture carrying a realistic shebang and
  header so it does not understate real shell density) plus a vendor-exclusion case with a control
  arm; the reminder hook's self-test gains a shell first-touch injection case. A new
  `tests/shell/hooks/comment-hooks-self-test.bats` wraps both hooks' `--self-test` runs, putting
  them in the suite for the first time — ten sibling hooks already had bats coverage; these two
  did not. `skills/shared/code-documentation.md` gains a shell BEFORE→AFTER gallery entry and a
  shell doc-block shape in a new `### Other grammars` fence.
- **Vendored-path exclusion in the density gate — a separate behavior change, not a rider on shell
  coverage.** `hooks/dv-comment-density-gate.sh`'s `run_gate` filter loop now skips any path
  matching `vendor/*`, `*/vendor/*`, `*/node_modules/*`, `*/Pods/*`, or `*/third_party/*`, and this
  `case` runs **before** the extension `case`, so it exempts vendored files of every gated
  language, not only shell. This is a genuine loosening of previously-active gating (e.g. a
  vendored `.ts` under `node_modules/` was, in principle, measured before and is not now).
  Confirmed zero first-party paths in this repo match any of the five globs, so present cost is
  nil; the change is otherwise safe-direction for a blocking gate (false negatives only, never
  false positives).

### Follow-ups (deliberately deferred, not fixed this round)

- `hooks/dv-comment-density-gate.sh` lines 90-91 document a leading-contiguous-comment-block skip
  that is not implemented in either awk arm. Harmless for Python; structural for shell, where the
  shebang and header always count as comment. This is the real mitigation for the shell comment
  tax — it is why a narrow shebang exemption was rejected as ineffective (moves the density figure
  at most ~2.5 percentage points; the multi-line header, not the shebang, is the actual driver).
- `.bats` files (43 first-party, the largest DV-authored shell class in the repo) remain outside
  the comment-density allow-list.
- `.context/planning-0.md § risks D1` for this worktask carries a mis-measured 39 percent figure
  for `hooks/test-execution-gate.sh`; the correct figure, measured the way the gate measures, is
  42 percent (see above).
- Plugin bug found during planning: `agents/product-manager.md` instructs
  `state-patch.sh --stage PL --prev USER`, but the script rejects `USER` as not a stage code —
  every PL run hits this.

## [3.41.1] - 2026-07-30

Test-execution authority enforcement: a behavioral policy change governing which stages may execute tests, with real blast radius. DV's silent full-suite auto-promotion on non-Apple platforms is now capped at module scope, SR/RE lose unrestricted Bash, and a new always-on `PreToolUse` hook enforces the policy at the delegation boundary. Min CC unchanged at **2.1.220**. Suite **fully green** (394 bats assertions including 27 new gate scenarios, 0 failures).

### Changed (Breaking)

- **Test-execution authority is now stage-scoped and mechanically enforced.** `skills/shared/testing-strategy.md` introduces a new canonical `## Test-Execution Authority` matrix: only DV (scoped execution required, full forbidden) and QA (sole holder of full-suite authority) may execute tests; every other stage is denied. Authority is orthogonal to `test_mode` (breadth) and is enforced at three layers: documented constraints on every stage agent, orchestrator step 4.8b dispatch-time ban banner, and a new `PreToolUse` hook `hooks/test-execution-gate.sh` that resolves the acting stage from `.context/state.json` and denies test-runner invocations outside `{DV, QA}`.
- **`security-reviewer` and `release-engineer` drop bare `Bash` for scoped allow-lists**, matching `technical-lead`/`project-manager` precedent. Both carry git read-only introspection (git diff/show/log/status/ls-files) and jq; RE additionally carries git-tag/describe. This reduces blast radius without breaking legitimate review operations.
- **DV's no-handler auto-promotion is capped at `module-scope`**, not `full`.** When no platform-specific test-selection handler is wired, DV no longer auto-escalates to `full`; instead it computes the touched-module test set and invokes the runner with ≥1 selection argument (classifying as `scoped_test_run`). Full-suite regression remains QA's sole gate. Deferred-to-QA flows are explicitly recorded.
- **`hooks/test-execution-gate.sh` — new `PreToolUse` hook, registered in `plugin.json`.** Fail-open on every ambiguity, stage-resolved from `.context/state.json` only, denies test-runner CLI invocations and `Task`/`Skill` delegations to test-capable agents outside `{DV, QA}`. Exit code always 0; decision travels in JSON. Escape hatch: `IGRSOFT_TEST_GATE=off`. Covers the delegation-path hole that tool-grant narrowing alone cannot close.

### Added

- **`hooks/test-execution-gate.sh`** — PreToolUse hook implementing the stage-authority policy at the tool-invocation boundary. Command classification: runner heads + multi-purpose subcommand checking + depth-capped `bash -c` recursion. Build-only verification is allowed everywhere; test-collection flags (`--count`, `--co`, etc.) are recognized and allowed. Fail-open on every ambiguity (no `.context/`, unparseable JSON, two stages in-progress, jq absent). `command_head` in audit rows is always a known runner token or `redacted`, never a secret. `--self-test` built-in, 18 scenario coverage.
- **`tests/shell/hooks/test-execution-gate.bats`** — 18 test scenarios covering all spec'd behaviors, edge cases, and fail-open branches. Scenario classes: DV/QA allow (scoped/full), banned stages deny, multi-purpose runner subcommand gating, build-only flags, `-c` / `--count` / `-N` / `--co` allowed, recursion depth capping, command_head redaction, escape hatch, no side effects on missing `.context/`, jq absence. Includes four regression cases for fix-validation (SR-H1 unanchored match, P1-4 `-c` false-positive, N1 xcodebuild prefilter, N2 predicate divergence).
- **`tests/shell/skills/test-authority-matrix.bats`** — 6 scenarios verifying single-sourcing: the canonical `## Test-Execution Authority` header exists, every non-DV/QA agent carries the ban pointer, no stray forbidden-runner list restatement, `RUNNERS`/`MULTI_PURPOSE_RUNNERS` in the hook match the canonical prose, and the predicate (≥1 selection argument or positional test target) is consistent across DV/QA/hook.
- **Extended `tests/shell/worktask/manifest-parity.bats`** — added check that `hooks/test-execution-gate.sh` exists, is executable, and is registered in `plugin.json`.

### Fixed

- **DV's auto-promotion was a live defect:** on systems/backend/web (no wired selective-test handler), DV always escalated from the plan's `test_mode: scoped` to `full`, silently widening the scope and deferring the choice to QA. Test selection semantics are now predictable: DV runs scoped (module-touched tests for systems; narrower for others), QA holds full-suite gate, and `deferred_to_qa: full_regression` is explicit in the artifact.
- **Tool-grant narrowing:** 8 occurrences of `auto_promoted_mode: full` in agent/skill prose were replaced with `module-scope`; the residual grep `grep -rn 'auto_promoted_mode: *full'` is now clean.
- **Section size limit compliance:** 8 sections that grew during this theme (canonical Test-Execution Authority + 7 other agent/skill sections) exceeded the 1000-char cap and were restructured into subsections. No substance lost — all 394 tests green post-split.

### Tests

- New `tests/shell/hooks/test-execution-gate.bats` — 18/18 scenarios pass, covering all entry/exit paths.
- New `tests/shell/skills/test-authority-matrix.bats` — 6/6 scenarios pass, verifying single-sourcing and predicate consistency.
- Extended `tests/shell/worktask/manifest-parity.bats` — 1 new case for gate hook registration.
- **Full regression — 394/394 pass** (`./run-tests.sh` exit 0). Baseline ~340; new tests added 54 cases (27 hook scenarios + 6 matrix parity + 3 manifest + 18 existing worktask cases re-exercised). Post-split `section-lint.bats` also passes (0 sections over 1000-char cap).

### Acknowledged Limitations

- **No-space `bash -c'…'` form, `env -i`, `/usr/bin/env … pytest`, backtick command substitution, `find -exec`/`xargs`** — not unwrapped by the gate and remain as accepted, documented bypasses. This hook is a backstop, not a sandbox — tool-grant narrowing (R5a) and orchestrator step 4.8b (R5b) are the primary controls.
- **Recursion depth is capped at 2 levels.** `bash -c 'bash -c "pytest"'` is chased and denied (if applicable); deeper nesting beyond the cap classifies as `not_test` (allow) rather than continuing to recurse unbounded (CWE-674 risk).
- **`npm test --dry-run` bypasses build-only override.** The `--dry-run` flag is classified as build-only and allows execution, but npm's run-script path ignores the flag for custom test scripts (unlike `npm install`-family commands), so the script still executes. This is an accepted bypass of the same class as the ones above; requires agent intent (`--dry-run` specifically) rather than tripping over a benign command.

## [3.41.0] - 2026-07-30

Branch naming moved from FN stage to PL start. New `branch-name.sh` entry point named once before any commit exists, never renamed afterward. Shared `branch-lib.sh` library unifies helpers. FN's `branch-name` subcommand removed entirely. Branch type vocabulary extended to `feature`/`bugfix`/`hotfix` long forms; `fix` retired from the vocabulary (a pre-existing `fix/*` branch now reads as non-conventional and is renamed onto the derived `bugfix/`/`hotfix/` target). Rank-4 issue resolver tightened to prevent false-positive issue matches from digit-terminated slugs. Input sanitization hardened to prevent shell injection of branch names into git push refspec. Min CC unchanged at **2.1.220**. Suite **fully green** (412 bats assertions, 0 failures).

### Added

- **`skills/worktask/scripts/branch-name.sh`** — new PL-stage entry point for branch naming. Named at the start of planning, before any commit exists, and never renamed again. Replaces the FN-stage `fn-preflight.sh branch-name` subcommand with a planning-time invocation. Includes full guard ladder (already conventional, upstream tracked, on integration branch, target exists, detached HEAD, jq unavailable, rename failure) with fail-open posture: no-op arms exit 0, and rename failure exits 0 with audit trail. Dry-run mode via `BRANCH_NAME_PRINT=1` prints the target and renames nothing.
- **`skills/worktask/scripts/branch-lib.sh`** — shared library extracting branch-naming helpers into one implementation: `derive_type`, `derive_slug`, `target_branch_name` (composition from type + slug, no ticket), `audit_fn` (row writer with action + result + origin stage), `meta_json` (metadata object builder), `fn_batch_scope` (batch/incident self-disable guard), `resolve_base_ref` (multi-rank base-ref resolver). Sourced by both the new PL entry point and surviving FN continuity/validate-pr commands. Dependency-free: sources nothing, sets no options, modifies no global IFS.
- **`state.json` field `metadata.facts.branch`** — the planned branch name at PL start, stamped by the orchestrator after validation. Read by FN for the PR push refspec (`git push -u origin HEAD:refs/heads/<facts.branch>`); empty on non-conventional branches (e.g., detached HEAD, non-conventional user input) to trigger the fallback plain push. Ledger field documented in `handoff-protocol.md § Field notes — branch`.

### Changed

- **Branch naming ownership at PL start**: `commands/worktask.md § Step 3c`, `skills/worktask/SKILL.md` check 10, and `agents/product-manager.md` document the new PL-stage naming step. The branch is named once, before planning tasks are created, and never renamed afterward. The FN stage no longer attempts renaming.
- **`skills/shared/git-conventions.md` gains § Branch Naming** — the canonical single source of truth for branch grammar (`<type>/<slug>`, no ticket), type vocabulary (13 tokens: `feat`, `feature`, `bugfix`, `hotfix`, `refactor`, `perf`, `docs`, `chore`, `test`, `ci`, `build`, `style`, `revert` — no `fix`), guard ladder (5 arms: conventional, upstream, integration branch, target exists, detached/not-a-repo), and the once-only rule. Eight other files now reference this section instead of restating rules.
- **Branch type vocabulary: `fix` retired, replaced by `bugfix`/`hotfix`**: `feat` (short form) and `feature` (long form) are both still accepted as conventional prefixes, and the entry point emits the long form (`feature/<slug>`) so existing `feat/*` branches remain valid without churn. `fix` is different: it is removed cleanly rather than kept for compatibility, so a pre-existing `fix/<slug>` branch now reads as non-conventional and is renamed at the next PL start onto the derived `bugfix/<slug>` (or `hotfix/<slug>` when the goal names a hotfix) target — `derive_type` checks `hotfix` before the general fix/bug/defect/crash arm so a goal mentioning both is not misclassified.
- **`agents/project-manager.md` — branch reading moved from git query to ledger**: FN no longer invokes `git rev-parse` or `git branch -l` to discover the branch name. Instead, FN reads `facts.branch` from `state.json`, stamped by the orchestrator after PL naming. Before interpolating into the push refspec, FN validates the branch name against `^[A-Za-z0-9._/-]+$` to prevent shell injection (defence-in-depth; validation also at orchestrator stamp and SKILL check 10).
- **`skills/worktask/references/workspace-modes.md`** — rewritten for the new stage ownership. § Host session authorization explains that the naming happens at PL start (not before FN's push) and the authorization to rename is gated on `branch_is_conventional` only. § Timing documents the pre-approval-gate mutation and clarifies that `--auto-plan`/`--emergency`/`/megatask` remove the gate. § Rollback documents the one-line `git branch -m <original-name>` rollback.
- **Issue resolver rank-4 tightened**: the resolver no longer greps a bare trailing integer off the branch name (which for ticket-less `feature/oauth2` would resolve to issue 2, a false positive). Rank-4 now matches only the leading `<type>/<NNN>-<slug>` shape that both the batch and worktask generators actually produce, making the shape constraint explicit and closing the false-positive window.
- `conductor-attachments.md § Plan fields table` updated to reference `branch-lib.sh` + `git-conventions.md` for type derivation instead of pointing at the finalization validator.

### Fixed

- **Security hardening — shell injection prevention (SR-1)**: Branch names are now gated on `branch_is_conventional` before any emission to stdout, preventing injection of shell metacharacters into the git push refspec. An attacker-controlled branch name (e.g., `fix/a$(id>/tmp/PWNED)`) now emits an empty `branch=` value, triggering the plain-push fallback. Defence-in-depth re-validation added at three consumption sites: orchestrator stamp (`commands/worktask.md § Step 3c` + `SKILL.md` check 10) and FN push (`agents/project-manager.md § Validating facts.branch before the push`), all using the same `^[A-Za-z0-9._/-]+$` regex.
- **Symlink traversal (SR-2)**: Both `branch-name.sh` and `fn-preflight.sh` now resolve their own script directory via `CDPATH= cd -- "$(dirname -- "$src")" && pwd -P` inside a readlink loop, following symlinks to their physical location before deriving sibling paths. This blocks ACE via an attacker-planted `branch-lib.sh` beside a symlinked script.
- **CDPATH lookup corruption (SR-4)**: Both scripts now disable `CDPATH` during directory resolution (`CDPATH= cd --`), preventing a directory named `.` from shadowing the sibling-library lookup.
- **Audit-row loss on unwritable sink (SR-3)**: `branch-lib.sh audit_fn` now captures the exit status of the append-redirection and surfaces failures with a diagnostic instead of silently swallowing them under `|| true`. A genuine rename with an unwritable audit sink now emits a warning (`branch-lib: audit row NOT recorded (sink unwritable) — action=branch_renamed result=ok`) and still exits 0 (fail-open posture preserved).
- Detached HEAD now emits empty `branch=` (never the literal token `HEAD`), triggering the documented plain-push fallback instead of attempting a ref that does not parse.

### Tests

- **New `tests/shell/worktask/branch-name.sh.bats`**: 13 test cases covering the full guard ladder and entry point modes. Six migrated from `fn-preflight.bats` (anonymous rename, second-run no-op, upstream refusal, batch self-disable, integration-branch refusal, dry-run) plus seven new cases (fresh rename via explicit `--goal`, target shape verification, already-conventional long form no-op, already-conventional short form no-op, upstream present no-op, on integration branch no-op, incident self-disable). Includes regression tests for SR-1 (five guard-ladder arms tested with hostile branch input), SR-2 (symlink resolution), SR-3 (audit-row loss), SR-4 (CDPATH corruption), SR-5 (detached HEAD never emits literal HEAD). Also tests that `feature/lyon` (this workspace's branch) reads as conventional (binding constraint AC-5).
- **`tests/shell/worktask/fn-preflight.bats`**: removed seven branch-naming cases (moved to branch-name.sh.bats); added usage-rejection case proving the removed `branch-name` subcommand exits with a dispatch error; added regression case proving rank-4 does not resolve a false issue number from `feature/oauth2` or `feature/migrate-to-swift-6` (digit-terminated ticket-less slugs). Both T4 (library-unreachable) halves now use `run --separate-stderr` and assert the warning lands on stderr specifically, not merged output (DR-3 tightened).
- Suite: 412 bats assertions across 41 files, 48 Swift Testing cases, 37 Python unittest cases, 175 benchmark-harness tests — **all green, 0 failures, exit 0**.

## [3.40.0] - 2026-07-29

Follow-through on 3.39.0: closes the gaps that release left open and clears the suite. Min CC unchanged at **2.1.220**. The test suite is now **fully green** for the first time in this series — 281 bats assertions passing, 0 failures, and the Swift-dependent benchmark tests skipping honestly rather than failing.

### Added

- **`tests/shell/skills/cross-plugin-refs.bats`** — a contract test asserting that every `/<plugin>:<command>` and `Task(<plugin>:<agent>)` this plugin names resolves to a real file in that sibling plugin. It immediately caught two live defects nothing else in the suite could see: the 3.39.0 build-delegation table promised `/ai-engineer:build-test` while ai-engineer shipped no such command, and an android agent rename left three `Task(android-developer:*)` grants pointing at deleted files. Skips cleanly when sibling repos are not checked out beside this one. Also freezes the registry ↔ `publish-pl-issue.sh` prefix-list lockstep that only prose asserted before.
- **`web-capture.sh` and `android-capture.sh`** — the DV screenshot system had one shipped capture script (Apple) and two prose procedures. All three platforms now have executable, self-tested scripts, closing the last structural asymmetry in the adapter layer.

### Fixed (test robustness)

- **The suite could not pass on a host without a working Apple toolchain** — in a plugin that now explicitly orchestrates six platforms. Two guards tested presence rather than usability: `test_generators.py` gated on `shutil.which("swift")`, and `run-tests.sh` hard-`fail`ed on `command -v swift` and then ran `swift test` unconditionally. A swiftly shim stays on PATH after its selected toolchain is uninstalled, so the binary resolved, no skip fired, and the run failed underneath. Both now probe that `swift --version` exits zero; Swift is downgraded from a hard prerequisite to an optional phase that skips with a warning. Same defect shape as the `cache-lint` test above — a guard testing for the wrong thing — and the same shape as the platform coupling this series set out to remove.

### Fixed

- **The suite's three long-standing red tests.** `skills/code-comment-standard/SKILL.md` carried a composed plugin-root token (the bare `${CLAUDE_PLUGIN_ROOT}` form with a path appended) outside the whitelist that contract protects (drift, now using the plain relative path); `attach-visual-evidence.sh` printed no usage message when invoked with no mode, and validated argv only after loading state, so a caller error was masked by a missing `state.json`; and the `cache-lint --filename-lint` test asserted against the live untracked `.context/` directory, so its result depended on whatever runtime state a worktask happened to leave behind — it now uses a fixture and tests the same behavior deterministically.
- **`android-developer`'s four functional-role agents collided with `apple-developer`'s.** Both shipped bare `code-fixer`, `security-auditor`, `test-generator`, and `dependency-manager`. Claude Code keys installed agents by frontmatter `name`, so one silently overwrote the other, and `error_file` derives from the basename, so both wrote to the same `.context/errors/test-generator.md` inside one worktask. android-developer renamed to the `and-` prefix (its 1.4.0); all references here follow, and `§ Naming` now records that apple-developer is the sole remaining bare-name plugin.
- **`deps --upgrade` could silently run a read-only audit.** Dispatch selects the mode from the first token, so a flag naming a mutating mode fell through to `audit` — the caller asked for an upgrade and was handed an audit report, reading "no action taken" as "nothing to do". backend-developer even documented the flag as an alias. All four affected plugins now stop with an explicit error; apple-developer was already safe.

### Changed

- `ai-engineer` gains `build-test` — the one core command the orchestrator structurally requires for a platform to be routable, since DV/DR/QA delegate their build gate to it. This is not a reversal of its documented command-set exception; the rest of the core set is still deliberately absent.
- `ai-engineer` gains the `workflow-integration` skill the compatibility contract requires. It was the only registered plugin without one, so it could be routed to but could not properly take over a stage. Registry updated: version floors, the ai-engineer command-set note, and the workflow-skill column.

## [3.39.0] - 2026-07-29

Platform-agnostic orchestration. Min CC unchanged at **2.1.220**. The registry landed in 3.38.0 made Apple *one of six* on paper; this release makes the pipeline behave that way.

### Changed

- **BREAKING (behavioral): the orchestrator no longer holds platform build tooling.** All 36 `mcp__XcodeBuildMCP__*` grants are removed from `developer`, `qa-engineer`, and `technical-lead`. DV/DR/QA now delegate to the detected platform's `/<plugin>:build-test`, which every dev plugin gained in its own release. Each plugin owns its toolchain lifecycle — MCP cold-start, retry, and raw-CLI fallback — so the first delegated build in a worktask may pay a cold-start retry or take the plugin's CLI fallback path. Neither aborts the stage; both are reported by the plugin. A missing plugin falls back to the project's own build command and writes a `plugin_unavailable` audit row.
- **The Apple XcodeBuildMCP pre-warm is deleted** (execution-loop step 5c and its contract section). It existed because a lazy-spawn stdio MCP server is only inherited by a subagent when already running in the parent — but warming it required the orchestrator to hold Apple tool grants, which is precisely what made one platform structurally privileged. `state.mcp_session` is now deprecated in the state-ledger schema rather than removed, so ledgers written by earlier versions still validate.
- **Screenshot capture delegates too.** The `apple`/`web`/`android` adapters now ask the platform's own agent to produce the file and stat the result, keeping the `{path, bytes, ok, error}` contract and the existing fallback ladder unchanged.

### Fixed

- **`skills/shared/testing-strategy.md` mandated Swift Testing for every platform.** Under a platform-neutral filename, it stated "All unit tests MUST use Swift Testing framework" with no guard, and it is the canonical testing reference for all six platforms — so a Go or React worktask was instructed to use Swift Testing. Rewritten as a genuine cross-platform reference with a per-platform framework and naming map. `agents/product-manager.md` carried the same unguarded rule under **Key Rules**; framework selection is now derived from the repo and the detected platform.
- **The state-ledger schema rejected four supported platforms.** `handoff-protocol.md` enumerated `[all, apple, ios, macos, watchos, tvos, visionos, web, server]` — five Apple sub-platforms, while `android`, `systems`, `backend`, and `ai` were absent, so a ledger for any of those failed its own documented schema. Now the canonical six keys.
- **`commands/test-coverage.md` could not run tests off Apple.** Its only executable grant was `Bash(swift test:*)`, and its compliance table marked Swift Testing "✅ Required" — unsatisfiable elsewhere. Now grants 16 ecosystems and checks against the project's established framework.
- **The comment-density gate never counted Python comments.** `hooks/dv-comment-density-gate.sh` detected comments with a C-family-only regex while its extension gate accepted `.py`, so a fully-commented Python file measured 0% density and always passed. Comment style is now keyed on file extension, with self-test cases for the hash-comment path.
- **Android UI changes were invisible to the screenshot gate.** `detect-ui-change.sh` carried Apple and web markers but none for Android (no Compose, `@Composable`, `res/layout`, `.kt`) while accepting `--platform android`, so `requires_screenshots` never fired for Android UI work.
- **`dv-screenshot-gate.sh` told every platform to run `apple-canvas`.** The gate logic was already neutral; only its remediation message was Apple-only, so a Go backend that tripped it got Apple instructions.
- **`commands/appstore-iap.md` could not perform its own procedure** — it granted no browser tool while its Phases 2-4 are pure App Store Connect browser automation. Now grants the Chrome MCP tools it actually calls.
- `map-and-filter.sh` classified only `*Tests.swift`/`*_test.py` as tests, silently discarding Kotlin/TS/Go/Rust/Java test files; `state-patch.sh` advised `swift package clean` on every platform's disk-space halt.
- **Advertised-but-unimplemented `--platform` values.** `design-accessibility` and `design-specs` offered `android` with no Android content; `estimate` offered web/backend/systems/ai with no adjustment rows. Each either gained the content or had its enum narrowed to its honest scope — the `design-*` commands stay `apple|android|web|all` because they are UI-only by nature.

### Added

- Per-platform depth where Apple previously had a private drill-down: security domain checklists for all six platforms (`security-reviewer`), documentation pipelines beyond DocC (`technical-writer`), rollback constraints beyond the App Store (`incident-responder`), architect routing and dual-pass architecture review for every platform (`software-architector`, `arch-review`, `arch-decision`).
- The three `appstore-*` commands are retained and now **labelled Apple-only** in their descriptions and in README, so the plugin's neutrality claim is honest. `appstore-screenshots` renames its Apple-device flag to `--apple-platform` so it stops colliding with the plugin-wide `--platform` vocabulary.

## [3.38.0] - 2026-07-29

Compatible dev-plugin registry. Min CC unchanged at **2.1.220**.

### Added

- **`skills/shared/compatible-plugins.md`** — the registry the orchestrator lacked. Carries plugin-level metadata only (role, platform key, version floor, entry agent, command-set tier, workflow skill), the functional-role agent roster used by AR/SR/QA/DR, the core-parity command set, and per-plugin handoff defaults. Agent routing stays canonical in `platform-detection.md`, which the registry points at rather than duplicating; the two files now cross-reference each other.
- **`skills/cross-plugin-handoff/references/plugin-onboarding.md`** — the compatibility contract a dev plugin must satisfy (command set, agent roster with plugin-unique prefixes, full handoff schema, workflow-integration skill, evidence declaration, AR consultation model) plus the ordered 14-row touchpoint checklist for adding a plugin and the procedure for replacing one.
- **`ai-engineer` is wired in.** Previously it had zero references anywhere in the plugin. It now has an `ai` platform key: specialization section and marker table in `platform-detection.md` (`.ipynb`, ML/LLM dependency detection, model artifacts, dvc/mlflow/wandb), six `Task(ai-engineer:*)` grants on `developer`, a common-row, stage tables in `plugin-protocols.md`, and rows in the AR/SR/QA consultation tables.
- **Stage handoff tables for `frontend-developer`, `backend-developer`, and `ai-engineer`** in `plugin-protocols.md`. All three were routed to by `developer.md` but had no protocol table; the three "graduated" plugins are noted under the Future Plugin Integration table.

### Fixed

- **`publish-pl-issue.sh` scrubbed only one dev plugin.** The plugin-prefix allow-list named `apple-developer` alone among the dev plugins, so `system-developer:`, `android-developer:`, `frontend-developer:`, `backend-developer:`, and `ai-engineer:` agent identifiers passed through into published PL issues — and the two leak-check greps that are supposed to catch exactly that shared the same blind spot. All four occurrences now carry the full list, with a comment binding them to the registry.
- **`pm-milestone.md` routed Android and web work to `igrsoft:developer`** rather than the plugins that now exist; `systems`, `backend`, and `ai` had no row at all. The Test Agent table gains rows for all five non-Apple platforms, with a note that the Plugin column disambiguates the `test-generator` name that apple-developer and android-developer both ship.
- **`software-architector`, `security-reviewer`, and `qa-engineer` could only reach apple-developer.** Each granted exactly one `Task(apple-developer:*)` target while the equivalent architect / security-auditor / test-generator existed in all six plugins. Grants and consultation tables now cover every platform; the Apple flow is retained as the worked example.
- **`developer.md` was missing a backend row** in its common-rows table despite routing backend work, and its `--platform` enum omitted `backend` at three sites.

### Changed

- Dev-plugin command references across `README.md`, `agents/technical-writer.md`, `agents/software-architector.md`, `commands/worktask.md`, `skills/cross-plugin-handoff/`, and `skills/self-improvement/` migrate to the unified command names (`code-refactor`→`fix-refactor`, `code-modernize`/`code-legacy-modernize`→`fix-modernize`, `generate-dooc`→`gen-docs`, `code-review`→`review-code`, `mock-api`→`gen-mock-api`). Several referenced apple commands that no longer exist under any name.
- The AR-collaboration text in `cross-plugin-handoff/SKILL.md` and `agent-coordination/SKILL.md` is generalized from Apple-only to all platform architects; the agent-coordination model table now points at the registry instead of enumerating a second copy of the roster.

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
