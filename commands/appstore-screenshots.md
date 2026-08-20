---
name: appstore-screenshots
description: 'Apple-only. Generate professional App Store screenshots from the AppStore/ folder for iOS, macOS, tvOS, and watchOS.'
argument-hint: '[--apple-platform ios|macos|tvos|watchos|all] [--lang en|ua] [--path <dir>] [--dry-run]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write, Bash, mcp__pencil__open_document, mcp__pencil__batch_design, mcp__pencil__batch_get, mcp__pencil__get_screenshot, mcp__pencil__snapshot_layout, mcp__pencil__find_empty_space_on_canvas, mcp__pencil__get_variables, mcp__pencil__set_variables, mcp__pencil__get_guidelines, mcp__pencil__get_style_guide_tags, mcp__pencil__get_style_guide
related:
  - commands/appstore-info.md
  - agents/release-engineer.md
  - agents/designer.md
  - commands/docs-release-notes.md
  - skills/appstore-screenshots/SKILL.md
  - skills/pencil-design-worktask/SKILL.md
---

# App Store Screenshots Command

> **Apple-only.** This command targets App Store listing assets and has no equivalent on
> other platforms. Its `--apple-platform` flag selects an Apple device class and is
> deliberately *not* the plugin-wide `--platform <apple|android|web|systems|backend|ai>`.

Generate professional App Store screenshots as `.pen` files using Pencil MCP. Reads features from `AppStore/{lang}/info.md`, uses screenshots from `AppStore/images/`, and applies `bg.png` as background.

## Usage

```
/appstore-screenshots
/appstore-screenshots --apple-platform ios
/appstore-screenshots --apple-platform macos --lang ua
/appstore-screenshots --apple-platform all
/appstore-screenshots --dry-run
```

## Options

- `--apple-platform <ios|macos|tvos|watchos|all>` — Target platform (default: `ios`)
- `--lang <en|ua>` — Language for feature copy from info.md (default: `en`)
- `--path <dir>` — Project root directory (default: current working directory)
- `--dry-run` — Preview slide plan without generating .pen files

## Prerequisites

`AppStore/` must exist — run `/appstore-info` first if it doesn't. Inputs read here:

- `AppStore/{lang}/info.md` — listing file, the features source (`en` required, `ua` optional)
- `AppStore/images/` — descriptively named `.png`/`.jpg` screenshots (`01-home.png`, `02-search.png`, …) plus optional `bg.png` background

## Step 0 — Load Pencil MCP Tools

All `mcp__pencil__*` tools are deferred; load them once before proceeding: `ToolSearch({ query: "+pencil" })`.

## Step 1 — Validate AppStore/ Structure

Require `AppStore/{lang}/info.md` (`{lang}` from `--lang`) and at least 1 screenshot in `AppStore/images/` (`.png`/`.jpg`, excluding `bg.png`). On failure, print a clear error and suggest running `/appstore-info` first.

## Step 2 — Extract Features from info.md

Read sections `## App Name`, `## Subtitle`, `## Description`, `## Keywords` from `AppStore/{lang}/info.md`. Parse the Description into distinct features/benefits — one feature per slide; if screenshots outnumber features, reuse or generalize.

## Step 3 — Scan Screenshots

Collect `.png`/`.jpg` files in `AppStore/images/` sorted alphabetically, excluding `bg.png` — use `bg.png` as the background if present, otherwise fall back to a gradient. Match each screenshot to a Step 2 feature by filename or order, and resolve absolute paths (Pencil `G()` requires them).

**IMPORTANT: Use every screenshot found. Never skip or filter any. If there are 6 images, generate exactly 6 slides.**

## Step 4 — Write Compelling Copy

For each screenshot, generate a **Headline** (3-6 words) and **Subtitle** (6-12 words) following the "screenshots are ads" philosophy in `skills/appstore-screenshots/SKILL.md` (emotional benefit over feature name; first slide = core value proposition; power words).

## Step 5 — Select Platform Devices

Based on `--apple-platform`, select device sets from the `appstore-screenshots` skill:

| Apple platform | Devices | Orientation | Layout | .pen file |
|----------------|---------|-------------|--------|-----------|
| `ios` | 7 iPhones + 7 iPads | portrait | screenshot with text | `ios-phones.pen` + `ios-ipads.pen` |
| `macos` | 3 Mac sizes | landscape | screenshot with text | `macos.pen` |
| `tvos` | 2 Apple TV sizes | landscape | full-bleed image | `tvos.pen` |
| `watchos` | 3 Apple Watch sizes | portrait | full-bleed image | `watchos.pen` |
| `all` | all of the above (22 total) | mixed | mixed | all .pen files |

## Step 6 — Create .pen Files with Pencil MCP

Create `AppStore/screenshots/` directory for output files. Follow `skills/appstore-screenshots/SKILL.md` for ALL build rules — `§ Building with batch_design` (op sequences, bg.png vs gradient fallback, full-bleed tvOS/watchOS, aspect-ratio formula), `§ Batch Operation Limits` (25 ops/call), and `references/layout-patterns.md` (Layout A–D rotation: never repeat consecutively; first and last slides use Layout A or D). Do not improvise op sequences.

## Step 7 — Visual Validation

After building each .pen file, screenshot key slides — `mcp__pencil__get_screenshot({ nodeId: "first-slide-node-id" })` — and check: background covers the full frame, screenshot centered and correctly sized, text readable and well-positioned, no overlapping elements. Fix with `batch_design` Update operations: `U("node-id", {x: 100, y: 200})`.

## Step 8 — Report

```markdown
# App Store Screenshots — Summary

## Configuration        ← Platform, Language, Screenshots found, Background (bg.png/gradient), Devices generated
## Files Generated      ← table: File | Devices | Slides (one row per .pen)
## Slides               ← table: # | Screenshot | Headline | Subtitle
## Next Steps           ← review in Pencil → adjust copy → export PNGs at device resolution → upload to App Store Connect slots
```

## Error Handling

| Error | Action |
|-------|--------|
| `AppStore/` folder missing | Suggest running `/appstore-info` first |
| No screenshots in `AppStore/images/` | Ask user to add screenshots |
| `info.md` missing for selected language | Suggest running `/appstore-info --lang {lang}` |
| Pencil MCP tools not available | Check that Pencil.app is running; fall back to text-only plan |
| `batch_design` fails | Retry with fewer operations per batch |

## Examples

```bash
/appstore-screenshots                                    # iOS (default)
/appstore-screenshots --apple-platform all               # all Apple device classes
/appstore-screenshots --apple-platform macos --lang ua   # macOS, Ukrainian copy
/appstore-screenshots --dry-run                          # plan only, no files
/appstore-screenshots --path ~/projects/MyApp            # specific project dir
```

## Integration

**RE stage** — generate screenshots before App Store submission: after `/appstore-info` scaffolds `AppStore/`, when preparing a new release or major version, or when adding an Apple device class (e.g. macOS screenshots to an iOS app).

Target: $ARGUMENTS
