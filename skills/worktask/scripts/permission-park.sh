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
#                tool and command come from --tool/--command or else the last `Tool(command)`
#                line at or before the classifier-denial line. Prints {tool, command,
#                classifier_reason, allow_rule}.
# @arg park      blocked_on via state-patch.sh --task-meta, then --task-status blocked; appends
#                one deduped permission_denied row with the redacted metadata {tool, dedupe_key,
#                command_head, truncated}. Prints {blocked_on, dedupe_key, truncated,
#                audit_row_written}.
# @arg batch     Every blocked task whose blocked_on.kind is permission; each need carries the
#                ledger's workspace_path as cwd. Interactive: {mode:"ask", needs, payloads:
#                [AskUserQuestion input, <=4 questions each]}. Under a megatask per-issue run: no
#                question; parks the issue (workspace.json execution failed / parked_escalation,
#                one escalation_parked row whose escalated[] is {tool, command_head, truncated}).
#                A symlinked workspace.json is refused: workspace_written false, workspace_reason
#                "symlink". Prints {mode:"megatask_park", ...}.
# @arg resume    --claim, clears blocked_on to null, appends one permission_resumed row recording
#                the answer under the same redacted metadata. Prints {resume_block, cleared,
#                audit_row_written}.
#
# @exitcode 0 success; for classify, the payload is a permission denial
# @exitcode 1 classify: not a parkable permission denial; park/resume: ledger write refused or
#             task not parked
# @exitcode 2 usage error, missing ledger, broken install, or (park/resume) a non-empty command
#             that cannot be masked for its dedupe key; the ledger is left untouched
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

# parse_tool_line <text> <last_line> — sets PP_LINE_TOOL and PP_LINE_CMD from the LAST line at
# or before line <last_line> shaped like Claude Code's echo of a tool call, `Tool(command)`. The
# denied call is the one echoed nearest above the classifier's wording: an earlier line is a call
# that already ran, and a later one never reached the classifier, so either would park, show and
# re-run the wrong command. An `mcp__*` name counts with or without arguments (its names may
# carry `-`, which the general shape excludes). Returns 1 on no match.
parse_tool_line() {
  local line n=0 max="${2:-0}"
  local call_re='^[[:space:]]*([A-Za-z][A-Za-z0-9_]*)\((.*)\)[[:space:]]*$'
  local mcp_re='^[[:space:]]*(mcp__[A-Za-z0-9_-]+)(\((.*)\))?[[:space:]]*$'
  PP_LINE_TOOL="" PP_LINE_CMD=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ "$n" -le "$max" ] || break
    if [[ "$line" =~ $mcp_re ]]; then
      PP_LINE_TOOL="${BASH_REMATCH[1]}" PP_LINE_CMD="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ $call_re ]]; then
      PP_LINE_TOOL="${BASH_REMATCH[1]}" PP_LINE_CMD="${BASH_REMATCH[2]}"
    fi
  done <<< "$1"
  [ -n "$PP_LINE_TOOL" ]
}

