# TicTacToe 4-Platform Stress Test — Findings and Improvement Plan

**Run date:** 2026-08-15 · **Duration:** ~5h wall-clock · **corpflow** 4.0.15
**Invocation:** `/worktask --secure --auto=[plan,decision,finalization] --platform all`
**Workspace:** `test/` (greenfield) · **Repo:** `ikorich/ttt-corpflow-test` (private)
**Outcome:** 11/11 stages completed · [PR #2](https://github.com/ikorich/ttt-corpflow-test/pull/2) open · all 6 acceptance criteria met

---

## 1. What this document is

The deliverable of this run was **not** the game. It was a live stress test of corpflow 4.0.15 plus
the igrsoft platform plugins, using a deliberately cross-platform product (iOS + Android + Web +
Dockerised leaderboard API) to force the pipeline through its hardest paths: `platform: all`
routing, TL fan-out across four DV streams, per-platform `build-test` delegation, worktree
isolation, the auto-decision delegate, the secure-pipeline SR/RE stages, and FN's commit/push/PR.

**42 findings**, 9 positive observations, and 5 corrections to the orchestrator's own analysis.

### Method note (read this before trusting anything below)

Findings were kept only where a **measurement** supported them. Five claims the orchestrator made
during the run were later falsified — by an agent pushing back, or by a direct check — and are
recorded in § 6 rather than deleted. Three findings originated from agents disputing the
orchestrator's framing. The single most important root cause (F-31R) was found by the stream that
never produced any product code.

---

## 2. What shipped

| Acceptance criterion | Status | Evidence |
|---|---|---|
| iOS simulator build | ✅ | Xcode project + shared scheme, 19 tests, 5 live simulator screenshots |
| Android debug APK | ✅ | 12.5 MB `app-debug.apk`, 29 tests, 4 live emulator screenshots |
| Web production build | ✅ | Vite 48 modules / 209 kB (65.7 kB gz), 105 tests, 5 live browser screenshots |
| Backend suite passes | ✅ | 113 tests (39 unit + 71 integration + 2 QA-added negatives) |
| Compose serves leaderboard e2e | ✅ | Orchestrator black-box curl: health, POST 201, REQ-15 tie-break on live data, AC-4 restart persistence |
| All clients share one API | ✅ | One web screenshot shows rows written by iOS, Android, the orchestrator's curl, and the web client itself |

**267 tests executed green.** 177 files, +18282/−2, 8 commits, four `--no-ff` stream merges.
SR0 `pass` (0 Critical, 0 High) · QA0 `GO` · RE0 `GO-WITH-RISKS` at 1.0.0 · ST0 `approve`.

---

## 3. Critical and high findings

### F-31R — a freshly spawned agent is assigned another stream's worktree *at spawn* ★ ROOT CAUSE
**Severity: critical.** Cost: 4 blocked dispatches, ~1h wall-clock, one stream that produced nothing
until fixed, and two incorrect diagnoses it provoked from the orchestrator.

```
expected (ledger, both fields):   .claude/worktrees/dv3-web    branch dv3-web
actual   (env + every tool call): .worktrees/dv0-service       branch dv0-service
```
Wrong from the **first tool call** — no `cd`, no `EnterWorktree`.

**Mechanism (evidenced, not assumed).** Two worktree parent directories were registered
simultaneously: `.worktrees/` (corpflow convention, containing exactly one entry, `dv0-service`)
and `.claude/worktrees/` (the only root `EnterWorktree` can reach). A resolver reconstructing a
worktree path *by convention* rather than reading `metadata.workspace_path` globs a prefix and lands
on another stream's directory. DV3 landed in `.worktrees/`'s single entry on all four attempts.

**Fix validated in-run.** After normalising all four worktrees under one parent, D0.0a passed for
the first time in five dispatches, and **both** independent pins (Bash and `Write`) resolved
correctly. DV3 then landed at the *repo root* rather than inside a sibling — exactly what a
by-convention resolver does when the prefix it used to glob is gone.

| Fix | Target |
|---|---|
| Spawn must take the pin from `tasks.<ID>.metadata.workspace_path` verbatim, never derive it | harness (the actual defect) |
| Assign every stage worktree under **one** parent, and make it `.claude/worktrees/` | `agents/team-lead.md` |
| Assert `git worktree list` contains exactly one parent prefix; fail loudly otherwise | `skills/worktask/scripts/dv-tree-preflight.sh` |
| Delete an emptied worktree parent (`git worktree move` leaves it behind) | `agents/team-lead.md` |

> This run's entire DV failure would have been caught in one second by the `dv-tree-preflight.sh`
> check above.

**Superseded by this finding:** the concurrency hypothesis and its "serialise DV streams"
recommendation (withdrawn, § 6), and the "dispatch was misrouted" claim (withdrawn, § 6).

---

### F-22 — corpflow's worktree location and the harness's `EnterWorktree` disagree
**Severity: high.** `agents/developer.md:261` instructs DV to use `EnterWorktree`; that tool only
manages worktrees under `.claude/worktrees/`, while TL0 and `metadata.workspace_path` assign
`.worktrees/`. DV therefore carries two mutually exclusive obligations — follow the agent
definition, or satisfy D0.0a.

**Two streams given identical instructions reached opposite conclusions**: DV3 blocked; DV1 used
`EnterWorktree` and relocated its tree, after which its diff landed at a path not matching its own
`workspace_path`, silently staling every guard keyed to that field. That is an ambiguous contract,
not an inconvenient one.

**Fix:** pick one location. Either corpflow adopts `.claude/worktrees/` (and `team-lead.md` stops
assigning `.worktrees/`), or `developer.md` stops naming `EnterWorktree` and prescribes
`git worktree add` at the assigned path. D0.0a must compare against whatever the sanctioned tool
actually produces.
**Files:** `agents/developer.md:261`, `agents/team-lead.md`, `skills/worktask/references/workspace-modes.md`

---

### F-23 — the Layer-2 safety net writes to a cwd-relative ledger, so it is inoperative inside a worktree
**Severity: high.** `.claude/hooks/state-merge.sh:125` hardcodes `STATE_FILE=".context/state.json"`
with no `WORKSPACE_ROOT`/`CLAUDE_PROJECT_DIR` resolution. The SubagentStop hook runs with cwd = the
subagent's worktree, where `.context/` does not exist (gitignored, never carried into a worktree).

Caught firing live inside DV1's tree, creating a **shadow** `.context/`:
```
.claude/worktrees/dv1-ios/.context/logs/state-merge.log
  [WARN] no artifact resolved (stage= artifact=) — no-op
```
It degraded safely this time. Had an artifact resolved, DV's completion patch would have merged
into a throwaway ledger inside a worktree.

`commands/worktask.md § Step 3b` calls this *"the Layer 2 safety net that patches state.json when
agents skip self-patching"* — and it is structurally unable to do that for **DV, the one stage where
worktree isolation is mandatory**. It fails via a warning line in a log nobody reads, in a directory
deleted with the worktree.

**Fix:** resolve `STATE_FILE` from `WORKSPACE_ROOT`/`CLAUDE_PROJECT_DIR`, or from
`git rev-parse --git-common-dir`'s parent when inside a linked worktree. Never bare-relative.
**File:** `.claude/hooks/state-merge.sh:125`

---

### F-37 — the canonical SR secrets scanner FAILS OPEN
**Severity: high.** `skills/security-review-process/scripts/scan-secrets.sh` crashes on all four
worktrees and **exits 0 — the documented "no Critical/High findings" code**:
```
scan-secrets: gitleaks not found — using built-in regex fallback
scripts/scan-secrets.sh: line 152: Trace/BPT trap: 5   grep -nEI -- "$regex" "$filepath"
(exit 0)
```
macOS BSD `grep` traps on one of the six built-in ERE patterns; the crash occurs inside a
`while read` process substitution whose pipeline ends `| cut … || true`, so the failure is swallowed.
ST0 located the precise line: **`:171`**, where `|| true` makes a crash indistinguishable from a
normal no-match exit 1.

A future SR following the skill's own instruction — *"invoke the script instead of reasoning through
these regexes manually"* — **reads a crashed scan as a clean bill of health.** This is a security
control that silently does not run.

The script already carries a comment noting that a previous `2> /dev/null` *"hid a dead pattern for
the whole life of the database-url regex"*. **The same failure class recurred one layer up, in the
exit code, after being documented once.**

**Fix:** (1) discriminate exit ≤1 (normal) from >1 (engine crash → abort loud, non-zero);
(2) fix or remove the BSD-incompatible pattern, or hard-require `gitleaks` on Darwin.
**File:** `skills/security-review-process/scripts/scan-secrets.sh:152,171`
*SR0 did not rely on it and scanned manually, so this run's secrets ruling stands.*

---

### F-40 — `git add` at stage N does not survive edits by stage N+1, and nothing re-checks
**Severity: high.** At FN entry, `dv0-service` showed:
```
MM README.md
AM api/test/integration/leaderboard.test.ts     →  81 insertions / 15 deletions NOT in the index
```
Those hunks were **DC0's entire § Security posture rewrite — this run's P0 fix — and QA0's two
SR-3 regression tests**. Committing the index as-is would have silently dropped both, shipping a
README carrying a security claim that SR0 and QA0 had each *measured* false. The stage dispatched
specifically to remove that claim would have had its work discarded at the last step, with no error
anywhere.

Every later stage that legitimately edits an earlier stage's file **un-stages it again**. DR-2
established that finished streams must be staged; nothing anticipated re-staling.

**Fix:** `fn-preflight.sh` must assert a clean index-vs-worktree state for every stream branch in
the payload and refuse to commit while unstaged modifications exist.
**Files:** `skills/worktask/scripts/fn-preflight.sh`, `agents/project-manager.md`
*Caught by RE0. The orchestrator had seen the `AM` marker and misread it — see § 6.*

---

### F-06 / F-07 — the branch-naming pair: a spec-compliant run silently loses its PR head name
**Severity: high (both).**

**F-06** — `commands/worktask.md § Step 3c` states `BRANCH_NAME_PRINT=1` "renames nothing and writes
**no audit row**", and calls previewing before the rename-mode run *"expected practice, not an
exception"*. It does write one:
```
branch_renamed noop reason=upstream_tracked branch=main
  target=feature/add-multiplatform-tictactoe-with-leaderboard-api
```

**F-07** — that row consumed the run's once-only naming window, so the single rename-mode
invocation 11 s later hit the `already_named` guard and emitted **both carriers empty**, discarding
the target it had derived. Following `§ Step 3c — which of the two names gets stamped` verbatim
therefore stamps `facts.branch` **empty**, and `§ Step 3c — an empty stamp is an honest outcome`
then instructs the orchestrator to accept that and let FN "push plainly" — on a repo whose `main`
tracks upstream.

**Fix:** (a) suppress audit writes under `BRANCH_NAME_PRINT`, matching the documented contract;
(b) the `already_named` arm must **re-emit the recorded target** rather than empty — a no-op on the
*rename* must not be a no-op on the *derivation*.
**Files:** `skills/worktask/scripts/branch-name.sh`, `skills/worktask/scripts/branch-lib.sh`,
`commands/worktask.md § Step 3c`

---

### F-25 (as amended) — the isolation guarantee is a point-in-time check on a mutable global
**Severity: high.** D0.0a validates the pin at stage entry, but writes happen minutes later, and
nothing requires re-validation between gate and write. DV0 put it exactly: *"My D0.0a preflight
passes and then goes stale seconds later."*

**What actually prevented corruption was the harness's write refusal, not corpflow.** Every stray
write was *refused, not misfiled*. Had writes merely been permitted, four streams would have
interleaved diffs onto each other's branches, surfacing only at FN.

Also recorded: DV0's recovery from a pin-steal required `ExitWorktree action:keep`; `action:remove`
**would have deleted a sibling stream's branch and work**. The documented recovery path is one
argument away from destroying another stream's output.

**Fix:** require pin re-verification immediately before every write batch (not once at D0.0a), and
document `action:keep` as the only safe pin-steal recovery.
**File:** `agents/developer.md § D0.0/D0.0a`, § recovery

---

## 4. The structural finding — ownership without a correction channel

**Four independent instances in one run.** Each time the correct action was known, the actor was
identified, and the ownership rule prevented it:

| # | Correction needed | Actor who could not act | Why |
|---|---|---|---|
| F-18 | Land AR's frozen contract into `base_ref` before DV cut worktrees | TL0 | Bash grant is `state-patch.sh` only |
| F-36 | Add the iOS test command DV1 discovered | DV1 | `README.md` is DV0's exclusive file |
| DR-2 | Stage finished streams' work for FN | *nobody* | DV done, FN not yet started |
| dc2 | Fix the same measured-false claim in `architecture-0.md` | DC0 | It is AR0's stage artifact |

F-18 and F-36 are the expensive ones. F-18 is a **hard deadlock** on any contract-first run: AR
produces a repo-path artifact but is not worktree-isolated and does not commit; TL owns sequencing
but cannot run git; DV could commit but runs *inside* the worktree missing the file; FN owns commits
but runs last. F-36 produced the run's **only P0** — DV1 knew the correct iOS test invocation
(including that plain `swift` on PATH is a broken swiftly shim), recorded it in its handoff, and it
never reached the README.

In all four cases the **orchestrator** — bound by `CLAUDE.md` to delegation-only — was the sole
actor able to close the gap.

> **The rule that prevents write conflicts also prevents corrections, and the pipeline has no way to
> distinguish the two.**

**Recommended fix (single structural change, not four patches):** add a `requests_correction`
handoff-frontmatter field so a later stage can flag a scoped, evidenced fix needed in an earlier
stage's file, plus an explicit **fan-in reconciliation step** where a nominated owner absorbs those
requests. ST0 independently proposed the same field (learnings proposal #3).
**Files:** `skills/agent-coordination/SKILL.md § File Ownership Boundaries`, `agents/team-lead.md`,
`agents/technical-lead.md`

---

## 5. Remaining findings

### Ledger integrity

| ID | Sev | Finding | File |
|---|---|---|---|
| F-42 | M-H | Ledger permanently records the **wrong worktree** for 2 of 4 streams: `DV2.worktree.path` = `.worktrees/dv0-service` (wrong stream, deleted dir); `DV3.worktree` holds **two key-shapes at once**. The handoff records where the agent *was*, not where it was *assigned*, so F-31R is baked into the permanent record. Nothing validates `worktree.path` against `metadata.workspace_path`. | `state-patch.sh`, `agents/developer.md` |
| F-35 | M-H | `facts.screenshots` capped at 5 and **last-writer-wins**. Root cause (found by ST0): `atomic_merge()` at `state-patch.sh:462` applies jq `'. * $p'`, which **replaces arrays wholesale**; `_STATE_BOUNDS_FILTER` has explicit handling for `facts.decisions` and `facts.dispatched_agents` but **none for `facts.screenshots`**. Final state: 5 rows, all iOS, zero Android/web, plus a `facts.screenshots_web` key DV3 invented to dodge the collision. | `state-patch.sh:462`, `skills/dv-screenshot-capture` |
| F-21 | H | No `blocked` status exists, so a stage that correctly **refuses to run** is stamped `completed` with only a separate `verdict: blocked` carrying the truth — and the loop's completion check never reads `verdict`. | `state-patch.sh`, `skills/worktask/SKILL.md` step 6.5 |
| F-34 | H | A **completed** stage with a written artifact and verdict still read `in_progress`: Layer 1 didn't fire, Layer 2 is cwd-broken (F-23), Layer 3 keys on a `Task()` return that never arrived because the agent reported by teammate message. | `skills/worktask/SKILL.md § Orchestrator Execution Loop` |
| F-28 | M-H | Two pin fields (`metadata.workspace_path`, `worktree.path`) express one fact, written by different actors, with no consistency check; a repair touched only one. | `state-patch.sh`, `handoff-protocol.md` |
| F-33 | M | The `worktree` object is optional and was populated for exactly one stream, so the F-28 consistency problem is latent everywhere and manifest only where someone filled it in. | `agents/developer.md` |

### Fail-open and silent defaults

| ID | Sev | Finding | File |
|---|---|---|---|
| F-14 | M | Complexity tier silently mislabels the published issue. `publish-pl-issue.sh:2459` matches `\((Low\|Medium\|…)\)` — **requiring parentheses**. PL0 wrote `— Critical tier.`, so extraction failed and `:2460` applied `TIER="moderate"` with no warning. Issue #1 carries `complexity:moderate` for a plan scored **46/50 critical**. | `publish-pl-issue.sh:2459-2460` |
| F-41 | L-M | `fn-preflight.sh` continuity check false-positives `diverged/cherry_pick` on a **multi-branch payload** — it assumes one stream branch fast-forwarded onto `main` and tests whether HEAD is an ancestor of main; a four-stream merge makes main an ancestor of HEAD instead. Multi-stream fan-out is a first-class feature, yet the preflight models only the single-branch shape. | `fn-preflight.sh` |
| F-12 | L | `cache-lint.sh` dies with a bare `jq: parse error` on unexpected input instead of a usage message. | `cache-lint.sh` |

### Build/test authority

| ID | Sev | Finding | File |
|---|---|---|---|
| F-29 | M-H | The `build-test` gate rejects the **whole invocation** rather than filtering requested **tasks**, so DV asking only for `assembleDebug` or `--build-only` is refused a build it is entitled to. DV2 could not re-verify its APK; DV3 could not run `vite build`; both fell back to direct toolchain calls — precisely what `developer.md` forbids. **Confirmed on two plugins.** Correctly did *not* fire for QA, so the authority model itself is sound. | `*/skills/build-test` shared gate |
| F-39 | M | The Android build requires `ANDROID_HOME`, which no stage sets and no artifact declares; DV2's shell had it pre-set, hiding the dependency until QA hit an `sdk.dir` error that reads as a broken project. | `android-developer:build-test` |

### Decisions made without execution

| ID | Sev | Finding |
|---|---|---|
| F-27 | M-H | "Binding" decisions are stamped without ever being executed. AR decision **ad8** was passed to DV as non-negotiable, yet two of three clauses were wrong in ways one `./gradlew` run would have exposed. Same pattern: F-04 (plan targeting an API level with no system image) and **contract-1** (a frozen OpenAPI whose own `PlayerName` example `Grace H.` is rejected by its own `pattern`). AR and the auto-decision delegate *decide* toolchain and contract details but never *execute* — and the pipeline forbids them from doing so. **Cheap fixes:** lint the OpenAPI document's own examples against its own schemas before freezing; cross-check declared SDK levels against what is installed; mark toolchain-version clauses `provisional` rather than `binding`. |
| F-13 | M-H | PL0 wrote a risk row asserting a **"verified"** tooling bug that does not reproduce (`handoff-harness.sh` returns `ok: stage=PL`, exit 0; the source extracts the fence with `awk` *before* invoking `yq` — exactly the behaviour claimed missing). The row instructs review stages to **discount a real lint failure as a tool fault**. A fabricated-but-plausible tooling excuse in a durable artifact is a review-integrity hazard. **Fix:** require a risk row claiming "verified" to cite the command run and its observed output. |

### Lint and validation calibration

| ID | Sev | Finding |
|---|---|---|
| F-11 | M | `section-lint.sh`'s flat 1000-char cap is not tier-aware. Every anchor in a critical-tier plan is over it (`## requirements` 2396, `## acceptance-criteria` 2913, `## risks` 4428) — passing would require under-specifying the plan the tier exists to force. |
| F-10 | L-M | PL frontmatter is 410 tokens against a 200 budget; warn-only, exit 0, so it will always be exceeded and never noticed. |
| F-15 | L | Published issue title truncated mid-word (`…a global leaderbo`), no ellipsis — `branch-name.sh` already solves this correctly by dropping the trailing *partial* segment. |

### Audit volume

| ID | Sev | Finding |
|---|---|---|
| F-01 | M | **80% of the audit trail is redundant.** Final: 2837 rows, 2265 `advisory:true`. Two stacked bugs: every installed dev plugin registers its own hook copy (**6×**), and each copy fires **twice** on subagent-stop (**12×** total for those events). `dedupe_key` is identical across all copies and consulted by none. Every reader — `refine-branch-target.sh`, `publish-pl-issue.sh`, the retrospective — pays 5× to parse it. **Fix:** claim a `dedupe_key` before appending, or register the hook once at marketplace level. |

### Environment and plugin lifecycle

| ID | Sev | Finding |
|---|---|---|
| F-03 | M | Plugin enablement is unreachable from inside a session — both the `settings.json` edit and the `claude plugin` CLI are refused, so an orchestrator cannot satisfy a plugin dependency it discovers mid-run. (Hot-load itself works: skills and agents loaded without restart.) |
| F-16 | M | A hot-loaded plugin's **hooks do not register** mid-session — `android-developer` was absent from the audit-hook actor list all run. Enabling mid-session yields a half-live plugin with no warning. |
| F-38 | M | The SR agent's tool grants, its agent definition, and the session's standing configuration disagree on whether it may delegate. SR0 resolved it conservatively and **disclosed the trade** — four platforms were reviewed by a generalist, visible only because SR was honest about it. |
| F-19 | M | Stage worktrees were placed *inside* the repo with no ignore-guard; `.gitignore` carried only `.context/`. Mitigated in-run via `.git/info/exclude` (common git dir, applies to all worktrees, never committed). |
| F-05 | M | `avdmanager` (cmdline-tools 22.0) reports zero targets/images despite valid `package.xml`; AVD had to be created by hand. Any skill scripting `avdmanager` to provision a DV-evidence emulator will fail on a current-tools machine. |
| F-02 | L | `git-conventions.md` mandates an `#<issue>` prefix on every commit, but the bootstrap commit that DV's mandatory worktree isolation requires must exist *before* any issue can be created. The spec mandates something unsatisfiable at t=0. |
| F-08 | L-M | The integration-branch *refusal* never evaluates — the upstream-tracked *no-op* fires first. The stronger guard should be tested first. |
| F-09 | L | `branch-name.sh` audit rows are hardcoded to `actor: "product-manager"` even when the orchestrator invokes the script directly at Step 3c, before any PM dispatch. |
| F-17 | H | AR's non-`.context/` artifacts cannot reach DV's isolated worktree (untracked in the shared checkout; `git worktree add` checks out a committed ref). See § 4 for the ownership half. **Fix:** have `dv-tree-preflight.sh` assert every path referenced by `architecture-N.md` resolves inside the worktree. |
| F-20/F-26/F-30/F-32 | — | Symptoms of F-31R; retained in the run log for the evidence trail, superseded here. |

---

## 6. Corrections to the orchestrator's own analysis

Recorded because a findings report's credibility depends on **how** claims survived, not just which.

| Claim | Status | How it was caught |
|---|---|---|
| "Three DV streams exited silently; `in_progress` means both running and dead" (F-24) | **Withdrawn** | Streams were still working. `ListAgents` is not a liveness oracle — it showed one row while two streams were writing files. The orchestrator also inspected `.worktrees/` while live work was under `.claude/worktrees/`, failing to apply F-22 which it had just documented. |
| "A stage dispatch was delivered to the wrong agent" (F-31) | **Withdrawn** | The agent corrected itself: it *was* the agent spawned; it had inferred its identity from its working directory — the very thing that was wrong. Replaced by F-31R. |
| "Concurrency causes pin drift; serialise DV streams" (F-25 fix #4) | **Withdrawn** | DV3 ran with no concurrency and was still mispinned. The pin was never drifting *within* a session; successive spawns were each mispinned. |
| "The parent `ai-agents/.context/` accumulates hook noise from this run" (F-01) | **Struck** | That `audit.jsonl` was last modified 29 Jul — untouched by this run. A pre-existing artifact mistaken for live leakage. |
| "The P0 README fix may have been dropped from the commit" | **Self-caught** | A literal grep failed on markdown emphasis (`*not*`) while the *old* wording matched — as a quotation inside the correction. Both signals pointed the wrong way. Prose verification needs semantic anchors, not remembered sentences. |

**A recurring orchestrator failure mode worth naming:** three times, a stale snapshot was handed to
an agent as standing fact (`.context/images/` is empty; no other agent is running; start numbering
at `dv-09`). In a parallel fan-out **an orchestrator's world-model is stale by the time the dispatch
lands.** Briefs should timestamp their facts and instruct re-verification rather than assert current
state.

---

## 7. What worked — and worked well

The agent layer substantially outperformed the plumbing it ran on.

1. **Five refusals-to-corrupt across four agents.** DV3 blocked three times rather than write into a
   sibling's tree — once explicitly reasoning that the target worktree "has already produced real
   work (4 screenshots at 19:16–19:17)". `backend-developer:node-developer`, mispinned into DV1's
   tree, wrote zero files and escalated. DV3 found that `Bash: touch` into the wrong tree *would*
   succeed and **declined to use it**, because it would leave every git/build call aimed elsewhere.
   **In every case the safe outcome came from agent judgement, not from a mechanism.**
2. **The stage that "failed" four times fixed the pipeline.** DV3 wrote no product code across four
   dispatches, yet falsified the concurrency hypothesis, retracted its own incorrect claim,
   identified the two-parent mechanism, proposed the fix, verified it, and caught the residual
   empty-directory hole. Judging stage success by artifacts produced would have scored it zero.
3. **The escalation guard worked as designed.** The Fable auto-decision delegate tested "no auth on
   writes" against the guard and argued it was documented scope rather than posture-weakening —
   *"a shared secret embedded in three distributable clients is a placebo, not a control"* — and
   explicitly reserved the final call for SR. **SR0 upheld it five hours and four streams later.**
4. **Measurement beat assertion, repeatedly.** On the rate limiter: README asserted per-IP works for
   LAN callers → DR0 suspected Docker NAT → SR0 *measured* one global bucket → QA0 *reproduced* it
   independently with fresh markers. Only the stages that measured got it right, and DC0 then
   documented the truth including why the obvious fix (`trustProxy`) is worse.
5. **DR0 refused to pass four self-reporting-green streams**, on one narrowly-scoped P0, with
   `fail_scope` bounding the blast radius — and verified minimax identity across three languages by
   reading the code rather than trusting three claims.
6. **DV2 found a self-contradiction in the frozen contract** (`Grace H.` fails its own pattern),
   verified it independently of its implementation, did **not** edit the artifact it does not own,
   and pinned the behaviour with a named test so AR's ruling would be recorded either way.
7. **DV2 verified rather than re-implemented** work already in its tree, reasoning that
   re-implementing evidenced code "to claim authorship would have destroyed the only build this
   stream has" — and disclosed, unprompted, a stray probe of its own that had landed in a sibling's
   tree, with confirmation it was removed.
8. **DV3 diagnosed a defect in its own instrument.** A board showed a mark it had not clicked; it
   instrumented the page with a capturing click listener, replayed deterministically, and concluded
   the fault was stale uid→node resolution in its **browser-automation layer**, not the app —
   documenting it so DR "shouldn't have to re-derive it".
9. **QA0 distinguished evidence it executed from evidence it accepted**, ran a fresh live
   cross-client tie-break check, and kept its own captures out of the DV manifest.

---

## 8. Improvement plan, prioritised

### P0 — correctness of isolation (do these first)

1. **Harness:** spawn must take the worktree pin from `metadata.workspace_path` verbatim. *(F-31R)*
2. `agents/team-lead.md` — assign every stage worktree under a **single** parent, `.claude/worktrees/<stream>`; never leave two registered, even transiently; delete an emptied parent. *(F-31R, F-19, F-22)*
3. `skills/worktask/scripts/dv-tree-preflight.sh` — assert exactly one worktree-parent prefix exists; fail loudly. **One second of checking would have prevented this run's dominant failure.** *(F-31R)*
4. `agents/developer.md` — resolve the `EnterWorktree` vs `.worktrees/` contradiction; require pin re-verification before every write batch; document `ExitWorktree action:keep` as the only safe pin-steal recovery. *(F-22, F-25)*

### P1 — fail-open and silent-loss defects

5. `skills/security-review-process/scripts/scan-secrets.sh:171` — discriminate exit ≤1 from >1; never exit 0 on an engine crash. *(F-37)*
6. `.claude/hooks/state-merge.sh:125` — resolve `STATE_FILE` from `WORKSPACE_ROOT`/git-common-dir, never bare-relative. *(F-23)*
7. `skills/worktask/scripts/fn-preflight.sh` — refuse to commit while the payload has unstaged modifications. *(F-40)*
8. `skills/worktask/scripts/publish-pl-issue.sh:2459-2460` — match the tier word without requiring parentheses; audit a `warn` row when the default is applied. *(F-14)*
9. `skills/worktask/scripts/branch-lib.sh` — the `already_named` arm must re-emit the recorded target; suppress audit writes under `BRANCH_NAME_PRINT`. *(F-06, F-07)*

### P2 — structural

10. `skills/agent-coordination/SKILL.md` — add a `requests_correction` handoff field plus a fan-in reconciliation step. **One change closes four observed failures.** *(§ 4)*
11. `skills/worktask/scripts/state-patch.sh` — add `blocked` status; make the loop's completion check read `verdict`; give `facts.screenshots` explicit array-merge handling beside `facts.decisions`; derive `worktree.path` from `metadata.workspace_path` and assert agreement. *(F-21, F-34, F-35, F-42, F-28)*
12. `*/skills/build-test` — filter requested tasks rather than rejecting the invocation. *(F-29)*
13. `agents/software-architector.md` + `commands/worktask.md § Auto-decision recording contract` — validate an OpenAPI document's own examples against its own schemas before freezing; cross-check SDK levels against installed ones; mark toolchain clauses `provisional`. *(F-27)*
14. `agents/product-manager.md` — a risk row claiming "verified" must cite the command and its observed output. *(F-13)*
15. `hooks/audit-*.sh` — claim `dedupe_key` before appending, or register once at marketplace level. *(F-01)*

### P3 — calibration and polish

16. `section-lint.sh` tier-aware caps *(F-11)* · `handoff-harness.sh` frontmatter budget *(F-10)* ·
    `publish-pl-issue.sh` title truncation on word boundaries *(F-15)* ·
    `fn-preflight.sh` multi-branch continuity *(F-41)* · `cache-lint.sh` input validation *(F-12)* ·
    `branch-lib.sh` audit actor attribution *(F-09)* · guard-ladder ordering *(F-08)* ·
    `git-conventions.md` bootstrap-commit shape *(F-02)* ·
    `android-developer:build-test` to export/verify `ANDROID_HOME` *(F-39)* ·
    document that mid-session plugin enablement does not register hooks *(F-16)*.

---

## 9. Orchestrator interventions

Six, each logged at the time, each because no pipeline actor could act:

| # | Action | Reason |
|---|---|---|
| 1 | Recovered and hand-stamped `facts.branch` | F-07 emitted both carriers empty; the target was recoverable from the audit row |
| 2 | Committed AR's contract to `base_ref` (`4bd041b`) | F-18 deadlock — TL prescribed it and could not execute it |
| 3 | Absolute paths + `--state` throughout | F-20/F-25 — orchestrator shell captured by a stage worktree |
| 4 | Wrote `.git/info/exclude` in the common git dir | F-26 — `.gitignore` has no owner; would have committed build caches |
| 5 | Repaired `tasks.DV3.worktree.path` | F-28 — two pin fields disagreed |
| 6 | Staged DV1 and DV3 (177 files total) | DR-2 — both complete, DR0 forbade re-dispatch, nothing else stages finished work |

Intervention #7 was **declined deliberately**: DC0's `dc2` (the same false claim left standing in
`architecture-0.md`). Four instances already established the generalisation; a fifth rescue would
have obscured the fact that the pipeline cannot self-correct here.

---

## 10. Cost note

A four-platform, 11-stage, full-auto run with four parallel DV streams, three DV re-dispatches, and
one remediation cycle. Benchmark precedent for a single 10-stage run is ≈ $17; this substantially
exceeded that. The dominant avoidable cost was **F-31R** — 4 blocked dispatches and ~1 hour of
wall-clock, all of which the one-line `dv-tree-preflight.sh` assertion in P0-3 would have prevented.

---

*Findings compiled by the orchestrator from `.context/` artifacts, `audit.jsonl` (2837 rows),
`.context/errors/developer.md`, ST0's `learnings.md`, and direct measurement. No plugin file was
modified — every item above is a proposal.*
