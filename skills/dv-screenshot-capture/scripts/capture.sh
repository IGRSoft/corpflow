#!/usr/bin/env bash
# @description  One-call DV entry point for dv-screenshot-capture.
#               Runs the worktask guard, picks the platform's adapter from the dispatch
#               table, walks the fallback ladder down to cli_fallback and its tool_missing
#               floor, applies the size budget, and rewrites screenshots-<TASK_ID>.md with
#               its tail sections — so DV gets its evidence from one Bash call and never
#               loads the skill body or reads a PNG back.
#
#               It runs only the adapter scripts beside it. The apple simulator adapter is
#               delegated to a platform agent in the skill and a script cannot spawn one, so
#               apple without --product or --canvas-files goes straight to cli_fallback
#               (reason delegation_unavailable) and says so under `## Fallbacks invoked`.
#
# @arg  --task-id <TASK_ID>      DV task the evidence belongs to (required)
# @arg  --capture <spec>         1..5 times; <slug>[:<arg>], slug kebab-case ≤40 chars.
#                                <arg> belongs to the primary adapter:
#                                  web           URL, http/https/file (required)
#                                  android       adb serial (optional)
#                                  macos_window  file of click/wait steps run before the
#                                                shot (optional; no `shot` lines)
#                                  apple_canvas  view key Module.Type (required)
#                                  cli_fallback  newline file list scoping the diff (optional)
# @arg  --platform <p>           default: tasks.<ID>.metadata.platform, ledger .platform, `all`
# @arg  --worktask-id <id>       must equal the resolved ledger's worktask_id
# @arg  --context-dir <dir>      .context to use; default: the shared root ladder
# @arg  --base-ref <ref>         cli_fallback diff base (default: task metadata.base_ref, else
#                                cli-fallback.sh's own default)
# @arg  --viewport <WxH>         web only
# @arg  --product <name>         apple/macos: SwiftPM library product → macos_window adapter
# @arg  --root-file <path>       apple/macos: captureRoot() Swift file (with --product)
# @arg  --package-path <dir>     apple/macos: SwiftPM root for macos_window
# @arg  --size <WxH>             apple/macos: macos_window window size
# @arg  --canvas-files <path>    apple/macos: modified-files list → apple_canvas adapter
# @arg  --self-test              run built-in fixture tests
#
# @exitcode 0  manifest written; every capture has an image row, a tool_missing floor row, an
#              oversize link-only entry, or was refused by the 5-capture cap
# @exitcode 1  internal error (broken install, unwritable manifest, an adapter's hard error)
# @exitcode 2  usage: bad arguments, no worktask resolved, or a ledger that is not this run's
# @exitcode 3  manifest written, but a capture ended with no row (render_failed or
#              tool_missing without a floor row); see the log named on stderr
#
# Stdout (≤7 lines): per capture `<NN> <slug> <adapter> <bytes|tool_missing|oversize|error>`
# (`-- <slug> - screenshot_count_exceeded` when refused), then `manifest=<path>` and
# `facts_screenshots=<json>` — [{slug,path,bytes,platform,ok,design_ref}], the state.json
# facts.screenshots shape macos-window-capture.sh prints; path is `—` when no file exists. Adapter stderr goes to
# <ctx>/logs/dv-capture-<TASK_ID>-<ts>.log.
#
# Minimum shell: Bash 3.2 (macOS system bash) — no associative arrays, no ${v,,}.

# Fallback bullets carry literal markdown backticks inside single-quoted printf formats.
# shellcheck disable=SC2016
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

readonly MAX_CAPTURES=5
readonly WARN_BYTES=200000
HDR='| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |'
SEP='|---|------|------|-------|----------|---------|---------|----------|------------|'

TASK_ID=""
PLATFORM=""
WORKTASK_ARG=""
CONTEXT_ARG=""
BASE_REF=""
VIEWPORT=""
PRODUCT=""
ROOT_FILE=""
PACKAGE_PATH=""
SIZE=""
CANVAS_FILES=""
CAPTURES=""
N_CAP=0
SELF_TEST=0

usage() {
  [[ -z "${1:-}" ]] || printf >&2 'capture: %s\n' "$1"
  cat >&2 << 'EOF'
usage: capture.sh --task-id <TASK_ID> --capture <slug>[:<arg>] [--capture ...]  (1..5)
  [--platform <p>] [--worktask-id <id>] [--context-dir <dir>] [--base-ref <ref>]
  web:          --capture <slug>:<url> [--viewport WxH]
  android:      --capture <slug>[:<serial>]
  apple/macos:  --product <P> --root-file <swift> --capture <slug>[:<steps-file>]
                [--package-path <dir>] [--size WxH]
                | --canvas-files <list> --capture <slug>:<Module.Type>
  other/all:    --capture <slug>[:<file-list>]   (annotated git diff via cli_fallback)
  exit 0 written, 1 internal, 2 usage, 3 a capture produced no row
EOF
  exit 2
}

