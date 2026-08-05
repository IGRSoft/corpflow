# canvas-fixture — apple-canvas end-to-end smoke fixture

Minimal SwiftUI sample project used as the P6 integration test for the
`company-workflow:dv-screenshot-capture` `apple-canvas` adapter and the
`company-workflow:preview-ensurer` skill.

## Layout

```
examples/canvas-fixture/
├── README.md                              ← this file
├── run-e2e.sh                             ← smoke harness
└── Sources/FixtureApp/Views/
    └── SimpleView.swift                   ← test target (no #Preview initially)
```

## What the smoke validates

| Acceptance criterion | Validated by |
|---|---|
| **A1** — fresh project + View + no `#Preview` → PNG produced unattended | run-e2e.sh asserts PNG file exists at expected path |
| **A4** — existing `#Preview` not overwritten | run-e2e.sh re-runs after first pass; asserts file content stable |
| **A5** — audit rows `canvas_render`, `preview_added`, (optional) `visual_diff_run` present | run-e2e.sh greps `.context/logs/audit.jsonl` |

A2 (force_canvas + sim-incompatible framework) and A3 (`design-ref.png` + RMSE)
are validated outside this fixture — A2 needs an overlay-style project, and A3
needs a Figma export. Both are scoped to QA stage per coordination-0.md §7.

## Pre-requisites

The smoke is self-contained for the preview-ensurer + auto-add path. The full
`swift run SnapshotHost` rendering step additionally requires:

- `swift` on `$PATH` (Xcode toolchain).
- macOS host (`.macOS(.v13)`+) for `ImageRenderer.cgImage`.
- For the optional RMSE diff step: `magick` (ImageMagick) on `$PATH`. The smoke
  uses graceful-degrade — missing imagemagick records `imagemagick_not_found`
  and continues without failing.

## Run

```bash
cd <repo-root>
./examples/canvas-fixture/run-e2e.sh
```

The harness creates temporary `.context/images/canvas-fixture-smoke/` (DV render
output — the RMSE candidate) and `.context/designs/canvas-fixture-smoke/` (the
optional design reference) directories, copies the fixture's `SimpleView.swift` to
a working location, invokes the apple-canvas adapter (via
`skills/dv-screenshot-capture/scripts/apple-canvas.sh`), and asserts on the audit log.

## What gets mutated

- `Sources/FixtureApp/Views/SimpleView.swift` — preview-ensurer appends a
  `#Preview { SimpleView() }` block in-source (per ad4).
- `.context/images/canvas-fixture-smoke/dv-NN-canvas-fixture.png` — rendered PNG
  (when the swift toolchain is present).
- `.context/logs/audit.jsonl` — appended `canvas_render` + `preview_added` rows.

Resetting between runs:

```bash
git checkout -- examples/canvas-fixture/Sources/FixtureApp/Views/SimpleView.swift
rm -rf .context/images/canvas-fixture-smoke .context/designs/canvas-fixture-smoke
```

## Design-ref.png (optional, for A3)

To enable RMSE verdict in the smoke, drop a reference PNG at:

```
.context/designs/canvas-fixture-smoke/design-ref.png
```

The reference lives under `.context/designs/` (design reference) and is diffed
against the DV render in `.context/images/` (candidate) — the same
`designs/`=reference, `images/`=candidate split QA uses in production. The harness
will then invoke `skills/dv-screenshot-capture/scripts/visual-diff.sh`. Without `design-ref.png`, the harness
skips the diff step.

## Limitations (v1)

- The fixture renders a static `SimpleView` only. Trait-collection / dark-mode
  matrix renders are deferred (see planning-0.md § scope.out).
- The smoke does NOT install or boot a simulator. The macOS host path is the
  canonical test surface (ad5 — OQ3 ratification).
- The smoke does NOT exercise the `apple` (sim) fallback path — that requires
  injecting a `module_graph_sim_required` exit, deferred to a more elaborate
  fixture in a future iteration.
