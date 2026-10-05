# QA Design Comparison (Visual QA) Procedure

Registry-driven design-comparison procedure for the QA stage. Read it only when the visual gate is open: `metadata.ui_visual_check: true` in `<plan_file>` and design references in `.context/designs/` (equivalently, `requires_screenshots: true`). The gate check and the `testing-N.md § Visual Evidence` schema live in `agents/qa-engineer.md`.

## Registry-Driven Comparison (Primary Path)

If `.context/designs/figma-registry.md` exists it is authoritative: parse its Entries table and compare row by row. The primary comparison source is the DV-captured result images, with the RMSE pixel diff (`skills/dv-screenshot-capture/scripts/visual-diff.sh`) as an objective pre-pass before multimodal vision. Live capture is the fallback, only when no DV image maps to the row (§ Implementation Screenshot Capture (fallback only)).

### Join Key (Design Ref)

Join `screenshots-*.md.Design Ref → figma-registry.md.ID` by explicit ID equality, over the optional `Design Ref` column on DV's per-task `.context/images/<worktask_id>/screenshots-<TASK_ID>.md` manifests (every task's, plus a legacy `screenshots.md`). Missing column or value = `—` (no candidate → fallback). The two blocks below are one loop.

### Per-Row Algorithm — Skip, Overview, Join

```
for each registry row R:
  if R missing ID | Screenshot | Target File(s):   # parser tolerance
      log missing_input → .context/errors/qa-engineer.md; continue
  if R.State == "overview":                        # container layout only — vision, NO RMSE
      emit_row(R, multimodal_layout_check(R), rmse=None); continue
  candidates = screenshots-*.md rows where (Design Ref == R.ID) # absent col / all "—" → ∅
  if candidates == ∅:                              # (d) live-capture fallback
      impl = build_run_sim → navigate(R.Target File(s)) → screenshot   # § fallback-only below
      emit_row(R, reconcile(None, multimodal_compare(R.Screenshot, impl)),
               source="live-capture"); continue
```

### Per-Row Algorithm — DV-Image Branch

```
# …continued: same loop, DV-image branch
  dv_img = newest_non_placeholder_png(candidates)   # log extra candidates to § Notes
  if dv_img is .txt / non-png placeholder:
      rmse = None; vision = multimodal_compare(R.Screenshot, dv_img-or-live)
  else:
      run skills/dv-screenshot-capture/scripts/visual-diff.sh \
          --reference .context/designs/<R.Screenshot> --candidate <dv_img> \
          --threshold 8 --worktask-id <worktask_id> --slug <R.ID>   # emits visual_diff_run
      rmse   = parse stdout "verdict=<pass|fail_visual_diff> value=<N>%"
      vision = multimodal_compare(R.Screenshot, dv_img)             # SAME image as RMSE
  emit_row(R, reconcile(rmse, vision), source="dv-result-image")
```

`visual-diff.sh` self-degrades: `magick` absent → `verdict=skipped reason=imagemagick_not_found`, exit 0; the row proceeds vision-only, non-blocking.

## Per-Frame Comparison

A container produces one `State: overview` row plus one row per child frame, each keyed on its own `Figma Node` id (`skills/shared/figma-capture.md § Registry Generation`). The `overview` row is the container reference, checked vision-only for layout completeness (all frames present). Each child-frame row runs the per-row algorithm against its own `.context/designs/<Screenshot>` file, state by state (default/error/empty/loading/success/…), not against one combined screenshot.

Emit one Design Comparison row per registry row, so an N-frame container yields N+1 rows and a mismatch on one frame never masks matches on the others. A leaf (single-screen) registry has no overview row and yields one row.

## Fallback: Glob Discovery (no registry)

No registry: glob `.context/designs/figma-*.png` and compare what's there. Flag the gap in `testing-N.md § Design Comparison`:

> No `figma-registry.md` found; using glob fallback. Screen/state/target mapping inferred from filenames only.

Pencil `.pen` mockups (`.context/designs/mockup-*.pen`) are compared independently of the Figma registry: load Pencil tools via `ToolSearch({ query: "+pencil" })`, then render with `mcp__pencil__get_screenshot({ filePath, nodeId })`.

## Implementation Screenshot Capture (fallback only)

Runs only when no DV result image maps to a registry row (absent `Design Ref` column, all `—`, or no PNG candidate). `build_run_sim` past ~2 min auto-backgrounds: await the completion notification, not the returned handle, before navigating or screenshotting (`skills/agent-coordination/SKILL.md § MCP Auto-Background`).

### Per-platform capture

