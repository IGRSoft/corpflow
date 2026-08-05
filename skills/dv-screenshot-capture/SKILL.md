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

## Live-drive verification (`ui_visual_check`)

When the plan sets `ui_visual_check: true`, static evidence alone does NOT satisfy the DV exit gate.

The principle is platform-independent: **a static or host-rendered snapshot verifies structure, not runtime presentation.** A component rendered outside the running app never executes the app's real update, layout and navigation path, so same-frame update faults, control overflow, and dropped state transitions survive it — as they survive a passing unit or state-machine test. Before handoff to DR/QA, DV MUST drive the real running app.

### Live-drive steps

1. Build and run the app on its real runtime surface (booted simulator, emulator, device, or browser session) — a host/static render is never the sole evidence for a `ui_visual_check` row.
2. Drive the app through EACH rendered substate the acceptance criteria name (default, error, empty, loading, success, and every result/review state), tapping through the real transitions rather than jumping to a state in isolation.
3. Confirm each primary control is on-screen and hittable and that transition controls actually present the next state, THEN capture from that live-driven state.

A `ui_visual_check` row whose only evidence is a static render or a passing unit test is incomplete — recapture from a live-driven run.

### What does not count, per platform

Each row is the same rule instantiated; the left column is never sufficient on its own.

| Platform | Not sufficient alone | Required |
|----------|---------------------|----------|
| apple | `#Preview` / `ImageRenderer` canvas render (the `apple-canvas` adapter) | app running on a booted simulator or device |
| web | a Storybook or other static component render | the page driven in a real browser session |
| android | a Compose `@Preview` render | app running on an emulator or device |

Platforms with no rendered UI surface (systems, backend, ai) do not set `ui_visual_check` — this gate does not apply to them.

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

One table lookup for every platform. A platform whose primary adapter can be unusable registers a **degraded-mode predicate** — a hook the dispatcher calls without knowing what it tests. No platform gets a branch of its own here.

#### Dispatch table

```python
# Entry = the adapter that normally runs + an optional degraded pair. The
# predicate belongs to the platform adapter, keeping platform-specific
# evidence out of this layer.
ADAPTERS = {
    "apple":   {"primary": apple_adapter,
                "degraded_if": apple_adapter.degraded,
                "degraded":    apple_canvas_adapter},
    "web":     {"primary": web_adapter},
    "android": {"primary": android_adapter},
}

def select_adapter(state, args):
    entry = ADAPTERS.get(state.platform)
    if entry is None:
        return cli_fallback_adapter
    predicate = entry.get("degraded_if")
    if predicate and predicate(state, args):
        return entry["degraded"]
    return entry["primary"]
```

Unknown or `"all"` platform → `cli_fallback_adapter`. Emit audit row `screenshot_platform_fallback` with `reason: "unknown_platform"`.

#### Degraded-mode predicate contract

`degraded_if(state, args) → bool`. Total, side-effect free, and safe to call when its platform's tooling is absent — a predicate that cannot decide returns `False` (run the primary adapter and let the normal fallback ladder handle a real failure).

Only `apple` registers one today; `web` and `android` have no degraded adapter to fall to, so they omit the pair and go straight to the ladder. A platform gains degraded mode by adding the two keys — no dispatcher change.

### Per-adapter behavior

#### apple, web, android adapters

These three **delegate the capture to the platform's own agent**. company-workflow no longer holds direct platform tool grants (XcodeBuildMCP and friends); the platform plugin does. So this skill asks that agent to produce a file at the target path, then stats the path itself to fill the `{path, bytes, ok, error}` contract — the return shape is unchanged.

##### Platform delegation table

Every no-file case below emits `screenshot_platform_fallback` and routes to `cli_fallback`; the last column is that row's audit `reason`.

| Adapter | Delegate to | Requested behavior | `reason` |
|---------|-------------|--------------------|----------|
| `apple` | `Task(apple-developer:ios-developer)` or the matching `macos-`/`tvos-`/`watchos-`/`visionos-developer` | Boot/locate sim (per `args.simulator`), navigate best-effort, screenshot to target path. | `xcodebuildmcp_unavailable` |
| `web` | `Task(frontend-developer:frontend-developer)` | Run `scripts/web-capture.sh --url <args.url> --viewport <args.viewport>`. | `playwright_unavailable` |
| `android` | `Task(android-developer:android-developer)` | Run `scripts/android-capture.sh [--serial <args.serial>]`. | `adb_unavailable` |

##### Scripts are the executable procedure, not a second delegation path

`web-capture.sh` and `android-capture.sh` are the executable form of the `web`/`android` rows above. They are plain CLI (`npx`, `adb`) and hold no MCP grant, so the delegated platform agent runs them exactly as a direct caller would — the delegation model is unchanged, and company-workflow still needs no platform tool grant.

##### Delegated-capture result handling

The delegate's prose reply is never the evidence — **the file is**. After the `Task` returns, stat the target path:

