#!/usr/bin/env bash
# @description  Web platform adapter for dv-screenshot-capture.
#               Drives Playwright's `screenshot` CLI against a URL and writes a
#               PNG at <ctx>/images/<id>/dv-<TASK_ID>-NN-<slug>.png, where <ctx> comes
#               from the shared root ladder (never cwd).
#               Pure CLI — needs no MCP grant, so the delegated platform agent
#               (or a direct caller) can run it unchanged.
#
#               Playwright absent → exit 2 (tool_missing) and the caller routes
#               to cli_fallback per SKILL.md § fallback ladder. Navigation or
#               timeout failure → exit 3 (capture_failed), same route. Neither
#               is a hard DV failure.
#
# @arg  --worktask-id <id>       state.json worktask_id (required)
# @arg  --task-id <TASK_ID>      DV task id naming the evidence stream (required)
# @arg  --slug <kebab>           kebab-case slug ≤40 chars (required)
# @arg  --url <url>              http/https/file URL to capture (required)
# @arg  --viewport <WxH>         viewport in pixels (default: 1280x800)
# @arg  --browser <name>         chromium|firefox|webkit (default: chromium)
# @arg  --timeout <ms>           Playwright action timeout (default: 30000)
# @arg  --wait-ms <ms>           settle delay before the shot (default: 0)
# @arg  --full-page              capture the full scrollable page
# @arg  --platform <platform>    platform value recorded in manifest row
# @arg  --run-index <N>          run_index from state.json (default: 0)
# @arg  --allow-npx-install      permit `npx --yes` to fetch Playwright (network)
# @arg  --self-test              run built-in fixture tests; no browser required
#
# @exitcode 0  success — PNG produced
# @exitcode 1  hard error (bad args, no .context resolved, ledger disagrees with the ids)
# @exitcode 2  tool_missing — Playwright unavailable; route to cli_fallback
# @exitcode 3  capture_failed — navigation/timeout/empty output; route to cli_fallback
#
# Contract (uniform adapter shape):
#   Prints one line to stdout:
#     path=<file>  bytes=<N>  ok=<true|false>  error=<null|tool_missing|capture_failed>
#   On exits 2 and 3 `path` is the intended target path and `bytes` is 0 — no
#   file was produced, and the ladder owns what happens next.
#
# Minimum shell: Bash 3.2 (macOS system bash) — no associative arrays, no ${v,,}.

set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
WORKTASK_ID=""
TASK_ID=""
SLUG=""
URL=""
VIEWPORT="1280x800"
BROWSER="chromium"
TIMEOUT_MS="30000"
WAIT_MS="0"
FULL_PAGE=0
PLATFORM="web"
RUN_INDEX="0"
ALLOW_NPX_INSTALL=0
SELF_TEST=0

usage() {
  cat >&2 << 'EOF'
usage: web-capture.sh
  --worktask-id <id>        worktask_id from state.json (required)
  --task-id <TASK_ID>       DV task id, e.g. DV0 (required)
  --slug <kebab>            kebab-case slug ≤40 chars (required)
  --url <url>               http/https/file URL to capture (required)
  [--viewport <WxH>]        viewport in pixels (default: 1280x800)
  [--browser <name>]        chromium|firefox|webkit (default: chromium)
  [--timeout <ms>]          Playwright action timeout (default: 30000)
  [--wait-ms <ms>]          settle delay before the shot (default: 0)
  [--full-page]             capture the full scrollable page
  [--platform <platform>]   platform label for manifest (default: web)
  [--run-index <N>]         run_index from state.json (default: 0)
  [--allow-npx-install]     permit `npx --yes` to fetch Playwright (network)
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
    --task-id)
      TASK_ID="${2:-}"
      shift 2
      ;;
    --slug)
      SLUG="${2:-}"
      shift 2
      ;;
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --viewport)
      VIEWPORT="${2:-}"
      shift 2
      ;;
    --browser)
      BROWSER="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_MS="${2:-}"
      shift 2
      ;;
    --wait-ms)
      WAIT_MS="${2:-}"
      shift 2
      ;;
    --full-page)
      FULL_PAGE=1
      shift
      ;;
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --run-index)
      RUN_INDEX="${2:-}"
      shift 2
      ;;
    --allow-npx-install)
      ALLOW_NPX_INSTALL=1
      shift
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
# Pure helpers — shared by the self-test and the real run, so the self-test
# exercises the shipped code rather than a re-typed copy of it.
# ---------------------------------------------------------------------------

