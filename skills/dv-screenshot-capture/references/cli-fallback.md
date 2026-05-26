# CLI Fallback Adapter — Reference

Used when `platform = "all"` or as the final fallback for `apple`, `web`, and `android` adapters when their backing tools are unavailable.

## Tool chain (priority order)

1. `silicon` — preferred; annotated diff PNG
2. `magick` (ImageMagick) — fallback; plain text-card PNG
3. `.txt` placeholder — floor; no visual, but evidence-of-attempt

## silicon

### Install check

```bash
which silicon 2>/dev/null && echo "available" || echo "absent"
```

### Render git diff as annotated PNG

```bash
BASE_REF="${base_ref:-origin/master}"
SLUG="${slug}"
OUT=".context/images/${WORKFLOW_ID}/dv-${NN}-${SLUG}.png"

git diff "${BASE_REF}...HEAD" -- "${selected_files[@]}" \
  | silicon \
      --language diff \
      --theme "Dracula" \
      --font "Hack" \
      --output "${OUT}" \
      --no-line-number \
      --pad-horiz 20 \
      --pad-vert 20
```

**Notes**:
- `--language diff` gives syntax-highlighted diff coloring.
- `--theme` defaults to any available theme; `Dracula` is aesthetically clear for diffs.
- `--font` falls back to any mono font if `Hack` is absent.
- Pipe only the relevant files to keep file size under budget. Use `-- <file>` filters.
- If the diff exceeds ~200 lines, pre-truncate with `head -200` before piping to stay under 200 KB.

### Install (if absent on developer machine)

```bash
brew install silicon        # macOS
cargo install silicon       # cross-platform via Rust
```

CI install is a follow-up (oq1). For CI, the `.txt` placeholder floor ensures no run is blocked.

## magick (ImageMagick)

### Install check

```bash
which magick 2>/dev/null || which convert 2>/dev/null && echo "available" || echo "absent"
```

### Render first 60 lines of diff as text-card PNG

```bash
BASE_REF="${base_ref:-origin/master}"
DIFF_CONTENT=$(git diff "${BASE_REF}...HEAD" -- "${selected_files[@]}" | head -60)
OUT=".context/images/${WORKFLOW_ID}/dv-${NN}-${SLUG}.png"

magick \
  -background white \
  -fill black \
  -font "Courier" \
  -pointsize 13 \
  -size 1200x800 \
  caption:"${SLUG}\n\n${DIFF_CONTENT}" \
  "${OUT}"
```

**Notes**:
- `caption:` auto-wraps text to fit the canvas size.
- `-size 1200x800` keeps the PNG under 200 KB for typical diff lengths.
- Use `convert` instead of `magick` on older ImageMagick 6.x installations.

### Install (if absent)

```bash
brew install imagemagick    # macOS
apt-get install imagemagick # Debian/Ubuntu
```

## .txt placeholder (floor)

When both `silicon` and `magick` are absent, write a plain-text placeholder. The screenshots.md manifest records it; DV completion counts it as evidence-of-attempt.

### Schema

```
# Screenshot placeholder — <slug>
# Workflow: <workflow_id>
# Run index: <N>
# Captured: <ISO-8601 UTC>
# Platform: <platform>
# Reason: tool_missing — silicon and magick both absent on PATH
# Tools checked: silicon, magick

git diff origin/master...HEAD (first 100 lines):
---
<raw diff text, 100 line max>
```

### Write command

```bash
OUT=".context/images/${WORKFLOW_ID}/dv-${NN}-${SLUG}.txt"
{
  echo "# Screenshot placeholder — ${SLUG}"
  echo "# Workflow: ${WORKFLOW_ID}"
  echo "# Run index: ${RUN_INDEX}"
  echo "# Captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Platform: ${PLATFORM}"
  echo "# Reason: tool_missing — silicon and magick both absent on PATH"
  echo "# Tools checked: silicon, magick"
  echo ""
  echo "git diff ${BASE_REF}...HEAD (first 100 lines):"
  echo "---"
  git diff "${BASE_REF}...HEAD" -- "${selected_files[@]}" | head -100
} > "${OUT}"
```

The `.txt` file is committed (it IS the evidence artifact). `ok: false`, `error: "tool_missing"` in the return shape.

## Redaction before capture

Before piping any diff to `silicon` or `magick`, scan for secret patterns:

```bash
# Detect common secret patterns; abort to tree-capture if found
if git diff "${BASE_REF}...HEAD" | grep -qE '(password|secret|token|api_key|private_key)\s*[=:]\s*["\x27][^"\x27]{8,}'; then
  echo "WARNING: Potential secret detected in diff. Falling back to file-tree capture." >&2
  git diff --name-only "${BASE_REF}...HEAD" | silicon --language text --output "${OUT}" || \
  git diff --name-only "${BASE_REF}...HEAD" > "${OUT}.txt"
fi
```

This preserves the `logging-conventions § Bash Pattern` redact-before-tee discipline for visual artifacts.