_need() { [[ $# -ge 2 && -n "$2" ]] || usage "$1 needs a value"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      SELF_TEST=1
      shift
      continue
      ;;
    -h | --help) usage ;;
  esac
  case "$1" in
    --task-id | --platform | --worktask-id | --context-dir | --base-ref | --viewport | --product | \
      --root-file | --package-path | --size | --canvas-files | --capture) _need "$@" ;;
    *) usage "unknown flag $1" ;;
  esac
  case "$1" in
    --task-id) TASK_ID="$2" ;;
    --platform) PLATFORM="$2" ;;
    --worktask-id) WORKTASK_ARG="$2" ;;
    --context-dir) CONTEXT_ARG="$2" ;;
    --base-ref) BASE_REF="$2" ;;
    --viewport) VIEWPORT="$2" ;;
    --product) PRODUCT="$2" ;;
    --root-file) ROOT_FILE="$2" ;;
    --package-path) PACKAGE_PATH="$2" ;;
    --size) SIZE="$2" ;;
    --canvas-files) CANVAS_FILES="$2" ;;
    --capture)
      # Specs travel newline-joined, so a newline or tab inside one would split it.
      case "$2" in *$'\n'* | *$'\t'*) usage "--capture must be one line" ;; esac
      CAPTURES="${CAPTURES}${2}"$'\n'
      N_CAP=$((N_CAP + 1))
      ;;
  esac
  shift 2
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

_slug_ok() {
  local re='^[a-z0-9][a-z0-9-]{0,39}$'
  [[ $1 =~ $re ]]
}

# Splits on the FIRST colon only: a slug never holds one, a URL or serial may.
_spec_slug() { printf '%s' "${1%%:*}"; }
_spec_arg() { case "$1" in *:*) printf '%s' "${1#*:}" ;; esac; }

# The adapter contract line → "path<TAB>bytes<TAB>ok<TAB>error". Anchored on ` bytes=` so a
# path holding spaces survives.
_parse_contract() {
  sed -n 's/^path=\(.*\) bytes=\([0-9][0-9]*\) ok=\([a-z]*\) error=\([a-z_]*\)$/\1	\2	\3	\4/p' "$1" | tail -1
}

# Capture rows already in the manifest: every table row except header and separator.
_row_count() {
  [[ -f "$1" ]] || {
    echo 0
    return 0
  }
  LC_ALL=C awk -F'|' '/^[[:space:]]*\|/ { v = $2; gsub(/[[:space:]]/, "", v); if (v ~ /^[0-9][0-9]$/) n++ } END { print n + 0 }' "$1"
}

# NN of this slug's tool_missing row, empty when cli-fallback.sh wrote none.
_tm_row_nn() { # <manifest> <slug>
  [[ -f "$1" ]] || return 0
  LC_ALL=C awk -F'|' -v s="$2" '/^[[:space:]]*\|/ {
      for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
      if ($3 == s && $7 == "cli_fallback" && index($8, "tool_missing:") == 1) { print $2; exit }
    }' "$1"
}

