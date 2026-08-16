# Changelog — 3.x (archived)

Archived release history for `3.0.0` through `3.43.0` — 83 releases. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/). `4.0.0` and later, plus `[Unreleased]`, live in [CHANGELOG.md](CHANGELOG.md); earlier majors in [CHANGELOG-2.x.md](CHANGELOG-2.x.md) and [CHANGELOG-1.x.md](CHANGELOG-1.x.md).

**Two provenance tiers.** `3.35.0`–`3.43.0` are reproduced verbatim from the contemporaneous changelog, which began at `3.36.0`. `3.0.0`–`3.34.2` were **reconstructed from git history** — the repository carries no release tags, so each entry was derived from the `version` field in `.claude-plugin/plugin.json`, its bump commit, and the release row that bump added to `MEMORY.md`.

Three things about the reconstructed span are worth knowing before reading it:

- **The version number was not monotonic.** Commits on 2026-04-20 briefly carried `3.7.0` and `3.8.0` before `plugin.json` was reset to `3.6.0` the same day; that work is recorded under `3.6.0`, and both numbers were re-issued in May for different changes. Likewise `3.9.0` (2026-05-09) was reset to `3.8.3` two days later, and its feature line formally shipped under `3.9.1`.
- **Six version numbers never reached `plugin.json` on `master`.** `3.4.0`, `3.9.3`, `3.11.3`, `3.13.0`, and `3.30.0` appear in commit messages and `MEMORY.md` as planned increments; each was folded into the next released version and is noted in the entry that absorbed it. `3.37.2` is the odd one out — it has its own entry below, written at the time, but the work went out under `3.38.0` the same day.
- **Dates are the date the version took effect** in `plugin.json` on `master`, which for a few releases is a day or two off the narrative date recorded in `MEMORY.md`.

## [3.43.0] - 2026-07-31

Unattended worktasks had a third interruption the two gate-bypass flags never covered: PL0's
open questions. `--auto-plan` skipped the plan-approval STOP, but a plan that surfaced
`open_questions[]` still parked the run on a human — or, worse, silently adopted defaults with
no recorded decision. The gap gets a first-class carrier: `PL0.metadata.decision_gate`
(`"user"` default, `"auto"` opt-in). On `"auto"`, a new orchestrator pre-pass (Step A.4, before
the plan gate) re-dispatches the product-manager as a **decision delegate on the Fable model**,
which answers each question default-biased and applies the amendments to the plan's existing
mandatory anchors in one batch pass; the orchestrator then merges the calls into
`state.json facts.decisions[]` marked `(auto-decided)` and drops the resolved
`facts.open_questions[]` entries, which is what makes them visible to AR/TL/DV — auditable
(`auto_decision_dispatched` → `auto_decision_resolved` carrying each rationale,
`subject:"PL<N>"`), resumable (new resume-table row), and bounded by a BINDING escalation
guard: irreversible/destructive, scope-expanding, security-posture-weakening, or
spend-authorizing questions are never auto-decided and stop for the user even under a bypassed
plan gate. The Fable dispatch reuses loop step 5f's capability fallback
(`facts.capabilities.fable_dispatch == "credit_blocked"` → `opus`, audited), so credit-gated
accounts degrade instead of hard-failing.

With three orthogonal automation carriers, two boolean flags stopped scaling. The flag surface
becomes one **array flag**: `--auto=[plan, decision, finalization]` — any non-empty subset,
brackets optional, whitespace tolerated, unknown values a parse error rather than a silent
drop. `--auto-plan` and `--auto-finalization` remain accepted as deprecated aliases
(`--auto=[plan]` / `--auto=[finalization]`) and compose with the array by union.

### Added

- **`PL0.metadata.decision_gate` carrier** (`"user"` default / `"auto"`), stamped by
  `--auto=[decision]` (or directly per-issue by `/megatask`). Bypasses neither `plan_gate` nor `fn_gate` — it changes WHO answers
  PL0's open questions, nothing else. `--emergency` leaves it `"user"` (no PL stage → inert).
- **Step A.4 Auto-Decision Pre-Pass** (`commands/worktask.md`): no-op unless
  `decision_gate == "auto"` AND `open_questions[]` is non-empty; otherwise dispatches the PM
  decision delegate on `model: "fable"`, with the step-5f `opus` fallback and
  `model_resolution_constrained` audit on credit-blocked accounts.
- **Escalation guard (BINDING)**: `escalate`-class items force a `checkpoint`-style stop for
  exactly those items even under `plan_gate: "bypass"` — auto-decision never widens what runs
  unattended.
- **Audit vocabulary**: `auto_decision_dispatched` / `auto_decision_resolved`
  (`subject:"PL<N>"`, `metadata: {questions|decided|escalated, model_resolved, decisions:
  [{question, answer, rationale}]}`) — the resolved row is where the per-question rationale lives.
- **Ledger merge duty (orchestrator, not the delegate)**: decided items are appended to
  `state.json facts.decisions[]` marked `(auto-decided)` and the resolved entries removed from
  `facts.open_questions[]` via `atomicMergeStateJson`. The delegate adds NO anchor to
  `planning-N.md` (the PL anchor set is exact — `## decisions` belongs to AR's
  `architecture-N.md`) and never re-runs `state-patch.sh`, since PL0 is already `completed`.
- **Precondition Signal 2b** (`skills/worktask/SKILL.md`): loop entry verifies the
  `auto_decision_resolved` row (and escalate resolutions) exist when the carrier is `"auto"`
  and questions were surfaced.
- **Resume-table row** (`references/resume.md`): `auto_decision_dispatched` without a matching
  `auto_decision_resolved` → re-run Step A.4; already-applied decisions (the `(auto-decided)`
  entries in `facts.decisions[]`) are not re-decided.
- **PM auto-decision path** (`agents/product-manager.md § Plan-Gate Open-Question Batching`):
  under `decision_gate: "auto"` the PM still builds the numbered defaults list but returns it
  via `open_questions[]` instead of holding a gate round-trip; the delegate turn's
  decide/apply/record duties and the never-auto-decide classes are spelled out.

### Changed

- **`--auto=[plan, decision, finalization]` replaces the boolean gate flags** as the canonical
  surface (`commands/worktask.md § Gate automation flag`); parse rule: strip brackets, split on
  commas, trim, union with legacy aliases, reject unknown values. All plugin docs
  (`README.md`, `skills/shared/worktask-invocation.md`, `skills/worktask/SKILL.md`,
  `references/{resume,fn-gate,workspace-modes}.md`, `skills/agent-coordination/SKILL.md`,
  `skills/security-review-process/SKILL.md`, headless-dispatch/hook-monitoring references) now
  name the array form.
- Plan-gate `checkpoint` summaries list every auto-decided question marked
  `(auto-decided by Fable — see facts.decisions[] / audit)` so approval covers the decisions
  together with the plan.
- **`/megatask` stamps `decision_gate: "auto"`** on every per-issue `PL0` alongside the two gate
  bypasses (`commands/megatask.md`, `skills/megatask/SKILL.md`) — a batch is unattended, so open
  questions route through the Fable decision pass. Escalate-class questions are still never
  auto-decided there: they PARK that single issue and the batch continues with the unblocked
  issues instead of stalling on a human. Parking rides the monitor's existing failure path — the
  per-issue worktask settles `execution.status: "failed"` +
  `execution.reason: "parked_escalation"` with an `escalation_parked` audit row, so
  `hooks/megatask-monitor.sh` frees the track, keeps dependents `blocked`, and the batch summary
  lists the parked issue with its unanswered questions.
- `.claude-plugin/marketplace.json` version parity — `metadata.version` and `plugins[0].version`
  bumped to 3.43.0 alongside `plugin.json` and the README badge.

### Deprecated

- `--auto-plan` and `--auto-finalization` — accepted, documented as legacy aliases of
  `--auto=[plan]` / `--auto=[finalization]`; new invocations and documentation must use the
  array form.

## [3.42.0] - 2026-07-31

AR and TL stop being score-driven mandates and become PL0 decisions. The tier tables encoded
architecture at score >=11 and team-lead at >=21 with no planning discretion, in four duplicated
copies plus the readme — so a single-workstream task at score 34 got a coordination stage it had
nothing to coordinate. TL0 is now removed from every tier default row and included only on the
split-work test; AR0 stays a default but an overridable one, against published criteria that live
in exactly one place. The matching correctness gap closes with it: the typed `DVHandoff` schema
had **no architecture field at all**, so DV found the AR artifact by filename convention while its
frontmatter hard-coded `refs.decisions: analyzing-N.md#decisions` even on tiers where AR never ran
— a dangling reference by construction. That reference is now conditional, typed, and gate-checked.
The gate ships **warn-only**: exit stays 0, `--strict` (or `IGRSOFT_AR_REF_STRICT=1`) opts into
blocking, and a future minor flips the default. Legacy invocation without `--state` is pinned
byte-identical. Suite green; `shellcheck` holds at the pre-existing two-SC2064 baseline on
`handoff-harness.sh`.

