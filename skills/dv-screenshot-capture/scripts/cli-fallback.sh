#!/usr/bin/env bash
# @description  CLI fallback adapter for dv-screenshot-capture.
#               Default for platform="all"/meta-work AND the universal final fallback
#               for every other adapter (silicon → magick → .txt floor).
#               Applies redaction grep before piping diff to any image tool.
#
# @arg  --worktask-id <id>           state.json worktask_id (required)
# @arg  --slug <kebab>               kebab-case slug ≤40 chars (required)
# @arg  --base-ref <ref>             git base ref (default: origin/master)
# @arg  --platform <platform>        platform value recorded in manifest row
# @arg  --run-index <N>              run_index from state.json (default: 0)
# @arg  --files <path-to-filelist>   newline-separated file list to diff (optional)
# @arg  --self-test                  run built-in fixture tests; no network/git required
#
# @exitcode 0  success — path to produced file printed to stdout
# @exitcode 1  hard error (bad args, write failure)
# @exitcode 2  tool_missing — .txt placeholder written (ok=false path still on stdout)
#
# Contract (uniform adapter shape):
#   Prints one line to stdout:
#     path=<file>  bytes=<N>  ok=<true|false>  error=<null|tool_missing>
#
# Minimum shell: Bash 4.x (uses [[ ]], local, command -v; macOS ships Bash 3.2 —
# call via `bash <path>` from Homebrew Bash 5 if features require it).

set -euo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
WORKTASK_ID=""
SLUG=""
BASE_REF="origin/master"
PLATFORM="all"
RUN_INDEX="0"
FILES_PATH=""
SELF_TEST=0

usage() {
  cat >&2 << 'EOF'
usage: cli-fallback.sh
  --worktask-id <id>        worktask_id from state.json (required)
  --slug <kebab>            kebab-case slug ≤40 chars (required)
  [--base-ref <ref>]        git base ref (default: origin/master)
  [--platform <platform>]   platform label for manifest (default: all)
  [--run-index <N>]         run_index from state.json (default: 0)
  [--files <path>]          newline-separated file list to scope diff (optional)
  [--self-test]             run built-in self-tests; exits 0 on pass
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktask-id)
      WORKTASK_ID="${2:-}"
      shift 2
      ;;
    --slug)
      SLUG="${2:-}"
      shift 2
      ;;
    --base-ref)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --run-index)
      RUN_INDEX="${2:-}"
      shift 2
      ;;
    --files)
      FILES_PATH="${2:-}"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h | --help) usage ;;
    *)
      printf >&2 'error: unknown flag %s\n' "$1"
      usage
      ;;
  esac
done

