# company-workflow Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **4.0.9** — opt-in change→test selection: a three-layer dependency matrix
  (L1 derived-live path rules, L2 `tests/selection/matrix.tsv` glob table, L3 an ALWAYS floor)
  behind `./run-tests.sh --changed`, so an edit to one agent, command, skill, hook, or script
  runs only the dependent `.bats`. Fail-closed on seven triggers (F1-F7) — unknown path, tooling
  edit, or absent base all widen to the full suite. DV selections over 50% of the tree exit 65
  and hand the run to QA rather than letting DV run the suite it lacks authority for. The
  execution gate is argument-aware. Default behaviour is unchanged: bare `./run-tests.sh` is
  still a full run. Full narrative: `CHANGELOG.md § [4.0.9]`.

### Previous release narratives

- Plugin version (previous): **4.0.8** — `state-patch.sh` idempotency guard now compares the whole
  patch (artifact and handoff edge, not just status and verdict), so a review-remediation loop that
  re-completes a stage at the same verdict refreshes `handoffs["PREV→CODE"]` instead of
  stranding it on pre-remediation prose. Identical inputs remain byte-identical no-ops.
  Regression coverage: self-test `T10` plus two `bats` cases, verified against the pre-fix
  script. Observed twice in one worktask (`AR→DV`, `DV→DR`), once on a review agent's own
  patch. Full narrative: `CHANGELOG.md § [4.0.8]`.

- Plugin version (previous): **4.0.7** — branch naming R1-R4 (title-driven `--goal`, end-to-end
  truncation visibility, one-shot pre-commit refinement via new `refine-branch-target.sh`) plus
  the once-only rename invariant reconciled across 8 docs. Orchestrator recommendation was `4.1.0`
  (MINOR: new script, new public `--print-target` flag, three new `branch-lib.sh` functions,
  new pipeline step A.4b); user decided `4.0.7` at the finalization gate — decision of record.
  Full narrative: `CHANGELOG.md § [4.0.7]`.