# Rewrites the manifest through a temp file and a rename: keeps the preamble and every
# existing row except those in <drop> (by Path) or <drop-tm> (a slug's stale tool_missing
# row), appends <rows>, and merges both tail sections. Each list argument is a file.
_TMP_MF=""
_write_manifest() { # <manifest> <rows> <drop> <drop-tm> <fallbacks> <oversize> <wid> <task> <run>
  local mf="$1" src="/dev/null"
  if [[ -d "$mf" || -L "$mf" ]]; then
    return 1
  fi
  [[ -f "$mf" ]] && src="$mf"
  _TMP_MF=$(mktemp "$(dirname -- "$mf")/.screenshots-$8.md.XXXXXX") || return 1
  LC_ALL=C awk -v rowsf="$2" -v dropf="$3" -v droptmf="$4" -v fbf="$5" -v obf="$6" \
    -v wid="$7" -v task="$8" -v run="$9" -v hdr="$HDR" -v sep="$SEP" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    BEGIN {
      while ((getline l < dropf) > 0) drop[l] = 1
      while ((getline l < droptmf) > 0) droptm[l] = 1
      state = "pre"
    }
    /^##[[:space:]]/ {
      h = trim(substr($0, 3))
      if (h == "Fallbacks invoked") state = "fb"
      else if (h ~ /^Out-of-budget files/) state = "ob"
      else { state = "other"; other[++no] = $0 }
      next
    }
    /^[[:space:]]*\|/ {
      if (state == "pre") state = "table"
      n = split($0, f, "|")
      for (i = 1; i <= n; i++) f[i] = trim(f[i])
      if (f[2] == "#" || f[2] ~ /^:?-+:?$/) next
      if (f[4] in drop) next
      if ((f[3] in droptm) && f[7] == "cli_fallback" && index(f[8], "tool_missing:") == 1) next
      rows[++nr] = $0
      next
    }
    state == "pre" { pre[++np] = $0; next }
    state == "fb" { if ($0 ~ /^- / && $0 !~ /^- \(none\)/) fb[++nf] = $0; next }
    state == "ob" { if ($0 ~ /^- / && $0 !~ /^- \(none\)/) ob[++nb] = $0; next }
    { if (state == "other" || trim($0) != "") other[++no] = $0 }
    END {
      while (np > 0 && trim(pre[np]) == "") np--
      if (np == 0) { print "# Screenshots — " wid " / " task; print ""; print "> Run index: " run "." }
      for (i = 1; i <= np; i++) print pre[i]
      print ""; print hdr; print sep
      for (i = 1; i <= nr; i++) print rows[i]
      while ((getline l < rowsf) > 0) print l
      print ""
      while (no > 0 && trim(other[no]) == "") no--
      if (no > 0) { for (i = 1; i <= no; i++) print other[i]; print "" }
      print "## Fallbacks invoked"; print ""
      c = nf
      for (i = 1; i <= nf; i++) print fb[i]
      while ((getline l < fbf) > 0) { print l; c++ }
      if (!c) print "- (none)"
      print ""; print "## Out-of-budget files (link-only)"; print ""
      c = nb
      for (i = 1; i <= nb; i++) print ob[i]
      while ((getline l < obf) > 0) { print l; c++ }
      if (!c) print "- (none)"
    }' "$src" > "$_TMP_MF" || return 1
  chmod 644 "$_TMP_MF" && mv -f -- "$_TMP_MF" "$mf" && _TMP_MF=""
}

# ---------------------------------------------------------------------------
# --self-test: no ledger, toolchain or git
# ---------------------------------------------------------------------------
if [[ "$SELF_TEST" -eq 1 ]]; then
  PASS=0
  FAIL=0
  _t() { # <label> <condition-result>
    if [[ "$2" -eq 0 ]]; then
      PASS=$((PASS + 1))
    else
      printf 'FAIL: %s\n' "$1"
      FAIL=$((FAIL + 1))
    fi
  }
  ST=$(mktemp -d)
  trap 'rm -rf "$ST"' EXIT

  _r=0
  [[ "$(_spec_slug 'home:https://x.test:8080/a')" == home && "$(_spec_arg 'home:https://x.test:8080/a')" == 'https://x.test:8080/a' ]] || _r=1
  _t "spec splits on the first colon" "$_r"
  _r=0
  [[ "$(_spec_slug diff)" == diff && -z "$(_spec_arg diff)" ]] || _r=1
  _t "spec without an arg" "$_r"
  _slug_ok "ab-1" && ! _slug_ok "Ab" && ! _slug_ok "-a"
  _t "slug grammar" $?

  printf 'path=/a b/dv-DV0-01-x.png bytes=12 ok=true error=null\n' > "$ST/c"
  _r=0
  [[ "$(_parse_contract "$ST/c")" == "/a b/dv-DV0-01-x.png	12	true	null" ]] || _r=1
  _t "contract line with a spaced path" "$_r"

  MF="$ST/screenshots-DV0.md"
  : > "$ST/empty"
  printf '| 01 | a | dv-DV0-01-a.png | 5 | web | web/playwright | a | t | — |\n' > "$ST/r1"
  printf -- '- dv-DV0-01: web → cli_fallback\n' > "$ST/fb1"
  _write_manifest "$MF" "$ST/r1" "$ST/empty" "$ST/empty" "$ST/fb1" "$ST/empty" wt DV0 0
  printf '| 02 | b | — | 0 | all | cli_fallback | tool_missing: silicon(absent) | t | — |\n' > "$ST/r2"
  printf '%s\n' b > "$ST/dtm"
  printf '| 03 | b | dv-DV0-03-b.png | 7 | web | cli_fallback | b | t | — |\n' > "$ST/r3"
  _write_manifest "$MF" "$ST/r2" "$ST/empty" "$ST/empty" "$ST/empty" "$ST/empty" wt DV0 0
  _write_manifest "$MF" "$ST/r3" "$ST/empty" "$ST/dtm" "$ST/empty" "$ST/empty" wt DV0 0
  [[ "$(_row_count "$MF")" == 2 ]] && [[ "$(grep -c '^## Fallbacks invoked$' "$MF")" == 1 ]] \
    && grep -qF -- '- dv-DV0-01: web → cli_fallback' "$MF" && ! grep -q 'tool_missing:' "$MF" \
    && grep -qxF -- '- (none)' "$MF" && [[ "$(head -1 "$MF")" == '# Screenshots — wt / DV0' ]] \
    && [[ -z "$(find "$ST" -name '.screenshots-*')" ]]
  _t "manifest rewrite keeps rows and tails, drops a superseded tool_missing row" $?
  printf '%s\n' dv-DV0-01-a.png > "$ST/drop"
  _write_manifest "$MF" "$ST/empty" "$ST/drop" "$ST/empty" "$ST/empty" "$ST/empty" wt DV0 0
  [[ "$(_row_count "$MF")" == 1 ]] && ! grep -q 'dv-DV0-01-a.png' "$MF"
  _t "a dropped path loses its row" $?

  printf '\nself-test: %d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# Argument validation — all before anything is resolved or written.