# ---------------------------------------------------------------------------
# --self-test: no git, no network, no external deps beyond bash + printf
# ---------------------------------------------------------------------------
if [[ "$SELF_TEST" -eq 1 ]]; then
  PASS=0
  FAIL=0

  _ok() {
    printf 'PASS: %s\n' "$1"
    ((PASS++)) || true
  }
  _fail() {
    printf 'FAIL: %s\n' "$1"
    ((FAIL++)) || true
  }

  # --- Test 1: portable stat idiom works on a known file
  T1_FILE="${BASH_SOURCE[0]}"
  T1_BYTES=$(stat -f%z "$T1_FILE" 2> /dev/null || stat -c%s "$T1_FILE" 2> /dev/null || echo 0)
  if [[ "$T1_BYTES" -gt 0 ]]; then
    _ok "portable stat returns non-zero for this script"
  else
    _fail "portable stat returned 0 for ${T1_FILE}"
  fi

  # --- Test 2: redaction pattern detection
  TMPDIR_TEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_TEST"' EXIT
  FAKE_DIFF="${TMPDIR_TEST}/fake.diff"
  printf 'password = "supersecret123"\n' > "$FAKE_DIFF"
  if grep -qE '(password|secret|token|api_key|private_key)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{8,}' "$FAKE_DIFF"; then
    _ok "redaction pattern fires on fake secret"
  else
    _fail "redaction pattern missed fake secret"
  fi

  # --- Test 3: safe diff (no secret) does NOT match redaction pattern
  SAFE_DIFF="${TMPDIR_TEST}/safe.diff"
  printf '+func foo() { return 42 }\n' > "$SAFE_DIFF"
  if ! grep -qE '(password|secret|token|api_key|private_key)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{8,}' "$SAFE_DIFF"; then
    _ok "redaction pattern leaves safe diff alone"
  else
    _fail "redaction pattern false-positive on safe diff"
  fi

  # --- Test 4: .txt placeholder write (simulates tool_missing floor)
  TXT_DIR="${TMPDIR_TEST}/images/self-test-wt"
  mkdir -p "$TXT_DIR"
  TXT_FILE="${TXT_DIR}/dv-01-self-test.txt"
  {
    printf '# Screenshot placeholder — self-test\n'
    printf '# Worktask: self-test-wt\n'
    printf '# Run index: 0\n'
    printf '# Captured: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# Platform: all\n'
    printf '# Reason: tool_missing — silicon and magick both absent on PATH\n'
    printf '# Tools checked: silicon, magick\n'
    printf '\ngit diff origin/master...HEAD (first 100 lines):\n'
    printf -- '---\n'
    printf '(self-test: no git diff)\n'
  } > "$TXT_FILE"
  TXT_BYTES=$(stat -f%z "$TXT_FILE" 2> /dev/null || stat -c%s "$TXT_FILE" 2> /dev/null || echo 0)
  if [[ "$TXT_BYTES" -gt 0 ]] && [[ -f "$TXT_FILE" ]]; then
    _ok ".txt placeholder written and non-empty"
  else
    _fail ".txt placeholder write failed or empty"
  fi

  # --- Test 5: NN counter picks up existing files
  PNG1="${TXT_DIR}/dv-01-foo.png"
  PNG2="${TXT_DIR}/dv-02-bar.png"
  printf 'x' > "$PNG1"
  printf 'x' > "$PNG2"
  existing_count=$(find "$TXT_DIR" -maxdepth 1 -type f -name 'dv-*.png' 2> /dev/null | wc -l | tr -d ' ')
  NN=$(printf '%02d' $((existing_count + 1)))
  if [[ "$NN" == "03" ]]; then
    _ok "NN counter increments correctly (existing=2 → next=03)"
  else
    _fail "NN counter wrong: expected 03, got ${NN}"
  fi

  printf '\nself-test: %d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# Required arg validation
# ---------------------------------------------------------------------------
[[ -z "$WORKTASK_ID" ]] && {
  printf >&2 'error: --worktask-id required\n'
  usage
}
[[ -z "$SLUG" ]] && {
  printf >&2 'error: --slug required\n'
  usage
}

# Slug safety: kebab-case, ≤40 chars, no injection
if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]; then
  printf >&2 'error: --slug must be kebab-case ≤40 chars (got: %s)\n' "$SLUG"
  exit 1
fi

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
IMAGES_DIR=".context/images/${WORKTASK_ID}"
LOGS_DIR=".context/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"

# Compute next NN (monotonic, never reset across reruns per SKILL.md)
existing_count=$(find "$IMAGES_DIR" -maxdepth 1 -type f -name 'dv-*.png' 2> /dev/null | wc -l | tr -d ' ')
NN=$(printf '%02d' $((existing_count + 1)))
OUTPUT_PNG="${IMAGES_DIR}/dv-${NN}-${SLUG}.png"
OUTPUT_TXT="${IMAGES_DIR}/dv-${NN}-${SLUG}.txt"

# ---------------------------------------------------------------------------
# Audit helper (mirrors apple-canvas.sh idiom exactly)
# ---------------------------------------------------------------------------
audit() {
  local action="$1"
  local result="$2"
  local metadata="$3"
  local ts
  ts="$(date -u +%FT%TZ)"
  if command -v jq > /dev/null 2>&1; then
    jq -nc \
      --arg ts "$ts" \
      --arg actor "cli-fallback-adapter" \
      --arg action "$action" \
      --arg subject "${WORKTASK_ID}/${SLUG}" \
      --arg result "$result" \
      --argjson metadata "$metadata" \
      '{ts:$ts, actor:$actor, action:$action, subject:$subject, result:$result, metadata:$metadata}' \
      >> "$AUDIT_LOG"
  else
    # jq absent — emit minimal JSON manually (safe: all values are controlled)
    printf '{"ts":"%s","actor":"cli-fallback-adapter","action":"%s","subject":"%s/%s","result":"%s"}\n' \
      "$ts" "$action" "$WORKTASK_ID" "$SLUG" "$result" >> "$AUDIT_LOG"
  fi
}

