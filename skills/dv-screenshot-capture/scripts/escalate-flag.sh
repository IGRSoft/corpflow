#!/usr/bin/env bash
# @description  DV's upward-only screenshot safety net. The planner decides
#               requires_screenshots; this helper raises a `false` flag to `true` when the
#               change set actually touches UI paths on an admitted platform. It never writes
#               `false`, and every operational failure is exit 0 with a warn row: a missed net
#               leaves the planner's verdict in place, it never blocks DV.
#
#               Run it from the DV worktree before capture and branch on its stdout, not on
#               the prompt-stamped flag, which goes stale after an escalation.
#
# @arg  --task-id <TASK_ID>   DV task (required); must be a key of the ledger's .tasks
# @arg  --context-dir <dir>   .context to use; default: the shared root ladder
# @arg  --invoker <dv|gate>   audit label only (default dv); with gate an escalated line also
#                             carries matched=<n>. No branch reads it.
#
# @stdout  exactly one line on exit 0:
#            requires_screenshots=<true|false> action=<escalated|noop|warn> reason=<token>
#          The flag is the effective value after the run. Platform and base ref are read from
#          the ledger only: a caller-supplied value could suppress an escalation.
# @exitcode 0  any outcome above, including warn rows
# @exitcode 1  broken install (shared lib, detector, state-patch or jq missing); nothing written
# @exitcode 2  usage: bad args, no ledger resolved, or a task id that is not a ledger key
#
# Write order is task flag, then ledger flag: the gate reads the task flag first, so a crash
# between the two writes still honours the escalation, and a re-run raises the missed ledger
# flag from current state.
#
# Minimum shell: Bash 3.2.

set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# The only flag payload this script ever writes. No `false` payload exists in the source.
readonly RAISE_PAYLOAD='{"requires_screenshots":true}'
readonly MATCH_CAP=10

TASK_ID=""
CONTEXT_ARG=""
INVOKER="dv"
N_MATCHED=""

usage() {
  [[ -z "${1:-}" ]] || printf >&2 'escalate-flag: %s\n' "$1"
  printf >&2 'usage: escalate-flag.sh --task-id <TASK_ID> [--context-dir <dir>] [--invoker dv|gate]\n'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id | --context-dir | --invoker)
      [[ $# -ge 2 && -n "$2" ]] || usage "$1 needs a value"
      case "$1" in
        --task-id) TASK_ID="$2" ;;
        --context-dir) CONTEXT_ARG="$2" ;;
        --invoker) INVOKER="$2" ;;
      esac
      shift 2
      ;;
    -h | --help) usage ;;
    *) usage "unknown flag $1" ;;
  esac
done

[[ "$INVOKER" == "dv" || "$INVOKER" == "gate" ]] || usage "--invoker must be dv or gate"
[[ -n "$TASK_ID" ]] || usage "--task-id is required"
[[ $TASK_ID =~ ^[A-Z]{2}[0-9]+$ ]] || usage "--task-id must match ^[A-Z]{2}[0-9]+\$"
if [[ -n "$CONTEXT_ARG" && ! -d "$CONTEXT_ARG" ]]; then usage "--context-dir $CONTEXT_ARG is not a directory"; fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd -P)"
_LIB_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../../shared/lib" 2> /dev/null && pwd -P)"
_WT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../../worktask/scripts" 2> /dev/null && pwd -P)"
DETECTOR="$_WT_DIR/detect-ui-change.sh"
STATE_PATCH="$_WT_DIR/state-patch.sh"
if [[ ! -r "$_LIB_DIR/audit-lib.sh" || ! -r "$_LIB_DIR/state-read-lib.sh" || ! -r "$_WT_DIR/branch-lib.sh" ||
  ! -r "$DETECTOR" || ! -r "$STATE_PATCH" ]] || ! command -v jq > /dev/null 2>&1; then
  printf >&2 'escalate-flag: plugin install broken — shared lib, detector, state-patch or jq not found\n'
  exit 1
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_LIB_DIR/audit-lib.sh"
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_LIB_DIR/state-read-lib.sh"
# shellcheck source=../../worktask/scripts/branch-lib.sh
. "$_WT_DIR/branch-lib.sh"

[[ -z "$CONTEXT_ARG" ]] || export CONTEXT_DIR="$CONTEXT_ARG"
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [[ "$_CTX_RC" -eq 2 ]]; then
  printf >&2 'escalate-flag: root resolver unreachable\n'
  exit 1
