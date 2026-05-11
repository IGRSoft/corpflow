---
name: test-selection-syntax
description: Inline test marker grammar for selective test execution. Reference when annotating tests, parsing markers in DV, or extending platform handlers. Defines @test-required, @depends-on, and @test-tag markers consumed by the Test Selection Gate.
effort: low
---

# Test Selection Syntax

Inline source-level markers that DV parses to compute the `Selected Tests` list consumed by QA. Companion to `skills/shared/testing-strategy.md § Test Selection Gate`.

## Markers

Three markers, written as line comments in test source files. All three are optional — untagged tests are treated as `@test-tag: regression` with no dependency edges (run only in `test_mode=full` or via explicit `metadata.always_required_tests`).

### `@test-required`

The test runs in **every** mode (`build-only`, `scoped`, `full`). Use sparingly — reserve for smoke tests, app-launch checks, auth round-trip, and other "if this fails the build is unusable" guards.

```swift
// @test-required
@Test("app launches and reaches root view")
func appLaunches() async throws { ... }
```

### `@depends-on: <SymbolName>`

Re-run this test when the named symbol (top-level type, function, or extension target) appears in the changed-files diff. One symbol per marker; repeat for multiple dependencies. Symbol matching is by exact name — case-sensitive — against the symbols extracted from changed files.

```swift
// @depends-on: PaymentService
// @depends-on: OrderRepository
@Test("refund flow reverses charge")
func refundFlow() async throws { ... }
```

A diff that touches `PaymentService.swift` (any symbol) marks `PaymentService` as changed; a diff that touches a free function `processRefund(...)` extracts that function's name. Tests with `@depends-on: PaymentService` or `@depends-on: processRefund` are added to the Selected Tests list.

### `@test-tag: <tag>`

Categorize the test for filtering. Conventional tags:

| Tag | Meaning | Where it runs |
|-----|---------|---------------|
| `smoke` | Critical-path verification | Always (treated as `@test-required`) |
| `regression` | Default for untagged tests | `test_mode=full` only, unless dep-matched |
| `perf` | Performance-sensitive, slow | `test_mode=full` only |
| `ui` | UI/visual interaction | `test_mode=full` AND `ui_visual_check=true` |
| `flaky` | Quarantined; not executed | Never (until untagged) |

Multiple tags allowed via repeated markers. Unknown tags are preserved (parser is permissive) but ignored by the dispatcher.

```swift
// @test-tag: smoke
// @depends-on: SessionStore
@Test("login round-trip stores session")
func loginRoundtrip() async throws { ... }
```

## Swift Testing trait equivalents

Swift Testing's native `.tags(_:)` trait is recognized as a first-class equivalent to `@test-tag:`. Define tags once per project and reference them by `Tag` value:

```swift
extension Tag {
    @Tag static var smoke: Self
    @Tag static var required: Self
}

@Test("login round-trip", .tags(.smoke, .required))
func loginRoundtrip() async throws { ... }
```

Mapping:

| Comment marker | Swift Testing trait |
|----------------|---------------------|
| `// @test-required` | `.tags(.required)` |
| `// @test-tag: smoke` | `.tags(.smoke)` |
| `// @depends-on: SymbolName` | (no native trait — use comment marker) |

`@depends-on:` has no Swift Testing trait equivalent because dependency declarations are not test-runner concerns; the parser reads comments. Mixed style is allowed: tests can use traits for tags and comments for `@depends-on:`.

## Parser algorithm (DV/D2)

DV's D2 step performs:

```
1. diff = git diff --name-only <base>...HEAD
2. changed_symbols = ∅
   for file in diff:
     if file matches src extension:
       changed_symbols += extract_top_level_symbols(file)  # types, funcs, enums
3. test_files = glob(<test source roots>)
4. selected = ∅
   for tf in test_files:
     for test in tests_in(tf):
       markers = parse_markers(test)
       if "@test-required" in markers OR "smoke" in tags(markers):
         selected += test
       if any(dep in changed_symbols for dep in markers["@depends-on"]):
         selected += test
       if test covers any file in diff (file-path heuristic; see below):
         selected += test
   selected += metadata.always_required_tests  # plan-level override
5. write Selected Tests section to development-N.md
```

### "Covers" rule — exact specification

A test is considered to **cover** a changed source file when **any** of these match (evaluated in order; first match wins):

1. **Filename correlation**: changed file is `Sources/<path>/<Name>.swift`; test file path matches glob `Tests/**/<Name>Tests.swift` OR `Tests/**/<Name>Spec.swift`.
2. **Type-name correlation**: changed file declares a top-level type `T`; test source declares a type matching `^${T}Tests?$` or `^${T}Spec$`.
3. **Module correlation** (used in `scoped` mode only — not `build-only`): test file is in the same module/target as the changed file (Swift package target, Xcode test target, or sibling directory under `Tests/`).

Rules 1 and 2 are the universal "covers" definition for `build-only` mode. Rule 3 is an additive over-inclusion in `scoped` mode (deliberate safety margin). `full` mode ignores this heuristic — it runs everything.

The parser logs an `info`-level note in `.context/logs/test-selection-warnings.md` for every diffed file with no covering test and no marker hit, so PMs can assess gaps.

### Malformed marker handling

Markers are parsed permissively:

- Unknown tag (`@test-tag: foo`) — preserved, ignored by dispatcher; warning logged.
- Malformed marker (e.g., `@depends-on:` with no symbol) — warning logged to `.context/logs/test-selection-warnings.md`; test is otherwise included as if the marker were absent.
- Marker on the wrong scope (e.g., `@test-required` on a `@Suite` instead of `@Test`) — applies to **all** tests in the suite. Documented behavior; intentional.

## Closure rules