- File exists, non-empty → `{path, bytes: <stat>, ok: true, error: null}`. Apply the size budget as usual.
- No file, empty file, or the `Task` itself errored → fall through the ladder to `cli_fallback` exactly as a missing tool did before. When the platform agent could not be reached at all, use `reason: "delegation_unavailable"` instead of the tool-specific reason above.

The error enum is unchanged: a delegated capture that fails still surfaces as `"capture_failed"` (or `"tool_missing"` once `cli_fallback` also bottoms out).

#### apple-canvas adapter

- **Backing tool**: `swift run SnapshotHost` (host-side SPM executable) + `Skill("preview-ensurer")`.
- **Behavior**: Scaffold `tools/SnapshotHost/` from template if missing → invoke `preview-ensurer` to auto-add `#Preview` macros to modified View files → `swift run --package-path tools/SnapshotHost SnapshotHost --view <ModuleType> --output <path> [--size WxH] [--scheme light|dark]`. macOS host first (`metadata.canvas_destination=macos-host`, default); iOS sim opt-in (`canvas_destination=ios-sim`). Emits `canvas_render` + `preview_added` audit rows. See `references/apple-canvas.md` for the full recipe and `references/preview-ensurer.md` for the heuristics summary.

##### apple degraded-mode predicate

Registered as `ADAPTERS["apple"]["degraded_if"]`. It is Apple-adapter-owned on purpose: the xcodebuild log scrape below is exactly the platform detail the generic dispatcher must not carry.

```python
def degraded(state, args) -> bool:
    return bool(
        args.get("force_canvas")                         # skill-call-level opt-in
        or state.metadata.get("requires_canvas_screenshot")   # plan-level opt-in
        or state.facts.get("simulator_blocked") is True       # explicit project marker
        or _grep_recent_log(r"framework not found .* iphonesimulator")
        or state.facts.get("last_sim_boot_failed") is True    # set on a prior boot failure
    )
```

The log scrape reads the most recent xcodebuild log under `.context/logs/` and catches the xcframework-missing-sim-slice case (C1). When every clause is false, the sim-booting `apple` adapter runs unchanged.

##### apple-canvas failure → fallback

- Host build fail → `apple` (sim) adapter (audit `screenshot_platform_fallback`, `reason: "canvas_host_build_failed"`).
- Sim unavailable → `cli_fallback` (audit `screenshot_platform_fallback`, `reason: "canvas_sim_unavailable"`).
- preview-ensurer error → DV `missing_input`.

#### cli/fallback adapter

| Adapter | Backing tool | Concrete behavior | Failure → fallback |
|---------|-------------|-------------------|--------------------|
| `cli/fallback` (also `platform: "all"`) | `silicon` → ImageMagick → `.txt` | **Step 1**: `git diff <base>...HEAD -- <files> \| silicon --language diff --output <path>`. **Step 2** (silicon absent): `magick -background white -fill black -size 1200x800 caption:"<slug>\n\n<first 60 lines of diff>" <path>`. **Step 3** (neither available): write `<path>.txt` (still recorded in screenshots.md; `ok: false`, `error: "tool_missing"`). | None — this IS the fallback. `.txt` is the floor. |

## Scripts (canonical executables)

Five shipped executables. Every one takes `--worktask-id` and `--slug`, resolves the next `NN` itself, and writes to `.context/images/<worktask_id>/dv-NN-<slug>.png`.

### `scripts/web-capture.sh`

```bash
bash scripts/web-capture.sh --worktask-id <id> --slug <kebab> --url <url> \
  [--viewport WxH] [--browser chromium|firefox|webkit] [--timeout <ms>] \
  [--wait-ms <ms>] [--full-page] [--platform <p>] [--run-index <N>] [--allow-npx-install]
```

Drives Playwright's `screenshot` CLI. Playwright absent → exit 2, audit `reason: "playwright_unavailable"`; navigation failure or timeout → exit 3, `reason: "playwright_navigation_failed"` / `"playwright_timeout"`.

Playwright is resolved as a `playwright` binary on PATH, else the local package via `npx --no-install`. `--allow-npx-install` opts into `npx --yes` fetching it; without that flag a missing package degrades down the ladder instead of reaching the network mid-DV.

### `scripts/android-capture.sh`

```bash
bash scripts/android-capture.sh --worktask-id <id> --slug <kebab> \
  [--serial <serial>] [--platform <p>] [--run-index <N>]
```

Resolves exactly one online device from `adb devices`, then `adb exec-out screencap -p`. `adb` absent → exit 2, `reason: "adb_unavailable"`. Exit 3 covers `no_device_attached`, `multiple_devices` (pass `--serial`), `serial_not_found`, `screencap_failed`, and `screencap_corrupt`.

Offline and unauthorized entries are not counted as devices — they cannot be captured from, so counting them would turn "authorize the device" into a spurious ambiguity error. The result is verified against the 8-byte PNG signature: a mangled stream is deleted rather than indexed into the manifest.

