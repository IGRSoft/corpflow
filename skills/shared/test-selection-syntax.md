---
name: test-selection-syntax
description: Inline test marker grammar for selective test execution. Reference when annotating tests, parsing markers in DV, or extending platform handlers. Defines @test-required, @depends-on, and @test-tag markers consumed by the Test Selection Gate.
effort: low
---

# Test Selection Syntax

Inline source-level markers that DV parses to compute the `Selected Tests` list consumed by QA. Companion to `skills/shared/testing-strategy.md § Test Selection Gate`.

## Markers

Three markers, written as line comments in test source files, in whatever comment syntax the
language uses (`//`, `#`, `--`). The marker text itself is identical on every platform. All three
are optional — untagged tests are treated as `@test-tag: regression` with no dependency edges (run only in `test_mode=full` or via explicit `metadata.always_required_tests`).

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

A diff that touches `PaymentService.swift` / `PaymentService.kt` / `payment_service.py` (any symbol) marks `PaymentService` as changed; a diff that touches a free function `processRefund(...)` extracts that function's name. Tests with `@depends-on: PaymentService` or `@depends-on: processRefund` are added to the Selected Tests list. Symbol names are matched as written in source, so a Python test depending on `payment_service.process_refund` writes `@depends-on: process_refund`.

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

```python
# @test-tag: smoke
# @depends-on: SessionStore
def test_login_roundtrip_stores_session(): ...
```

## Native tag equivalents

Where a framework has its own tagging mechanism, it is recognized as a first-class equivalent to
`@test-tag:` — prefer it over the comment marker, since the runner can also filter on it.

| Framework | Native tag | Equivalent to |
|-----------|-----------|---------------|
| Swift Testing | `.tags(.smoke)` | `@test-tag: smoke` |
| JUnit 5 | `@Tag("smoke")` | `@test-tag: smoke` |
| pytest | `@pytest.mark.smoke` | `@test-tag: smoke` |
| Go | `testing.Short()` guard | `@test-tag: perf` (inverse sense) |
| Vitest / Jest | none — use the comment marker | — |

`@depends-on:` has no native equivalent anywhere: dependency declarations are not a test-runner
concern. Always use the comment marker for it. Mixed style is expected and allowed.

### Swift Testing traits

Define tags once per project and reference them by `Tag` value:

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

