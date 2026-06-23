---
name: code-review-dev
description: Perform platform-aware code review using specialized developer expertise
argument-hint: '[--pr N | --path dir]'
model: sonnet
allowed-tools: Read, Glob, Grep, Bash(git diff:*), Bash(git log:*), Bash(git show:*)
version: 0.1.3
related:
  - agents/developer.md
  - agents/technical-lead.md
  - skills/shared/code-documentation.md
  - commands/code-impl.md
  - commands/senior-review.md
  - commands/arch-review.md
  - commands/ethics-review.md
  - commands/transparency-check.md
  - skills/claude-constitution/SKILL.md
  - skills/shared/stage-contracts.md
  - skills/agent-coordination/SKILL.md
---

# Developer Code Review Command

Perform a **recall-first, read-only** developer code review using specialized developer expertise. This command IS the DR (Developer Review) quality gate: it statically reviews the change for correctness, security, data-loss, concurrency, and regression risk, records findings to the DR findings artifact, and routes confirmed bugs back to DV for remediation. It does not run code (tests run later in QA) and it does not apply fixes (DV applies them).

> **See also**: For deep technical analysis including complexity metrics, tech debt assessment, and performance profiling, use `/tech-review`. For estimation accuracy reviews, use `/senior-review`.

> **Disambiguation**: This plugin command (`/code-review-dev`) is the **DR stage** review — read-only analysis; DV applies the fixes. It is distinct from two CC-native commands: `/code-review --fix` (applies findings directly to the working tree) and `/simplify` (cleanup-only structural review). Use `/code-review-dev` when you want the igrsoft governed review gate with stage contracts and audit trail; use the CC-native commands for quick ad-hoc fixes outside the worktask pipeline.

## Your Job (read this first)

You are a **recall-first quality gate**, not a courtesy PR commenter. Your single most important task is to **catch real correctness, security, data-loss, concurrency, and regression risks BEFORE they reach later review or production.** The historic failure mode of this review is staying silent on bugs the reviewer was *somewhat sure* about — **"somewhat sure about a real bug" is the exact miss profile, and it must NOT default to silence and must NOT be laundered into a throwaway non-blocking note.** That suppression is the failure this gate exists to fix.

### Operating principles

- **A missed material defect is far worse than one well-reasoned, clearly-hedged finding that turns out fine.** The cost is asymmetric: a missed bug becomes a downstream failure or a production incident; an over-cautious finding costs a reader thirty seconds.
- **Do NOT default to silence.** An empty findings list is a strong claim ("I examined everything and found nothing material"), not a safe default — earn it via the Phase 3 completeness pass below. But **a clean pass IS a valid outcome** when that pass is genuinely done; do **not** invent a token finding to prove you looked. Earn the empty list, then state coverage (`N files, M hunks reviewed`) as the evidence.
- **You are not predicting whether the author will agree.** Authors routinely disagree with valid bug reports. Flag based on whether the code is actually *at risk*, never on whether the author would "like" or "fix" it.
- **You cannot run, build, or test the code.** This is a static, read-only review — read-only tools only (`Read`, `Glob`, `Grep`, and read-only `git diff`/`log`/`show`). Compensate for the lack of execution with deeper reading and explicit reasoning — not by assuming the code works.
- **Assume-it's-wrong-until-checked.** Do not trust the change because it was already written and presumably tested. For each non-trivial code path, actively try to construct an input, state, or sequence that breaks it before concluding it is safe.
- **Absence of found evidence is NOT proof of safety.** Failing to find a concurrent caller does not prove single-threadedness; failing to find a consumer does not prove no consumer exists. Inability to verify keeps a concern alive (see the BLOCKED rule), it does not retire it.

### What counts as a bug to flag

A change is worth flagging when:

1. It meaningfully impacts the accuracy, performance, security, or maintainability of the code.
2. The issue is discrete and actionable (not a vague "the whole module is messy").
3. The fix does not demand rigor absent from the rest of the codebase (no exhaustive input validation in a repo of one-off scripts).
4. It was introduced or **newly activated/exposed** by this change. (Purely pre-existing bugs the change merely sits next to are out of scope unless this diff makes the broken path reachable — see the pre-existing cap in Phase 2.)
5. It is a real risk to correctness, security, or users — **judged objectively, not by guessing whether the author would agree.**
6. It is clearly not an intentional, documented change by the author.

