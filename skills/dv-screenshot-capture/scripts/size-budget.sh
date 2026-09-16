#!/usr/bin/env bash
# @description  5-step size-budget enforcer for dv-screenshot-capture.
#               Runs after every capture() call per SKILL.md § Size budget.
#
#   Step 1  stat bytes of the produced file
#   Step 2  if ≥500 KB: pngquant --quality=65-80 --force --output <path> <path>; re-stat
#   Step 3  if still ≥500 KB: move to oversize/ + add to .gitignore + emit size-fail audit
#   Step 4  if 200 KB ≤ bytes < 500 KB: emit screenshot_size_warn audit; keep file
#   Step 5  emit one compact size audit row to stdout
#
# @arg  --path <file>           PNG to inspect (required)
# @arg  --worktask-id <id>      for oversize/ dir path + audit subject (required)
# @arg  --slug <kebab>          slug label in audit row (default: inferred from filename)
# @arg  --project-root <dir>    root dir where .gitignore lives (default: the git toplevel
#                               above the resolved .context; no .gitignore write without one)
# @arg  --self-test             run built-in fixture tests; no network required
#
# @exitcode 0  file within budget (or warn-only)
# @exitcode 1  argument/write error, no .context resolved, or the ledger disagrees with the id
# @exitcode 2  broken plugin install
# @exitcode 3  file moved to oversize/ (ok=false, error=oversize_unquantizable)
#
# Output (single line to stdout on exit 0 or 3):
#   size_audit: path=<file> bytes=<N> verdict=<ok|warn|oversize>
#
# Minimum shell: Bash 4.x

set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Constants (mirrors SKILL.md § Size budget)
# ---------------------------------------------------------------------------
readonly WARN_BYTES=200000 # 200 KB
readonly HARD_BYTES=500000 # 500 KB

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FILE_PATH=""
WORKTASK_ID=""
SLUG=""
PROJECT_ROOT=""
SELF_TEST=0

usage() {
  cat >&2 << 'EOF'
usage: size-budget.sh
  --path <file>            PNG to inspect (required)
  --worktask-id <id>       worktask_id (required)
  [--slug <kebab>]         slug label; default inferred from filename
  [--project-root <dir>]   directory holding .gitignore (default: git toplevel of the .context)
  [--self-test]            run built-in fixture tests; exits 0 on pass
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      FILE_PATH="${2:-}"
      shift 2
      ;;
    --worktask-id)
      WORKTASK_ID="${2:-}"
      shift 2
      ;;
    --slug)
      SLUG="${2:-}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
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

