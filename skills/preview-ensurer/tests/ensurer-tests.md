# ensurer-tests.md — preview-ensurer fixture test matrix

Expected behavior of `PreviewEnsurer.swift` against the fixture corpus under `Fixtures/`. This is a documented contract; there is no Swift Testing or XCTest harness yet (see § Open follow-ups).

Runner — `--modified-files` takes a newline-separated list or the path of a file holding one path per line, so pass a list file, as apple-canvas does:

```
printf '%s\n' skills/preview-ensurer/tests/Fixtures/SimpleView.swift > <list-file>
swift run --package-path skills/preview-ensurer/references/reference-impl PreviewEnsurer \
  --modified-files <list-file> \
  --auto-add true \
  --project-root <repo-root>
```

The runner emits JSON matching `EnsureResult { views: [...], errors: [...] }` to stdout. Each fixture below asserts on:

1. The `views[0]` row (file/type/has_preview/action/reason/mock_strategy).
2. Side effects on the fixture file (added `#Preview` block vs. unchanged).
3. The `errors[]` array (empty on success).

Fixture files are mutated on `--auto-add true`; reset them between runs with `git checkout -- skills/preview-ensurer/tests/Fixtures/`.

---

## Test 1 — SimpleView (no params, no #Preview → auto-add)

**Input file**: `Fixtures/SimpleView.swift`

**Pre-state**: SwiftUI View struct with `body: some View { Text("Hello") }`. No `#Preview`. No initializer params.

**Expected JSON**:

```json
{
  "errors": [],
  "views": [
    {
      "file": "skills/preview-ensurer/tests/Fixtures/SimpleView.swift",
      "type": "SimpleView",
      "has_preview": false,
      "action": "added",
      "reason": null,
      "mock_strategy": "concrete-init"
    }
  ]
}
```

**Expected file mutation**: append at EOF:

```swift

#Preview {
    SimpleView()
}
```

**Expected audit row**:

```jsonc
{
  "actor": "preview-ensurer",
  "action": "preview_added",
  "subject": "SimpleView",
  "result": "ok",
  "metadata": {
    "file": "skills/preview-ensurer/tests/Fixtures/SimpleView.swift",
    "view_type": "SimpleView",
    "mock_strategy": "concrete-init",
    "lines_added": 4
  }
}
```

**Pass criteria**: JSON matches (modulo whitespace); appended block parses via `swift -frontend -parse`; original `body` declaration unchanged.

---

## Test 2 — BindingView (Binding<String> param → auto-add with .constant(""))

**Input file**: `Fixtures/BindingView.swift`

**Pre-state**: View struct with `@Binding var text: String`. No `#Preview`.

**Expected JSON**:

```json
{
  "errors": [],
  "views": [
    {
      "file": "skills/preview-ensurer/tests/Fixtures/BindingView.swift",
      "type": "BindingView",
      "has_preview": false,
      "action": "added",
      "reason": null,
      "mock_strategy": "binding-constant"
    }
  ]
}
```

**Expected file mutation**: append at EOF:

```swift

#Preview {
    BindingView(text: .constant(""))
}
```

**Pass criteria**:

- `mock_strategy == "binding-constant"`.
- Generated arg is exactly `.constant("")` (not `.constant(nil)`, not `.constant(false)`).
- File parses after edit.

> **SwiftSyntax detail**: `@Binding var text: String` desugars to an initializer parameter of type `Binding<String>` in the synthesized memberwise init. The detector's `extractParameters` infers this from the stored-property declaration.

---

## Test 3 — AmbiguousMultiView (3 top-level Views → skip with ambiguous_view_target)

**Input file**: `Fixtures/AmbiguousMultiView.swift`

**Pre-state**: file contains `HeaderView`, `BodyView`, `FooterView` — all View-conforming, all top-level. No `--view` arg provided to the runner.

**Expected JSON**:

```json
{
  "errors": [],
  "views": [
    {
      "file": "skills/preview-ensurer/tests/Fixtures/AmbiguousMultiView.swift",
      "type": "HeaderView",
      "has_preview": false,
      "action": "skipped",
      "reason": "ambiguous_view_target",
      "mock_strategy": null
    }
  ]
}
```

**Expected file mutation**: none (the file is read-only on `ambiguous_view_target`).

**Pass criteria**:

- `action == "skipped"`.
- `reason == "ambiguous_view_target"`.
- File content unchanged (verify via `git diff Fixtures/AmbiguousMultiView.swift` returns empty).

To target one View, the caller passes its type name (`--view HeaderView`); this test covers only the skip.

---

## Test 4 — Idempotence (re-run on already-modified file → action="found")

**Input file**: `Fixtures/SimpleView.swift` after Test 1 has run.

**Pre-state**: file contains the SimpleView struct AND a `#Preview { SimpleView() }` block at the bottom.

**Expected JSON**:

```json
{
  "errors": [],
  "views": [
    {
      "file": "skills/preview-ensurer/tests/Fixtures/SimpleView.swift",
      "type": "SimpleView",
      "has_preview": true,
      "action": "found",
      "reason": null,
      "mock_strategy": null
    }
  ]
}
```

**Expected file mutation**: none — an existing preview is never overwritten.

**Pass criteria**:

- `action == "found"`.
- `has_preview == true`.
- File content unchanged from Test 1's post-state.

---

## Test 5 — Comment containing `#Preview` (false-positive guard)

**Input file**: synthetic fixture (could be added as `Fixtures/CommentedPreview.swift`):

```swift
import SwiftUI

// #Preview { ContentView() }   ← commented out; should be ignored
struct ContentView: View {
    var body: some View { Text("hi") }
}
```

**Expected JSON**:

```json
{
  "errors": [],
  "views": [
    {
      "type": "ContentView",
      "has_preview": false,
      "action": "added",
      "mock_strategy": "concrete-init"
    }
  ]
}
```

**Pass criteria**: SwiftSyntax trivia (comments) is ignored by the visitor. No fixture file ships for this case yet (see § Open follow-ups).

---

## Run protocol

1. `git checkout -- skills/preview-ensurer/tests/Fixtures/` (reset).
2. For each test:
   a. Invoke runner with the test's input file.
   b. Capture stdout JSON.
   c. Compare against expected (allow whitespace differences).
   d. Verify file mutation (or absence thereof).
3. `git checkout -- skills/preview-ensurer/tests/Fixtures/` (reset for next run).

---

## Open follow-ups

- **Swift Testing harness**: convert this contract into runnable `@Test` declarations under `Tests/PreviewEnsurerTests/` once the executable is wired into a testable target.
- **CommentedPreview fixture**: add the literal file once the harness exists.
- **Generic / closure / mock-found fixtures**: extend the corpus to exercise every branch of `deriveMockArg`.
- **End-to-end**: `examples/canvas-fixture/run-e2e.sh` exercises preview-ensurer against a real-ish project.

---

## Audit-trail expectations

Via the apple-canvas adapter, each `action: "added"` view yields one `preview_added` audit row. The fixture tests assert only on the JSON return shape; audit rows are an integration concern.