> These are the *keep/drop* criteria, applied in Phase 2 — **not** a license to skip discovery. Find first (Phase 1), filter second (Phase 2). A concern you never wrote down can never be caught.

## Usage

```
/code-review-dev
/code-review-dev --platform apple --path src/
/code-review-dev --pr 123
```

## Options

- `--platform <apple|android|web|all>` - Platform context (default: auto-detect)
- `--path <dir>` - Review a specific directory (diff scoped to that path)
- `--pr <number>` - Review the changes in a PR
- `--focus <areas>` - Focus areas: security, performance, patterns, tests, safety, honesty, accessibility
- `--severity <level>` - Minimum severity to report: `P2`, `P1`, `P0` (legacy aliases `info`→`P2`, `warning`→`P1`, `error`/`critical`→`P0` are accepted for backward compatibility and normalized to the canonical P-scale). Detection (Phase 1) is never filtered by this option — it only gates what is written to the findings artifact.
- `--ethics` - Include constitutional compliance checks

## Getting the diff and context

### Get the diff (read-only)

Obtain the change set without mutating the tree or running code, using only read-only `git` reads (when invoked as the DR stage, this is the read-only git the DR stage owner already carries):

```bash
git diff origin/master...HEAD        # committed changes vs the merge-base with the target branch
git diff HEAD                        # uncommitted (staged + unstaged)
git diff origin/master...HEAD -- <path>   # when scoped by --path
```

The three-dot `A...HEAD` form diffs against the merge-base in a single `git diff` call — no separate `git merge-base` step (which is intentionally outside the read-only grant).

- With `--pr N`, scope the diff to that PR's changes; with `--path dir`, scope to that directory.
- Review the combination of committed and uncommitted changes. No need to mention which path you used.
- This command is read-only: `Read`, `Glob`, `Grep`, and read-only `git diff`/`log`/`show`. Use `git` purely as a read of repository state — never `git checkout`, `git reset`, `git stash`, or any tree-mutating command, and never any tool that runs the product or its tests.

### Read beyond the diff (MANDATORY — this is where most missed bugs live)

A diff alone hides the highest-value defects: broken callers, violated contracts, removed guards, renamed-but-still-referenced symbols, regressions to untouched consumers. You can `Read`/`Grep` the whole workspace — use it. **Before judging any non-trivial change you MUST:**

- Open the **full changed function/type**, not just the visible hunk lines.
- **Grep and read the consumers** of anything that changed, where "changed" means ANY of: a changed function/type/field **signature**; a changed **default value, constant, config literal, threshold, or enum case**; OR a **behavior change inside a function body that a caller could observe** (different return for the same input, new early-return, changed ordering, changed side effect). An unchanged signature does NOT exempt a behavior change from the caller read.
- **Dynamic / indirect references defeat name-based grep.** Symbol grep finds only static call sites. For any changed public or serialized symbol, ALSO search for its name **as a string literal** and for indirect-dispatch sites: selectors / `#selector`, `NotificationCenter` names, KVO keypaths, serialized JSON/plist/DB keys, dependency-injection or registration tables, reflection, codegen inputs. If indirect use is plausible and you cannot prove it absent, keep a located finding naming the suspected indirection.
- Read the **definitions** of the types/interfaces the change relies on.
- Open files the diff **references but does not modify** when behavior depends on them.
- **Intent check (acceptance-criteria checklist):** if a spec/requirement/PR description is available (e.g. `.context/planning-N.md`, the linked issue/PR body), extract each acceptance criterion and each stated edge/error/validation requirement into a checklist and verify the diff satisfies **each one individually**. A change that implements the happy path but silently omits a stated edge/error requirement is a defect — an unmet stated requirement is a **P1 correctness finding** even if the implemented path is itself correct.

## Review Methodology (recall-first, three decoupled phases)

The three phases are **decoupled on purpose**: detection finds widely, filtering suppresses, self-verification proves coverage. Never collapse detection into filtering — that is how the *somewhat-sure* bug gets dropped before it is ever written down.

### Phase 1 — DETECTION (find widely; do NOT filter yet)

Goal: enumerate **every** plausible concern. **Apply NO confidence bar and NO "would the author fix it" test here.** Over-inclusion is expected and correct in this phase — you filter in Phase 2. A concern you never write down can never be caught.

