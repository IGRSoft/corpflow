---
name: appstore-screenshots
description: Use when creating App Store screenshots or marketing visuals. Device specs, layout patterns, typography, and Pencil MCP worktask for App Store screenshot generation.
effort: high
keep-coding-instructions: true
paths:
  - "**/AppStore/**"
  - "**/*.pen"
---

# App Store Screenshots Reference

Device specifications, layout patterns, typography tables, and Pencil MCP worktask for generating professional App Store screenshots as `.pen` files.

## Layout Calculator (canonical — use this instead of reading reference files)

`scripts/layout-calc.py` encodes the full 22-device matrix and every proportional/centering formula from the two reference files below. One call returns paste-ready JSON for `batch_design`; the model owns only op-string assembly, copy, and color.

### Invocation examples

```bash
# By device key (preferred)
python3 ${CLAUDE_SKILL_DIR}/scripts/layout-calc.py iphone-6.9-1320x2868 --layout A

# By explicit dimensions
python3 ${CLAUDE_SKILL_DIR}/scripts/layout-calc.py --w 1320 --h 2868 --platform ios --layout B

# List all 22 device keys
python3 ${CLAUDE_SKILL_DIR}/scripts/layout-calc.py --list-devices

# Full-bleed platforms (tvOS/watchOS) — returns canvas-fill passthrough
python3 ${CLAUDE_SKILL_DIR}/scripts/layout-calc.py appletv-4k-3840x2160 --layout A
```

### Output schema

Compact JSON, interpolate directly into `batch_design` params:
```
{
  "device":     {"name": str, "w": int, "h": int},
  "headline":   {"x": int, "y": int, "w": int, "fontSize": int, "textAlign": str},
  "subtitle":   {"x": int, "y": int, "w": int, "fontSize": int, "opacity": float, "textAlign": str},
  "screenshot": {"x": int, "y": int, "w": int, "h": int, "cornerRadius": int}
}
# full-bleed devices additionally include: "full_bleed": true
```

### Layouts and reference files

Layouts: **A** (text top / screenshot bottom-center hero), **B** (text top-left), **C** (screenshot top / text bottom), **D** (text top / large screenshot). Op-string construction, copy, gradient stops, and color stay with the model.

`references/device-specs.md` and `references/layout-patterns.md` remain the authoritative spec for the formulas encoded above — read them only to verify a formula or extend the device matrix, never in the generation happy path.

---

## Philosophy: Screenshots Are Ads

Screenshots are the #1 conversion driver; they must sell the app in 2 seconds of scrolling.

- Lead with **emotional benefit**, not feature name ("Never miss a moment" > "Push notifications")
- Each screenshot tells a **micro-story** — a user problem and how the app solves it
- The first screenshot conveys the core value proposition
- Use **power words**: effortless, instant, beautiful, smart, secure, free
- Vary compositions between screenshots for visual rhythm

### Copywriting — Good vs Bad

| Bad (feature name) | Good (emotional benefit) |
|--------------------|--------------------------|
| Dashboard View | Everything at a Glance |
| Settings Screen | Make It Yours |
| Search Feature | Find Anything Instantly |
| Dark Mode Support | Easy on the Eyes |
| Push Notifications | Never Miss a Moment |
| Cloud Sync | Your Data, Everywhere |
| Widget Support | Info at a Glance |

## Pencil MCP Worktask

### Loading Tools

Pencil MCP tools are deferred — load them first with `ToolSearch({ query: "+pencil" })`.

### File Organization

One `.pen` file per platform; one frame per device size; each slide is a child frame of its device.

```
AppStore/screenshots/
├── ios-phones.pen       # 7 device frames × N slides
├── ios-ipads.pen        # 7 device frames × N slides
├── macos.pen            # 3 device frames × N slides
├── tvos.pen             # 2 device frames × N slides (full-bleed)
└── watchos.pen          # 3 device frames × N slides (full-bleed)
```

### Frame Structure per Device

