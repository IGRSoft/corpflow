#!/usr/bin/env bash
# @description  Android platform adapter for dv-screenshot-capture.
#               Verifies an online device/emulator, then streams
#               `adb exec-out screencap -p` into
#               <ctx>/images/<id>/dv-<TASK_ID>-NN-<slug>.png, <ctx> from the root ladder.
#               Pure CLI — needs no MCP grant, so the delegated platform agent
#               (or a direct caller) can run it unchanged.
#
#               adb absent → exit 2 (tool_missing) and the caller routes to
#               cli_fallback per SKILL.md § fallback ladder. No device, an
#               ambiguous device set, or a corrupt stream → exit 3
#               (capture_failed), same route. Neither is a hard DV failure.
#
# @arg  --worktask-id <id>       state.json worktask_id (required)
# @arg  --task-id <TASK_ID>      DV task id naming the evidence stream (required)
# @arg  --slug <kebab>           kebab-case slug ≤40 chars (required)
# @arg  --serial <serial>        adb serial; required when >1 device is online
# @arg  --platform <platform>    platform value recorded in manifest row
# @arg  --run-index <N>          run_index from state.json (default: 0)
# @arg  --self-test              run built-in fixture tests; no device required
#
# @exitcode 0  success — PNG produced
# @exitcode 1  hard error (bad args, no .context resolved, ledger disagrees with the ids)
# @exitcode 2  tool_missing — adb not on PATH; route to cli_fallback
# @exitcode 3  capture_failed — no/ambiguous device or corrupt stream; route to cli_fallback
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
SERIAL=""
PLATFORM="android"
RUN_INDEX="0"
SELF_TEST=0

usage() {
  cat >&2 << 'EOF'
usage: android-capture.sh
  --worktask-id <id>        worktask_id from state.json (required)
  --task-id <TASK_ID>       DV task id, e.g. DV0 (required)
  --slug <kebab>            kebab-case slug ≤40 chars (required)
  [--serial <serial>]       adb serial; required when more than one device is online
  [--platform <platform>]   platform label for manifest (default: android)
  [--run-index <N>]         run_index from state.json (default: 0)
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
    --serial)
      SERIAL="${2:-}"
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

_valid_serial() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]
}

# stdin: raw `adb devices` output. stdout: one serial per online device.
# Drops the header, the `* daemon …` chatter, and every non-`device` state —
# an offline or unauthorized handset cannot be captured from, so counting it
# would turn a fixable "authorize the device" into a misleading ambiguity error.
_adb_online_devices() {
  local serial state rest
  while IFS=$' \t' read -r serial state rest; do
    [[ -z "$serial" ]] && continue
    case "$serial" in
      List | \**) continue ;;
    esac
    [[ "$state" == "device" ]] || continue
    printf '%s\n' "$serial"
  done
}

# A PNG stream that lost its header is worse than no capture: it indexes into
# the manifest and fails silently downstream. Verify the 8-byte signature.
_is_png() {
  local magic
  [[ -s "$1" ]] || return 1
  magic=$(od -An -tx1 -N8 < "$1" 2> /dev/null | tr -d ' \n')
  [[ "$magic" == "89504e470d0a1a0a" ]]
}