# ---------------------------------------------------------------------------
# Build file-scope arg array for git diff
# ---------------------------------------------------------------------------
# FILES_PATH is a path to a newline-delimited file list; if absent, no filter.
declare -a DIFF_FILES=()
if [[ -n "$FILES_PATH" ]] && [[ -f "$FILES_PATH" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    DIFF_FILES+=("$line")
  done < "$FILES_PATH"
fi

# ---------------------------------------------------------------------------
# Redaction check — scan diff for secret patterns before any rendering
# (follows logging-conventions § Bash Pattern; see SKILL.md § Redaction)
# If triggered, fall back to file-tree capture instead of full diff.
# ---------------------------------------------------------------------------
_diff_args=("${BASE_REF}...HEAD")
if [[ "${#DIFF_FILES[@]}" -gt 0 ]]; then
  _diff_args+=("--" "${DIFF_FILES[@]}")
fi

REDACTED=0
if git rev-parse --git-dir > /dev/null 2>&1; then
  # shellcheck disable=SC2086  # intentional — _diff_args is an array
  if git diff "${_diff_args[@]}" 2> /dev/null \
    | grep -qE '(password|secret|token|api_key|private_key)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{8,}'; then
    printf >&2 'warn: potential secret detected in diff; falling back to file-tree capture\n'
    REDACTED=1
  fi
fi

# ---------------------------------------------------------------------------
# Tool availability checks (guard-first so --self-test never needs them)
# ---------------------------------------------------------------------------
HAS_SILICON=0
HAS_MAGICK=0
command -v silicon > /dev/null 2>&1 && HAS_SILICON=1
command -v magick > /dev/null 2>&1 && HAS_MAGICK=1
# Older ImageMagick 6.x uses `convert` instead of `magick`
HAS_CONVERT=0
command -v convert > /dev/null 2>&1 && HAS_CONVERT=1

# ---------------------------------------------------------------------------
# Step 1 — silicon (preferred): annotated diff PNG
# ---------------------------------------------------------------------------
if [[ "$HAS_SILICON" -eq 1 ]] && git rev-parse --git-dir > /dev/null 2>&1; then
  if [[ "$REDACTED" -eq 1 ]]; then
    # Secret detected — render file-tree only
    RENDER_OK=0
    set +e
    git diff --name-only "${BASE_REF}...HEAD" 2> /dev/null \
      | head -200 \
      | silicon --language text --output "$OUTPUT_PNG" \
        --theme Dracula --no-line-number \
        --pad-horiz 20 --pad-vert 20
    RENDER_OK=$?
    set -e
  else
    RENDER_OK=0
    set +e
    git diff "${_diff_args[@]}" 2> /dev/null \
      | head -200 \
      | silicon \
        --language diff \
        --theme Dracula \
        --no-line-number \
        --pad-horiz 20 \
        --pad-vert 20 \
        --output "$OUTPUT_PNG"
    RENDER_OK=$?
    set -e
  fi

  if [[ "$RENDER_OK" -eq 0 ]] && [[ -f "$OUTPUT_PNG" ]]; then
    BYTES=$(stat -f%z "$OUTPUT_PNG" 2> /dev/null || stat -c%s "$OUTPUT_PNG" 2> /dev/null || echo 0)
    audit screenshot_captured ok "$(
      jq -nc \
        --arg slug "$SLUG" \
        --arg path "$OUTPUT_PNG" \
        --argjson bytes "$BYTES" \
        --arg platform "$PLATFORM" \
        --arg adapter "cli_fallback/silicon" \
        '{slug:$slug,path:$path,bytes:$bytes,platform:$platform,adapter:$adapter}'
    )"
    printf 'path=%s bytes=%d ok=true error=null\n' "$OUTPUT_PNG" "$BYTES"
    exit 0
  fi
  printf >&2 'warn: silicon render failed; trying magick\n'
fi

# ---------------------------------------------------------------------------
# Step 2 — magick/convert: text-card PNG from first 60 diff lines
# ---------------------------------------------------------------------------
MAGICK_CMD=""
if [[ "$HAS_MAGICK" -eq 1 ]]; then
  MAGICK_CMD="magick"
elif [[ "$HAS_CONVERT" -eq 1 ]]; then
  MAGICK_CMD="convert"
fi

if [[ -n "$MAGICK_CMD" ]] && git rev-parse --git-dir > /dev/null 2>&1; then
  if [[ "$REDACTED" -eq 1 ]]; then
    DIFF_CONTENT="[redacted: secret pattern detected]\n\nFiles changed:\n$(git diff --name-only "${BASE_REF}...HEAD" 2> /dev/null | head -60 || true)"
  else
    DIFF_CONTENT=$(git diff "${_diff_args[@]}" 2> /dev/null | head -60 || true)
  fi

  RENDER_OK=0
  set +e
  "$MAGICK_CMD" \
    -background white \
    -fill black \
    -font Courier \
    -pointsize 13 \
    -size 1200x800 \
    "caption:${SLUG}\n\n${DIFF_CONTENT}" \
    "$OUTPUT_PNG"
  RENDER_OK=$?
  set -e

  if [[ "$RENDER_OK" -eq 0 ]] && [[ -f "$OUTPUT_PNG" ]]; then
    BYTES=$(stat -f%z "$OUTPUT_PNG" 2> /dev/null || stat -c%s "$OUTPUT_PNG" 2> /dev/null || echo 0)
    audit screenshot_captured ok "$(
      jq -nc \
        --arg slug "$SLUG" \
        --arg path "$OUTPUT_PNG" \
        --argjson bytes "$BYTES" \
        --arg platform "$PLATFORM" \
        --arg adapter "cli_fallback/magick" \
        '{slug:$slug,path:$path,bytes:$bytes,platform:$platform,adapter:$adapter}'
    )"
    printf 'path=%s bytes=%d ok=true error=null\n' "$OUTPUT_PNG" "$BYTES"
    exit 0
  fi
  printf >&2 'warn: magick render failed; writing .txt placeholder\n'