When a `@depends-on: A` marker matches and includes test `T`, **transitive closure is NOT computed** by default — the parser does **not** chase A's downstream callers. Rationale: transitive closure invariably balloons the selected set and defeats the purpose of selective execution. If a dependency has fan-out tests that must always run, mark them `@test-required` or list in `metadata.always_required_tests`.

Exception: when `test_mode=scoped`, the parser additionally adds tests for **any module** touched by the diff (module = directory of the changed file). This is a deliberate over-inclusion: `scoped` is the safety mode for users who can't trust the marker graph yet.

## Examples

### Backend-only diff with good markers

Diff: `Sources/Networking/RetryPolicy.swift` (function rename + behavior change)

Test markers (existing repo state):
- `RetryPolicyTests` — `// @depends-on: RetryPolicy`
- `NetworkClientTests` — `// @depends-on: NetworkClient` (NetworkClient calls RetryPolicy but no marker on NetworkClientTests for RetryPolicy)
- `AuthFlowTests` — no marker
- `AppLaunchTests` — `// @test-required`

`test_mode: build-only` → Selected = `RetryPolicyTests`, `AppLaunchTests`. NetworkClientTests excluded (not marked). AuthFlowTests excluded.

`test_mode: scoped` → Selected = `RetryPolicyTests`, `AppLaunchTests` + every test in `NetworkingTests/` (module-level over-inclusion). AuthFlowTests still excluded (different module).

`test_mode: full` → entire suite.

### UI feature diff

Diff: `Sources/UI/LoginView.swift`, `.context/designs/figma-login-error-42-7.png`

Plan: `test_mode: build-only`, `ui_visual_check: true`

→ DV: build only, no test execution. Selected Tests = `[<from markers>]` written to development-N.md.
→ QA: runs Selected Tests + Design Comparison (gated on `ui_visual_check=true` AND designs present, independent of `test_mode`).

### Migration: untagged repository

A project with zero markers running `test_mode: build-only` produces an empty Selected Tests list (apart from `metadata.always_required_tests`). The dispatcher applies the **auto-promotion safety net** documented in `testing-strategy.md § Three test modes`: QA promotes to `scoped` for that run and writes a note to `testing-N.md § Notes`:

> Selected Tests was empty under `test_mode: build-only`. Auto-promoted to `scoped` for safety. Add `@test-required` markers or `metadata.always_required_tests` to opt back into build-only.

DV warns to `.context/logs/test-selection-warnings.md`:

> No `@test-required` or `@depends-on:` markers found in <N> test files. Selected Tests is empty. Either tag tests, set `metadata.always_required_tests`, or use `test_mode: scoped|full`.

DR (`agents/technical-lead.md`) reads the warning log as part of code review and surfaces non-empty warning files in `developer-review-N.md § Findings`. Silent test drops escalate to DV via DR's normal feedback channel.

## Warning log schema

`.context/logs/test-selection-warnings.md` (appended by DV, never overwritten):

```markdown
# Test Selection Warnings — <ISO-8601 timestamp>

## Run <N> — <plan_file>

- INFO: 12 changed files; 8 covered by markers, 4 with no covering test or marker.
- WARN: malformed marker at `Tests/PaymentRefundTests.swift:14` — `// @depends-on:` (missing symbol). Treated as absent.
- WARN: unknown tag `@test-tag: critical-path` at `Tests/AuthFlowTests.swift:22`. Use one of: smoke, regression, perf, ui, flaky.
- INFO: empty Selected Tests for `test_mode=build-only`. Consider tagging or `metadata.always_required_tests`.
```

QA reads this file and quotes any `WARN:` lines into `testing-N.md § Notes`.

## Platform handlers

The marker grammar is platform-agnostic (line comments are universally parseable). Platform-specific concerns:

| Platform | Test ID format used in `-only-testing:` / equivalent | Implementation |
|----------|------------------------------------------------------|----------------|
| Apple (Swift Testing / XCTest) | `<TargetName>/<TypeName>/<methodName>` | `apple-developer:swift-testing-entry` skill, `references/dependency-markers.md` |
| Android (JUnit) | `<package>.<ClassName>#<methodName>` (TBD) | Stub — handler not yet implemented |
| Web (Vitest/Jest) | file-path + test-name pattern (TBD) | Stub — handler not yet implemented |

**Auto-promotion when no handler**: a non-Apple platform with `test_mode ∈ {build-only, scoped}` triggers DV to auto-promote that run to `full` and log to `.context/logs/test-selection-warnings.md`:

> No selective-test handler for platform `<android|web>`. Auto-promoted to `full` for this run; selective execution will activate when a handler ships. Markers are still parsed and recorded for forward-compatibility.

`development-N.md § Decisions` records `auto_promoted_mode: full` so QA and DR see the deviation. The plan-level `test_mode` is **not** rewritten — it's a per-run override.

## Reader matrix

| Reader | What it does with markers/Selected Tests |
|--------|------------------------------------------|
| **DV** (`agents/developer.md` D2) | Parses markers; writes Selected Tests list and any warnings; runs build + smoke set in `build-only`, build + Selected Tests in `scoped`, build + Selected Tests in `full`. |
| **QA** (`agents/qa-engineer.md` Q1) | Reads `development-N.md § Selected Tests`; runs the list (build-only/scoped) or full suite (full); reads `.context/logs/test-selection-warnings.md` and copies WARN lines to `testing-N.md § Notes`. |
| **DR** (`agents/technical-lead.md`) | Reads `.context/logs/test-selection-warnings.md`; surfaces non-empty warnings as findings in `developer-review-N.md § Findings`. Does NOT execute tests. |
| **PL** (`agents/product-manager.md`) | Writes `metadata.test_mode`, `metadata.always_required_tests`, `metadata.ui_visual_check`. Does not parse markers. |
