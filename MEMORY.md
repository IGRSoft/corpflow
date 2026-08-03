# company-workflow Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **4.0.1** (two silent publication-surface fixes. Branch naming: Step 3c is now unconditional — `branch_is_conventional()` is the SOLE authority, never an eyeball judgement, with a non-blocking post-check audit row; grammar gains an optional `<ticket>-` segment budgeted inside the 48-char cap; `derive_slug` stops cutting mid-word; `derive_type` matches `fix` as a word and knows defect vocabulary. `publish-pl-issue.sh`: issue title and `## Summary` resolve through independent fallback chains instead of sharing the optional `facts.goal`, whose absence published a kebab-slug title with an empty body; the slug rank is audited, the ticket-prefix guard is case-insensitive, and the recovery search probes the legacy title. Step 3a seeds `facts.goal`. Scripts + tests + docs only — no stage, agent, or gate semantics change. Previous release: plugin renamed `igrsoft` → `company-workflow`: every invocation id, the marketplace plugin entry, the `Stop` hook matcher, and the install cache path move to the new prefix; the six `IGRSOFT_*` environment variables become `COMPANY_WORKFLOW_*` with no fallback read. Vendor identity — author `IGRSoft`, `support@igrsoft.com`, the `github.com/IGRSoft` URLs, `com.igrsoft.*` bundle IDs, and the marketplace name — is deliberately unchanged. BREAKING: `igrsoft:*` ids no longer resolve and there is no back-compat alias. See release-history row below for the full changelog.)
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
- 2026-07-29: v3.40.0 — suite fully green (281/0); new cross-plugin-refs contract test caught 2 dangling delegations; web/android capture scripts; android `and-*` agent rename propagated; `deps --upgrade` silent-audit fixed. ~12 files.
- 2026-07-29: v3.39.0 — platform-agnostic orchestration: 36 XcodeBuildMCP grants removed (DV/DR/QA delegate to `/<plugin>:build-test`), Apple pre-warm deleted, Swift-Testing-for-all-platforms mandate and 4-platform schema gap fixed, Python comment-density and Android UI-detection bugs fixed. ~44 files.
- 2026-07-29: v3.38.0 — compatible dev-plugin registry + onboarding checklist; ai-engineer wired in; publish-pl-issue prefix-regex leak (5 plugins) and pm-milestone/AR/SR/QA routing gaps fixed. ~15 files.
- 2026-07-29: v3.37.2 — image hosting: tier-0 user-attachments LIVE via `drogers0/gh-image` (only tier that renders on private repos + takes binaries + commits nothing); gist tier proven unable to host any image (`gh gist create` refuses binaries) and fails fast; `manifest_unparseable` split from `no_captures`; `ASSET_GIST_PUBLIC` tri-state, auto-derived from repo visibility. Self-tests 37→38. 6 files.
- 2026-07-28: v3.37.1 — model-name sweep: no superseded Opus/Sonnet generation named outside CHANGELOG; dated rows de-named; benchmark STAGE_TABLE repinned to Opus 5/Sonnet 5. ~14 files.
## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