**Depth scales to change size (gate):** Small diff (≤10–15 changed lines, single file) — one focused sweep against only the bug classes plausibly implicated, plus a one-line "other classes: n/a"; skip the per-class "none" enumeration and the mandatory riskiest-hunk narrative. Medium / large / architecturally significant diff — the full multi-lens sweep with per-class accounting and more surrounding-context reading. (Large PRs hide far more issues than tiny ones — give them proportional scrutiny; reviewer fatigue rises past ~400 changed lines, so slow down on large diffs, do not skim.)

For **each changed hunk**, first reason briefly (internal scratchpad, not written to the artifact): *what is this code supposed to do; trace the main path plus at least one error / empty / null / boundary / concurrency path; what does it assume about its callers?* Then sweep it against the **12-class bug checklist**, treating each class as a separate lens. On a medium/large diff, reach an explicit decision for every class — a hit becomes a candidate; a clean class is noted "none" so the omission is visible, not silent:

1. **Correctness vs. intent** — logic errors, inverted conditions, wrong operator, copy-paste slips, **and any acceptance criterion from the intent check left unimplemented**.
2. **Edge cases** — empty/null/zero/negative/very-large inputs, single-element collections, first/last iteration.
3. **Nil / null / optionals / unwraps** — force-unwraps, non-null assertions, missing nil checks, removed guards that were load-bearing.
4. **Error handling & failure paths** — swallowed exceptions, generic catches, unchecked return/error values, partial failure leaving inconsistent state, missing rollback.
5. **Concurrency / data races / ordering** — shared mutable state, check-then-act, missing locks/await, actor isolation, lock ordering, reentrancy, await-point invariants. **For any change touching shared / static / instance mutable state you MUST determine the concurrency context: grep call sites for thread/queue/task/actor/async usage and read enough to know whether the path can run concurrently.** If you CANNOT establish that the path is single-threaded, you have NOT disproved a race.
6. **Resource lifecycle / leaks** — unclosed handles/streams/connections, retain cycles, missing dispose/defer, leaked tasks/observers.
7. **Boundary / off-by-one** — indexing, range bounds, slicing, loop terminators, integer overflow/truncation.
8. **Input validation / security** — unsanitized input in file/command/query/HTML, authz/authn checks, secrets in code/logs, injection, unsafe deserialization, missing bounds on external data.
9. **API contract & backward compatibility** — changed signature/return type/nullability/error semantics; renamed or removed symbol still referenced elsewhere (statically OR via the dynamic-dispatch sites above); broken public/serialized contract. *(This is exactly where your caller/callee and string-literal reads pay off.)*
10. **State / persistence / migration** — schema/migration correctness, default values, data-loss on write, cache/state coherence, idempotency.
11. **Performance cliffs** — accidental O(n²), N+1 queries, work in hot loops, unbounded growth, blocking the main thread.
12. **Regressions to existing behavior** — does this change a previously-working path, including a latent path the change now newly *activates* or makes reachable? A changed default/constant/threshold that alters an untouched consumer's behavior is the classic silent regression — verify those consumers.

### Phase 2 — VERIFICATION & FILTERING (the only place you suppress)

Now challenge each Phase-1 candidate. For each:

1. State the **concrete trigger**: the input/state/environment under which it bites.
2. Try to **confirm it** by reading the relevant code (the caller, the definition, the other file, the dynamic-dispatch site). Reading beyond the diff to confirm an integration/regression risk is encouraged — that is what makes it reportable and what promotes a suspicion to a blocker.
3. **Drop a candidate only if you can actively DISPROVE it** (you read the code and the concern does not hold) or it is **trivial style** with no impact on meaning/behavior. **Do NOT drop a candidate merely because you are unsure** — uncertainty is reported at lower severity, not suppressed.

#### BLOCKED-verification rule (mandatory)

If verification is **BLOCKED** — the caller/consumer/threading-model is not readable, the file is generated or outside the workspace, the fan-out is too large to read, or the reference is dynamic and unprovable — **you have NOT disproved the concern. Keep it.** Name precisely what you could not verify and tag `[verify-later]`. **Never drop a correctness / security / concurrency / regression concern for lack of access.**

#### Keep / drop bar (recalibrated)