# Portable stat (mirrors cli-fallback.sh / size-budget.sh idiom).
_stat_bytes() {
  stat -f%z "$1" 2> /dev/null || stat -c%s "$1" 2> /dev/null || echo 0
}

# Task ids name the evidence stream and sit inside file names, so the grammar has no glob characters.
_task_id_ok() {
  local re='^[A-Z]{2}[0-9]+$'
  [[ $1 =~ $re ]]
}

# Ids that become path segments or manifest cells: no `/`, `|`, whitespace or leading dot.
_field_ok() {
  local re='^[A-Za-z0-9][A-Za-z0-9._-]*$'
  [[ $1 =~ $re ]]
}

# Next NN for one task: 1 + the highest NN on disk (incl. oversize/) or in its manifest.
# The max, not a count, so a deleted capture never recycles a number; 10# keeps 08 and 09 decimal.
_next_nn() {
  local dir="$1" task="$2" max=0 f nn
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f="${f##*/}"
    nn="${f#dv-"$task"-}"
    nn="${nn%%-*}"
    if [ "$((10#$nn))" -gt "$max" ]; then
      max="$((10#$nn))"
    fi
  done << EOF
$(find "$dir" "$dir/oversize" -maxdepth 1 -type f -name "dv-$task-[0-9][0-9]-*" 2> /dev/null || true)
$(LC_ALL=C awk -F'|' -v t="$task" '/^[[:space:]]*\|/ { gsub(/[[:space:]]/, "", $2); if ($2 ~ /^[0-9][0-9]$/) print "dv-" t "-" $2 "-row" }' "$dir/screenshots-$task.md" 2> /dev/null || true)
EOF
  if [ "$max" -ge 99 ]; then
    return 1
  fi
  printf '%02d\n' "$((max + 1))"
}

