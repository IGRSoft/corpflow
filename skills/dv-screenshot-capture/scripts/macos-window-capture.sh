#!/usr/bin/env bash
# @description  macOS live-drive adapter for dv-screenshot-capture.
#               Hosts a SwiftPM package's real root view in a real NSWindow, drives it with
#               scripted clicks and renders each `shot` step to
#               <ctx>/images/<id>/dv-<TASK_ID>-NN-<slug>.png, <ctx> from the shared root ladder.
#               Clicks go through NSWindow.sendEvent and the PNG through cacheDisplay, both
#               in-process, so it needs no Screen Recording, Accessibility or simulator — the
#               grants `screencapture` and a launched binary need and a DV host usually lacks.
#
#               The host package is scaffolded at <ctx>/tools/WindowCaptureHost/ from
#               templates/window-capture-host.swift plus the caller's --root-file.
#
# @arg  --worktask-id <id>     state.json worktask_id (required)
# @arg  --task-id <TASK_ID>    DV task id naming the evidence stream (required)
# @arg  --product <name>       library product exporting the root view (required)
# @arg  --root-file <path>     Swift file defining `@MainActor func captureRoot() -> some View`
#                              and importing what it needs (required)
# @arg  --steps <path>         step list, one per line (required):
#                                click <x> <y>          points from the PNG's top-left
#                                wait <seconds>
#                                shot <slug> [caption]  caption lands in the manifest row
#                              blank lines and lines starting with # are ignored
# @arg  --package-path <dir>   SwiftPM root (default: cwd when it holds Package.swift, else
#                              the git toplevel)
# @arg  --size <WxH>           window content size in points (default: 480x640)
# @arg  --timeout <seconds>    host run limit (default: 120)
# @arg  --probe                write <slug>.png under the host's probe/ dir instead: no
#                              numbering, manifest row or audit row — for finding coordinates
# @arg  --platform <platform>  platform value recorded in manifest and audit rows (default: apple)
# @arg  --run-index <N>        run_index from state.json (default: 0)
# @arg  --self-test            run built-in fixture tests; no toolchain or window server needed
#
# @exitcode 0  every shot captured; evidence runs also upserted screenshots-<TASK_ID>.md
# @exitcode 1  hard error (bad args or step grammar, >5 shots, unknown product, no .context
#              resolved, ledger disagrees with the ids)
# @exitcode 2  tool_missing — not macOS, or swift absent; route to cli_fallback
# @exitcode 3  capture_failed — host build, run or a shot failed; nothing lands in images/
#
# Contract (uniform adapter shape), one line per shot on exit 0:
#   path=<file> bytes=<N> ok=true error=null
# then `manifest=<file>` and `facts_screenshots=<json array for state.json facts.screenshots>`.
# A probe prints `probe=<file> bytes=<N>` per shot instead. Exits 2 and 3 print one
# `path=<first intended file> bytes=0 ok=false error=<tool_missing|capture_failed>` line.
#
# Minimum shell: Bash 3.2 (macOS system bash) — no associative arrays, no ${v,,}.

set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

WORKTASK_ID=""
TASK_ID=""
PRODUCT=""
ROOT_FILE=""
STEPS_FILE=""
PACKAGE_PATH=""
SIZE="480x640"
TIMEOUT_S="120"
PROBE=0
PLATFORM="apple"
RUN_INDEX="0"
SELF_TEST=0

usage() {
  cat >&2 << 'EOF'
usage: macos-window-capture.sh
  --worktask-id <id>        worktask_id from state.json (required)
  --task-id <TASK_ID>       DV task id, e.g. DV0 (required)
  --product <name>          library product exporting the root view (required)
  --root-file <path>        Swift file defining captureRoot() (required)
  --steps <path>            click <x> <y> | wait <s> | shot <slug> [caption] (required)
  [--package-path <dir>]    SwiftPM root (default: cwd with Package.swift, else git toplevel)
  [--size <WxH>]            window content size in points (default: 480x640)
  [--timeout <seconds>]     host run limit (default: 120)
  [--probe]                 unnumbered shots under the host's probe/ dir, no evidence rows
  [--platform <platform>]   platform label for manifest and audit (default: apple)
  [--run-index <N>]         run_index from state.json (default: 0)
  [--self-test]             run built-in self-tests; exits 0 on pass
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktask-id) WORKTASK_ID="${2:-}"; shift 2 ;;
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --product) PRODUCT="${2:-}"; shift 2 ;;
    --root-file) ROOT_FILE="${2:-}"; shift 2 ;;
    --steps) STEPS_FILE="${2:-}"; shift 2 ;;
    --package-path) PACKAGE_PATH="${2:-}"; shift 2 ;;
    --size) SIZE="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT_S="${2:-}"; shift 2 ;;
    --probe) PROBE=1; shift ;;
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --run-index) RUN_INDEX="${2:-}"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -h | --help) usage ;;
    *)
      printf >&2 'error: unknown flag %s\n' "$1"
      usage
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Pure helpers — shared by the self-test and the real run.
# ---------------------------------------------------------------------------

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

