---
name: dv-screenshot-capture
description: |
  Capture screenshots during the DV stage and attach to the PR as visual evidence for QA and DR.
  ALWAYS use this skill when DV is about to complete and `metadata.requires_screenshots` is true
  (default) — the completion gate fails otherwise.
version: 1.0.0
effort: medium
argument-hint: "<worktask_id> <platform> <slug> [args-json]"
keep-coding-instructions: true
---

# dv-screenshot-capture

Capture and attach visual evidence during the DV (Development) stage. One screenshot per acceptance criterion with a visual manifestation; one annotated `git diff` for meta-work. Gate DV completion on screenshot presence when `metadata.requires_screenshots` is true (default).

## Trigger conditions

Run this skill under any of the following conditions:

1. **DV completion gate** — DV is about to execute its Completion Verification checklist AND `metadata.requires_screenshots ≠ false`.
2. **Retroactive QA/DR request** — QA or DR has appended a `screenshot_request` line to `.context/errors/developer.md` referencing a missing visual.
3. **ST retrospective re-run** — ST stage flagged "missing visual evidence" as a learning and a re-run is invoked.
4. **Manual user request** — "capture a screenshot of X".

## Storage layout

```
.context/images/<worktask_id>/
├── dv-01-<slug>.png        # first capture (or .txt placeholder)
├── dv-02-<slug>.png        # second capture
├── …
├── dv-05-<slug>.png        # maximum 5 per run
├── oversize/               # .gitignore'd; oversize PNGs moved here
└── screenshots.md          # REQUIRED manifest — single source of truth
```

**Path scheme rules**:
- `<worktask_id>` from `state.json.worktask_id`.
- `NN` is **two-digit zero-padded**, monotonically increasing within a worktask. First capture = `01`.
- `<slug>` is kebab-case, ≤40 chars, derived from purpose.
- Numbering: scan existing `dv-*.png` in folder; `NN = max_existing + 1`.
- Across reruns (`run_index > 0`): do NOT reset counter. New captures append (`dv-06-…`). Archival cleanup at FN/ST or via `/worktask archive`.
- `oversize/` subdirectory must be excluded from git. Before the first move to `oversize/`, append `.context/images/*/oversize/` to `.gitignore` if not already present:
  ```bash
  grep -qxF '.context/images/*/oversize/' .gitignore 2>/dev/null || echo '.context/images/*/oversize/' >> .gitignore
  ```
  PNGs inside are NOT committed.

## What to capture

| Scenario | Capture strategy |
|----------|-----------------|
| UI feature (apple/web/android) | Golden-path state after implementation; key edge cases; before+after for bug fixes |
| Meta-work (skill/agent edits) | Annotated `git diff <base>...HEAD` rendered as PNG via `silicon` |
| Backend-only change | CLI output showing key behavior; or `git diff` render |
| Multiple ACs with visual manifestations | One screenshot per AC (up to 5 total per run) |
| Bug fix | Before (reproduce) + after (fixed) pair; counts as 2 |

Minimum: **1 screenshot** per worktask run (when `metadata.requires_screenshots: true`).
Maximum: **5 screenshots** per run (skill enforces; 6th call returns `error: "screenshot_count_exceeded"`).

## Adapters

Uniform contract — all adapters implement the same return shape:

```
capture(slug: string, platform: string, args: object) → {
  path:  string,     # .context/images/<worktask_id>/dv-NN-<slug>.png (or .txt)
  bytes: integer,    # filesystem size of produced file (0 if .txt placeholder)
  ok:    boolean,
  error: string | null   # null on success; values below
}
```

**Error values**: `"no_adapter"` | `"oversize_unquantizable"` | `"tool_missing"` | `"capture_failed"` | `"screenshot_count_exceeded"`

### Adapter selection rule

```python
# When state.platform == "apple", choose between sim-booting `apple` adapter
# and host-rendering `apple-canvas` adapter (no sim boot, ImageRenderer-based).
# Canonical pseudocode — see references/apple-canvas.md for the full contract.
if state.platform == "apple":
    if args.get("force_canvas") or sim_unavailable(state):
        adapter = apple_canvas_adapter
    else:
        adapter = apple_adapter
else:
    adapter = ({
        "web":     web_adapter,
        "android": android_adapter,
    }).get(state.platform, cli_fallback_adapter)
```

