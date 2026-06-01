# Fixture 02 — Multi-frame section (container) node

Exercises the container-aware per-frame descent. Modeled on the real OV-76 section
`255-2263` ("SKIN ANALYSIS – FACE SCAN") holding 4 child frames (25% / hint / 100% /
analyzing). The PM captures the container once as an overview AND each child frame
individually, persisting 5 PNGs and writing 5 registry rows (1 overview + 4 frames).

Primary ACs: **AC-1** (container of N≥2 frames → N per-frame PNGs + 1 overview),
**AC-3** (each persisted file verified), **AC-4** (one registry row per frame +
overview row), **AC-5** (design-preview lists every persisted per-frame file with
per-state build notes).

## Input

Task description contains:

```
https://www.figma.com/design/FOO/FaceScan?node-id=255-2263
```

## Node classification (`get_metadata`)

```
node 255:2263  type=SECTION  name="SKIN ANALYSIS – FACE SCAN"
  children:
    255:2264  type=FRAME  name="Scan 25"
    255:2265  type=FRAME  name="Scan Hint"
    255:2266  type=FRAME  name="Scan 100"
    255:2267  type=FRAME  name="Analyzing"
```

→ **Container** (SECTION with ≥ 2 direct `frame` children). Descend one level.
Targets = `255:2263` (overview) + the 4 child frames. Under the R2 cap (first 12),
all 4 are captured; no cap note needed.

## Expected persisted files (`.context/designs/`)

Exactly **5** PNGs (1 overview + 4 frames), all verified non-zero:

```
figma-skin-analysis-face-scan-overview-255-2263.png   # overview (container)
figma-scan-25-default-255-2264.png
figma-scan-hint-default-255-2265.png
figma-scan-100-default-255-2266.png
figma-analyzing-default-255-2267.png
```

(States shown as `default` here because the input URL carried no per-frame state
annotations; per-frame states appear when the user annotates them.)

## Expected registry rows (`figma-registry.md`)

Exactly **5** Entries rows — one `overview` row keyed on the container id plus one
row per child frame keyed on its **own** node id:

| ID | Screen | State | Figma Node | Screenshot |
|----|--------|-------|------------|------------|
| design-001 | skin-analysis-face-scan | overview | 255:2263 | figma-skin-analysis-face-scan-overview-255-2263.png |
| design-002 | scan-25 | default | 255:2264 | figma-scan-25-default-255-2264.png |
| design-003 | scan-hint | default | 255:2265 | figma-scan-hint-default-255-2265.png |
| design-004 | scan-100 | default | 255:2266 | figma-scan-100-default-255-2266.png |
| design-005 | analyzing | default | 255:2267 | figma-analyzing-default-255-2267.png |

## Expected design-preview (`<plan_file> § design-preview`)

The original URL line PLUS one line per persisted file (overview + 4 frames), each
frame line carrying its state mapping and per-frame build notes:

- `figma-skin-analysis-face-scan-overview-255-2263.png` — container overview (all 4 states).
- `figma-scan-25-default-255-2264.png` — state `default` — 25% progress ring, hint text hidden.
- `figma-scan-hint-default-255-2265.png` — state `default` — hint banner visible, ring mid.
- `figma-scan-100-default-255-2266.png` — state `default` — 100% ring, success badge.
- `figma-analyzing-default-255-2267.png` — state `default` — spinner, "Analyzing…" label.

## Over-capture cap (R2)

If the container had > 12 child frames, the PM captures the first 12 in document order
and appends to `.context/errors/product-manager.md`:
`R2 over-capture cap hit: container 255:2263 has <N> frames, captured first 12`.

## Per-URL MCP failure (R-continue)

If one frame's MCP call or persist fails, the PM continues with the remaining frames,
writes the registry with the successfully-persisted rows, records the failed frame with
`failed: true` + an open question, and never blocks.

## Assertions (QA)

- [ ] Exactly 5 PNGs persisted (1 overview + 4 frames); all verified non-zero.
- [ ] Exactly 5 registry rows: 1 `overview` row (container id) + 4 frame rows (own ids).
- [ ] Each frame row's `Figma Node` is the child id, not the container id.
- [ ] design-preview lists all 5 files with per-state build notes (AC-5).
- [ ] QA Design Comparison emits 5 comparison rows (per-frame), not 1 combined.