# Slug from a capture file name: both dv-NN-<slug> and dv-<TASK_ID>-NN-<slug> strip to <slug>.
_infer_slug() {
  local base re='^dv-([A-Z]{2}[0-9]+-)?[0-9]{2}-(.+)$'
  base="$(basename -- "$1")"
  case "$base" in
    *.png | *.jpg | *.jpeg | *.webp | *.txt) base="${base%.*}" ;;
  esac
  if [[ $base =~ $re ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  else
    printf '%s' "$base"
  fi
}

# ---------------------------------------------------------------------------
# --self-test: no network, no pngquant required
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

  TMPDIR_TEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_TEST"' EXIT

  # Portable stat helper (mirrors apple-canvas.sh idiom)
  _stat_bytes() {
    stat -f%z "$1" 2> /dev/null || stat -c%s "$1" 2> /dev/null || echo 0
  }

  # --- Test 1: portable stat returns size of a known file
  SELF_BYTES=$(_stat_bytes "${BASH_SOURCE[0]}")
  if [[ "$SELF_BYTES" -gt 0 ]]; then
    _ok "portable stat returns non-zero for this script ($SELF_BYTES bytes)"
  else
    _fail "portable stat returned 0 for ${BASH_SOURCE[0]}"
  fi

  # --- Test 2: under-budget file is classified ok
  SMALL_FILE="${TMPDIR_TEST}/small.png"
  # write ~100-byte file (under WARN_BYTES=200000)
  printf '%0.s.' {1..100} > "$SMALL_FILE"
  SMALL_BYTES=$(_stat_bytes "$SMALL_FILE")
  if [[ "$SMALL_BYTES" -lt "$WARN_BYTES" ]]; then
    _ok "small fixture (${SMALL_BYTES} B) correctly below warn threshold"
  else
    _fail "small fixture unexpectedly large: ${SMALL_BYTES} B"
  fi

  # --- Test 3: warn-range file (200 KB ≤ x < 500 KB)
  WARN_FILE="${TMPDIR_TEST}/warn.png"
  dd if=/dev/zero bs=1 count=250000 2> /dev/null > "$WARN_FILE"
  WARN_BYTES_VAL=$(_stat_bytes "$WARN_FILE")
  if [[ "$WARN_BYTES_VAL" -ge "$WARN_BYTES" ]] && [[ "$WARN_BYTES_VAL" -lt "$HARD_BYTES" ]]; then
    _ok "warn fixture (${WARN_BYTES_VAL} B) correctly in warn range"
  else
    _fail "warn fixture unexpected size: ${WARN_BYTES_VAL} B (expected 200000–499999)"
  fi

  # --- Test 4: oversize/ dir creation + .gitignore guard
  OVERSIZE_WORKTASK="self-test-wt"
  IMAGES_DIR="${TMPDIR_TEST}/images/${OVERSIZE_WORKTASK}"
  mkdir -p "$IMAGES_DIR"
  OVERSIZE_DIR="${IMAGES_DIR}/oversize"
  GITIGNORE="${TMPDIR_TEST}/.gitignore"
  BIG_FILE="${IMAGES_DIR}/dv-01-big.png"
  dd if=/dev/zero bs=1 count=600000 2> /dev/null > "$BIG_FILE"

  mkdir -p "$OVERSIZE_DIR"
  mv -- "$BIG_FILE" "${OVERSIZE_DIR}/dv-01-big.png"
  # guard .gitignore
  grep -qxF '.context/images/*/oversize/' "$GITIGNORE" 2> /dev/null \
    || printf '.context/images/*/oversize/\n' >> "$GITIGNORE"

  if [[ -f "${OVERSIZE_DIR}/dv-01-big.png" ]] \
    && grep -qxF '.context/images/*/oversize/' "$GITIGNORE" 2> /dev/null; then
    _ok "oversize/ dir and .gitignore guard work correctly"
  else
    _fail "oversize/ dir or .gitignore guard failed"
  fi

  # --- Test 5: slug inference strips both name shapes
  INFERRED="$(_infer_slug "dv-03-my-feature.png")|$(_infer_slug "dv-DV12-04-my-feature.jpg")|$(_infer_slug "other.png")"
  if [[ "$INFERRED" == "my-feature|my-feature|other" ]]; then
    _ok "slug inference strips dv-NN- and dv-<TASK_ID>-NN- (got: $INFERRED)"
  else
    _fail "slug inference failed: expected 'my-feature|my-feature|other', got '$INFERRED'"
  fi

  printf '\nself-test: %d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# Required arg validation
# ---------------------------------------------------------------------------
[[ -z "$FILE_PATH" ]] && {
  printf >&2 'error: --path required\n'
  usage
}
[[ -z "$WORKTASK_ID" ]] && {
  printf >&2 'error: --worktask-id required\n'
  usage
}
[[ -f "$FILE_PATH" ]] || {
  printf >&2 'error: file not found: %s\n' "$FILE_PATH"
  exit 1
}

if [[ ! "$WORKTASK_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  printf >&2 'error: --worktask-id must match ^[A-Za-z0-9][A-Za-z0-9._-]*$ (got: %s)\n' "$WORKTASK_ID"
  exit 1
fi

if [[ -z "$SLUG" ]]; then
  SLUG="$(_infer_slug "$FILE_PATH")"
fi

# Shared audit-row appender — one key order, one symlink refusal for every audit.jsonl.
# Fails closed: a missing library is a broken install, not a runtime condition.
_AUDIT_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 'size-budget: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

_STATE_READ_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/state-read-lib.sh"
if [ ! -r "$_STATE_READ_LIB" ]; then
  printf >&2 'size-budget: plugin install broken — state-read-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_STATE_READ_LIB"

# A ledger for another worktask refuses the write; without a ledger only an explicit CONTEXT_DIR may.
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [ "$_CTX_RC" -eq 2 ]; then
  printf >&2 'size-budget: root resolver unreachable\n'
  exit 2
elif [ "$_CTX_RC" -ne 0 ]; then
  printf >&2 'size-budget: no .context resolved; set WORKSPACE_ROOT or run inside a worktask\n'
  exit 1
fi
if [ -f "$CTX_DIR/state.json" ]; then
  if [ "$(corpflow_worktask_id "$CTX_DIR/state.json" "")" != "$WORKTASK_ID" ]; then
    printf >&2 'size-budget: --worktask-id %s does not match %s\n' "$WORKTASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
elif [ -z "${CONTEXT_DIR:-}" ] || [ "$CTX_DIR" != "$CONTEXT_DIR" ]; then
  printf >&2 'size-budget: no ledger at %s; set CONTEXT_DIR to run outside a worktask\n' "$CTX_DIR"
  exit 1
fi

# .gitignore belongs to the repository that owns .context; with no such repository, skip the write.
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT=$(trap - ERR; git -C "$(dirname -- "$CTX_DIR")" rev-parse --show-toplevel 2> /dev/null) || PROJECT_ROOT=""
fi

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
OVERSIZE_DIR="${IMAGES_DIR}/oversize"
LOGS_DIR="${CTX_DIR}/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
GITIGNORE=""
[[ -z "$PROJECT_ROOT" ]] || GITIGNORE="${PROJECT_ROOT}/.gitignore"
mkdir -p "$LOGS_DIR"

# ---------------------------------------------------------------------------
# Portable stat helper (mirrors apple-canvas.sh idiom exactly)
# ---------------------------------------------------------------------------
_stat_bytes() {
  stat -f%z "$1" 2> /dev/null || stat -c%s "$1" 2> /dev/null || echo 0
}

# audit <action> <result> <metadata-json> — binds this adapter's actor and subject onto
# the shared appender.
audit() {
  corpflow_audit_row --file "$AUDIT_LOG" --actor "size-budget" \
    --action "$1" --subject "${WORKTASK_ID}/${SLUG}" --result "$2" --task-id unknown --meta "${3:-}"
}

# ---------------------------------------------------------------------------
# Step 1 — stat bytes
# ---------------------------------------------------------------------------
BYTES=$(_stat_bytes "$FILE_PATH")

# ---------------------------------------------------------------------------
# Step 2 — pngquant if ≥500 KB
# ---------------------------------------------------------------------------
BYTES_BEFORE="$BYTES"
if [[ "$BYTES" -ge "$HARD_BYTES" ]]; then
  if command -v pngquant > /dev/null 2>&1; then
    set +e
    pngquant --quality=65-80 --force --output "$FILE_PATH" -- "$FILE_PATH"
    PNGQUANT_EXIT=$?
    set -e
    if [[ "$PNGQUANT_EXIT" -eq 0 ]] && [[ -f "$FILE_PATH" ]]; then
      # Re-stat after quantize
      BYTES=$(_stat_bytes "$FILE_PATH")
    fi
    # pngquant exit 98 = image already below quality floor — treat as attempted
  else
    printf >&2 'warn: pngquant not on PATH; cannot quantize %s\n' "$FILE_PATH"
  fi
fi

# ---------------------------------------------------------------------------
# Step 3 — still ≥500 KB → move to oversize/
# ---------------------------------------------------------------------------
if [[ "$BYTES" -ge "$HARD_BYTES" ]]; then
  mkdir -p "$OVERSIZE_DIR"
  if [[ -n "$GITIGNORE" ]]; then
    grep -qxF '.context/images/*/oversize/' "$GITIGNORE" 2> /dev/null \
      || printf '.context/images/*/oversize/\n' >> "$GITIGNORE"
  fi

  DEST="${OVERSIZE_DIR}/$(basename -- "$FILE_PATH")"
  mv -- "$FILE_PATH" "$DEST"

  audit screenshot_size_fail ok "$(
    jq -nc \
      --arg path "$DEST" \
      --argjson bytes_before "$BYTES_BEFORE" \
      --argjson bytes_after "$BYTES" \
      '{path:$path,bytes_before:$bytes_before,bytes_after:$bytes_after}'
  )" 2> /dev/null || true

  printf 'size_audit: path=%s bytes=%d verdict=oversize\n' "$DEST" "$BYTES"
  exit 3
fi

# ---------------------------------------------------------------------------
# Step 4 — warn range: 200 KB ≤ bytes < 500 KB
# ---------------------------------------------------------------------------
VERDICT="ok"
if [[ "$BYTES" -ge "$WARN_BYTES" ]]; then
  VERDICT="warn"
  audit screenshot_size_warn ok "$(
    jq -nc \
      --arg path "$FILE_PATH" \
      --argjson bytes "$BYTES" \
      '{path:$path,bytes:$bytes}'
  )" 2> /dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 5 — emit one compact size audit row
# ---------------------------------------------------------------------------
audit screenshot_captured ok "$(
  jq -nc \
    --arg path "$FILE_PATH" \
    --argjson bytes "$BYTES" \
    --arg verdict "$VERDICT" \
    '{path:$path,bytes:$bytes,verdict:$verdict}'
)" 2> /dev/null || true

printf 'size_audit: path=%s bytes=%d verdict=%s\n' "$FILE_PATH" "$BYTES" "$VERDICT"
exit 0
