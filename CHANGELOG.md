# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [4.0.20] — 2026-08-21

### Changed

- **Prompt surface compressed 19.7% (240,429 → 193,168 words) across all 38 commands, 16 agents,
  and 111 skill files** (#313). Behavior-preserving: one canonical copy per fact — `skills/shared/`
  and skill references are canon, commands/agents point instead of restating — tables over prose,
  one worked example per pattern, report samples reduced to section skeletons plus content rules.
  Frontmatter, tool grants, trigger descriptions, gate/AC language, schemas, script contracts, and
  every test-pinned string and cited section anchor preserved verbatim (605 citations re-resolved
  in a closing cross-file audit) — the sole frontmatter edits are the three corrected
  `argument-hint` fields listed below. Every rewritten file carrying a `version:` field takes a minor
  bump (`structure` category per `agents/prompt-engineer.md § Self-Improvement Patch Application`).
  Estimation run detail split to a new on-demand
  `skills/estimation-methodology/references/estimation-run.md`.

### Fixed

- Defects surfaced by the compression sweep: three dead `/release-notes` links (renamed command),
  a factually drifted stage→model lookup table in `stage-codes.md` (FN/IR swapped vs shipped
  frontmatter), a stale atomic-merge snippet in `stage-contracts.md` missing the mandated mkdir
  spinlock, an emergency stage list missing DR, six dangling section anchors, a stale
  `skills/README.md` index (12 missing entries), and mis-labeled rule-range headings in
  `self-improvement/references/target-mapping.md`.
- Three `argument-hint` fields that had drifted from their command's documented options:
  `appstore-iap` and `appstore-screenshots` gained the `--dry-run` (and `--path <dir>`) flags they
  already accept, and `appstore-info` dropped a positional `<app name or bundle ID>` it no longer
  takes in favour of its real `--lang` / `--path` / `--readme-only` / `--dry-run` set.
- `milestone-helpers.sh` cited `megatask § Priority Sorting`, a heading this release folded into
  `§ Dependency & Blocker Resolution (DAG)`. The unqualified `<skill> §` shorthand fell outside the
  citation audit, which resolves the qualified `<path>.md §` form.
- An unescaped `||` inside a code span in `security-review-process/SKILL.md § Secure Coding
  Patterns` split the Authorization row into five cells, truncating the rule where it rendered.

## [4.0.19] — 2026-08-17

### Fixed

- **A DV brief built from the repo's own README ran the full suite and pre-empted QA's gate.** The
  orchestrator had no rule about where a stage brief's test invocation comes from, so the most
  reachable command — a full-suite `xcodebuild test` pasted out of a project `CLAUDE.md § Core
  Commands` — reached DV four times on a `test_mode: scoped` plan. `testing-strategy.md §
  Dispatch discipline` now sources the invocation from `<plan_file>` frontmatter (`test_mode`,
  `always_required_tests`) and requires the brief to state the resolved mode **and** the exact
  selector, with DV recording any identifier-grammar reconciliation in `development-N.md §
  Decisions`. The mechanical deny (`hooks/test-execution-gate.sh`) already covered this shape,
  including quoted multi-word `-destination` values; this closes the prose layer that produced the
  command in the first place.

### Changed

- **`build-only` is now *selected* for a comment/doc-only diff, not merely available.** The mode
  existed for exactly this case but was opt-in and never reached for, so doc work paid full
  simulator cost. When every planned hunk is a comment, a prose file, or a non-executable string,
  PL sets it and the marker-coverage precondition does not apply — nothing executable changed, so
  no markers are standing in for a run. One executable hunk anywhere disqualifies the diff. The
  downstream consequence is stated with it: a doc-only change landing after QA (typically DC,
  which holds no execution authority at all) does not re-trigger QA, and FN commits on QA's
  existing evidence.

- **FN unwinds build-tool churn as the last action before staging.** Build tools mutate tracked
  files nobody edited — auto-extracted localization keys, scheme and build-configuration rewrites,
  lockfile touch-ups — and those edits reached commits because no stage owned removing them.
  `project-manager.md § Pre-commit scope check` requires `git status --porcelain` to show only the
  run's intended files, reverts the rest immediately before `git add`, and forbids running
  anything that builds afterwards, since a build re-creates exactly what was just removed. FN
  holds no build path, which is what makes it the right stage to own it. Reverted paths are listed
  in `complete-summary-N.md`; one that recurs every run is a repo defect worth its own issue.

## [4.0.18] — 2026-08-17

### Fixed

- **Absolute local paths leaked into published PR and issue bodies from two directions.** The
  Pass-1 strip in `publish-pl-issue.sh` and its byte-identical copy in `pr-body-lint.sh` knew only
  the home-directory mounts (`/Users`, `/home`, `/tmp`, `/var`, `/opt`, `/etc`, `/root`), so a
  checkout under `/Volumes`, `/mnt`, `/media`, `/private`, `/srv`, or a Windows drive letter walked
  through both. The alternation now covers all of them, and `local-path-regex-parity.bats` pins the
  two copies identical. Separately, `fn-preflight.sh pr-body` skipped **all** work under batch and
  incident routing, publishing unsanitised bodies; the strip now always runs and only the
  *blocking* behaviour is dropped for those routes.

- **The comment-density gate blocked legitimate per-declaration DocC.** A 20-case enum with one
  on-budget `///` per case measured 48% and was rejected. Runs of one-line comments no longer
  count as a block; every existing fixture keeps its prior verdict.

- **Change→test selection failed closed to FULL for `hooks/lib/` self-test bodies.** `sel_alias_for`
  now resolves `<name>-selftest.sh` to its owning hook's `.bats` by chaining through the alias
  table, restoring scoped runs for hook work.

- **`commands/agent-report.md` was never registered in `marketplace.json`**, leaving the command
  invisible to the marketplace since it was added.

- **Six red tests, all pre-existing.** `env -u` after a `NAME=VALUE` operand is a no-op on BSD
  `env` (macOS took `-u` as the command name); the `stale-check.sh` write guard matched the word
  `SendMessage` in its own advice prose rather than any call, and now matches invocation syntax
  with a falsification test beside it; `fn-preflight` F23 asserted a message the batch exemption
  stopped emitting when it moved ahead of the sanitiser.

### Added

- **A duplicate GitHub issue is caught before `.context/` exists.** The existing anchor and
  exact-title guards are reachable only *after* the context exists, so a paraphrased request opened
  a second issue every time. `/worktask` Step 2a now scores keyword overlap against open-issue
  titles locally and offers at most three candidates. Advisory and human-confirmed only: it never
  links, comments, or writes on its own, and any failure — no `gh`, no auth, API error, timeout,
  zero hits — proceeds to a new context. Batch, incident, and non-interactive runs skip it;
  `PREFLIGHT_ISSUE_SCAN=0` disables it.

- **The test-execution gate denies a run that already happened.** Once an authorized invocation is
  allowed, the identical invocation is denied while the tree is byte-identical, scoped to
  `run_index`. The fingerprint is HEAD plus `git status --porcelain` **and** `git diff HEAD` — the
  diff is load-bearing, since porcelain reports only names and status letters. Checked on the allow
  path only, so suppression can never widen what the gate permits; every unresolvable input allows.
  `CORPFLOW_TEST_DEDUPE=off` is the hatch.

- **Unit tests for `conventional-commits-lib.sh`**, which shipped without a dedicated `.bats` —
  17 cases pinning breaking-change detection, section mapping, bump aggregation, and record
  collection at the library rather than through its two consumers.

### Changed

- **Every markdown section is back within the 1000-char cap** (38 were over, across 28 files).
  Sections were **split, not cut**: leaf semantics mean a subheading turns one over-cap section
  into two compliant ones without losing a word. The largest cluster was the nine copies of
  `State Patch — REQUIRED before return`, each split at its `--facts` obligation.

- **The gate no longer forks `sed`, and resolves the stage only for test commands.** Classification
  runs first; `sed` is gone from the classify path entirely (5 forks to 0). Measured: benign call
  13ms → 10ms, test command 36ms → 27ms. `classify_segment` is 216 lines, down from 270.

- **Hook comments compacted to `skills/code-comment-standard`**, and self-test bodies moved to
  `hooks/lib/` — four hooks shed 660 lines of test code, `test-execution-gate.sh` 1280 → 1078.
  Each dispatcher fails **closed**: a missing body reports a failure rather than "OK". Code lines
  are byte-stable in every file.

- **`request-plan` v0.3.0**, from an open-coded error analysis of 96 human-labelled traces
  (`skills/request-plan/evals/failure-taxonomy.md` — 9 categories, rates, and the case lists).
  Five rules address the format and routing categories: decide once between asking and planning,
  confirm a file owns the behaviour before planning against it, never assert absence you did not
  check, always emit all three phase rows, and end with exactly one `/worktask` line.
  `estimation-methodology` gains a surface check above the size logic, so `--secure` and
  `--emergency` are decided by what the work touches rather than by how large it is.

  The analysis then found that **half of all failures were one root cause wearing two faces**:
  16 of 32 were `buried`-grounding cases (50% failure rate, against 17–29% elsewhere) that either
  planned against the wrong file or gave up and asked — both the same search stopping before it
  reached the owning module. § 2 had licensed exactly that, telling the model to "stop gathering
  once more reading wouldn't move scope, phases, or effort" — a condition unknowable from inside
  the failure, since a search that has not found the right file cannot tell that more reading
  would change the plan. It now stops on evidence (name the owning file and what you read in it),
  searches by behaviour rather than filename, treats one hit as a hypothesis rather than a
  finding, makes `Explore` mandatory rather than preferred, and gates the "no surface" branch on
  the search having actually run.

- **The eval grader stopped excusing the failure it was built to catch.** An unexpected clarifying
  question was reported as `CLARIFY` and dropped from the denominator, hiding 9 of 32 known
  failures and computing the headline over 87 cases instead of 96; it is now scored against the
  case's `expected_outcome`. The `cites-a-repo-path` threshold dropped from 2 resolving paths to 1:
  at 2 it failed 8 plans a human passed, because a plan citing the handed file by full path and its
  neighbours by bare name resolves exactly one. Together these move the harness from TPR 83% /
  TNR 100% to **TPR 94% / TNR 100%** against the human labels.

## [4.0.17] — 2026-08-16

### Changed

- **`state-merge.sh` ships from `hooks/` like every other hook.** It was the lone occupant
  of `.claude/hooks/`, a split that bought nothing and cost a carve-out in every rule that
  quantifies over hooks. Only the **plugin-root source path** moved: the project-local
  install destination written by `hook-install.sh` is still `<project>/.claude/hooks/state-merge.sh`,
  because that is Claude Code's per-project hook directory, not a corpflow convention. The
  file is now executable, which is what `manifest-parity`'s AC-9 contract already required
  of everything under `hooks/`; the exemption that excused it from the mode bit is gone.

### Fixed

- **The relocation would have silently disabled the Layer-2 net.** `state-merge.sh` locates
  `state-patch.sh` — the only merge implementation — through `$CLAUDE_PLUGIN_ROOT` first and
  a relative arm second. That arm read `${HOOK_DIR}/../..`, which is the plugin root from
  `.claude/hooks/` but its *parent* from `hooks/`, so the shipped copy resolved a path with
  no `skills/` tree under it. A SubagentStop hook must never block a stage transition, so the
  not-found branch exits 0 — the failure mode is not a crash but a merge that quietly stops
  happening, the same silent-net class as the cwd bug fixed in 4.0.16. Both arms (dispatch
  path and `--self-test`) now go up one level. Six of the eleven `state-merge.bats` cases
  caught it; the two that stayed green were the ones passing `CLAUDE_PLUGIN_ROOT` explicitly.

- **Version parity was red before this release.** `plugin.json` read 4.0.16 while
  `marketplace.json` and `README.md` still read 4.0.15, so `manifest-parity` AC-4 failed on a
  clean checkout of 4.0.16. All four sites now agree.

- **The `state_repair` audit row recorded an absolute backup path.** 4.0.16 moved the hook onto
  a resolved `WORKSPACE_DIR`, which made `STATE_FILE` — and with it the backup path derived from
  it — absolute, so the row leaked the worktree it happened to fire in. `handoff-protocol.md` F4
  names the backup `.context/state.json.corrupt.<iso-ts>` and the sibling `artifact` field in the
  same row is workspace-relative; the row now matches both. Filesystem operations still use the
  absolute path — only what is written to the trail changed.

- **The AR-gate test pinned an index the gate deliberately does not name.** `handoff-harness.sh`
  matches any `AR[0-9]+` ("did AR run", not "did AR0 run"), so when no entry exists there is no
  index to report and the warning says `tasks.AR<N>`. The test asserted `tasks.AR0`, contradicting
  the any-instance rule it was meant to guard. The test now matches; no behaviour changed.

### Documentation

- **A green test run no longer reads as a measured skill eval.** `tests/python/test_skill_evals.py`
  described itself as grading "captured responses," and `evals/README.md` said every case "is
  graded by binary, code-checked assertions" — but no capture step exists: nothing dispatches
  the case prompts and no responses are stored. What runs offline is the assertion engine
  against hand-built fixture plans plus the eval-set lint. Both files now say so, and
  `benchmark/README.md`'s totals line no longer counts them as "skill-eval tests green".

- **Published test counts were stale and mutually contradictory.** `tests/README.md` and
  `benchmark/README.md` disagreed on the same suites (202 vs 344 harness tests, 37 vs 52
  skill-script tests). Every figure is re-derived: **924** bats across **60** files, 52 Python
  skill-script, 350 Python harness, 48 Swift — **1374** total. The hand-maintained coverage
  roster in `tests/README.md` is replaced by a pointer to `meta/coverage-proxy.bats`, which
  computes the target set at run time; a prose count that nothing enforces is what drifted.

- **Two sections were over the 1000-char lint cap.** `agent-coordination/SKILL.md`'s plugin-hook
  writers table (1178) had the same lifecycle-field sentence duplicated across two rows and an
  inline aside on the `state_transition` hook path; both are factored into a `Plugin-hook row
  fields` subsection. `shared/state-ledger.md`'s write-operations section (1137) gained an
  `Idempotency and key creation` heading over its existing trailing paragraph. No content removed.

## [4.0.16] — 2026-08-15

### Fixed

- **`scan-secrets.sh` no longer fails open.** The regex fallback swallowed grep's exit
  status with `|| true`, making "no match" (exit 1, normal) indistinguishable from "the
  engine crashed" (exit >1). On macOS, BSD `grep` can trap on a pattern it cannot compile
  (`Trace/BPT trap: 5`, status 133); the scan then exited **0** — the documented "no
  Critical/High findings" code — so a crashed scan read as a clean bill of health to any
  reviewer following the skill's own instruction to invoke the script rather than reason
  through the patterns by hand. The status is now discriminated exactly as `gitleaks_scan`
  already did: >1 reports the failing pattern and file on stderr and returns 2 (the
  script's existing hard-error code). Clean (0) and findings-present (1) are unchanged.
  This is the same failure class an existing comment in the file describes one layer down,
  where a `2> /dev/null` once hid a dead pattern for the life of a regex.

- **`state-merge.sh` resolves the workspace instead of trusting cwd.** The hook fires on
  `SubagentStop`, and the subagent that just stopped is very often a DV stream — the one
  stage for which worktree isolation is mandatory. Its cwd is a linked worktree, where
  `.context/` does not exist, because the directory is gitignored and never carried into a
  worktree checkout. Resolving `.context/` relative to cwd therefore made the documented
  "Layer 2 safety net" structurally unable to patch the ledger for the only stage that
  always needs it, and it failed silently — a `no artifact resolved` line written into a
  shadow `.context/logs/` inside the worktree, a directory deleted along with it. Had an
  artifact resolved, the completion patch would have merged into a throwaway ledger. The
  hook now resolves `WORKSPACE_ROOT`, then `CLAUDE_PROJECT_DIR`, then the parent of
  `git rev-parse --git-common-dir` (which points at the main checkout from inside a linked
  worktree), before falling back to `pwd`. The corrupt-ledger repair path derives its temp
  file from the resolved ledger so the two cannot land on different filesystems.

- **The test-execution denial now names the supported way to build.** Stages without
  test-execution authority were told only to record `requests_test_evidence` or return
  blocked. `--no-test` — accepted by every platform plugin's `build-test` command, and
  already classified `build_only` and allowed by this gate — went unmentioned. In a
  measured run two streams were denied, neither discovered the flag, both invented
  `--build-only` (which no command accepts, so the classifier reads it as a full test run
  and denies again), and both then fell back to invoking the toolchain directly, which
  `agents/developer.md` forbids. The denial now names `--no-test` first, warns that
  `--build-only` is not a real flag, and states explicitly that falling back to the raw
  toolchain is not an option.

- **`publish-pl-issue.sh` no longer silently mislabels the complexity tier.** Tier
  extraction required the word in parentheses, so a plan writing `Score: 46 / 50 — Critical
  tier.` did not match, and a silent default labelled the issue `complexity:moderate` — the
  amber label on the run's highest-risk issue, indistinguishable in the audit trail from a
  real match. A bare-word arm (word-anchored, so it cannot fire on "critically") now runs
  when the parenthesised form is absent, and applying the default emits a stderr line.

- **`dv-tree-preflight.sh` reports split worktree parents.** When linked worktrees live
  under more than one parent directory, anything that reconstructs a worktree path by
  convention rather than from `metadata.workspace_path` must guess a prefix — and can hand
  a stage another stream's tree. In a measured four-stream run a stream assigned
  `.claude/worktrees/dv3-web` was given `.worktrees/dv0-service` at spawn on four
  consecutive dispatches, because `.worktrees/` held exactly one entry for the glob to land
  on; normalising to a single parent fixed it on the next dispatch. The preflight now names
  the condition and the parents involved. Advisory, not blocking: the stream that runs it
  has already passed the assigned-tree check, and the condition harms a different one.

## [4.0.15] - 2026-08-15

Claude Code 2.1.233 removed the Todo/task-tracking tools — `TaskCreate`, `TaskGet`, `TaskUpdate`,
`TaskList`, `TodoWrite` — on Opus 4.8, Sonnet 5, Fable 5, Mythos 5 **and newer**. Every model this
plugin dispatches is on that list, and the orchestrator loop was built entirely on those four
tools, so on 2.1.233 every worktask and megatask run was broken before it started. Verified
empirically rather than inferred: the tools are absent from an Opus 5 session on 2.1.233.

`CLAUDE_CODE_ENABLE_TODO_TOOLS=1` restores them. This release deliberately does **not** depend on
that. Instead the plugin moves to a single durable ledger, with no mirror and no fallback path —
one mechanism, one code path, correct whether or not the tools exist.

Two premises worth recording, because both were checked rather than assumed:

- **`CLAUDE_CODE_ENABLE_TASKS` is not the switch.** It was set in the observed environment and does
  nothing for these tools. Confusing the two costs a debugging session.
- **`state.json` already held most of the ledger.** `stages{}` carried the same status enum,
  `retry_count`, `error_file`, `artifact`, `verdict`; `state-patch.sh` already owned locking and the
  atomic write; and 13 of 16 agents already held its Bash grant. The cutover is smaller than the
  tool removal makes it sound.

### Changed

- **BREAKING — `state.json` is `version: 2`.** `tasks{}`, keyed by numbered stage id (`PL0`, `DV0`,
  `DV1`), is now the sole stage ledger. It replaces **both** the Task System and the old `stages{}`
  map. A `version: 1` ledger is not migrated and not tolerated — readers fail loud. There were no
  in-flight ledgers on disk when this landed, so no converter ships.
- **The numbered key is the point.** `stages{}` was keyed by bare stage code and could not represent
  parallel DVN tracks, which is why `dispatched_agents[]` had to be keyed separately. `DV0` and
  `DV1` are now simply distinct keys. `hooks/test-execution-gate.sh` gains from this: two parallel
  tracks of one stage resolve to a single unambiguous stage code where bare codes forced a
  fail-open.
- **BREAKING — the four Task tools are removed from all 16 agents' `tools:` frontmatter**, and from
  `commands/worktask.md`, `commands/megatask.md`, `commands/cost-report.md`,
  `commands/context-status.md`, `commands/test-report.md`, `commands/improve-yourself.md`.
- **BREAKING — `metadata.context_files` and the F1 fallback are deleted.** `context_files` existed
  solely as the degraded path for "state.json is absent". The ledger is mandatory now, so that path
  cannot occur and a second context-delivery mechanism is exactly the kind of dual path this
  release removes. `context_refs` + `state_file` is the whole contract.
- `skills/shared/task-system.md` → **`skills/shared/state-ledger.md`**, with all 33 inbound
  references updated (two of them structured frontmatter deps, not prose).
- `.claude-plugin/plugin.json` — the `PostToolUse` audit matcher moves from
  `TaskUpdate|TaskCreate|Write|Edit` to `Bash|Write|Edit`. Without this the stage-transition audit
  trail silently stops, and `audit.jsonl` is load-bearing: it drives all nine resume branch tables.
  `hooks/audit-tooluse.sh` now recognises a `state-patch.sh` invocation, records `task_id` and
  `status` from it, and drops every other Bash call so widening the matcher does not turn the audit
  log into shell noise.
- `workspace.json` `worktask.task_prefix` (`"t1"`) is removed with no replacement. The `t{track}-{n}`
  id scheme it namespaced no longer exists, and no key-level namespace succeeds it: every track's
  ledger keys are the plain `<STAGE>0` ids, isolated by the track's own worktree.

### Added

- `state-patch.sh` ledger operations, replacing the retired tools: `--task-create <ID> --metadata`,
  `--task-status <ID> <status>`, `--task-block <ID> --on <ID[,ID...]>`, `--task-meta <ID> --set`.
  `--task-create` is idempotent and `--task-block` unions rather than appends, so re-running a seed
  is safe. A new `--task-id` overrides id resolution; without it the script resolves a stage code to
  the open instance of a split stage, else the highest existing, else `<CODE>0`.
- Self-test groups T14 (ledger ops, blocked_by union, idempotent create) and T15 (split-stage id
  resolution, explicit override); three bats tests covering the audit hook's ledger filtering.
- `Bash(bash skills/worktask/scripts/state-patch.sh:*)` granted to `designer`. `prompt-engineer` and
  `workflow-engineer` already held unrestricted `Bash`.

### Changed — Claude Code 2.1.221→2.1.233 integration

- **The 200-subagent per-session spawn cap is gone** (2.1.224). "Three independent ceilings" is now
  two — depth and concurrency. `/megatask`'s ~18/~22-issue batch ceiling and the advice to raise
  `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` or split the batch are deleted; batch size is bounded by
  concurrency, disk, and rate budget alone.
- **Subagent forking is on by default** (2.1.232) — `CLAUDE_CODE_FORK_SUBAGENT=1` is no longer
  needed, and a fork inherits the parent's prompt cache, making it the cheapest available handoff
  for a stage that needs whole-orchestrator context.
- **Worktree git isolation is runtime-enforced** (2.1.222), promoting a corpflow convention to a
  guarantee. The v4.0.14 conflict-recovery precondition stays as written — it is conditioned on the
  *host* refusing destructive git, which is still the right framing.
- Documented: `/commit-push-pr` no longer auto-approving dangerous git flags (2.1.229);
  background sessions preserving work per `CLAUDE.md` (2.1.221); `/review` as a `/code-review` alias
  with `ultra` and background high-effort runs (2.1.223, 2.1.232); org-restricted family aliases
  stepping down within the family and the restricted-model warning (2.1.222, 2.1.223); `Notification`
  firing for permission prompts under Desktop/VS Code (2.1.233); PreToolUse auto-allow no longer
  widening an agent's grant list (2.1.222); immediate plugin activation, `"."` skills paths, the
  `archive` source with SHA-256 pinning, and `plugin validate` frontmatter checking (2.1.221,
  2.1.224, 2.1.233); cross-session `SendMessage`/`ListAgents` (2.1.224-2.1.232);
  `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` sibling staggering (2.1.229); and
  `CLAUDE_CODE_TOOL_MEMORY_LIMIT` (2.1.233, Linux only).
- Minimum Claude Code raised **2.1.220 → 2.1.233**, pinned to the band top per the v3.35.0/v3.37.0
  precedent.
- `MEMORY.md` trimmed from 37KB to under its own documented ~5KB cap.

## [4.0.14] - 2026-08-15

A completed 9-issue parallel `/megatask` batch, turned into tooling. Nothing here is speculative:
every item below is a collision that actually happened, was paid for once by trial, and is written
down so the next batch does not pay for it again. Two halves — codifying git mechanics already
learned (REQ-1..4), and reducing the collision *rate* by giving parallel tickets visibility into
shared seams and by making the one purely mechanical conflict class self-resolving (REQ-5, REQ-6).

Three of the six changes exist because a premise in the originating post-mortem turned out to be
false when checked against the tree, so the corrections are part of the release:

- **The deny-list premise does not hold in this repo.** The proposal assumed a `settings.json`
  denying `git merge` / `git reset --hard` / `git push --force`. This repo ships no such file. That
  refusal was a property of the *host environment* the batch ran in. A playbook that asserts a file
  the reader cannot find loses its credibility on the first line, so the playbook is written
  **condition-first** instead.
- **Git has no per-worktree exclude.** `.git/worktrees/<name>/info/exclude` is simply not consulted
  (verified on git 2.54); only the common dir's `info/exclude` works. So the exclusion is
  necessarily checkout-wide, and the release documents that consequence rather than hiding it.
- **The "one-line script fix" was not one line.** Three candidate mechanisms with materially
  different blast radius, one of which pollutes every future commit.

### Added

- **`## Conflict Recovery` playbook** in `skills/megatask/references/git-integration.md`. Five
  ordered steps for the case where the environment refuses destructive git: rebase locally, push
  under a **new** branch name, open a replacement PR, close the superseded one, merge the
  replacement. Step 2 is the non-obvious one and gets its own subsection — re-pushing the original
  name would need `--force`, which is exactly what is refused. A further subsection reconciles the
  local rebase with `git-conventions.md § Merge Strategy`: that rule governs how a PR is
  *integrated*, not whether a branch may be rebased before review.
- **Scratch metadata excluded at worktree creation**, not reactively. `init-worktree.sh` gains
  `exclude_scratch`, writing `/workspace.json` and `/.worktrees/` into the git **common** dir's
  `info/exclude` *before* `git worktree add`, behind an exact-line `grep -qxF` guard so repeated
  init cannot duplicate entries, with a provenance header naming the script that wrote them. The
  motivating failure was an unscoped stage-everything command during a conflict resolution that
  committed the batch's own scratch file to the shared branch. It never touches the tracked
  `.gitignore` and never writes a stored setting; `--dry-run` announces and writes nothing. The
  checkout-wide reach is bounded and documented: an ignore rule can never mask a **tracked** file,
  and the patterns are anchored, so a nested `src/sub/workspace.json` stays visible.
- **`## Conflict Resolution` rules** in `skills/megatask/SKILL.md`. Rule 1: DI-container and
  coordinator-shaped conflicts are hand-resolved by a human and **never** script-merged — a scripted
  "keep both sides" resolver mis-joined an argument list (a missing separator, because the other
  side's block opened with a comment) and duplicated a closing brace, twice, both caught only by a
  later build. Rule 2: a real build and test run before pushing any resolution. A script is
  permitted only where its class needs no interpretation *and* it refuses what it does not
  recognise — which is the bar `resolve-pbxproj-membership.sh` below is held to.
- **`## Shared-Seam Registry` convention** — a decision rule, not advice. Exactly one registry per
  batch, hosted by the sole level-0 issue, or by the milestone / orchestrator issue when there are
  several level-0 issues or none; the rule is total, so no batch shape is ambiguous. The schema
  requires a **verbatim declaration block with ordered parameter labels**, plus `consumers:` and
  `change-protocol:`. The ordering is load-bearing: the motivating failure was two parallel tickets
  inventing the same abstraction under near-identical names with a **reversed argument order**, and
  a name-only schema would not have caught it. `commands/megatask.md § Step 3` restates the
  resolution inline so the per-issue prompt is self-sufficient. **Convention, not a gate** — nothing
  validates the registry this release, by design.
- **`skills/megatask/scripts/resolve-pbxproj-membership.sh`** — sorted-union resolver for
  `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions`, the one project-file
  conflict class that needs no interpretation. Dropping either side silently unregisters test
  files: green build, tests never run. All-or-nothing — any out-of-class conflict anywhere refuses
  the whole file with exit 1 and leaves it byte-identical (structural, not defensive: the parse goes
  to a temp buffer and `mv -f` runs only on accept). It refuses a conflict outside the list, a diff3
  `|||||||` base section (resurrecting a deliberate deletion is worse than refusing), a non-entry
  line inside a side, nesting, an unterminated conflict, and a list close inside a conflict. Ships
  with `--dry-run`, a 35-check `--self-test` and dual `--flag value` / `--flag=value` parsing,
  matching `build-orchestrator.sh`'s established pattern, and is registered in § Canonical Scripts.

### Changed

- **`skills/shared/git-conventions.md` records the comment-character trap.** The `#NNN`
  commit-subject convention collides with git's default comment character; in the source batch it
  destroyed the subject on **four** separate invocations, promoting the body's first paragraph to
  the subject each time. The scope is now stated precisely, because the imprecise version is what
  makes people distrust the note: `strip` cleanup deletes `#`-leading lines on **editor-driven**
  invocations only — `rebase --continue`, bare `commit`, `--amend`, conflict commits — while `-m`
  and `-F` use `whitespace` cleanup and are unaffected. The remedy is **per-invocation**
  (`git -c core.commentChar=…`, or `--cleanup=verbatim`); writing it into a stored configuration
  file is explicitly forbidden. Stated once, in the source of truth; the megatask docs reference it
  rather than restating it.

### Fixed

- **The test-execution gate was inert for every stage after PL, of every worktask.**
  `hooks/test-execution-gate.sh` resolves the acting stage from `.context/state.json` alone —
  deliberately, never from `agent_type` or an env var, so a nested delegate inherits the stage and
  the deny reaches its own leaf `Bash` call. But the orchestrator loop marked stages `in_progress`
  in the **Task System only**: the sole state.json mirror sat in the step-6.5a2 incomplete-return
  path, which fires *after* a stage returns, not at dispatch, and stage agents only ever patch
  `completed`. So from dispatch to completion nothing in the ledger named an acting stage,
  `resolve_stage()` returned empty, empty means allow — correctly, since guessing in the deny
  direction would deadlock unrelated sessions — and every deny the hook implements was unreachable
  in a live run. Nothing was unsafe: this is a fail-*open* backstop by design, and the
  dispatch-time ban banner and tool-grant narrowing are the primary controls. The backstop simply
  was not covering. `skills/worktask/SKILL.md` step 5 now mirrors the mark into state.json
  immediately beside the `TaskUpdate`, with the reason stated inline so the two writes are not
  separated again. Found by the gate firing twice against a hand-written ledger during this
  release's own run, while two real full-suite invocations at banned stages had gone through
  untouched. Both directions are pinned by tests — a non-authority stage denies, and a ledger with
  nothing `in_progress` fails open — plus an assertion that step 5 still carries the mirror, since
  that instruction *is* the fix and nothing else guards it.
- **Separated `stat -f` is a GNU/BSD trap, and it was in the new code.** `stat -f '%Lp' "$f"` is
  correct on BSD, but on GNU coreutils `-f` is `--file-system` and takes no argument, so the format
  and the path become operands: stat prints a filesystem block **to stdout** while exiting non-zero,
  the `|| stat -c%a` fallback sees only the status, and the capture becomes that block concatenated
  with the fallback value. `chmod` then fails and the script aborts before its `mv` — on Linux,
  every accepted resolution died. All four sites now use the repo's attached idiom,
  `stat -f%Lp "$f" 2>/dev/null || stat -c%a "$f" 2>/dev/null || printf '644'`, which is safe because
  GNU getopt rejects `-f%Lp` at option-parse time and writes nothing to stdout — the same form ten
  pre-existing call sites already use. Two guards make the class fail locally next time: a runtime
  `^[0-7]+$` check before the `chmod`, and a self-test probe asserting the token is single-line and
  purely numeric.
- **Resolved files keep their permission bits.** The temp buffer is created 0600; the target's mode
  is captured before the `mv` and re-applied. Tests assert a distinctive `0640` survives, not the
  644 default that would pass by accident.
- **No temp-file residue.** `$( )` subshells reset traps, so buffers allocated inside one were
  unreachable by the cleanup trap, and `TMPDIR` alone does not help (macOS `mktemp -t` ignores it).
  Buffers now use an explicit template directory under `RESOLVE_TMPDIR`/`TMPDIR`, with a
  module-level array and a single EXIT trap. Measured across a self-test run: 659 temp entries
  before, 659 after; previously +34 per run.

### Known limitations

- **Not executed on Linux.** The full suite (913 bats + 52 + 350 unittest, 0 failures) and all
  self-tests ran on macOS / BSD userland. The `stat` fix above was validated against a faithful
  GNU-getopt `stat` model with a positive control that reproduces the original break, but that
  models exactly one binary — `mktemp`, `chmod`, `awk` variants, `sed`, `grep -qxF` and git's
  `rev-parse --git-common-dir` answer are unexercised on a real GNU userland. This repo has no CI
  configuration, so nothing catches a Linux regression automatically. A Linux job is recommended
  before the plugin is relied on off-macOS.
- **The worktree exclusion is verified on git 2.54 only.** It depends on the per-worktree
  `info/exclude` *not* being consulted while the common-dir one is — empirically established, not a
  documented guarantee. A future git could change it; the self-test would catch it, but only when
  run.
- **`skills/worktask/scripts/state-patch.sh` still carries the separated-`stat` shape** at its lock
  mtime read, where it degrades *silently* (`|| printf ''`). Pre-existing at HEAD and deliberately
  out of scope for this release; tracked as a follow-up.

## [4.0.13] - 2026-08-13

The same rename, a second time. v4.0.0 moved `igrsoft` → `company-workflow` because the plugin id
was the last artifact carrying the vendor name; this release moves `company-workflow` → `corpflow`
because the repository has since become `IGRSoft/corpflow` and the plugin id was, again, the last
thing to catch up. The v4.0.0 entry below is the template this pass followed — the same three-role
split, the same runtime-literal traps, the same sibling ordering.

The word's three roles, and separating them is again the whole substance. **Plugin identity**
moves: every `company-workflow:<agent|skill>` invocation id, the `marketplace.json` plugin entry,
`plugin.json`'s `Stop` matcher and its notification title, the `Task(company-workflow:…)`
frontmatter grants, and the install key (`corpflow@igrsoft`). **Vendor identity** does not: the
author block (`IGRSoft`, `support@igrsoft.com`), the `github.com/IGRSoft/…` owner segment, the
`com.igrsoft.*` bundle IDs in `/appstore-iap`, and the marketplace name — still `igrsoft`, so the
cache path becomes `~/.claude/plugins/cache/igrsoft/corpflow/<version>/` with only the second
segment changed, exactly as last time.

The **third** role is new, and is what made this pass different from v4.0.0: the **repo slug**.
GitHub had already been renamed, so `README.md`'s `git clone https://github.com/igrsoft/company-workflow.git`
was a published command that no longer resolved, and the cache-discovery glob in
`skills/shared/plugin-root-resolution.md` pointed at a directory that will never exist again.

Five sites matched the literal string at runtime and would have failed silently rather than
loudly — the first four are the same four v4.0.0 called out, which is itself the argument for
writing them down:

- `hooks/dv-screenshot-gate.sh` guards on exact equality (`!= "corpflow:developer"`). Left stale,
  the DV screenshot gate would no-op on every run with no error.
- `skills/self-improvement/scripts/build-context-set.sh` maps agent refs to file paths via an awk
  field compare (`$1 == "corpflow"`).
- `.claude-plugin/plugin.json`'s `Stop` matcher must track the plugin name or the PL/FN
  approval-gate push notification stops firing.
- `skills/worktask/scripts/publish-pl-issue.sh` carries four identical copies of the plugin-prefix
  leak regex that strips internal agent ids out of published GitHub issues; they stay byte-for-byte
  in lockstep with the list in `skills/shared/compatible-plugins.md`.
- **New this time:** `skills/agent-coordination/SKILL.md` documents that `subagent_type` matching is
  case- and separator-insensitive, using the literal example `Task({ subagent_type: "Company_Workflow:Developer" })`.
  A lowercase-only pass rewrites the rest of that line and leaves the example standing — the one
  illustration on the page would have become the only stale id in the repo. The residual sweep is
  now case- and separator-insensitive (`grep -niE "company[-_ ]?workflow"`) so this class cannot
  survive again.

### Changed

- **Redundant phrasing collapsed.** `company-workflow workflow` doubled the noun; under the new
  name it would have read `corpflow workflow`. The trailing noun is dropped instead — "this agent
  is inside a company-workflow workflow" becomes "this agent is inside corpflow" — across ~78 sites
  in the six sibling plugins' agent intake blocks. The separated form
  `company-workflow 11-stage workflow system` becomes `corpflow 11-stage pipeline`, reusing the word
  the README already uses for the stage chain.

### Breaking

Recorded as breaking despite the PATCH version number, which is user-owned (the same call as at
4.0.3). Anyone reading semver alone will not be warned by the number.

- **`company-workflow:*` agent and skill ids no longer resolve.** There is no back-compat alias.
  The six sibling plugins (`apple-developer`, `system-developer`, `android-developer`,
  `frontend-developer`, `backend-developer`, `ai-engineer`) are updated in the same pass; merge
  this release first, since their docs reference `corpflow:` ids.
- **`COMPANY_WORKFLOW_*` environment variables renamed to `CORPFLOW_*` with no fallback read** —
  `TEST_GATE`, `TEST_SELECT`, `AR_REF_STRICT`, `PR_BODY_STRICT`, and
  `COMMENT_DENSITY_{MAX,WARN,MIN_LINES}`. An eighth, `COMPANY_WORKFLOW_DIR` → `CORPFLOW_DIR`, lives
  in `scripts/validate.sh` in four of the siblings. Update shell profiles and CI jobs.
- **Stale installs must be reinstalled.** `~/.claude/plugins/cache/` and the
  `known_marketplaces.json` / `installed_plugins.json` indexes still key on the old plugin name
  until then.
- **`audit.jsonl` is not comparable across the boundary** — the `subject` field changes prefix, so
  pre- and post-rename audit trails cannot be diffed directly.

### Not changed

Pre-4.0.13 `CHANGELOG.md` entries and `benchmark/results/**` keep their original text. A changelog
row records what shipped under the name in force at the time; rewriting it would make the history
lie. `benchmark/results/result.html` still reads "igrsoft benchmark" for the same reason and
regenerates from `report.py` on the next `make report`.

## [4.0.12] - 2026-08-12

Activating guards that were already written. A full `/worktask` run (OV-184, shipped as PR #436)
burned a whole DV cycle: the agent pinned itself to a stale worktree of a *different* clone and
could write nothing. The agent's logic was not at fault. `/worktask` never stamped
`metadata.workspace_path` — only `/megatask` did (`commands/megatask.md`) — and that single
omission silently disabled three guards that already existed and were already tested:

| Guard | Why it no-opped |
|---|---|
| orchestrator workspace-root cross-check | `_task_root="${_task_root:-$_orch_root}"` compared a value to itself |
| `dv-tree-preflight.sh` `resolve_assigned()` | returned empty → warn + exit 0, by design |
| `agents/developer.md` path-prefix check | gated on "when `task.metadata.workspace_path` is set" |

`dv-tree-preflight.sh` would have caught this exact failure — its header names the scenario
verbatim — but nothing invoked it: a prose reference with an unfilled `<workspace>` placeholder,
no hook, no orchestrator injection.

### Added

- **`metadata.workspace_path` stamped on every run.** Seeded into `state.json` at
  `commands/worktask.md` Step 3a (`git rev-parse --show-toplevel`, else `pwd`) and onto the PL0
  task at Step 4, beside `isolation`. Documented in the ledger schema
  (`handoff-protocol.md § metadata.workspace_path`) and in `task-system.md`.
- **`dv-tree-preflight.sh` invoked from the DV dispatch surface.** A new Step 4.8 assigned-tree
  banner instructs DV to run it before its first edit and treat exit 1 as blocking — following
  the precedent Step 4.8a states outright: *prose loses to the dispatch surface*.
- **Step 6.5a2 — incomplete-return arm.** An agent that yields mid-sentence with budget remaining
  has not errored, so 6.5a does not fire and control fell through to F3, which hard-codes
  `status:"completed", verdict:"ok"` over a stage that never finished. The arm keys on the
  evidence (artifact absent, or present with no `handoff.verdict`) rather than on message shape,
  marks the stage `in_progress`, emits `stage_returned_incomplete`, and resumes the agent via
  `SendMessage` instead of re-delegating. A normally-completed stage still takes the Layer-2 path.
- **`--emit pr` idempotency.** `attach-visual-evidence.sh --emit pr` caches its emission at
  `.context/logs/visual-evidence-pr-<worktask_id>-<run_index>.md` and replays it on any later run
  for the same run index; `--force` re-hosts. Running it twice previously uploaded two full asset
  sets and orphaned the first on GitHub. `fn-preflight.sh` treats the new `reused` audit result
  exactly like `ok`, so a replay cannot retire the "## Visual evidence" heading requirement.
- **`agents/developer.md` § The voluntary yield** — never end a turn to announce what you are
  about to do next; an intent sentence is not a handoff. Plus a sixth Artifact-Complete Gate box.
- **`agents/developer.md` § Manifest row shape** — DV is told the manifest is written *by the
  skill* and so never sees a column name. Adds the canonical 9-column row and the two-digit-index
  rule, and says why a malformed row is worse than a missing one.

### Changed

- **The cross-check no longer defaults to itself.** An unset `workspace_path` is now a loud stop
  with a named audit row, not a silent pass.
- **`dv-screenshot-capture/references/examples/README.md` corrected to the canonical 9 columns.**
  It was a **7**-column table (no `Captured`, no `Design Ref`) that would fail
  `--validate-manifest` — and it is the file `attach-visual-evidence.sh`'s failure diagnostic
  sends a stuck DV agent to. Its AC-coverage table became a list, since the validator judges
  *every* pipe table in the file it is pointed at.
- **`workspace-modes.md`** gains the sibling-**worktree** hazard beside the existing
  sibling-*clone* hazard, with the table of why D0, D0.0, and the stated Edit/Write rule all pass
  on the wrong tree. Its claim that stale worktrees are auto-cleaned with no reuse of
  prior-session worktrees is corrected — this run disproved it.
- **`agents/developer.md` D0/D0.0** name the failure geometry: once the harness pins a worktree,
  `git rev-parse --show-toplevel` returns *that* tree, so D0 is self-consistent and cannot detect
  the problem; and a stale worktree passes D0.0 because it genuinely is isolated.
  **Isolation ≠ assignment.** D0.0a's `<workspace>` placeholder is replaced with the concrete
  resolution order.
- **`agents/product-manager.md`** no longer frames `workspace_path` as a megatask-mode detector.
- **`references/resume.md`** classifies the yielded agent, which sat between its live-mid-work
  and agent-gone rows.
- **`pr-body-lint.sh` usage errors print to stderr.** `usage()` sent the help header to stdout
  while the one-line diagnostic went to stderr, so under this plugin's own `; true` / piped
  convention a caller saw help text and read it as "ran, nothing to report". An explicit
  `-h`/`--help` still writes to stdout.

## [4.0.11] - 2026-08-10

Fail-loud worktask tooling (#431 retrospective, 9 approved self-improvement proposals). The
defect class: a tool that reports success while doing nothing. `state-patch.sh`'s existing
exit-0-on-unresolved behaviour is correct for most callers (a hook probing for a stage that
never ran), but for the 13 stage agents patching their *own just-written* artifact it meant a
missed ledger patch returned success — the same silent-skip shape recurred three separate times
in this repo's own history before this worktask.

### Added

- **Fail-loud self-patch assertion (REQ-2).** `state-patch.sh` now exits **3** when the artifact
  does not resolve, `--prev` is present, and `--via` is absent — the documented signature of an
  agent patching its own predecessor edge (`handoff-protocol.md:846`). Every other combination —
  a hook, `--via`, or a never-run stage — keeps the exact exit-0 no-op byte for byte;
  `state-patch.bats:51` is unmodified. `--allow-missing-artifact` silences the assertion for a
  caller that legitimately wants no edge, but writes **nothing** — documented as such at all four
  citing sites after a review-round finding that the first pass had it write a synthesized entry.
- **Resolution-only alias basenames (REQ-1).** `DR: review`, `QA: qa`, `FN: finalization` resolve
  in a new sibling function, never inside the canonical 13-entry map, so the existing parity
  guard keeps reading exactly 13 primaries. `AR: analyzing` is deliberately not added — a prior
  artifact-naming generation used it, and re-accepting it would let a stale file answer for the
  current one.
- **`USER` as a valid `--prev` predecessor (REQ-3).** Matches the already-canonical `USER→PL` /
  `USER→IR` edges; `USER` still owns no artifact and is never a valid `--stage`.
- **`dv-tree-preflight.sh`, new D0.0a gate (REQ-7).** Asserts the resolved git root **equals**
  the assigned workspace before DV's first edit. Worktree isolation alone doesn't catch this —
  a stale worktree is perfectly isolated, which is how a correctly-specified edit once landed on
  the wrong tree.
- **Screenshot-manifest schema at the writing stage (REQ-8).** `attach-visual-evidence.sh
  --validate-manifest` is a new read-only mode; `dv-screenshot-gate.sh` ANDs its verdict into the
  pass condition and now blocks a table-free manifest sitting beside real capture files (the
  parser reports the fact, the gate applies the policy — only the gate can see the directory).
  A genuine table-free skip-rationale manifest with no captures beside it still passes.
- **Explicit issue-close check on non-default integration branches (REQ-9).**
  `fn-preflight.sh issue-close-required` compares the merge target against the repo's default
  branch and prints the exact `gh issue close <N>` command when they differ, so a non-default
  integration branch can no longer leave the tracking issue silently open. FN's procedure gained
  the acting step that runs it and executes the printed command.

### Changed

- **Tool grants for 10 of 13 stage agents, not the plan's 6 (REQ-5).** `software-architector`,
  `technical-writer`, `team-lead`, `stakeholder`, `ethics-reviewer` held no `Bash` grant at all;
  `product-manager`, `technical-lead`, `security-reviewer`, `release-engineer`, `project-manager`
  held narrow allowlists with no `bash`. All 10 gain the scoped
  `Bash(bash skills/worktask/scripts/state-patch.sh:*)` token. This grant is **empirically
  unverified** against the permission matcher under enforcement — the probe session that ran it
  enforced no denials at all — so it is not the fix by itself.
- **Mandatory documented Edit-direct fallback for all 13 agents (REQ-6), the load-bearing half.**
  `$CLAUDE_PLUGIN_ROOT` was confirmed empty in the model's Bash tool environment (exit 127 on a
  probe), so no grant string keyed on it — and the cache-install path is version-keyed, so no
  stable literal exists either way. Every agent's State Patch section now states an ordered
  ladder: run the script; on exit 3, write the artifact and re-run; if the tool cannot run at
  all, patch `.context/state.json` directly with `Edit` — both the `stages.<CODE>` entry and the
  `handoffs["<PREV>→<CODE>"]` edge — and record the occurrence under `metadata.pl_tooling_gaps`.
  The SubagentStop hook is explicitly not a substitute: it never passes `--prev`, so it repairs
  the stage entry but drops the handoff edge.

### Fixed

- `attach-visual-evidence.sh` table separator detection now accepts alignment rows (`:---`),
  removing a false schema block on a valid model-authored table.
- `fn-preflight.sh`'s unresolved-issue line no longer promises a `gh issue close` command in the
  same breath as reporting it cannot be printed.
- `state-patch.sh`'s basename resolver requires the filename stem to equal the basename exactly,
  so e.g. `qa-notes-3.md` can no longer answer for the new `qa` alias.

## [4.0.10] - 2026-08-07

Eval-audit release (#279). The benchmark's only quality signal was the arm's own
`swift test` — self-graded, and across every stored live record it never once
returned `fail`. Nothing measured whether generated output was actually correct,
user corrections to delivered work were discarded with each run's gitignored
`.context/`, and skill eval sets carried prose expectations no grader could
check. This release makes each of those signals held-out, durable, or binary.

### Added

- **Held-out oracle** (`benchmarkkit/oracle.py`, `benchmark/oracle/cases.json`).
  Both arms' prompts embed a scripted CLI contract (`_cli-contract.txt` is the
  SSOT; a lint pins both prompts to it verbatim). After measurement the harness
  release-builds each arm's `tictactoe` and scores it against 30 cases whose
  goldens are captured from `ttt-template`, never hand-written. Cases are tiered:
  `specified` (24, restates the contract — the floor `pass_fail` reads) and
  `implied` (6, derivable but unstated — the discriminating signal, reported
  beside the verdict). A mutant that sweeps `specified` while failing `implied`
  is built and asserted in `test_oracle.py`.
- **Comparability eras.** Every record now stamps `era` (harness generation,
  prompt-contract version, per-stage model pins); `bench-analyze` compares
  against the previous live record automatically and caveats each differing
  dimension — the v3.37.1 silent-repin failure mode, closed.
- **Committed failure-label dataset** (self-improvement Step 5b,
  `evals/failure-labels.jsonl`). Classified user edits persist as append-only
  JSONL labels via `append-labels.sh` (idempotent per worktask run, opt-out
  `SELF_IMPROVE_LABELS=0`, no diff bodies); `label-stats.sh` aggregates per
  target/category. Runs regardless of proposal approval.
- **Binary skill eval sets.** `skills/request-plan/evals/evals.json` replaces
  prose expectations with code-checked assertions (`contains_all`/`contains_none`/
  `regex_all`/`regex_any`); `tests/python/test_skill_evals.py` is the assertion
  engine plus a lint keeping every eval set gradeable. Interpretive criteria are
  parked in `deferred`, not graded badly.
- **Skill-reference contract** (`tests/shell/skills/skill-refs.bats`). Four
  repo-wide predicates: every ordered `Skill(` call has the `Skill` tool grant,
  every Skill target names a real skill, every `skills/<name>/…` citation
  resolves, and every agent citing plugin paths carries a `## Plugin paths`
  resolution block. Each predicate is falsified against a synthetic tree.
- **Findings docs**: `results/AGENT-GRANT-ENFORCEMENT.md` (tool *sets* bind in
  headless dispatch; `Bash(cmd:*)` scoping and `maxTurns` did not — probe
  specified before any fix), `results/KNOWN-BAD-RECORDS.md` (stored records
  excluded from comparisons instead of edited), `results/VARIANCE-STUDY.md`
  (the n=3 procedure; the only step that spends money).

### Changed

- **Per-arm budgets and per-stage projections** (`benchmarklive/budget.py`).
  Paired runs split `--budget` into equal per-arm tallies (a shared purse let
  the first arm starve the second — the defect that invalidated the first
  paired A/B), projections use calibrated `STAGE_EXPECTED_TOKENS` (DV ≈ 10× a
  light stage; the flat figure admitted budgets that could not finish), and the
  running tally reserves the heavier of the projection and the heaviest
  observed stage.
- **Fail-closed verdicts.** An unmeasured or degraded arm is never green;
  where the oracle ran, it — not the arm's self-written suite — decides
  `pass_fail`. `coverage_pct` is `null` when unmeasured, never a fabricated 0.0.
- **Live retention is unbounded** (`rotation.RETENTION`): live records and
  their `results/runs/live/` detail files are kept and tracked in git —
  deterministic records stay latest-3 and gitignored.
- **Agents**: every agent carries the `## Plugin paths` resolution block;
  `developer` and `stakeholder` gain the `Skill` grant their bodies order
  (`dv-screenshot-capture`, `self-improvement` — both silently never ran);
  `Skill` invocations use the real `Skill({skill: "company-workflow:…"})`
  syntax; `technical-lead`'s DR gate reads `commands/dev-code-review.md` as a
  command instead of invoking it as a nonexistent skill.

### Fixed

- Each arm's verdict reads its own degradation flag; a WITHOUT-only breach no
  longer fails a complete, oracle-conforming WITH arm (pinned by
  `PairedVerdictSymmetry`).
- Label dedup hashes `(worktask_id, run_index, path, added, removed, summary)`,
  so a correction recurring in a later worktask counts as the recurrence it is
  instead of being dropped.

## [4.0.9] - 2026-08-06

Every test run was the whole suite. Editing one agent doc, one hook, or one script ran all
55 `.bats` files, so the dev loop paid full-suite latency for a one-file change and the only
lever was to skip testing entirely. The obstacle to fixing it is that a wrong selector is
silently green — it under-runs and reports success — so the change is built to over-select
by construction: three independent layers unioned, a floor that every run includes, and
seven triggers that abandon selection and run everything. Selection is opt-in and off by
default; a bare `./run-tests.sh` is byte-identical to what it was.

### Added

- **A three-layer change→test dependency matrix.** L1 is computed live from the tree — every
  repo path a `.bats` names literally, plus the `X.sh` → `X.bats` convention resolver, which
  matters because 13 scripts have more than one consumer and convention alone returns one of
  them. L2 is `tests/selection/matrix.tsv` (24 rows), for dependencies that are a *pattern*
  rather than a path, where the glob lives inside the script the test invokes. L3 is the
  ALWAYS floor, a constant in `tests/lib/select_lib.bash`: `lib/test-helper`,
  `meta/coverage-proxy`, `skills/plugin-root-refs`, and `worktask/manifest-parity` — 47 of
  811 tests, included in every scoped run. The engine lives in `tests/lib/select_lib.bash`
  and `tests/bin/select-tests.sh`.
- **An opt-in runner surface** (`run-tests.sh`, `Makefile`). `--changed` runs the selection,
  `--base <ref>` picks the diff base, and `--print-selection` prints the plan and runs
  nothing. `make test-changed`, `make test-changed BASE=master`, and `make test-select` wrap
  the three. `COMPANY_WORKFLOW_TEST_SELECT=0` disables selection entirely. Passing
  `--changed` with `--coverage` is a hard **exit 64**, not a silent full run.
- **Fail-closed triggers F1–F7.** An unrecognised path, an unresolvable base, an empty
  changed set, a delete under `tests/`, `hooks/`, `.claude/hooks/` or a skill `scripts/`
  directory, a change to the runner or the selector itself, and an unparseable matrix each
  yield a `FULL` verdict and run everything. `--print-selection` names the trigger id, so a
  widened run says why it widened instead of looking like a slow selection.
- **A >50% widening cap with a hand-off to QA** (`run-tests.sh`). A selection covering more
  than half the file count emits `WIDE`. If `.context/state.json` shows the DV stage in
  progress the run exits **65** and hands the suite to QA, since DV has no full-suite
  authority; for everyone else `WIDE` is informational and the run proceeds.
- **A 17-guard suite** (`tests/shell/meta/test-selection.bats`). It drives the real selection
  entry point rather than asserting on the matrix data, refuses a matrix row without a
  rationale, refuses a glob matching no tracked path, refuses a `.bats` no layer can reach,
  and plants violations to require the checker to name them — the fail-closed and cap
  behaviours are falsification tests, not assertions about output text.

### Changed

- **The test-execution gate now classifies by argument** (`hooks/test-execution-gate.sh`).
  `run-tests.sh` has a selection surface, so a bare invocation is still `full_test_run` while
  `--changed`/`--base` read as `scoped_test_run` and `--print-selection` as `build_only`.
  DV may therefore run a scoped suite it previously could not. Matching is padded-segment and
  anchored, so `cat run-tests.sh` does not classify as a test run. The widening cap is
  deliberately **not** enforced here: only the runner knows the selection size, and this hook
  stays a cheap `PreToolUse` classifier.
- **`tests/shell/meta/coverage-proxy.bats`** now drives the resolver extracted into
  `tests/lib/select_lib.bash` through shims instead of carrying its own copy, and its
  script-inventory check iterates the alias keys. The resolver's `find | head -1`
  filesystem-order dependence is fixed with `LC_ALL=C sort`, so a multi-match is stable.

### Deliberately not shipped

- **No `make coverage-changed`**, and `--changed --coverage` is a hard exit 64 rather than a
  no-op (`tests/COVERAGE.md`). kcov's denominator is the **source** set and does not shrink
  when fewer tests run, so a scoped coverage run lowers the numerator only — the bash branch
  has no percentage gate to catch it and would report a drop that looks like a regression in
  the code rather than in the measurement, while the Swift branch's ≥85% gate would fail for
  a reason unrelated to the change under test. Coverage is a full-suite QA activity.
- **No module correlation.** A `SKILL.md` edit does not pull in that skill's script tests.
  This is the release's main residual false-negative risk: a reference-doc edit whose path no
  test names literally selects only the ALWAYS floor. It is bounded by the reachability and
  non-script-coverage guards, and the fix for any gap found in practice is a targeted matrix
  row, not a blanket rule.
- **No `/test-select` slash command** — manifest parity asserts the marketplace command list
  against the commands directory, so adding one carries its own blast radius.

## [4.0.8] - 2026-08-06

`state-patch.sh` skipped its write whenever a stage was already `completed` at the same
verdict. A review-remediation loop is exactly that shape — DV completes `ok`, DR requests
changes, DV remediates and re-completes `ok` — so the second call short-circuited and left
`handoffs["PREV→CODE"]` describing the pre-remediation artifact, with no flag to correct it.
The stage record and the artifact reference stayed correct, so nothing failed loudly; the
inline summary a later stage reads just described work that had since been redone.

### Fixed

- **The idempotency guard now compares the whole patch, not just status and verdict**
  (`skills/worktask/scripts/state-patch.sh`). It additionally compares
  `stages.<CODE>.artifact` and, when `--prev` is given, the handoff edge the call would
  write. Identical inputs still exit early and leave `state.json` byte-identical; a changed
  artifact or summary now re-merges and logs `re-merge: ... artifact/handoff differ`.
  Observed twice in one worktask (`AR→DV` and `DV→DR`), once on a review agent's own patch.

### Added

- **Regression coverage for the remediation loop** — self-test `T10` (same-verdict re-merge
  refreshes the edge; a third unchanged run stays byte-identical) plus two `bats` cases in
  `tests/shell/worktask/state-patch.bats`. Verified against the pre-fix script, which leaves
  the stale edge in place.

## [4.0.7] - 2026-08-06

Branch naming's `--goal` took the raw task description, so a multi-sentence description
silently truncated mid-phrase into the branch slug — the original incident was operator
error compounded by doc wording that discouraged the cheap fix (a free preview) and hid the
free one (query modes). This release ships the branch-naming R1-R4 fix, R6's linked-worktree
rename behaviour flip, and documentation reconciliation together.

**This release changes default git behaviour on every linked-worktree machine** (Conductor
and similar host-workspace setups) — see `### Changed — R6` below before upgrading.

### Changed

- **`--goal` now takes a concise imperative title**, not the raw task description
  (`commands/worktask.md § Step 3c`, `skills/worktask/SKILL.md § Validation check 10`).
  `BRANCH_NAME_PRINT=1` is documented as a free preview — no rename, no audit row — and the
  "do not re-invoke" prohibition is narrowed to **rename mode** only, so the query modes
  (`--check`/`--print-types`/`--print-target`) stay free to use.
- **Truncation is now visible end to end**: `branch-lib.sh` gains `slug_body`/`slug_budget`/
  `slug_is_truncated` (`derive_slug` refactored onto them); `branch-name.sh` emits
  `slug_truncated=1` conditionally; Step 3c writes a `branch_slug_truncated` audit row; the
  Step A.5 plan-gate summary surfaces the derived name and the truncation warning.

### Changed — refinement window & invariant reconciliation

- **The planned branch name gets one pre-commit refinement window.** New
  `skills/worktask/scripts/refine-branch-target.sh`, invoked at new Step A.4b, refines the
  planned target once from the approved plan's own `title:` before the issue is published —
  six gates, a closed 15-token noop reason set, one `branch_target_refined` audit row, atomic
  ledger write, **no git mutation**, exit 0 always.
- **Once-only rule reconciled across 8 sites** (`skills/shared/git-conventions.md`,
  `skills/worktask/references/handoff-protocol.md`, `skills/worktask/references/resume.md`,
  `agents/project-manager.md`, `agents/product-manager.md`, `commands/worktask.md`,
  `skills/worktask/SKILL.md`, `skills/shared/task-system.md`): the **rename** happens exactly
  once, at the start of planning; the **planned name** on the ledger may additionally be
  refined at most once per run, pre-commit, ledger-only, with no git mutation.

### Changed — R6: linked worktrees now rename their own branch

**Behaviour flip, opt-out available.** `branch-name.sh` now renames the local branch inside
a linked worktree (Conductor and similar host-workspace setups) instead of deferring to
whatever name the host assigned. `is_host_workspace` still detects a worktree, but its early
`return 0` is gone: a hit now sets `IN_WORKTREE=1` and falls through to the existing
`target_exists` → `git branch -m` tail, same as any other workspace. On success `branch=`
and `target_branch=` are equal.

#### R6 — why, and the risk

The deferred behaviour assumed the host owns a meaningful, stable branch name. Falsified
live, in this very worktask — Step 3c saw `cape-town` (a placeholder), and by the
finalization gate Conductor had **silently renamed the branch mid-run** to
`which-stages-ran-tests` (derived from the chat topic), so `facts.branch` diverged from the
actual local branch with nothing detecting it. Neither name was shippable, and nothing in the
old design could tell. **Risk, stated plainly**: a host that keys its own workspace tracking
to the branch name may need to re-sync after this rename. Documented rather than discovered.

#### R6 — the opt-out and the new guard

**Opt-out**: `BRANCH_NAME_WORKTREE_RENAME=0` (literal `0` only) restores the previous
defer-to-host behaviour. Subtractive at guard-ladder position 8 — it can only restore a
behaviour a higher guard already permitted, never authorize a rename a higher guard refused.
**This is the line an upgrading user most needs to find** if their host relies on the old
behaviour. **New `already_named` guard** at ladder position 4, keyed on the `branch_renamed`
audit dedupe key rather than the branch name — a host rename makes the branch
non-conventional again, and a name-based guard would have authorized a *second* rename.

#### R6 — divergence detection and disclosure

**New `fn-preflight.sh branch-divergence`** (also runs on resume): non-blocking, exit-0-
always, excluded from `all`. Compares local HEAD against the `to` of the last
`branch_renamed / ok` audit row, classifying `expected` vs `third_party`, and surfaces only
`third_party`. **Mandatory disclosure**: a stdout line at rename time names the host re-sync
risk and the opt-out; the Step A.5 gate summary carries a matching line. Both reach a user
already running the pipeline — neither reaches a user deciding whether to *upgrade*, which is
why this CHANGELOG entry is the third disclosure surface. 12 reconciliation sites, including
Step 3c's "never revert this step's rename" rule, which was previously moot inside a worktree
and is now live there too.

### Fixed

- **Audit-scan `fromjson?` guard completed against well-formed non-object lines.** R1's AD-9
  hardening closed the *unparsable*-line half of this class but left the well-formed
  *non-object* half open (`123`, `[1,2]`, `"str"` parse cleanly, then abort on the first
  field access) — and the failure is **position-dependent**: whether the bad line sits
  before or after the row a scan is looking for.

#### Fixed — all four scans, `objects` load-bearing in each

| scan | jq form | bad line before match | bad line after match |
|---|---|---|---|
| `branch-name.sh already_named` | slurped | rc 5, fails open | rc 5, fails open |
| `fn-preflight.sh branch-divergence` | slurped | rc 5, detection suppressed | rc 5, suppressed |
| `refine-branch-target.sh` once-guard | streaming | rc 0, holds | **rc 5, fails open** |
| `refine-branch-target.sh` incumbent-truncation | streaming | rc 0, holds | rc 5, fails closed |

#### Fixed — why "after the match" is the common case, not the edge case

Audit logs are **append-only**, and the streaming pair's own rows land unusually early: the
once-guard scans for `branch_target_refined / ok`, written at Step A.4b, and the
incumbent-truncation check scans for `branch_slug_truncated`, written even earlier at Step
3c — both in Phase 1, before any stage dispatch. Every later stage's row necessarily
accumulates *after* them, so "bad line after the match" isn't merely the common case for
these two scans, it's very nearly guaranteed. Demonstrated end to end against the
un-hardened once-guard: a second refinement was authorized (`ok_rows=2`, the ledger value
overwritten); hardened, it correctly declines `already_refined` (`ok_rows=1`). All four scans
now use `fromjson? | objects`; the same gap existed in three test helpers, which is why the
new cases initially failed against already-correct production code — a fixture line must not
be able to break the assertion helper and mask the real result.

### Fixed — COVERAGE.md re-measurement

- `tests/COVERAGE.md`'s bash `@test` total was stale three times this release: first after QA
  closed three P2 coverage gaps (AC-7/23-25) in `refine-branch-target.bats` (680→683), then a
  self-contradictory `683`/`53` after R6, then a fourth-assertion undercount from a race
  between two parallel stages. Superseded by a single direct re-measurement taken after both
  stages settled: **787 `@test` across 54 `.bats` files**, `branch-name.sh` now the
  highest-density target at 90.

### Known limits (deferred, not shipped this release)

- **R5** — ticket derivation for a bare GitHub issue number (`#N`) is deliberately deferred
  pending an explicit grammar decision: mint an `issue-390-` segment, or document that repos
  minting their own issue numbers stay ticket-less. Never fabricate an alphabetic tracker key
  from a bare issue number.
- **`cache-lint.sh:92`** (`--anchor-lint`'s `extract_stage()`) pipes whole markdown files to
  `yq` under `|| true` and is non-deterministic on artifact content — confirmed by review: it
  passed against one stage artifact and failed against another for no reason but body length.
  It cannot serve as a gate for any stage until `:92` is routed through the existing
  frontmatter-scoped helper at `:485`. Not fixed here — out of this release's scope; routed
  to DV for the next touch of the script.
- **`skills/agent-coordination/scripts/audit-dedup.sh:84`** has the identical well-formed-
  non-object `fromjson?` gap this release's audit-scan fix closed elsewhere
  (`[inputs | select(length > 0) | fromjson?] as $rows` then `.value + {__idx: .key}`,
  with no `objects` filter). Pre-existing, not introduced by R4 or R6, left unfixed here —
  same one-token fix as the four scans above.

### Known limits, continued

- **`state-patch.sh` idempotency** short-circuits when a stage is already `completed`,
  silently dropping a remediation cycle's handoff summary. A remediation round in this very
  release needed a manual `stages.DV.status` reset to re-apply. Not fixed here; needs a
  design call (always re-merge summary fields vs. document the manual-reset procedure).

## [4.0.6] - 2026-08-05

The test-execution gate advertised "DV may not run the full suite" but did not enforce it for any
runner whose mandatory flags are non-selecting. A full `xcodebuild test` with `-project`, `-scheme`
and `-destination` sailed through, because the classifier saw surviving arguments and concluded the
caller had narrowed the run.

### Fixed

- **Full-suite runs carrying only non-selecting flags now deny at DV.** The classifier strips each
  runner's mandatory-but-non-selecting flags before the "did an argument survive?" test. The strip
  is **quote-aware**, which is what the reported incident actually needed:
  `-destination "platform=iOS Simulator,name=iPhone 16 Pro"`. Verdicts invert allow→deny for
  `xcodebuild test` with project/workspace/scheme/destination/sdk/arch/result-bundle/derived-data
  flags, `dotnet test <solution>`, `gradle test -p .`, `npm`/`pnpm`/`yarn test --ci`, and
  `cargo test --release`. The gradle task token is found **order-independently** (mirroring the
  xcodebuild action scan), so the flags-before-task spelling `gradle -p . test` denies identically
  rather than slipping through on the project-dir positional — and the same scan removes a
  pre-existing false deny: `gradle -p . assembleAndroidTest` (a flags-first build-only task) no
  longer reads as a test run at banned stages. Genuine selectors (`-only-testing:`, `--filter`,
  `-k`, `-t`, `-run`, a real positional) still classify scoped and are allowed, at DV and
  everywhere else.
- **`-only-testing:` selector spelling.** The explicit selector list spelled the Apple selector with
  two leading dashes; the real flag takes one, so that limb never matched a real invocation and
  scoped Apple runs classified correctly only via the positional fallback.
- **Two pre-existing false denies removed.** `-c` is not a selector for `go test` (compile-only) or
  `rspec` (`--colour`), joining the existing `bats -c` (`--count`) build-only carve-out.
- **The DV authority-matrix note documented the bug as the contract.** It claimed the deny was
  "mechanical for the bare-runner form only" and that any trailing flag classified scoped. Rewritten
  to describe what the gate now does, with its known limits stated plainly rather than buried.
- **The finalization stage was instructed to do what it is forbidden — and unable — to do.** Its
  duty list ("Run final builds and tests"), its completion checklist ("All tests passing in final
  build") and the finalization row of the shared pipeline stage table all contradicted the
  prohibition the same agent carries. FN holds no test-execution authority, no build/test Bash
  grant and no `Skill` tool, so even a build-only rewrite would have been unreachable. It now
  **verifies QA's recorded evidence** from `testing-N.md` frontmatter, mirroring the stakeholder
  stage. The `requests_test_evidence` escape path is unchanged.

### Added

- **Narrowest-run default in the developer contract**, with its cost attached: verify with the
  narrowest run that proves the change — build-only for a compile check, a selector for behaviour.
- **Fixtures on both surfaces**, 24 → 40 self-test assertions and 58 → 80 bats cases, including a
  finalization-stage deny case kept as a doc-parity lock rather than a bug catch.

### Known limits (accepted, documented)

- Whole-tree positionals (`go test ./...`, `pytest tests/`) still classify scoped. Flipping the
  positional limb's polarity has a different fail direction and is tracked separately.
- `npm|pnpm|yarn test -- -c <spec>` denies although genuinely scoped (one shared arm). Moving `-c`
  into the valueless arm would strip the flag and leave its value surviving as a positional, so any
  full run with a valueless flag before a positional would classify scoped and be allowed —
  reopening the hole this release closes. These package managers hide the underlying runner, so the
  ambiguity is irreducible. `npm test -- <spec>` is unaffected.

## [4.0.5] - 2026-08-05

Test-suite stringency hardening. The suite went from 45 files / 501 tests to **53 / 680**, every
claim in it re-derived by mutation rather than ratified, and four production defects the old tests
had characterised as "known bugs" were fixed. One of those four is a **security disclosure for
downstream consumers** and is listed first.

### Security

- **DISCLOSURE — `scan-secrets.sh` never detected credentials in database URLs. If you have run this
  plugin's security-review stage in your own repository, your past scans may have missed
  `mysql://`, `postgres://` and `mongodb://` credentials, and a clean result did not mean they were
  absent.** This is not a newly introduced regression; it is a defect that shipped from the
  beginning.

  - **What was wrong.** The built-in fallback scanner stored each rule as
    `label|severity|regex` and recovered the pattern with `${entry##*|}` — a *greedy* strip to the
    **last** `|`. Exactly one built-in pattern, `database-url`, contains an alternation, so its
    regex was truncated mid-group to `mongodb)://[^@[:space:]]{3,}@` — an ERE with an unmatched `)`.
  - **It failed on every dialect, but by two different mechanisms — and neither was noisy.** GNU
    `grep` and `ugrep` **reject** the pattern (exit 2, parse error). BSD `/usr/bin/grep`, which is
    what this script actually resolves at runtime on macOS, **accepts** it and treats the unmatched
    `)` as a *literal* character — exit 1, no diagnostic, matching only the impossible text
    `mongodb)://…`. Either way nothing real was ever matched, and because the `grep` call sent
    stderr to `/dev/null`, even the GNU parse error was swallowed. The scan reported completion with
    no finding and no diagnostic on both paths.
  - **Do not assume a loud failure would have alerted you.** On the BSD path there was never
    anything to see: no error was produced at all, not merely suppressed.
  - **Which versions are affected: all of them.** `git log --reverse` on the script shows a single
    prior commit, `01c6f6f` (2026-06-29), which introduced both the file and the broken pattern.
    **No released version ever detected these credentials, on any `grep` dialect** — on GNU because
    the pattern was rejected, on BSD because it was accepted as a literal that matches nothing.
  - **Blast radius.** `scan-secrets.sh` is a shipped artifact, so every repository that has run the
    security-review stage since 2026-06-29 has run the broken pattern. The other five built-in
    patterns (AWS keys, private keys, generic tokens, and the rest) were unaffected and continued
    to fire normally; only the `database-url` class was blind. Repos configured to use `gitleaks`
    took the gitleaks path and are not affected.
  - **What to do.** Re-scan with this version. The fixed scanner reports
    `<file>:<line>:Critical:database-url` for all three schemes.
  - **Bounding the claim for *this* repository.** A retrospective scan was run here and is
    **clean**: 234 tracked files plus a 200-revision history sweep produced no real finding. Every
    hit is either a test fixture on an RFC 2606 `.invalid` host or a deliberate literal in the
    scanner's own `--self-test`. That result bounds this repository only and says nothing about
    yours.

- `scan-secrets.sh` now validates all six patterns at startup (an O(6) compile check) and no longer
  sends `grep`'s stderr to `/dev/null`, so a malformed pattern is fatal and named instead of
  silently producing an empty scan. **This is necessary but not sufficient, and would not have
  caught the original bug** — BSD `grep` accepts `mongodb)://` as a valid ERE, so the compile check
  passes it. Semantic truncation is caught only by the new per-scheme specimen tests.
- **Known limitation, unfixed and disclosed:** `scan-secrets.sh --self-test` still exercises only 2
  of the 6 built-in patterns, and `--self-test` is exactly what runs on hosts without `bats`. The
  script's self-contained check remains weaker than its external suite; that coverage was narrowed
  by **zero** in this change.
- **Known limitation, introduced here:** removing the stderr suppression means an unreadable file
  now emits `Permission denied` six times (once per pattern) and the scan still exits 0. Not fixed,
  because the only lever that makes a file unreadable is permissions, and such a test would pass
  vacuously under root.

### Fixed

- **`build-orchestrator.sh` produced false dependency cycles.** The `blocks?` regex also matched
  "Blocked by", adding a spurious reverse edge and failing the DAG build with exit 5. Now
  `\bblocks?\b`.
- **`build-context-set.sh` silently dropped agent paths on macOS.** GNU-only `\s` escapes mangled
  leading whitespace under BSD `sed`, and `set -e` then exited the pipeline. All **7** affected
  sites now use `[[:space:]]` (the original report named only 2).
- **`detect-user-changes.sh` double-counted every change.** A redundant second `git diff` ran in
  both the patch and the numstat blocks.
- **`milestone-helpers.sh` base-branch strip was case-sensitive** while its detection was not, so a
  `BASE_BRANCH:` declaration was detected and then not stripped. `sed` gains the `I` flag.
- **`state-merge.sh` could not recover a corrupt state ledger.** It now rebuilds the skeleton and
  falls through to the unchanged `state-patch.sh` delegation, backing up the corrupt file first and
  aborting without modification if the backup cannot be written.
- **The Python phase's exit status was discarded**, so a failing Python suite could not fail
  `make test`. The suite rc now propagates.
- Documentation drift: `tests/README.md` and `tests/COVERAGE.md` disagreed with each other (36/36
  vs 34/34 targets) and both disagreed with the tree. Both are regenerated from recorded commands.
  Dead references to `skills/agent-coordination/scripts/audit-dedup.sh` and to a `cost-log.sh` that was never shipped are
  corrected.

### Added

- `RUN_TESTS_REQUIRE_SWIFT=1` — opt-in gate making a skipped Swift phase a failure. The default exit
  status is unchanged; without it a Swift-less host still exits 0 and reports `SKIPPED PHASES`.
- `tests/shell/meta/coverage-proxy.bats` — a standing gate requiring every shell script to have a
  dedicated `.bats` with ≥3 real scenarios. Exemption list is empty.
- `skills/worktask/scripts/attachments-preseed.sh` — renders both Conductor attachments from their
  canonical templates, replacing six manual writer steps.

### Changed

- **`run-tests.sh`'s clean-clone guarantee now names `python3 >= 3.10`.** The guarantee was always
  conditional on it and never said so: `validate-export.sh` embeds a validator using PEP 604
  `X | None` annotations evaluated at runtime, which raise `TypeError` on 3.9. macOS ships 3.9.6 as
  `/usr/bin/python3`, so on a stock Mac the suite returns 1 until a newer `python3` is on `PATH`.
  This is a pre-existing defect in an untouched file — documented here, not fixed.

### Known issues

- `make coverage` is unreachable on macOS: the kcov branch runs away (352 MB of output in 90 s
  without completing a single target) and `benchmark/ttt-template` sits at 84.5 % against an 85 %
  gate behind it. The binding green criterion is `./run-tests.sh` rc 0.
- `state-merge.sh`'s repair writes through a `$$`-suffixed temp path that still follows a dangling
  symlink — same weakness class as the one fixed in its backup path, different code path.

## [4.0.4] - 2026-08-05

Gate-revision semantics. The spec carried one concept ("a PL invocation") where the pipeline has
two — starting a **new run** (allocate N+1, reset facts, create tasks) versus **revising the run
in flight** (reuse N, edit in place, preserve facts, update tasks). Only the first was specified,
so following the plan-gate rejection line verbatim silently forked the run. Both gates now specify
their revision path. Plus four rule fixes traced to observed failures in the 4.0.3 worktask.

### Fixed

- **Plan-gate rejection no longer forks the run (data loss).** Re-dispatching PM after a rejection
  allocated `planning-1.md` while the run was still on `planning-0.md`, which (1) wiped `facts.*`
  via the Step-4 state.json reset — erasing the `facts.decisions[]` the user had just supplied at
  that gate, (2) froze the plan under revision as "historical" and split AC baselines across two
  files, (3) `TaskCreate`d a second stage chain at `run_index: 1`, stranding the original tasks
  `pending` forever, and (4) bumped the `<worktask_id>:<run_index>:gh_issue` dedupe anchor so the
  revision read as a later run. `commands/worktask.md` now routes the rejection to
  § Plan-revision re-dispatch: `run_index`/`plan_file` frozen for the life of a run, PM
  re-dispatched with `plan_revision: true`, a four-row BINDING invariant table (edit in place /
  patch `facts.*` additively / `TaskUpdate` not `TaskCreate` / no issue re-publish),
  `metadata.revision_count` bookkeeping with one `plan_revision_dispatched` audit row, and a
  re-entry into the plan gate on return.
- **`agents/prompt-engineer.md` could not run its own embedded-command contract.** No `Skill` tool
  in the frontmatter grant, so a DV-stage dispatch carrying a mandatory
  `Skill("skill-creator:skill-creator", …)` contract had to escalate and apply the skill body
  manually as a disclosed substitute. `Skill` added.
- **AC verification commands could ship syntactically broken.** The
  `(unverified — dry-run required after theme lands)` mark excused everything, including
  invalidity — a shipped plan carried `grep -viv -e … -e …` (triple negation, a no-op reporting
  everything "clean") and three downstream stages independently re-derived the correct form. The
  mark now covers only the RESULT's representativeness, never the command's validity.

### Added

- **FN-gate rejection resume path** (`skills/worktask/SKILL.md § FN gate rejection`) — the same
  conflation at the second gate, which previously ended at "STOP (do NOT delegate FN)" with no
  defined resume. Now symmetric with the plan gate: feedback routed to the owning stage (DV fix
  round / DC re-stamp / plan amendment), `run_index` frozen, completed stages never re-run
  wholesale, `revision_count` bookkeeping, and the FN gate re-presented on completion.
- **DV-stage yield discipline for `agents/prompt-engineer.md`** — across one worktask it stopped
  mid-theme at least four times, each needing an orchestrator nudge to finish its own stage
  contract. Now points at `agents/workflow-engineer.md § Batch-Completion Discipline (DV
  execution)`, the rule that already existed but was unreachable from this agent.
- **`file:line` citations are starting sets too** (`agents/product-manager.md`) — the staleness
  rule that already covered enumerated FILE lists now covers LINE numbers cited in theme prose:
  cite as an approximate locator, require DV to re-locate the anchor by quoted text before
  editing.

## [4.0.3] - 2026-08-05

Full legacy-logic removal. Round 1 removed every rules-surface deprecation whose sunset window had
elapsed from `agents/`, `commands/`, `skills/` with zero semantics change. Round 2 (user-approved,
aggressive scope) then deleted the remaining legacy *logic* across hooks, scripts, tests, and the
benchmark harness — accepting loss of pre-4.0 `.context/` read-support. Load-bearing current
contracts (the F1–F4 fallback family, the `plan_file` path-vs-basename boundary, hook-vs-agent audit
authority, CC `--json` camelCase coalescing, visual-QA degradation invariants) are kept but reworded
away from the misleading word "legacy" — they are current behavior, not compatibility.

### BREAKING

- **Legacy `--auto-plan`/`--auto-finalization` flags removed.** Only `--auto=[plan, decision,
  finalization]` remains. These aliases are no longer recognised or documented; no rule in
  `worktask.md` governs an unrecognised top-level flag, so the effect of passing either legacy
  flag is undefined by the docs going forward.
- **`requires_ui_tests` back-compat mapping removed.** A resumed pre-4.0 `.context/planning-N.md`
  that still presents `requires_ui_tests: true` with no `test_mode` now falls to the `scoped`
  default and `ui_visual_check: false` — a legacy plan that asked for full regression plus Design
  Comparison silently gets neither, with no deprecation note surfaced.
- **Dual dedupe-key mechanism deleted.** `metadata.dedupe_key_extended` is no longer written by any
  hook and `skills/agent-coordination/scripts/audit-dedup.sh` (the base/extended mode selector) is removed. The 3-segment
  `dedupe_key` is the only documented shape; readers dedupe on it directly. `parent_agent_id` is
  still captured, for observability only.
- **Pre-run-index artifact names no longer resolve.** The artifact resolver's bare-basename rung
  (`.context/<base>.md`) is gone from `state-patch.sh` and from every documented resolver chain —
  only `<base>-<run_index>.md` and the newest-glob fallback remain.
- **Pre-#375 issue-title probe removed.** `publish-pl-issue.sh` no longer builds `TITLE_LEGACY` or
  re-probes the old slug title, so an issue published under the pre-#375 scheme is no longer found
  by the anchor-loss recovery search and a duplicate may be opened.
- **`state.json .git.base_branch` fallback removed** from the integration-branch chain; the
  surviving order is `$FN_BASE_REF` → `state.json .metadata.base_ref` → `workspace.json
  .git.base_branch` → `origin/HEAD` → unresolved.
- **Single-file visual-evidence marker shape dropped.** `attach-visual-evidence.sh` reads only the
  per-issue marker directory; `GH_MARKER_FILE` is no longer honoured.
- **Redaction supersets removed — leak risk accepted.** `publish-pl-issue.sh` no longer strips the
  `igrsoft:` plugin prefix or the pre-3.42.0 `analyzing-N.md` artifact name. A worktask resumed from
  a pre-4.0 `.context/` can therefore publish those internal identifiers into a GitHub issue body.
- **Strict benchmark token decoding.** A `tokens` block present in a benchmark record MUST carry all
  five keys (`in`, `out`, `total`, `cache_read`, `cache_creation`); a partial block now raises
  instead of decoding with silent `None`s. `benchmark/results/history.json` was migrated in place
  (key-presence-only, explicit `null`s).
- **`state.mcp_session`, `--severity` legacy aliases, and the bare-name agent shim dropped.**
  `metadata.agent` and `subagent_type` MUST be fully-qualified `plugin:agent`; `--severity` accepts
  only `P0`/`P1`/`P2`; `mcp_session` is gone from the state-ledger schema.

### Removed

- Legacy `--auto-plan`/`--auto-finalization` aliases and the `#### Legacy aliases (deprecated)`
  table (5 files + `README.md`).
- Sunset `requires_ui_tests` compat-mapping table (2 files, 6 sites).
- `igrsoft` rename residuals outside the vendor-identity allow-list (7 files).
- Stale pre-4.0 (`v3.x`) version gates: 21 of 42 matches removed in round 1; round 2 removed the
  rest, including every `v3.x+` header peg across the 8 remaining hook/skill scripts.
- Dead code: `_inline_merge` (the ~105-line inline state merger in `.claude/hooks/state-merge.sh`)
  and its call site — `state-patch.sh` is the single merge implementation.
- Files: `skills/agent-coordination/scripts/audit-dedup.sh`, `skills/shared/legacy-fallback-f1.md` (folded into
  `handoff-protocol.md#f1-fallback`), `tests/shell/hooks/audit-dedup.bats`,
  `benchmark/harness/tests/test_history_backcompat.py`, and 3 audit fixtures.
- `norm_dk` cross-shape key normalisation from `skills/agent-coordination/scripts/audit-dedup.sh`
  (it normalised a 4-segment key shape no writer ever emitted).
- The `fallback_legacy` value from the `artifact_path_resolved` audit enum (now
  `{ok, fallback_glob, miss}`) — unreachable once the bare-basename rung was removed.

### Changed

- Compaction pass across `agents/`, `commands/`, `skills/`: removed change-narration, deduped
  repeated canon to a single source + pointers, collapsed redundant structure. Total tracked
  markdown: 34,119 → 34,035 lines (`agents/` 4,722 → 4,694; `commands/` 9,329 → 9,292; `skills/`
  20,068 → 20,049).
- Reword sweep (rename-only, no behavior change): F1 is now "`context_files` mode" and is documented
  as required behavior rather than backward compatibility; the `handoff-harness.sh` A/B arm is
  "baseline" rather than "legacy"; `milestone-helpers` "Legacy Command" is "Non-worktree Command";
  visual-QA degradation invariants are canonical in `visual-qa.md` with `testing-strategy.md`
  pointing at them.
- `build-context-set.sh` no longer exits non-zero when a probed candidate path does not exist
  (each qualified agent ref probes agent/command/skill paths; a miss is normal).

## [4.0.2] - 2026-08-03

A live worktask in a Conductor workspace shipped PR #382 from `ov166-skin-score-all-layers`
— a branch name that fails this plugin's own `branch_is_conventional` predicate, on a repo
that merges rather than squashes, so the name is permanent history. The design was already
right (FN pushes `HEAD:refs/heads/<facts.branch>`, decoupling the PR head from the local
branch); it was fed a bad value. Scripts, tests, and docs only — no stage, agent, or gate
semantics change.

### Fixed — the derived branch target is no longer discarded on the no-op arms

`branch-name.sh` derived the conventional target inside the rename arm alone. Every other
arm — upstream tracked, target exists, jq unavailable — passed the *current* branch to
`emit_branch`, which prints `branch=` empty when the name fails the predicate. The right
answer was computed and thrown away, `facts.branch` landed empty, and FN's documented
fallback pushed the non-conventional local name as the PR head.

- **A second stdout line, `target_branch=<name>`**, emitted by every arm that can derive
  one, independent of whether the local rename happened. Derivation moved above the no-op
  arms; `derive_target` split out as a pure function. `branch=` keeps its exact semantics
  and stays the **final** stdout line — four docs and every consumer specify that parse, so
  the new line goes before it, not after. Both lines pass the same `branch_is_conventional`
  gate before emission, preserving the shell-injection hardening `emit_branch` exists for.
- **Arms that must not propose a target still emit it empty**: already-conventional
  (`branch=` is the answer), the integration branch (never a PR head under any name), and
  batch/incident routing (which owns its own naming).
- **Step 3c now stamps the target it already computed.** The post-check wrote `derived_target`
  into an audit row and discarded it; the orchestrator now stamps `facts.branch` from
  `target_branch=` whenever `branch=` is empty or fails `--check`, and the post-check reuses
  the captured value instead of re-invoking the script (which wrote a duplicate audit row).
  A non-empty `derived_target` in that warning row is now a bug report, not a shrug.

### Added — host-workspace (linked-worktree) arm

Nothing in the guard ladder could see a host workspace: Conductor leaves no `workspace.json`
in `$PWD`, so all five `fn_batch_scope` signals miss it. New arm, detected as
`git rev-parse --git-dir != --git-common-dir`: derive and emit the target, **skip** the local
`git branch -m`, audit `branch_renamed / skipped` with `reason: host_workspace_worktree`. The
host's branch↔workspace mapping stays intact *and* the PR gets a conventional head — what
`workspace-modes.md § Host mapping caveat` previously described as a manual equivalent is now
the automatic behaviour. `facts.branch` deliberately differs from the local branch name there;
that divergence is documented in `handoff-protocol.md` and `agents/project-manager.md` as the
designed outcome, so no reader "repairs" it back to a `git rev-parse`.

### Fixed — the host-session authorization was invisible at the point of decision

`workspace-modes.md § Host session authorization` ("invoking `/worktask` satisfies a host's
no-rename session rule") was referenced from exactly one file: the **FN** agent, which runs
long after the rename and never renames anything. The orchestrator at Step 3c — the only
actor that decides — had no pointer, and Step 3c's own "MUST NOT block, no STOP, no retry,
no rename" text reads as *tolerate the divergence*. An orchestrator holding Conductor's
session rule and Step 3c had everything it needed to revert a correct rename. It did. Step 3c
now carries the authorization inline as a BINDING note, in `commands/worktask.md` and
`skills/worktask/SKILL.md`.

### Tests

Twelve new cases in `tests/shell/worktask/branch-name.sh.bats` (57 total, all green): the
host-workspace arm over a real `git worktree` (local name kept, target derived, HEAD
untouched, audit reason); the acceptance trio executed through the documented Step 3c
stamping rule rather than paraphrased; both cwd cases for the detection itself — a
subdirectory of a plain repo must still rename (git answers `--git-dir` absolutely and
`--git-common-dir` relatively from there, so the comparison resolves both to physical
paths), a subdirectory inside a worktree must still detect; `target_branch=` on the
upstream-tracked, target-exists, and jq-unavailable arms; empty on the arms that must not
propose one; batch routing still winning over the host arm; a shell-hostile current branch
reaching neither emitted line; and the `BRANCH_NAME_PRINT` dry run unchanged.

## [4.0.1] - 2026-08-03

Two publication-surface bugs, both found the same way: a live worktask shipped output nobody
would have written by hand — a `fix/`-prefixed branch after `fix` had been removed from the
vocabulary, and a GitHub issue titled with a kebab slug. Neither was a failure; both paths
degraded silently and stayed within their non-blocking contracts while doing it. Scripts,
tests, and docs only — no stage, agent, or gate semantics change.

### Fixed — worktask branch naming (four defects on one path)

A live worktask shipped `fix/catalog-image-blinking` — a branch whose type prefix had been
deliberately removed from `BRANCH_TYPES`. The root cause was not the vocabulary but the step
that enforces it.

- **Step 3c was skippable.** `commands/worktask.md` told the orchestrator to run
  `branch-name.sh` but nothing verified that it did, so on a workspace already sitting on a
  plausible-looking branch an orchestrator could reasonably conclude "already named, skip" and
  stamp the pre-existing name into `facts.branch`. Step 3c is now **unconditional**, with the
  reason stated (the "already conventional" arm is a no-op, so always running it costs one
  process and is the only correct way to decide), a BINDING line that conventionality is
  decided by `branch_is_conventional()` and never by eye, an explicit pre-existing-branch
  clause, and a non-blocking post-check that emits one `branch_convention_check` warning row
  naming both the actual and the derived target when the stamped value fails the predicate.
- **The grammar gained an optional ticket segment** — `<type>/[<ticket>-]<slug>`. Repos using
  this plugin already ship `bugfix/ov-156-…`, which the spec (documented as the single source
  of truth) previously forced to drop its issue key. The new `derive_ticket` reads the first
  `\b[A-Z]{2,}-\d+\b` token from the goal text only, lowercased; no key found means unchanged
  behaviour. `branch_is_conventional` accepts both shapes, so no existing branch becomes
  non-conventional and gets churned. Branch ticket and PR closing keyword are complementary,
  not alternatives.
- **`derive_slug` no longer truncates mid-word.** `cut -c1-48` produced
  `…-blinking-before-r`; truncation now drops the trailing partial segment and always keeps at
  least one whole word. The ticket prefix is budgeted inside the 48-char cap, so a long issue
  key cannot starve the slug, and the key is stripped from the slug body so it appears once.
- **`derive_type` no longer misclassifies bug reports as features.** The `*"fix "*` arm
  required a trailing space, so "…investigate and fix" and "…and fix." fell through to
  `feature`. `fix` is now matched as a word (without swallowing `prefix`/`fixture`), and the
  bugfix arm gained the defect vocabulary `blink`, `flicker`, `glitch`, `broken`, `regression`,
  `incorrect`, `wrong`, `fails`, `failing`. The hotfix-before-bugfix ordering is unchanged.

Guard ladder unchanged — every arm is still a no-op or a refusal, never a failure. Commit-type
table untouched: `feature` stays branch-only. +26 bats cases across `branch-lib.bats` and
`branch-name.sh.bats`.

### Fixed — `publish-pl-issue.sh` published a garbage title and an empty Summary

Issue #375 was published as `OV-164 ov-164-catalog-image-blinking` with an empty `## Summary`.
`facts.goal` was the ONLY source for both, and it is OPTIONAL in the handoff protocol — written
only when the PM agent patches state.json, so orchestrator-inline seeding, a hand-authored
`.context/`, or a regenerated state left it unset and degraded both outputs at once, silently.

- **Title and Summary now resolve through independent chains**, first non-empty wins. Title:
  `facts.goal` → plan frontmatter `title:` → plan first H1 → first sentence of
  `## summary`/`## problem` → `worktask_id`. Summary: `facts.goal` → `## summary` →
  `## problem`. The worktask slug is deliberately not a Summary rank — an empty section is
  honest, a slug posing as prose is not.
- **New readers**, POSIX sh + awk in house style: `extract_frontmatter_field` (leading `---`
  fence only, so a thematic break mid-body is never mistaken for frontmatter),
  `extract_first_h1`, `first_sentence` (skips bullets; a terminator must be followed by
  whitespace, so `3.5s` is not a sentence end). The `head -1 | cut -c1-100 | sanitise_body`
  pipeline still applies to every rank.
- **Reaching the `worktask_id` rank is audited**, not silent: one advisory row with
  `reason: "title_fallback_worktask_id"` and `metadata.title_source`, on the
  `<dedupe_key>:title_source` suffix so it never masks the canonical outcome. Still non-blocking.
- **External-ticket extraction gained ranks** (winning title source, then plan frontmatter
  `issue:`) and its no-double-prefix guard is now case-insensitive and accepts `-` as a
  separator — the exact-case check is why `ov-164-…` was treated as unprefixed and doubled.
- **Recovery-search compatibility**: changing title generation orphans issues published under
  the old title, so `resolve_context_issue_search()` probes the current title first and the
  legacy one only on a miss. Documented as removable once that corpus is closed.

Secondary (separate commit): `commands/worktask.md` Step 3a now seeds `facts.goal` from the
task description, `skills/worktask/references/initialization-patterns.md` carries it in the
seed snippet, and `agents/product-manager.md` states that a non-empty `facts.goal` is part of
the PL state-patch contract. Nothing on the patch path actually wrote the field before. The
script fix stands on its own regardless — a missing optional field is not a reason to publish
a broken title. +5 `--self-test` blocks (13a–13e) with three new plan fixtures.

## [4.0.0] - 2026-07-31

The plugin was declared as `"name": "igrsoft"` while the repository had already become
`IGRSoft/company-workflow` — the plugin id was the last artifact carrying the vendor name as its
identity. This release renames the **plugin**, and only the plugin.

The word appeared in three distinct roles, and separating them is the whole substance of the
change. **Plugin identity** moves: every `igrsoft:<agent|skill>` invocation id, the
`marketplace.json` plugin entry, the `plugin.json` `Stop` hook matcher, the `Task(igrsoft:…)`
frontmatter grants, the bare-name resolution shim, and the Claude Code install cache path.
**Vendor identity** does not move: the author block (`IGRSoft`, `support@igrsoft.com`), the
`github.com/IGRSoft/…` URLs, the `com.igrsoft.*` bundle IDs in `/appstore-iap`, and the
marketplace name — which stays `igrsoft`, so the cache path becomes
`~/.claude/plugins/cache/igrsoft/company-workflow/<version>/` with only the second segment
changed, and the install key becomes `company-workflow@igrsoft`.

Most of the ~330 references were prose or ids, but four sites matched the literal string at
runtime and would have failed silently rather than loudly:

- `hooks/dv-screenshot-gate.sh` guards on exact equality (`!= "company-workflow:developer"`).
  Left stale, the DV screenshot gate would have no-opped on every run with no error.
- `skills/self-improvement/scripts/build-context-set.sh` maps agent refs to file paths via an
  awk field compare (`$1 == "company-workflow"`).
- `.claude-plugin/plugin.json`'s `Stop` matcher must track the plugin name or the PL/FN
  approval-gate push notification stops firing.
- `skills/worktask/scripts/publish-pl-issue.sh` carries four identical copies of the
  plugin-prefix leak regex that strips internal agent ids out of published GitHub issues; they
  are kept byte-for-byte in lockstep with the list in `skills/shared/compatible-plugins.md`.

### Breaking

- **`igrsoft:*` agent and skill ids no longer resolve.** There is no back-compat alias. The six
  sibling plugins (`apple-developer`, `system-developer`, `android-developer`,
  `frontend-developer`, `backend-developer`, `ai-engineer`) are updated in the same pass; merge
  this release first, since their docs reference `company-workflow:` ids.
- **`IGRSOFT_*` environment variables renamed to `COMPANY_WORKFLOW_*` with no fallback read** —
  `TEST_GATE`, `AR_REF_STRICT`, `PR_BODY_STRICT`, and `COMMENT_DENSITY_{MAX,WARN,MIN_LINES}`.
  Update shell profiles and CI jobs.
- **Stale installs must be reinstalled.** `~/.claude/plugins/cache/` and the
  `known_marketplaces.json` / `installed_plugins.json` indexes still key on the old plugin name
  until then.
- **`audit.jsonl` is not comparable across the boundary** — the `subject` field changes prefix,
  so pre- and post-rename audit trails cannot be diffed directly.

---

**Earlier releases are archived per major line: [CHANGELOG-3.x.md](CHANGELOG-3.x.md) (`3.0.0`–`3.43.0`), [CHANGELOG-2.x.md](CHANGELOG-2.x.md) (`2.0.0`), [CHANGELOG-1.x.md](CHANGELOG-1.x.md) (`1.0.0`).**
