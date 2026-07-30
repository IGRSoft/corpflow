# igrsoft Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **3.40.0** (follow-through on 3.39.0; suite **fully green** 281/0 for the first time in the series. NEW `tests/shell/skills/cross-plugin-refs.bats` — asserts every `/<plugin>:<command>` and `Task(plugin:agent)` resolves in the sibling repo; caught two live defects nothing else could see (3.39.0 promised `/ai-engineer:build-test` which did not exist; android rename left 3 dangling Task grants). Skips when siblings absent. NEW `web-capture.sh`/`android-capture.sh` — all 3 platforms now have shipped capture scripts (Apple was the only one). Fixed the 3 long-red tests: composed-token drift in code-comment-standard, `attach-visual-evidence` missing usage + argv validated after state load, `cache-lint` test asserting on untracked live `.context/`. android-developer renamed its 4 colliding bare-name agents to `and-*` (apple-developer now the sole bare-name plugin); refs here follow. `deps --upgrade` silently ran a read-only audit in 4 plugins — now an explicit error. ai-engineer gained `build-test` + the required `workflow-integration` skill. MINOR; min CC unchanged 2.1.220.)
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

- 2026-07-30: v3.41.0 — branch naming PL-stage entry point + shared library; FN `branch-name` subcommand removed entirely; vocabulary extended to `feature`/`feat` (backward compatible); rank-4 issue resolver tightened; shell-injection hardening (input gate + validation at 3 consumption hops); symlink ACE + CDPATH + audit-row-loss fixes. 340 bats green. ~20 files.
- 2026-07-29: v3.40.0 — suite fully green (281/0); new cross-plugin-refs contract test caught 2 dangling delegations; web/android capture scripts; android `and-*` agent rename propagated; `deps --upgrade` silent-audit fixed. ~12 files.
- 2026-07-29: v3.39.0 — platform-agnostic orchestration: 36 XcodeBuildMCP grants removed (DV/DR/QA delegate to `/<plugin>:build-test`), Apple pre-warm deleted, Swift-Testing-for-all-platforms mandate and 4-platform schema gap fixed, Python comment-density and Android UI-detection bugs fixed. ~44 files.
- 2026-07-29: v3.38.0 — compatible dev-plugin registry + onboarding checklist; ai-engineer wired in; publish-pl-issue prefix-regex leak (5 plugins) and pm-milestone/AR/SR/QA routing gaps fixed. ~15 files.
- 2026-07-29: v3.37.2 — image hosting: tier-0 user-attachments LIVE via `drogers0/gh-image` (only tier that renders on private repos + takes binaries + commits nothing); gist tier proven unable to host any image (`gh gist create` refuses binaries) and fails fast; `manifest_unparseable` split from `no_captures`; `ASSET_GIST_PUBLIC` tri-state, auto-derived from repo visibility. Self-tests 37→38. 6 files.
- 2026-07-28: v3.37.1 — model-name sweep: no superseded Opus/Sonnet generation named outside CHANGELOG; dated rows de-named; benchmark STAGE_TABLE repinned to Opus 5/Sonnet 5. ~14 files.
- 2026-07-28: v3.37.0 — Claude Code 2.1.216→2.1.220: nesting depth 5→3, 20-concurrent cap, Opus 5 default, budget-halt resume branch; min CC → 2.1.220. ~23 files.
- 2026-07-27: v3.36.2 — worktask PR-composition, issue-publish, branch-naming, base-ref fixes. `fn-preflight.sh` gains `pr-body` (sanitises the composed body in place by sourcing `publish-pl-issue.sh`'s own `sanitise_body` under `PUBLISH_LIB_ONLY=1`, fail-closed; requires a `Test plan` heading; requires the `visual_evidence_pr_emitted` audit row for the current run index, and the `## Visual evidence` section when that row says `ok`) and `branch-name` (`<type>/<ticket>-<slug>`, idempotent, never renames an upstream-tracked or integration branch, deliberately not in `all` because `all` runs post-push). Both self-disable under `/megatask` and `--emergency` via a local five-signal `fn_batch_scope` mirror that depends on nothing but jq + the filesystem. `resolve_base_ref` replaces the hardcoded `main` continuity fallback with one five-rank order (`FN_BASE_REF` → `state.metadata.base_ref` → `state.git.base_branch` → `workspace.json` → `origin/HEAD` → unresolved, no literal). `publish-pl-issue.sh` resolves a bare-basename `plan_file` against the state directory and prints a stderr diagnostic naming every candidate on the fatal path. `plan_file` path-vs-basename boundary stated at seven writer/reader sites. +26 bats cases. ~13 files.
- 2026-07-27: v3.36.1 — test-selection grammar and coordination: Apple test identifiers are suite-terminal (function parentheses + param suffixes in Swift Testing prevent per-function `-only-testing:` matching, causing full-suite fallback), DV dispatch test-scope enforcement + advisory TL reader, `environmental_contention` classification with re-baseline-only handler, `igrsoft:context-compression` wired into DR/QA, audit-only counters (`full_test_run`/`scoped_test_run` keyed on invocation shape, never a gate), cross-repo divergence note on upstream apple-developer plugin. ~8 files.
- 2026-07-22: v3.36.0 — plugin token-utilization & cross-agent comms (issue #221, PR #224): paired ±agent benchmark runner (U3/U4 symmetric with/without arms, shared prompts), per-call token accounting (U5), generated-project output sections (U2), bypassPermissions + deny-list enforcement (A1, both arms), progressive-disclosure ref files (visual-qa.md, platform-detection.md, workspace-modes.md), phase-4 worktask prose diet, state-patch.sh --prev + fn-preflight.sh, STAGE_TABLE reconciliation (AR/DV/DR high, QA medium, FN/ST sonnet/low), 156 harness tests (up from 131), agents/ 283,888→245,987 B, section-lint 15→0. ~80 files.
- 2026-07-21: v3.35.1 — code-comment-standard made loadable everywhere: new skill skills/code-comment-standard/SKILL.md (0.1.0) wrapping skills/shared/code-documentation.md; new PostToolUse hook hooks/comment-standard-context.sh injects the compressed standard once per session on first source Write/Edit; ban-list mirrors added to qa-engineer.md, incident-responder.md, workflow-engineer.md (+frontmatter bumps). MINOR, ~10 files.
- 2026-07-21: v3.35.0 — Claude Code 2.1.210→2.1.215 update (MCP auto-background protocol, 200-spawn cap, "Needs input" resume branch, hook-contract guarantees) + repo-wide removal of pre-2.1.215 version gates; min CC → 2.1.215. ~30 files + band file.
- 2026-07-20: v3.34.2 — compact-comment hardening of `skills/shared/code-documentation.md`: Length-budget rows + `## Doc block shape` templates for function docs (1–3-line info block; blank `///` line + grouped `- Parameters:` block, one sentence per entry), var/constant (one sentence only when the name isn't clear), and `#Preview` (never commented); issue-ID bullet reworded — tag only where the issue materially changed business logic (was "one per file"); new AC-/REQ--ID ban; Examples split into Property/Function H3s + new OV-153 function BEFORE→AFTER. Ban-list mirrors extended: developer.md 0.7.2→0.7.3 (×3 sites), technical-lead.md 0.3.0→0.3.1, dev-code-review.md 0.2.0→0.2.1, cross-plugin-handoff delegation prompt, technical-writer.md 0.1.2→0.1.3 (DC gate). Docs/prompt-only PATCH, ~9 files.
## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