This release also renames the AR stage artifact `analyzing-N.md` -> `architecture-N.md` (see
`### Changed`). That is the release's **one breaking change**, and it ships with no back-compat
fallback by explicit decision — so the commit carries the `refactor(workflow)!:` type and a
`BREAKING CHANGE:` footer naming the old -> new mapping, following `cada9e4`'s shape.

**Visual evidence stopped reaching pull requests, and nothing noticed.** A UI worktask captured
six verified screenshots, published a PR carrying none of them plus a dead `.context/` path, and
was audited `ok`. Four independent defects, each reproduced before being fixed.

The leak was **not** specific to visual evidence. `sanitise_body`'s pass-1 rules anchor on
`(^|[[:space:]])`, and a backtick is neither — so wrapping a path in a code span defeated every
one of them, while pass 2 then copied code spans through verbatim by design. Four rule families
were affected (`.context/`, `/Users/…`, `~/`, `../`), on **issue bodies as well as PR bodies**;
absolute host paths escaping into published GitHub issues was the more serious half. Pass 1 now
matches on a backtick-neutralised copy of the line. Substituting a space rather than deleting the
backtick preserves each anchor's intent: `` `.context/ `` matches, `foo.context/` still does not.
The visual-evidence block emitted its manifest reference **as a code span**, so it tripped this on
every run; that reference is now path-free. Changing it was forced rather than optional — once
pass 1 sees through backticks, a path there is simply stripped and `see manifest` names nothing.

Tier-0 image hosting was never unavailable, only **unbounded**. `gh image check-token` succeeds
but decrypts the browser cookie store on a cold cache (measured >120s cold, ~3s warm) and can
block indefinitely on a macOS Keychain prompt when non-interactive. It was called with no timeout,
so finalization stalled and the stall was then reported as "inline hosting unavailable". The
obvious fix does not work: stock macOS ships neither `timeout` nor `gtimeout`, so the existing
`command -v gtimeout || command -v timeout` guard resolved to empty and left the call unbounded on
exactly the platform that needed it — including, already, `gh issue create`. Both now route
through a coreutils-free `run_with_timeout`, and `GH_SESSION_TOKEN` skips browser extraction.

Finally, the failure was silent. `visual_evidence_pr_emitted` reports `ok` whether or not a single
image embedded, so it could not distinguish a healthy run from an invisible one. A distinct
`visual_evidence_degraded` row now carries `captured`/`embedded`/`reason` whenever captures exist
that the reader cannot see, alongside a stderr `NOTICE` and an FN-gate reporting duty. The trigger
is `embedded < hostable`, not `== 0`, so partial loss counts too — the failing run had six
captures against a five-embed cap and would have lost one even with hosting working.

### Added

- **Stage Inclusion Criteria (PL0 authority) — one canonical block.** `skills/estimation-methodology/SKILL.md`
  gains the criteria as canon: the four conditions under which PL0 MAY exclude AR0, the five under
  which it MUST include it at any tier including Low, and the single split-work test that governs
  TL0. The other three tier-table copies and the readme carry a one-line pointer footnote rather
  than a duplicated restatement, so there is one place to change when the rules move.
- **`metadata.added_stages`.** A symmetric counterpart to `skipped_stages` with the identical
  `{stage, reason}` shape, recording every stage PL0 includes beyond the tier default (AR0 forced
  at a low tier, TL0 at any tier). Both lists stay measured against the full nine-stage reference
  pipeline, so a declined stage always appears with a reason. Pre-stage validation gains check 3b:
  every entry's reason must be decision-shaped, not a score restatement.
- **AR->DV architecture-reference gate in `handoff-harness.sh`.** `--validate-frontmatter` accepts
  `--state <state.json>` and `--strict`. When the artifact is a DV handoff and the ledger has a
  `stages.AR` entry, the architecture reference must match `^architecture-[0-9]+\.md(#[a-z-]+)?$` and
  resolve to a file beside the artifact. Violations are `warn:` + exit 0 by default and `fail:` +
  exit 1 under `--strict`; the env opt-in `IGRSOFT_AR_REF_STRICT=1` is read by the script itself,
  not only by the orchestrator, so the opt-in works even when an older caller omits the flag. The
  inverse guard — an architecture reference with no `stages.AR` entry — warns in both modes and can
  never fail. An unreadable `--state` (absent file, malformed JSON, or no `jq`) is reported rather than
  treated as "AR did not run" — silence there would be a false negative on every `jq`-less host
  once `--strict` becomes the default. `--self-test` covers all sixteen branches; fifteen new
  bats cases cover the six specified scenarios, the AC-6 legacy pin, the four conditional edges
  and the per-stream filename grammar.
- **DR verification of architecture *application*, not just reference.** `agents/technical-lead.md`
  gains an Architecture-Application Check that runs only when `stages.AR` exists: read
  `architecture.applied`, spot-check the diff against AR's `key_decisions`, and fail an
  **undeclared** deviation back to DV. A deviation declared with rationale in
  `development-N.md ## decisions` passes.
- **Anchored-rejection rule for DR.** Every DR rejection must cite a resolvable ref — an AR
  decision id or a plan acceptance-criterion id. An unanchored rejection is invalid and DV may
  bounce it back as `missing_input` on DR; a concern that cannot be anchored is a finding, not a
  blocker.
- **DV architecture ownership.** When AR was excluded, or when AR ran but is silent on a question
  the implementation forces, DV decides and records the call in `development-N.md ## decisions`
  with alternatives and rationale. No AR re-open loop, no separate artifact, no stalling on a
  `missing_input` for a decision DV is competent to make.
- **Per-workstream DV artifacts under TL fan-out.** TL assigns each workstream a kebab `stream`
  slug; each DV sub-agent writes only `development-N-<stream>.md`, and the DV entry agent alone
  merges the canonical `development-N.md` at fan-in — removing contention on a shared artifact.
  `development-N.md` stays the DR/QA input and the file the handoff describes. Filename-lint
  (`cache-lint.sh --filename-lint`) and `hooks/anchor-preflight.sh` accept the suffix; the
  preflight self-test gains two positive and three negative cases pinning the kebab shape.
