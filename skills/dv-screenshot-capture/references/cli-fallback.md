# CLI Fallback Adapter — Reference

Spec for `platform = "all"` and for the final fallback of the `apple`, `web`, and `android` adapters when their backing tools are unavailable. `scripts/cli-fallback.sh` is the executable implementation — read this file when debugging it or reproducing a step by hand.

Tool chain, in priority order: `silicon` (annotated diff PNG) → `magick`/ImageMagick (plain text-card PNG) → loud failure with no file written (see § Floor).

## silicon

```bash
BASE_REF="${base_ref:-origin/master}"
SLUG="${slug}"
OUT=".context/images/${WORKTASK_ID}/dv-${NN}-${SLUG}.png"

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
- `--language diff` gives syntax-highlighted diff coloring; `--theme`/`--font` fall back to any available theme/mono font, so `Dracula` and `Hack` are preferences, not requirements.
- Pipe only the relevant files (`-- <file>` filters) to keep the PNG under budget; pre-truncate a diff over ~200 lines with `head -200` to stay under 200 KB.
- Install where absent: `brew install silicon` or `cargo install silicon`. CI install is a follow-up (oq1) — the `.txt` floor keeps CI unblocked meanwhile.

## magick (ImageMagick)

```bash
BASE_REF="${base_ref:-origin/master}"
DIFF_CONTENT=$(git diff "${BASE_REF}...HEAD" -- "${selected_files[@]}" | head -60)
OUT=".context/images/${WORKTASK_ID}/dv-${NN}-${SLUG}.png"

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
- `caption:` auto-wraps to the canvas; `-size 1200x800` keeps typical diffs under 200 KB.
- ImageMagick 6.x ships `convert` instead of `magick`. Install where absent: `brew install imagemagick` / `apt-get install imagemagick`.

## Floor — loud failure, no placeholder

When no image tool produced a usable PNG, `scripts/cli-fallback.sh` writes **no file**. It emits the
adapter contract line with `ok=false` and exits non-zero, distinguishing two conditions that have
different remedies:

| Condition | `error` | Exit | Remedy |
|---|---|---|---|
| No image tool on PATH (or not a git repository) | `tool_missing` | 2 | Install `silicon` or ImageMagick |
| A tool ran but produced no usable PNG | `render_failed` | 3 | Read the stderr warning from that tool's step |

The audit row is `screenshot_capture_failed` (result `fail`) carrying `reason` and a
`tools_checked` string that names each tool as present or `(absent)`.

An earlier revision wrote a `.txt` diff dump here. It was removed because it satisfies an existence
check without being visual evidence: `attach-visual-evidence.sh` classified it as a `placeholder`
capture and DV completion counted it as evidence-of-attempt.

## Redaction before capture

Before piping any diff to `silicon` or `magick`, scan for secret patterns — this preserves the `logging-conventions § Bash Pattern` redact-before-tee discipline for visual artifacts:

```bash
# Detect common secret patterns; abort to tree-capture if found
if git diff "${BASE_REF}...HEAD" | grep -qE '(password|secret|token|api_key|private_key)\s*[=:]\s*["\x27][^"\x27]{8,}'; then
  echo "WARNING: Potential secret detected in diff. Falling back to file-tree capture." >&2
  git diff --name-only "${BASE_REF}...HEAD" | silicon --language text --output "${OUT}" || \
  git diff --name-only "${BASE_REF}...HEAD" > "${OUT}.txt"
fi
```
