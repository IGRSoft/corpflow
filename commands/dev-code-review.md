---
name: dev-code-review
description: Perform platform-aware code review using specialized developer expertise; --depth deep adds full technical-review analysis
argument-hint: '[--pr N | --path dir] [--depth surface|deep]'
model: sonnet
allowed-tools: Read, Glob, Grep, Bash(git diff:*), Bash(git log:*), Bash(git show:*)
version: 0.3.0
related:
  - agents/developer.md
  - agents/technical-lead.md
  - skills/shared/code-documentation.md
  - commands/arch-review.md
  - commands/arch-debt.md
  - commands/ethics-review.md
  - commands/estimate.md
  - skills/claude-constitution/SKILL.md
  - skills/shared/stage-contracts.md
  - skills/agent-coordination/SKILL.md
---

# Developer Code Review Command

A **recall-first, read-only** developer code review. This command IS the DR (Developer Review) quality gate: it statically reviews the change for correctness, security, data-loss, concurrency, and regression risk, records findings to the DR artifact, and routes confirmed bugs back to DV. It never runs code (tests run later in QA) and never applies fixes (DV applies them).

> **Depth modes**: `--depth surface` (default) is the standard DR review below — behavior unchanged. `--depth deep` layers a technical-review analysis on top; see [Deep Mode](#deep-mode---depth-deep). For estimation-accuracy reviews use `/estimate --review`.

> **Disambiguation**: use `/dev-code-review` for the corpflow governed gate (stage contracts, audit trail, read-only — DV applies the fixes); use the CC-native `/code-review` (alias `/review`, applies findings with `--fix`; `ultra` = multi-agent cloud review) or `/simplify` for ad-hoc work outside the worktask pipeline.

## Your Job (read this first)

You are a **recall-first quality gate**, not a courtesy PR commenter: **catch real correctness, security, data-loss, concurrency, and regression risks BEFORE they reach later review or production.** The historic failure mode of this review is silence on bugs the reviewer was *somewhat sure* about — **"somewhat sure about a real bug" is the exact miss profile, and it must NOT default to silence and must NOT be laundered into a throwaway non-blocking note.**

### Operating principles

| Principle | Rule |
|---|---|
| **Never default to silence** | Costs are asymmetric: a missed defect becomes a production incident; a hedged over-cautious finding costs a reader thirty seconds. An empty findings list is a strong claim, earned only via the Phase 3 pass — but an earned clean pass IS valid, so never invent a token finding to prove you looked. Coverage (`N files, M hunks reviewed`) is the evidence. |
| **Judge objectively** | You are not predicting whether the author will agree — authors routinely disagree with valid bug reports. Flag on whether the code is actually *at risk*. |

#### Operating principles — verification stance

| Principle | Rule |
|---|---|
| **Read, don't run** | Static, read-only review (`Read`, `Glob`, `Grep`, read-only `git diff`/`log`/`show`). Compensate for the lack of execution with deeper reading and explicit reasoning — never by assuming the code works. |
| **Adversarial stance** | Assume-it's-wrong-until-checked; for each non-trivial path actively try to construct an input, state, or sequence that breaks it. |
| **Absence of evidence ≠ safety** | Not finding a concurrent caller does not prove single-threadedness; not finding a consumer does not prove none exists. Inability to verify keeps a concern alive (BLOCKED rule) — it does not retire it. |

The *keep/drop* criteria that decide what is finally reported live in Phase 2 — they are **not** a license to skip discovery. Find first (Phase 1), filter second. A concern you never wrote down can never be caught.

## Usage

```
/dev-code-review
/dev-code-review --platform apple --path src/
/dev-code-review --pr 123
/dev-code-review --pr 123 --depth deep
```

## Options

- `--platform <apple|android|web|systems|backend|ai|all>` - Platform context (default: auto-detect)
- `--path <dir>` - Review a specific directory (diff scoped to that path)
- `--pr <number>` - Review the changes in a PR
### Depth and focus options

- `--depth <surface|deep>` - Review depth (default: `surface`, the recall-first DR review below); `deep` additionally emits the technical-review analysis (see [Deep Mode](#deep-mode---depth-deep)). The DR stage passes no `--depth`, so it always resolves to `surface`.
- `--focus <areas>` - Focus areas: security, performance, patterns, tests, safety, honesty, accessibility. `--depth deep` additionally accepts `quality` and `debt`.
### Output, severity, and ethics options

- `--output <summary|detailed>` - Output verbosity for `--depth deep` (default: `detailed`). Ignored in surface mode, which always writes the findings artifact format below.
- `--severity <level>` - Minimum severity to report: `P2`, `P1`, `P0`. Detection (Phase 1) is never filtered by this option — it only gates what is written to the findings artifact.
- `--ethics` - Include constitutional compliance checks

## Getting the diff and context

Obtain the change set with read-only `git` only (as the DR stage, this is the read-only git the stage owner already carries):

```bash
git diff origin/master...HEAD             # committed changes vs the merge-base with the target branch
git diff HEAD                             # uncommitted (staged + unstaged)
git diff origin/master...HEAD -- <path>   # when scoped by --path
```

The three-dot form diffs against the merge-base in one call — no separate `git merge-base` step (intentionally outside the read-only grant). `--pr N` scopes to that PR, `--path dir` to that directory; review committed and uncommitted changes together. Never `git checkout`/`reset`/`stash`, any other tree-mutating command, or any tool that runs the product or its tests.

### Read beyond the diff (MANDATORY — this is where most missed bugs live)

A diff alone hides the highest-value defects: broken callers, violated contracts, removed guards, renamed-but-still-referenced symbols, regressions to untouched consumers. You can `Read`/`Grep` the whole workspace — use it. **Before judging any non-trivial change you MUST:**

- Open the **full changed function/type**, not just the visible hunk, plus the **definitions** it relies on and any file the diff **references but does not modify** when behavior depends on it.
- **Grep and read the consumers** of anything changed — a changed **signature**; a changed **default, constant, config literal, threshold, or enum case**; OR a **caller-observable behavior change inside a body** (different return for the same input, new early-return, changed ordering or side effect). An unchanged signature does NOT exempt a behavior change from the caller read.

#### Dynamic references and the intent check

- **Chase dynamic / indirect references — they defeat name-based grep.** For any changed public or serialized symbol, ALSO search its name **as a string literal** and the indirect-dispatch sites: selectors / `#selector`, `NotificationCenter` names, KVO keypaths, serialized JSON/plist/DB keys, DI or registration tables, reflection, codegen inputs. If indirect use is plausible and you cannot prove it absent, keep a located finding naming the suspected indirection.
- **Intent check (acceptance-criteria checklist):** where a spec exists (`.context/planning-N.md`, the linked issue/PR body), extract every acceptance criterion and stated edge/error/validation requirement into a checklist and verify the diff satisfies **each one individually**. An unmet stated requirement is a **P1 correctness finding** even if the implemented path is itself correct.

## Review Methodology (recall-first, three decoupled phases)

The phases are **decoupled on purpose**: detection finds widely, filtering suppresses, self-verification proves coverage. Never collapse detection into filtering — that is how the *somewhat-sure* bug gets dropped before it is written down.

### Phase 1 — DETECTION (find widely; do NOT filter yet)

Enumerate **every** plausible concern. **Apply NO confidence bar and NO "would the author fix it" test here** — over-inclusion is correct; you filter in Phase 2.

#### Depth gate — scale scrutiny to change size

Small diff (≤10–15 changed lines, single file): one focused sweep against only the classes plausibly implicated plus a one-line "other classes: n/a"; skip the per-class "none" enumeration and the riskiest-hunk narrative. Medium / large / architecturally significant diff: the full multi-lens sweep with per-class accounting and more surrounding-context reading — fatigue rises past ~400 changed lines, so slow down, do not skim.

For **each changed hunk**, first reason briefly (internal scratchpad, not written to the artifact): *what is this code supposed to do; trace the main path plus at least one error / empty / null / boundary / concurrency path; what does it assume about its callers?* Then sweep it against the **13-class checklist**, each class a separate lens. On a medium/large diff decide explicitly for every class — a hit becomes a candidate; a clean class is noted "none" so the omission is visible, not silent.

#### Bug classes 1–4

| # | Bug class | Lens |
|---|---|---|
| 1 | Correctness vs. intent | Logic errors, inverted conditions, wrong operator, copy-paste slips, **and any acceptance criterion from the intent check left unimplemented**. |
| 2 | Edge cases | Empty/null/zero/negative/very-large inputs, single-element collections, first/last iteration. |
| 3 | Nil / optionals / unwraps | Force-unwraps, non-null assertions, missing nil checks, removed load-bearing guards. |
| 4 | Error handling & failure paths | Swallowed exceptions, generic catches, unchecked error returns, partial failure leaving inconsistent state, missing rollback. |

#### Bug classes 5–8

| # | Bug class | Lens |
|---|---|---|
| 5 | Concurrency / races / ordering | Shared mutable state, check-then-act, missing locks/await, actor isolation, lock ordering, reentrancy, await-point invariants. **For any change touching shared / static / instance mutable state you MUST determine the concurrency context: grep call sites for thread/queue/task/actor/async usage and read enough to know whether the path can run concurrently.** Failing to establish it is single-threaded is NOT disproving a race. |
| 6 | Resource lifecycle / leaks | Unclosed handles/streams/connections, retain cycles, missing dispose/defer, leaked tasks/observers. |
| 7 | Boundary / off-by-one | Indexing, range bounds, slicing, loop terminators, integer overflow/truncation. |
| 8 | Input validation / security | Unsanitized input in file/command/query/HTML, authz/authn checks, secrets in code/logs, injection, unsafe deserialization, missing bounds on external data. |

#### Bug classes 9–12

| # | Bug class | Lens |
|---|---|---|
| 9 | API contract & compatibility | Changed signature/return type/nullability/error semantics; renamed or removed symbol still referenced (statically OR via the dynamic-dispatch sites above); broken public/serialized contract. |
| 10 | State / persistence / migration | Schema/migration correctness, default values, data-loss on write, cache/state coherence, idempotency. |
| 11 | Performance cliffs | Accidental O(n²), N+1 queries, work in hot loops, unbounded growth, blocking the main thread. |
| 12 | Regressions to existing behavior | A previously-working path changed, including a latent path this change newly *activates*. A changed default/constant/threshold that alters an untouched consumer is the classic silent regression — verify those consumers. |

#### Bug class 13 — hallucinated dependencies

| # | Bug class | Lens |
|---|---|---|
| 13 | Hallucinated dependencies | Imports/requires/`use`s resolving to no declared dependency (Package.swift/Podfile/`*.gradle`/package.json/requirements.txt); invented API methods or plausible-but-absent symbols; calls into an API removed in the version actually resolved. This stage's diff **is** AI-generated, which fabricates these at rates hand-written code does not — a fabricated symbol type-checks locally yet resolves to nothing at build time. |

### Phase 2 — VERIFICATION & FILTERING (the only place you suppress)

For each Phase-1 candidate: state the **concrete trigger** (the input/state/environment under which it bites), then try to **confirm it** by reading the relevant code (caller, definition, other file, dynamic-dispatch site) — that reading is what makes an integration/regression risk reportable and promotes a suspicion to a blocker. **Drop a candidate only if you can actively DISPROVE it** or it is **trivial style** with no impact on meaning/behavior. **Do NOT drop a candidate merely because you are unsure** — uncertainty is reported at lower severity, not suppressed.

#### BLOCKED-verification rule (mandatory)

If verification is BLOCKED — caller/consumer/threading model not readable, file generated or outside the workspace, fan-out too large, reference dynamic and unprovable — **you have NOT disproved the concern. Keep it.** Name precisely what you could not verify and tag `[verify-later]`. **Never drop a correctness / security / concurrency / regression concern for lack of access.**

#### Keep / drop bar (recalibrated)

A candidate is worth reporting when it (a) meaningfully impacts accuracy, performance, security, or maintainability; (b) is discrete and actionable, not "the whole module is messy"; (c) does not demand rigor absent from the rest of the codebase; (d) was introduced or **newly activated/exposed** by this change; (e) is a real risk to correctness, security, or users, **judged objectively**; and (f) is clearly not an intentional, documented change by the author.

##### What to keep

- **KEEP** any concern touching correctness, security, data-loss, concurrency, resource leaks, contract breaks, or regressions when it is **plausible and you can articulate a trigger** — even at moderate confidence. It may rest on a **reasonable, stated inference** about intent: say the inference out loud, do not veto it for being inferential.
- **KEEP** a clearly-reasoned cross-file / integration / ripple risk even if you cannot *prove* the break, **provided you name the specific other code you suspect and why**. Hedge the wording; do not silently drop it.

##### Style bar, pre-existing cap, systemic defects

- **RAISE THE BAR** only for low-severity style / maintainability items: apply a strict "would a competent reviewer clearly endorse this" test, and skip trivial style unless it obscures meaning or violates a documented standard. Over-documentation violating `skills/shared/code-documentation.md` (doc-comment essays, design-history narration, audit logs, call-site enumerations, AC-/REQ-/issue-ID tags, commented-out preview/story/fixture blocks) is a flaggable **P2**.
- **Pre-existing-weakness cap (class 12):** a pre-existing weakness blocks (P0/P1) ONLY if THIS diff makes the broken path newly reachable AND you can name the new entry point. Otherwise record **P2 `[verify-later]`** noted "pre-existing, exposed by this change."
- Systemic / multi-edit defects (a bug spanning several hunks) ARE in scope — report as one finding describing the pattern.

#### Severity routing for uncertain findings (the recall-vs-noise control)

- **Route to P1 (blocking)** when (a) you are *somewhat sure or more* it is a real defect AND (b) it is of a class a normal test run rarely exercises — **concurrency races, rare-edge nil/unwrap crashes, regressions to untouched paths, indirect-dispatch contract breaks**. These cannot be rescued by "the tests will catch it," so a non-blocking note would launder a likely-real bug into a guaranteed miss. Requires a **read-confirmed trigger** OR a **directly-cited contradiction** in the caller/contract you read.
- **Route to P2 `[verify-later]`** (non-blocking) when EITHER a normal test run genuinely WOULD exercise it (testing is a real backstop), OR it is an unproven located suspicion you could not confirm by reading (BLOCKED or read-but-inconclusive). **An unproven cross-file/ripple suspicion stays P2 — promote to P1 only after reading the cited code confirms the break.**

### Phase 3 — Completeness / self-verification (before you write output)

Do NOT skip this — it catches the misses. (On a small diff per the Phase-1 gate, steps 2–3 collapse to one line confirming the implicated classes were considered.)

1. **Coverage**: confirm you examined **every changed file and every hunk**; if any was skipped, go back now. This is the basis of the mandatory coverage statement.
2. **What did I miss?**: re-read the full diff once more against the 13-class checklist. **Treat your own silence as a red flag, not a success** — but do not manufacture a finding to break it.
3. **Highest-risk hunks**: for the 1–3 riskiest changes (medium/large diffs), explicitly answer "**what is the most likely way this breaks in production?**" No answer means you have not looked hard enough.
4. For anything considered and **dismissed**, keep a one-line reason (in your reasoning; not necessarily in the artifact).

## Severity scheme (P0/P1/P2 — canonical)

P0/P1/P2 is the single canonical severity scheme for this command. Tag every kept finding with its canonical P-level.

| Canonical | Definition |
|-----------|------------|
| **P0** (blocker) | Crash, data loss/corruption, security vulnerability, broken build/contract, or a regression to core behavior. High confidence. |
| **P1** (high) | Likely-incorrect behavior, unhandled error/edge path, concurrency hazard, resource leak, contract risk, or an unmet stated acceptance requirement, with a **read-confirmed or directly-cited** trigger (or a hard-to-test class you are somewhat-sure-or-more about, per the routing rule). |
| **P2** (nice-to-have / suspected) | Lower-impact issues, unproven-but-located suspicions, BLOCKED-verification concerns, change-exposed-but-not-newly-reachable pre-existing weaknesses (tagged `[verify-later]`), minor maintainability. |

## Examples

```
/dev-code-review
/dev-code-review --platform apple --path Sources/
/dev-code-review --pr 42 --focus security,performance
/dev-code-review --path src/components --focus patterns
/dev-code-review --pr 42 --severity P1
/dev-code-review --pr 42 --depth deep --focus quality,debt --output summary
/dev-code-review --pr 42 --ethics
```

## Output Format

Findings go to the DR findings artifact `.context/developer-review-N.md § Findings` (N = `task.metadata.run_index`; resolver: metadata → newest glob `developer-review-*.md`), never as inline diff comments — this command has no diff-comment tool and runs read-only.

Each finding carries its canonical severity tag, names the file (and tightest line subrange), states **why** it is a bug, and **explicitly names the scenario/inputs/environment** needed for it to arise. At most one paragraph each; for uncertain findings say so plainly and tag `[verify-later]`. Tone matter-of-fact, not accusatory, not flattering.

### Example findings artifact

```markdown
# Developer Code Review

**Platform**: Apple (Swift/iOS)
**Coverage**: 12 files, 34 hunks reviewed

## Findings

### #1 [P0] Empty input crashes on load
If the input field is empty when the page loads, `parseInput` force-unwraps nil and crashes.
File: `src/client/ui/Input.tsx:42-44`

### #2 [P1] Caller in PaymentService breaks on changed return type
`fetchUser` now returns `User?`; `PaymentService.charge` does not handle nil and would dereference it.
Triggers when the user lookup misses. Read-confirmed in `PaymentService.ts`.
File: `src/server/PaymentService.ts:88`

### #3 [P2][verify-later] Possible indirect consumer via notification name
The renamed `"userDidUpdate"` notification may still be observed elsewhere; string-literal grep was
inconclusive across generated files. Not blocking.
File: `src/core/Notifications.ts:17`

## Decision

Decision: changes-requested (1 open P0, 1 open P1)
Coverage: 12 files, 34 hunks reviewed
```

### Decision line (required)

End every review with an explicit decision and the coverage statement:

- `Decision: changes-requested` (verdict `fail`) when **any open P0 or P1** finding exists.
- `Decision: pass` when the review is **P2-only or clean** — record the P2 findings for follow-up but do not block.
- Always state coverage: `Coverage: N files, M hunks reviewed`.

This aligns with the plugin's DR verdict semantics in `agents/technical-lead.md` (the DR handoff `verdict: pass|fail`).

## Escalation to DV (changes-requested → DV fix → DR re-review)

A **sound bug** — a **read-confirmed P0/P1** (read-confirmed trigger OR directly-cited contradiction in the caller/contract you read) — makes the verdict `fail` and is **routed back to DV for remediation**, after which DR **re-verifies** the fix, reusing the EXISTING retry/escalate machinery. A **P2 `[verify-later]` suspicion** is non-blocking: surfaced in `§ Findings` for QA follow-up, never a DV escalation (promote to P1 only after reading the cited code confirms the break).

### How to escalate (reuse existing machinery)

1. **Set the DR run `verdict: fail` — this IS the escalation.** The orchestrator's execution loop re-dispatches the **previous stage (DV)** on a DR rejection, carrying the DR findings verbatim into the DV retry prompt (run_index bumped, `retry_count++`). See `skills/worktask/SKILL.md § Orchestrator Execution Loop` and the escalation chain `…DR→DV…` in `skills/agent-coordination/SKILL.md § Error Handling`. No special routing classification is needed.
2. **Record the sound findings in `.context/developer-review-N.md § Findings`** — the artifact the DV retry prompt reads — one entry per finding naming the file, the trigger, and what must change.

#### Escalation step 3 — optional tracking block

3. **Optional tracking block.** If you also append a `## DR[N] Retry — <ts>` block to `.context/errors/developer.md`, give it a `### Resolution Path` with one bullet per sound finding and use `**Classification**: missing_input` — the ONLY classification besides `exhausted` that the Retry/Escalate Matrix routes to the **previous stage** (DV). Do NOT use `logic` (routes to the same agent, re-running the DR reviewer, never DV) or `ambiguous_requirements` (routes to PL). The block is tracking only; step 1 is the mechanism.

### DR3.5 reconciliation and the read-only guarantee

> **Reconciliation with `agents/technical-lead.md § DR3.5`:** DR3.5 has a narrower trigger — test-selection parser warnings (`unknown_symbol`, `missing_marker`, malformed `@depends-on:`) — but routes to the **same place** by the **same two mechanisms**, because those warnings concern DV-owned test markers. Either way DV fixes, then DR **re-reviews** the remediation as a fresh DR run on the new diff. Repeat changes-requested → DV fix → DR re-verification until no open P0/P1 remains.

Do not restate the retry/escalate matrix or the error-block schema here — they are owned by `skills/agent-coordination/SKILL.md § Error Handling` and `skills/shared/stage-contracts.md`.

**DR stays read-only.** This command routes confirmed bugs to DV and re-reviews the fix; it does **NOT** apply the fix. `allowed-tools` stays read-only — no tree-mutating or code-executing tool is ever added for remediation.

## Review Dimension Routing

When multiple focus areas are requested, consider parallel multi-dimensional review:

| Scenario | Recommended Dimensions |
|----------|----------------------|
| API endpoint changes | security, performance, patterns |
| UI component changes | patterns, tests, accessibility |
| Data model changes | security, performance, patterns |
| Auth/payment flows | security, safety, tests |

## Focus Areas

| Focus | Covers |
|---|---|
| **security** | Authentication, data storage, input validation, secrets, supply chain. Deep mode adds OWASP Top 10, authorization, data protection, secure coding practices. |
| **performance** | Memory, CPU, network, battery. Deep mode adds Big-O complexity, resource management, caching, hot-path optimization. |
| **patterns** | Platform idioms, design patterns, architecture |
| **tests** | Coverage, quality, edge cases |
| **safety** | Harm potential, user protection, error handling for safety-critical paths |
| **honesty** | Truthful comments, accurate error messages, non-deceptive UI patterns |
| **accessibility** | WCAG compliance, VoiceOver/TalkBack support, Dynamic Type |

### Deep-mode focus areas and the safety/honesty format

| Focus | Covers |
|---|---|
| **quality** *(deep)* | Cyclomatic/cognitive complexity, duplication, naming clarity, error-handling completeness, documentation adequacy |
| **debt** *(deep)* | New debt introduced, existing debt affected, interest-rate assessment, remediation. Codebase-wide inventory: `/arch-debt`. |

`--focus safety` and `--focus honesty` findings use the same entry format and canonical P-scale in `§ Findings`, numbered `#S-01` / `#H-01`, and add two lines: the harm or violated property (`Potential harm: SQL injection, data corruption. Affected: all users submitting profile updates.` / `Property violated: truthful, forthright.`) and a concrete recommendation.

## Deep Mode (`--depth deep`)

`--depth deep` runs the full surface review **and then** appends the analysis below, never altering the surface findings, verdict semantics, or DV-escalation loop. Emit these sections with the tables specified (status cells use ✅ / ⚠️):

```markdown
# Technical Review (deep)

## Summary
| Dimension | Score | Status |  — Correctness, Readability, Maintainability, Efficiency, Security, Testability (n/10)
**Overall**: n/10 — one-line merge verdict

## Code Quality Analysis
Complexity:  | File | Cyclomatic | Cognitive | Status |
Duplication: | Pattern | Occurrences | Impact |
Naming:      | Issue | Location | Suggestion |

## Performance Analysis
Hot paths:   | Path | Complexity | Concern |   — e.g. `searchUsers()` | O(n²) | ⚠️ optimize
Resources:   | Check | Status | Notes |        — memory allocation, connection handling, file handles
Caching:     one bullet per candidate with call frequency and why it is cacheable
```

### Deep template — security, debt, coverage

```markdown
## Security Implementation
OWASP:       | Check | Status | Notes |        — input validation, output encoding, authn, authz, data protection, logging
Vulnerabilities: | Risk | Severity | Location | Remediation |

## Technical Debt Identified
New debt:    | Item | Type | Interest | Effort |
Existing:    | Item | Change | Recommendation |

## Test Coverage Impact
| Metric | Before | After | Status |            — line, branch, changed-code coverage
Missing test cases: one bullet each
```

`--output summary` emits the Summary table plus one bullet per section's top finding; `detailed` emits every table.

## Integration

- The DR gate in the worktask: the technical-lead reads and follows this file (`agents/technical-lead.md § DR Stage Owner`). This is a command, not a skill — there is no `skills/dev-code-review/` to invoke.
- DV/QA stages via `--depth deep` for a technical-quality deep dive.
- Before merging PRs, and for periodic codebase health checks.