# ---------------------------------------------------------------------------
[[ -n "$TASK_ID" ]] || usage "--task-id required"
_task_id_ok "$TASK_ID" || usage "--task-id must match ^[A-Z]{2}[0-9]+\$ (got: $TASK_ID)"
[[ "$N_CAP" -ge 1 ]] || usage "at least one --capture required"
[[ "$N_CAP" -le "$MAX_CAPTURES" ]] || usage "screenshot_count_exceeded — $N_CAP captures, a task holds at most $MAX_CAPTURES"
if [[ -n "$PLATFORM" ]] && ! _field_ok "$PLATFORM"; then usage "--platform must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$"; fi
if [[ -n "$WORKTASK_ARG" ]] && ! _field_ok "$WORKTASK_ARG"; then usage "--worktask-id must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$"; fi
if [[ -n "$CONTEXT_ARG" && ! -d "$CONTEXT_ARG" ]]; then usage "--context-dir $CONTEXT_ARG is not a directory"; fi
# A ref starting with `-` would reach git as an option.
if [[ "$BASE_REF" == -* ]]; then usage "--base-ref must not start with -"; fi
for _v in "$VIEWPORT" "$SIZE"; do
  if [[ -n "$_v" && ! "$_v" =~ ^[0-9]+x[0-9]+$ ]]; then usage "--viewport and --size take WxH"; fi
done
if [[ -n "$PRODUCT" || -n "$ROOT_FILE" ]]; then
  [[ -n "$PRODUCT" && -n "$ROOT_FILE" ]] || usage "--product and --root-file go together"
  [[ -f "$ROOT_FILE" ]] || usage "--root-file $ROOT_FILE is not a file"
fi
if [[ -n "$CANVAS_FILES" && ! -f "$CANVAS_FILES" ]]; then usage "--canvas-files $CANVAS_FILES is not a file"; fi
SEEN=" "
while IFS= read -r _spec; do
  [[ -n "$_spec" ]] || continue
  _s=$(_spec_slug "$_spec")
  _slug_ok "$_s" || usage "--capture slug must be kebab-case ≤40 chars (got: $_s)"
  case "$SEEN" in *" $_s "*) usage "--capture slug $_s given twice" ;; esac
  SEEN="$SEEN$_s "
done <<< "$CAPTURES"

# ---------------------------------------------------------------------------
# Libraries, root resolution and the worktask guard
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd -P)"
_LIB_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../../shared/lib" 2> /dev/null && pwd -P)"
if [[ ! -r "$_LIB_DIR/audit-lib.sh" || ! -r "$_LIB_DIR/state-read-lib.sh" ]] || ! command -v jq > /dev/null 2>&1; then
  printf >&2 'capture: plugin install broken — shared lib or jq not found\n'
  exit 1
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_LIB_DIR/audit-lib.sh"
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_LIB_DIR/state-read-lib.sh"

[[ -z "$CONTEXT_ARG" ]] || export CONTEXT_DIR="$CONTEXT_ARG"
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [[ "$_CTX_RC" -eq 2 ]]; then
  printf >&2 'capture: root resolver unreachable\n'
  exit 1
fi
if [[ "$_CTX_RC" -ne 0 || ! -f "$CTX_DIR/state.json" ]]; then
  printf >&2 'no worktask resolved — runs only inside a worktask DV stage\n'
  exit 2
fi
STATE="$CTX_DIR/state.json"
_G_RC=0
_GUARD=$(trap - ERR; bash "$SCRIPT_DIR/resolve-worktask.sh" --task-id "$TASK_ID" --state "$STATE") || _G_RC=$?
case "$_G_RC" in
  0) ;;
  4)
    printf >&2 'no worktask resolved — runs only inside a worktask DV stage\n'
    exit 2
    ;;
  *) exit 2 ;;