Unknown or `"all"` platform → `cli_fallback_adapter`. Emit audit row `screenshot_platform_fallback` with `reason: "unknown_platform"`.

**`sim_unavailable(state)` definition** (boolean, evaluated per `apple-canvas` selection):

```python
def sim_unavailable(state) -> bool:
    # True when ANY of:
    #   1. state.facts.simulator_blocked == True (explicit project marker)
    #   2. Most recent xcodebuild log under .context/logs/ contains the regex
    #      r"framework not found .* iphonesimulator" (xcframework missing sim slice — C1)
    #   3. state.facts.last_sim_boot_failed == True (set by adapter on prior boot failure)
    return (
        state.facts.get("simulator_blocked") is True
        or _grep_recent_log(r"framework not found .* iphonesimulator")
        or state.facts.get("last_sim_boot_failed") is True
    )
```

Trigger inputs for `force_canvas`: `metadata.requires_canvas_screenshot` (plan-level) or `args.force_canvas` (skill-call-level). When both unset and `sim_unavailable(state)` is False, the legacy `apple_adapter` runs unchanged.

### Per-adapter behavior

| Adapter | Backing tool | Concrete behavior | Failure → fallback |
|---------|-------------|-------------------|--------------------|
| `apple` | `mcp__XcodeBuildMCP__screenshot` | Boot/locate simulator (per `args.simulator`), navigate best-effort, call MCP screenshot tool. Save to target path. | XcodeBuildMCP unavailable → `cli_fallback`. Audit: `screenshot_platform_fallback`, `reason: "xcodebuildmcp_unavailable"`. |
| `apple-canvas` | `swift run SnapshotHost` (host-side SPM executable) + `Skill("preview-ensurer")` | Scaffold `tools/SnapshotHost/` from template if missing → invoke `preview-ensurer` to auto-add `#Preview` macros to modified View files → `swift run --package-path tools/SnapshotHost SnapshotHost --view <ModuleType> --output <path> [--size WxH] [--scheme light\|dark]`. macOS host first (`metadata.canvas_destination=macos-host`, default); iOS sim opt-in (`canvas_destination=ios-sim`). Emits `canvas_render` + `preview_added` audit rows. See `references/apple-canvas.md` for the full recipe and `references/preview-ensurer.md` for the heuristics summary. | Host build fail → `apple` (sim) adapter (audit `screenshot_platform_fallback`, `reason: "canvas_host_build_failed"`). Sim unavailable → `cli_fallback` (audit `screenshot_platform_fallback`, `reason: "canvas_sim_unavailable"`). preview-ensurer error → DV `missing_input`. |
| `web` | Playwright (`npx playwright screenshot <url>`) or Chrome MCP | Launch headless browser, navigate to `args.url`, capture at `args.viewport`. | Playwright not installed → `cli_fallback`. Audit: `screenshot_platform_fallback`, `reason: "playwright_unavailable"`. |
| `android` | `adb exec-out screencap -p` | Verify device via `adb devices`, then `adb exec-out screencap -p > <path>`. | `adb` not on PATH → `cli_fallback`. Audit: `screenshot_platform_fallback`, `reason: "adb_unavailable"`. |
| `cli/fallback` (also `platform: "all"`) | `silicon` → ImageMagick → `.txt` | **Step 1**: `git diff <base>...HEAD -- <files> \| silicon --language diff --output <path>`. **Step 2** (silicon absent): `magick -background white -fill black -size 1200x800 caption:"<slug>\n\n<first 60 lines of diff>" <path>`. **Step 3** (neither available): write `<path>.txt` (still recorded in screenshots.md; `ok: false`, `error: "tool_missing"`). | None — this IS the fallback. `.txt` is the floor. |

See `references/cli-fallback.md` for silicon command examples, magick template, and `.txt` placeholder schema. See `references/apple-canvas.md` for the canvas adapter contract (scaffold/preview-ensurer/render/diff) and `references/preview-ensurer.md` for the cross-skill heuristics summary.

## Attachment

### screenshots.md manifest (REQUIRED)

The manifest is the authoritative index. It is rewritten atomically on every skill invocation — never edited piecemeal.

