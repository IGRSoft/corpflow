# QA Design Comparison (Visual QA) Procedure

Canonical registry-driven design-comparison procedure for the QA stage, extracted from `agents/qa-engineer.md § Design Comparison` (Phase-4 Worktask-Integration diet). **Read this file only when the visual gate is open** — `metadata.ui_visual_check: true` in `<plan_file>` AND design references exist in `.context/designs/` (equivalently, `requires_screenshots: true`). The gate check itself and the `testing-N.md § Visual Evidence` artifact schema stay in the agent body.

## Registry-Driven Comparison (Primary Path)

If `.context/designs/figma-registry.md` exists, it is the authoritative source — parse its Entries table and run comparison row-by-row. QA **reuses the DV-captured result images** as the primary comparison source and runs the RMSE pixel diff (`skills/dv-screenshot-capture/scripts/visual-diff.sh`) as an objective pre-pass **before** multimodal vision. **Step 3 (live capture) is skipped when a DV image maps to the row; live re-capture is the fallback only** (see § Implementation Screenshot Capture (fallback only)).

### Join Key (Design Ref)

The join key is the optional **`Design Ref`** column on DV's `.context/images/<worktask_id>/screenshots.md` manifest (Option A): QA joins `screenshots.md.Design Ref → figma-registry.md.ID` by explicit ID equality. A missing column or missing value is treated as `—` (no candidate → fallback). Per-row algorithm (replaces the legacy 5-step capture loop) — three parts below form ONE loop:

### Per-Row Algorithm — Skip, Overview, Join

```
for each registry row R:
  # parser tolerance: rows missing ID / Screenshot / Target File(s) are skipped,
  # logged as missing_input in .context/errors/qa-engineer.md
  if R missing ID or Screenshot or Target File(s):
      log missing_input; continue

  if R.State == "overview":                 # container layout completeness only
      vision = multimodal_layout_check(R)   # vision-only, NO RMSE
      emit_row(R, vision, rmse=None); continue

  candidates = screenshots.md rows where (Design Ref == R.ID)   # absent col / all "—" → ∅
```

### Per-Row Algorithm — Fallback Branch (d)

```
# …continued: same loop, empty-candidates branch
  if candidates == ∅:                       # (d) LEGACY FALLBACK — byte-equivalent to today
      impl = build_run_sim → navigate(R.Target File(s)) → screenshot   # § fallback-only below
      vision = multimodal_compare(R.Screenshot, impl)
      emit_row(R, reconcile(None, vision), source="live-capture"); continue
```

### Per-Row Algorithm — DV-Image Branch

```
# …continued: same loop, DV-image branch
  dv_img = newest_non_placeholder_png(candidates)   # log extra candidates to § Notes
  if dv_img is .txt / non-png placeholder:
      rmse = None
      vision = multimodal_compare(R.Screenshot, dv_img-or-live)
  else:
      run scripts/visual-diff.sh \
          --reference .context/designs/<R.Screenshot> \
          --candidate <dv_img> \
          --threshold 8 --worktask-id <worktask_id> --slug <R.ID>   # self-degrades; emits visual_diff_run
      rmse   = parse stdout "verdict=<pass|fail_visual_diff> value=<N>%"
      vision = multimodal_compare(R.Screenshot, dv_img)             # SAME image as RMSE
  emit_row(R, reconcile(rmse, vision), source="dv-result-image")
```

### Algorithm Notes

- **Step 3 (live capture) is skipped** for any row with a mapped DV image — the DV result image is both the RMSE `--candidate` and the vision input.
- `visual-diff.sh` self-degrades: `magick` absent → it emits `verdict=skipped reason=imagemagick_not_found` and exits 0; QA then proceeds vision-only for that row (non-blocking).
- The fallback branch `(d)` is intentionally a **separately-headed branch that stays byte-equivalent to today's behaviour** (R1): same build→navigate→screenshot→vision, same `source="live-capture"` labelling.
- **Auto-background**: branch (d)'s `build_run_sim` may auto-background past ~2 min — await the completion notification (not the returned handle) before `navigate`/`screenshot`; see `agent-coordination § MCP Auto-Background`.

## Per-Frame Comparison

When the registry contains **per-frame rows** — a container produces one `State: overview` row plus one row per child frame, each keyed on its own `Figma Node` id (see `agents/product-manager.md § Registry Generation`) — compare against **each persisted frame file individually**, state by state, NOT against a single combined screenshot:

1. Treat the `overview` row as the container reference. It is verified for layout completeness (all frames present) but is not a per-state target — **vision-only, no RMSE** (`rmse=None`).

### Per-Frame Child Rows and Emission

2. For each child-frame row, run the RMSE pre-pass on the mapped DV result image (joined via `Design Ref == ID`) when one exists, then compare against that row's `.context/designs/<Screenshot>` file via vision; live re-capture only when no DV image maps. Compare state by state (default/error/empty/loading/success/…), NOT against a single combined screenshot.
3. Emit one Design Comparison table row per registry row (overview + each frame), so an N-frame container yields N+1 comparison rows. A mismatch on one frame does not mask matches on the others.

A leaf (single-screen) registry has no overview row and collapses to the normal one-row comparison — no regression.

## Fallback: Glob Discovery (Legacy Tasks)

If the registry is missing, glob `.context/designs/figma-*.png` and compare what's there — the legacy behavior. Flag the missing registry in `testing.md § Design Comparison` as a process gap:

> No `figma-registry.md` found; using glob fallback. Screen/state/target mapping inferred from filenames only.

