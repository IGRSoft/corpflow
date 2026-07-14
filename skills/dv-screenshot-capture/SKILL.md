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

### Path scheme rules

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

#### sim_unavailable(state) definition

Boolean, evaluated per `apple-canvas` selection:

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

#### force_canvas trigger inputs

Trigger inputs for `force_canvas`: `metadata.requires_canvas_screenshot` (plan-level) or `args.force_canvas` (skill-call-level). When both unset and `sim_unavailable(state)` is False, the legacy `apple_adapter` runs unchanged.

### Per-adapter behavior

#### apple, web, android adapters

| Adapter | Backing tool | Concrete behavior | Failure → fallback |
|---------|-------------|-------------------|--------------------|
| `apple` | `mcp__XcodeBuildMCP__screenshot` | Boot/locate simulator (per `args.simulator`), navigate best-effort, call MCP screenshot tool. Save to target path. | XcodeBuildMCP unavailable → `cli_fallback`. Audit: `screenshot_platform_fallback`, `reason: "xcodebuildmcp_unavailable"`. |
| `web` | Playwright (`npx playwright screenshot <url>`) or Chrome MCP | Launch headless browser, navigate to `args.url`, capture at `args.viewport`. | Playwright not installed → `cli_fallback`. Audit: `screenshot_platform_fallback`, `reason: "playwright_unavailable"`. |
| `android` | `adb exec-out screencap -p` | Verify device via `adb devices`, then `adb exec-out screencap -p > <path>`. | `adb` not on PATH → `cli_fallback`. Audit: `screenshot_platform_fallback`, `reason: "adb_unavailable"`. |

#### apple-canvas adapter

- **Backing tool**: `swift run SnapshotHost` (host-side SPM executable) + `Skill("preview-ensurer")`.
- **Behavior**: Scaffold `tools/SnapshotHost/` from template if missing → invoke `preview-ensurer` to auto-add `#Preview` macros to modified View files → `swift run --package-path tools/SnapshotHost SnapshotHost --view <ModuleType> --output <path> [--size WxH] [--scheme light|dark]`. macOS host first (`metadata.canvas_destination=macos-host`, default); iOS sim opt-in (`canvas_destination=ios-sim`). Emits `canvas_render` + `preview_added` audit rows. See `references/apple-canvas.md` for the full recipe and `references/preview-ensurer.md` for the heuristics summary.

##### apple-canvas failure → fallback

- Host build fail → `apple` (sim) adapter (audit `screenshot_platform_fallback`, `reason: "canvas_host_build_failed"`).
- Sim unavailable → `cli_fallback` (audit `screenshot_platform_fallback`, `reason: "canvas_sim_unavailable"`).
- preview-ensurer error → DV `missing_input`.

#### cli/fallback adapter

| Adapter | Backing tool | Concrete behavior | Failure → fallback |
|---------|-------------|-------------------|--------------------|
| `cli/fallback` (also `platform: "all"`) | `silicon` → ImageMagick → `.txt` | **Step 1**: `git diff <base>...HEAD -- <files> \| silicon --language diff --output <path>`. **Step 2** (silicon absent): `magick -background white -fill black -size 1200x800 caption:"<slug>\n\n<first 60 lines of diff>" <path>`. **Step 3** (neither available): write `<path>.txt` (still recorded in screenshots.md; `ok: false`, `error: "tool_missing"`). | None — this IS the fallback. `.txt` is the floor. |

## Scripts (canonical executables)

| Script | Invocation | Purpose |
|--------|-----------|---------|
| `scripts/cli-fallback.sh` | `bash scripts/cli-fallback.sh --worktask-id <id> --slug <kebab> [--base-ref <ref>] [--platform <p>] [--run-index <N>] [--files <path>]` | Runs the silicon→magick→.txt chain; emits `path=… bytes=… ok=… error=…` to stdout. Replaces the happy-path need to read `references/cli-fallback.md`. |
| `scripts/size-budget.sh` | `bash scripts/size-budget.sh --path <file> --worktask-id <id> [--slug <kebab>] [--project-root <dir>]` | Enforces the 5-step size budget (stat→pngquant→oversize/→warn→audit). Emits `size_audit: path=… bytes=… verdict=…` to stdout. |

Both scripts implement `--self-test` (no network, no git required). Exit codes and stdout contract are documented in each script's shdoc header.

### Scripts vs reference docs

`references/cli-fallback.md` remains as the spec (silicon/magick command examples, `.txt` schema, redaction recipe) but is **no longer needed in the happy path** — `scripts/cli-fallback.sh` is the canonical implementation. Similarly, the size-budget prose in `## Size budget` below is the authoritative spec; `scripts/size-budget.sh` is its executable form.

See `references/apple-canvas.md` for the canvas adapter contract (scaffold/preview-ensurer/render/diff) and `references/preview-ensurer.md` for the cross-skill heuristics summary.

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
```

#### Design Ref column (QA join key)

```markdown
<!-- …continued: screenshots.md manifest template -->
The trailing **`Design Ref`** column is the QA join key (Option A). It carries the
matching `figma-registry.md` row `ID` when this capture maps to a known design
frame, else `—`. See **Registry tagging** below. The column is optional and
append-only: old manifests lacking it parse fine (QA treats a missing value as `—`).
```

#### Manifest tail sections

```markdown
<!-- …continued: screenshots.md manifest template -->
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

#### Advisory semantics

This step is **advisory**: it never fails DV. A failed, missing, or ambiguous match
writes `—` and DV proceeds normally. The registry is **PM-owned** — DV reads it but
NEVER writes or back-patches it. The match is conservative by construction: when in
doubt write `—`, which routes QA to its safe live-capture fallback (never a wrong
pairing).