| Platform | Capture |
|----------|---------|
| Apple | `mcp__XcodeBuildMCP__build_run_sim` (or `build_run_macos`) → navigate to target screen → `mcp__XcodeBuildMCP__screenshot` |
| Web | Load chrome tools via `ToolSearch({ query: "select:mcp__claude-in-chrome__computer" })` → screenshot |
| Android | `adb devices` to confirm an attached emulator/device → launch the app → navigate to target screen → `adb exec-out screencap -p > <path>` |
| Other (systems / backend / ai) | No live UI surface to drive. Reuse the DV capture recorded in a `screenshots-<TASK_ID>.md`; if none maps, render the change via `skills/dv-screenshot-capture/scripts/cli-fallback.sh --task-id <QA task id>` and compare behaviour, not pixels |

## Visual Comparison

`Read` both the design screenshot and the implementation screenshot; multimodal vision compares layout and spacing, color accuracy, typography (size, weight, line height), component presence and positioning, state representation (default, error, empty, loading), and icon/image placement.

### Severity Taxonomy (canonical)

- **Critical**: Layout broken, missing components, unusable state
- **Major**: Noticeable visual difference — wrong colors, spacing off by > 8px, wrong copy
- **Minor**: Subtle spacing or color difference, typography nuance

## Evidence integrity (direct-read before accepting)

Captions and manifest rows are self-reported, and a stale, placeholder or unrelated image can carry a plausible caption. When a prior stage offers a screenshot as acceptance-criteria proof, open the image with `Read` and confirm it shows the claimed state before marking the AC accepted; a caption, filename or manifest row alone is not proof.

### High-risk artifacts

- Captures that assert their own validity (`dv-*-VERIFIED.*` names, remediation/re-capture images, any "fixed"/"after" pair) are where a mislabeled or duplicated capture hides; check them closely.
- Byte-identical captures for different states, or a capture showing an unrelated screen (home screen, springboard, wrong app) → `flagged`, not `accepted`, recorded in `testing-N.md § Notes`.

## Verdict reconciliation

Reconcile a row's RMSE pre-pass and vision results with the matrix below. RMSE only escalates: it may raise severity, never lower it, because it measures pixel distance and is blind to copy and semantic errors (a green RMSE on a wrong button label is still a Mismatch).

| RMSE | Vision | Verdict | Severity |
|------|--------|---------|----------|
| pass (≤8%) | match | Match | — |
| pass | mismatch | Mismatch | per vision |
| fail (>8%) | match | Mismatch | ≥ Major |
| fail | mismatch | Mismatch | ≥ Major (→ Critical if layout broken) |
| skipped/None | match | Match | — (vision-only) |
| skipped/None | mismatch | Mismatch | per vision |

### Skipped/None Semantics and Threshold Caveat

`skipped/None` covers overview rows, `.txt`/non-png placeholders and the `magick`-absent path; all take the vision verdict alone. `fail+match → ≥ Major` can over-escalate on anti-aliasing, DPR or scale noise between a Figma export and a canvas render; the recorded RMSE % lets humans tell borderline 8–12% noise from a real break.

## Reporting

Document results in `testing-N.md § Design Comparison` using the canonical table:

| ID | Screen | State | RMSE | Verdict | Severity | Notes |
|----|--------|-------|------|---------|----------|-------|
| design-001 | login | default | 2.1% (pass) | Match    | — | source=dv-result-image |
| design-002 | login | error   | 11.4% (fail) | Mismatch | Major | Error banner color off (#FF3B30 vs #D32F2F); RMSE over threshold |
| design-003 | login | overview | — (vision) | Match | — | container layout complete |
| design-004 | login | empty   | n/a (live-capture) | Match | — | source=live-capture (no DV image mapped) |

On the registry path, every registry row appears as exactly one row in this table.

### RMSE Column Values and AC Summary

`RMSE` column values by row type:
- Compared child row → `<value>% (pass|fail)` (e.g. `2.1% (pass)`, `11.4% (fail)`).
- Overview row → `— (vision)` (vision-only, no RMSE).
- Skipped/degraded row → `n/a (<reason>)` — e.g. `n/a (live-capture)`, `n/a (imagemagick_not_found)`, `n/a (placeholder)`.

After the table, include a one-line AC coverage summary:

> AC coverage: N of M acceptance criteria from `<plan_file>` have matching design-verified screens.

(`<plan_file>` resolves from `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`.)

## Degradation invariants

The design↔result reuse + RMSE pre-pass is strictly additive:

| Condition | Behaviour |
|---|---|
| Top-level gate | Unchanged — runs only when `metadata.ui_visual_check: true` AND `.context/designs/` has artifacts |
| `requires_screenshots: false` | No DV images exist → every row joins ∅ → branch `(d)`; RMSE never invoked, output byte-equivalent to 100% live-capture |
| `magick` absent | Vision-only, row reports `n/a (imagemagick_not_found)`, never blocks |
| No registry | Glob Discovery untouched — vision-only, no RMSE, no join |
| Manifest without `Design Ref` | Parses fine; missing column/value → `—` → no candidate → live-capture fallback |
