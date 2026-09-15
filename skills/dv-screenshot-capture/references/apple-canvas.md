# apple-canvas adapter

Reference for the `apple-canvas` adapter in `dv-screenshot-capture`. Renders SwiftUI `#Preview` views to PNG via `ImageRenderer` in a host-side SPM executable target (`tools/SnapshotHost/`), without booting the simulator.

> Companion: `preview-ensurer.md` (heuristics summary). The canonical contract for the cross-skill boundary lives in **this** file.

## When this adapter runs

Selected when `state.platform == "apple"` and this adapter's degraded-mode predicate fires — plan-level `metadata.requires_canvas_screenshot`, per-call `args.force_canvas`, or a sim-unavailable inference (xcframework-without-sim-slice, etc.). The dispatcher only calls `ADAPTERS["apple"]["degraded_if"]`; the clauses are the adapter's own and canonical in `../SKILL.md § apple degraded-mode predicate`. Render destination comes from `metadata.canvas_destination ∈ {"macos-host","ios-sim"}` (default `macos-host`, ad5).

## Cross-skill contract with preview-ensurer

**preview-ensurer runs BEFORE SnapshotHost**, and the apple-canvas adapter is its sole caller — never invoked directly from DV in v1 (ad8, single chokepoint).

### Function signature (canonical)

```
ensure_previews(
  modified_files: [Path],         # absolute paths from git diff --diff-filter=AMR
  options: {
    auto_add: Bool,               # default true; false = dry-run (detect only)
    write_mode: "in-source"       # OQ1 ratified; "staged-patch" unsupported in v1
  }
) → {
  views: [
    {
      file: Path,
      type: String,               # e.g. "ContentView"
      has_preview: Bool,
      action: "found" | "added" | "skipped",
      reason: String?,            # populated when action == "skipped"
      mock_strategy: String?      # populated when action == "added"; matches audit enum
    }
  ],
  errors: [String]                # non-empty → SnapshotHost run aborts; DV reports missing_input
}
```

### Invocation sequence

`Skill("dv-screenshot-capture", task_id=<TASK_ID>, platform="apple", args.force_canvas=true)` → adapter selection picks apple-canvas → `Skill("preview-ensurer", modified_files, auto_add=true)` → empty `errors` continues, non-empty throws `missing_input` (the DV completion gate appends it to `.context/errors/developer.md`) → `swift run --package-path tools/SnapshotHost SnapshotHost …` → PNG → `screenshots-<TASK_ID>.md` manifest row + `state.json` `facts.screenshots`.

### State sharing

preview-ensurer appends to `state.json → facts.previews_added[]` — `{file, type, action, mock_strategy}` per view, e.g. `{"file": "Sources/UI/ContentView.swift", "type": "ContentView", "action": "added", "mock_strategy": "binding-constant"}`. The DV summary surfaces the array, so a single `git checkout -- <file>` reverts an auto-added `#Preview`.

## Adapter inputs / outputs / audit schemas

### Inputs

| Input | Source | Required |
|---|---|---|
| `modified_files` | `git diff --name-only --diff-filter=AMR <base>...HEAD` filtered to `*.swift` under View paths | Yes |
| `args.view` | `metadata.canvas_view` or auto-derived (first View under modified_files) | No |
| `args.force_canvas` | `metadata.requires_canvas_screenshot` or explicit | No |
| `args.canvas_destination` | `metadata.canvas_destination`, default `"macos-host"` | No |
| `args.size` | `metadata.canvas_size`, default `393x852` (iPhone artboard) | No |
| `args.scheme` | `metadata.canvas_scheme ∈ {"light","dark"}`, default `light` | No |

### Outputs

The standard adapter shape (`../SKILL.md § Adapters`); `error` here is one of `null`, `"capture_failed"`, `"tool_missing"`, `"oversize_unquantizable"`.

### Audit row schema

| `action` | `phase` (when applicable) | Required `metadata` |
|---|---|---|
| `canvas_render` | `"scaffold"` | `phase`, `view`, `destination`, `swift_version` |
| `canvas_render` | `"complete"` | `phase`, `view`, `destination`, `output_path`, `bytes`, `duration_ms`, `swift_version`, `swift_syntax_version` |
| `canvas_render` | `"retry"` | `phase`, `view`, `destination`, `duration_ms`, `prev_error` |
| `preview_added` | — | `file`, `view_type`, `mock_strategy`, `lines_added` |
| `visual_diff_run` | — | `reference`, `candidate`, `metric: "RMSE"`, `value_percent`, `threshold_percent`, `verdict` |

`screenshot_platform_fallback` rows are still emitted on cascade transitions (`canvas_host_build_failed`, `canvas_sim_unavailable`, etc.).

## Failure cascade ladder

Four tiers (ad6), additive to the existing `dv-screenshot-capture` failure-mode vocabulary — apple-canvas never replaces that chain. Each transition emits its own audit row.

### Tiers

