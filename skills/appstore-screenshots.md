---
name: appstore-screenshots
description: Device specs, layout patterns, typography, and Pencil MCP workflow for App Store screenshot generation. (user)
---

# App Store Screenshots Reference

Device specifications, layout patterns, typography tables, and Pencil MCP workflow for generating professional App Store screenshots as `.pen` files.

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

## Device Tables

### iOS Phones (7 devices)

| Device name | W | H | Headline fontSize | Subtitle fontSize |
|---|---|---|---|---|
| iPhone 6.9" (1320x2868) | 1320 | 2868 | 72 | 42 |
| iPhone 6.9" (1290x2796) | 1290 | 2796 | 70 | 40 |
| iPhone 6.9" (1260x2736) | 1260 | 2736 | 68 | 40 |
| iPhone 6.5" (1284x2778) | 1284 | 2778 | 70 | 40 |
| iPhone 6.5" (1242x2688) | 1242 | 2688 | 68 | 38 |
| iPhone 6.3" (1206x2622) | 1206 | 2622 | 66 | 38 |
| iPhone 6.3" (1179x2556) | 1179 | 2556 | 64 | 36 |

### iPads (7 devices)

| Device name | W | H | Headline fontSize | Subtitle fontSize |
|---|---|---|---|---|
| iPad 13" (2064x2752) | 2064 | 2752 | 84 | 48 |
| iPad 13" (2048x2732) | 2048 | 2732 | 84 | 48 |
| iPad 12.9" (2048x2732) | 2048 | 2732 | 84 | 48 |
| iPad 11" (1668x2420) | 1668 | 2420 | 72 | 42 |
| iPad 11" (1668x2388) | 1668 | 2388 | 72 | 42 |
| iPad 11" (1640x2360) | 1640 | 2360 | 70 | 40 |
| iPad 11" (1488x2266) | 1488 | 2266 | 64 | 36 |

### macOS (3 devices, landscape)

| Device name | W | H | Headline fontSize | Subtitle fontSize |
|---|---|---|---|---|
| Mac 2880x1800 | 2880 | 1800 | 84 | 48 |
| Mac 2560x1600 | 2560 | 1600 | 72 | 42 |
| Mac 1280x800 | 1280 | 800 | 48 | 28 |

### tvOS (2 devices, landscape)

| Device name | W | H | Layout |
|---|---|---|---|
| Apple TV 4K (3840x2160) | 3840 | 2160 | full-bleed image |
| Apple TV (1920x1080) | 1920 | 1080 | full-bleed image |

tvOS uses full-bleed image layout — no device frame, no text layers. Background + screenshot filling the canvas.

### watchOS (3 devices)

| Device name | W | H | Layout |
|---|---|---|---|
| Apple Watch Ultra 3 (422x514) | 422 | 514 | full-bleed image |
| Apple Watch Ultra (410x502) | 410 | 502 | full-bleed image |
| Apple Watch Series 10 (416x496) | 416 | 496 | full-bleed image |

watchOS uses full-bleed image layout — no device frame, no text layers. Background + screenshot filling the canvas.

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

## Layout Patterns (iOS/iPad/macOS)

All values use proportional `W*ratio` and `H*ratio` formulas — they scale automatically to any device canvas.

**IMPORTANT: Never use the same layout twice in a row.** Rotate through patterns.

### Screenshot Centering (Phone-like proportions)

The screenshot image is displayed with phone-like proportions inside the slide frame. Corner radius gives a device-like appearance.

```python
PHONE_ASPECT = 19.5 / 9  # ~2.167
ss_h = round(H * height_ratio)
ss_w = round(ss_h / PHONE_ASPECT)
ss_x = round((W - ss_w) / 2)  # center horizontally
```

### macOS Screenshot Centering

```python
MAC_ASPECT = 16.0 / 10.0  # 1.6
ss_h = round(H * height_ratio)
ss_w = round(ss_h * MAC_ASPECT)
ss_x = round((W - ss_w) / 2)
```

### Layout A — Text top, screenshot bottom-center (hero shot)

```
Headline:  x=W*0.06, y=H*0.04,  w=W*0.88
Subtitle:  x=W*0.1,  y=H*0.13,  w=W*0.8,  opacity=0.75
Screenshot: h=H*0.74, w=h/aspect, x=(W-w)/2, y=H*0.24, cornerRadius=32
```

### Layout B — Text top-left, screenshot below centered

```
Headline:  x=W*0.06, y=H*0.04,  w=W*0.88, textAlign=left
Subtitle:  x=W*0.06, y=H*0.13,  w=W*0.8,  textAlign=left, opacity=0.75
Screenshot: h=H*0.74, w=h/aspect, x=(W-w)/2, y=H*0.24, cornerRadius=32
```

### Layout C — Screenshot top, text bottom

```
Screenshot: h=H*0.65, w=h/aspect, x=(W-w)/2, y=H*0.03, cornerRadius=32
Headline:  x=W*0.06, y=H*0.72,  w=W*0.88
Subtitle:  x=W*0.1,  y=H*0.81,  w=W*0.8,  opacity=0.75
```

### Layout D — Text top, large screenshot below

```
Headline:  x=W*0.06, y=H*0.04,  w=W*0.88
Subtitle:  x=W*0.1,  y=H*0.13,  w=W*0.8,  opacity=0.75
Screenshot: h=H*0.78, w=h/aspect, x=(W-w)/2, y=H*0.22, cornerRadius=32
```

### macOS Layouts (landscape)

```
Layout A (landscape):
  Headline:  x=W*0.06, y=H*0.04,  w=W*0.88
  Subtitle:  x=W*0.1,  y=H*0.16,  w=W*0.8,  opacity=0.75
  Screenshot: h=H*0.68, w=h*1.6, x=(W-w)/2, y=H*0.30, cornerRadius=16
```

### Composition Rules

- **Rotate layouts**: A, B, C, D, B, A — never repeat consecutively
- **Vary gradient angles**: 180°, 135°, 225°, 160°, 200° (when using gradient fallback)
- **First and last screenshots** should be the strongest (Layout A or D)
- **Use the app's own colors** from info.md or theme files

## Batch Operation Limits

Pencil MCP `batch_design` supports max 25 operations per call. For a typical slide (4 layers: bg, screenshot, headline, subtitle), you can build ~6 slides per batch call.

**Strategy for many devices**: Build one device at a time. For each device, batch all slides in 1-2 calls depending on slide count.

## Export

After generation, screenshots can be exported from Pencil:
1. Open the `.pen` file in Pencil
2. Select individual slide frames
3. Export as PNG at the exact device resolution
4. Upload to App Store Connect
