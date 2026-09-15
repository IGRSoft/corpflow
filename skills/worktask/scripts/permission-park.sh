#!/usr/bin/env bash
# @description permission-park.sh — the orchestrator side of an auto-mode permission denial:
#   classify a stage's return, park the task without spending a retry, batch every parked need
#   into one user question, and build the step-only resume.
#
#   Grants nothing. A grant is the user's act, in Claude Code's own permission prompt or as a
#   user-run `! <command>`; `resume` only re-dispatches after that answer. No subcommand writes
#   Claude Code configuration, and none emits a retry decision.
#
# Usage:
#   permission-park.sh classify [--payload <json|text>] [--tool <t>] [--command <c>]
#   permission-park.sh park     --task-id <ID> --detail <json> [--state <state.json>]
#   permission-park.sh batch    [--tasks <ID,ID...>] [--boundary <ID>] [--workspace-json <path>]
#                               [--state <state.json>]
#   permission-park.sh resume   --task-id <ID> --answer grant|manual [--state <state.json>]
#   permission-park.sh --self-test
#
# @arg classify  Reads --payload or stdin. A typed handoff `blocked_on` wins; a Claude Code
#                PermissionDenied event is next; classifier-denial text is last, and there the
#                tool and command come from --tool/--command or else the return's first
#                `Tool(command)` line. Prints {tool, command, classifier_reason, allow_rule}.
# @arg park      blocked_on via state-patch.sh --task-meta, then --task-status blocked; appends
#                one deduped permission_denied row (source orchestrator). Prints
#                {blocked_on, dedupe_key, truncated, audit_row_written}.
# @arg batch     Every blocked task whose blocked_on.kind is permission. Interactive: {mode:"ask",
#                needs, payloads:[AskUserQuestion input, <=4 questions each]}. Under a megatask
#                per-issue run: no question; parks the issue (workspace.json execution failed /
#                parked_escalation, one escalation_parked row). Prints {mode:"megatask_park", ...}.
# @arg resume    --claim, clears blocked_on to null, appends one permission_resumed row recording
#                the answer. Prints {resume_block, cleared, audit_row_written}.
#
# @exitcode 0 success; for classify, the payload is a permission denial
# @exitcode 1 classify: not a parkable permission denial; park/resume: ledger write refused or
#             task not parked
# @exitcode 2 usage error, missing ledger, or broken install
#
# Minimum shell: bash 3.2+. Requires jq.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
_PP_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
STATE_PATCH="$SCRIPT_DIR/state-patch.sh"

die() {
  printf >&2 'permission-park: %s\n' "$2"
  exit "$1"
}

usage() {
  sed -n '/^# Usage:/,/^# @arg classify/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
  exit 2
}

if [ "${1:-}" = "--self-test" ]; then
  # shellcheck source=skills/worktask/scripts/permission-park-selftest.sh
  . "$SCRIPT_DIR/permission-park-selftest.sh"
  self_test
  exit $?
fi

command -v jq > /dev/null 2>&1 || die 2 "jq is required"
for _pp_lib in "$_PP_ROOT/hooks/lib/permission-denied-lib.sh" \
  "$_PP_ROOT/skills/shared/lib/audit-lib.sh" \
  "$_PP_ROOT/skills/shared/lib/state-read-lib.sh"; do
  [ -r "$_pp_lib" ] || die 2 "plugin install broken — missing $_pp_lib"
  # shellcheck source=/dev/null
  . "$_pp_lib"
done

SUBCMD="${1:-}"
[ "$#" -gt 0 ] && shift
PAYLOAD_ARG="" PAYLOAD_GIVEN=0 TOOL_ARG="" COMMAND_ARG="" TASK_ARG="" DETAIL_ARG=""
TASKS_ARG="" BOUNDARY_ARG="" WS_JSON_ARG="" ANSWER_ARG="" STATE_PATH=""
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || die 2 "missing value for $1"
  case "$1" in
    --payload) PAYLOAD_ARG="$2" PAYLOAD_GIVEN=1 ;;
    --tool) TOOL_ARG="$2" ;;
    --command) COMMAND_ARG="$2" ;;
    --task-id) TASK_ARG="$2" ;;
    --detail) DETAIL_ARG="$2" ;;
    --tasks) TASKS_ARG="$2" ;;
    --boundary) BOUNDARY_ARG="$2" ;;
    --workspace-json) WS_JSON_ARG="$2" ;;
    --answer) ANSWER_ARG="$2" ;;
    --state) STATE_PATH="$2" ;;
    *) die 2 "unknown flag: $1" ;;
  esac
  shift 2