1. **Filename correlation**: the changed source file's basename `<Name>` maps to a test filename by the language's convention — see § Test-file naming by language.
2. **Type-name correlation**: changed file declares a top-level type or exported symbol `T`; test source declares a type, class, or `describe`/`@Suite` block matching `^${T}(Tests?|Spec)$`.
3. **Module correlation** (used in `scoped` mode only — not `build-only`): test file is in the same module/target as the changed file (Swift package or Xcode test target, Gradle source set, npm workspace package, Python package, Go package directory, or sibling directory under the repo's test root).

#### Test-file naming by language

Rule 1 resolves `<Name>` through the row matching the changed file's extension. Test roots are
repo-conventional (`Tests/`, `src/test/`, `tests/`, `__tests__/`, or alongside the source).

Rust's in-file `mod tests` is the one case where "test file" and "source file" are the same
path: a changed `<name>.rs` with an inline `mod tests` always self-covers.

##### Naming table

| Language | Source | Test filename |
|----------|--------|---------------|
| Swift | `<Name>.swift` | `<Name>Tests.swift`, `<Name>Spec.swift` |
| Kotlin / Java | `<Name>.kt`, `<Name>.java` | `<Name>Test.kt`, `<Name>Tests.kt` |
| TypeScript / JS | `<name>.ts`, `<name>.tsx` | `<name>.test.ts(x)`, `<name>.spec.ts(x)` |
| Python | `<name>.py` | `test_<name>.py`, `<name>_test.py` |
| Go | `<name>.go` | `<name>_test.go` (same package directory) |
| Rust | `<name>.rs` | in-file `mod tests`, or `tests/<name>.rs` |
| Ruby | `<name>.rb` | `<name>_spec.rb`, `<name>_test.rb` |
| C / C++ | `<name>.c`, `<name>.cpp` | `test_<name>.c`, `<name>_test.cpp`, `<Name>Test.cpp` |
| Bash | `<name>.sh` | `<name>.bats` |

#### Covers rule × test mode

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

Diff: `src/components/LoginForm.tsx`, `.context/designs/figma-login-error-42-7.png`

Plan: `test_mode: build-only`, `ui_visual_check: true`

→ DV: build only, no test execution. Selected Tests = `[<from markers>]` written to development-N.md.
→ QA: runs Selected Tests + Design Comparison (gated on `ui_visual_check=true` AND designs present, independent of `test_mode`).

### Migration: untagged repository

A project with zero markers running `test_mode: build-only` produces an empty Selected Tests list (apart from `metadata.always_required_tests`). The dispatcher applies the **auto-promotion safety net** documented in `testing-strategy.md § Three test modes`: QA promotes to `scoped` for that run and writes a note to `testing-N.md § Notes`:

> Selected Tests was empty under `test_mode: build-only`. Auto-promoted to `scoped` for safety. Add `@test-required` markers or `metadata.always_required_tests` to opt back into build-only.

#### DV warning and DR surfacing

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

The marker grammar is platform-agnostic (line comments are universally parseable). What varies is
the **identifier grammar** each runner accepts and whether company-workflow has wired a handler that emits
it. Status is per-platform and load-bearing: a platform whose handler is not wired auto-promotes
to `full` (see § Auto-promotion when no handler) regardless of how well-specified its syntax is.

### Identifier grammar by platform

Apple's row is the only one an company-workflow parser emits today; the rest document the syntax a
platform handler will need.

#### Grammar — app platforms

| Platform / runner | Selection syntax | Handler status |
|-------------------|------------------|----------------|
| Apple (Swift Testing / XCTest) | `-only-testing:<Target>/<Suite>` — suite-terminal [^apple] | Wired [^divergence] |
| Android (Gradle + JUnit) | `--tests '<package>.<ClassName>'`, optionally `.<methodName>` [^android] | Documented, not wired |
| Web (Vitest / Jest) | `<file path>` positional + `-t '<name pattern>'` | Documented, not wired |
| Web E2E (Playwright) | `<file path>` positional + `-g '<title pattern>'` | Documented, not wired |

#### Grammar — systems, backend, ai runners

All rows below are documented, not wired.

| Runner | Selection syntax |
|--------|------------------|
| Python (pytest) | nodeid `<file>::<Class>::<test>`, or `-k '<expr>'` |
| Go | `-run '^<TestFunc>$'` scoped to a package path |
| Rust | `cargo test <substring>` (matches the test path) |
| C / C++ | `ctest -R '<regex>'`; GoogleTest `--gtest_filter='<Suite>.<Test>'` |
| Bash (bats) | `<file>` positional + `-f '<name regex>'` |

#### Handler status semantics

"Documented, not wired" means the syntax above is correct and safe to write into a plan or
report, but no company-workflow parser emits it yet — those runs auto-promote to module-scope at DV (see
§ Auto-promotion when no handler; never `full` — `testing-strategy.md § Test-Execution
Authority`).

### Apple identifier grammar — suite-terminal

Apple is the one platform whose grammar is a hard runner constraint rather than a convention,
so it carries the extra rule below. The other rows are ordinary filter syntax.

[^apple]: The identifier ends at a **type**, never at a function. `<SuiteName>` is an
`XCTestCase` subclass or a Swift Testing suite type, spelled as in source. Nested suites
legitimately add a segment (`Target/Outer/Inner`) — the terminal segment is still a type.

#### Why per-function forms are forbidden

Per-function forms (`/testRefundFlow`, `/testRefundFlow()`, `/testRefundFlow(amount:)`) are
**forbidden**: a Swift Testing `@Test` identifier includes the function's parentheses and
`@Test(arguments:)` appends a per-argument suffix, so `Target/Type/methodName` matches zero
Swift Testing tests — xcodebuild selects nothing and the run degrades to a full-suite fallback.
A suite flag runs the whole suite; that widening is intended, and is strictly cheaper than the
full-suite fallback it replaces. Do not "optimize" it back to per-function.

### Identifier grammar — platform asymmetries

[^android]: Android keeps a per-method form on purpose. JUnit's filter grammar has neither the
parenthesis nor the parameterized-suffix problem, so per-method selection is correct there. The
same is true of pytest nodeids, `go test -run`, and `vitest -t` — Apple's suite-terminal rule is
the exception, not the model to copy.

[^divergence]: `apple-developer:swift-testing-entry` still documents the per-function form and
lives in a separate repository. Until that follow-up lands, **this table is authoritative** for
company-workflow stages.

### Auto-promotion when no handler

A platform whose handler is not wired (every row except Apple in § Identifier grammar by platform) with `test_mode ∈ {build-only, scoped}` triggers DV to auto-promote that run to **module-scope**
(never `full` — DV holds no full-suite authority, `testing-strategy.md § Test-Execution
Authority`) and log to `.context/logs/test-selection-warnings.md`:

> No selective-test handler wired for platform `<platform>`. Auto-promoted to module-scope for this run (every test file in the touched module(s), via the platform's positional/filter syntax); selective execution will activate when a handler ships. Markers are still parsed and recorded for forward-compatibility.

#### Recording the auto-promotion

`development-N.md § Decisions` records `auto_promoted_mode: module-scope` so QA and DR see the deviation — this is a DV-artifact execution value, never a `test_mode` value. The plan-level `test_mode` is **not** rewritten — it's a per-run override. If module scope cannot be computed, DV runs the smoke set and records `deferred_to_qa: full_regression` instead.

## Reader matrix

### DV and QA

| Reader | What it does with markers/Selected Tests |
|--------|------------------------------------------|
| **DV** (`agents/developer.md` D2) | Parses markers; writes Selected Tests list and any warnings. Builds in every mode. Executes only `Executed Tests (DV)` = `Selected ∩ test files Added/Modified` (`git diff --diff-filter=AMR`) ∪ `metadata.always_required_tests`. Empty-set safety net: runs smoke set with `auto_executed: smoke_set`. See `testing-strategy.md § DV Executed vs Selected`. |
| **QA** (`agents/qa-engineer.md` Q1) | Reads `development-N.md § Selected Tests` (full list, not DV's Executed subset); runs the list (build-only/scoped) or full suite (full); reads `.context/logs/test-selection-warnings.md` and copies WARN lines to `testing-N.md § Notes`. |

### DR and PL

| Reader | What it does with markers/Selected Tests |
|--------|------------------------------------------|
| **DR** (`agents/technical-lead.md`) | Reads `.context/logs/test-selection-warnings.md` and `§ Executed at DV`; surfaces non-empty warnings as findings in `developer-review-N.md § Findings`. Does NOT execute tests — see `agents/technical-lead.md § Constraints` for the forbidden-commands list. |
| **PL** (`agents/product-manager.md`) | Writes `metadata.test_mode`, `metadata.always_required_tests`, `metadata.ui_visual_check`. Does not parse markers. |

## Footer Markers

Structured metadata blocks appended to source and test files that provide bidirectional cross-references between production code and its tests. Footer markers are **advisory** — the test selection algorithm (§ Parser algorithm) ignores them. Their purpose is human and agent traceability: developers see which tests cover a file, reviewers verify coverage intent, and QA discovers cross-dependency tests.

### Source File Footer

Appended to production source files. Provides a forward pointer from source to its covering tests.

| Field | Required | Format | Description |
|-------|----------|--------|-------------|
| `@test-file:` | yes | Relative path from project root | Primary test file for this source |
| `@related-tests:` | no | Comma-separated relative paths | Cross-dependency test files that also exercise this source |
| `@test-coverage:` | yes | Free text (single line) | Brief description of what the tests verify |

#### Source footer examples

```swift
// MARK: - Test Info
// @test-file: Tests/Services/PaymentServiceTests.swift
// @related-tests: Tests/Integration/PaymentFlowTests.swift, Tests/Services/NetworkClientTests.swift
// @test-coverage: Unit tests for charge(), refund(), and validateCard(). Integration tests for end-to-end payment flow.
```

Minimal form (no related tests), here in Python — same fields, native section idiom:

```python
# region Test Info
# @test-file: tests/services/test_payment_service.py
# @test-coverage: Unit tests for charge(), refund(), and validate_card().
```

### Test File Footer

Appended to test files. Provides a back pointer from tests to the source and relevant documentation.

| Field | Required | Format | Description |
|-------|----------|--------|-------------|
| `@source-file:` | yes | Relative path from project root | Production source file this test exercises |
| `@doc-refs:` | no | Comma-separated URLs | Platform/framework docs or other relevant documentation links |

```swift
// MARK: - Source Info
// @source-file: Sources/Services/PaymentService.swift
// @doc-refs: https://developer.apple.com/documentation/storekit, https://stripe.com/docs/api
```

Minimal form (no doc refs), here in TypeScript:

```ts
// #region Source Info
// @source-file: src/services/paymentService.ts
```

### Platform Variants

What is fixed is the **sentinel phrase** — `Test Info` / `Source Info` on a comment line, followed
by contiguous `@`-marker lines. The decoration around it is the language's own section idiom, not
Swift's. `MARK:` is an Xcode affordance and means nothing outside Swift and Objective-C — do not
export it. Where a language has no section idiom, a plain comment banner is correct.

Region forms (`region` / `#region`) fold in IntelliJ, VS Code, and PyCharm; close them with the
editor's matching `endregion` line if the file already uses that convention elsewhere.

#### Sentinel by language

| Language | Source footer sentinel | Test footer sentinel |
|----------|----------------------|---------------------|
| Swift / Objective-C | `// MARK: - Test Info` | `// MARK: - Source Info` |
| Kotlin / Java | `// region Test Info` | `// region Source Info` |
| TypeScript / JS | `// #region Test Info` | `// #region Source Info` |
| Python | `# region Test Info` | `# region Source Info` |
| Ruby | `# --- Test Info ---` | `# --- Source Info ---` |
| Go | `// --- Test Info ---` | `// --- Source Info ---` |
| Rust | `// --- Test Info ---` | `// --- Source Info ---` |
| C / C++ | `// --- Test Info ---` | `// --- Source Info ---` |
| Bash | `# --- Test Info ---` | `# --- Source Info ---` |

### Position Rules

- Footer MUST be the **last block** in the file (after all code, extensions, and closing braces).
- A blank line MUST separate the footer from preceding code.
- Footer lines are contiguous — no blank lines within the block.
- All paths are relative to project root (the directory containing `.git/`, or the nearest manifest — `Package.swift`, `settings.gradle(.kts)`, `package.json`, `pyproject.toml`, `go.mod`, `CMakeLists.txt`), use forward slashes, no leading `./`.
- Multi-value fields (`@related-tests:`, `@doc-refs:`) use comma-space (`, `) as delimiter. When the line exceeds ~120 characters, overflow to repeated marker lines: `// @related-tests: Tests/A.swift` / `// @related-tests: Tests/B.swift`. Repeated lines are additive (union of all values).

### Marker Namespace

Footer markers coexist with selection markers. The full namespace:

| Marker | Kind | Consumed by |
|--------|------|-------------|
| `@test-required` | Selection | Parser algorithm (D2) |
| `@depends-on:` | Selection | Parser algorithm (D2) |
| `@test-tag:` | Selection | Parser algorithm (D2) |
| `@test-file:` | Footer (source) | Human / agent (advisory) |
| `@related-tests:` | Footer (source) | Human / agent (advisory) |
| `@test-coverage:` | Footer (source) | Human / agent (advisory) |
| `@source-file:` | Footer (test) | Human / agent (advisory) |
| `@doc-refs:` | Footer (test) | Human / agent (advisory) |

### Parser Behavior

Footer markers are **not consumed** by the test selection algorithm. They carry no runtime semantics — `@related-tests:` does NOT cause the listed tests to be selected. Use `@depends-on:` in test files for that purpose. Missing footers produce no error; malformed footers (e.g., `@test-file:` with no path) log a warning to `.context/logs/test-selection-warnings.md` but do not affect test selection.

### Future: test-generator integration

When a plugin's test generator (`apple-developer:test-generator`, `frontend-developer:fe-test-generator`, `system-developer:sys-test-generator`, and the peers listed in `skills/shared/compatible-plugins.md § Functional-role agents`) creates new test files, it SHOULD auto-populate the `Source Info` footer with `@source-file:` pointing to the file under test and `@doc-refs:` with the relevant framework documentation URLs, in that language's section idiom. It SHOULD also emit an update instruction for the source file's `Test Info` footer. Not yet implemented — tracked for a future release.