esac
WORKTASK_ID="${_GUARD#worktask_id=}"
WORKTASK_ID="${WORKTASK_ID%% *}"
if [[ -n "$WORKTASK_ARG" && "$WORKTASK_ARG" != "$WORKTASK_ID" ]]; then
  printf >&2 'capture: --worktask-id %s is not the resolved ledger'"'"'s %s; writing nothing\n' "$WORKTASK_ARG" "$WORKTASK_ID"
  exit 2
fi
# Every adapter below re-resolves the root; pinning it keeps them on this ledger.
export CONTEXT_DIR="$CTX_DIR"

if [[ -z "$PLATFORM" ]]; then
  PLATFORM=$(jq -r --arg t "$TASK_ID" '(.tasks[$t].metadata.platform? // .platform // "all") | tostring' "$STATE" 2> /dev/null || echo all)
  _field_ok "$PLATFORM" || usage "ledger platform is malformed: $PLATFORM"
fi
if [[ -z "$BASE_REF" ]]; then
  BASE_REF=$(jq -r --arg t "$TASK_ID" '.tasks[$t].metadata.base_ref? // "" | tostring' "$STATE" 2> /dev/null || true)
  [[ "$BASE_REF" != -* ]] || BASE_REF=""
fi
RUN_INDEX=$(corpflow_run_index "$STATE")
[[ "$RUN_INDEX" =~ ^[0-9]+$ ]] || RUN_INDEX=0

# ---------------------------------------------------------------------------
# Dispatch table: one lookup, then the per-capture argument check for that adapter.
# ---------------------------------------------------------------------------
ROUTE_REASON=""
case "$PLATFORM" in
  apple | macos)
    if [[ -n "$PRODUCT" ]]; then
      PRIMARY=macos_window
    elif [[ -n "$CANVAS_FILES" ]]; then
      PRIMARY=apple_canvas
    else
      PRIMARY=cli_fallback
      ROUTE_REASON=delegation_unavailable
    fi
    [[ -z "$VIEWPORT" ]] || usage "--viewport is web-only"
    ;;
  web) PRIMARY=web ;;
  android) PRIMARY=android ;;
  *)
    PRIMARY=cli_fallback
    ROUTE_REASON=unknown_platform
    ;;
esac
case "$PLATFORM" in
  apple | macos) ;;
  *)
    if [[ -n "$PRODUCT$ROOT_FILE$PACKAGE_PATH$SIZE$CANVAS_FILES" ]]; then
      usage "--product, --root-file, --package-path, --size and --canvas-files are apple/macos-only"
    fi
    [[ "$PLATFORM" == web || -z "$VIEWPORT" ]] || usage "--viewport is web-only"
    ;;
esac
while IFS= read -r _spec; do
  [[ -n "$_spec" ]] || continue
  _a=$(_spec_arg "$_spec")
  case "$PRIMARY" in
    web) [[ "$_a" =~ ^(https?|file):// ]] || usage "web --capture needs <slug>:<http/https/file URL>" ;;
    android) [[ -z "$_a" || "$_a" =~ ^[A-Za-z0-9._:-]+$ ]] || usage "android --capture arg must be an adb serial" ;;
    apple_canvas) [[ "$_a" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]] || usage "apple_canvas --capture needs <slug>:<Module.Type>" ;;
    macos_window | cli_fallback)
      if [[ -n "$_a" && ! -f "$_a" ]]; then usage "--capture arg $_a is not a file"; fi
      if [[ "$PRIMARY" == macos_window && -n "$_a" ]] && grep -qE '^[[:space:]]*shot([[:space:]]|$)' "$_a"; then
        usage "macos steps file $_a must not hold shot lines; the capture adds its own"
      fi
      ;;
  esac
done <<< "$CAPTURES"

# ---------------------------------------------------------------------------
# Paths and scratch
# ---------------------------------------------------------------------------
IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
LOGS_DIR="${CTX_DIR}/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
MANIFEST="${IMAGES_DIR}/screenshots-${TASK_ID}.md"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"
LOG="${LOGS_DIR}/dv-capture-${TASK_ID}-$(date -u +%Y%m%d-%H%M%S).log"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [[ -z "${_TMP_MF:-}" ]] || rm -f "$_TMP_MF"' EXIT
for _f in rows drop droptm fallbacks oversize results; do : > "$WORK/$_f"; done
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HARD=0
NOROW=0