cmd_classify() {
  local payload="$PAYLOAD_ARG" typed detail hit reason tool cmd
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
  hit=$(printf '%s' "$payload" | grep -n -Ei -m1 \
    'Blocked by classifier|Auto mode could not evaluate this action|Classifier unavailable|auto[- ]mode classifier' \
    2> /dev/null || true)
  [ -n "$hit" ] || return 1
  reason="${hit#*:}"

  tool="$TOOL_ARG" cmd="$COMMAND_ARG"
  if parse_tool_line "$payload" "${hit%%:*}"; then
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
  local detail blocked key tool cmd kcmd meta written=false
  is_task_id "$TASK_ARG" || die 2 "park needs --task-id <STAGE><N>"
  [ -n "$DETAIL_ARG" ] || die 2 "park needs --detail <json>"
  resolve_state
  detail=$(pd_normalize_detail "$DETAIL_ARG")
  [ -n "$detail" ] || die 2 "--detail must be a JSON object with a non-empty string tool"
  tool=$(printf '%s' "$detail" | jq -r '.tool')
  cmd=$(printf '%s' "$detail" | jq -r '.command')
  # Before any ledger write: a command that cannot be masked leaves the task untouched rather
  # than parked with no row, and its key is never taken over the unmasked text.
  kcmd=$(pd_key_command "$cmd")
  [ -n "$kcmd" ] || [ -z "$cmd" ] || die 2 "cannot mask the denied command for its dedupe key"
  blocked=$(jq -cn --argjson d "$detail" \
    '{blocked_on: {kind: "permission", detail: $d, resume_with: "decision_ref"}}')

  # Metadata before status: a crash between the two leaves blocked_on on a task that is not
  # blocked, which batch skips because it selects blocked tasks only, instead of a blocked task
  # with no reason attached.
  # --log /dev/null: state-patch logs every --set value verbatim to .context/logs/state-merge.log,
  # and this one alone carries the unmasked denied command.
  ledger --log /dev/null --task-meta "$TASK_ARG" --set "$blocked" || die 1 "state-patch refused --task-meta $TASK_ARG"
  ledger --task-status "$TASK_ARG" blocked || die 1 "state-patch refused --task-status $TASK_ARG blocked"

  key=$(pd_dedupe_key "$TASK_ARG" "$tool" "$kcmd")
  # A hook row whose subject never resolved keys on "unknown", so that key is re-derived too.
  if ! pd_audit_has_key "$AUDIT" "$key" && ! pd_audit_has_twin "$AUDIT" "$tool" "$kcmd" unknown; then
    meta=$(pd_audit_meta "$tool" "$cmd" "$key")
    # The kv pairs keep a degraded row pairable by key; none carries command text.
    corpflow_audit_row --file "$AUDIT" --actor orchestrator --action permission_denied \
      --result block --subject "$TASK_ARG" --task-id "$TASK_ARG" --meta "$meta" \
      --meta-kv "tool=$tool" --meta-kv "dedupe_key=$key"
    [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ] && written=true
  fi
  jq -cn --argjson b "$blocked" --arg key "$key" --argjson w "$written" "$PD_JQ_DEFS"'
    {blocked_on: $b.blocked_on, dedupe_key: $key,
     truncated: ($b.blocked_on.detail.command | pd_truncated(512)), audit_row_written: $w}'
}

# write_workspace_parked <workspace.json> — merges the PARK execution state; 0 when written,
# else 1 with WS_REASON naming why (symlink, missing, not_regular_file, unreadable, malformed,
# write_failed). A symlink is refused, never read, merged or replaced: whoever planted it chose
# the target. The file is read once and the link check repeats after the read and before the
# rename, so a link swapped in mid-write costs a refusal rather than a write through it. The
# temp file is created exclusively beside the target and the rename replaces the path itself.
write_workspace_parked() {
  local ws="$1" tmp body
  WS_REASON=""
  if [ -L "$ws" ]; then
    WS_REASON="symlink"
    return 1
  fi
  [ -e "$ws" ] || { WS_REASON="missing"; return 1; }
  [ -f "$ws" ] || { WS_REASON="not_regular_file"; return 1; }
  body=$(cat -- "$ws" 2> /dev/null) || { WS_REASON="unreadable"; return 1; }
  [ ! -L "$ws" ] || { WS_REASON="symlink"; return 1; }
  body=$(printf '%s' "$body" \
    | jq '.execution = ((.execution // {}) + {status: "failed", reason: "parked_escalation"})' 2> /dev/null) \
    || { WS_REASON="malformed"; return 1; }
  tmp=$(mktemp "$(dirname -- "$ws")/.workspace.json.XXXXXX" 2> /dev/null) || { WS_REASON="write_failed"; return 1; }
  if printf '%s\n' "$body" > "$tmp" && [ ! -L "$ws" ] && mv -f -- "$tmp" "$ws"; then
    return 0
  fi
  rm -f -- "$tmp"
  if [ -L "$ws" ]; then WS_REASON="symlink"; else WS_REASON="write_failed"; fi
  return 1
}