- Plugin version (previous): **4.0.6** (Test-execution gate closes the flag-carrying full-suite hole at DV: the
  classifier now strips each runner's mandatory non-selecting flags — quote-aware, so
  `-destination "platform=iOS Simulator,name=iPhone 16 Pro"` no longer reads as a narrowed run —
  before deciding whether an argument survived. `xcodebuild`/`dotnet`/`gradle`/`npm`,`pnpm`,`yarn`/
  `cargo --release` full runs invert allow→deny at DV; genuine selectors still allow. The `-c`
  generalisation additionally fixed two PRE-EXISTING false denies (`go test -c`, `rspec -c`), and
  the `--only-testing:` double-dash spelling defect — a selector limb that never matched a real
  invocation — is corrected; the gradle task token is found order-independently, so
  `gradle -p . test` denies like `gradle test -p .` (and flags-first build-only tasks such as
  `gradle -p . assembleAndroidTest` stop false-denying). Fixtures 24→40 self-test, 58→80 bats.
  Prose reconciled in the same
  patch: the authority matrix's DV row documented the bug as the contract, and the finalization
  stage's own duty list, checklist and shared stage-table row instructed it to run tests it is
  forbidden and unable to run — FN now verifies QA's recorded evidence instead. Known limits stated
  rather than buried: whole-tree positionals (`go test ./...`) still read as scoped, and
  `npm|pnpm|yarn test -- -c <spec>` denies though genuinely scoped — accepted because the
  alternative reopens the hole. Previous release 4.0.5 — test-suite stringency hardening: 45 `.bats` / 501 `@test` → **53 / 680**,
  every claim re-derived by mutation rather than ratified. Six production defects fixed, each landing
  in one commit with the pinned "KNOWN BUG" test flipped to assert correct behaviour. One is a
  **downstream security disclosure**: `scan-secrets.sh` recovered each rule's regex with a greedy
  `${entry##*|}`, truncating the only built-in pattern containing an alternation, so **no released
  version ever detected `mysql://`/`postgres://`/`mongodb://` credentials on any `grep` dialect** —
  GNU rejects the unmatched `)`, BSD accepts it as a literal, and the `2>/dev/null` hid the former.
  Runner integrity: `make coverage` no longer discards the Python phase's exit code, `run-tests.sh`
  reports skipped phases and gains an opt-in `RUN_TESTS_REQUIRE_SWIFT` gate. 7 additive bats helpers
  (`run_script` frozen, byte-identical); `examples/tictactoe`'s 1817-line byte-identical duplicate of
  `benchmark/ttt-template` deleted; a `coverage-proxy` meta-gate now reds when a script has no
  dedicated `.bats`; `state-merge.sh` repairs a corrupt ledger backup-first instead of no-oping.
  Known-unfinished, disclosed rather than smoothed: `make coverage` is unreachable-clean on macOS
  (pre-existing kcov runaway), `scan-secrets --self-test` still covers 2 of 6 patterns, and
  `run-tests.sh`'s clean-clone guarantee silently requires `python3 >= 3.10`.
  Previous release 4.0.4 — gate-revision semantics + 4 rule fixes. The spec carried ONE concept
  ("a PL invocation") where the pipeline has TWO — a new run (allocate N+1, reset facts, create
  tasks) vs a revision of the run in flight (reuse N, edit in place, preserve facts, update
  tasks); only the first was specified. Plan-gate rejection now routes to
  `commands/worktask.md § Plan-revision re-dispatch`: `run_index`/`plan_file` FROZEN for the life
  of a run, PM re-dispatched with `plan_revision: true`, four BINDING invariants (edit
  `planning-N.md` in place / patch `facts.*` additively / `TaskUpdate` not `TaskCreate` / no issue
  re-publish), `revision_count` + one `plan_revision_dispatched` audit row, plan gate re-entered on
  return. Fixes four field failures: `facts.decisions[]` silently wiped by the Step-4 reset, a
  forked plan file, a duplicated stage chain stranded at `run_index: 1`, and a split
  `<worktask_id>:<run_index>:gh_issue` anchor. The FN gate gains the symmetric reject-resume path
  (`skills/worktask/SKILL.md § FN gate rejection`) — route to the owning stage, index frozen,
  completed stages never re-run wholesale, gate re-presented on completion. Rule fixes:
  `prompt-engineer` gains the `Skill` tool grant (its mandatory embedded-command contract was
  unrunnable) and a DV-stage yield-discipline pointer to `workflow-engineer § Batch-Completion
  Discipline`; `product-manager` extends the staleness rule from FILE lists to `file:line`
  citations (approximate locators — re-locate by quoted text) and closes the `(unverified)` escape
  hatch on AC verification commands (the mark covers the RESULT's representativeness, never the
  command's validity — a shipped `grep -viv` triple negation reported everything "clean"). Spec/
  docs only — no script, hook, or test-logic changes. Previous release 4.0.3 — Round 1:
  deprecation cleanup + compaction across `agents/`,
  `commands/`, `skills/`: every elapsed-sunset rules deprecation removed — legacy `--auto-plan`/
  `--auto-finalization` aliases, the sunset `requires_ui_tests` compat-mapping table, `igrsoft`
  rename residuals outside the vendor-identity allow-list, 21 of 42 stale pre-4.0 version gates —
  plus a token-compaction pass, 34,119 → 34,035 tracked markdown lines. Round 2 — user-approved
  aggressive legacy-*logic* removal (13 themes) across hooks, scripts, tests, and the benchmark
  harness: the dual dedupe-key mechanism (`metadata.dedupe_key_extended` + `skills/agent-coordination/scripts/audit-dedup.sh`)
  deleted; pre-4.0 `.context/` read-compat dropped (bare-basename artifact resolver rung, pre-#375
  issue-title probe, single-file visual-evidence marker shape, `state.json .git.base_branch`
  fallback); redaction supersets removed (leak risk accepted for pre-4.0 identifiers);
  benchmark `tokens` block decoding now strict (all 5 keys required, no silent `None`s,
  `history.json` migrated in place); `state.mcp_session`, `--severity` legacy aliases, and the
  bare-name agent shim dropped. Zero stage/agent/gate semantics change on current-contract paths.
  BREAKING (round 1): the two legacy `--auto-*` flags are no longer recognised or documented
  (undefined effect, no parse error); a resumed pre-4.0 plan with `requires_ui_tests` and no
  `test_mode` now silently degrades to `scoped` test mode with no Design Comparison, no
  deprecation note. BREAKING (round 2): pre-4.0 `.context/` artifacts, issue titles, and visual-
  evidence markers no longer resolve via any compat path; redacted identifiers may leak into
  GitHub issue bodies on a pre-4.0 resume; a partial benchmark `tokens` block now raises instead
  of decoding. Previous release 4.0.1 — two silent publication-surface fixes. Branch naming: Step 3c is now unconditional — `branch_is_conventional()` is the SOLE authority, never an eyeball judgement, with a non-blocking post-check audit row; grammar gains an optional `<ticket>-` segment budgeted inside the 48-char cap; `derive_slug` stops cutting mid-word; `derive_type` matches `fix` as a word and knows defect vocabulary. `publish-pl-issue.sh`: issue title and `## Summary` resolve through independent fallback chains instead of sharing the optional `facts.goal`, whose absence published a kebab-slug title with an empty body; the slug rank is audited, the ticket-prefix guard is case-insensitive, and the recovery search probes the legacy title. Step 3a seeds `facts.goal`. Scripts + tests + docs only — no stage, agent, or gate semantics change. Previous release: plugin renamed `igrsoft` → `company-workflow`: every invocation id, the marketplace plugin entry, the `Stop` hook matcher, and the install cache path move to the new prefix; the six `IGRSOFT_*` environment variables become `COMPANY_WORKFLOW_*` with no fallback read. Vendor identity — author `IGRSoft`, `support@igrsoft.com`, the `github.com/IGRSoft` URLs, `com.igrsoft.*` bundle IDs, and the marketplace name — is deliberately unchanged. BREAKING: `igrsoft:*` ids no longer resolve and there is no back-compat alias. See release-history row below for the full changelog.)
- Claude Code min required: **2.1.220** (README.md is authoritative; nested delegation is off by default on 2.1.217–2.1.218 and the plugin's DV routing depends on it, so 2.1.219 is the functional floor — pinned to the band top per the v3.35.0 precedent)
- Claude Code latest integrated band: **2.1.216→2.1.220**

## CC Feature Band Index

Canonical band files live in the authoritative memory directory (`~/.claude/projects/<slug>/memory/`).

| Band | Canonical file | Plugin release |
|------|----------------|----------------|
| 2.1.216→2.1.220 | cc-features-2.1.216-220.md | v3.37.0 (nesting depth 5→3 + 20-concurrent cap; Opus 5 default; min CC → 2.1.220) |
| 2.1.210→2.1.215 | cc-features-2.1.210-215.md | v3.35.0 (MCP auto-background + spawn cap + "Needs input"; min CC → 2.1.215, version-gate cleanup) |
| 2.1.203→2.1.209 | cc-features-2.1.203-209.md | v3.34.0 (background-agent/worktree stabilization) |
| 2.1.185→2.1.202 | cc-features-2.1.185-202.md | v3.30.0 (background-default dispatch + Sonnet 5) |
| 2.1.176→2.1.183 | cc-features-2.1.176-183.md | v3.24.0 (agent-teams API) |
| 2.1.171→2.1.175 | cc-features-2.1.171-175.md | v3.17.0 (nested sub-agents) |
| 2.1.166→2.1.170 | cc-features-2.1.166-170.md | v3.13.0 (Fable 5) |
| 2.1.157→2.1.165 | cc-features-2.1.157-165.md | v3.12.0 |
| 2.1.151→2.1.156 | cc-features-2.1.151-156.md | v3.10.13 (top-Opus refresh) |
| 2.1.143→2.1.150 | cc-features-2.1.143-150.md | v3.10.6 |
| 2.1.141→2.1.142 | cc-features-2.1.141-142.md | v3.9.3 |
| 2.1.129→2.1.140 | cc-features-2.1.129-140.md | v3.9.2 |
| 2.1.122→2.1.128 | cc-features-2.1.122-128.md | v3.8.1 |
| 2.1.115→2.1.121 | cc-features-2.1.115-121.md | v3.6.1 |
| 2.1.102→2.1.114 | cc-features-2.1.102-114.md | v3.6.0 |
| 2.1.92→2.1.101 | cc-features-2.1.92-101.md | v3.5.0 |
| 2.1.87→2.1.91 | cc-features-2.1.87-91.md | v3.4.0 |
| 2.1.77→2.1.86 | cc-features-2.1.77-86.md | v3.3.0 |
| 2.1.51→2.1.76 | cc-features-2.1.51-76.md | v3.1.0/v3.2.0 |

## Release History (last 12, newest first)

- 2026-08-06: v4.0.9 — change→test dependency matrix, opt-in behind `./run-tests.sh --changed`
  (plus `--base <ref>`, `--print-selection`, and `COMPANY_WORKFLOW_TEST_SELECT=0` to disable).
  Three layers: L1 derived-live path rules, L2 a 24-row `tests/selection/matrix.tsv` glob table,
  L3 an ALWAYS floor of 47 tests that every scoped run includes. Selection is fail-closed —
  triggers F1-F7 (unknown path, edits to the runner/selector itself, missing base ref, and four
  others) widen to the full suite rather than under-run. A DV selection exceeding 50% of the tree
  exits 65 and hands off to QA, since DV has no full-suite authority. `hooks/test-execution-gate.sh`
  now classifies by argument. Deliberately not shipped: `make coverage-changed` — `--changed
  --coverage` is a hard exit 64, because kcov's denominator is the source set and does not shrink
  with the test set, so a scoped coverage number reads as a code regression rather than a
  measurement artifact — and module correlation, so a `SKILL.md` edit no longer pulls in that
  skill's script tests. The latter is the release's main residual false-negative risk, bounded by
  the reachability and non-script-coverage guards; the fix for any gap found in practice is a
  targeted matrix row, not a blanket rule. Bare `./run-tests.sh` is unchanged. Guard suite:
  `tests/shell/meta/test-selection.bats`.

- 2026-08-06: v4.0.8 — `state-patch.sh` idempotency guard widened from (status, verdict) to the
  full patch: it now also compares `stages.<CODE>.artifact` and, under `--prev`, the handoff edge
  the call would write. A DV→DR→DV remediation loop re-completes at the same verdict, which the
  old guard read as a no-op, leaving `handoffs["PREV→CODE"]` on the pre-remediation summary with
  no flag to correct it. Identical inputs still exit early byte-identical; a changed artifact or
  summary re-merges and logs `re-merge: ... artifact/handoff differ`. Regression coverage:
  self-test `T10` (refresh + third-run idempotence) and two `bats` cases, both verified to fail
  against the pre-fix script. Found in an apple-developer worktask where it fired twice
  (`AR→DV`, `DV→DR`) — the second on a review agent's own patch.

- 2026-08-06: v4.0.7 — branch naming R1-R4 (user decided PATCH at the finalization gate over
  the orchestrator's MINOR recommendation — see § Version Tracking): `--goal` takes a concise
  imperative title (was the raw
  task description, silently truncating mid-phrase into the slug); `BRANCH_NAME_PRINT=1` documented
  as a free preview, the "do not re-invoke" prohibition narrowed to rename mode only; truncation
  visible end to end (`slug_truncated=1`, `branch_slug_truncated` audit row, Step A.5 gate summary);
  new `refine-branch-target.sh` at Step A.4b refines the planned name once, pre-commit, ledger-only,
  no git mutation, exit 0 always. Once-only rename invariant reconciled across 8 sites (rename once
  at PL start; planned name refinable once more, pre-commit). `tests/COVERAGE.md` `@test` total
  680→683 (QA's 3 added cases). R5 (bare-issue ticket grammar), `cache-lint.sh:92` (non-deterministic
  on artifact content), and `state-patch.sh`'s completed-stage idempotency short-circuit deferred.
- 2026-08-05: v4.0.6 — test-execution gate: runner-aware, quote-aware strip of non-selecting flags
  closes the flag-carrying full-suite hole at DV (`xcodebuild`/`dotnet`/`gradle`/`npm`/`pnpm`/`yarn`/
  `cargo --release` invert allow→deny; genuine selectors unaffected). `--only-testing:` spelling
  defect fixed; `go test -c` / `rspec -c` / flags-first gradle false denies removed. Fixtures
  24→40 / 58→80. Prose
  reconciled: DV authority-matrix note no longer documents the bug as the contract, and FN's duty
  list/checklist/stage-table row now verify QA's recorded evidence instead of running tests FN is
  forbidden and unable to run.
- 2026-08-05: v4.0.5 — test-suite stringency hardening: 45 `.bats` / 501 `@test` → 53 / 680, bats
  `skip` directives 1 → 0, and every fix pinned by a mutation that reds only its own file (9 of 9,
  zero coupling). Six production defects: the `scan-secrets.sh` greedy field split that blinded
  `database-url` detection in **every released version** (shipped as a downstream security
  disclosure), `build-orchestrator.sh`'s unanchored `blocks?` inventing dependency cycles from
  "Blocked by" prose, a redundant second `git diff` in `detect-user-changes.sh`, a case-mismatched
  `sed` strip in `milestone-helpers.sh`, GNU-only `\s` in `build-context-set.sh`, and
  `state-merge.sh` no-oping on a corrupt ledger instead of repairing it backup-first. Runner
  integrity (`make coverage` propagates the Python rc; `run-tests.sh` reports skipped phases),
  7 additive bats helpers, `attachments-preseed.sh` extracted, `examples/tictactoe`'s 1817-line
  duplicate deleted, and a `coverage-proxy` meta-gate against future coverage gaps. ~97 paths.
- 2026-08-05: v4.0.4 — gate-revision semantics: plan-gate rejection is an in-place revision of the
  run in flight (frozen `run_index`/`plan_file`, `plan_revision: true` re-dispatch, additive
  `facts.*` patch, `TaskUpdate` not `TaskCreate`, no issue re-publish, `revision_count` +
  `plan_revision_dispatched` audit row, plan gate re-entered), fixing silent `facts.decisions[]`
  loss, a forked plan, a stranded second stage chain, and a split issue anchor; symmetric FN-gate
  reject-resume path specified. Four rule fixes: `Skill` tool grant + DV yield discipline for
  `prompt-engineer`; approximate `file:line` locators + syntactic validation of AC verification
  commands for `product-manager`.
- 2026-08-05: v4.0.3 — full legacy-logic removal (user-owned version scheme: 4.0.3, not the
  round-2 4.1.0 target — re-affirmed at the FN gate; round 1 + round 2 shipped together). **Round 1** (deprecation cleanup + compaction across `agents/`,
  `commands/`, `skills/`): removed legacy `--auto-plan`/`--auto-finalization` aliases (5 files +
  README, only `--auto=[plan, decision, finalization]` remains); sunset `requires_ui_tests`
  compat-mapping table (2 files, 6 sites); `igrsoft` rename residuals outside the vendor-identity
  allow-list (7 files); 21 of 42 stale pre-4.0 version gates (21 kept, still needed to validate old
  ledgers). Compaction: 34,119 → 34,035 tracked markdown lines. **Round 2** (user-approved,
  aggressive scope, 13 themes — hooks/scripts/tests/benchmark): dual dedupe-key mechanism deleted
  (`metadata.dedupe_key_extended` + `skills/agent-coordination/scripts/audit-dedup.sh`); pre-run-index artifact bare-basename
  resolver rung removed; pre-#375 issue-title probe removed; `state.json .git.base_branch`
  fallback removed from the integration-branch chain; single-file visual-evidence marker shape
  dropped; redaction supersets removed (leak risk accepted for pre-4.0 identifiers); benchmark
  `tokens` block decoding now strict (all 5 keys required, `history.json` migrated in place);
  `state.mcp_session`, `--severity` legacy aliases, bare-name agent shim dropped; dead
  `_inline_merge` deleted from `state-merge.sh`. Zero stage/agent/gate/threshold semantics change
  on current-contract paths — every removal itemised with its repo-wide grep in
  `development-0.md`. BREAKING (round 1): legacy `--auto-*` flags no longer recognised or
  documented (undefined effect, not a parse error); a resumed pre-4.0 plan carrying
  `requires_ui_tests` with no `test_mode` now silently falls to `scoped` test mode with no Design
  Comparison and no deprecation note. BREAKING (round 2): pre-4.0 `.context/` artifacts, pre-#375
  issue titles, and single-file visual-evidence markers no longer resolve via any compat path;
  redacted identifiers may leak into GitHub issue bodies on a pre-4.0 resume; a partial benchmark
  `tokens` block now raises instead of decoding with silent `None`s.
- 2026-08-03: v4.0.1 — two silent publication-surface degradations. **Branch naming**:
  `commands/worktask.md` Step 3c is now UNCONDITIONAL with a BINDING line that
  `branch_is_conventional()` is the sole authority (an orchestrator judging "already named,
  skip" by eye is how `fix/catalog-image-blinking` reached `facts.branch`), plus a non-blocking
  `branch_convention_check` post-check naming actual + derived target. Grammar gains an OPTIONAL
  ticket segment `<type>/[<ticket>-]<slug>` (`derive_ticket`, first `\b[A-Z]{2,}-\d+\b` from the
  goal, budgeted inside the 48-char cap and stripped from the slug body); the predicate accepts
  both shapes so no existing branch churns. `derive_slug` drops the trailing PARTIAL word instead
  of cutting mid-word; `derive_type` matches `fix` as a WORD (the old `*"fix "*` missed "…and
  fix.") and gained defect vocabulary (blink/flicker/glitch/broken/regression/incorrect/wrong/
  fails/failing). **`publish-pl-issue.sh`**: title and Summary now resolve through INDEPENDENT
  chains (title: `facts.goal` → frontmatter `title:` → first H1 → summary/problem first sentence
  → slug; summary: `facts.goal` → `## summary` → `## problem`) — `facts.goal` is optional and
  nothing on the PL patch path ever wrote it, so one unset field produced both a kebab-slug title
  and an empty Summary. Slug rank is audited (`title_fallback_worktask_id`); the no-double-prefix
  guard is now case-insensitive and `-`-aware; the recovery search probes the legacy title on a
  miss. Step 3a now seeds `facts.goal`. +34 tests, all non-blocking contracts intact.
- 2026-07-31: v4.0.0 — plugin renamed `igrsoft` → `company-workflow`. Every `igrsoft:<agent|skill>`
  invocation id, the `marketplace.json` plugin entry, the `plugin.json` `Stop` matcher, the
  bare-name resolution shim, and the install cache path (`cache/igrsoft/company-workflow/`, only
  the plugin segment) move to the new prefix. The six `IGRSOFT_*` env vars become
  `COMPANY_WORKFLOW_*` — hard cut, no fallback read. Three runtime string matches were the real
  risk and moved with it: `dv-screenshot-gate.sh`'s exact `!= "company-workflow:developer"` guard,
  `build-context-set.sh`'s awk `$1 == "company-workflow"`, and the 4 copies of the leak-regex
  alternation in `publish-pl-issue.sh` (kept in lockstep with `compatible-plugins.md`). Vendor
  identity deliberately untouched: author `IGRSoft`, `support@igrsoft.com`, `github.com/IGRSoft`
  URLs, `com.igrsoft.*` bundle IDs, and the marketplace name itself. BREAKING — no alias.
- 2026-07-31: v3.43.0 — `--auto` becomes an array flag (`--auto=[plan, decision, finalization]`;
  legacy `--auto-plan`/`--auto-finalization` kept as deprecated aliases, union-composed). New
  `PL0.metadata.decision_gate` (`"user"`/`"auto"`) + orchestrator Step A.4: on `"auto"`, PL0's
  `open_questions[]` are decided by a PM decision delegate on `model: "fable"` (step-5f `opus`
  fallback), applied to the plan's existing anchors in one batch pass, then merged by the
  orchestrator into `state.json facts.decisions[]` as `(auto-decided)` entries (no new plan
  anchor — `## decisions` stays AR's), audited `auto_decision_dispatched`→`auto_decision_resolved`
  (rationale per question in that row). BINDING escalation guard: irreversible/scope/security/spend
  questions always stop for the user, even under `plan_gate: "bypass"`. `/megatask` stamps
  `decision_gate: "auto"` per issue and PARKS an escalate-class issue instead of stalling the
  batch (settled `failed` + `execution.reason: "parked_escalation"`, riding the monitor's normal
  failure path — track freed, dependents stay blocked). New Signal 2b precondition + resume-table row. Docs + `marketplace.json` version parity
  only; files include `commands/{worktask,megatask}.md`, `skills/megatask/SKILL.md`,
  `.claude-plugin/marketplace.json`.
- 2026-07-31: v3.42.0 — TL0 removed from every tier default (four table copies + README),
  included only when PL0 splits work across ≥2 developers; AR0 stays a tier default PL0 may
  override either direction, against one canonical Stage Inclusion Criteria block
  (`skills/estimation-methodology/SKILL.md`) with pointer footnotes elsewhere. New
  `metadata.added_stages` (symmetric with `skipped_stages`, `{stage, reason}`). `DVHandoff` gains
  optional `architecture: {ref, applied}`, gate-required when AR ran; `refs.decisions` conditional
  on AR; precedence `refs.decisions` then `architecture.ref` cited identically in 5 places.
  `handoff-harness.sh` gains `--state`/`--strict` plus the AR-ref check, ships **warn-only** (exit
  0 by default; `--strict` or `COMPANY_WORKFLOW_AR_REF_STRICT=1` opts into blocking; legacy invocation
  byte-identical). Edge registry created (did not exist at HEAD) covering all 20 handoff edges
  incl. `AR→DV`/`PL→DV`/`PL→TL`/`USER→IR`/`IR→DV`/`QA→RE`/`<invoker>→ET`. Per-workstream
  `development-N-<stream>.md` under TL fan-out. **BREAKING, folded in from a second DV round:**
  AR's own artifact renamed `analyzing-N.md`→`architecture-N.md` across every reference pattern,
  map and grammar (finishes the `cada9e4`/v3.8.0 normalization that left AR behind); no back-compat
  — `.context/` is gitignored so the affected population is bounded to an in-flight worktask
  spanning the bump, migrated via `mv` (not `git mv`, which fails — gitignored path). New
  `tests/shell/worktask/artifact-map-parity.bats` (8 tests) asserts all seven stage→basename
  sources of truth agree — nothing compared them before, which is how the v3.8.0 drift went
  unnoticed for 34 minors. 13 provenance comments citing a past run's real `analyzing-0.md`
  deliberately left byte-identical (own follow-up to delete under `company-workflow:code-comment-standard`,
  not a rename miss); `publish-pl-issue.sh`'s leak filter keeps both tokens permanently
  (`PERMANENT-SUPERSET`). Suite: 438 bats (0 fail, up from 394) + 48 Swift + 37/175 Python; all 4
  self-tests exit 0; shellcheck at pre-existing baseline on all edited scripts. 59 files. Known
  follow-up: pre-existing `state-patch.sh` idempotence bug (stale handoff edge survives a stage
  re-run after rejection) deferred out of scope, FN to file as its own GitHub issue.
- 2026-07-31: v3.41.2 — comment-density and comment-standard-reminder hooks extended to cover
  `sh`/`bash` (allow-list + `comment_style_for` hash-arm routing); density gate gains a
  vendored-path exclusion (`vendor/`, `node_modules/`, `Pods/`, `third_party/`) applying to every
  gated language, called out as its own behavior change; bloated/lean shell self-test fixture pair
  + vendor-exclusion control-arm case; new `tests/shell/hooks/comment-hooks-self-test.bats` wraps
  both hooks' self-tests into the suite for the first time; `code-documentation.md` gains a shell
  BEFORE→AFTER gallery entry and an `### Other grammars` fence. 2 self-test suites green (9 density
  cases), vendored `hooks/` bats module 106/106, shellcheck at the one-item SC2016 baseline. 4 files.
- 2026-07-30: v3.41.1 — test-execution authority enforcement via stage-scoped policy matrix; DV auto-promotion capped at module-scope; SR/RE tool-grant narrowing (bare Bash → scoped allow-lists); new `PreToolUse` hook `hooks/test-execution-gate.sh` with fail-open guards; 27 new hook test scenarios + 6 parity tests; 8 sections restructured for size compliance. 394 bats green. ~25 files.
- 2026-07-30: v3.41.0 — branch naming PL-stage entry point + shared library; FN `branch-name` subcommand removed entirely; vocabulary extended to `feature`/`feat` (backward compatible); rank-4 issue resolver tightened; shell-injection hardening (input gate + validation at 3 consumption hops); symlink ACE + CDPATH + audit-row-loss fixes. 340 bats green. ~20 files.

## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