- **`metadata.architecture_ref` on DV0, DR0 and QA0 dispatches.** When AR completed, all three
  carry `{path, anchors, key_decisions}` (the digest drawn from AR's frontmatter, <=200 chars) and
  name `architecture-N.md` in `context_files`; when AR was excluded, none of them may carry either.
- **Three conditional handoff edges — `AR->DV`, `PL->DV`, `PL->TL`** — with an edge registry in
  `handoff-protocol.md` giving every edge its when-clause, plus `AR->DV 350` / `PL->DV 400` /
  `PL->TL 400` context budget rows. Three new state-patch bats cases pin the edges.
- `skills/worktask/scripts/pr-body-lint.sh` — validates a composed PR body: local-path leaks
  (backtick-aware), a `Visual evidence` section with no images, non-`https://` image refs, missing
  `Motivation`/`Changes`/`Test plan`/`Closes #<N>`, and AI-attribution footers. **Warn-only** by
  default so it lands mid-flight; `--strict` / `IGRSOFT_PR_BODY_STRICT=1` exits 1, and that
  becomes the default in a later minor — the same rollout the AR-ref gate uses above. Wired into
  `fn-preflight.sh pr-body` after sanitisation, so it reads back the byte-identical body that
  reaches `gh pr create`. Self-disables under `/megatask` and `--emergency`.
- **`visual_evidence_degraded` audit row + stderr `NOTICE`**, emitted whenever captures exist that
  did not reach the reader (`embedded < hostable`, so partial loss counts). Carries `captured`,
  `embedded` and a `reason`; `agents/project-manager.md` must surface it at the FN gate.
- `GH_IMAGE_FAIL_REASON` (`absent` / `token_invalid` / `probe_timeout` / `no_host_tier` / `ok`),
  replacing one undifferentiated "hosting unavailable" sentence with the action that fixes it.
- `run_with_timeout` — bounded execution with no coreutils dependency — and
  `GH_IMAGE_PROBE_TIMEOUT` (default 90, deliberately longer than `GH_TIMEOUT` because a cold probe
  legitimately needs it).

### Changed

- **BREAKING — the AR stage artifact is renamed `analyzing-N.md` -> `architecture-N.md`.**
  Old -> new, in every position: `analyzing-N.md` -> `architecture-N.md`,
  `analyzing-0.md` -> `architecture-0.md`, `analyzing.md` -> `architecture.md`,
  `analyzing-*.md` -> `architecture-*.md`, and the reference pattern
  `^analyzing-[0-9]+\.md(#[a-z-]+)?$` -> `^architecture-[0-9]+\.md(#[a-z-]+)?$`.
  This finishes the normalization `cada9e4` (v3.8.0) began when it renamed four sibling stage
  artifacts to noun-of-output names and left AR's behind.

  **There is no back-compat fallback — writers and readers flip together.** Unlike `cada9e4`,
  which kept legacy names readable for one cycle, an in-flight worktask that started under
  <=3.41.2 and continues under 3.42.0 will not resolve its existing `analyzing-N.md`. The
  affected population is bounded: `.context/` is gitignored and per-workspace, so this cannot
  affect anything already merged. **To migrate, rename the file and its references:**
  `mv .context/analyzing-N.md .context/architecture-N.md`, then update any `refs.decisions:` /
  `architecture.ref` value in a stage artifact's frontmatter. Use `git mv` only in the unusual
  case that you track `.context/` — against the default gitignored layout it fails with
  `fatal: not under version control`. A worktask that has already cleared DR and DC needs no
  action; one that passed DV but has not yet cleared them still needs the rename, because DR's
  Architecture-Application Check (`agents/technical-lead.md`) and the DV/DC input rows in
  `skills/shared/stage-contracts.md` all resolve `architecture-N.md` unconditionally.

  One deliberate exception: the `.context/`-path redaction filter in
  `skills/worktask/scripts/publish-pl-issue.sh` recognizes **both** names permanently
  (`PERMANENT-SUPERSET`). It is a leak filter, not a compat shim — a filter that forgets a name it
  used to recognize can only leak more.

  New guard: `tests/shell/worktask/artifact-map-parity.bats` asserts all six copies of the
  stage -> artifact-basename map agree for every stage code. The drift this rename repairs went
  unnoticed for 34 minor releases because nothing compared those copies.
- **TL0 removed from every tier default row** (Moderate, High, Critical) across
  `skills/estimation-methodology/SKILL.md`, `skills/worktask/SKILL.md`, `README.md` and the command
  surface; each table gains the `+ TL0 — only when PL0 splits the work across >=2 developers`
  footnote, and each AR0 row is annotated as a PL0-overridable default. A single workstream served
  by a single DV agent now gets no TL0 at any score.
- **PL0 step 3 is three sub-steps** (`agents/product-manager.md`): resolve the tier default, apply
  the AR0 override criteria, then decide TL0 on the split-work test alone — stamping both metadata
  lists and recording both decisions in `planning-N.md ## stages`. The plan-approval gate summary
  must now show the AR decision (flagging any deviation from the tier default) and the TL
  split-work decision, each with its one-line reason.
- **DV `refs.decisions` is conditional on AR having run**, in the stage-contract template, the
  developer agent's own frontmatter block, and the `DVHandoff` schema — which gains the optional
  `architecture: {ref, applied}` object, gate-required when `stages.AR` exists. `refs.coordination`
  is likewise conditional on TL.
- **Conditional `--prev` in the developer and team-lead contracts.** Both now select the
  predecessor from the `stages` keys actually present in the ledger rather than passing a fixed
  value.
- **AR's `next_stage_focus` is addressed to TL when TL is in the plan, else to DV**, with the same
  conditional on `open_questions` addressees.
- **Published issue and PR bodies now strip strictly more.** A line mentioning a local path inside
  backticks is removed rather than preserved. This includes benign-looking cases: a line containing
  `` `./run-tests.sh` `` is dropped, exactly as the bare `./run-tests.sh` form always was —
  backticks were an accidental escape hatch, not a documented exemption. Pass 2 is unchanged, so
  fenced code blocks and code spans carrying no leak token still render verbatim.
- `skills/shared/git-conventions.md § Pull Request Format` now documents `Test plan`,
  `Visual evidence` and the `Closes #<N>` trailer, which three enforcement points already required
  but the spec omitted.

### Fixed

- **The refs-validation false claim.** `handoff-protocol.md` asserted that the handoff harness
  validates cross-file `refs.*` resolution. It does not, and did not: it checked key presence only.
  The statement is narrowed to the truth — cross-file resolution is enforced for the AR->DV edge
  alone, every other ref is presence-only, and authors remain responsible for those.
- **A pre-existing over-cap section in `skills/shared/code-documentation.md`.** The
  `section-lint` 1000-char enforcement test was already red at HEAD: `### Other grammars`, added
  in 3.41.2, measured 1076 chars. Split with a `#### Shell` sub-heading — no content change. Out
  of this release's nominal scope, but the suite could not go green without it.
- **The phantom `TL->DV` edge.** `agents/developer.md` unconditionally wrote
  `state-patch.sh --prev TL`, stamping a handoff edge from a stage that never ran on every tier
  below Moderate. Writing an edge for an absent stage is now documented as a ledger defect.
- **`sanitise_body` no longer lets a backtick-wrapped local path through pass 1** — the defect
  that published a `.context/` path into a PR. Applies to issue bodies equally.
- **The visual-evidence manifest reference no longer emits a `.context/` path**, and three call
  sites stopped overriding it with one.
- **`gh image check-token` and `gh issue create` are bounded on hosts without `timeout`/
  `gtimeout`** — i.e. stock macOS, where the previous `TIMEOUT_BIN` probe resolved to empty and
  silently left both calls unbounded.

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

## [3.35.1] - 2026-07-21

*Reconstructed from git history — this release shipped without a changelog entry.*

### Fixed

- **The compact comment standard never loaded outside DV/DR/DC.** It bound only via prose path-references inside those three agent prompts, so the top-level orchestrator and the other write-capable agents (`qa-engineer`, `incident-responder`, `workflow-engineer`) never saw it. Made loadable everywhere: a new invocable skill wrapping the single-source-of-truth `code-documentation.md`, a `PostToolUse` hook that injects the compressed standard once per session on the first source edit (never blocks, injection-safe), and ban-list mirrors in the three write-capable agents.

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

## [3.34.2] - 2026-07-20

### Fixed

- **The compact-comment standard was being ignored.** DV/DR/DC agents still emitted multi-paragraph `///` doc essays, `AC-`/`REQ-` traceability IDs, and commented-out `#Preview` blocks despite the `3.27.1` standard. `skills/shared/code-documentation.md` now encodes the doc-block shape (1–3-line summary, blank `///` separator, grouped `- Parameters:` block, one sentence per entry), an issue-ID-only-where-business-logic-materially-changed rule, and var/constant plus SwiftUI `#Preview` rules; the ban-list mirrors in `developer`, `technical-lead`, `technical-writer`, `dev-code-review`, and `cross-plugin-handoff` were extended to match. The plugin cache is version-keyed, so the reworded rules only reach installs with the bump.

## [3.34.1] - 2026-07-17

### Fixed

- **Figma capture never fired for `/file/` and `/proto/` URLs.** The trigger matched only `figma.com/design/`, so the other two URL forms populated the design-preview anchor but produced no PNGs, no `figma-registry.md`, and silently skipped QA's design gate. Widened to `figma.com/(?:file|design|proto)/` at both sites that must agree (`agents/product-manager.md` and `skills/shared/figma-capture.md`); the non-capturing group preserves the Group 1 `fileKey` / Group 4 `nodeId` contract. Fixture `04-alternate-url-forms.md` guards the regression.

## [3.34.0] - 2026-07-14

Claude Code 2.1.203→2.1.209 band — background-agent and worktree stabilization.

### Changed

- **2.1.206 `EnterWorktree` confirmation guard** documented for paths outside `.claude/worktrees/`, which affects megatask lanes.
- **A background-task completion notification is never the human approval a gate requires** (2.1.205) — reaffirmed explicitly.
- Reference accuracy: headless env preservation, resume reliability, `SessionStart` headless streaming, agent-teams mailbox crash-loop fix, broadened `rm -rf` guards, and auto-mode-without-opt-in on Bedrock/Vertex/Foundry.

### Fixed

- A stale `2.1.169` min-CC reference. Min CC stays 2.1.200 — nothing here requires 2.1.203+.

## [3.33.2] - 2026-07-13

### Added

- **`tests/shell/skills/plugin-root-refs.bats`** freezes the plugin-root reference grammar: the composed token only on the five whitelisted CC-config markdown lines, no colon-dash form in markdown, env-var reads limited to the three env-first scripts.

### Fixed

- `MEMORY.md`'s version line, repairing the `3.33.0`-vs-`3.33.1` drift left when `3.33.1` shipped without a MEMORY row.

## [3.33.1] - 2026-07-11

### Changed

- **Nine `.sh` helpers moved from `references/` to `scripts/`** (worktask ×8, agent-coordination ×1) to match skill convention — `references/` is for context-loaded docs, `scripts/` for executables. All 58 path citations across 30 files repointed, including the live anchor-preflight hook and the `gh-issue-dedup` frontmatter dependency. `publish-pl-issue.sh` loads self-test fixtures relative to its own directory, so that lookup was repointed into the sibling `references/fixtures` — fixture data stays reference content. Full shell suite 217/217 pass.

## [3.33.0] - 2026-07-08

### Fixed

- **A second worktask in the same `.context/` opened a duplicate GitHub issue.** `state.json` is re-seeded on every fresh `/worktask` and its metadata wiped, so `metadata.github_issue_url` — the only dedup anchor `publish-pl-issue.sh` checked — was lost on each `run_index` increment. The issue reference now persists to a run-independent `.context/gh-issue.json` anchor, and the helper gained a comment-instead-of-create branch: a later run resolves the anchor (or an exact-title single-hit `gh issue search`) and posts a marker-deduped follow-up comment. Milestone mode still skips both.

### Added

- **`gh-issue-dedup` skill** documenting the protocol; the FN PR-issue-link validator gained the anchor as a fallback source; 6 bats cover create/comment/idempotency/search.

## [3.32.0] - 2026-07-07

### Breaking

- **46 commands consolidated into 36** under one domain-prefix taxonomy (`pm-`, `arch-`, `dev-`, `test-`, `design-`, `docs-`, `business-`, `appstore-`): 10 renames, 7 merges into 5 absorbing commands via flags, and 3 never-used commands deleted (`code-impl`, `transparency-check`, `create-pr`). No deprecation aliases. Bumped in both manifests — the plugin cache is version-keyed, so a rename without a bump serves stale paths.

## [3.31.0] - 2026-07-07

### Added

- **`state.json` v1 additive upgrade plus a patch lock.** The CC 2.1.185–2.1.202 band changed the very execution semantics `state.json` exists to track: background-default subagents (launch-ack ≠ completion), structured `errored` returns, and legal sibling-stage overlap racing the lockless merge. Six additive v1 fields land — `dispatched_agents`, `last_error`, `completed_via`, `stages.<CODE>.worktree`, `model_requested`/`resolved`+`name`, `facts.capabilities` — alongside an mkdir-spinlock in `state-patch.sh` with `--via` provenance and 9 new bats tests. Ships with the staged `3.30.0` cc-update band integration.

## [3.29.0] - 2026-07-06

### Changed

- **Benchmark, tests, and the Tic-Tac-Toe fixture migrated from Python to Swift** — 37 Python files and 5,155 LOC retired, 226 Swift tests against a 171 parity target. `benchmark/README.md` and `tests/COVERAGE.md` updated with the migration's known issue (a P1 temp-dir leak) and coverage-count deltas, so downstream readers stop seeing stale Python-era numbers.

## [3.28.1] - 2026-06-30

### Fixed

- **Three renamed skills silently dropped out of the registry.** A prior commit renamed `estimation`→`estimation-methodology`, `pencil-design`→`pencil-design-worktask`, and `review`→`senior-developer-review` without bumping the version. The plugin cache is version-keyed, so the stale `3.28.0` cache kept the old directories while the refreshed manifest pointed at the new paths — producing "skills path not found" load errors. Bumping forces a fresh cache.
- `commands/accessibility-audit.md` declared `a11y-audit` in its frontmatter `name` and usage examples, but the command registers from its filename. Corrected the name field and all four examples.

## [3.28.0] - 2026-06-23

### Fixed

- **The DV visual-evidence gate did not install.** `marketplace.json` runs under `strict: true`, so its enumerated `commands`/`skills` arrays are the authoritative load list — and the `dv-screenshot-capture` and `preview-ensurer` skills plus the `create-pr` and `improve-yourself` commands were never added to it. All four registered. Also de-staled the request-plan evals (`quick:`/`worktask:` → `/worktask`) and clarified the shared/milestone-helpers load note.

## [3.27.1] - 2026-06-23

### Added

- **A compact code-documentation standard for the DV stage.** DV-generated source carried verbose doc-comment essays — design history, Figma/rgba narration, verification logs, call-site lists. `skills/shared/code-documentation.md` becomes the single source of truth, wired into the DV→DR→DC path and into the cross-plugin delegation prompt so external platform specialists receive the rule too.

## [3.27.0] - 2026-06-22

### Changed

- **Token-utilization pass across the plugin**: net −416 lines (376 insertions / 792 deletions) over 83 files. Ambient descriptions trimmed −555 characters (~−139 tokens) with zero over-cap descriptions left; `agents/developer.md` −118 lines (platform routing tables externalized); `agents/product-manager.md` −163 lines (Figma workflow externalized); `README.md` −57 lines. 45 command/skill files moved their `## Related` sections into `related:` frontmatter.
- **Four new on-demand shared docs** (311 lines, zero steady-path overhead): `skills/shared/platform-detection.md`, `figma-capture.md`, `worktask-stage-context.md`, and `legacy-fallback-f1.md`.

### Removed

- Tier-D deprecation cleanup: `FAST_MODE_OVERRIDE`, and the old stage codes `TC`/`PE`/`DS` purged from the Model Lookup tables.

## [3.26.1] - 2026-06-22

### Removed

- **The `--dynamic` native-Workflow execution mode**, collapsing to a single execution path: the manual Task-based orchestrator loop. The opt-in was never the default and carried ongoing maintenance cost with no active users. `dynamic-workflow.md` and `dynamic-megatask.md` deleted, all `--dynamic` / `execution_mode` / native-Workflow rules scrubbed from commands, skills, and references, and 2 keywords dropped from `plugin.json`. PL0 dynamic *sizing* (complexity-based stage selection) is preserved — a different thing with a confusingly similar name.

## [3.26.0] - 2026-06-22

### Changed

- **Milestone orchestration extracted into `/megatask`.** `/worktask` becomes strictly single-issue and milestone-agnostic. `/megatask` resolves a GitHub milestone or an explicit issue array, builds a dependency/blocker DAG from `Depends on:` / `Blocks:` plus P0–P3 labels, and runs issues in topological + priority order, never starting one whose blockers are unmerged. `skills/worktask-milestone` renamed to `skills/megatask` (orchestrator schema v3.1), plus a new `hooks/megatask-monitor.sh` (`SubagentStop`) that unblocks dependents as each per-issue run completes.

## [3.25.0] - 2026-06-22

### Breaking

- **The PL plan-approval gate is enforced on the initial execution path, not just on resume.** `plan_gate` was stamped into `state.json` during the OV-131 guardrail work but never checked on first run. A plain worktask now STOPs after PL0, presents the plan, and waits for explicit approval before dispatching implementation stages. `commands/worktask.md` gains Step A.5 (precondition check + `AskUserQuestion` approval loop); `--auto-plan` stamps `plan_gate: "bypass"` for the trusted fast path; `--milestone:N` stamps bypass for unattended batches. The approval audit subject was generalized to `PL<run_index>` to prevent stale-approval reuse across re-runs.
- **Trigger set collapsed** — the `micro:`, `quick:`, and `fworktask:` triggers were removed.

## [3.24.2] - 2026-06-22

### Breaking

- **The FN finalization gate is a real human checkpoint again.** `PL0.metadata.fn_gate` now defaults to `"checkpoint"`, so the orchestrator STOPs before any commit/push/PR and waits for approval. `--auto-finalization` bypasses it (alongside `--milestone:N` and `--emergency`); `--auto-plan` stays orthogonal and never bypasses FN. Audit lines (`fn_gate_waiting`, `approval_received`, `approval_rejected`, `fn_gate_bypass`) use `subject: "FN<run_index>"` for resume coherence.

## [3.24.1] - 2026-06-22

### Breaking

- **The `worktask:` / `emergency:` message prefixes are gone.** They were pure documentation convention — no hook or `settings.json` ever parsed them. `/worktask` (with `--emergency` for incidents) or `Skill({skill:"igrsoft:worktask"})` is now the single documented entry point. `skills/shared/worktask-triggers.md` renamed to `worktask-invocation.md`, keeping the BLOCKING rule and invocation gate but dropping the trigger table; the dead `secure-worktask:` / `full-worktask:` prefixes were retired and the dangling `commands/emergency.md` fixed.

## [3.24.0] - 2026-06-19

Claude Code 2.1.176–2.1.183 band. The headline is the **agent-teams API removal**, which had made the plugin's team documentation factually wrong on CC ≥ 2.1.178.

### Changed

- **Agent teams**: `TeamCreate`/`TeamDelete` removed in favour of an implicit per-session team and Agent-name spawn; `team_name` ignored from 2.1.178. Teammate background tasks survive turn end; tmux pane launch fixed (2.1.183).
- **Tools and permissions**: `Tool(param:value)` and `*` wildcard rules (2.1.178); subagent `disallowedTools` MCP server-level specs honored (2.1.178); `ExitWorktree` Windows clean-removal fix (2.1.181).
- **Hooks**: Read/Edit/Write path if-conditions match correctly (2.1.176).
- **Subagents**: the classifier evaluates spawns pre-launch (2.1.178); foreground subagents share the 5-level depth cap (2.1.181); WebSearch and `thinking.disabled` 400 fixed (2.1.183).

### Added

- A canonical handoff `SCHEMA` plus an anchor-lint hook.

## [3.23.2] - 2026-06-19

### Changed

- **The DR-stage review command rebuilt around recall**, so confirmed correctness/security/concurrency/regression risks stop slipping past DR to QA. `code-review-dev.md` gains decoupled Phase 1 DETECTION / Phase 2 VERIFY+FILTER / Phase 3 completeness, a 12-class bug checklist, mandatory read-beyond-the-diff, a BLOCKED-keep rule, P0/P1/P2 severity routing, explicit decision + coverage output, read-only git acquisition, and an escalation-to-DV loop where a read-confirmed sound P0/P1 sets `verdict: fail` and re-dispatches DV.

### Fixed

- **DV-owned escalations never reached DV.** `technical-lead.md` classified them as `ambiguous_requirements`, which routes to PL; corrected to `missing_input`, which routes to the previous stage.

### Removed

- Two unused commands, `/api-docs` and `/onboard-task` (45 → 43).

## [3.23.1] - 2026-06-19

### Added

- **OV-131 worktask guardrails** (additive prompt hardening): a canonical `skills/shared/worktask-triggers.md` with a §BLOCKING rule and trigger table, an INVOCATION GATE banner, `metadata.skipped_stages` recording, and a `metadata.plan_gate` carrier honoring the `micro:`/`quick:` resume checkpoint.

### Known Considerations

- `marketplace.json` carried its own stale versions (`metadata.version` 3.8.3, `plugins[0].version` 3.9.0), drifted from `plugin.json` across many releases. Release tooling reads `plugin.json` and the MEMORY `Plugin version:` line, not `marketplace.json`, so it was left untouched here rather than taking an unreviewed multi-version leap.

## [3.23.0] - 2026-06-17

### Breaking

- **Git-worktree isolation is unconditional** for all file-writing work. The `--worktree` flag, the complexity-30 isolation auto-trigger, and the "isolation optional" fallback are gone — one isolation mode, no carve-outs. The legacy `.workspaces/` milestone mode is deleted; it is always `.worktrees/` now.
- **Both human approval gates dropped** (post-PL0 and pre-FN); worktasks run unattended end to end. PL0 stamps `metadata.isolation: "worktree"` and `fn_gate: "bypass"` unconditionally — worktree isolation is what keeps an unattended FN (commit/push/PR) reviewable as a PR. Both gates were restored two releases later, in `3.24.2` and `3.25.0`.
- Retained: the standard `.context/` main-checkout path, the `EnterWorktree`-failure → `verdict: blocked` safety valve with its DR `worktree_isolation_waived` waiver, and complexity as a stage-sizing/effort/DR-fanout input — removed only as an isolation trigger.

## [3.22.1] - 2026-06-15

### Fixed

- **PL re-runs could overwrite the original plan.** `worktask.md` step 3a hard-coded `plan_file=planning-0.md` and `run_index: 0` on every init, colliding with PL0's increment algorithm, so a re-run in a populated `.context/` sometimes clobbered `planning-0.md`. The seed is now re-run aware (glob and increment to the next free `planning-N`), PL0 is marked the authoritative writer that recomputes N and never overwrites an existing file, and the three seed templates were reconciled with `run_index` restored as a required field.

## [3.22.0] - 2026-06-15

### Added

- **`request-plan` skill and command** — turns a free-form request into a lightweight, context-aware plan and recommends the worktask trigger to execute it.

## [3.21.0] - 2026-06-14

### Added

- Android skills.

## [3.20.0] - 2026-06-14

### Added

- **`frontend-developer` wired into the DV router.** The web detection row was matching but routed to a placeholder ("typescript/javascript"), so web front-end DV work fell through with no specialist. Adds 9 `Task(frontend-developer:*)` scopes, retargets the web detection row, adds a Web Platform Specialization table parallel to Apple/Systems, and adds a web-vs-native precedence note (UI layer → frontend, native module → `apple-developer:*`). Web reuses the existing `web_adapter` screenshot path (`requires_screenshots: true` by default, with Lighthouse/axe as evidence).

## [3.19.0] - 2026-06-14

### Added

- **`backend-developer` wired into the DV router.** With no back-end specialist, web/service files fell through to the generic developer or to `system-developer`'s language agents, which do not own the web-framework, API-contract, or persistence layer. Adds `Task(backend-developer:*)` targets and a backend detection-rules block with Python-language-vs-web and front/back `package.json` precedence notes.

## [3.18.0] - 2026-06-13

### Added

- **`system-developer` wired into the DV router** for C/C++/Python/Bash. Adds a `systems` platform with detection rules for `.c`/`.cpp`/`.py`/`.sh` plus build markers — closing a previously unhandled `.py` routing gap — specialist routing tables, `Task(system-developer:*)` delegations, and a `systems` → `cli_fallback_adapter` screenshot row. `cross-plugin-handoff` gains the system-developer stage protocol table and notes the `requires_screenshots: false` / CLI-fallback norm for non-UI systems work.

## [3.17.0] - 2026-06-12

Claude Code 2.1.171–2.1.175 band (2.1.171 never published), with an explicit sub-agent focus.

### Changed

- **5-level nested spawning (2.1.172)** retires every "cannot spawn sub-subagents" claim, activates `/cost-report` `dispatch_depth`, and starts the audit-dedup base→extended cut-over.
- **Managed `availableModels` now constrains subagent model overrides** (2.1.172), and `enforceAvailableModels` (2.1.175) constrains the default model — `metadata.model` may silently down-resolve, so Pre-Stage Validation step 6 audits the resolved model instead of trusting the alias.
- **Fable 5 is 1M-context by default (2.1.173)**, and dispatch fails outright without 1M credits (observed live) — hence degrade guidance in `model-selection` and `context-compression`, plus new dynamic-workflow risk R8 (`agent()` `opts.model` override not honored under credit gating).

### Fixed

- Four fable-blind `3.13.0` drift bugs: the worktask alias check, `optimize-agent` audit rows, headless DV/SR/DR pins, and the task-system model row.

## [3.16.0] - 2026-06-12

### Added

- **Screenshot-to-surface wiring** — DV screenshots embed into the issue and the PR on a UI change, via two new helper scripts, a new REQUIRED plan-metadata field, and a new orchestrator loop-exit step. Additive and backwards-compatible.

## [3.15.0] - 2026-06-10

### Changed

- **Progressive disclosure across the worktask surface** — situational SKILL.md sections moved into `references/` and are Read at trigger points rather than carried ambiently. No renames; all H2 headings and stage codes preserved. Four commands and several agent sections that merely restated their companion skill were thinned, and an orphan `team-communication.md` plus dead sub-2.1.169 version qualifiers were deleted.
- **`MEMORY.md` moved to a lean rolling format** with cc-update maintenance rules.

### Added

- **`desc-lint.sh`** lints all 84 frontmatter descriptions against the 250-character ambient cap (multi-line YAML scalar aware, with `--self-test`).

## [3.14.0] - 2026-06-10

### Breaking

- **Pre-2.1.169 backward compatibility retired** — resume degrade tiers collapsed to one baseline, the legacy unnumbered artifact-name grace dropped, and sub-floor provenance tags stripped. Min CC raised to 2.1.169.

### Added

- **A Fable model tier above `opus`**, with 6 agents (AR, DR-TC, DV, PE, SR, ET) routed `opus` → `fable`.

## [3.12.1] - 2026-06-05

### Fixed

- **Layer-3 state merges silently missed whenever agents wrote numbered artifacts.** The `SubagentStop` state-merge hook mapped stages to bare filenames while the canonical contract uses numbered `stage-N.md` artifacts, so only Layer 1/2 saved state. The resolver now prefers an exact `run_index` match, then the highest N, then the bare legacy filename. Also fixes a latent `yq` two-document double-verdict bug via `select(documentIndex==0)`.

## [3.12.0] - 2026-06-05

Claude Code 2.1.157–2.1.165 band.

### Added

- **Self-healing gates** via `hookSpecificOutput.additionalContext` (2.1.163), injecting DR/QA blockers automatically.
- **Precise resume** using the `waitingFor` field from `claude agents --json` (2.1.162).
- A required Worktask Efficiency Analysis pass in the `cc-update` command.

## [3.11.4] - 2026-06-05

### Fixed

- **The OV-56 screenshot-gate bypass class**, where a headless DV deferred screenshot capture in prose, DR waived the absent manifest, and the bypass merged. `hooks/dv-screenshot-gate.sh` (a `SubagentStop` block hook) filesystem-verifies `screenshots.md`, the DR manifest gate became non-waivable, and a PM Figma placement guard keeps frames in `.context/designs/` and never in `images/`.

### Added

- **DV result images wired into QA's authoritative Design Comparison** through an optional Design Ref join column, running an RMSE pixel-diff pre-pass as a one-way escalator before multimodal vision; live re-capture becomes the fallback rather than the default. Strictly additive.

## [3.11.2] - 2026-06-05

### Fixed

- **Figma screenshot embeds did not render on private or internal repos.** `raw.githubusercontent.com` URLs are served camo-anonymously for those repos, so GitHub refuses to render images not pre-verified as publicly accessible — and the raw tier was used regardless of visibility. The render-verification gate was rewritten with camo-anonymous semantics: PRIVATE and INTERNAL repos now refuse the raw tier and degrade to the next viable one (repos-contents API → releases asset), so only GitHub-blessed URLs get embedded. The tier-0 user-attachments path ships opt-in and OFF by default (`ASSET_UA_ENABLE`) — investigation confirmed it is not viable with `gh` CLI auth (`gh api POST` returns 404, `curl` Bearer POST returns 422; the token is not a web session), so it is reserved as a forward hook only.

### Added

- A durable DV-routing rule: worktask-infra changes (`publish-pl-issue.sh`, state machines, hooks) route DV to `workflow-engineer`, not to a platform developer.

## [3.11.1] - 2026-06-01

### Added

- **Figma screenshots render as real images in the published PL issue** instead of plain-text `.context/` paths, which GitHub cannot render and the sanitiser strips anyway. PM authors the design-preview anchor with `{{asset:<basename>}}` placeholders, and `publish-pl-issue.sh` resolves them to hosted image lines *after* `sanitise_body` runs — so the image lines survive Pass-1 L1 and no local path leaks. Hosting degrades non-blocking: `raw.githubusercontent.com` → gist → URL-only note. Also lands the per-frame Figma capture work this builds on: in-turn curl persistence, `figma-registry`, per-frame QA comparison, and the canonical `.context/designs` asset directory.

## [3.11.0] - 2026-05-29

### Added

- **Opt-in `--dynamic` execution mode**, running the gate-free AR→QA span on Claude Code's native Workflow engine (2.1.154+) instead of the manual orchestrator loop — real parallelism via `phase()`/`parallel()`, per-stage budget control, and milestone fan-out via `pipeline()`, while PL0 and FN stay human-gated orchestrator stages. Additive and backwards-compatible: nothing changes unless `--dynamic` is set *and* the Workflow tool is present; absent either, a `dynamic_fallback` audit event fires and the manual loop continues. Removed again in `3.26.1`.

## [3.10.13] - 2026-05-29

### Changed

- **Opus 4.7 → 4.8 documentation refresh** — high effort default, `/effort xhigh`, fast mode at 2× rate / 2.5× speed, lean system prompt default, and 1M context. Adds complementary positioning of native dynamic workflows against the staged pipeline, the `MessageDisplay` and `SessionStart(reloadSkills)` hooks, `disallowed-tools` frontmatter for skills and commands, the `worktree.baseRef: "head"` fix, and updated cost baselines.

## [3.10.12] - 2026-05-27

### Fixed

- **Merged PRs did not auto-close their issues.** Workflow PR bodies lacked the `Closes #N` keyword, so GitHub's `closingIssuesReferences` stayed empty. Adds a 4-rank issue-number resolver (`state.json` `metadata.github_issue_url` → `metadata.github_issue_number` → branch trailing digits → first `#NNN` in the last 5 commits) and an FN pre-`gh pr create` validator that blocks when the keyword is missing and an issue is known, or audit-defers when no issue resolves. The closing line was added to the PR-body templates in all four canonical locations.

## [3.10.11] - 2026-05-27

### Fixed

- **Figma capture intent was silently lost when the MCP server was not pre-authenticated.** PM now probes `mcp__plugin_figma_figma__get_screenshot` before writing the plan when the task description contains a `figma.com` URL. On auth failure (`authenticate`/`OAuth`/`unauthorized`/`401`) it emits a single user-facing line with the OAuth URL, logs `q1` to `state.json` `open_questions`, and continues plan authoring without the screenshot — a soft halt rather than a silent deferral to DV. Non-auth failures fall through to the existing per-URL failure path.

## [3.10.10] - 2026-05-26

### Changed

- **Published GitHub issues are readable again.** The `## Planned Stages` section exposed plugin internals — stage names, agent IDs — that were never meant for external readers; it was dropped from both the live render and the abort-dump branch, and its contribution to the strip-ratio denominator removed.

### Added

- **Defense-in-depth identifier-leakage scrub**: PM authoring hygiene (a new subsection plus rewrite examples) as Layer A, and sanitiser Pass-1 L10 (verb-leading line drop) plus Pass-2 A6 (strict known-prefix token strip) as Layer B, with backtick passthrough preserved so code fences survive.
- **An optional `## Design Preview` section** between Scope and Complexity when PL captures a Figma URL, with its bytes excluded from the strip-ratio denominator. Helper self-test 18 → 22 assertions, all passing.

## [3.10.9] - 2026-05-26

### Added

- **`dv-screenshot-capture` skill**, so DV stages produce visual evidence (1–N PNGs under `.context/images/<workflow_id>/`) that QA and DR consume during validation. Four adapters route by platform (apple → XcodeBuildMCP, web → headless browser, android → adb, all/fallback → silicon), with a manifest-first attachment (`screenshots.md`) that is portable across forges, a uniform `capture(slug, platform, args) → {path, bytes, ok, error}` contract, a size budget (200KB warn / 500KB fail / 5-cap), 7 audit actions, and a `metadata.requires_screenshots` gate defaulting to true. Verbatim prompt deltas land on `developer.md` (completion gate), `qa-engineer.md` (Q1.5 visual-evidence ingestion), and `technical-lead.md` (visual-evidence review bullet).

## [3.10.8] - 2026-05-26

### Fixed

Three bugs surfaced by the OV-113 run:

- **Missing GitHub labels were masked as `network_error`.** `ensure_labels()` now queries `gh label list` and creates any missing label with a deterministic colour/description map; a failed create appends to `dropped_labels`, drops the label from the `--label` argument, and records `labels_dropped` in the success audit. Idempotent on re-run.
- **No external-ticket awareness.** `extract_external_ticket()` matches `^[A-Z][A-Z0-9]+-[0-9]+\b` against `facts.goal` and threads the result into the title, a `ticket:<prefix>` label, `state.metadata.external_ticket`, and the audit row.
- **PM flipped downstream stage tasks to `in_progress` during PL0.** `agents/product-manager.md` now explicitly prohibits `TaskUpdate(status: "in_progress")` against any task other than its own PL0.

### Added

- **A failure-mode taxonomy** via `classify_gh_failure()` — `label_create_failed`, `gh_api_error`, `gh_timeout`, `permission_denied`, `repo_not_found`, `auth_missing`, `network_error` — with `network_error` reserved for genuine transport failures only.
- **An opt-in `--strict` flag** (also `metadata.gh_issue.strict`) that blocks the workflow on operational failure; the non-blocking default is preserved. Self-test extended 5 → 18 assertions.

## [3.10.7] - 2026-05-26

### Added

- **Collision-safe agent-naming guidance** adopted from upstream: Claude Code keys agents by frontmatter `name`, and cross-plugin name collisions silently overwrite. Generic stems (`developer`, `qa-engineer`, `incident-responder`, `designer`, `technical-writer`) are collision-prone, so new agents should prefer `<plugin>-<role>`; `/optimize-agent` flags violations as P1.
- **A description-trigger MUST for commands**, with an explicit exemption for slash-only (`disable-model-invocation: true`) and path-triggered (`paths:`) skills, which bypass description-based auto-invocation and must not be flagged.

## [3.10.6] - 2026-05-25

Claude Code 2.1.143–2.1.150 band, in six integrations around two upstream features.

### Added

- **`claude agents --json` live session discovery** wired into the resume procedure, eliminating orphan-respawn token waste.
- **OTEL `agent_id`/`parent_agent_id` trace parenting**, with forward-compatible hook-stdin capture and an audit-row dedupe migration via an opt-in `dedupe_key_extended` field plus auto-detection in `audit-dedup.sh`.
- `background_tasks`/`session_crons` hook capture and a `/cost-report` Background Activity table. All additive — the existing `dedupe_key` is preserved.

## [3.10.5] - 2026-05-22

### Fixed

- **The GitHub-issue publish step could silently no-op with no audit trail.** Both invocation sites called the helper as `bash skills/workflow/references/publish-pl-issue.sh; true` — a bare relative path resolved against the orchestrator's CWD, not the plugin root. When the worktask ran from a project directory where the plugin is not the CWD, the file was absent, `bash` failed, and the mandatory `; true` swallowed the non-zero exit, making the failure indistinguishable from a legitimate deferral. Both sites now resolve via `${CLAUDE_PLUGIN_ROOT}` behind a `[ -f ]` guard that emits a `helper_not_found` audit row when the file is unreachable. The same bare-relative bug in the `workflow-engineer` runbook (`hook-install.sh`, `cache-lint.sh --filename-lint`) was fixed too. The helper script itself is unchanged.

## [3.10.4] - 2026-05-20

### Added

- **A sanitised GitHub issue is auto-published after PL approval**, via a new `publish-pl-issue.sh` helper (~330 lines) invoked at orchestrator step 6.5. A two-pass sanitiser guarantees no `.context/` paths, absolute paths, workspace IDs, or artifact filenames reach the published body: pass 1 strips whole lines on rules L1–L9, pass 2 strips `Foo.swift`-shaped tokens unless an A1–A5 allow-list rule fires (code fence, inline code, `symbol:` prefix, narrative bullet, extension outside the deny-list). A strip ratio above 50% aborts the publish and persists the partial body for inspection. Milestone mode skips publishing entirely — the parent milestone issue stays the canonical record. Non-blocking by contract: every operational outcome exits 0 with an audit row. Ships with 5 fixtures and `--self-test`, a `github_issue_created` audit action, `state.json` `metadata.github_issue_url` for FN PR linkage, and a `--no-gh-issue` opt-out.

## [3.10.3] - 2026-05-19

### Changed

- **Six systematic token-waste patterns addressed**, found by analysing 7 real worktask sessions that hit usage limits and not covered by existing optimizations: a Read-Once Protocol (`facts.files_read` in `state.json` lets DR/QA use `git diff` instead of full re-reads, 15–25% on downstream stages); mandatory git/grep batching (combined commands, alternation patterns, a zero-result protocol, 5–15%); Edit-Batch-Build at DV D1 (plan all edits, apply all, build once, fix all errors in one pass, 5–10%); an MCP session cache (`mcp_session` in `state.json` so DV skips redundant `session_show_defaults`/`list_sims`/`list_schemes`, 3–5%); targeted reads (files over 200 lines must use offset/limit, 2–5%); and reduced `TaskList` polling (2–3%). All backward-compatible — the new `state.json` fields have explicit fallback language. Estimated 25–40% reduction in wasted tokens per session.

## [3.10.2] - 2026-05-18

### Fixed

- **`state.json` was never patched after PL0** because all three enforcement layers were unwired. This wires them: `state-merge.sh` registered in `plugin.json` (Layer 2), inline atomic-merge snippets added to all 13 stage agents (Layer 1), and orchestrator step 6.5 tightened to invoke the hook explicitly (Layer 3). Adds a `hook-install.sh` installer, a `--filename-lint` mode for `cache-lint.sh`, and a `workflow-engineer` troubleshooting runbook.

## [3.10.1] - 2026-05-15

A cross-axis audit (worktask logic, `/optimize-agent` and `/optimize-command`, CC 2.1.0–142 utilization) surfaced 2 P0 / 9 P1 / 8 P2 findings; this ships the text-safe subset, deferring behaviour-changing items to the `3.11.0` roadmap.

### Fixed

- The FN gate logs `fn_gate_invalid_value` when `PL0.metadata.fn_gate` is outside `{required, bypass}` — still fail-closed by default.
- Pre-stage validation step 8 emits an `artifact_path_resolved` audit row for early `run_index` drift detection.
- The `subagent_stopped` dedupe key extended to `<session>:<agent>:<task>:stop`, disambiguating back-to-back DV split-task retries where `agent_id` is constant.
- **DR3.5 warning escalation**: a non-empty test-selection warning log now routes to `errors/developer.md` as `ambiguous_requirements` and forces `verdict: fail` for `unknown_symbol`/`missing_marker` kinds, instead of being filed silently under findings.

### Added

- `facts.goal` (≤240 chars) in the `state.json` schema, superseding the `/goal` slash directive that would have been a drift-prone second surface.
- `audit-dedup.sh` — a canonical jq filter that groups audit rows by `metadata.dedupe_key` and keeps only `hook:*` rows on collision, preventing double-counted hook+agent pairs.

## [3.10.0] - 2026-05-15

An audit of 20 high-value CC 2.1.110–2.1.142 features found 14 documented but never wired. This release moves the inter-agent communication primitives from prose instruction to plugin-enforced runtime.

### Added

- **Four new plugin hooks** — `audit-tooluse`, `audit-subagent`, `precompact-checkpoint`, `agent-stop` — each with `--self-test` (4/4 pass), plus a `plugin.json` hooks block wiring `PostToolUse`, `SubagentStop`, `PreCompact`, and `Stop(type: mcp_tool)`.
- **A hook-authored audit trail**, `PreCompact` state checkpoints (`state.checkpoint-*.json`), agent-frontmatter lifecycle hooks on PL/FN/ST, effort capture in `cost-log`, and `mcp_tool` `PushNotification` at the PL/FN gates.
- `cost-log.sh` captures `CLAUDE_EFFORT`; `/cost-report` gains an Effort Distribution table.
- A dedupe protocol so agent-emitted rows stay forward-compatible: hook rows carry `actor: "hook:<name>"` and a `metadata.dedupe_key`, and the hook row wins on collision.

Min CC unchanged at 2.1.114 — `mcp_tool` needs 2.1.118 but degrades gracefully.

## [3.9.4] - 2026-05-15

### Added

- **A worktask ↔ `claude agents` flag bridge** — a new `headless-dispatch.md` maps `task.metadata` to CLI flags with per-stage one-liners, and 7 optional dispatch-metadata fields are documented (`effort`, `permission_mode`, `add_dirs`, `mcp_config_path`, `plugin_dir_overrides`, `dangerously_skip_permissions`, `settings_path`). PL0 writer rules: `permission_mode=default` on SR/FN under `--secure`/`--full`, `effort=xhigh` on DV when complexity ≥ 35.
- Claude Code 2.1.141–2.1.142 documentation (folded in from the `3.9.3` increment): fast mode defaulting to Opus 4.7, hook terminal sequences, hook config error hints, and pre-existing worktree reuse.

## [3.9.2] - 2026-05-13

### Changed

- Claude Code 2.1.129–2.1.140 documented: subagent skill discovery, hook `effort.level` and `$CLAUDE_EFFORT` (2.1.133), `worktree.baseRef` (2.1.133), hook exec-form `args[]` and `PostToolUse` `continueOnBlock` (2.1.139), and case/separator-insensitive `subagent_type` matching (2.1.140). 2.1.130/134/135 were never published; 2.1.137 is VSCode-Windows-only; 2.1.138 was internal fixes.

## [3.9.1] - 2026-05-13

### Changed

- **Handoff Protocol boilerplate centralized** from 13 stage agents into a single source in `skills/shared/stage-contracts.md` — roughly 245 duplicated lines removed, with each agent's section dropping from ~30–40 lines to 10–14. The YAML payload stays inline for paste-source ergonomics. No runtime contract change: agents read the same `state.json` and emit the same `handoff:` frontmatter, only the prose moved. This release also formally carries the `3.9.0` Test Selection Gate feature line, whose version bump had been reset by the `3.8.3` marketplace sync.

### Added

- **Cache observability** — `cost-log.sh` captures `cache_read_input_tokens` and `cache_creation_input_tokens`, and `/cost-report` surfaces a Cache Performance table with hit ratio, sub-60% row flags, and F1-fallback counts.
- **`cache-lint.sh --frontmatter-template-lint`** to prevent re-drift: each stage agent must have exactly one YAML block under `## Handoff Protocol`, with the canonical `stage:` value and ≤30 lines. 7/7 self-tests pass; all 13 agents pass at 10–14 lines.

## [3.9.0] - 2026-05-09

### Changed

- **Binary `requires_ui_tests` replaced by a three-mode `test_mode`** (`build-only` | `scoped` | `full`), plus inline source markers (`@test-required`, `@depends-on:`, `@test-tag:`) that DV parses into a Selected Tests list consumed by QA. A change to `Foo` retests `FooTests` *and* anything marked `// @depends-on: Foo`. `requires_ui_tests` is aliased to `scoped`/`full` for one release cycle.
- Reviewer-driven adjustments worth recording: the effective default for unannotated plans is `scoped`, not `build-only`, so untagged repos do not suffer a silent coverage blackout; `build-only` still runs the smoke set (`@test-required` plus `always_required_tests`) rather than zero tests; auto-promotion safety nets cover both empty-selection and missing-platform-handler cases; and DR reads the warning log to catch silent test drops.

Note: `plugin.json` was reset to `3.8.3` two days later by the marketplace sync, so this feature line formally shipped under `3.9.1`.

## [3.8.3] - 2026-05-11

### Fixed

- Marketplace and plugin versions synced to `3.8.3`, and the smoke-set definition and `build-only` mode label corrected.

## [3.8.2] - 2026-05-08

### Changed

- **Token and communication enhancements** without touching agent roles or stage contracts. The model cost-tier table was deduped to a single source in `shared/model-selection`, and a per-effort thinking-budget matrix added (`low ≤4K`, `medium ≤16K`, `high ≤32K`, `xhigh ≤50K`, `max ≤64K`).

### Added

- `metadata.skip_exploration` and `exploration_anchors`, stamped by PL0 and used by AR/TL to short-circuit redundant `Glob`/`Grep` when PL has already explored.
- Anchor pre-flight via a `PostToolUse` hook spec, catching missing artifact anchors at the producing stage rather than post-hoc at the DR gate.
- F1 fallback telemetry — agents log to `.context/logs/fallback-N.log` when `state.json` is absent, surfacing silent cache degradation.
- An error-file lazy-create guard: a missing `metadata.error_file` on disk is treated as `retry_count = 0` instead of a validation failure.

## [3.8.1] - 2026-05-05

### Changed

- Claude Code 2.1.122–2.1.128 documented: the Bash sibling cascade scoped to mutating calls only (2.1.128), four token-baseline rows appended (subagent summary cache, idle throttle, read-only Bash sibling safety, 1M autocompact threshold), and the manual `origin/develop` recipe distinguished from the `EnterWorktree` tool default, which branches from local HEAD as of 2.1.128. 2.1.124/125/127 were never published.

## [3.8.0] - 2026-05-03

### Breaking

- **Stage artifacts are numbered by `run_index`.** PL0 propagates N to every downstream stage, so each run produces `analyzing-N.md`, `coordination-N.md`, `development-N.md`, and so on, and atomically resets `state.json` on a new run. Four basenames were renamed in the same pass: `release-prep` → `release`, `complete` → `complete-summary`, `incident-report` → `incident`, `approval` → `retrospective`. Legacy unnumbered filenames are accepted as a fallback for one release cycle.

## [3.7.0] - 2026-05-02

### Added

- **Handoff-protocol redesign** — a `state.json` ledger plus a `handoff:` YAML frontmatter schema, with a cache-friendly preamble layout `[1][2][3][4][5][6][7]` applied across 12 stage agents, 7 skills, and 1 command. Additive; no breaking changes.

## [3.6.1] - 2026-04-28

### Changed

- Claude Code 2.1.115–2.1.121 integrated (14 features across 5 published versions; 2.1.115 and 2.1.120 were never published), touching the developer agent, the agent-coordination skill and its hook-monitoring reference, and the shared stage-codes and model-selection skills.
- **`cc-update` routing rules**: a new binding Workflow Routing section forcing `prompt-engineer` ownership when embedded in a worktask, a batch bump-policy block, an edge-case rewrite documenting the curl/jq fallback, and a "do not self-commit inside the worktask" instruction.

### Known Considerations

- DR flagged the bundle as scope drift and read strict policy as mandating MINOR; a user directive fixed PATCH, and the disagreement was recorded in the run artifacts. QA verdict was GO at 13/14 checks.

## [3.6.0] - 2026-04-20

Claude Code 2.1.114 integration and an agent effort rebalance. Min CC raised to 2.1.114.

This is also where the Phase A and Phase B+C+D worktask-enhancement work landed. Those commits briefly carried `3.7.0` and `3.8.0` version labels before `plugin.json` was reset to `3.6.0` the same day; the content stayed, and both version numbers were re-issued in May for different work.

### Added

- **A DR (Developer Review) stage** in the pipeline.
- **Phase A** — `skills/shared/stage-contracts.md` with per-stage Inputs → Outputs → Validation and an `error_file` for every stage; a Mermaid error decision tree and retry/escalate matrix classifying failures as transient, logic, missing_input, ambiguous_requirements, design_flaw, hard_constraint, or exhausted; a JSON Schema for task metadata; and a clean-cut migration from `.context/error.md` to per-agent `.context/errors/<agent>.md`, which is parallel-safe for QA+DC, TL-split DV, and milestone tracks.
- **Phase B (observability)** — per-stage cost tracking via a `SubagentStop` hook writing `.context/logs/cost-*.jsonl`; an append-only `audit.log` JSONL trail with a `{ts, actor, action, subject, result, task_id?, artifact?}` schema; stage timings in the FN summary template.
- **Phase C (resilience)** — a resume protocol mapping `TaskList()` shape to action with a 6-step procedure driven off the audit-log tail; an approval-gate `PreToolUse` hook with a two-phase advisory-then-blocking rollout; an 8-row worktree partial-failure matrix; and soft validation of context files that warns rather than aborts.
- **Phase D (UX)** — an 11-state workflow state machine diagram, and ethics-gate auto-detection at PL0 via weighted keyword scoring that inserts ET0 at score ≥ 5.

### Changed

- **Effort rebalanced**: the Opus 4.7 `xhigh` tier adopted for `software-architector`, `security-reviewer`, and `prompt-engineer`; `ethics-reviewer` promoted from sonnet/medium to opus/high for nuanced constitutional judgment; `project-manager` trimmed to medium; `stakeholder` raised to medium.
- `qa-engineer` retiered haiku → sonnet, justified by 19 tools including XcodeBuildMCP and multimodal design comparison.

### Fixed

- **Orchestrator delegation guardrails** to prevent direct implementation, and an enforced approval protocol with a pre-work prohibition and dual-signal checks.
- Security constraints and runtime-critical content that a prior token-optimization pass had removed.

## [3.5.0] - 2026-04-12

### Changed

- Ten Claude Code releases integrated (2.1.92–2.1.101): the Monitor tool, effort defaulting to high, `keep-coding-instructions` frontmatter, skill name resolution, MCP dynamic inheritance, subagent worktree access, and 15 security hardening fixes. Min CC raised to 2.1.101. Absorbs the `3.4.0` band increment (2.1.87–2.1.91), which was documented but never shipped under its own number.
- Skill directories renamed and reorganized; embedded command detection and execution added.

## [3.3.0] - 2026-04-08

### Added

- **`effort` and `maxTurns` frontmatter on all 16 agents** (CC 2.1.78+) for cost control and thinking-depth tuning: `high` for deep-work agents (developer, architector, security, tech-lead), `medium` for coordination agents, `low` for structured-output agents, with `maxTurns` calibrated 20–80 by role complexity. `SKILLS.md` renamed to `SKILL.md`.
- **Figma screenshot capture at PL** and design comparison at QA; a shared exploration cache to eliminate cross-stage file re-reads.

### Fixed

- The approval gate enforced via tool restrictions rather than prose, with multi-plugin agent dispatch supported.
- Stage agents spawned with an explicit model parameter, instead of relying on inheritance.

## [3.2.0] - 2026-03-15

### Changed

- Commands and features updated for Claude Code 2.1.72–2.1.76; agents and commands optimized against the official Claude plugins patterns.

## [3.1.0] - 2026-03-08

### Added

- Claude Code 2.1.51–2.1.71 optimization features: ultrathink mode (high-effort Opus reasoning), hook events carrying `agent_id`/`agent_type` payloads (2.1.69+), HTTP webhook support for external monitoring (2.1.63+), and improved subagent result recovery (2.1.71+). `claude_code_min_version: 2.1.51` added.
- `/appstore-iap` and `/appstore-info` commands for App Store automation; `/create-command` and `/create-skill`; agent teams support with tool restrictions.
- Worktree support for parallel milestone execution (CC 2.1.49+), and range-based story points (Min/Max) in estimation.

### Changed

- Designer mockups migrated from SVG to Pencil MCP, with automatic Designer invocation based on prompt context.

## [3.0.0] - 2026-01-30

### Breaking

- **The pipeline expands from 8 stages to 10**, with three new stage-owning agents: `security-reviewer` (SR, OWASP compliance), `release-engineer` (RE, versioning and deployment readiness), and `incident-responder` (IR, production hotfixes). Adds comprehensive cross-plugin handoff patterns for marketplace integrations.