fi

# ---------------------------------------------------------------------------
# Step 3 — .txt placeholder (floor — always succeeds)
# ---------------------------------------------------------------------------
TOOLS_CHECKED="silicon"
[[ -n "$MAGICK_CMD" ]] && TOOLS_CHECKED="${TOOLS_CHECKED}, magick" || TOOLS_CHECKED="${TOOLS_CHECKED}, magick"

{
  printf '# Screenshot placeholder — %s\n' "$SLUG"
  printf '# Worktask: %s\n' "$WORKTASK_ID"
  printf '# Run index: %s\n' "$RUN_INDEX"
  printf '# Captured: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# Platform: %s\n' "$PLATFORM"
  printf '# Reason: tool_missing — silicon and magick both absent on PATH\n'
  printf '# Tools checked: silicon, magick\n'
  printf '\ngit diff %s...HEAD (first 100 lines):\n' "$BASE_REF"
  printf -- '---\n'
  if git rev-parse --git-dir > /dev/null 2>&1; then
    if [[ "$REDACTED" -eq 1 ]]; then
      printf '[redacted: secret pattern detected; showing file list only]\n'
      git diff --name-only "${BASE_REF}...HEAD" 2> /dev/null | head -100 || true
    else
      git diff "${_diff_args[@]}" 2> /dev/null | head -100 || true
    fi
  else
    printf '(not a git repository)\n'
  fi
} > "$OUTPUT_TXT"

TXT_BYTES=$(stat -f%z "$OUTPUT_TXT" 2> /dev/null || stat -c%s "$OUTPUT_TXT" 2> /dev/null || echo 0)

audit screenshot_tool_missing ok "$(
  jq -nc \
    --arg tools_checked "silicon, magick" \
    --arg slug "$SLUG" \
    --arg path "$OUTPUT_TXT" \
    --arg platform "$PLATFORM" \
    '{tools_checked:$tools_checked,slug:$slug,path:$path,platform:$platform}'
)" 2> /dev/null || true

printf 'path=%s bytes=%d ok=false error=tool_missing\n' "$OUTPUT_TXT" "$TXT_BYTES"
exit 2