done

is_task_id() {
  [[ "${1:-}" =~ ^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)[0-9]+$ ]]
}

resolve_state() {
  local ctx rc=0
  if [ -z "$STATE_PATH" ]; then
    ctx=$(corpflow_context_dir) || rc=$?
    [ "$rc" -eq 0 ] || die 2 "no .context/ resolved; pass --state"
    STATE_PATH="$ctx/state.json"
  fi
  [ -f "$STATE_PATH" ] || die 2 "no ledger at $STATE_PATH"
  jq -e 'type == "object"' "$STATE_PATH" > /dev/null 2>&1 || die 2 "unparseable ledger at $STATE_PATH"
  AUDIT="${STATE_PATH%/*}/logs/audit.jsonl"
}

ledger() {
  bash "$STATE_PATCH" --state "$STATE_PATH" "$@" 1>&2
}

# parse_tool_line <text> — sets PP_LINE_TOOL and PP_LINE_CMD from the first line shaped like
# Claude Code's echo of a tool call, `Tool(command)`. An `mcp__*` name counts with or without
# arguments (its names may carry `-`, which the general shape excludes). Returns 1 on no match.
parse_tool_line() {
  local line
  local call_re='^[[:space:]]*([A-Za-z][A-Za-z0-9_]*)\((.*)\)[[:space:]]*$'
  local mcp_re='^[[:space:]]*(mcp__[A-Za-z0-9_-]+)(\((.*)\))?[[:space:]]*$'
  PP_LINE_TOOL="" PP_LINE_CMD=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $mcp_re ]]; then
      PP_LINE_TOOL="${BASH_REMATCH[1]}" PP_LINE_CMD="${BASH_REMATCH[3]}"
      return 0
    fi
    if [[ "$line" =~ $call_re ]]; then
      PP_LINE_TOOL="${BASH_REMATCH[1]}" PP_LINE_CMD="${BASH_REMATCH[2]}"
      return 0
    fi
  done <<< "$1"
  return 1
}