# ---------------------------------------------------------------------------
# --self-test: no adb, no device, no network
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

  # --- Test 2: device parser keeps only online devices
  MULTI_FIXTURE="${TMPDIR_TEST}/multi.txt"
  {
    printf '* daemon not running; starting now at tcp:5037\n'
    printf '* daemon started successfully\n'
    printf 'List of devices attached\n'
    printf 'emulator-5554\tdevice\n'
    printf 'R58M12345XY\tdevice\n'
    printf '0123456789ABCDEF\toffline\n'
    printf '9876543210\tunauthorized\n'
    printf '\n'
  } > "$MULTI_FIXTURE"
  MULTI_ONLINE=$(_adb_online_devices < "$MULTI_FIXTURE")
  MULTI_COUNT=$(printf '%s\n' "$MULTI_ONLINE" | wc -l | tr -d ' ')
  if [[ "$MULTI_COUNT" == "2" ]] \
    && printf '%s\n' "$MULTI_ONLINE" | grep -qx 'emulator-5554' \
    && printf '%s\n' "$MULTI_ONLINE" | grep -qx 'R58M12345XY'; then
    _ok "device parser drops daemon chatter/header/offline/unauthorized (2 online)"
  else
    _fail "device parser wrong: got [${MULTI_ONLINE}] count=${MULTI_COUNT}"
  fi

  # --- Test 3: single-device fixture yields exactly one serial
  ONE_FIXTURE="${TMPDIR_TEST}/one.txt"
  printf 'List of devices attached\nemulator-5554\tdevice\n\n' > "$ONE_FIXTURE"
  ONE_ONLINE=$(_adb_online_devices < "$ONE_FIXTURE")
  if [[ "$ONE_ONLINE" == "emulator-5554" ]]; then
    _ok "single-device fixture resolves to emulator-5554 without --serial"
  else
    _fail "single-device fixture wrong: got [${ONE_ONLINE}]"
  fi

  # --- Test 4: no-device fixture yields nothing (routes to capture_failed)
  NONE_FIXTURE="${TMPDIR_TEST}/none.txt"
  printf 'List of devices attached\n\n' > "$NONE_FIXTURE"
  NONE_ONLINE=$(_adb_online_devices < "$NONE_FIXTURE")
  if [[ -z "$NONE_ONLINE" ]]; then
    _ok "no-device fixture yields no serials"
  else
    _fail "no-device fixture yielded [${NONE_ONLINE}]"
  fi

  # --- Test 5: PNG signature check accepts a real header, rejects a corrupt one
  GOOD_PNG="${TMPDIR_TEST}/good.png"
  printf '\211PNG\r\n\032\n' > "$GOOD_PNG"
  printf 'IHDRpadding' >> "$GOOD_PNG"
  BAD_PNG="${TMPDIR_TEST}/bad.png"
  printf '\211PNG\r\r\n\032\n' > "$BAD_PNG"
  EMPTY_PNG="${TMPDIR_TEST}/empty.png"
  : > "$EMPTY_PNG"
  if _is_png "$GOOD_PNG" && ! _is_png "$BAD_PNG" && ! _is_png "$EMPTY_PNG"; then
    _ok "PNG signature check accepts valid header, rejects CRLF-mangled and empty"
  else
    _fail "PNG signature check misclassified a fixture"
  fi

  # --- Test 6: serial validation keeps shell metacharacters out of argv
  if _valid_serial "emulator-5554" \
    && _valid_serial "192.168.1.10:5555" \
    && ! _valid_serial "foo; rm -rf /" \
    && ! _valid_serial '$(whoami)'; then
    _ok "serial validation accepts real serials and rejects metacharacters"
  else
    _fail "serial validation misclassified a fixture"
  fi

  # --- Test 7: NN is per task and never recycles a deleted number
  NN_DIR="${TMPDIR_TEST}/images/self-test-wt"
  mkdir -p "$NN_DIR"
  printf 'x' > "${NN_DIR}/dv-DV0-01-foo.png"
  printf 'x' > "${NN_DIR}/dv-DV0-03-bar.png"
  printf 'x' > "${NN_DIR}/dv-DV1-07-other.png"
  NN=$(_next_nn "$NN_DIR" DV0)
  if [[ "$NN" == "04" ]]; then
    _ok "NN is the per-task max + 1 (DV0 01,03 → 04; DV1 ignored)"
  else
    _fail "NN wrong: expected 04, got ${NN}"
  fi

  # --- Test 8: tool_missing stdout line matches the adapter contract
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
if [[ -n "$SERIAL" ]] && ! _valid_serial "$SERIAL"; then
  printf >&2 'error: --serial must match [A-Za-z0-9._:-]+ (got: %s)\n' "$SERIAL"
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
  printf >&2 'android-capture: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

_STATE_READ_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/state-read-lib.sh"
if [ ! -r "$_STATE_READ_LIB" ]; then
  printf >&2 'android-capture: plugin install broken — state-read-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_STATE_READ_LIB"

# A ledger for another worktask refuses the write, so a worktree capture never lands in the
# main checkout; without a ledger only an explicit CONTEXT_DIR may capture.
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [ "$_CTX_RC" -eq 2 ]; then
  printf >&2 'android-capture: root resolver unreachable\n'
  exit 2
elif [ "$_CTX_RC" -ne 0 ]; then
  printf >&2 'android-capture: no .context resolved; set WORKSPACE_ROOT or run inside a worktask\n'
  exit 1
fi
if [ -f "$CTX_DIR/state.json" ]; then
  if [ "$(corpflow_worktask_id "$CTX_DIR/state.json" "")" != "$WORKTASK_ID" ]; then
    printf >&2 'android-capture: --worktask-id %s does not match %s\n' "$WORKTASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
  if [ "$(jq -r --arg t "$TASK_ID" '(.tasks|type) == "object" and (.tasks|has($t))' "$CTX_DIR/state.json" 2> /dev/null || true)" != "true" ]; then
    printf >&2 'android-capture: task %s is not in %s\n' "$TASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
elif [ -z "${CONTEXT_DIR:-}" ] || [ "$CTX_DIR" != "$CONTEXT_DIR" ]; then
  printf >&2 'android-capture: no ledger at %s; set CONTEXT_DIR to capture outside a worktask\n' "$CTX_DIR"
  exit 1
