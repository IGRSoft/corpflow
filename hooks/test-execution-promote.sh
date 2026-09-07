#!/usr/bin/env bash
# test-execution-promote — PostToolUse companion of hooks/test-execution-gate.sh.
#
# Registered on PostToolUseFailure as well: a non-zero runner exit is delivered
# as an error tool result, which fires that event INSTEAD of PostToolUse, so a
# PostToolUse-only registration would leave every failing run unrecorded.
#
# The gate is a PreToolUse hook, so it fires before any result exists: recording
# a run's fingerprint there let an invocation that aborted having executed
# nothing claim that fingerprint permanently, and every later attempt against the
# same tree was denied on the strength of a run that produced no evidence. The
# gate now writes only a `.pending` marker; this hook promotes it to a real
# sentinel once the tool actually produced a result, and deletes it otherwise.
#
# It computes NOTHING of its own: the gate is sourced with --lib-only so the
# classifier, the invocation derivation and the key are the same definitions the
# gate itself used. Two independent derivations would orphan every marker and
# disable suppression silently — the failure this design exists to prevent.
#
# Exits 0 always and emits no decision. A PostToolUse hook cannot un-run the
# tool, and a promotion failure only means the next identical run is allowed.
set -u
set -f

_GATE="$(dirname "$0")/test-execution-gate.sh"
_CF_OPTS=$-
set +e
# shellcheck source=hooks/test-execution-gate.sh
[ -f "$_GATE" ] && . "$_GATE" --lib-only
case "$_CF_OPTS" in *e*) set -e ;; esac
command -v gate_classify_payload > /dev/null 2>&1 || exit 0
command -v dedupe_pending_key > /dev/null 2>&1 || exit 0

# tool_produced_result <payload> -> 0 when the call returned something usable.
#
# The narrowest observable that separates a real run from an abort. On
# PostToolUse that is `tool_response`: present and non-empty, with no error flag.
#
# A FAILING call carries no `tool_response` at all — the failure arrives as a
# top-level `error` string — so keying on it there would discard every red suite
# and suppress only green ones, inverting the point: a red suite that printed its
# failures IS a run, and its identical repeat is exactly what must be suppressed.
# On that event the error text therefore counts as output.
#
# The accepted cost: a 1.0s abort carrying only error text now promotes and holds
# the tree until the next edit. It is the cheaper half of the trade, because the
# alternative disables suppression for every rerun of a failing suite.
# `is_interrupt` is the one failure kept inert — a cancelled call produced no
# evidence at all.
#
# Unresolvable shapes fall through to a discard, the allow direction. Honest
# limit — a runner that exits 0 having executed 0 tests still promotes; that is
# beyond a hook's reach and belongs to QA's evidence check.
tool_produced_result() {
  printf '%s' "$1" | jq -e '
    (.tool_response // null) as $r
    | ((.error // "") | if type == "string" then . else "" end) as $errtext
    | (if ($r | type) == "object" then (($r.error? // false) or ($r.is_error? // false))
       else false end) as $rflag
    | (if $r == null then false
       elif ($r | type) as $t | $t == "string" or $t == "array" or $t == "object"
       then ($r | length) > 0
       else true end) as $rhas
    | ((.is_interrupt // false)
       or (if ($r | type) == "object" then ($r.is_interrupt? // false) else false end))
      as $interrupted
    | ((.hook_event_name // "") == "PostToolUseFailure"
       or ($r == null and ($errtext | length) > 0)) as $failed
    | ($interrupted | not)
      and ($rflag | not)
      and ($rhas or ($failed and ($errtext | length) > 0))
  ' > /dev/null 2>&1
}

run_promote() {
  local _payload="$1" _ctx="$2" _tool _ident _class _cmd_head _inv _n _pkey

  [ "${CORPFLOW_TEST_DEDUPE:-}" = "off" ] && return 0
  [ "${CORPFLOW_TEST_GATE:-}" = "off" ] && return 0
  command -v jq > /dev/null 2>&1 || return 0

  _tool=$(printf '%s' "$_payload" | jq -r '.tool_name // empty' 2> /dev/null)
  [ -n "$_tool" ] || return 0

  _ident="$(gate_classify_payload "$_payload" "$_tool")" || return 0
  _class="${_ident%%$'\t'*}"
  _cmd_head="${_ident#*$'\t'}"
  # Only an executing class can have left a marker, so everything else is a
  # cheap exit rather than a filesystem probe.
  case "$_class" in
    full_test_run|scoped_test_run) ;;
    *) return 0 ;;
  esac

  # The tree is deliberately NOT consulted here: the run itself may have written
  # un-ignored artifacts, so a fingerprint taken now names a marker the gate
  # never wrote. The gate's pre-run key travels inside the marker instead.
  _n=$(run_index_of "$_ctx")
  [ -n "$_n" ] || return 0
  _inv="$(dedupe_invocation "$_payload" "$_tool" "$_cmd_head")"
  _pkey=$(dedupe_pending_key "$_class" "$_inv" "$_n")
  [ -n "$_pkey" ] || return 0

  if tool_produced_result "$_payload"; then
    dedupe_promote "$_ctx" "$_pkey"
  else
    dedupe_discard "$_ctx" "$_pkey"
  fi
  return 0
}

# Sourced by its own bats suite, which calls run_promote directly against a
# fixture ctx; the dispatch below runs only when this file is the entry point.
# shellcheck disable=SC2317 # `return` outside a function fails when executed directly, so the exit IS reached
case "${1:-}" in
  --lib-only) return 0 2>/dev/null || exit 0 ;;
esac

IFS= read -r -d '' PAYLOAD || true
[ -n "${PAYLOAD:-}" ] || exit 0

run_promote "$PAYLOAD" "${CLAUDE_PROJECT_DIR:-.}/.context"
exit 0