audit() { # <action> <slug> <metadata-json>
  corpflow_audit_row --file "$AUDIT_LOG" --actor "dv-capture-entry" \
    --action "$1" --subject "${WORKTASK_ID}/$2" --task-id "$TASK_ID" --result ok --meta "$3" 2> /dev/null || true
}

audit_fallback() { # <slug> <reason>
  audit screenshot_platform_fallback "$1" "$(jq -nc --arg p "$PLATFORM" --arg r "$2" --argjson ri "$RUN_INDEX" \
    '{requested_platform:$p,used_adapter:"cli_fallback",reason:$r,run_index:$ri}')"
}

# _child <out-file> <script> [args...] — stdout to <out-file>, stderr to the run log; echoes rc.
# stdin is /dev/null: the callers loop over a here-string, which a child tool would otherwise drain.
_child() {
  local out="$1" script="$2" rc=0 IFS=' '
  shift 2
  printf '== %s %s\n' "$script" "$*" >> "$LOG"
  bash "$SCRIPT_DIR/$script" "$@" < /dev/null > "$out" 2>> "$LOG" || rc=$?
  printf '%s' "$rc"
}

# result <slug> <nn> <adapter> <status> <bytes> <path> — one TSV line per capture, in order.
result() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$WORK/results"; }

_nn_of() { # <path> → NN from dv-<TASK>-NN-<slug>.png
  local b="${1##*/}"
  b="${b#dv-"$TASK_ID"-}"
  printf '%s' "${b%%-*}"
}

# Size budget after an image lands. Below WARN_BYTES size-budget.sh only writes a second
# screenshot_captured row, so it is skipped there. Sets B_STATUS (ok|oversize), B_BYTES, B_PATH.
budget() { # <path> <slug>
  local rc line
  B_STATUS=ok
  B_PATH="$1"
  B_BYTES=$(_stat_bytes "$1")
  [[ "$B_BYTES" -ge "$WARN_BYTES" ]] || return 0
  rc=$(_child "$WORK/budget" size-budget.sh --path "$1" --worktask-id "$WORKTASK_ID" --slug "$2")
  line=$(sed -n 's/^size_audit: path=\(.*\) bytes=\([0-9]*\) verdict=.*/\1	\2/p' "$WORK/budget" | tail -1)
  if [[ "$rc" -eq 3 && -n "$line" ]]; then
    B_PATH="${line%%	*}"
    B_BYTES="${line##*	}"
    B_STATUS=oversize
    printf -- '- %s: %s after quantize, exceeds 500 KB\n' "$B_PATH" "$B_BYTES" >> "$WORK/oversize"
    printf '%s\n' "${1##*/}" >> "$WORK/drop"
  elif [[ "$rc" -eq 0 ]]; then
    B_BYTES=$(_stat_bytes "$1")
  fi
}

# Records a landed image: size budget, then a manifest row unless the adapter wrote its own.
image() { # <slug> <path> <adapter> <row:yes|no>
  local nn
  nn=$(_nn_of "$2")
  budget "$2" "$1"
  if [[ "$B_STATUS" == oversize ]]; then
    result "$1" "$nn" "$3" oversize "$B_BYTES" "$B_PATH"
    return 0
  fi
  if [[ "$4" == yes ]]; then
    printf '| %s | %s | %s | %s | %s | %s | %s | %s | — |\n' \
      "$nn" "$1" "${2##*/}" "$B_BYTES" "$PLATFORM" "$3" "$1" "$NOW" >> "$WORK/rows"
  fi
  printf '%s\n' "$1" >> "$WORK/droptm"
  result "$1" "$nn" "$3" ok "$B_BYTES" "$2"
}

# The last rung: cli-fallback.sh. Its tool_missing floor row is its own write.
cli_rung() { # <slug> <file-list-or-empty>
  local rc c p bytes err nn
  local args
  args=(--worktask-id "$WORKTASK_ID" --task-id "$TASK_ID" --slug "$1" --platform "$PLATFORM" --run-index "$RUN_INDEX")
  [[ -z "$BASE_REF" ]] || args+=(--base-ref "$BASE_REF")
  [[ -z "$2" ]] || args+=(--files "$2")
  rc=$(_child "$WORK/out" cli-fallback.sh "${args[@]}")
  c=$(_parse_contract "$WORK/out")
  p="${c%%	*}"
  bytes=$(printf '%s' "$c" | cut -f2)
  err="${c##*	}"
  if [[ "$rc" -eq 0 && -s "$p" ]]; then
    image "$1" "$p" cli_fallback yes
    return 0
  fi
  nn=$(_nn_of "$p")
  if [[ "$rc" -eq 2 && "$err" == tool_missing ]] && [[ -n "$(_tm_row_nn "$MANIFEST" "$1")" ]]; then
    nn=$(_tm_row_nn "$MANIFEST" "$1")
    printf -- '- dv-%s-%s: silicon and ImageMagick both absent on PATH; no capture produced (`tool_missing`).\n' \
      "$TASK_ID" "$nn" >> "$WORK/fallbacks"
    result "$1" "$nn" cli_fallback tool_missing 0 "—"
    return 0
  fi
  if [[ "$rc" -eq 2 || "$rc" -eq 3 ]] && [[ -n "$err" ]]; then
    printf -- '- dv-%s-%s: cli_fallback produced no image and no row (`%s`).\n' "$TASK_ID" "${nn:---}" "$err" >> "$WORK/fallbacks"
    result "$1" "${nn:---}" cli_fallback "failed:$err" "${bytes:-0}" "—"
  else
    HARD=1
    result "$1" "${nn:---}" cli_fallback error 0 "—"
  fi
  NOROW=1
  printf >&2 'capture: %s ended with no row (cli-fallback exit %s); see %s\n' "$1" "$rc" "$LOG"
}

