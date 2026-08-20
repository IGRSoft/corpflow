# Layout Patterns (iOS/iPad/macOS)

Proportional `W*ratio` / `H*ratio` formulas — they scale to any device canvas. Encoded in
`../scripts/layout-calc.py`; read here only to verify a formula.

**IMPORTANT: Never use the same layout twice in a row.** Rotate through patterns.

## Screenshot Centering (Phone-like proportions)

The screenshot sits at phone-like proportions inside the slide frame; corner radius gives the device-like look.

```python
PHONE_ASPECT = 19.5 / 9  # ~2.167
ss_h = round(H * height_ratio)
ss_w = round(ss_h / PHONE_ASPECT)
ss_x = round((W - ss_w) / 2)  # center horizontally
```

## macOS Screenshot Centering

```python
MAC_ASPECT = 16.0 / 10.0  # 1.6
ss_h = round(H * height_ratio)
ss_w = round(ss_h * MAC_ASPECT)
ss_x = round((W - ss_w) / 2)
```

## Layout A — Text top, screenshot bottom-center (hero shot)

```
Headline:  x=W*0.06, y=H*0.04,  w=W*0.88
Subtitle:  x=W*0.1,  y=H*0.13,  w=W*0.8,  opacity=0.75
Screenshot: h=H*0.74, w=h/aspect, x=(W-w)/2, y=H*0.24, cornerRadius=32
```

## Layout B — Text top-left, screenshot below centered

```
Headline:  x=W*0.06, y=H*0.04,  w=W*0.88, textAlign=left
Subtitle:  x=W*0.06, y=H*0.13,  w=W*0.8,  textAlign=left, opacity=0.75
Screenshot: h=H*0.74, w=h/aspect, x=(W-w)/2, y=H*0.24, cornerRadius=32
```

## Layout C — Screenshot top, text bottom

```
Screenshot: h=H*0.65, w=h/aspect, x=(W-w)/2, y=H*0.03, cornerRadius=32
Headline:  x=W*0.06, y=H*0.72,  w=W*0.88
Subtitle:  x=W*0.1,  y=H*0.81,  w=W*0.8,  opacity=0.75
```

## Layout D — Text top, large screenshot below

```
Headline:  x=W*0.06, y=H*0.04,  w=W*0.88
Subtitle:  x=W*0.1,  y=H*0.13,  w=W*0.8,  opacity=0.75
Screenshot: h=H*0.78, w=h/aspect, x=(W-w)/2, y=H*0.22, cornerRadius=32
```

## macOS Layouts (landscape)

```
Layout A (landscape):
  Headline:  x=W*0.06, y=H*0.04,  w=W*0.88
  Subtitle:  x=W*0.1,  y=H*0.16,  w=W*0.8,  opacity=0.75
  Screenshot: h=H*0.68, w=h*1.6, x=(W-w)/2, y=H*0.30, cornerRadius=16
```

## Composition Rules

- **Rotate layouts**: A, B, C, D, B, A — never repeat consecutively
- **Vary gradient angles**: 180°, 135°, 225°, 160°, 200° (when using gradient fallback)
- **First and last screenshots** should be the strongest (Layout A or D)
- **Use the app's own colors** from info.md or theme files
