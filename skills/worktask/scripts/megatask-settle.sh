#!/usr/bin/env bash
# @description megatask-settle.sh — settle a /megatask per-issue run as failed before it stops
#   for a user who is not there, so hooks/megatask-monitor.sh frees its track and keeps its
#   dependents blocked.
#
#   A per-issue run is a background subagent: any path that ends at USER (the last link of an
#   escalation chain, a stop per § Error Handling, a blocked stage) would otherwise leave
#   workspace.json at "in_progress", and the monitor, which settles only "completed" or
#   "failed", would hold the track for good. Outside /megatask this is a no-op, so the call can
#   sit on every such path unconditionally.
#
# Usage:
#   megatask-settle.sh --subject <ID> --detail <text> [--state <state.json>]
#   megatask-settle.sh -h | --help
#
# @arg --subject <ID>   Ledger id of the stage or gate that stopped (PL0, DV1, FN0, …).
# @arg --detail <text>  One line naming why; stored in the audit row, capped at 300 chars.
# @arg --state <path>   Ledger (default: corpflow_context_dir()/state.json). workspace.json is
#                       the file beside that .context/, never one in the caller's cwd.
#
# Megatask mode is PL0.metadata.megatask_group, the key /megatask stamps on every per-issue PL0.
#
# stdout (key=value): result=settled|skipped|refused, reason=<why>, workspace=<path>.
#   skipped/not_megatask  the ledger names no megatask group; nothing written
#   skipped/already_<s>   execution.status is already completed or failed; never overwritten,
#                         so a PARK's parked_escalation or FN's completed stands
#   settled/escalated_to_user  execution.status "failed", execution.reason
#                         "escalated_to_user", one megatask_escalated audit row
#   refused/<why>         symlink, missing, not_regular_file, unreadable, malformed or
#                         write_failed; nothing written through a link
#
# @exitcode 0 settled or skipped
# @exitcode 1 refused: the track will not free by itself, report it and stop
# @exitcode 2 usage error, unresolved or unparseable ledger, jq missing, broken install
#
# Minimum shell: bash 3.2+. Requires jq.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
_MS_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd -P)"

die() {
  printf >&2 'megatask-settle: %s\n' "$2"
  exit "$1"
}

usage() {
  sed -n '/^# Usage:/,/^# @arg --subject/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
  exit 2
}

SUBJECT="" DETAIL="" STATE_PATH=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    --subject | --detail | --state)
      [ "$#" -ge 2 ] || die 2 "missing value for $1"
      case "$1" in
        --subject) SUBJECT="$2" ;;
        --detail) DETAIL="$2" ;;
        --state) STATE_PATH="$2" ;;
      esac
      shift 2
      ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

[[ "$SUBJECT" =~ ^[A-Z]{2}[0-9]+$ ]] || die 2 "--subject needs a ledger id such as PL0 or DV1"
[ -n "$DETAIL" ] || die 2 "--detail is required"
command -v jq > /dev/null 2>&1 || die 2 "jq is required"
for _ms_lib in "$_MS_ROOT/skills/shared/lib/audit-lib.sh" \
  "$_MS_ROOT/skills/shared/lib/state-read-lib.sh"; do
  [ -r "$_ms_lib" ] || die 2 "plugin install broken — missing $_ms_lib"
  # shellcheck source=/dev/null
  . "$_ms_lib"
done

if [ -z "$STATE_PATH" ]; then
  _ms_rc=0
  _ms_ctx=$(corpflow_context_dir) || _ms_rc=$?
  [ "$_ms_rc" -eq 0 ] && [ -n "$_ms_ctx" ] || die 2 "no .context/ resolved; pass --state"
  STATE_PATH="$_ms_ctx/state.json"
fi
[ -f "$STATE_PATH" ] || die 2 "no ledger at $STATE_PATH"
jq -e 'type == "object"' "$STATE_PATH" > /dev/null 2>&1 || die 2 "unparseable ledger at $STATE_PATH"

WS="$(dirname -- "$(dirname -- "$STATE_PATH")")/workspace.json"
AUDIT="$(dirname -- "$STATE_PATH")/logs/audit.jsonl"

emit() { # <result> <reason>
  printf 'result=%s\nreason=%s\nworkspace=%s\n' "$1" "$2" "$WS"
}

group=$(jq -r '(.tasks.PL0.metadata.megatask_group // .tasks["PL\(.run_index // 0)"].metadata.megatask_group // "")
  | if type == "string" then . else "" end' "$STATE_PATH")
if [ -z "$group" ]; then
  emit skipped not_megatask
  exit 0
fi

# The link check repeats after the read and before the rename, so a link swapped in mid-write
# costs a refusal rather than a write through it.
refuse() {
  emit refused "$1"
  exit 1
}
[ ! -L "$WS" ] || refuse symlink
[ -e "$WS" ] || refuse missing
[ -f "$WS" ] || refuse not_regular_file
body=$(cat -- "$WS" 2> /dev/null) || refuse unreadable
[ ! -L "$WS" ] || refuse symlink
current=$(printf '%s' "$body" | jq -r '.execution.status // "in_progress"' 2> /dev/null) || refuse malformed
case "$current" in
  completed | failed)
    emit skipped "already_$current"
    exit 0
    ;;
esac
body=$(printf '%s' "$body" \
  | jq '.execution = ((.execution // {}) + {status: "failed", reason: "escalated_to_user"})' 2> /dev/null) \
  || refuse malformed
tmp=$(mktemp "$(dirname -- "$WS")/.workspace.json.XXXXXX" 2> /dev/null) || refuse write_failed
if ! { printf '%s\n' "$body" > "$tmp" && [ ! -L "$WS" ] && mv -f -- "$tmp" "$WS"; }; then
  rm -f -- "$tmp"
  [ ! -L "$WS" ] || refuse symlink
  refuse write_failed
fi

corpflow_audit_row --file "$AUDIT" --actor orchestrator --action megatask_escalated \
  --result block --subject "$SUBJECT" --task-id "$SUBJECT" \
  --meta "$(jq -cn --arg g "$group" --arg d "${DETAIL:0:300}" \
    '{megatask_group: $g, reason: "escalated_to_user", detail: $d}')"
emit settled escalated_to_user