# A primary adapter produced nothing: note the ladder step, then take the last rung.
fell_through() { # <slug> <adapter> <intended-path|""> <error> <rc>
  local label="$1"
  [[ -z "$3" ]] || label="dv-${TASK_ID}-$(_nn_of "$3")"
  printf -- '- %s: %s → cli_fallback (`%s`, exit %s).\n' "$label" "$2" "${4:-no_output}" "$5" >> "$WORK/fallbacks"
  cli_rung "$1" ""
}

# ---------------------------------------------------------------------------
# Captures, within the per-task cap
# ---------------------------------------------------------------------------
EXISTING=$(_row_count "$MANIFEST")
ALLOWED=$((MAX_CAPTURES - EXISTING))
[[ "$ALLOWED" -ge 0 ]] || ALLOWED=0
TAKEN=""
REFUSED=""
_i=0
while IFS= read -r _spec; do
  [[ -n "$_spec" ]] || continue
  _i=$((_i + 1))
  if [[ "$_i" -le "$ALLOWED" ]]; then TAKEN="$TAKEN$_spec"$'\n'; else REFUSED="$REFUSED$_spec"$'\n'; fi
done <<< "$CAPTURES"

# macos_window renders every shot in one host run and writes its own rows, so it goes as a batch.
if [[ "$PRIMARY" == macos_window && -n "$TAKEN" ]]; then
  : > "$WORK/steps"
  while IFS= read -r _spec; do
    [[ -n "$_spec" ]] || continue
    _a=$(_spec_arg "$_spec")
    [[ -z "$_a" ]] || { cat -- "$_a"; printf '\n'; } >> "$WORK/steps"
    printf 'shot %s\n' "$(_spec_slug "$_spec")" >> "$WORK/steps"
  done <<< "$TAKEN"
  _args=(--worktask-id "$WORKTASK_ID" --task-id "$TASK_ID" --product "$PRODUCT" --root-file "$ROOT_FILE"
    --steps "$WORK/steps" --platform "$PLATFORM" --run-index "$RUN_INDEX")
  [[ -z "$PACKAGE_PATH" ]] || _args+=(--package-path "$PACKAGE_PATH")
  [[ -z "$SIZE" ]] || _args+=(--size "$SIZE")
  _rc=$(_child "$WORK/mw" macos-window-capture.sh "${_args[@]}")
  if [[ "$_rc" -eq 0 ]]; then
    sed -n 's/^path=\(.*\) bytes=[0-9]* ok=true error=null$/\1/p' "$WORK/mw" > "$WORK/mw-paths"
    while IFS= read -r _spec; do
      [[ -n "$_spec" ]] || continue
      _s=$(_spec_slug "$_spec")
      _p=$(grep -E "/dv-${TASK_ID}-[0-9][0-9]-${_s}\.png\$" "$WORK/mw-paths" | tail -1 || true)
      if [[ -n "$_p" && -s "$_p" ]]; then
        image "$_s" "$_p" macos_window no
      else
        fell_through "$_s" macos_window "" shot_missing 0
      fi
    done <<< "$TAKEN"
  else
    _c=$(_parse_contract "$WORK/mw")
    while IFS= read -r _spec; do
      [[ -n "$_spec" ]] || continue
      fell_through "$(_spec_slug "$_spec")" macos_window "" "${_c##*	}" "$_rc"
    done <<< "$TAKEN"
  fi
  TAKEN=""
fi