Document → device frame `"iPhone 6.9 (1320x2868)"` (W×H) → slide frames `"Slide 1 - Core Value"`, `"Slide 2 - Find Instantly"`, … (each W×H) → four layers per slide, in order: Background (bg.png image or gradient shape), Screenshot (app screen, centered at device-like proportions), Headline text, Subtitle text. Repeat the device frame per device size.

### Building with batch_design

#### Create device frame and first slide

```typescript
mcp__pencil__batch_design({
  operations: `
device=I(document, {type: "frame", name: "iPhone 6.9 (1320x2868)", width: 1320, height: 2868})
slide1=I(device, {type: "frame", name: "Slide 1 - Core Value", width: 1320, height: 2868, fill: "#1a1a2e"})
`
})
```

#### Add background image (bg.png)

```typescript
mcp__pencil__batch_design({
  operations: `
bg=I("slide1-id", {type: "image", name: "Background", width: 1320, height: 2868, imageFill: "fill"})
G(bg, "file", "/absolute/path/to/AppStore/images/bg.png")
`
})
```

#### Add screenshot image (centered, with padding for device-like look)

Geometry below comes from `layout-calc.py iphone-6.9-1320x2868 --layout A` — use the script, never hand-compute.

```typescript
mcp__pencil__batch_design({
  operations: `
ss=I("slide1-id", {type: "image", name: "Screenshot", x: 170, y: 688, width: 979, height: 2122, cornerRadius: 32, imageFill: "fill"})
G(ss, "file", "/absolute/path/to/AppStore/images/01-home.png")
`
})
```

#### Add text layers

```typescript
mcp__pencil__batch_design({
  operations: `
headline=I("slide1-id", {type: "text", name: "Headline", content: "Your Core Value", x: 79, y: 115, width: 1161, fontSize: 72, fontWeight: "700", fill: "#ffffff", textAlign: "center"})
subtitle=I("slide1-id", {type: "text", name: "Subtitle", content: "A short benefit description", x: 132, y: 373, width: 1056, fontSize: 42, fontWeight: "400", fill: "#ffffff", opacity: 0.75, textAlign: "center"})
`
})
```

#### Full-bleed layout (tvOS/watchOS) — no text, no device frame

```typescript
mcp__pencil__batch_design({
  operations: `
device=I(document, {type: "frame", name: "Apple TV 4K (3840x2160)", width: 3840, height: 2160})
slide=I(device, {type: "frame", name: "Slide 1", width: 3840, height: 2160})
bg=I(slide, {type: "image", name: "Background", width: 3840, height: 2160, imageFill: "fill"})
G(bg, "file", "/absolute/path/to/AppStore/images/bg.png")
ss=I(slide, {type: "image", name: "Screenshot", width: 3840, height: 2160, imageFill: "fill"})
G(ss, "file", "/absolute/path/to/AppStore/images/01-home.png")
`
})
```

### Gradient Background Fallback

With no `bg.png`, put a gradient fill on the slide frame itself:

```typescript
mcp__pencil__batch_design({
  operations: `
slide=I(device, {type: "frame", name: "Slide 1", width: 1320, height: 2868, fillType: "gradient", gradientType: "linear", gradientAngle: 180, gradientStops: [{"color": "#1a1a2e", "position": 0}, {"color": "#16213e", "position": 1}]})
`
})
```

Vary gradient angles per slide: 180°, 135°, 225°, 160°, 200°.

### Visual Validation

Validate each built device with `mcp__pencil__get_screenshot({ nodeId: "slide1-node-id" })`.

## Batch Operation Limits

Pencil MCP `batch_design` takes max 25 operations per call — at 4 layers per slide (bg, screenshot, headline, subtitle) that is ~6 slides per call.

**Strategy for many devices**: build one device at a time, batching all its slides in 1-2 calls.

## Export

From Pencil: open the `.pen` file, select the slide frames, export as PNG at the exact device resolution, upload to App Store Connect.