fi
if [[ "$_CTX_RC" -ne 0 || ! -f "$CTX_DIR/state.json" ]]; then
  printf >&2 'escalate-flag: no worktask ledger resolved\n'
  exit 2
fi
STATE="$CTX_DIR/state.json"
export STATE_PATH="$STATE"

_G_RC=0
_GUARD=$(trap - ERR; bash "$SCRIPT_DIR/resolve-worktask.sh" --task-id "$TASK_ID" --state "$STATE" 2> /dev/null) || _G_RC=$?
if [[ "$_G_RC" -ne 0 ]]; then
  printf >&2 'escalate-flag: task %s is not in the ledger at %s\n' "$TASK_ID" "$STATE"
  exit 2
fi
WID="${_GUARD#worktask_id=}"
WID="${WID%% *}"

LOGS_DIR="$CTX_DIR/logs"
AUDIT_LOG="$LOGS_DIR/audit.jsonl"

# --- reporting -------------------------------------------------------------
PLATFORM="unknown"
BASE_USED=""
RAISED_JSON='[]'
MATCH_JSON=""

audit() { # <result> <reason>
  local meta
  meta=$(jq -nc --arg p "$PLATFORM" --arg b "$BASE_USED" --arg r "$2" --arg inv "$INVOKER" --argjson raised "$RAISED_JSON" \
    --argjson m "${MATCH_JSON:-null}" \
    '{platform:$p, base:$b, reason:$r, invoker:$inv, raised:$raised}
     + (if $m == null then {} else {matched_count:$m.count, matched:$m.paths} end)')
  mkdir -p "$LOGS_DIR" 2> /dev/null || true
  corpflow_audit_row --file "$AUDIT_LOG" --actor "dv-escalate-flag" \
    --action screenshot_flag_escalated --subject "${WID}/${TASK_ID}" --task-id "$TASK_ID" \
    --result "$1" --meta "$meta" 2> /dev/null || true
}

# finish <flag> <action> <reason> — one stdout line, exit 0. warn/escalated also audit.
finish() {
  case "$2" in
    escalated) audit ok "$3" ;;
    warn) audit warn "$3" ;;
  esac
  # The gate's block text needs the count; the DV line stays byte-identical.
  local extra=""
  if [[ "$2" == "escalated" && "$INVOKER" == "gate" ]]; then extra=" matched=$N_MATCHED"; fi
  printf 'requires_screenshots=%s action=%s reason=%s%s\n' "$1" "$2" "$3" "$extra"
  exit 0
}

# --- read both flags (the gate's FLAG_JQ for the task, the FN readers' rule for the ledger) ---
if ! (trap - ERR; jq -e . "$STATE" > /dev/null 2>&1); then
  finish true warn ledger_unreadable
fi

# shellcheck disable=SC2016
TASK_FLAG_JQ='
  def flag(o): if (o|type) == "object" and (o|has("requires_screenshots"))
               then (o.requires_screenshots|tostring) else empty end;
  [ flag(.tasks[$t].metadata?), flag(.metadata?), "true" ] | .[0]'
# shellcheck disable=SC2016
LEDGER_FLAG_JQ='
  def flag(o): if (o|type) == "object" and (o|has("requires_screenshots"))
               then (o.requires_screenshots|tostring) else empty end;
  [ flag(.metadata?), "true" ] | .[0]'

TASK_EFF=$(trap - ERR; jq -r --arg t "$TASK_ID" "$TASK_FLAG_JQ" "$STATE" 2> /dev/null) || finish true warn ledger_unreadable
LEDGER_EFF=$(trap - ERR; jq -r "$LEDGER_FLAG_JQ" "$STATE" 2> /dev/null) || finish true warn ledger_unreadable

if [[ "$TASK_EFF" != "false" && "$LEDGER_EFF" != "false" ]]; then
  finish true noop already_true
fi
# Stdout flag for every non-escalating arm: what the gate would read for this task.
CUR=$([[ "$TASK_EFF" == "false" ]] && echo false || echo true)

PLATFORM=$(trap - ERR; jq -r --arg t "$TASK_ID" \
  '(.tasks[$t].metadata.platform? // .platform? // "all") | if type == "string" then . else "all" end' \
  "$STATE" 2> /dev/null) || PLATFORM="all"