# URL allow-list. Blocks javascript:/data: and anything with whitespace before
# the value ever reaches an argv slot.
_valid_url() {
  [[ "$1" =~ ^(https?|file)://[^[:space:]]+$ ]]
}

_valid_viewport() {
  [[ "$1" =~ ^[0-9]{2,5}x[0-9]{2,5}$ ]]
}

# Playwright's --viewport-size wants "W,H"; the skill's arg grammar uses "WxH".
_viewport_to_pw() {
  printf '%s\n' "${1/x/,}"
}

# Map a Playwright stderr log to the audit `reason` for screenshot_platform_fallback.
_classify_pw_failure() {
  local log="$1"
  if [[ -f "$log" ]] && grep -qiE 'timeout .*exceeded|timeout [0-9]+ ?ms|navigation timeout' "$log"; then
    printf 'playwright_timeout\n'
  elif [[ -f "$log" ]] && grep -qiE 'net::ERR_|ENOTFOUND|ECONNREFUSED|EAI_AGAIN|cannot navigate' "$log"; then
    printf 'playwright_navigation_failed\n'
  else
    printf 'playwright_capture_failed\n'
  fi
}

# ---------------------------------------------------------------------------
# --self-test: no browser, no network, no git
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

  # --- Test 1: portable stat idiom works on a known file
  T1_BYTES=$(_stat_bytes "${BASH_SOURCE[0]}")
  if [[ "$T1_BYTES" -gt 0 ]]; then
    _ok "portable stat returns non-zero for this script (${T1_BYTES} bytes)"
  else
    _fail "portable stat returned 0 for ${BASH_SOURCE[0]}"
  fi

  # --- Test 2: viewport WxH → Playwright W,H
  PW_VIEW=$(_viewport_to_pw "1280x800")
  if [[ "$PW_VIEW" == "1280,800" ]]; then
    _ok "viewport 1280x800 converts to Playwright form 1280,800"
  else
    _fail "viewport conversion wrong: expected 1280,800, got ${PW_VIEW}"
  fi

  # --- Test 3: viewport validation accepts good, rejects malformed
  if _valid_viewport "390x844" && ! _valid_viewport "1280*800" && ! _valid_viewport "wide"; then
    _ok "viewport validation accepts 390x844 and rejects 1280*800 / wide"
  else
    _fail "viewport validation misclassified a fixture"
  fi

  # --- Test 4: URL allow-list keeps javascript:/data: out of argv
  if _valid_url "https://example.com/app" \
    && _valid_url "file:///tmp/build/index.html" \
    && ! _valid_url "javascript:alert(1)" \
    && ! _valid_url "data:text/html,<h1>x" \
    && ! _valid_url "https://example.com/a b"; then
    _ok "URL allow-list admits http/https/file and rejects javascript:/data:/spaces"
  else
    _fail "URL allow-list misclassified a fixture"
  fi

  # --- Test 5: failure classification from fixture Playwright logs
  TIMEOUT_LOG="${TMPDIR_TEST}/timeout.log"
  printf 'page.goto: Timeout 30000ms exceeded.\n' > "$TIMEOUT_LOG"
  NAV_LOG="${TMPDIR_TEST}/nav.log"
  printf 'page.goto: net::ERR_NAME_NOT_RESOLVED at https://nope.invalid/\n' > "$NAV_LOG"
  EMPTY_LOG="${TMPDIR_TEST}/empty.log"
  : > "$EMPTY_LOG"
  R_TIMEOUT=$(_classify_pw_failure "$TIMEOUT_LOG")
  R_NAV=$(_classify_pw_failure "$NAV_LOG")
  R_EMPTY=$(_classify_pw_failure "$EMPTY_LOG")
  if [[ "$R_TIMEOUT" == "playwright_timeout" ]] \
    && [[ "$R_NAV" == "playwright_navigation_failed" ]] \
    && [[ "$R_EMPTY" == "playwright_capture_failed" ]]; then
    _ok "failure classifier maps timeout / navigation / unknown logs correctly"
  else
    _fail "failure classifier wrong: timeout=${R_TIMEOUT} nav=${R_NAV} empty=${R_EMPTY}"
  fi

  # --- Test 6: NN is per task and takes the highest of disk and manifest
  NN_DIR="${TMPDIR_TEST}/images/self-test-wt"
  mkdir -p "$NN_DIR/oversize"
  printf 'x' > "${NN_DIR}/dv-DV0-01-foo.png"
  printf 'x' > "${NN_DIR}/oversize/dv-DV0-08-big.png"
  printf 'x' > "${NN_DIR}/dv-DV1-12-other.png"
  printf '| 02 | x | dv-DV0-02-x.png |\n' > "${NN_DIR}/screenshots-DV0.md"
  NN=$(_next_nn "$NN_DIR" DV0)
  NN1=$(_next_nn "$NN_DIR" DV2)
  if [[ "$NN" == "09" ]] && [[ "$NN1" == "01" ]]; then
    _ok "NN is per task (DV0 → 09 past oversize 08, fresh DV2 → 01)"
  else
    _fail "NN wrong: expected 09/01, got ${NN}/${NN1}"
  fi

  # --- Test 7: tool_missing stdout line matches the adapter contract
  CONTRACT_LINE=$(printf 'path=%s bytes=%d ok=false error=tool_missing\n' \
    ".context/images/self-test-wt/dv-01-self-test.png" 0)
  if [[ "$CONTRACT_LINE" =~ ^path=[^[:space:]]+\ bytes=[0-9]+\ ok=(true|false)\ error=(null|tool_missing|capture_failed)$ ]]; then
    _ok "tool_missing stdout line matches the {path,bytes,ok,error} contract"
  else
    _fail "tool_missing stdout line off-contract: ${CONTRACT_LINE}"
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
[[ -z "$TASK_ID" ]] && {
  printf >&2 'error: --task-id required\n'
  usage
}
[[ -z "$SLUG" ]] && {
  printf >&2 'error: --slug required\n'
  usage
}
[[ -z "$URL" ]] && {
  printf >&2 'error: --url required\n'
  usage
}

if ! _task_id_ok "$TASK_ID"; then
  printf >&2 'error: --task-id must match ^[A-Z]{2}[0-9]+$ (got: %s)\n' "$TASK_ID"
  exit 1
fi
if ! _field_ok "$WORKTASK_ID" || ! _field_ok "$PLATFORM"; then
  printf >&2 'error: --worktask-id and --platform must match ^[A-Za-z0-9][A-Za-z0-9._-]*$\n'
  exit 1
fi
if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]; then
  printf >&2 'error: --slug must be kebab-case ≤40 chars (got: %s)\n' "$SLUG"
  exit 1
fi
if ! _valid_url "$URL"; then
  printf >&2 'error: --url must be an http/https/file URL without whitespace (got: %s)\n' "$URL"
  exit 1
fi
if ! _valid_viewport "$VIEWPORT"; then
  printf >&2 'error: --viewport must be WxH in pixels (got: %s)\n' "$VIEWPORT"
  exit 1
fi
if [[ ! "$BROWSER" =~ ^(chromium|firefox|webkit)$ ]]; then
  printf >&2 'error: --browser must be chromium|firefox|webkit (got: %s)\n' "$BROWSER"
  exit 1
fi
if [[ ! "$TIMEOUT_MS" =~ ^[0-9]+$ ]] || [[ ! "$WAIT_MS" =~ ^[0-9]+$ ]]; then
  printf >&2 'error: --timeout and --wait-ms must be integer milliseconds\n'
  exit 1
fi
if [[ ! "$RUN_INDEX" =~ ^[0-9]+$ ]]; then
  printf >&2 'error: --run-index must be a non-negative integer (got: %s)\n' "$RUN_INDEX"
  exit 1
fi

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
# Shared audit-row appender — one key order, one symlink refusal for every audit.jsonl.
# Fails closed: a missing library is a broken install, not a runtime condition.
_AUDIT_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 'web-capture: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

_STATE_READ_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/state-read-lib.sh"
if [ ! -r "$_STATE_READ_LIB" ]; then
  printf >&2 'web-capture: plugin install broken — state-read-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_STATE_READ_LIB"

# A ledger for another worktask refuses the write, so a worktree capture never lands in the
# main checkout; without a ledger only an explicit CONTEXT_DIR may capture.
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [ "$_CTX_RC" -eq 2 ]; then
  printf >&2 'web-capture: root resolver unreachable\n'
  exit 2
elif [ "$_CTX_RC" -ne 0 ]; then
  printf >&2 'web-capture: no .context resolved; set WORKSPACE_ROOT or run inside a worktask\n'
  exit 1
fi
if [ -f "$CTX_DIR/state.json" ]; then
  if [ "$(corpflow_worktask_id "$CTX_DIR/state.json" "")" != "$WORKTASK_ID" ]; then
    printf >&2 'web-capture: --worktask-id %s does not match %s\n' "$WORKTASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
  if [ "$(jq -r --arg t "$TASK_ID" '(.tasks|type) == "object" and (.tasks|has($t))' "$CTX_DIR/state.json" 2> /dev/null || true)" != "true" ]; then
    printf >&2 'web-capture: task %s is not in %s\n' "$TASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
elif [ -z "${CONTEXT_DIR:-}" ] || [ "$CTX_DIR" != "$CONTEXT_DIR" ]; then
  printf >&2 'web-capture: no ledger at %s; set CONTEXT_DIR to capture outside a worktask\n' "$CTX_DIR"
  exit 1
fi

IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
LOGS_DIR="${CTX_DIR}/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
CAPTURE_LOG="${LOGS_DIR}/web-capture-${TS}.log"

if ! NN=$(trap - ERR; _next_nn "$IMAGES_DIR" "$TASK_ID"); then
  printf >&2 'web-capture: task %s already has capture 99\n' "$TASK_ID"
  exit 1
fi
OUTPUT_PNG="${IMAGES_DIR}/dv-${TASK_ID}-${NN}-${SLUG}.png"

# audit <action> <result> <metadata-json> — binds this adapter's actor and subject onto
# the shared appender.
audit() {
  corpflow_audit_row --file "$AUDIT_LOG" --actor "web-capture-adapter" \
    --action "$1" --subject "${WORKTASK_ID}/${SLUG}" --task-id "${TASK_ID:-unknown}" --result "$2" --meta "${3:-}"
}

# Emit the platform-fallback audit row + the contract line, then hand the
# decision back to the caller's ladder.
fallback_exit() {
  local reason="$1"
  local err="$2"
  local code="$3"
  audit screenshot_platform_fallback ok "$(
    jq -nc \
      --arg requested_platform "$PLATFORM" \
      --arg used_adapter "cli_fallback" \
      --arg reason "$reason" \
      --argjson run_index "$RUN_INDEX" \
      '{requested_platform:$requested_platform,used_adapter:$used_adapter,reason:$reason,run_index:$run_index}' \
      2> /dev/null || printf '{}'
  )" 2> /dev/null || true
  printf 'path=%s bytes=0 ok=false error=%s\n' "$OUTPUT_PNG" "$err"
  exit "$code"
}