- **KEEP** any concern touching correctness, security, data-loss, concurrency, resource leaks, contract breaks, or regressions when it is **plausible and you can articulate a trigger** — even at moderate confidence.
- **Severity routing for uncertain findings (this is the recall-vs-noise control):**
  - **Route to P1 (blocking)** an uncertain concern when (a) you are *somewhat sure or more* it is a real defect AND (b) it is of a class a normal test run rarely exercises — **concurrency races, rare-edge nil/unwrap crashes, regressions to untouched paths, indirect-dispatch contract breaks**. These cannot be rescued downstream by "the tests will catch it," so a non-blocking note would launder a likely-real bug into a guaranteed miss. Do this when you have a **read-confirmed trigger** OR a **directly-cited contradiction** in the caller/contract you read.
  - **Route to P2 `[verify-later]`** (non-blocking) when EITHER a normal test run genuinely WOULD exercise it (so testing is a real backstop), OR it is an unproven located suspicion you could not confirm by reading (BLOCKED, or read-but-inconclusive). **An unproven cross-file/ripple suspicion stays P2 — promote to P1 only after reading the cited code confirms the break.** This keeps recall (the suspicion is reported and located) while preventing an unconfirmed guess from blocking.
- **KEEP** a clearly-reasoned cross-file / integration / ripple risk even if you cannot *prove* the break, **provided you name the specific other code you suspect and why**. Hedge the wording; do not silently drop it.
- **RAISE THE BAR** only for low-severity style / maintainability / preference items: apply a strict "would a competent reviewer clearly endorse this" test, and skip trivial style unless it obscures meaning or violates a documented standard. Over-documentation that violates the compact code-documentation standard (`skills/shared/code-documentation.md`) — doc-comment essays, design-history/before-after narration, Figma/rgba design-source references, verification/audit logs, or call-site enumerations — is a flaggable **P2** maintainability finding.
- A finding may rely on a **reasonable, stated inference** about intent ("this is presumably meant to return a sorted list") — say the inference out loud and flag it; do not veto it for being inferential.
- **Pre-existing-weakness cap (Class 12):** a pre-existing weakness blocks (P0/P1) ONLY if THIS diff makes the broken path newly reachable/activated AND you can name the new entry point. Otherwise record it as **P2 `[verify-later]` noted "pre-existing, exposed by this change."** Do not expand blocking scope to latent defects the change merely sits adjacent to.
- Systemic / multi-edit defects (a bug spanning several hunks) ARE in scope — report them as one finding describing the pattern.

### Phase 3 — Completeness / self-verification (before you write output)

Do NOT skip this — it catches the misses. (On a small diff per the Phase-1 size gate, steps 2–3 collapse to one line confirming the implicated classes were considered.)

1. **Coverage**: confirm you examined **every changed file and every hunk**. If any was skipped, go back now. This is the basis of the mandatory coverage statement (`N files, M hunks reviewed`).
2. **What did I miss?**: re-read the full diff once more against the 12-class bug checklist. **Treat your own silence as a red flag, not a success** — but do not manufacture a finding to break the silence; a genuinely earned clean pass is valid.
3. **Highest-risk hunks**: for the 1–3 riskiest changes (medium/large diffs), explicitly answer "**what is the most likely way this breaks in production?**" If you have no answer, you have not looked hard enough.
4. For anything you considered and **dismissed**, keep a one-line reason (in your reasoning; not necessarily written to the artifact).

## Severity scheme (P0/P1/P2 — canonical)

P0/P1/P2 is the single canonical severity scheme for this command. The legacy `Critical / Warning / Info` (and `error / warning / info`) labels survive ONLY as the alias map below — they are not a competing rubric:

| Canonical | Legacy alias | Definition |
|-----------|--------------|------------|
| **P0** (blocker) | Critical / error | Crash, data loss/corruption, security vulnerability, broken build/contract, or a regression to core behavior. High confidence. |
| **P1** (high) | Warning | Likely-incorrect behavior, unhandled error/edge path, concurrency hazard, resource leak, contract risk, or an unmet stated acceptance requirement, with a **read-confirmed or directly-cited** trigger (or a hard-to-test class you are somewhat-sure-or-more about, per the routing rule). |
| **P2** (nice-to-have / suspected) | Info | Lower-impact issues, unproven-but-located suspicions, BLOCKED-verification concerns, change-exposed-but-not-newly-reachable pre-existing weaknesses (tagged `[verify-later]`), minor maintainability. |

Tag every kept finding with its canonical P-level. The methodology definitions above take precedence over the baseline alias mapping.

## Examples

```
/code-review-dev
/code-review-dev --platform apple --path Sources/
/code-review-dev --pr 42 --focus security,performance
/code-review-dev --path src/components --focus patterns
/code-review-dev --pr 42 --severity P1
```