#### Skip manifest (requires_screenshots: false)

When `metadata.requires_screenshots: false` and DV captures nothing:

```markdown
# Screenshots — <worktask_id>

> Skipped: `metadata.requires_screenshots = false`. Rationale: <one line from PL0 or DV>.
```

### PR body attachment

**Do NOT** hand-author `![…](.context/…)` refs in the PR body — relative `.context/` paths never render in GitHub PR or issue bodies (camo image proxy fetches anonymously; private/internal raw URLs 404; relative markdown links unresolved). Root cause of the broken-image class fixed in v3.11.2.

Instead, FN runs `skills/worktask/scripts/attach-visual-evidence.sh --emit pr` and inserts its stdout between `## Test plan` and `## Notes` in the PR body. The helper hosts PNGs via the publish-helper tier order (raw → gist → none-tier note), emitting a `## Visual evidence` block with hosted URLs. It prints nothing when `metadata.requires_screenshots == false` or no captures exist (section cleanly absent). `.txt` placeholder and oversize rows become plain bullets, never image embeds. See `skills/worktask/references/conductor-attachments.md` for the full insertion contract.

#### Issue body

The orchestrator posts captures to the GitHub issue at stage-loop exit via `attach-visual-evidence.sh --post issue` (marker-deduped `gh issue comment`). FN does not write to the issue.

#### Attachment consumers

| Consumer | Stage | Action |
|----------|-------|--------|
| **FN** | FN | `attach-visual-evidence.sh --emit pr` → insert block into PR body between ## Test plan and ## Notes |
| **Orchestrator** | Post-loop exit | `attach-visual-evidence.sh --post issue` → marker-deduped `gh issue comment` on the PL-published issue (visual-evidence block only) |
| **Orchestrator** | Post-merge (PR closes) | `attach-visual-evidence.sh --post completion` → one marker-deduped comment per related issue resolved by PR closes (work-summary + visual-evidence block when captures exist; summary-only otherwise). Resolves related issues via PR-body keywords (`Closes`/`Fixes`/`Resolves #N`) ∪ `gh pr view --json closingIssuesReferences`, deduped to integers |

## Size budget

Enforced after every `capture()` call:

1. Read `result.bytes`.
2. If `bytes ≥ 500_000`: run `pngquant --quality=65-80 --force --output <path> <path>` (Bash). Re-stat.
3. If still `≥ 500_000`: move to `.context/images/<worktask_id>/oversize/` (not committed). Record link-only in `screenshots.md § Out-of-budget files`. `ok: false`, `error: "oversize_unquantizable"`. DV does NOT abort — proceeds with remaining captures.
4. If `200_000 ≤ bytes < 500_000`: emit audit row `screenshot_size_warn` with `metadata: {path, bytes}`. Keep file.
5. If `count > 5`: refuse further captures. Emit audit row `screenshot_count_exceeded`. DV stops at 5.

Budget constants: **warn ≥200 KB**, **hard fail ≥500 KB**, **cap 5 files/run**.

## Failure modes

### Gate and tool failures

| Failure | Detection | Required Behavior |
|---------|-----------|-------------------|
| `metadata.requires_screenshots: false` AND zero captures | DV completion checklist | Write `screenshots.md` with skip rationale. DV proceeds. NO `missing_screenshot_artifact` error. |
| `metadata.requires_screenshots: true` (default) AND zero captures | DV completion checklist | DV FAILS with `missing_screenshot_artifact`. Append `## DV[N] Retry [X/3]` block to `.context/errors/developer.md` (classification: `logic`). Retry: attempt `cli_fallback` once. |
| Platform tool missing (XcodeBuildMCP / Playwright / adb) | `error: "tool_missing"` from adapter | Fall back to `cli_fallback`. Audit `screenshot_platform_fallback`. Continue. |

### Fallback-floor, budget, and invocation failures

| Failure | Detection | Required Behavior |
|---------|-----------|-------------------|
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

#### screenshot_* actions

| `action` | When | Required `metadata` keys |
|----------|------|--------------------------|
| `screenshot_captured` | Successful `capture()` | `slug, path, bytes, platform, adapter` |
| `screenshot_skipped` | `metadata.requires_screenshots: false` | `reason` |
| `screenshot_platform_fallback` | Adapter differs from `state.platform` | `requested_platform, used_adapter, reason` |
| `screenshot_size_warn` | 200 KB ≤ bytes < 500 KB | `path, bytes` |
| `screenshot_size_fail` | bytes ≥ 500 KB after pngquant | `path, bytes_before, bytes_after` |
| `screenshot_count_exceeded` | 6th capture attempted | `attempted_slug` |
| `screenshot_tool_missing` | cli/fallback: no silicon, no magick | `tools_checked` |

#### canvas and visual-diff actions

| `action` | When | Required `metadata` keys |
|----------|------|--------------------------|
| `canvas_render` | Each `apple-canvas` adapter invocation (one row per phase) | `phase ∈ {"scaffold","complete","retry"}`, `view`, `destination ∈ {"macos-host","ios-sim"}`, `output_path`, `bytes`, `duration_ms`, `swift_version`, `swift_syntax_version` (optional) |
| `preview_added` | `preview-ensurer` added a `#Preview` block to source | `file`, `view_type`, `mock_strategy ∈ {"binding-constant","optional-nil","mock-found","preview-tbd"}`, `lines_added` |
| `visual_diff_run` | QA executes RMSE diff (via `scripts/visual-diff.sh`) | `reference`, `candidate`, `metric: "RMSE"`, `value_percent`, `threshold_percent`, `verdict ∈ {"pass","fail_visual_diff"}` |
