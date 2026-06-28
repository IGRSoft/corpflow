# apple-canvas adapter

Reference for the `apple-canvas` adapter in `dv-screenshot-capture`. Renders SwiftUI `#Preview` views to PNG via `ImageRenderer` in a host-side SPM executable target (`tools/SnapshotHost/`), without booting the simulator.

> Companion: `preview-ensurer.md` (heuristics summary). Canonical contract for the cross-skill boundary lives in **this** file.

## When this adapter runs

Selected by the Adapter Selection Rule when `state.platform == "apple"` AND (`args.force_canvas` OR `sim_unavailable(state)`). See `SKILL.md § Adapter selection rule`.

Trigger inputs:

| Source | Field | Effect |
|---|---|---|
| Plan metadata | `metadata.requires_canvas_screenshot: true` | Force canvas for the whole worktask |
| Skill call args | `args.force_canvas: true` | Force canvas for this specific invocation |
| State inference | `sim_unavailable(state) == True` | Auto-route to canvas (xcframework-without-sim-slice, etc.) |
| Plan metadata | `metadata.canvas_destination ∈ {"macos-host","ios-sim"}` | Pick render destination (default `macos-host`, ad5) |

## Cross-skill contract with preview-ensurer

**preview-ensurer runs BEFORE SnapshotHost.** The apple-canvas adapter is the sole orchestrator; preview-ensurer is never invoked directly from DV outside this adapter in v1 (ad8 — single chokepoint).

### Function signature (canonical)

```
ensure_previews(
  modified_files: [Path],         # absolute paths from git diff --diff-filter=AMR
  options: {
    auto_add: Bool,               # default true; false = dry-run (detect only)
    write_mode: "in-source"       # OQ1 ratified; "staged-patch" not supported in v1
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

```
DV → Skill("dv-screenshot-capture", platform="apple", args.force_canvas=true)
     → adapter selection → apple-canvas
       → Skill("preview-ensurer", modified_files, auto_add=true)
         ↳ result.errors empty → continue
         ↳ result.errors non-empty → throw missing_input → DV completion gate catches,
                                     appends to .context/errors/developer.md
       → swift run --package-path tools/SnapshotHost SnapshotHost ...
       → PNG → screenshots.md manifest row + state.json facts.screenshots
```

### State sharing

preview-ensurer writes to `state.json → facts.previews_added[]`:

```json
{
  "facts": {
    "previews_added": [
      { "file": "Sources/UI/ContentView.swift", "type": "ContentView", "action": "added", "mock_strategy": "binding-constant" }
    ]
  }
}
```

DV summary surfaces this array — single `git checkout -- <file>` reverts the auto-added `#Preview`.

## Adapter inputs / outputs / audit schemas

### Inputs

| Input | Source | Required |
|---|---|---|
| `modified_files` | `git diff --name-only --diff-filter=AMR <base>...HEAD` filtered to `*.swift` under View paths | Yes |
| `args.view` | `metadata.canvas_view` or auto-derived (first View under modified_files) | No |
| `args.force_canvas` | `metadata.requires_canvas_screenshot` or explicit | No |
| `args.canvas_destination` | `metadata.canvas_destination`, default `"macos-host"` | No |
| `args.size` | `metadata.canvas_size`, default `393x852` (iPhone artboard, planning risk row 3) | No |
| `args.scheme` | `metadata.canvas_scheme ∈ {"light","dark"}`, default `light` | No |

### Outputs

Returns the standard `dv-screenshot-capture` adapter shape:

```
{
  path:  ".context/images/<worktask_id>/dv-NN-<slug>.png",
  bytes: <integer>,
  ok:    Bool,
  error: null | "capture_failed" | "tool_missing" | "oversize_unquantizable"
}
```

### Audit rows

| `action` | `phase` (when applicable) | Required `metadata` |
|---|---|---|
| `canvas_render` | `"scaffold"` | `phase`, `view`, `destination`, `swift_version` |
| `canvas_render` | `"complete"` | `phase`, `view`, `destination`, `output_path`, `bytes`, `duration_ms`, `swift_version`, `swift_syntax_version` |
| `canvas_render` | `"retry"` | `phase`, `view`, `destination`, `duration_ms`, `prev_error` |
| `preview_added` | — | `file`, `view_type`, `mock_strategy`, `lines_added` |
| `visual_diff_run` | — | `reference`, `candidate`, `metric: "RMSE"`, `value_percent`, `threshold_percent`, `verdict` |

`screenshot_platform_fallback` rows continue to be emitted on cascade transitions (`canvas_host_build_failed`, `canvas_sim_unavailable`, etc.).

## Failure cascade ladder

Three-tier cascade per ad6. Each transition emits its own audit row.

```
[1] SnapshotHost missing on disk
      → scaffold from skills/dv-screenshot-capture/templates/SnapshotHost-template/
      → write tools/SnapshotHost/.canvas-scaffold-version marker
      → retry render step
      → emit canvas_render, phase: "scaffold"
      → success | proceed to [4]

[2] Host build fails (swift build non-zero, OR exit code = module_graph_sim_required)
      → escalate to `apple` (sim) adapter
      → emit screenshot_platform_fallback, reason: "canvas_host_build_failed"
      → success | proceed to [3]

[3] `apple` (sim) adapter unavailable (sim_unavailable(state) == true)
      → cli/fallback (existing skill behavior)
      → emit screenshot_platform_fallback, reason: "canvas_sim_unavailable"

[4] preview-ensurer returns errors
      → bubble as missing_input to DV completion gate
      → append to .context/errors/developer.md
      → do NOT render; do NOT silently skip (ad8)
```