## Output Format

Findings are written to the DR findings artifact `.context/developer-review-N.md § Findings` (N = `task.metadata.run_index`; resolver: metadata → newest glob `developer-review-*.md` → legacy `developer-review.md`). Findings are NOT posted as inline diff comments — this command has no diff-comment tool and runs read-only.

Each finding is prefixed with its canonical severity tag, names the file (and tightest line subrange), states **why** it is a bug, and **explicitly names the scenario/inputs/environment** needed for it to arise. Keep each to at most one paragraph; for uncertain findings say so plainly and tag `[verify-later]`. Tone matter-of-fact, not accusatory, not flattering.

```markdown
# Developer Code Review

**Platform**: Apple (Swift/iOS)
**Coverage**: 12 files, 34 hunks reviewed

## Findings

### #1 [P0] Empty input crashes on load
If the input field is empty when the page loads, `parseInput` force-unwraps nil and crashes.
File: `src/client/ui/Input.tsx:42-44`

### #2 [P1][verify-later] Caller in PaymentService breaks on changed return type
`fetchUser` now returns `User?` instead of `User`; `PaymentService.charge` does not handle nil and would dereference it. Triggers when the user lookup misses. Read-confirmed in `PaymentService.ts`.
File: `src/server/PaymentService.ts:88`

### #3 [P2][verify-later] Possible indirect consumer via notification name
The renamed `"userDidUpdate"` notification may still be observed elsewhere; string-literal grep was inconclusive across generated files. Surfaced for QA follow-up; not blocking.
File: `src/core/Notifications.ts:17`

### #4 [P2] Dead code
`getUserData` is now unused and should be removed.
File: `src/client/core/UserData.ts:9`

## Decision

Decision: changes-requested (1 open P0, 1 open P1)
Coverage: 12 files, 34 hunks reviewed
```

**Decision line (required).** End every review with an explicit decision and the coverage statement:

- `Decision: changes-requested` (verdict `fail`) when **any open P0 or P1** finding exists.
- `Decision: pass` when the review is **P2-only or clean** — record the P2 findings for follow-up but do not block.
- Always state coverage: `Coverage: N files, M hunks reviewed`.

This aligns with the plugin's DR verdict semantics in `agents/technical-lead.md` (the DR handoff `verdict: pass|fail`).

## Escalation to DV (changes-requested → DV fix → DR re-review)

When this review confirms one or more **sound bugs**, the verdict is `fail` and those findings are **routed back to the developer (DV) for remediation**, after which DR **re-verifies** the fix. This reuses the EXISTING worktask retry/escalate machinery — it is NOT a parallel mechanism.

**Sound bug vs. P2 suspicion (the distinction that gates escalation):**

- A **sound bug** is a **read-confirmed P0/P1** finding: a **read-confirmed trigger** OR a **directly-cited contradiction** in the caller/contract you read (per the Phase-2 severity-routing rule). Sound bugs are **blocking** and **trigger DV escalation**.
- A **P2 `[verify-later]` suspicion** is an unproven-but-located concern (BLOCKED verification, read-but-inconclusive, or a class a normal test run backstops). P2 suspicions are **non-blocking**: they are **surfaced in `§ Findings` for QA / follow-up** and do **NOT** trigger DV escalation. (Promote a P2 to P1 only after reading the cited code confirms the break.)

**How to escalate (reuse existing machinery):**