while IFS= read -r _spec; do
  [[ -n "$_spec" ]] || continue
  _s=$(_spec_slug "$_spec")
  _a=$(_spec_arg "$_spec")
  case "$PRIMARY" in
    web | android)
      _args=(--worktask-id "$WORKTASK_ID" --task-id "$TASK_ID" --slug "$_s" --platform "$PLATFORM" --run-index "$RUN_INDEX")
      if [[ "$PRIMARY" == web ]]; then
        _args+=(--url "$_a")
        [[ -z "$VIEWPORT" ]] || _args+=(--viewport "$VIEWPORT")
        _script=web-capture.sh
        _label=web/playwright
      else
        [[ -z "$_a" ]] || _args+=(--serial "$_a")
        _script=android-capture.sh
        _label=android/adb
      fi
      # Both adapters write their own screenshot_captured / screenshot_platform_fallback rows.
      _rc=$(_child "$WORK/out" "$_script" "${_args[@]}")
      _c=$(_parse_contract "$WORK/out")
      _p="${_c%%	*}"
      if [[ "$_rc" -eq 0 && -s "$_p" ]]; then
        image "$_s" "$_p" "$_label" yes
      else
        fell_through "$_s" "$_label" "$_p" "${_c##*	}" "$_rc"
      fi
      ;;
    apple_canvas)
      _rc=$(_child "$WORK/out" apple-canvas.sh --worktask-id "$WORKTASK_ID" --task-id "$TASK_ID" \
        --modified-files "$CANVAS_FILES" --view "$_a" --slug "$_s")
      _p=$(grep -E "/dv-${TASK_ID}-[0-9][0-9]-${_s}\.png\$" "$WORK/out" | tail -1 || true)
      if [[ "$_rc" -eq 0 && -n "$_p" && -s "$_p" ]]; then
        # apple-canvas.sh writes canvas_render, not screenshot_captured.
        audit screenshot_captured "$_s" "$(jq -nc --arg s "$_s" --arg p "$_p" --argjson b "$(_stat_bytes "$_p")" \
          --arg pl "$PLATFORM" '{slug:$s,path:$p,bytes:$b,platform:$pl,adapter:"apple_canvas"}')"
        image "$_s" "$_p" apple_canvas yes
      else
        # The canvas's own row escalates to the simulator, which only a platform agent can drive.
        audit_fallback "$_s" canvas_sim_unavailable
        fell_through "$_s" apple_canvas "" canvas_failed "$_rc"
      fi
      ;;
    cli_fallback)
      audit_fallback "$_s" "$ROUTE_REASON"
      if [[ "$ROUTE_REASON" == delegation_unavailable ]]; then
        printf -- '- %s: apple simulator capture is delegated to the platform agent (`delegation_unavailable`); cli_fallback used.\n' \
          "$_s" >> "$WORK/fallbacks"
      fi
      cli_rung "$_s" "$_a"
      ;;
  esac
done <<< "$TAKEN"

while IFS= read -r _spec; do
  [[ -n "$_spec" ]] || continue
  _s=$(_spec_slug "$_spec")
  audit screenshot_count_exceeded "$_s" "$(jq -nc --arg s "$_s" '{attempted_slug:$s}')"
  result "$_s" -- - screenshot_count_exceeded 0 ""
done <<< "$REFUSED"

# ---------------------------------------------------------------------------
# Manifest, summary, facts
# ---------------------------------------------------------------------------
if ! _write_manifest "$MANIFEST" "$WORK/rows" "$WORK/drop" "$WORK/droptm" "$WORK/fallbacks" \
  "$WORK/oversize" "$WORKTASK_ID" "$TASK_ID" "$RUN_INDEX"; then
  printf >&2 'capture: could not write %s\n' "$MANIFEST"
  exit 1
fi

FACTS="[]"
while IFS=$'\t' read -r _s _nn _ad _st _b _p; do
  [[ -n "$_s" ]] || continue
  case "$_st" in
    ok) printf '%s %s %s %s\n' "$_nn" "$_s" "$_ad" "$_b" ;;
    screenshot_count_exceeded)
      printf -- '-- %s - screenshot_count_exceeded\n' "$_s"
      continue
      ;;
    *) printf '%s %s %s %s\n' "$_nn" "$_s" "$_ad" "$_st" ;;
  esac
  FACTS=$(jq -c --arg s "$_s" --arg p "$_p" --argjson b "${_b:-0}" --arg pl "$PLATFORM" --arg st "$_st" \
    '. + [{slug:$s,path:$p,bytes:$b,platform:$pl,ok:($st == "ok"),design_ref:"—"}]' <<< "$FACTS")
done < "$WORK/results"
printf 'manifest=%s\n' "$MANIFEST"
printf 'facts_screenshots=%s\n' "$FACTS"

[[ "$HARD" -eq 0 ]] || exit 1
[[ "$NOROW" -eq 0 ]] || exit 3
exit 0