```markdown
# Screenshots — <worktask_id>

> Authored by DV stage via `dv-screenshot-capture` skill. Run index: <N>.

| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |
|---|------|------|-------|----------|---------|---------|----------|------------|
| 01 | <slug> | dv-01-<slug>.png | 187234 | apple | apple_adapter | <one-line caption> | <ISO-8601 UTC> | design-002 |
| 02 | <slug> | dv-02-<slug>.txt | 0      | all   | cli_fallback (.txt) | tool_missing: silicon and magick absent | <ISO-8601 UTC> | — |

The trailing **`Design Ref`** column is the QA join key (Option A). It carries the
matching `figma-registry.md` row `ID` when this capture maps to a known design
frame, else `—`. See **Registry tagging** below. The column is optional and
append-only: old manifests lacking it parse fine (QA treats a missing value as `—`).

## Fallbacks invoked

- dv-02: silicon and ImageMagick both absent on PATH; .txt placeholder written.

## Out-of-budget files (link-only)

- (none) | <path>: <bytes> after quantize, exceeds 500 KB
```

### Registry tagging (`Design Ref` resolution — advisory)

When `.context/designs/figma-registry.md` exists at capture time, resolve each
capture's `Design Ref` so QA can reuse the result image instead of re-capturing:

1. Determine the capture's intended **Screen** and **State** (from the slug / capture
   purpose / the AC it satisfies).
2. Find the registry row whose `Screen` **and** `State` both equal the capture's
   Screen+State. On a unique match, write that row's `ID` (e.g. `design-002`) into
   `Design Ref`.
3. **Overview rows (`State: overview`) are NEVER a match target** — they are
   container-completeness references, not per-state result frames. Skip them.
4. No registry, no unique match, or an ambiguous (multi-row) match → write `—`.

This step is **advisory**: it never fails DV. A failed, missing, or ambiguous match
writes `—` and DV proceeds normally. The registry is **PM-owned** — DV reads it but
NEVER writes or back-patches it. The match is conservative by construction: when in
doubt write `—`, which routes QA to its safe live-capture fallback (never a wrong
pairing).

When `metadata.requires_screenshots: false` and DV captures nothing:

```markdown
# Screenshots — <worktask_id>

> Skipped: `metadata.requires_screenshots = false`. Rationale: <one line from PL0 or DV>.
```

### PR body attachment

DV's FN-pre handoff (or FN agent) inserts into the PR body:

```markdown
## Visual evidence

See [screenshots.md](.context/images/<worktask_id>/screenshots.md) for the full manifest.

![dv-01 <caption>](.context/images/<worktask_id>/dv-01-<slug>.png)
![dv-02 <caption>](.context/images/<worktask_id>/dv-02-<slug>.png)
```

GitHub renders inline `![…]` refs on public repos and same-org private repos. The manifest link works on any forge (portability floor). Non-GitHub forge URL forms are deferred (out of scope this version).

## Size budget

Enforced after every `capture()` call:

1. Read `result.bytes`.
2. If `bytes ≥ 500_000`: run `pngquant --quality=65-80 --force --output <path> <path>` (Bash). Re-stat.
3. If still `≥ 500_000`: move to `.context/images/<worktask_id>/oversize/` (not committed). Record link-only in `screenshots.md § Out-of-budget files`. `ok: false`, `error: "oversize_unquantizable"`. DV does NOT abort — proceeds with remaining captures.
4. If `200_000 ≤ bytes < 500_000`: emit audit row `screenshot_size_warn` with `metadata: {path, bytes}`. Keep file.
5. If `count > 5`: refuse further captures. Emit audit row `screenshot_count_exceeded`. DV stops at 5.

Budget constants: **warn ≥200 KB**, **hard fail ≥500 KB**, **cap 5 files/run**.

## Failure modes