cmd_classify() {
  local payload="$PAYLOAD_ARG" typed detail reason tool cmd
  if [ "$PAYLOAD_GIVEN" -eq 0 ] && [ ! -t 0 ]; then
    payload=$(cat)
  fi
  [ -n "$payload" ] || return 1

  if printf '%s' "$payload" | jq -e 'type == "object"' > /dev/null 2>&1; then
    typed=$(printf '%s' "$payload" | jq -c '
      if has("kind") and has("detail") then .
      elif (.blocked_on | type) == "object" then .blocked_on
      elif (.handoff.blocked_on | type) == "object" then .handoff.blocked_on
      else empty end')
    if [ -n "$typed" ]; then
      # A typed blocked_on of another kind is a real answer, not a miss to re-guess from text.
      [ "$(printf '%s' "$typed" | jq -r '.kind // ""')" = "permission" ] || return 1
      detail=$(pd_normalize_detail "$(printf '%s' "$typed" | jq -c '.detail // {}')")
      [ -n "$detail" ] || return 1
      printf '%s\n' "$detail"
      return 0
    fi
    detail=$(pd_detail_from_event "$payload")
    if [ -n "$detail" ] && printf '%s' "$payload" | jq -e 'has("reason")' > /dev/null 2>&1; then
      printf '%s\n' "$detail"
      return 0
    fi
  fi

  # Free text is the weakest signal: only Claude Code's classifier wording counts, because a
  # user rejecting an ordinary prompt reads alike and must stay a plain blocked return.
  reason=$(printf '%s' "$payload" | grep -Ei -m1 \
    'Blocked by classifier|Auto mode could not evaluate this action|Classifier unavailable|auto[- ]mode classifier' \
    2> /dev/null || true)
  [ -n "$reason" ] || return 1

  tool="$TOOL_ARG" cmd="$COMMAND_ARG"
  if parse_tool_line "$payload"; then
    [ -n "$tool" ] || tool="$PP_LINE_TOOL"
    if [ -z "$cmd" ] && [ "$tool" = "$PP_LINE_TOOL" ]; then cmd="$PP_LINE_CMD"; fi
  fi
  # No tool means no command to show, no allow rule and a key that pairs with nothing: that
  # return stays an ordinary blocked one rather than a park the user cannot act on.
  [ -n "$tool" ] || return 1
  detail=$(pd_normalize_detail "$(jq -cn --arg t "$tool" --arg c "$cmd" --arg r "$reason" \
    '{tool: $t, command: $c, classifier_reason: $r, allow_rule: ""}')")
  [ -n "$detail" ] || return 1
  printf '%s\n' "$detail"
  return 0
}

cmd_park() {
  local detail blocked key tool cmd meta written=false
  is_task_id "$TASK_ARG" || die 2 "park needs --task-id <STAGE><N>"
  [ -n "$DETAIL_ARG" ] || die 2 "park needs --detail <json>"
  resolve_state
  detail=$(pd_normalize_detail "$DETAIL_ARG")
  [ -n "$detail" ] || die 2 "--detail must be a JSON object with a non-empty string tool"
  blocked=$(jq -cn --argjson d "$detail" \
    '{blocked_on: {kind: "permission", detail: $d, resume_with: "decision_ref"}}')

  # Metadata before status: a crash between the two leaves blocked_on on a task that is not
  # blocked, which batch skips because it selects blocked tasks only, instead of a blocked task
  # with no reason attached.
  ledger --task-meta "$TASK_ARG" --set "$blocked" || die 1 "state-patch refused --task-meta $TASK_ARG"
  ledger --task-status "$TASK_ARG" blocked || die 1 "state-patch refused --task-status $TASK_ARG blocked"

  tool=$(printf '%s' "$detail" | jq -r '.tool')
  cmd=$(printf '%s' "$detail" | jq -r '.command')
  key=$(pd_dedupe_key "$TASK_ARG" "$tool" "$cmd")
  if ! pd_audit_has_key "$AUDIT" "$key" && ! pd_audit_has_twin "$AUDIT" "$tool" "$cmd" unknown; then
    meta=$(jq -cn --argjson d "$detail" --arg key "$key" '$d + {source: "orchestrator", dedupe_key: $key}')
    # The kv pairs duplicate --meta so the four keys survive a jq-less host's degraded row.
    corpflow_audit_row --file "$AUDIT" --actor orchestrator --action permission_denied \
      --result block --subject "$TASK_ARG" --meta "$meta" \
      --meta-kv "tool=$tool" --meta-kv "command=$cmd" \
      --meta-kv "classifier_reason=$(printf '%s' "$detail" | jq -r '.classifier_reason')" \
      --meta-kv "allow_rule=$(printf '%s' "$detail" | jq -r '.allow_rule')" \
      --meta-kv "source=orchestrator" --meta-kv "dedupe_key=$key"
    [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ] && written=true
  fi
  jq -cn --argjson b "$blocked" --arg key "$key" --argjson w "$written" "$PD_JQ_DEFS"'
    {blocked_on: $b.blocked_on, dedupe_key: $key,
     truncated: ($b.blocked_on.detail.command | pd_truncated(512)), audit_row_written: $w}'
}

# write_workspace_parked <workspace.json> — merges the PARK execution state; 0 when written.
# The temp file is created exclusively beside the target, so a pre-planted name cannot redirect
# the write, and the rename replaces the path itself rather than anything it points at.
write_workspace_parked() {
  local ws="$1" tmp
  [ -f "$ws" ] && [ ! -L "$ws" ] || return 1
  tmp=$(mktemp "$(dirname -- "$ws")/.workspace.json.XXXXXX" 2> /dev/null) || return 1
  if jq '.execution = ((.execution // {}) + {status: "failed", reason: "parked_escalation"})' \
    "$ws" > "$tmp" 2> /dev/null && [ ! -L "$ws" ] && mv -f -- "$tmp" "$ws"; then
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

cmd_batch() {
  local id needs megatask payloads boundary ws escalated ws_written=false row_written=false
  local ids=()
  if [ -n "$TASKS_ARG" ]; then
    IFS=, read -r -a ids <<< "$TASKS_ARG"
    for id in "${ids[@]}"; do
      is_task_id "$id" || die 2 "invalid task id in --tasks: $id"
    done
  fi
  resolve_state
  needs=$(jq -c --arg ids "$TASKS_ARG" "$PD_JQ_DEFS"'
    ($ids | if . == "" then null else split(",") end) as $want
    | [(.tasks // {}) | to_entries[]
       | select($want == null or (.key as $k | $want | index($k)) != null)
       | select(.value.status == "blocked"
           and (.value.metadata.blocked_on.kind? // "") == "permission")
       | (.value.metadata.blocked_on.detail // {}) as $d
       | {task_id: .key} + pd_detail($d.tool; $d.command; $d.classifier_reason; $d.allow_rule)
       | . + {truncated: (.command | pd_truncated(512))}]' \
    "$STATE_PATH")
  megatask=$(jq -r '(.tasks["PL\(.run_index // 0)"].metadata.megatask_group // "") | tostring' "$STATE_PATH")

  if [ -z "$megatask" ]; then
    # Every untrusted field sits inside a fenced block one backtick longer than its longest
    # backtick run, so no command text can close the fence or render as markup. Labels are
    # fixed strings. A truncated command is never offered as a `!` line: pasted, it would run
    # something other than what was denied.
    payloads=$(printf '%s' "$needs" | jq -c "$PD_JQ_DEFS"'
      map({
        header: (.task_id | .[0:12]),
        question: ("\(.task_id) was denied a tool call by the auto-mode classifier. How should it continue?\n\n"
          + ("tool: \(.tool)\ncommand: \(.command)\nreason: \(.classifier_reason)" | pd_fence)
          + (if .truncated
             then "\n\nThe command was truncated to 512 characters, so it is not offered as a line to run. Read the full command in the Claude Code denial notice or under /permissions recent denials."
             else "\n\nTo run it yourself, enter:\n\n" + ("! \(.command)" | pd_fence) end)),
        multiSelect: false,
        options: [
          {label: "grant and continue",
           description: "Grant it in the Claude Code permission prompt; only the denied step runs again."},
          {label: "run it yourself",
           description: (if .truncated
             then "Run the full command from the denial notice; the step then continues without running it again."
             else "Run the ! line shown above; the step then continues without running it again." end)}
        ]})
      | [range(0; length; 4) as $i | {questions: .[$i:($i + 4)]}]')
    jq -cn --argjson n "$needs" --argjson p "$payloads" '{mode: "ask", needs: $n, payloads: $p}'
    return 0
  fi

  if [ "$(printf '%s' "$needs" | jq 'length')" -eq 0 ]; then
    jq -cn '{mode: "megatask_park", needs: [], payloads: [], park: null}'
    return 0
  fi
  boundary="$BOUNDARY_ARG"
  [ -n "$boundary" ] || boundary=$(printf '%s' "$needs" | jq -r '.[0].task_id')
  is_task_id "$boundary" || die 2 "invalid --boundary: $boundary"
  escalated=$(printf '%s' "$needs" | jq -c 'map({tool, command, allow_rule})')

  ws="$WS_JSON_ARG"
  [ -n "$ws" ] || ws="$(dirname -- "${STATE_PATH%/*}")/workspace.json"
  write_workspace_parked "$ws" && ws_written=true

  if ! jq -nRe --arg b "$boundary" --argjson e "$escalated" '
      [inputs | fromjson? | select(type == "object" and .action == "escalation_parked"
        and .subject == $b and .metadata.escalated == $e)] | length > 0' \
    "$AUDIT" > /dev/null 2>&1; then
    corpflow_audit_row --file "$AUDIT" --actor orchestrator --action escalation_parked \
      --result block --subject "$boundary" \
      --meta "$(jq -cn --argjson e "$escalated" '{escalated: $e, reason: "parked_escalation", kind: "permission"}')"
    [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ] && row_written=true
  fi

  jq -cn --argjson n "$needs" --arg b "$boundary" --argjson e "$escalated" \
    --argjson ww "$ws_written" --argjson rw "$row_written" '
    {mode: "megatask_park", needs: $n, payloads: [],
     park: {boundary: $b, execution: {status: "failed", reason: "parked_escalation"},
            escalated: $e, workspace_written: $ww, audit_row_written: $rw}}'
}

cmd_resume() {
  local blocked detail tool cmd key seq ref written=false
  is_task_id "$TASK_ARG" || die 2 "resume needs --task-id <STAGE><N>"
  case "$ANSWER_ARG" in grant | manual) : ;; *) die 2 "resume needs --answer grant|manual" ;; esac
  resolve_state
  blocked=$(jq -c --arg id "$TASK_ARG" '.tasks[$id].metadata.blocked_on // null' "$STATE_PATH")
  [ "$(printf '%s' "$blocked" | jq -r '.kind? // ""')" = "permission" ] \
    || die 1 "tasks.$TASK_ARG is not parked for a permission"
  detail=$(pd_normalize_detail "$(printf '%s' "$blocked" | jq -c '.detail // {}')")
  [ -n "$detail" ] || die 1 "tasks.$TASK_ARG blocked_on carries no usable detail"

  ledger --claim "$TASK_ARG" || die 1 "state-patch refused --claim $TASK_ARG"
  # `null`, not deletion: --task-meta is a recursive merge and has no unset, so a cleared
  # park reads as blocked_on == null.
  ledger --task-meta "$TASK_ARG" --set '{"blocked_on":null}' || die 1 "state-patch refused clearing blocked_on on $TASK_ARG"

  # The row is what blocked_on.resume_with: decision_ref points at. The sequence number keeps
  # the ref unique when the same call is denied, parked and resumed again in one task.
  tool=$(printf '%s' "$detail" | jq -r '.tool')
  cmd=$(printf '%s' "$detail" | jq -r '.command')
  key=$(pd_dedupe_key "$TASK_ARG" "$tool" "$cmd")
  seq=0
  if [ -f "$AUDIT" ]; then
    seq=$(grep -F '"action":"permission_resumed"' -- "$AUDIT" 2> /dev/null \
      | grep -F "\"subject\":\"$TASK_ARG\"" 2> /dev/null | grep -Fc "\"dedupe_key\":\"$key\"" 2> /dev/null) || seq=0
  fi
  ref="permission_resumed:$TASK_ARG:$key:$((seq + 1))"
  corpflow_audit_row --file "$AUDIT" --actor orchestrator --action permission_resumed \
    --result ok --subject "$TASK_ARG" \
    --meta "$(jq -cn --arg a "$ANSWER_ARG" --arg k "$key" --arg t "$tool" --arg c "$cmd" --arg r "$ref" \
      '{answer: $a, dedupe_key: $k, tool: $t, command: $c, decision_ref: $r}')" \
    --meta-kv "answer=$ANSWER_ARG" --meta-kv "dedupe_key=$key" --meta-kv "tool=$tool" \
    --meta-kv "command=$cmd" --meta-kv "decision_ref=$ref"
  [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ] && written=true

  # Built by concatenation, never sub(): the command is data, and a regex replacement would
  # read any `\` or `&` inside it as syntax. It sits in a fence for the same reason as batch.
  printf '%s' "$detail" | jq -c --arg id "$TASK_ARG" --arg a "$ANSWER_ARG" --arg ref "$ref" \
    --argjson w "$written" "$PD_JQ_DEFS"'
    . as $d
    | ($d.command | pd_truncated(512)) as $cut
    | (if $a == "grant"
       then "Resume only the step that was denied: the user has granted the call below, so make it again."
       else "The user ran the denied call below themselves. Verify its effect and continue after that step without running it again." end)
      as $head
    | (if $cut and $a == "grant"
       then " The recorded command was truncated, so run the step'"'"'s own command, not this text."
       elif $cut then " The recorded command was truncated and is context only."
       else "" end) as $note
    | {resume_block: {task_id: $id, tool: $d.tool, command: $d.command, answer: $a,
         truncated: $cut, do_not_rerun: true, decision_ref: $ref,
         instruction: ($head + $note + "\n\n"
           + ("tool: \($d.tool)\ncommand: \($d.command)" | pd_fence)
           + "\n\nDo not re-run any step that already completed.")},
       cleared: true, audit_row_written: $w}'
}

case "$SUBCMD" in
  classify) cmd_classify ;;
  park) cmd_park ;;
  batch) cmd_batch ;;
  resume) cmd_resume ;;
  -h | --help | "") usage ;;
  *) die 2 "unknown subcommand: $SUBCMD" ;;
esac