# ---------------------------------------------------------------------------
# Step 1 — resolve a Playwright entry point
#
# Preference order: a `playwright` binary on PATH, then the locally installed
# package via `npx --no-install`. The no-install guard matters: a bare `npx
# playwright` silently downloads a package mid-DV, which is a network side
# effect the caller has to opt into with --allow-npx-install.
# ---------------------------------------------------------------------------
PW_CMD=()
if command -v playwright > /dev/null 2>&1; then
  PW_CMD=(playwright)
elif command -v npx > /dev/null 2>&1; then
  # Probed in a condition so a missing package stays an expected outcome
  # rather than tripping the ERR trap.
  if npx --no-install playwright --version > /dev/null 2>&1; then
    PW_CMD=(npx --no-install playwright)
  elif [[ "$ALLOW_NPX_INSTALL" -eq 1 ]]; then
    PW_CMD=(npx --yes playwright)
  fi
fi

if [[ "${#PW_CMD[@]}" -eq 0 ]]; then
  printf >&2 'warn: Playwright not available (no `playwright` binary, no local package); routing to cli_fallback\n'
  fallback_exit "playwright_unavailable" "tool_missing" 2
fi

# ---------------------------------------------------------------------------
# Step 2 — capture
# ---------------------------------------------------------------------------
PW_ARGS=(
  screenshot
  --browser "$BROWSER"
  --viewport-size "$(_viewport_to_pw "$VIEWPORT")"
  --timeout "$TIMEOUT_MS"
)
[[ "$WAIT_MS" -gt 0 ]] && PW_ARGS+=(--wait-for-timeout "$WAIT_MS")
[[ "$FULL_PAGE" -eq 1 ]] && PW_ARGS+=(--full-page)
PW_ARGS+=("$URL" "$OUTPUT_PNG")

