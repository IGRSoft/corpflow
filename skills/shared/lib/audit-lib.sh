#!/usr/bin/env bash
# @description audit-lib.sh — the one `.context/logs/audit.jsonl` appender for the skills
#   tree. One writer, one key order, one symlink refusal.
#
#   Not mirrored into hooks/lib/: the hook tree has its own appender,
#   hooks/model-switch-lib.sh corpflow_hook_audit_row.
#
#   Symbols: corpflow_audit_row.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — must be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'audit-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_AUDIT_LIB:-}" ] && return 0
_CORPFLOW_AUDIT_LIB=1

# Not `readonly`: consumer bats suites source this file twice per process, and a second
# readonly assignment is rc 1, which kills a `set -e` caller.

# corpflow_audit_row --file <path> --actor <a> --action <x> --result <r>
#                    --subject <s> --task-id <t> [--meta <compact-json>]
#                    [--meta-kv <key>=<value>]...
#
# Appends exactly one row and always returns 0: an audit row is evidence, never a gate, so
# no failure here may abort the caller that is mid-way through a real action. A caller that
# must notice a lost row reads CORPFLOW_AUDIT_LAST_RC (0 written, 1 not) instead of the
# return code — returning non-zero would abort the `set -e` caller this contract protects.
#
# Flags, not positions: `actor`, `action`, `result` and `subject` are all bare strings, so a
# positional signature lets a transposition emit a valid row that lies — the worst failure an
# audit log has.
#
# `subject` and `task_id` are required and non-empty on both paths below: a row nobody can
# attribute to a task reads as a record while being a gap. A call missing either writes
# nothing and names the key on one stderr line. A caller holding no ledger key passes
# "none" (no stage is active) or "unknown" (one is, but cannot be resolved).
#
# Without jq the row degrades to a minimal form built by printf over values reduced to an
# alphabet that cannot break the literal. Degrading the value beats emitting a line that
# stops every later reader of audit.jsonl at the parse error. `--meta` is dropped on that
# path (an arbitrary JSON literal cannot be made injection-safe without a parser), so a
# caller whose metadata must survive a jq-less host passes it as `--meta-kv key=value`
# pairs instead: those are flat scalars the sanitiser can guarantee.
corpflow_audit_row() {
  local _file="" _actor="" _action="" _result="" _subject="" _meta="" _task_id=""
  local _missing="" _pair _k _v
  local _kv=()
  local _dir _ts _row
  # shellcheck disable=SC2034  # out-parameter; read by callers
  CORPFLOW_AUDIT_LAST_RC=1
  while [ "$#" -gt 0 ]; do
    case "${1:-}" in
      --file) _file="${2:-}" ;;
      --actor) _actor="${2:-}" ;;
      --action) _action="${2:-}" ;;
      --result) _result="${2:-}" ;;
      --subject) _subject="${2:-}" ;;
      --task-id) _task_id="${2:-}" ;;
      --meta) _meta="${2:-}" ;;
      --meta-kv) _kv[${#_kv[@]}]="${2:-}" ;;
      *) shift; continue ;;
    esac
    # Never `shift 2` blind: a flag given with no value would shift past $# and abort a
    # `set -e` caller from inside the appender.
    if [ "$#" -gt 1 ]; then shift 2; else shift; fi
  done

  [ -n "$_file" ] || return 0
  [ -n "$_actor" ] || return 0
  [ -n "$_action" ] || return 0
  [ -n "$_result" ] || return 0

  [ -n "$_subject" ] || _missing="subject"
  [ -n "$_task_id" ] || _missing="${_missing:+$_missing and }task_id"
  if [ -n "$_missing" ]; then
    printf >&2 'corpflow_audit_row: %s row not written, missing %s\n' \
      "${_action//[^A-Za-z0-9_.:-]/_}" "$_missing" || :
    return 0
  fi

  _dir=$(dirname -- "$_file")
  mkdir -p "$_dir" 2> /dev/null || return 0
  # A symlinked audit.jsonl turns this append into a write primitive against an arbitrary
  # target. Refuse rather than follow.
  [ ! -L "$_file" ] || return 0

  _ts=$(date -u +%FT%TZ 2> /dev/null) || _ts="unknown"
  [ -n "$_ts" ] || _ts="unknown"

  if command -v jq > /dev/null 2>&1; then
    [ -n "$_meta" ] || _meta='{}'
    # Malformed metadata degrades rather than dropping the row: losing metadata beats
    # losing the row that says what happened.
    printf '%s' "$_meta" | jq -e . > /dev/null 2>&1 || _meta='{"_meta_invalid":true}'
    for _pair in ${_kv[@]+"${_kv[@]}"}; do
      _k="${_pair%%=*}"
      _v="${_pair#*=}"
      _meta=$(printf '%s' "$_meta" \
        | jq -c --arg k "$_k" --arg v "$_v" '. + {($k): $v}' 2> /dev/null) || _meta='{}'
    done
    # Key order is pinned by construction, not by jq's sort: assert with keys_unsorted.
    _row=$(jq -cn --arg ts "$_ts" --arg actor "$_actor" --arg action "$_action" \
      --arg subject "$_subject" --arg result "$_result" --argjson meta "$_meta" \
      --arg task_id "$_task_id" '
      {ts: $ts, actor: $actor, action: $action, subject: $subject, result: $result,
       task_id: $task_id, metadata: $meta}
    ' 2> /dev/null) || return 0
  else
    _row=$(_corpflow_audit_row_nojq "$_ts" "$_actor" "$_action" "$_result" \
      "$_subject" "$_task_id" ${_kv[@]+"${_kv[@]}"}) || return 0
  fi

  # The `2>/dev/null` on the jq pipeline above silences jq alone; this append is the
  # calling shell's redirection and its failure is invisible to that guard. Capture it
  # explicitly so a caller that must not complete un-audited can see the loss.
  { printf '%s\n' "$_row" >> "$_file"; } 2> /dev/null || return 0
  # shellcheck disable=SC2034  # out-parameter; read by callers
  CORPFLOW_AUDIT_LAST_RC=0
  return 0
}

# The jq-absent row. Every value is reduced to `[A-Za-z0-9_.:/@+-]`, so no quote, backslash
# or newline can reach the literal this printf builds. Trailing arguments are the
# --meta-kv pairs, rendered as a flat metadata object under the same reduction.
_corpflow_audit_row_nojq() {
  local ts="${1//[^A-Za-z0-9_.:\/@+-]/_}" actor="${2//[^A-Za-z0-9_.:\/@+-]/_}"
  local action="${3//[^A-Za-z0-9_.:\/@+-]/_}" result="${4//[^A-Za-z0-9_.:\/@+-]/_}"
  local subject="${5//[^A-Za-z0-9_.:\/@+-]/_}" task_id="${6//[^A-Za-z0-9_.:\/@+-]/_}"
  shift 6
  local head meta="" pair k v
  head=$(printf '{"ts":"%s","actor":"%s","action":"%s","subject":"%s","result":"%s","task_id":"%s"' \
    "$ts" "$actor" "$action" "$subject" "$result" "$task_id")
  for pair in "$@"; do
    k="${pair%%=*}"; k="${k//[^A-Za-z0-9_]/_}"
    v="${pair#*=}"; v="${v//[^A-Za-z0-9_.:\/@+-]/_}"
    meta="$meta${meta:+,}$(printf '"%s":"%s"' "$k" "$v")"
  done
  [ -z "$meta" ] || head="$head$(printf ',"metadata":{%s}' "$meta")"
  printf '%s}' "$head"
}