_valid_size() {
  [[ "$1" =~ ^[0-9]{2,4}x[0-9]{2,4}$ ]]
}

# Normalises a step list to the host's stdin grammar on stdout, one `shot <slug>\t<caption>`
# per shot so the caller can split them. Returns 1 on the first malformed line, named on stderr:
# the host would only reject it after a build, so a typo costs a turn instead of a minute.
_normalize_steps() { # <file>
  local line verb a b rest n=0 num='^[0-9]+([.][0-9]+)?$'
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    case "$line" in '' | '#'*) continue ;; esac
    IFS=' ' read -r verb a b rest <<< "$line"
    case "$verb" in
      click)
        if [[ "$a" =~ $num && "$b" =~ $num && -z "$rest" ]]; then
          printf 'click %s %s\n' "$a" "$b"
          continue
        fi
        ;;
      wait)
        if [[ "$a" =~ $num && -z "$b" ]]; then
          printf 'wait %s\n' "$a"
          continue
        fi
        ;;
      shot)
        rest="${b}${rest:+ $rest}"
        if [[ "$a" =~ ^[a-z0-9][a-z0-9-]{0,39}$ && "$rest" != *'|'* && ${#rest} -le 120 ]]; then
          printf 'shot %s\t%s\n' "$a" "$rest"
          continue
        fi
        ;;
    esac
    printf >&2 'macos-window-capture: bad step at line %d: %s\n' "$n" "$line"
    return 1
  done < "$1"
}

# SwiftPM names a path dependency after its directory, lowercased — not after its manifest name.
_package_identity() {
  local base="${1%/}"
  base="${base##*/}"
  printf '%s\n' "$base" | tr '[:upper:]' '[:lower:]'
}

_host_manifest() { # <package-path> <identity> <product> <macos-version>
  cat << EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowCaptureHost",
    platforms: [.macOS("$4")],
    dependencies: [.package(path: "$1")],
    targets: [
        .executableTarget(
            name: "WindowCaptureHost",
            dependencies: [.product(name: "$3", package: "$2")]
        ),
    ]
)
EOF
}

# Appends rows below the manifest's capture table through a temp file and a rename, so a
# reader never sees a half-written table; creates the manifest when absent.
_append_manifest_rows() { # <manifest> <rows-file> <worktask> <task> <run-index>
  local mf="$1" rows="$2" wid="$3" task="$4" run="$5" tmp
  if [ -d "$mf" ] || [ -L "$mf" ]; then
    return 1
  fi
  tmp=$(mktemp "$(dirname -- "$mf")/.screenshots-$task.md.XXXXXX") || return 1
  if [ -f "$mf" ]; then
    LC_ALL=C awk -v rowsfile="$rows" '
      function flush() { while ((getline r < rowsfile) > 0) print r; done = 1 }
      /^[[:space:]]*\|/ { intable = 1; print; next }
      intable && !done { flush() }
      { print }
      END {
        if (done) exit
        if (!intable) {
          print ""
          print "| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |"
          print "|---|------|------|-------|----------|---------|---------|----------|------------|"
        }
        flush()
      }' "$mf" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    {
      printf '# Screenshots — %s / %s\n\n> Run index: %s.\n\n' "$wid" "$task" "$run"
      printf '| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |\n'
      printf '|---|------|------|-------|----------|---------|---------|----------|------------|\n'
      cat "$rows"
    } > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  chmod 644 "$tmp" && mv -f -- "$tmp" "$mf"
}

