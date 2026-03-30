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

For each screenshot, generate:

- **Headline** (3-6 words): emotional benefit, not feature description
- **Subtitle** (6-12 words): adds context or specificity

Follow the "screenshots are ads" philosophy from the `appstore-screenshots` skill:
- Lead with emotional benefit, not feature name
- Each screenshot tells a micro-story
- First screenshot = core value proposition
- Use power words: effortless, instant, beautiful, smart, secure, free

### Step 5 — Select Platform Devices

Based on `--platform` flag, select device sets from the `appstore-screenshots` skill:

| Platform | Devices | Orientation | Layout | .pen file |
|----------|---------|-------------|--------|-----------|
| `ios` | 7 iPhones + 7 iPads | portrait | screenshot with text | `ios-phones.pen` + `ios-ipads.pen` |
| `macos` | 3 Mac sizes | landscape | screenshot with text | `macos.pen` |
| `tvos` | 2 Apple TV sizes | landscape | full-bleed image | `tvos.pen` |
| `watchos` | 3 Apple Watch sizes | portrait | full-bleed image | `watchos.pen` |
| `all` | all of the above (22 total) | mixed | mixed | all .pen files |

**tvOS and watchOS** use full-bleed image layout — no text layers. Just background + screenshot filling the canvas.

### Step 6 — Create .pen Files with Pencil MCP

Create `AppStore/screenshots/` directory for output files.

**For each platform .pen file:**

1. **Open document** — `mcp__pencil__open_document({ filePathOrTemplate: "AppStore/screenshots/{platform}.pen" })`

2. **For each device size**, create a device frame:
```typescript
mcp__pencil__batch_design({
  operations: `
device=I(document, {type: "frame", name: "iPhone 6.9 (1320x2868)", width: 1320, height: 2868})
`
})
```

3. **For each slide within the device**, create layers (max 25 ops per batch_design call):

**With bg.png:**
```typescript
mcp__pencil__batch_design({
  operations: `
slide=I("device-id", {type: "frame", name: "Slide 1 - Core Value", width: W, height: H, clipsContent: true})
bg=I(slide, {type: "image", name: "Background", width: W, height: H, imageFill: "fill"})
G(bg, "file", "/absolute/path/to/AppStore/images/bg.png")
ss=I(slide, {type: "image", name: "Screenshot", x: X, y: Y, width: SW, height: SH, cornerRadius: 32, imageFill: "fill"})
G(ss, "file", "/absolute/path/to/AppStore/images/01-home.png")
headline=I(slide, {type: "text", name: "Headline", content: "Your Core Value", x: HX, y: HY, width: HW, fontSize: FS, fontWeight: "700", fill: "#ffffff", textAlign: "center"})
subtitle=I(slide, {type: "text", name: "Subtitle", content: "A short benefit", x: SX, y: SY, width: SW2, fontSize: FS2, fontWeight: "400", fill: "#ffffff", opacity: 0.75, textAlign: "center"})
`
})
```

**Without bg.png (gradient fallback):**
```typescript
// Use gradient fill on the slide frame itself
slide=I("device-id", {type: "frame", name: "Slide 1", width: W, height: H, clipsContent: true, fillType: "gradient", gradientType: "linear", gradientAngle: 180, gradientStops: [{"color": "#1a1a2e", "position": 0}, {"color": "#16213e", "position": 1}]})
```

**Full-bleed layout (tvOS/watchOS):**
```typescript
slide=I("device-id", {type: "frame", name: "Slide 1", width: W, height: H, clipsContent: true})
bg=I(slide, {type: "image", name: "Background", width: W, height: H, imageFill: "fill"})
G(bg, "file", "/absolute/path/to/bg.png")
ss=I(slide, {type: "image", name: "Screenshot", width: W, height: H, imageFill: "fill"})
G(ss, "file", "/absolute/path/to/01-home.png")
```

**Layout formulas** — Apply from the `appstore-screenshots` skill:
- Rotate layouts A, B, C, D — never repeat consecutively
- First and last slides use Layout A or D
- Compute screenshot position using aspect ratio formulas
- Phone screenshots: `ss_h = H * ratio`, `ss_w = ss_h / (19.5/9)`, `ss_x = (W - ss_w) / 2`
- macOS screenshots: `ss_h = H * ratio`, `ss_w = ss_h * 1.6`, `ss_x = (W - ss_w) / 2`

**Batching strategy**: Each slide uses ~7 operations (frame + bg image + G() + screenshot image + G() + headline + subtitle). Batch up to 3 slides per `batch_design` call to stay under 25-op limit.

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

## Configuration
| Field | Value |
|-------|-------|
| Platform | [ios/macos/tvos/watchos/all] |
| Language | [en/ua] |
| Screenshots | [N found] |
| Background | [bg.png / gradient fallback] |
| Devices | [N devices generated] |

## Files Generated
| File | Devices | Slides |
|------|---------|--------|
| AppStore/screenshots/ios-phones.pen | 7 iPhones | N slides each |
| AppStore/screenshots/ios-ipads.pen | 7 iPads | N slides each |
| ... | ... | ... |

## Slides
| # | Screenshot | Headline | Subtitle |
|---|-----------|----------|----------|
| 1 | 01-home.png | Your Core Value | A short benefit description |
| 2 | 02-search.png | Find Anything Instantly | Search across all your content |
| ... | ... | ... | ... |

## Next Steps
1. Open .pen files in Pencil to review and fine-tune
2. Adjust text copy for your brand voice
3. Customize colors and backgrounds
4. Export each slide frame as PNG at device resolution
5. Upload to the appropriate device slots in App Store Connect
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

```
# Generate iOS screenshots (default)
/appstore-screenshots

# Generate for all Apple platforms
/appstore-screenshots --platform all

# Generate macOS screenshots with Ukrainian copy
/appstore-screenshots --platform macos --lang ua

# Preview slide plan without generating files
/appstore-screenshots --dry-run

# Use a specific project directory
/appstore-screenshots --path ~/projects/MyApp --platform ios
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
- [pencil-design-workflow skill](../skills/pencil-design-workflow.md) — Pencil MCP tools reference

Target: $ARGUMENTS