cmd_batch() {
  local id needs megatask payloads boundary ws escalated need ws_written=false row_written=false
  local ids=()
  if [ -n "$TASKS_ARG" ]; then
    IFS=, read -r -a ids <<< "$TASKS_ARG"
    for id in "${ids[@]}"; do
      is_task_id "$id" || die 2 "invalid task id in --tasks: $id"
    done
  fi
  resolve_state
  # cwd is the stage's tree from the ledger, never from blocked_on: the four-key detail is the
  # stage's own report, and the directory a user runs a command in must not be its to choose.
  needs=$(jq -c --arg ids "$TASKS_ARG" "$PD_JQ_DEFS"'
    . as $s
    | ($ids | if . == "" then null else split(",") end) as $want
    | [(.tasks // {}) | to_entries[]
       | select($want == null or (.key as $k | $want | index($k)) != null)
       | select(.value.status == "blocked"
           and (.value.metadata.blocked_on.kind? // "") == "permission")
       | (.value.metadata.blocked_on.detail // {}) as $d
       | ((.value.metadata.workspace_path? // $s.metadata.workspace_path? // "") | pd_bound(600)) as $cwd
       | {task_id: .key} + pd_detail($d.tool; $d.command; $d.classifier_reason; $d.allow_rule)
       | . + {truncated: (.command | pd_truncated(512)), cwd: $cwd}]' \
    "$STATE_PATH")
  megatask=$(jq -r '(.tasks["PL\(.run_index // 0)"].metadata.megatask_group // "") | tostring' "$STATE_PATH")

  if [ -z "$megatask" ]; then
    # Every untrusted field sits inside a fenced block one backtick longer than its longest
    # backtick run, so no command text can close the fence or render as markup. Labels are
    # fixed strings. A truncated command is never offered as a `!` line: pasted, it would run
    # something other than what was denied. The stage's directory is a `cwd:` data line inside
    # the same fence and is never spliced into the `!` line: a `! ` line runs in the main
    # session's directory, and composing `cd <dir> && …` would build shell text from ledger data.
    payloads=$(printf '%s' "$needs" | jq -c "$PD_JQ_DEFS"'
      map((.cwd != "") as $has_cwd | {
        header: (.task_id | .[0:12]),
        question: ("\(.task_id) was denied a tool call by the auto-mode classifier. How should it continue?\n\n"
          + ("tool: \(.tool)\ncommand: \(.command)\nreason: \(.classifier_reason)"
             + (if $has_cwd then "\ncwd: \(.cwd)" else "" end) | pd_fence)
          + (if .truncated
             then "\n\nThe command was truncated to 512 characters, so it is not offered as a line to run. Read the full command in the Claude Code denial notice or under /permissions recent denials."
               + (if $has_cwd then " Run it from that directory (the cwd line above)." else "" end)
             elif $has_cwd
             then "\n\nTo run it yourself, run it from that directory (the cwd line above) and enter:\n\n" + ("! \(.command)" | pd_fence)
             else "\n\nTo run it yourself, enter:\n\n" + ("! \(.command)" | pd_fence) end)),
        multiSelect: false,
        options: [
          {label: "grant and continue",
           description: "Grant it in the Claude Code permission prompt; only the denied step runs again."},
          {label: "run it yourself",
           description: (if .truncated
             then "Run the full command from the denial notice; the step then continues without running it again."
             elif $has_cwd
             then "Run the ! line shown above from the cwd shown there; the step then continues without running it again."
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
  boundary_task="$boundary"
  is_task_id "$boundary_task" || boundary_task="unknown"
  is_task_id "$boundary" || die 2 "invalid --boundary: $boundary"
  # The row names each need by tool and redacted head only; the full detail stays in blocked_on.
  escalated="[]"
  while IFS= read -r need; do
    [ -n "$need" ] || continue
    escalated=$(jq -cn --argjson e "$escalated" --arg t "$(printf '%s' "$need" | jq -r '.tool')" \
      --argjson h "$(pd_command_head "$(printf '%s' "$need" | jq -r '.command')")" '$e + [{tool: $t} + $h]')
  done <<< "$(printf '%s' "$needs" | jq -c '.[]')"

  ws="$WS_JSON_ARG"
  [ -n "$ws" ] || ws="$(dirname -- "${STATE_PATH%/*}")/workspace.json"
  WS_REASON=""
  write_workspace_parked "$ws" && ws_written=true

  if ! jq -nRe --arg b "$boundary" --argjson e "$escalated" '
      [inputs | fromjson? | select(type == "object" and .action == "escalation_parked"
        and .subject == $b and .metadata.escalated == $e)] | length > 0' \
    "$AUDIT" > /dev/null 2>&1; then
    corpflow_audit_row --file "$AUDIT" --actor orchestrator --action escalation_parked \
      --result block --subject "$boundary" --task-id "$boundary_task" \
      --meta "$(jq -cn --argjson e "$escalated" '{escalated: $e, reason: "parked_escalation", kind: "permission"}')"
    [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ] && row_written=true
  fi

  jq -cn --argjson n "$needs" --arg b "$boundary" --argjson e "$escalated" \
    --argjson ww "$ws_written" --arg wr "$WS_REASON" --argjson rw "$row_written" '
    {mode: "megatask_park", needs: $n, payloads: [],
     park: {boundary: $b, execution: {status: "failed", reason: "parked_escalation"},
            escalated: $e, workspace_written: $ww,
            workspace_reason: (if $ww then null else $wr end), audit_row_written: $rw}}'
}

cmd_resume() {
  local blocked detail tool cmd kcmd key seq ref meta written=false
  is_task_id "$TASK_ARG" || die 2 "resume needs --task-id <STAGE><N>"
  case "$ANSWER_ARG" in grant | manual) : ;; *) die 2 "resume needs --answer grant|manual" ;; esac
  resolve_state
  blocked=$(jq -c --arg id "$TASK_ARG" '.tasks[$id].metadata.blocked_on // null' "$STATE_PATH")
  [ "$(printf '%s' "$blocked" | jq -r '.kind? // ""')" = "permission" ] \
    || die 1 "tasks.$TASK_ARG is not parked for a permission"
  detail=$(pd_normalize_detail "$(printf '%s' "$blocked" | jq -c '.detail // {}')")
  [ -n "$detail" ] || die 1 "tasks.$TASK_ARG blocked_on carries no usable detail"
  tool=$(printf '%s' "$detail" | jq -r '.tool')
  cmd=$(printf '%s' "$detail" | jq -r '.command')
  # Before --claim, for the same reason as park: an unmaskable command leaves the task parked.
  kcmd=$(pd_key_command "$cmd")
  [ -n "$kcmd" ] || [ -z "$cmd" ] || die 2 "cannot mask the denied command for its dedupe key"

  ledger --claim "$TASK_ARG" || die 1 "state-patch refused --claim $TASK_ARG"
  # `null`, not deletion: --task-meta is a recursive merge and has no unset, so a cleared
  # park reads as blocked_on == null.
  ledger --task-meta "$TASK_ARG" --set '{"blocked_on":null}' || die 1 "state-patch refused clearing blocked_on on $TASK_ARG"

  # The row is what blocked_on.resume_with: decision_ref points at. The sequence number keeps
  # the ref unique when the same call is denied, parked and resumed again in one task.
  key=$(pd_dedupe_key "$TASK_ARG" "$tool" "$kcmd")
  seq=0
  if [ -f "$AUDIT" ]; then
    seq=$(grep -F '"action":"permission_resumed"' -- "$AUDIT" 2> /dev/null \
      | grep -F "\"subject\":\"$TASK_ARG\"" 2> /dev/null | grep -Fc "\"dedupe_key\":\"$key\"" 2> /dev/null) || seq=0
  fi
  ref="permission_resumed:$TASK_ARG:$key:$((seq + 1))"
  meta=$(pd_audit_meta "$tool" "$cmd" "$key")
  [ -n "$meta" ] || meta='{}'
  corpflow_audit_row --file "$AUDIT" --actor orchestrator --action permission_resumed \
    --result ok --subject "$TASK_ARG" --task-id "$TASK_ARG" \
    --meta "$(jq -cn --argjson m "$meta" --arg a "$ANSWER_ARG" --arg r "$ref" \
      '$m + {answer: $a, decision_ref: $r}')" \
    --meta-kv "tool=$tool" --meta-kv "dedupe_key=$key" \
    --meta-kv "answer=$ANSWER_ARG" --meta-kv "decision_ref=$ref"
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