UI_PLATFORMS=$(trap - ERR; bash "$DETECTOR" --ui-platforms 2> /dev/null) || UI_PLATFORMS=""
PATH_CLASSES=$(trap - ERR; bash "$DETECTOR" --path-classes 2> /dev/null) || PATH_CLASSES=""
if [[ -z "$UI_PLATFORMS" || -z "$PATH_CLASSES" ]]; then
  finish "$CUR" warn path_classes_unavailable
fi

if ! printf '%s\n' "$PLATFORM" | grep -qxE "$UI_PLATFORMS"; then
  finish "$CUR" noop platform_not_ui
fi

# --- change-set corpus, from the cwd's git toplevel (the DV worktree) -------
TOP=$(trap - ERR; git -c core.fsmonitor=false rev-parse --show-toplevel 2> /dev/null) || TOP=""
[[ -n "$TOP" ]] || finish "$CUR" warn not_a_git_repo

BASE_RAW=$(trap - ERR; jq -r --arg t "$TASK_ID" '.tasks[$t].metadata.base_ref? // "" | if type == "string" then . else "" end' "$STATE" 2> /dev/null) || BASE_RAW=""
if [[ -z "$BASE_RAW" ]]; then
  BASE_RAW=$(trap - ERR; cd "$TOP" && resolve_base_ref 2> /dev/null) || BASE_RAW=""
fi
BASE_USED=""
if [[ -n "$BASE_RAW" ]]; then
  BASE_USED=$(trap - ERR; cd "$TOP" && resolve_git_ref "$BASE_RAW" 2> /dev/null) || BASE_USED=""
fi
if [[ -z "$BASE_USED" ]] || ! (trap - ERR; git -c core.fsmonitor=false -C "$TOP" rev-parse --verify --quiet "$BASE_USED" > /dev/null 2>&1); then
  BASE_USED="$BASE_RAW"
  finish "$CUR" warn base_unresolvable
fi

CORPUS=$(
  trap - ERR
  {
    git -c core.fsmonitor=false -C "$TOP" diff --no-renames --name-only "${BASE_USED}...HEAD" || exit 1
    git -c core.fsmonitor=false -C "$TOP" diff --no-renames --name-only HEAD || exit 1
    git -c core.fsmonitor=false -C "$TOP" ls-files --others --exclude-standard || exit 1
  } 2> /dev/null
) || CORPUS="__unreadable__"
[[ "$CORPUS" != "__unreadable__" ]] || finish "$CUR" warn diff_unreadable

# Ledger and evidence files are not the change set; deleted paths still count.
MATCHED=$(printf '%s\n' "$CORPUS" | grep -v '^$' | grep -v '^\.context/' | LC_ALL=C sort -u | grep -E "$PATH_CLASSES" || true)
[[ -n "$MATCHED" ]] || finish "$CUR" noop no_ui_path

N_MATCHED=$(printf '%s\n' "$MATCHED" | grep -c . || true)
# Cap inside jq: an early-exiting `head` SIGPIPEs the writer on a large list and pipefail aborts.
MATCH_JSON=$(printf '%s\n' "$MATCHED" | jq -R . | jq -cs --argjson n "$N_MATCHED" --argjson c "$MATCH_CAP" '{count:$n, paths:.[:$c]}')

# --- upward-only writes: task first, then ledger ----------------------------
WLOG="$LOGS_DIR/escalate-flag-${TASK_ID}.log"
mkdir -p "$LOGS_DIR" 2> /dev/null || true
RAISED=""

if [[ "$TASK_EFF" == "false" ]]; then
  if (trap - ERR; bash "$STATE_PATCH" --state "$STATE" --task-meta "$TASK_ID" --set "$RAISE_PAYLOAD" > /dev/null 2>> "$WLOG"); then
    RAISED="task"
  else
    finish false warn task_flag_unwritten
  fi
fi
if [[ "$LEDGER_EFF" == "false" ]]; then
  if (trap - ERR; bash "$STATE_PATCH" --state "$STATE" --ledger-meta --set "$RAISE_PAYLOAD" > /dev/null 2>> "$WLOG"); then
    RAISED="${RAISED:+$RAISED,}ledger"
  else
    RAISED_JSON=$(printf '%s' "$RAISED" | jq -Rc 'split(",") | map(select(. != ""))')
    finish true warn ledger_flag_unwritten
  fi
fi

RAISED_JSON=$(printf '%s' "$RAISED" | jq -Rc 'split(",") | map(select(. != ""))')
finish true escalated ui_path_matched