The cascade is additive to the existing `dv-screenshot-capture` failure-mode vocabulary — apple-canvas never replaces the existing chain.

## macOS host vs ios-sim destination selection (ad5)

| Destination | When to use | `Package.swift` platforms | Speed | Determinism | Font fidelity |
|---|---|---|---|---|---|
| `macos-host` (default) | All cases unless pixel-perfect Figma diff required | `.macOS(.v13)` only | <10s cold, <2s warm | High (no sim cache, no simctl state) | Sub-pixel drift on SF Pro vs XCPreviewAgent |
| `ios-sim` (opt-in) | Pixel-perfect Figma comparison; project where macOS Catalyst build path is broken | `.macOS(.v13)` + `.iOS(.v16)` | 30-90s cold (sim boot + build) | Lower (carries sim cache) | Matches XCPreviewAgent exactly |

Switch via `metadata.canvas_destination: "ios-sim"`. The scaffolder uncomments the `.iOS(.v16)` line in `Package.swift` on opt-in.

## Fidelity caveats (ImageRenderer ≠ XCPreviewAgent)

`ImageRenderer` on the macOS host does not perfectly match `XCPreviewAgent`'s rasterization. Known divergences:

1. **Font metrics** — kerning, baseline shift, and dynamic-type rendering can differ by 1–2 px on certain SF Pro weights (ultralight, heavy).
2. **System background materials** — `.ultraThinMaterial` and friends rasterize differently on host vs simulator runtime.
3. **Status bar / dynamic island / device chrome** — `ImageRenderer` produces a clipped content rect; canvas snapshots have NO device chrome (constraint C5).
4. **Dynamic Type / dark-mode matrices** — single-shot snapshot only; matrix rendering deferred to a future `args.trait_collections` flag.

Mitigations:

- Pin `proposedSize = CGSize(width: 393, height: 852)` (iPhone artboard) so layout is deterministic across host/sim (risk row 3).
- Default RMSE threshold 8% absorbs sub-pixel font drift while still catching real visual regressions.
- Pixel-perfect escape hatch: `metadata.canvas_destination: "ios-sim"`.
- For whole-screen Figma comparisons that include status bar / dynamic island, document an inset wrapper in your project's preview file rather than embedding chrome rendering in this adapter (C5).

## tools/SnapshotHost/ on-disk shape

After scaffolding (and committed afterward for CI reproducibility):

```
tools/SnapshotHost/
  Package.swift                 # template from templates/SnapshotHost-template/Package.swift
  Sources/SnapshotHost/
    main.swift                  # CLI: --view --output --size --scheme
    PreviewBridge.swift         # @testable import of leaf View modules; rewritten idempotently
  .canvas-scaffold-version      # plain text "1" — bumped on backward-incompatible template changes
```

The `.canvas-scaffold-version` marker addresses the open-item from AR0 § Open Items for Downstream Stages.

## CLI contract — `swift run SnapshotHost`

```
swift run SnapshotHost
  --view <ModuleName.TypeName>          # required; key into PreviewBridge.viewRegistry
  --output <path>                       # required; absolute path to PNG destination
  [--size 393x852]                      # default 393×852 (iPhone artboard)
  [--scheme light|dark]                 # default light; affects ColorScheme env
```

Exit codes:

| Code | Meaning | Adapter handling |
|---|---|---|
| `0` | success | proceed to size budget step |
| `2` | view-key not found in PreviewBridge.viewRegistry | `ok: false, error: "capture_failed"`; surface key + available registry keys in DV summary |
| `3` | ImageRenderer returned nil | `ok: false, error: "capture_failed"`; check the render log for SwiftUI runtime exception |
| `4` | PNG write failed (disk full / permission denied) | `ok: false, error: "capture_failed"`; surface filesystem error |
| Any other non-zero | unexpected | treat as `3`; log full stderr |

## Driver script

`scripts/apple-canvas.sh` is the bash driver. Inputs:

```
--worktask-id <id>            # state.json.worktask_id
--modified-files <path>       # newline-separated file paths (typically from git diff)
--view <ModuleType>           # optional; if omitted, derived from modified_files
--destination <macos-host|ios-sim>   # optional; default macos-host
--size <WxH>                  # optional; default 393x852
--scheme <light|dark>         # optional; default light
```

Steps (matches the failure cascade above):

1. Resolve outputs path: `.context/images/<worktask_id>/dv-NN-canvas-<slug>.png` (NN per existing storage layout rules).
2. Scaffold-if-missing: copy `templates/SnapshotHost-template/` if `tools/SnapshotHost/Package.swift` absent.
3. Invoke preview-ensurer; abort on errors with `missing_input`.
4. Update `PreviewBridge.swift` viewRegistry (idempotent).
5. `swift run --package-path tools/SnapshotHost SnapshotHost --view <…> --output <…> --size <…> --scheme <…>`.
6. Apply 500 KB size budget (pngquant fallback → oversize/) — reuse parent skill logic.
7. Emit manifest row + audit JSON.

Logs land in `.context/logs/build-developer-<ts>.log` and `.context/logs/canvas-render-<ts>.log` (per logging-conventions).