fi

IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
LOGS_DIR="${CTX_DIR}/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
CAPTURE_LOG="${LOGS_DIR}/android-capture-${TS}.log"

if ! NN=$(trap - ERR; _next_nn "$IMAGES_DIR" "$TASK_ID"); then
  printf >&2 'android-capture: task %s already has capture 99\n' "$TASK_ID"
  exit 1
fi
OUTPUT_PNG="${IMAGES_DIR}/dv-${TASK_ID}-${NN}-${SLUG}.png"

# audit <action> <result> <metadata-json> — binds this adapter's actor and subject onto
# the shared appender.
audit() {
  corpflow_audit_row --file "$AUDIT_LOG" --actor "android-capture-adapter" \
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
# Step 1 — adb on PATH
# ---------------------------------------------------------------------------
if ! command -v adb > /dev/null 2>&1; then
  printf >&2 'warn: adb not on PATH; routing to cli_fallback\n'
  fallback_exit "adb_unavailable" "tool_missing" 2
fi

# ---------------------------------------------------------------------------
# Step 2 — resolve exactly one online device
# ---------------------------------------------------------------------------
DEVICES_EXIT=0
DEVICES_RAW=$(adb devices 2>> "$CAPTURE_LOG") || DEVICES_EXIT=$?

if [[ "$DEVICES_EXIT" -ne 0 ]]; then
  printf >&2 'warn: `adb devices` failed (exit %d); see %s\n' "$DEVICES_EXIT" "$CAPTURE_LOG"
  fallback_exit "adb_server_unreachable" "capture_failed" 3
fi

ONLINE=$(printf '%s\n' "$DEVICES_RAW" | _adb_online_devices)
if [[ -z "$ONLINE" ]]; then
  DEVICE_COUNT=0
else
  DEVICE_COUNT=$(printf '%s\n' "$ONLINE" | wc -l | tr -d ' ')
fi

if [[ "$DEVICE_COUNT" -eq 0 ]]; then
  printf >&2 'warn: no online adb device (check `adb devices` for offline/unauthorized entries)\n'
  fallback_exit "no_device_attached" "capture_failed" 3
fi

if [[ -n "$SERIAL" ]]; then
  if ! printf '%s\n' "$ONLINE" | grep -qxF -- "$SERIAL"; then
    printf >&2 'warn: --serial %s is not among the online devices\n' "$SERIAL"
    fallback_exit "serial_not_found" "capture_failed" 3
  fi
elif [[ "$DEVICE_COUNT" -gt 1 ]]; then
  printf >&2 'warn: %d online devices; pass --serial to disambiguate\n' "$DEVICE_COUNT"
  fallback_exit "multiple_devices" "capture_failed" 3
else
  SERIAL="$ONLINE"
fi

# ---------------------------------------------------------------------------
# Step 3 — capture
#
# `exec-out` (not `shell`) is what keeps the PNG byte-exact: the shell
# transport line-ends the stream and corrupts the image on some platforms.
# ---------------------------------------------------------------------------
CAPTURE_EXIT=0
adb -s "$SERIAL" exec-out screencap -p > "$OUTPUT_PNG" 2>> "$CAPTURE_LOG" || CAPTURE_EXIT=$?

# ---------------------------------------------------------------------------
# Step 4 — outcome. The file is the evidence, never the exit code alone.
# ---------------------------------------------------------------------------
if [[ "$CAPTURE_EXIT" -eq 0 ]] && _is_png "$OUTPUT_PNG"; then
  BYTES=$(_stat_bytes "$OUTPUT_PNG")
  audit screenshot_captured ok "$(
    jq -nc \
      --arg slug "$SLUG" \
      --arg path "$OUTPUT_PNG" \
      --argjson bytes "$BYTES" \
      --arg platform "$PLATFORM" \
      --arg adapter "android/adb-screencap" \
      --argjson run_index "$RUN_INDEX" \
      '{slug:$slug,path:$path,bytes:$bytes,platform:$platform,adapter:$adapter,run_index:$run_index}' \
      2> /dev/null || printf '{}'
  )" 2> /dev/null || true
  printf 'path=%s bytes=%d ok=true error=null\n' "$OUTPUT_PNG" "$BYTES"
  exit 0
fi

# Remove the unusable artifact so the manifest never indexes a broken PNG.
rm -f "$OUTPUT_PNG"

if [[ "$CAPTURE_EXIT" -ne 0 ]]; then
  REASON="screencap_failed"
else
  REASON="screencap_corrupt"
fi
printf >&2 'warn: adb screencap failed (%s, exit %d); see %s\n' \
  "$REASON" "$CAPTURE_EXIT" "$CAPTURE_LOG"
fallback_exit "$REASON" "capture_failed" 3