_png_ok() {
  [ -s "$1" ] && [ "$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ]
}

# ---------------------------------------------------------------------------
# --self-test: no toolchain, no window server, no git
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

  printf '# probe\n\nclick 220 212.5\nwait 0.8\nshot main-menu S1 main menu\nshot win\n' > "$TMPDIR_TEST/ok.txt"
  GOT=$(_normalize_steps "$TMPDIR_TEST/ok.txt")
  WANT=$(printf 'click 220 212.5\nwait 0.8\nshot main-menu\tS1 main menu\nshot win\t')
  if [[ "$GOT" == "$WANT" ]]; then
    _ok "step grammar normalises click/wait/shot and drops comments and blanks"
  else
    _fail "step normalisation wrong: ${GOT}"
  fi

  BAD=0
  for f in 'click 10' 'wait soon' 'shot Main_Menu' 'shot ok a|b' 'tap 1 2'; do
    printf '%s\n' "$f" > "$TMPDIR_TEST/bad.txt"
    _normalize_steps "$TMPDIR_TEST/bad.txt" > /dev/null 2>&1 || BAD=$((BAD + 1))
  done
  if [[ "$BAD" -eq 5 ]]; then
    _ok "step grammar rejects short click, non-numeric wait, bad slug, pipe caption, unknown verb"
  else
    _fail "step grammar accepted $((5 - BAD)) malformed fixture(s)"
  fi

  if [[ "$(_package_identity /tmp/Work/MyApp/)" == "myapp" ]]; then
    _ok "package identity is the lowercased directory name"
  else
    _fail "package identity wrong: $(_package_identity /tmp/Work/MyApp/)"
  fi

  if _host_manifest /p/app app AppKit2 15.0 | grep -qF '.product(name: "AppKit2", package: "app")' \
    && _host_manifest /p/app app AppKit2 15.0 | grep -qF '.macOS("15.0")'; then
    _ok "host manifest pins the product, identity and deployment target"
  else
    _fail "host manifest missing product or platform"
  fi

  MF="$TMPDIR_TEST/screenshots-DV0.md"
  printf '| 01 | a | dv-DV0-01-a.png | 1 | apple | macos_window | x | t | — |\n' > "$TMPDIR_TEST/r1"
  printf '| 02 | b | dv-DV0-02-b.png | 1 | apple | macos_window | y | t | — |\n' > "$TMPDIR_TEST/r2"
  _append_manifest_rows "$MF" "$TMPDIR_TEST/r1" wt DV0 0
  printf '\n## Fallbacks invoked\n\n- none\n' >> "$MF"
  _append_manifest_rows "$MF" "$TMPDIR_TEST/r2" wt DV0 0
  if [[ "$(grep -c '^| 0[12] ' "$MF")" -eq 2 ]] \
    && [[ "$(grep -n '^| 02 ' "$MF" | cut -d: -f1)" -lt "$(grep -n '^## Fallbacks' "$MF" | cut -d: -f1)" ]]; then
    _ok "manifest rows append inside the table, above the tail sections"
  else
    _fail "manifest append misplaced a row"
  fi

  printf '\211PNG\r\n\032\nx' > "$TMPDIR_TEST/a.png"
  printf 'text' > "$TMPDIR_TEST/b.png"
  if _png_ok "$TMPDIR_TEST/a.png" && ! _png_ok "$TMPDIR_TEST/b.png"; then
    _ok "PNG signature check admits a PNG and refuses a renamed text file"
  else
    _fail "PNG signature check misclassified a fixture"
  fi

  printf '\nself-test: %d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
for _req in WORKTASK_ID TASK_ID PRODUCT ROOT_FILE STEPS_FILE; do
  if [[ -z "${!_req}" ]]; then
    printf >&2 'error: --%s required\n' "$(printf '%s' "$_req" | tr '[:upper:]_' '[:lower:]-')"
    usage
  fi
done
if ! _task_id_ok "$TASK_ID"; then
  printf >&2 'error: --task-id must match ^[A-Z]{2}[0-9]+$ (got: %s)\n' "$TASK_ID"
  exit 1
fi
if ! _field_ok "$WORKTASK_ID" || ! _field_ok "$PLATFORM" || [[ ! "$PRODUCT" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
  printf >&2 'error: --worktask-id, --platform and --product must be plain identifiers\n'
  exit 1
fi
if ! _valid_size "$SIZE" || [[ ! "$TIMEOUT_S" =~ ^[0-9]+$ ]] || [[ ! "$RUN_INDEX" =~ ^[0-9]+$ ]]; then
  printf >&2 'error: --size is WxH points, --timeout and --run-index are integers\n'
  exit 1
fi
if [[ ! -f "$ROOT_FILE" ]] || [[ ! -f "$STEPS_FILE" ]]; then
  printf >&2 'error: --root-file and --steps must be readable files\n'
  exit 1
fi
if [[ -z "$PACKAGE_PATH" ]]; then
  if [[ -f "$PWD/Package.swift" ]]; then
    PACKAGE_PATH="$PWD"
  else
    PACKAGE_PATH=$(git rev-parse --show-toplevel 2> /dev/null || true)
  fi
fi
if [[ -z "$PACKAGE_PATH" ]] || [[ ! -f "$PACKAGE_PATH/Package.swift" ]]; then
  printf >&2 'error: no Package.swift at --package-path %s\n' "${PACKAGE_PATH:-<unresolved>}"
  exit 1
fi
PACKAGE_PATH=$(cd "$PACKAGE_PATH" && pwd -P)

STEPS_NORM=$(trap - ERR; _normalize_steps "$STEPS_FILE") || exit 1
SHOT_COUNT=$(printf '%s\n' "$STEPS_NORM" | grep -c '^shot ' || true)
if [[ "$SHOT_COUNT" -lt 1 ]]; then
  printf >&2 'error: --steps holds no shot line\n'
  exit 1
fi
if [[ "$PROBE" -eq 0 && "$SHOT_COUNT" -gt 5 ]]; then
  printf >&2 'error: screenshot_count_exceeded — %d shots, a task holds at most 5\n' "$SHOT_COUNT"
  exit 1
fi

# ---------------------------------------------------------------------------
# Root resolution and ledger guard
# ---------------------------------------------------------------------------
_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)"
_TEMPLATE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../templates" 2> /dev/null && pwd -P)/window-capture-host.swift"
if [ ! -r "$_LIB_DIR/audit-lib.sh" ] || [ ! -r "$_LIB_DIR/state-read-lib.sh" ] || [ ! -r "$_TEMPLATE" ]; then
  printf >&2 'macos-window-capture: plugin install broken — shared lib or host template not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_LIB_DIR/audit-lib.sh"
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_LIB_DIR/state-read-lib.sh"

# A ledger for another worktask refuses the write, so a worktree capture never lands in the
# main checkout; without a ledger only an explicit CONTEXT_DIR may capture.
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [ "$_CTX_RC" -eq 2 ]; then
  printf >&2 'macos-window-capture: root resolver unreachable\n'
  exit 2
elif [ "$_CTX_RC" -ne 0 ]; then
  printf >&2 'macos-window-capture: no .context resolved; set CONTEXT_DIR or run inside a worktask\n'
  exit 1
fi
if [ -f "$CTX_DIR/state.json" ]; then
  if [ "$(corpflow_worktask_id "$CTX_DIR/state.json" "")" != "$WORKTASK_ID" ]; then
    printf >&2 'macos-window-capture: --worktask-id %s does not match %s\n' "$WORKTASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
  if [ "$(jq -r --arg t "$TASK_ID" '(.tasks|type) == "object" and (.tasks|has($t))' "$CTX_DIR/state.json" 2> /dev/null || true)" != "true" ]; then
    printf >&2 'macos-window-capture: task %s is not in %s\n' "$TASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
elif [ -z "${CONTEXT_DIR:-}" ] || [ "$CTX_DIR" != "$CONTEXT_DIR" ]; then
  printf >&2 'macos-window-capture: no ledger at %s; set CONTEXT_DIR to capture outside a worktask\n' "$CTX_DIR"
  exit 1
fi

IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
LOGS_DIR="${CTX_DIR}/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
HOST_DIR="${CTX_DIR}/tools/WindowCaptureHost"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"
TS="$(date -u +%Y%m%d-%H%M%S)"
BUILD_LOG="${LOGS_DIR}/build-macos-window-${TS}.log"
RUN_LOG="${LOGS_DIR}/monitor-macos-window-${TS}.log"
MANIFEST="${IMAGES_DIR}/screenshots-${TASK_ID}.md"

if ! NN=$(trap - ERR; _next_nn "$IMAGES_DIR" "$TASK_ID"); then
  printf >&2 'macos-window-capture: task %s already has capture 99\n' "$TASK_ID"
  exit 1
fi
FIRST_SLUG=$(printf '%s\n' "$STEPS_NORM" | awk '/^shot / { sub(/^shot /, ""); sub(/\t.*/, ""); print; exit }')
FIRST_PNG="${IMAGES_DIR}/dv-${TASK_ID}-${NN}-${FIRST_SLUG}.png"

audit() {
  corpflow_audit_row --file "$AUDIT_LOG" --actor "macos-window-adapter" \
    --action "$1" --subject "${WORKTASK_ID}/${2}" --task-id "$TASK_ID" --result "$3" --meta "${4:-}"
}

fallback_exit() { # <reason> <error> <code>
  if [[ "$PROBE" -eq 0 ]]; then
    audit screenshot_platform_fallback "$FIRST_SLUG" ok "$(jq -nc --arg platform "$PLATFORM" \
      --arg reason "$1" --argjson run_index "$RUN_INDEX" \
      '{requested_platform:$platform,used_adapter:"cli_fallback",reason:$reason,run_index:$run_index}' \
      2> /dev/null || printf '{}')" 2> /dev/null || true
  fi
  printf 'path=%s bytes=0 ok=false error=%s\n' "$FIRST_PNG" "$2"
  exit "$3"
}

# ---------------------------------------------------------------------------
# Toolchain, package facts, host scaffold and build
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v swift > /dev/null 2>&1; then
  printf >&2 'warn: needs macOS with a Swift toolchain; routing to cli_fallback\n'
  fallback_exit "swift_unavailable" "tool_missing" 2
fi

PKG_JSON=$(trap - ERR; swift package dump-package --package-path "$PACKAGE_PATH" 2>> "$BUILD_LOG") || {
  printf >&2 'warn: swift package dump-package failed; see %s\n' "$BUILD_LOG"
  fallback_exit "package_unreadable" "capture_failed" 3
}
if ! jq -e --arg p "$PRODUCT" '[.products[]? | select(.name == $p and (.type | has("library")))] | length > 0' \
  <<< "$PKG_JSON" > /dev/null 2>&1; then
  printf >&2 'error: --product %s is not a library product; library products: %s\n' "$PRODUCT" \
    "$(jq -r '[.products[]? | select(.type | has("library")) | .name] | join(", ")' <<< "$PKG_JSON" 2> /dev/null || true)"
  exit 1
fi
MACOS_MIN=$(jq -r '[.platforms[]? | select(.platformName == "macos") | .version][0] // "13.0"' <<< "$PKG_JSON")

mkdir -p "$HOST_DIR/Sources/WindowCaptureHost"
_host_manifest "$PACKAGE_PATH" "$(_package_identity "$PACKAGE_PATH")" "$PRODUCT" "$MACOS_MIN" \
  > "$HOST_DIR/Package.swift"
cp "$_TEMPLATE" "$HOST_DIR/Sources/WindowCaptureHost/WindowCaptureHost.swift"
cp "$ROOT_FILE" "$HOST_DIR/Sources/WindowCaptureHost/CaptureRoot.swift"

if ! swift build --package-path "$HOST_DIR" >> "$BUILD_LOG" 2>&1; then
  printf >&2 'warn: host build failed; first errors from %s:\n' "$BUILD_LOG"
  sed $'s/\x1b\\[[0-9;]*m//g' "$BUILD_LOG" | grep -E '^/.*: error:' | sort -u | head -5 >&2 || true
  fallback_exit "host_build_failed" "capture_failed" 3
fi

# ---------------------------------------------------------------------------
# Run into a staging dir: evidence lands all-or-nothing, so a failed run never leaves an
# image without a manifest row for the gate to block on.
# ---------------------------------------------------------------------------
STAGE="${HOST_DIR}/out-${TS}"
[[ "$PROBE" -eq 1 ]] && STAGE="${HOST_DIR}/probe"
mkdir -p "$STAGE"
SHOTS=""
HOST_STDIN=""
_n=$((10#$NN))
while IFS= read -r _line; do
  case "$_line" in
    shot\ *)
      _rest="${_line#shot }"
      _slug="${_rest%%$'\t'*}"
      _cap="${_rest#*$'\t'}"
      if [[ "$PROBE" -eq 1 ]]; then
        _name="$_slug"
      else
        _name="dv-${TASK_ID}-$(printf '%02d' "$_n")-${_slug}"
        _n=$((_n + 1))
      fi
      SHOTS="${SHOTS}${_name}"$'\t'"${_slug}"$'\t'"${_cap:-$_slug}"$'\n'
      HOST_STDIN="${HOST_STDIN}shot ${_name}"$'\n'
      ;;
    *) HOST_STDIN="${HOST_STDIN}${_line}"$'\n' ;;
  esac
done <<< "$STEPS_NORM"

_W="${SIZE%x*}"
_H="${SIZE#*x}"
RUN_RC=0
printf '%s' "$HOST_STDIN" | "$HOST_DIR/.build/debug/WindowCaptureHost" "$STAGE" "$_W" "$_H" "$TIMEOUT_S" \
  > "$RUN_LOG" 2>&1 || RUN_RC=$?
if [[ "$RUN_RC" -ne 0 ]]; then
  printf >&2 'warn: host run exited %d; see %s\n' "$RUN_RC" "$RUN_LOG"
  fallback_exit "host_run_failed" "capture_failed" 3
fi
while IFS=$'\t' read -r _name _slug _cap; do
  [[ -n "$_name" ]] || continue
  if ! _png_ok "$STAGE/${_name}.png"; then
    printf >&2 'warn: shot %s produced no PNG; see %s\n' "$_name" "$RUN_LOG"
    fallback_exit "shot_missing" "capture_failed" 3
  fi
done <<< "$SHOTS"

if [[ "$PROBE" -eq 1 ]]; then
  while IFS=$'\t' read -r _name _slug _cap; do
    [[ -n "$_name" ]] || continue
    printf 'probe=%s bytes=%d\n' "$STAGE/${_name}.png" "$(_stat_bytes "$STAGE/${_name}.png")"
  done <<< "$SHOTS"
  exit 0
fi

ROWS="${STAGE}/rows.md"
: > "$ROWS"
FACTS="[]"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
while IFS=$'\t' read -r _name _slug _cap; do
  [[ -n "$_name" ]] || continue
  _dest="${IMAGES_DIR}/${_name}.png"
  mv -f -- "$STAGE/${_name}.png" "$_dest"
  _bytes=$(_stat_bytes "$_dest")
  _nn="${_name#dv-"$TASK_ID"-}"
  _nn="${_nn%%-*}"
  printf '| %s | %s | %s.png | %s | %s | macos_window | %s | %s | — |\n' \
    "$_nn" "$_slug" "$_name" "$_bytes" "$PLATFORM" "$_cap" "$NOW" >> "$ROWS"
  audit screenshot_captured "$_slug" ok "$(jq -nc --arg slug "$_slug" --arg path "$_dest" \
    --argjson bytes "$_bytes" --arg platform "$PLATFORM" --argjson run_index "$RUN_INDEX" \
    '{slug:$slug,path:$path,bytes:$bytes,platform:$platform,adapter:"macos_window",run_index:$run_index}' \
    2> /dev/null || printf '{}')" 2> /dev/null || true
  FACTS=$(jq -c --arg slug "$_slug" --arg path "$_dest" --argjson bytes "$_bytes" --arg platform "$PLATFORM" \
    '. + [{slug:$slug,path:$path,bytes:$bytes,platform:$platform,ok:true,design_ref:"—"}]' <<< "$FACTS")
  printf 'path=%s bytes=%d ok=true error=null\n' "$_dest" "$_bytes"
done <<< "$SHOTS"

if ! _append_manifest_rows "$MANIFEST" "$ROWS" "$WORKTASK_ID" "$TASK_ID" "$RUN_INDEX"; then
  printf >&2 'macos-window-capture: could not write %s; add the rows by hand from %s\n' "$MANIFEST" "$ROWS"
  exit 1
fi
rm -rf "$STAGE"
printf 'manifest=%s\n' "$MANIFEST"
printf 'facts_screenshots=%s\n' "$FACTS"