Pencil `.pen` mockups (`.context/designs/mockup-*.pen`) are compared independently of the Figma registry: load Pencil tools via `ToolSearch({ query: "+pencil" })`, then use `mcp__pencil__get_screenshot({ filePath, nodeId })` to render the mockup for visual comparison.

## Implementation Screenshot Capture (fallback only)

Live re-capture runs **only** when no DV result image maps to a registry row
(absent `Design Ref` column, all `—`, or no PNG candidate). When a DV image maps,
this step is skipped and the DV result image is used directly. This branch is
byte-equivalent to the pre-change behaviour (R1) — same tools, same `source="live-capture"`.

`build_run_sim` past ~2 min auto-backgrounds — await the completion notification before navigating/screenshotting (`agent-coordination § MCP Auto-Background`).

| Platform | Worktask |
|----------|----------|
| iOS | `mcp__XcodeBuildMCP__build_run_sim` → navigate to target screen → `mcp__XcodeBuildMCP__screenshot` |
| Web | Load chrome tools via `ToolSearch({ query: "select:mcp__claude-in-chrome__computer" })` → screenshot |

## Visual Comparison

Use the `Read` tool to load both the design screenshot and the implementation screenshot. Claude's multimodal vision compares:
- Layout and spacing
- Color accuracy
- Typography (font size, weight, line height)
- Component presence and positioning
- State representation (default, error, empty, loading)
- Icon and image placement

### Severity Taxonomy (canonical)

- **Critical**: Layout broken, missing components, unusable state
- **Major**: Noticeable visual difference — wrong colors, spacing off by > 8px, wrong copy
- **Minor**: Subtle spacing or color difference, typography nuance

## Verdict reconciliation

When a row has both an RMSE pre-pass result and a multimodal vision result, reconcile
them with the matrix below. **RMSE is a one-way *escalator*: it may raise severity,
never lower it.** RMSE is blind to copy/semantic errors (it only measures pixel
distance), so it can never downgrade a vision-detected Mismatch to a Match — a green
RMSE on a screen with the wrong button label is still a Mismatch per vision.

| RMSE | Vision | Verdict | Severity |
|------|--------|---------|----------|
| pass (≤8%) | match | Match | — |
| pass | mismatch | Mismatch | per vision |
| fail (>8%) | match | Mismatch | ≥ Major |
| fail | mismatch | Mismatch | ≥ Major (→ Critical if layout broken) |
| skipped/None | match | Match | — (vision-only) |
| skipped/None | mismatch | Mismatch | per vision |

### Skipped/None Semantics and Threshold Caveat

`skipped/None` covers overview rows (no RMSE), `.txt`/non-png placeholders, and the
`magick`-absent self-degrade path — all of which fall through to the vision verdict
alone. The `fail+match → ≥ Major` row may over-escalate on AA/DPR/scale noise between
a Figma export and a canvas render (R3); the 8% threshold is generous and the RMSE %
is recorded in the reporting table so humans can spot borderline 8–12% noise vs a real
break.

## Reporting

Document results in `testing.md § Design Comparison` using the canonical table:

| ID | Screen | State | RMSE | Verdict | Severity | Notes |
|----|--------|-------|------|---------|----------|-------|
| design-001 | login | default | 2.1% (pass) | Match    | — | source=dv-result-image |
| design-002 | login | error   | 11.4% (fail) | Mismatch | Major | Error banner color off (#FF3B30 vs #D32F2F); RMSE over threshold |
| design-003 | login | overview | — (vision) | Match | — | container layout complete |
| design-004 | login | empty   | n/a (live-capture) | Match | — | source=live-capture (no DV image mapped) |

When using the registry path, every registry row MUST appear as exactly one row in this table.

### RMSE Column Values and AC Summary

`RMSE` column values by row type:
- Compared child row → `<value>% (pass|fail)` (e.g. `2.1% (pass)`, `11.4% (fail)`).
- Overview row → `— (vision)` (vision-only, no RMSE).
- Skipped/degraded row → `n/a (<reason>)` — e.g. `n/a (live-capture)`, `n/a (imagemagick_not_found)`, `n/a (placeholder)`.

After the table, include a one-line AC coverage summary:

> AC coverage: N of M acceptance criteria from `<plan_file>` have matching design-verified screens.

(`<plan_file>` resolves from `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`.)

## Backward-compatibility guarantees

The design↔result reuse + RMSE pre-pass is strictly additive — these invariants hold:

- **Top-level gate unchanged**: Design Comparison still runs only when
  `metadata.ui_visual_check: true` AND `.context/designs/` has artifacts. Nothing about
  the gate condition changed.
- **`requires_screenshots: false` → today's output**: no DV result images exist, so every
  registry row joins to ∅ and falls to the live-capture branch `(d)`. RMSE is never invoked;
  output is byte-equivalent to the pre-change behaviour (100% live-capture).

### Degradation and Legacy-Input Invariants

- **`magick` absent → vision-only, non-blocking**: `visual-diff.sh` self-degrades
  (`verdict=skipped reason=imagemagick_not_found`, exit 0). QA proceeds with vision alone;
  the row reports `n/a (imagemagick_not_found)`. Never blocks.
- **No registry → Glob Discovery fallback untouched**: the legacy glob path (above) is
  unchanged and remains vision-only — no RMSE, no join.
- **Old manifest without `Design Ref` column**: parses fine; a missing column/value is
  treated as `—` → no candidate → live-capture fallback.
