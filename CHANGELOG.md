# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
