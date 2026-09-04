#!/usr/bin/env bash
# @description audit-lib.sh — the one `.context/logs/audit.jsonl` appender for the skills
#   tree. One writer, one key order, one symlink refusal.
#
#   NOT MIRRORED into hooks/lib/. The hook tree already has exactly one appender
#   (hooks/model-switch-lib.sh corpflow_audit_row) that every hook emitter binds its actor
#   onto; a second same-purpose symbol there would be the duplication this file exists to
#   remove, and the name would collide in any hook that sourced both.
#
#   Symbols: corpflow_audit_row.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement.
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
#                    [--subject <s>] [--meta <compact-json>]
#
# Appends exactly one row and always returns 0: an audit row is evidence, never a gate, so
# no failure here may abort the caller that is mid-way through a real action.
#
# Flags, not positions: `actor`, `action`, `result` and `subject` are all bare strings, so a
# positional signature lets a transposition emit a VALID ROW THAT LIES — the worst failure an
# audit log has. Same reasoning as hooks/model-switch-lib.sh.
#
# `subject` is emitted only when --subject was passed, so a caller with no subject produces
# no `subject` key rather than an empty one that reads as "blank" instead of "absent".
#
# Without jq the row degrades to a minimal form with no `metadata` key, built by printf over
# values reduced to an alphabet that cannot break the literal. Degrading the value beats
# emitting a line that stops every later reader of audit.jsonl at the parse error.
corpflow_audit_row() {
  local _file="" _actor="" _action="" _result="" _subject="" _meta="" _has_subject=0
  local _dir _ts _row
  while [ "$#" -gt 0 ]; do
    case "${1:-}" in
      --file) _file="${2:-}" ;;
      --actor) _actor="${2:-}" ;;
      --action) _action="${2:-}" ;;
      --result) _result="${2:-}" ;;
      --subject) _subject="${2:-}"; _has_subject=1 ;;
      --meta) _meta="${2:-}" ;;
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

  _dir=$(dirname -- "$_file")
  mkdir -p "$_dir" 2> /dev/null || return 0
  # A symlinked audit.jsonl turns this append into a write primitive against an arbitrary
  # target. Refuse rather than follow — the guard hooks/model-switch-lib.sh carries and
  # tests/shell/hooks/test-execution-gate.bats pins for the hook side.
  [ ! -L "$_file" ] || return 0

  _ts=$(date -u +%FT%TZ 2> /dev/null) || _ts="unknown"
  [ -n "$_ts" ] || _ts="unknown"

  if command -v jq > /dev/null 2>&1; then
    [ -n "$_meta" ] || _meta='{}'
    # Malformed metadata degrades rather than dropping the row: losing metadata beats
    # losing the row that says what happened.
    printf '%s' "$_meta" | jq -e . > /dev/null 2>&1 || _meta='{"_meta_invalid":true}'
    # Key order is pinned by construction, not by jq's sort: assert with keys_unsorted.
    _row=$(jq -cn --arg ts "$_ts" --arg actor "$_actor" --arg action "$_action" \
      --arg subject "$_subject" --arg result "$_result" --argjson meta "$_meta" \
      --argjson has_subject "$_has_subject" '
      {ts: $ts, actor: $actor, action: $action}
      + (if $has_subject == 1 then {subject: $subject} else {} end)
      + {result: $result, metadata: $meta}
    ' 2> /dev/null) || return 0
  else
    _row=$(_corpflow_audit_row_nojq "$_ts" "$_actor" "$_action" "$_result" \
      "$_has_subject" "$_subject") || return 0
  fi

  { printf '%s\n' "$_row" >> "$_file"; } 2> /dev/null || return 0
  return 0
}

# The jq-absent row. Every value is reduced to `[A-Za-z0-9_.:/@+-]`, so no quote, backslash
# or newline can reach the literal this printf builds.
_corpflow_audit_row_nojq() {
  local ts="${1//[^A-Za-z0-9_.:\/@+-]/_}" actor="${2//[^A-Za-z0-9_.:\/@+-]/_}"
  local action="${3//[^A-Za-z0-9_.:\/@+-]/_}" result="${4//[^A-Za-z0-9_.:\/@+-]/_}"
  local has_subject="$5" subject="${6//[^A-Za-z0-9_.:\/@+-]/_}"
  if [ "$has_subject" = "1" ]; then
    printf '{"ts":"%s","actor":"%s","action":"%s","subject":"%s","result":"%s"}' \
      "$ts" "$actor" "$action" "$subject" "$result"
  else
    printf '{"ts":"%s","actor":"%s","action":"%s","result":"%s"}' \
      "$ts" "$actor" "$action" "$result"
  fi
}
