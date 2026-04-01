---
name: appstore-screenshots
description: Device specs, layout patterns, typography, and Pencil MCP workflow for App Store screenshot generation. Use when creating App Store screenshots or marketing visuals.
effort: high
paths:
  - "**/AppStore/**"
  - "**/*.pen"
---

# App Store Screenshots Reference

Device specifications, layout patterns, typography tables, and Pencil MCP workflow for generating professional App Store screenshots as `.pen` files.

For device dimensions and font sizes, see `${CLAUDE_SKILL_DIR}/references/device-specs.md`

For layout formulas and composition rules, see `${CLAUDE_SKILL_DIR}/references/layout-patterns.md`

## Philosophy: Screenshots Are Ads

App store screenshots are the #1 conversion driver. They must sell the app in 2 seconds of scrolling.

- Lead with **emotional benefit**, not feature name ("Never miss a moment" > "Push notifications")
- Each screenshot should tell a **micro-story** — a problem the user has and how this app solves it
- The first screenshot conveys the app's core value proposition
- Use **power words**: effortless, instant, beautiful, smart, secure, free
- Vary compositions between screenshots to create visual rhythm

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

## Pencil MCP Workflow

### Loading Tools

All Pencil MCP tools are deferred and must be loaded first:

```
ToolSearch({ query: "+pencil" })
```

### File Organization

Each platform gets a separate `.pen` file. Each device size is a separate frame within the file. Each slide within a device is a child frame.

```
AppStore/screenshots/
├── ios-phones.pen       # 7 device frames × N slides
├── ios-ipads.pen        # 7 device frames × N slides
├── macos.pen            # 3 device frames × N slides
├── tvos.pen             # 2 device frames × N slides (full-bleed)
└── watchos.pen          # 3 device frames × N slides (full-bleed)
```

### Frame Structure per Device

```
Document
├── "iPhone 6.9 (1320x2868)"          # device frame (W×H)
│   ├── "Slide 1 - Core Value"        # slide frame (W×H)
│   │   ├── Background                # image (bg.png) or gradient shape
│   │   ├── Screenshot                # image of app screen, centered with device-like proportions
│   │   ├── Headline                  # text layer
│   │   └── Subtitle                  # text layer
│   ├── "Slide 2 - Find Instantly"    # slide frame
│   │   └── ...
│   └── ...
├── "iPhone 6.9 (1290x2796)"          # next device
│   └── ...
```

### Building with batch_design

**Create device frame and first slide:**

```typescript
mcp__pencil__batch_design({
  operations: `
device=I(document, {type: "frame", name: "iPhone 6.9 (1320x2868)", width: 1320, height: 2868})
slide1=I(device, {type: "frame", name: "Slide 1 - Core Value", width: 1320, height: 2868, fill: "#1a1a2e"})
`
})
```

**Add background image (bg.png):**

```typescript
mcp__pencil__batch_design({
  operations: `
bg=I("slide1-id", {type: "image", name: "Background", width: 1320, height: 2868, imageFill: "fill"})
G(bg, "file", "/absolute/path/to/AppStore/images/bg.png")
`
})
```

**Add screenshot image (centered, with padding for device-like look):**

```typescript
// For phone screenshots: compute centered position
// screenshot_h = H * 0.74, screenshot_w = screenshot_h / (19.5/9)
// screenshot_x = (W - screenshot_w) / 2, screenshot_y = H * 0.24

mcp__pencil__batch_design({
  operations: `
ss=I("slide1-id", {type: "image", name: "Screenshot", x: 171, y: 688, width: 979, height: 2122, cornerRadius: 32, imageFill: "fill"})
G(ss, "file", "/absolute/path/to/AppStore/images/01-home.png")
`
})
```

**Add text layers:**

```typescript
mcp__pencil__batch_design({
  operations: `
headline=I("slide1-id", {type: "text", name: "Headline", content: "Your Core Value", x: 79, y: 115, width: 1161, fontSize: 72, fontWeight: "700", fill: "#ffffff", textAlign: "center"})
subtitle=I("slide1-id", {type: "text", name: "Subtitle", content: "A short benefit description", x: 132, y: 373, width: 1056, fontSize: 42, fontWeight: "400", fill: "#ffffff", opacity: 0.75, textAlign: "center"})
`
})
```

**Full-bleed layout (tvOS/watchOS) — no text, no device frame:**

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

When no `bg.png` exists, use a gradient fill on the slide frame itself:

```typescript
mcp__pencil__batch_design({
  operations: `
slide=I(device, {type: "frame", name: "Slide 1", width: 1320, height: 2868, fillType: "gradient", gradientType: "linear", gradientAngle: 180, gradientStops: [{"color": "#1a1a2e", "position": 0}, {"color": "#16213e", "position": 1}]})
`
})
```

Vary gradient angles per slide: 180°, 135°, 225°, 160°, 200°.

### Visual Validation

After building each device, validate with a screenshot:

```typescript
mcp__pencil__get_screenshot({ nodeId: "slide1-node-id" })
```

## Batch Operation Limits

Pencil MCP `batch_design` supports max 25 operations per call. For a typical slide (4 layers: bg, screenshot, headline, subtitle), you can build ~6 slides per batch call.

**Strategy for many devices**: Build one device at a time. For each device, batch all slides in 1-2 calls depending on slide count.

## Export

After generation, screenshots can be exported from Pencil:
1. Open the `.pen` file in Pencil
2. Select individual slide frames
3. Export as PNG at the exact device resolution
4. Upload to App Store Connect