| Failure | Detection | Required Behavior |
|---------|-----------|-------------------|
| `metadata.requires_screenshots: false` AND zero captures | DV completion checklist | Write `screenshots.md` with skip rationale. DV proceeds. NO `missing_screenshot_artifact` error. |
| `metadata.requires_screenshots: true` (default) AND zero captures | DV completion checklist | DV FAILS with `missing_screenshot_artifact`. Append `## DV[N] Retry [X/3]` block to `.context/errors/developer.md` (classification: `logic`). Retry: attempt `cli_fallback` once. |
| Platform tool missing (XcodeBuildMCP / Playwright / adb) | `error: "tool_missing"` from adapter | Fall back to `cli_fallback`. Audit `screenshot_platform_fallback`. Continue. |
| All adapters fail including `cli_fallback` (no silicon, no magick) | `cli_fallback` returns `ok: false, error: "tool_missing"` | Write `.txt` placeholder. Audit `screenshot_tool_missing`. screenshots.md records it. DV completion counts this as evidence-of-attempt — the gate measures evidence, not visual fidelity. |
| Size budget exceeded after pngquant | `oversize_unquantizable` | Move to `oversize/`, link-only in screenshots.md. Continue. |
| 5-cap reached | `screenshot_count_exceeded` | Stop further captures. Audit row. Continue. |
| `Skill()` invocation itself fails | DV catches exception | Escalate per `commands/worktask.md § Error Handling`. Append to `.context/errors/developer.md` (classification: `transient` for retry; `logic` for escalate to AR). Do NOT silently treat as success. |

## Redaction

When using the `cli/fallback` adapter, the `git diff` pipe may expose env files, tokens, or secrets that happen to appear in the diff. Apply the same redaction discipline as `logging-conventions § Bash Pattern` — redact secrets before piping to `silicon` or `magick`. If a sensitive pattern is detected in the diff, capture the file tree (`git diff --name-only`) instead of the full diff content.

## Consumers

| Consumer | Stage | What they read | Where they write |
|----------|-------|----------------|-----------------|
| **DV** | DV | Captures; writes `screenshots.md` + `state.json → facts.screenshots[]` | `development-N.md § Decisions` + audit.jsonl |
| **DR** | DR | `screenshots.md` (count, first filename, fallbacks, oversize notes) | `developer-review-N.md § Findings` |
| **QA** | QA | `screenshots.md` + each PNG/txt. The `Design Ref` column joins each result image to a `figma-registry.md` row `ID`; `screenshots.md` is now the **RMSE result-image source** for QA's Registry-Driven Design Comparison (the `--candidate` for `scripts/visual-diff.sh`). Live re-capture is QA's fallback only. | `testing-N.md § Visual Evidence` + `§ Design Comparison` |

### state.json registration schema

```json
{
  "facts": {
    "screenshots": [
      {
        "slug": "storage-layout",
        "path": ".context/images/dv-screenshot-capability/dv-01-storage-layout.png",
        "bytes": 187234,
        "platform": "all",
        "ok": true
      }
    ]
  }
}
```

Array max 5 items. Eviction: cleared on worktask archival (FN/ST), not within a run. Follows `facts.files_read` precedent.

### Audit actions emitted by this skill

| `action` | When | Required `metadata` keys |
|----------|------|--------------------------|
| `screenshot_captured` | Successful `capture()` | `slug, path, bytes, platform, adapter` |
| `screenshot_skipped` | `metadata.requires_screenshots: false` | `reason` |
| `screenshot_platform_fallback` | Adapter differs from `state.platform` | `requested_platform, used_adapter, reason` |
| `screenshot_size_warn` | 200 KB ≤ bytes < 500 KB | `path, bytes` |
| `screenshot_size_fail` | bytes ≥ 500 KB after pngquant | `path, bytes_before, bytes_after` |
| `screenshot_count_exceeded` | 6th capture attempted | `attempted_slug` |
| `screenshot_tool_missing` | cli/fallback: no silicon, no magick | `tools_checked` |
| `canvas_render` | Each `apple-canvas` adapter invocation (one row per phase) | `phase ∈ {"scaffold","complete","retry"}`, `view`, `destination ∈ {"macos-host","ios-sim"}`, `output_path`, `bytes`, `duration_ms`, `swift_version`, `swift_syntax_version` (optional) |
| `preview_added` | `preview-ensurer` added a `#Preview` block to source | `file`, `view_type`, `mock_strategy ∈ {"binding-constant","optional-nil","mock-found","preview-tbd"}`, `lines_added` |
| `visual_diff_run` | QA executes RMSE diff (via `scripts/visual-diff.sh`) | `reference`, `candidate`, `metric: "RMSE"`, `value_percent`, `threshold_percent`, `verdict ∈ {"pass","fail_visual_diff"}` |
