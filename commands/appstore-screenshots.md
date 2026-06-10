---
name: appstore-screenshots
description: Generate professional App Store screenshots from AppStore/ folder for iOS, macOS, tvOS, watchOS
argument-hint: '[--platform ios|macos|tvos|watchos|all] [--lang en|ua]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write, Bash, mcp__pencil__open_document, mcp__pencil__batch_design, mcp__pencil__batch_get, mcp__pencil__get_screenshot, mcp__pencil__snapshot_layout, mcp__pencil__find_empty_space_on_canvas, mcp__pencil__get_variables, mcp__pencil__set_variables, mcp__pencil__get_guidelines, mcp__pencil__get_style_guide_tags, mcp__pencil__get_style_guide
---

# App Store Screenshots Command

Generate professional App Store screenshots as `.pen` files using Pencil MCP. Reads features from `AppStore/{lang}/info.md`, uses screenshots from `AppStore/images/`, and applies `bg.png` as background.

## Usage

```
/appstore-screenshots
/appstore-screenshots --platform ios
/appstore-screenshots --platform macos --lang ua
/appstore-screenshots --platform all
/appstore-screenshots --dry-run
```

## Options

- `--platform <ios|macos|tvos|watchos|all>` — Target platform (default: `ios`)
- `--lang <en|ua>` — Language for feature copy from info.md (default: `en`)
- `--path <dir>` — Project root directory (default: current working directory)
- `--dry-run` — Preview slide plan without generating .pen files

## Prerequisites

The `AppStore/` folder must exist with at least one listing file. Run `/appstore-info` first if it doesn't exist.

Required structure:
```
AppStore/
├── en/
│   └── info.md          # App Store listing (features source)
├── ua/
│   └── info.md          # Ukrainian listing (optional)
├── images/
│   ├── bg.png           # Background image (optional, falls back to gradient)
│   ├── 01-home.png      # Screenshots named descriptively
│   ├── 02-search.png
│   ├── 03-settings.png
│   └── ...
└── changelog.md
```

## Steps

### Step 0 — Load Pencil MCP Tools

```
ToolSearch({ query: "+pencil" })
```

All `mcp__pencil__*` tools are deferred. Load them once before proceeding.

### Step 1 — Validate AppStore/ Structure

Check that the required files exist:

1. Verify `AppStore/{lang}/info.md` exists (where `{lang}` is from `--lang` option)
2. Verify `AppStore/images/` directory has at least 1 screenshot (`.png` or `.jpg`, excluding `bg.png`)
3. If validation fails, print a clear error message and suggest running `/appstore-info` first

### Step 2 — Extract Features from info.md

Read `AppStore/{lang}/info.md` and extract:

- **App Name** — from the `## App Name` section
- **Subtitle** — from the `## Subtitle` section
- **Description** — from the `## Description` section (parse individual features/benefits)
- **Keywords** — from the `## Keywords` section

Parse the Description to identify distinct features or benefits. Each feature maps to one screenshot slide. If there are more screenshots than features, reuse or generalize features.

### Step 3 — Scan Screenshots

List all image files in `AppStore/images/`:

- Collect `.png` and `.jpg` files, sorted alphabetically
- Exclude `bg.png` from the screenshot list (it's the background)
- Check if `bg.png` exists — if yes, use it as background; otherwise fall back to gradient
- Match each screenshot to a feature from Step 2 based on filename or order
- Resolve absolute paths for all images (Pencil `G()` operation requires absolute paths)

**IMPORTANT: Use every screenshot found. Never skip or filter any. If there are 6 images, generate exactly 6 slides.**

### Step 4 — Write Compelling Copy

For each screenshot, generate a **Headline** (3-6 words) and **Subtitle** (6-12 words) following the "screenshots are ads" philosophy in `skills/appstore-screenshots/SKILL.md` (emotional benefit over feature name; first slide = core value proposition; power words).

### Step 5 — Select Platform Devices

Based on `--platform` flag, select device sets from the `appstore-screenshots` skill:

| Platform | Devices | Orientation | Layout | .pen file |
|----------|---------|-------------|--------|-----------|
| `ios` | 7 iPhones + 7 iPads | portrait | screenshot with text | `ios-phones.pen` + `ios-ipads.pen` |
| `macos` | 3 Mac sizes | landscape | screenshot with text | `macos.pen` |
| `tvos` | 2 Apple TV sizes | landscape | full-bleed image | `tvos.pen` |
| `watchos` | 3 Apple Watch sizes | portrait | full-bleed image | `watchos.pen` |
| `all` | all of the above (22 total) | mixed | mixed | all .pen files |

### Step 6 — Create .pen Files with Pencil MCP

Create `AppStore/screenshots/` directory for output files. Follow `skills/appstore-screenshots/SKILL.md` for ALL build rules — `§ Building with batch_design` (op sequences, bg.png vs gradient fallback, full-bleed tvOS/watchOS, aspect-ratio formula), `§ Batch Operation Limits` (25 ops/call), and `references/layout-patterns.md` (Layout A–D rotation: never repeat consecutively; first and last slides use Layout A or D). Do not improvise op sequences.

### Step 7 — Visual Validation

After building each .pen file, validate key slides:

```typescript
mcp__pencil__get_screenshot({ nodeId: "first-slide-node-id" })
```

Check:
- Background covers the full frame
- Screenshot is properly centered and sized
- Text is readable and well-positioned
- No overlapping elements

If issues are found, fix with `batch_design` Update operations:
```typescript
mcp__pencil__batch_design({
  operations: `U("node-id", {x: 100, y: 200})`
})
```

### Step 8 — Report

Print summary:

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
/appstore-screenshots                              # iOS (default)
/appstore-screenshots --platform all               # all Apple platforms
/appstore-screenshots --platform macos --lang ua   # macOS, Ukrainian copy
/appstore-screenshots --dry-run                    # plan only, no files
/appstore-screenshots --path ~/projects/MyApp      # specific project dir
```

## Integration

This command is used:
- At the **RE stage** — generate screenshots before App Store submission
- After `/appstore-info` scaffolds the AppStore/ folder
- When preparing a new app release or major version update
- When adding platform support (e.g., adding macOS screenshots to an iOS app)

## Related

- [appstore-info](./appstore-info.md) — Scaffold AppStore/ folder and generate listing content
- [release-engineer](../agents/release-engineer.md) — Release Engineering stage
- [designer](../agents/designer.md) — Design review and specifications
- [create-release-notes](./create-release-notes.md) — Generate "What's New" content
- [appstore-screenshots skill](../skills/appstore-screenshots.md) — Device specs and layout reference
- [pencil-design skill](../skills/pencil-design/SKILL.md) — Pencil MCP tools reference

Target: $ARGUMENTS