CAPTURE_EXIT=0
"${PW_CMD[@]}" "${PW_ARGS[@]}" > "$CAPTURE_LOG" 2>&1 || CAPTURE_EXIT=$?

# ---------------------------------------------------------------------------
# Step 3 — outcome. The file is the evidence, never the exit code alone: a
# zero-byte PNG from a half-loaded page must not pass as a capture.
# ---------------------------------------------------------------------------
if [[ "$CAPTURE_EXIT" -eq 0 ]] && [[ -s "$OUTPUT_PNG" ]]; then
  BYTES=$(_stat_bytes "$OUTPUT_PNG")
  audit screenshot_captured ok "$(
    jq -nc \
      --arg slug "$SLUG" \
      --arg path "$OUTPUT_PNG" \
      --argjson bytes "$BYTES" \
      --arg platform "$PLATFORM" \
      --arg adapter "web/playwright" \
      --argjson run_index "$RUN_INDEX" \
      '{slug:$slug,path:$path,bytes:$bytes,platform:$platform,adapter:$adapter,run_index:$run_index}' \
      2> /dev/null || printf '{}'
  )" 2> /dev/null || true
  printf 'path=%s bytes=%d ok=true error=null\n' "$OUTPUT_PNG" "$BYTES"
  exit 0
fi

# Remove a truncated artifact so the manifest never indexes a broken PNG.
[[ -f "$OUTPUT_PNG" ]] && [[ ! -s "$OUTPUT_PNG" ]] && rm -f "$OUTPUT_PNG"

REASON=$(_classify_pw_failure "$CAPTURE_LOG")
printf >&2 'warn: playwright capture failed (%s, exit %d); see %s\n' \
  "$REASON" "$CAPTURE_EXIT" "$CAPTURE_LOG"
fallback_exit "$REASON" "capture_failed" 3