### `scripts/apple-canvas.sh`

```bash
bash scripts/apple-canvas.sh --worktask-id <id> --modified-files <path> \
  [--view <Module.Type>] [--destination macos-host|ios-sim] \
  [--size WxH] [--scheme light|dark] [--slug <kebab>]
```

Scaffolds `tools/SnapshotHost/` from template, invokes `preview-ensurer`, renders via `swift run SnapshotHost`. Prints the PNG path on success. Exit 2 = preview-ensurer errors (`missing_input`), 3 = render failed (escalate to the sim adapter), 4 = scaffold failed, 5 = argument error.

### `scripts/cli-fallback.sh`

```bash
bash scripts/cli-fallback.sh --worktask-id <id> --slug <kebab> \
  [--base-ref <ref>] [--platform <p>] [--run-index <N>] [--files <path>]
```

Runs the silicon→magick→`.txt` chain; emits `path=… bytes=… ok=… error=…` to stdout. Replaces the happy-path need to read `references/cli-fallback.md`.

### `scripts/size-budget.sh`

```bash
bash scripts/size-budget.sh --path <file> --worktask-id <id> \
  [--slug <kebab>] [--project-root <dir>]
```

Enforces the 5-step size budget (stat→pngquant→`oversize/`→warn→audit). Emits `size_audit: path=… bytes=… verdict=…` to stdout.

### Script conventions

`cli-fallback.sh`, `web-capture.sh`, `android-capture.sh`, and `size-budget.sh` implement `--self-test` — fixture-driven, needing no network, git, browser, or device. Exit codes and the stdout contract are documented in each script's shdoc header.

The three capture scripts share one exit-code grammar: **0** success, **1** bad arguments, **2** `tool_missing`, **3** `capture_failed`. Exits 2 and 3 still print a well-formed contract line carrying the intended `path` with `bytes=0`, and emit a `screenshot_platform_fallback` audit row — a missing tool degrades down the ladder, it never hard-fails DV.

### Adapter maturity (read the tables honestly)

Every adapter except `apple` now ships an executable. What actually ships:

| Adapter | Shipped as | Notes |
|---------|-----------|-------|
| `cli/fallback` | Executable script (`scripts/cli-fallback.sh`) + `references/cli-fallback.md` | The floor; always available |
| `apple-canvas` | Executable script (`scripts/apple-canvas.sh`) + templates + `Skill("preview-ensurer")` + a 237-line `references/apple-canvas.md` | The most specified adapter |
| `web` | Executable script (`scripts/web-capture.sh`), self-tested | Playwright CLI; no reference doc |
| `android` | Executable script (`scripts/android-capture.sh`), self-tested | `adb` CLI; no reference doc |
| `apple` | Prose procedure (delegated `Task`) | No script — the only remaining prose-only adapter |

#### Parity status

`web` and `android` reached parity with `cli/fallback`: each is a real script with a `--self-test`, the shared exit-code grammar, and an audit row on every degradation path. A failure there is now a reportable tool or device condition, not under-specified tooling.

`apple` remains prose on purpose: booting a simulator and driving the running app needs the XcodeBuildMCP grant this skill deliberately does not hold. Treat an `apple` failure as before — fall through to `cli_fallback`.

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

**Do NOT** hand-author `![…](.context/…)` refs in the PR body — relative `.context/` paths never render in GitHub PR or issue bodies (camo image proxy fetches anonymously; private/internal raw URLs 404; relative markdown links unresolved).

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
| Platform capture produced no file (delegate unreachable, or its tooling — XcodeBuildMCP / Playwright / adb — missing) | Target path absent or empty after the delegated `Task`; `error: "tool_missing"` from adapter | Fall back to `cli_fallback`. Audit `screenshot_platform_fallback`. Continue. |

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
| `canvas_render` | Each canvas-adapter invocation (one row per phase) | `phase ∈ {"scaffold","complete","retry"}`, `view`, `destination`, `output_path`, `bytes`, `duration_ms` |
| `preview_added` | `preview-ensurer` added a `#Preview` block to source | `file`, `view_type`, `mock_strategy ∈ {"binding-constant","optional-nil","mock-found","preview-tbd"}`, `lines_added` |
| `visual_diff_run` | QA executes RMSE diff (via `scripts/visual-diff.sh`) | `reference`, `candidate`, `metric: "RMSE"`, `value_percent`, `threshold_percent`, `verdict ∈ {"pass","fail_visual_diff"}` |

##### Adapter-scoped `canvas_render` extras

The keys above are the contract every canvas adapter satisfies. Toolchain identifiers are the reporting adapter's own business and are optional additions, never contract-level:

- `apple-canvas` also records `swift_version` and `swift_syntax_version`, and uses `destination ∈ {"macos-host","ios-sim"}`.
- A future canvas adapter on another platform records its own toolchain keys and its own `destination` values instead.