1. **Set the DR run `verdict: fail` — this IS the escalation.** A DR `verdict: fail` is a review rejection, and the orchestrator's execution loop re-dispatches the **previous stage (DV)** on a DR rejection, carrying the DR findings verbatim into the DV retry prompt (run_index bumped, `retry_count++`). See `skills/worktask/SKILL.md § Orchestrator Execution Loop` ("when the previous DR returned `verdict:fail` … the orchestrator re-dispatches DV") and the escalation chain `…DR→DV…` in `skills/agent-coordination/SKILL.md § Error Handling`. No special routing classification is needed — the standard stage-rejection loop inherently reaches DV.
2. **Record the sound findings in `.context/developer-review-N.md § Findings`** (the DR artifact the DV retry prompt reads), one entry per sound finding naming the file, the trigger, and what must change. This is what DV actually consumes to remediate.
3. **Optional supplementary tracking block.** If you also append a `## DR[N] Retry — <ts>` block to `.context/errors/developer.md` (mirroring the DR3.5 precedent's *form*), give it a `### Resolution Path` with one bullet per sound finding, and use `**Classification**: missing_input` — the ONLY classification besides `exhausted` that the Retry/Escalate Matrix routes to the **previous stage** (DV, per the chain above). Do NOT use `logic` (the matrix routes `logic` to "same agent" — it re-runs the DR reviewer, never DV) and do NOT use `ambiguous_requirements` (the matrix routes that to PL). The error block is a tracking artifact only; the `verdict: fail` in step 1 is the mechanism that re-dispatches DV.

> **Reconciliation with `agents/technical-lead.md § DR3.5`:** DR3.5 covers a *narrower, different trigger* — test-selection parser warnings (`unknown_symbol`, `missing_marker`, malformed `@depends-on:`) — but routes to the **same place this subsection does: DV**, because those warnings concern DV-owned test markers/selection that only the developer can fix. It reaches DV the same two ways: its `verdict: fail` re-dispatches DV, and its tracking block uses `**Classification**: missing_input` (matrix → previous stage = DV). The only difference is the trigger — DR3.5 fires on test-selection warnings, this subsection on a read-confirmed sound code bug. DV fixes, then DR **re-reviews** the changed remediation — a fresh DR run on the new diff. Repeat the changes-requested → DV fix → DR re-verification loop until no open P0/P1 remains.

Do not restate the retry/escalate matrix or the error-block schema here — they are owned by `skills/agent-coordination/SKILL.md § Error Handling` and `skills/shared/stage-contracts.md`. This subsection only states which findings escalate and that the existing machinery carries them.

**DR stays read-only.** This command routes confirmed bugs to DV and re-reviews the fix; it does **NOT** apply the fix itself. `allowed-tools` is read-only (`Read`, `Glob`, `Grep`, read-only `git diff`/`log`/`show`) — no tree-mutating or code-executing tool is ever added for remediation.

## Review Dimension Routing

When multiple focus areas are requested, consider parallel multi-dimensional review:

| Scenario | Recommended Dimensions |
|----------|----------------------|
| API endpoint changes | security, performance, patterns |
| UI component changes | patterns, tests, accessibility |
| Data model changes | security, performance, patterns |
| Auth/payment flows | security, safety, tests |

## Focus Areas

- **security**: Authentication, data storage, input validation, secrets, supply chain
- **performance**: Memory, CPU, network, battery impact
- **patterns**: Platform idioms, design patterns, architecture
- **tests**: Coverage, quality, edge cases
- **safety**: Harm potential, user protection, error handling for safety-critical paths
- **honesty**: Truthful comments, accurate error messages, non-deceptive UI patterns
- **accessibility**: WCAG compliance, VoiceOver/TalkBack support, Dynamic Type

### Safety Focus (`--focus safety`)

Reviews code for potential user harm. Findings use the canonical P-scale and are written to `§ Findings`:

```markdown
### #S-01 [P1] Missing input validation on user data
User input is passed directly to a database query in `src/forms/UserProfile.swift:34`.
Potential harm: SQL injection, data corruption. Affected: all users submitting profile updates.
Constitutional principle: harm avoidance. Recommendation: sanitize input before the database operation.

### #S-02 [P1] No rate limiting on API endpoint
`src/api/SubmitController.swift:12` is vulnerable to abuse.
Potential harm: service disruption, resource exhaustion. Recommendation: add rate-limiting middleware.
```

### Honesty Focus (`--focus honesty`)

Reviews code for truthfulness and transparency. Findings use the canonical P-scale and are written to `§ Findings`:

```markdown
### #H-01 [P2] Misleading error message
`src/errors/ErrorHandler.swift:45` throws `UserError("Something went wrong")` — it does not describe the
actual problem. Property violated: truthful, forthright. Users cannot understand or fix the issue.
Recommendation: provide a specific, actionable message (e.g. "Failed to save profile: network unavailable").

### #H-02 [P1] Hidden data collection
`src/analytics/Tracker.swift:78` collects analytics without user notification.
Property violated: transparent, non-deceptive. Users are unaware of the data collected.
Recommendation: disclose in privacy settings and allow opt-out.
```

## Integration

This command is used:
- As the DR (Developer Review) gate in the worktask, invoked by the technical-lead (`Skill("code-review-dev")`).
- Before merging PRs.
- For periodic codebase health checks.