1. **SnapshotHost missing on disk** → scaffold from `templates/SnapshotHost-template/`, write the `tools/SnapshotHost/.canvas-scaffold-version` marker, retry the render, emit `canvas_render` `phase: "scaffold"`.
2. **Host build fails** (`swift build` non-zero, or exit `module_graph_sim_required`) → escalate to the `apple` (sim) adapter; `screenshot_platform_fallback`, `reason: "canvas_host_build_failed"`.
3. **Sim adapter unavailable** (`sim_unavailable(state) == true`) → `cli/fallback`; `reason: "canvas_sim_unavailable"`.
4. **preview-ensurer returned errors** → bubble as `missing_input` to the DV completion gate, append to `.context/errors/developer.md`. Do NOT render; do NOT silently skip (ad8).

## macOS host vs ios-sim destination selection (ad5)

| Destination | When to use | `Package.swift` platforms | Speed | Determinism | Font fidelity |
|---|---|---|---|---|---|
| `macos-host` (default) | All cases unless pixel-perfect Figma diff required | `.macOS(.v13)` only | <10s cold, <2s warm | High (no sim cache or simctl state) | Sub-pixel drift on SF Pro vs XCPreviewAgent |
| `ios-sim` (opt-in) | Pixel-perfect Figma comparison; project whose macOS Catalyst build path is broken | `.macOS(.v13)` + `.iOS(.v16)` | 30–90s cold (sim boot + build) | Lower (carries sim cache) | Matches XCPreviewAgent exactly |

Switch via `metadata.canvas_destination: "ios-sim"`; the scaffolder uncomments the `.iOS(.v16)` line in `Package.swift` on opt-in.

## Fidelity caveats (ImageRenderer ≠ XCPreviewAgent)

Host-side `ImageRenderer` does not match `XCPreviewAgent`'s rasterization: font metrics differ by 1–2 px on some SF Pro weights; system materials (`.ultraThinMaterial` and friends) rasterize differently; there is NO device chrome — status bar, dynamic island, bezel are absent from the clipped content rect (C5); and only a single-shot snapshot is produced (trait matrices await a future `args.trait_collections` flag).

Mitigations: pin `proposedSize = CGSize(width: 393, height: 852)` so layout is deterministic across host and sim; rely on the default 8% RMSE threshold to absorb sub-pixel drift while still catching real regressions; escape to `metadata.canvas_destination: "ios-sim"` when pixel-perfect; and for whole-screen Figma comparisons including chrome, document an inset wrapper in the project's own preview file rather than rendering chrome here (C5).

## tools/SnapshotHost/ on-disk shape

Scaffolded from the template, then committed for CI reproducibility:

```
tools/SnapshotHost/
  Package.swift                 # from templates/SnapshotHost-template/Package.swift
  Sources/SnapshotHost/
    main.swift                  # CLI: --view --output --size --scheme
    PreviewBridge.swift         # @testable import of leaf View modules; rewritten idempotently
  .canvas-scaffold-version      # plain text "1"; bumped on backward-incompatible template changes
```

## CLI contract — `swift run SnapshotHost`

```
swift run SnapshotHost
  --view <ModuleName.TypeName>          # required; key into PreviewBridge.viewRegistry
  --output <path>                       # required; absolute path to PNG destination
  [--size 393x852]                      # default 393×852 (iPhone artboard)
  [--scheme light|dark]                 # default light; affects ColorScheme env
```

### Exit codes

| Code | Meaning | Adapter handling |
|---|---|---|
| `0` | success | proceed to size budget step |
| `2` | view-key not found in `PreviewBridge.viewRegistry` | `ok: false, error: "capture_failed"`; surface key + available registry keys in the DV summary |
| `3` | `ImageRenderer` returned nil | `ok: false, error: "capture_failed"`; check the render log for a SwiftUI runtime exception |
| `4` | PNG write failed (disk full / permission denied) | `ok: false, error: "capture_failed"`; surface the filesystem error |
| Any other non-zero | unexpected | treat as `3`; log full stderr |

## Driver script

`scripts/apple-canvas.sh` is the bash driver; its flags are listed in `../SKILL.md § Script usage`. Steps, matching the cascade above:

1. Resolve the context root (`../SKILL.md § Root resolution`; unresolved or ledger mismatch → exit 1) and the output path `<ctx>/images/<worktask_id>/dv-<TASK_ID>-NN-<slug>.png` (`NN` per `../SKILL.md § Numbering`; default slug `canvas-preview`).
2. Copy `templates/SnapshotHost-template/` when `tools/SnapshotHost/Package.swift` is absent.
3. Invoke preview-ensurer; abort on errors with `missing_input`.
4. Update the `PreviewBridge.swift` viewRegistry (idempotent).
5. `swift run --package-path tools/SnapshotHost SnapshotHost --view <…> --output <…> --size <…> --scheme <…>`.
6. Apply the parent skill's 500 KB size budget (pngquant → `oversize/`), then emit the manifest row + audit JSON.

Logs land in `.context/logs/build-developer-<ts>.log` and `.context/logs/canvas-render-<ts>.log` (per logging-conventions).
