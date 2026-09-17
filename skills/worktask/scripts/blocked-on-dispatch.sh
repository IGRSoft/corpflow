#!/usr/bin/env bash
# @description blocked-on-dispatch.sh — the orchestrator side of a typed `handoff.blocked_on`
#   return: route it to its arm or its user_action fallback, batch the parked needs into one
#   user question, and build the resume. The arm table lives in blocked-on-lib.sh, so no
#   orchestrator branch picks an arm by hand (SKILL.md § Step 6.5a3).
#
#   The permission arm writes nothing here: permission-park.sh parks it (§ Step 6.5a4), and its
#   denied/granted/resumed legs are that script's permission_denied and permission_resumed rows.
#   No subcommand runs a need's command, grants a permission or answers for the user.
#
# Usage:
#   blocked-on-dispatch.sh route  --task-id <ID> --payload <handoff json> [--state <state.json>]
#   blocked-on-dispatch.sh batch  [--tasks <ID,ID...>] [--boundary <ID>] [--workspace-json <path>]
#                                 [--state <state.json>]
#   blocked-on-dispatch.sh resume --task-id <ID> --leg <leg> [--state <state.json>]
#   blocked-on-dispatch.sh --self-test
#
# @arg route   Normalizes (legacy cross_session_ask becomes peer_session) and validates the
#              need against its arm. permission: writes nothing. host_environment: parks,
#              re-probes the check with autonomy-preflight.sh in check mode and writes `probed`;
#              a pass clears it and prints resume_block, anything else parks it as a user_action.
#              Every other kind parks as a user_action (fallback_from/owner_issue for a pending
#              arm) and writes `requested`. Prints one JSON line {task_id, kind, arm, leg, source,
#              parked, audit_row_written, [fallback_from, owner_issue], [decision_ref, resume_block]}.
# @arg batch   Every blocked task whose blocked_on.kind is not permission. Interactive:
#              {mode:"ask", needs, payloads:[{questions:[<=4]}]}. Under a megatask per-issue run:
#              no question; parks the issue like permission-park.sh batch, with one
#              escalation_parked row whose escalated[] is {kind, [command_head, truncated]}.
# @arg resume  --claim, blocked_on set to null, one closing-leg row carrying decision_ref
#              blocked_on:<task_id>:<kind>:<n>. Prints {resume_block, cleared, audit_row_written}.
#
# @env BLOCKED_ON_PREFLIGHT  Script run for the host_environment re-probe (default: the sibling
#                            autonomy-preflight.sh). A test seam, as GH_BIN is for the preflight.
#
# @exitcode 0 success
# @exitcode 1 route: an invalid need, one `fail:` line on stderr, nothing written; resume: the
#             task is not parked on a non-permission blocked_on, or --leg is not its closing leg
# @exitcode 2 usage error, missing or unparseable ledger, broken install, or a ledger write refused
#
# Minimum shell: bash 3.2+. Requires jq.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
_BO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
STATE_PATCH="$SCRIPT_DIR/state-patch.sh"
PREFLIGHT="${BLOCKED_ON_PREFLIGHT:-$SCRIPT_DIR/autonomy-preflight.sh}"

die() {
  printf >&2 'blocked-on-dispatch: %s\n' "$2"
  exit "$1"
}

usage() {
  sed -n '/^# Usage:/,/^# @arg route/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
  exit 2
}

if [ "${1:-}" = "--self-test" ]; then
  # shellcheck source=skills/worktask/scripts/blocked-on-dispatch-selftest.sh
  . "$SCRIPT_DIR/blocked-on-dispatch-selftest.sh"
  self_test
  exit $?
fi

command -v jq > /dev/null 2>&1 || die 2 "jq is required"
for _bo_lib in "$_BO_ROOT/hooks/lib/permission-denied-lib.sh" \
  "$_BO_ROOT/skills/shared/lib/audit-lib.sh" \
  "$_BO_ROOT/skills/shared/lib/state-read-lib.sh" \
  "$SCRIPT_DIR/blocked-on-lib.sh"; do
  [ -r "$_bo_lib" ] || die 2 "plugin install broken — missing $_bo_lib"
  # shellcheck source=/dev/null
  . "$_bo_lib"
done
BO_TABLE="$(blocked_on_table_json)" || die 2 "plugin install broken — blocked_on arm table unreadable"

SUBCMD="${1:-}"
[ "$#" -gt 0 ] && shift
PAYLOAD_ARG="" PAYLOAD_GIVEN=0 TASK_ARG="" TASKS_ARG="" BOUNDARY_ARG="" WS_JSON_ARG="" LEG_ARG=""
STATE_PATH=""
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || die 2 "missing value for $1"
  case "$1" in
    --payload) PAYLOAD_ARG="$2" PAYLOAD_GIVEN=1 ;;
    --task-id) TASK_ARG="$2" ;;
    --tasks) TASKS_ARG="$2" ;;
    --boundary) BOUNDARY_ARG="$2" ;;
    --workspace-json) WS_JSON_ARG="$2" ;;
    --leg) LEG_ARG="$2" ;;
    --state) STATE_PATH="$2" ;;
    *) die 2 "unknown flag: $1" ;;
  esac
  shift 2
done

# Stage-written text only ever reaches a prompt through these: fixed lead lines with the task id
# as the one substitution, and detail rendered as bounded `key: value` data lines for a fence.
# shellcheck disable=SC2016  # jq program text: its $names are jq variables, not shell ones
BO_JQ_DEFS='
def bo_lead($id; $kind):
  if $kind == "user_decision" then "\($id) needs your decision. Answer with one of the options below, or your own."
  elif $kind == "user_action" then "\($id) needs you to do the request below, then answer done."
  elif $kind == "peer_session" then "\($id) needs an answer from the session below. Ask it, then answer with its reply."
  elif $kind == "artifact" then "\($id) waits on the file below from another task. Answer done once it exists."
  elif $kind == "correction" then "\($id) found the defect below in another task\u0027s work. Answer done once it is fixed."
  elif $kind == "host_environment" then "\($id) is blocked by the host check below, which still fails. Answer done once it passes."
  else "\($id) is blocked on the need below. Answer done once it is met." end;
def bo_lines: (if type == "object" then . else {} end) | to_entries
  | map("\(.key | pd_bound(64)): \(.value | (if type == "string" then . else tojson end) | pd_bound(600))")
  | join("\n");
'

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

# bo_field <arm row> <n> — field n (1-based) of a blocked_on_arm row.
bo_field() {
  printf '%s' "$1" | cut -d'|' -f"$2"
}

# bo_command_head <command> — {"command_head","truncated"} for an audit row, or {} for an empty
# command. The head is at most 4 tokens of already masked and path-scrubbed text; each rung is
# tried only when the one above yields nothing, and no rung ever falls back to the raw command.
bo_command_head() {
  local cmd="${1:-}" lib="$_BO_ROOT/hooks/lib/command-head-lib.sh" raw="" text="" cut=false pd
  [ -n "$cmd" ] || { printf '{}'; return 0; }
  if [ -r "$lib" ]; then
    # A subshell: the helper is another issue's file, and sourcing it must not be able to
    # redefine this script's functions or exit it.
    raw=$( (
      # shellcheck source=/dev/null
      . "$lib" > /dev/null 2>&1 || exit 1
      command -v audit_command_head > /dev/null 2>&1 || exit 1
      audit_command_head "$cmd"
    ) 2> /dev/null) || raw=""
    if printf '%s' "$raw" | jq -e 'type == "object" and (.command_head | type) == "string"' > /dev/null 2>&1; then
      text=$(printf '%s' "$raw" | jq -r '.command_head')
      cut=$(printf '%s' "$raw" | jq -r '.truncated == true')
    else
      text=$(printf '%s\n' "$raw" | head -n 1)
    fi
  fi
  if [ -z "$text" ]; then
    pd=$(pd_command_head "$cmd")
    if printf '%s' "$pd" | jq -e '(.command_head | type) == "string"' > /dev/null 2>&1; then
      text=$(printf '%s' "$pd" | jq -r '.command_head')
      cut=$(printf '%s' "$pd" | jq -r '.truncated == true')
    fi
  fi
  if [ -n "$text" ]; then
    text=$(jq -cn --arg h "$text" --argjson c "$cut" "$PD_JQ_DEFS"'
      ($h | pd_bound(80) | [splits("\\s+")] | map(select(length > 0))) as $tok
      | if ($tok | length) == 0 then empty
        else {command_head: ($tok[0:4] | join(" ")), truncated: ($c or ($tok | length) > 4)} end' 2> /dev/null) || text=""
  fi
  [ -n "$text" ] || text='{"command_head":"[redacted]","truncated":true}'
  printf '%s' "$text"
}

# bo_meta <kind> <arm> <leg> <fallback_from> <owner_issue> <head json> <decision_ref> — the only
# metadata a blocked_on row carries. It takes no detail text: every field is an enum value, a
# number, a redacted head or a ref, which is what keeps the committed audit log free of it.
bo_meta() {
  jq -cn --arg k "$1" --arg a "$2" --arg l "$3" --arg ff "$4" --arg oi "$5" --argjson h "$6" --arg dr "$7" '
    {kind: $k, arm: $a, leg: $l}
    + (if $ff != "" then {fallback_from: $ff} else {} end)
    + (if $oi != "" then {owner_issue: ($oi | tonumber)} else {} end)
    + $h
    + (if $dr != "" then {decision_ref: $dr} else {} end)'
}

# bo_row <result> <meta json> — appends one blocked_on row; BO_ROW_WRITTEN reports it.
bo_row() {
  BO_ROW_WRITTEN=false
  corpflow_audit_row --file "$AUDIT" --actor orchestrator --action blocked_on --result "$1" \
    --subject "$TASK_ARG" --task-id "$TASK_ARG" --meta "$2"
  if [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ]; then BO_ROW_WRITTEN=true; fi
  return 0
}

# bo_leg_recorded <kind> <leg> — 0 when this task's still-open need of that kind already has a
# row for the leg. A re-route of the same return (a retried orchestrator turn) then adds no
# second opening row; a need that closed and was raised again is a new need and does.
bo_leg_recorded() {
  [ -f "$AUDIT" ] || return 1
  jq -nRe --arg id "$TASK_ARG" --arg k "$1" --arg l "$2" '
    [inputs | fromjson? | select(type == "object" and .action == "blocked_on"
      and .subject == $id and (.metadata.kind? // "") == $k)]
    | (to_entries | map(select((.value.metadata.decision_ref? // null) != null) | .key)) as $closed
    | (if ($closed | length) == 0 then 0 else $closed[-1] + 1 end) as $from
    | .[$from:] | any(.[]; .metadata.leg == $l)' "$AUDIT" > /dev/null 2>&1
}

# bo_next_ref <kind> — blocked_on:<task_id>:<kind>:<n>, n being 1 plus the earlier closing rows for
# this task and kind, so a need raised, resumed and raised again gets a distinct ref.
bo_next_ref() {
  local n=0
  if [ -f "$AUDIT" ]; then
    n=$(jq -nR --arg id "$TASK_ARG" --arg k "$1" '
      [inputs | fromjson? | select(type == "object" and .action == "blocked_on" and .subject == $id
        and (.metadata.kind? // "") == $k and ((.metadata.decision_ref? // null) | type) == "string")]
      | length' "$AUDIT" 2> /dev/null) || n=0
  fi
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  printf 'blocked_on:%s:%s:%s' "$TASK_ARG" "$1" "$((n + 1))"
}

# bo_resume_block <blocked_on> <arm> <leg> <decision_ref> <artifact_path> — the resume a stage
# receives. The detail sits in a fence as data, and the instruction forbids re-running completed
# steps, because the stage stopped mid-way and a blind re-run repeats side effects.
bo_resume_block() {
  printf '%s' "$1" | jq -c --arg id "$TASK_ARG" --arg arm "$2" --arg leg "$3" --arg dr "$4" --arg ap "$5" \
    "$PD_JQ_DEFS$BO_JQ_DEFS"'
    . as $b
    | {task_id: $id, kind: $b.kind, arm: $arm, leg: $leg, decision_ref: $dr,
       resume_with: $b.resume_with, do_not_rerun: true,
       instruction: ("The \($b.kind) need below, which stopped this stage, is resolved. Continue from the step it blocked."
         + "\n\n" + ($b.detail | bo_lines | pd_fence)
         + (if (($b.detail.verify? // "") | tostring) != "" then "\n\nConfirm the verify line above before you continue." else "" end)
         + "\n\nDo not re-run any step that already completed.")}
    + (if $b.resume_with == "artifact_path" then {artifact_path: ($ap | pd_bound(600))} else {} end)'
}

# bo_park <blocked_on> — ledger copy first, then status, as permission-park.sh parks.
bo_park() {
  # Null before the new value: --task-meta is a recursive merge, so a leftover detail from an
  # earlier need of another kind would otherwise mix its keys into this one.
  # --log /dev/null: state-patch logs every --set value verbatim, and this one carries the
  # stage's full request, command or finding.
  ledger --log /dev/null --task-meta "$TASK_ARG" --set '{"blocked_on":null}' \
    || die 2 "state-patch refused --task-meta $TASK_ARG"
  ledger --log /dev/null --task-meta "$TASK_ARG" --set "$(jq -cn --argjson b "$1" '{blocked_on: $b}')" \
    || die 2 "state-patch refused --task-meta $TASK_ARG"
  ledger --task-status "$TASK_ARG" blocked || die 2 "state-patch refused --task-status $TASK_ARG blocked"
}

# bo_route_out <arm> <leg> <parked> <written> <fallback_from> <owner_issue> <decision_ref> <resume_block>
bo_route_out() {
  jq -cn --arg id "$TASK_ARG" --arg k "$BO_KIND" --arg arm "$1" --arg leg "$2" --arg src "$BO_SOURCE" \
    --argjson p "$3" --argjson w "$4" --arg ff "$5" --arg oi "$6" --arg dr "$7" --argjson rb "$8" '
    {task_id: $id, kind: $k, arm: $arm, leg: (if $leg == "" then null else $leg end), source: $src,
     parked: $p, audit_row_written: $w}
    + (if $ff != "" then {fallback_from: $ff} else {} end)
    + (if $oi != "" then {owner_issue: ($oi | tonumber)} else {} end)
    + (if $dr != "" then {decision_ref: $dr, resume_block: $rb} else {} end)'
}

# route_user_action <fallback_from> <already_parked> <prior_written> — the requested leg.
route_user_action() {
  local ff="$1" oi="" head='{}' row landed written="$3"
  if [ -n "$ff" ]; then
    row=$(blocked_on_arm "$BO_KIND")
    landed=$(bo_field "$row" 7)
    if [ "$landed" != "yes" ]; then oi=$(bo_field "$row" 6); fi
  else
    head=$(bo_command_head "$(printf '%s' "$BO" | jq -r '.detail.command // "" | tostring')")
  fi
  [ "$2" = true ] || bo_park "$BO"
  if bo_leg_recorded "$BO_KIND" requested; then
    written=false
  else
    bo_row blocked "$(bo_meta "$BO_KIND" user_action requested "$ff" "$oi" "$head" "")"
    if [ "$BO_ROW_WRITTEN" != true ]; then written=false; fi
  fi
  bo_route_out user_action requested true "$written" "$ff" "$oi" "" null
}

route_host_environment() {
  local check platforms out result_json dr rb written=true
  local args=(--auto plan)
  check=$(printf '%s' "$BO" | jq -r '.detail.check | tostring')
  bo_park "$BO"
  platforms=$(jq -r '(.metadata.preflight.platforms? // [])
    | if type == "array" then map(tostring) | join(",") else "" end' "$STATE_PATH" 2> /dev/null) || platforms=""
  # Ledger text becomes an argv element only in the shape a platform list has.
  if [[ "$platforms" =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]]; then args+=(--platform "$platforms"); fi
  if [ "$check" = "git-reset-hard" ]; then args+=(--harness); fi
  out=$(bash "$PREFLIGHT" "${args[@]}" < /dev/null 2> /dev/null) || true
  result_json=$(printf '%s\n' "$out" | sed -n 's/^result_json=//p' | tail -n 1)

  # Only an entry with this id reading pass clears the need: a skipped run (a megatask per-issue
  # run skips the preflight) or a run that never probed this id proves nothing about it.
  if [ -n "$result_json" ] && printf '%s' "$result_json" \
    | jq -e --arg c "$check" 'any(.checks[]?; .id == $c and .status == "pass")' > /dev/null 2>&1; then
    ledger --claim "$TASK_ARG" || die 2 "state-patch refused --claim $TASK_ARG"
    ledger --task-meta "$TASK_ARG" --set '{"blocked_on":null}' \
      || die 2 "state-patch refused clearing blocked_on on $TASK_ARG"
    dr=$(bo_next_ref host_environment)
    bo_row ok "$(bo_meta host_environment host_environment probed "" "" '{}' "$dr")"
    rb=$(bo_resume_block "$BO" host_environment probed "$dr" "")
    bo_route_out host_environment probed false "$BO_ROW_WRITTEN" "" "" "$dr" "$rb"
    return 0
  fi

  if bo_leg_recorded host_environment probed; then
    written=false
  else
    bo_row blocked "$(bo_meta host_environment host_environment probed "" "" '{}' "")"
    written="$BO_ROW_WRITTEN"
  fi
  route_user_action host_environment true "$written"
}

cmd_route() {
  local handoff norm
  is_task_id "$TASK_ARG" || die 2 "route needs --task-id <STAGE><N>"
  [ "$PAYLOAD_GIVEN" -eq 1 ] || die 2 "route needs --payload <handoff json>"
  resolve_state
  handoff=$(printf '%s' "$PAYLOAD_ARG" \
    | jq -c 'if type == "object" and (.handoff | type) == "object" then .handoff else . end' 2> /dev/null) || handoff=""
  if ! norm=$(blocked_on_normalize "$handoff"); then
    printf >&2 'fail: the payload carries no blocked_on or cross_session_ask\n'
    exit 1
  fi
  BO=$(printf '%s' "$norm" | jq -c '.blocked_on')
  BO_SOURCE=$(printf '%s' "$norm" | jq -r '.source')
  blocked_on_validate_arm "$BO" || exit 1
  BO_KIND=$(printf '%s' "$BO" | jq -r '.kind')
  jq -e --arg id "$TASK_ARG" '.tasks[$id] | type == "object"' "$STATE_PATH" > /dev/null 2>&1 \
    || die 2 "no tasks.$TASK_ARG in the ledger"

  case "$BO_KIND" in
    permission) bo_route_out permission "" false false "" "" "" null ;;
    host_environment) route_host_environment ;;
    user_action) route_user_action "" false true ;;
    *) route_user_action "$BO_KIND" false true ;;
  esac
}

# write_workspace_parked <workspace.json> — permission-park.sh's park write, kept byte-for-byte in
# behaviour: 0 when written, else 1 with WS_REASON (symlink, missing, not_regular_file, unreadable,
# malformed, write_failed). A symlink is refused and never read or replaced, before the read and
# again before the rename, because whoever planted it chose the target.
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
  local id full needs megatask payloads boundary ws escalated need entry ws_written=false row_written=false
  local ids=()
  if [ -n "$TASKS_ARG" ]; then
    IFS=, read -r -a ids <<< "$TASKS_ARG"
    for id in "${ids[@]}"; do
      is_task_id "$id" || die 2 "invalid task id in --tasks: $id"
    done
  fi
  resolve_state
  # A parked need reaches the user as a user_action whatever its kind: the native arm shows the
  # stage's request, a fallback shows its kind's fixed lead line. cwd comes from the ledger, never
  # from blocked_on, because the directory a user runs a command in is not the stage's to choose.
  full=$(jq -c --arg ids "$TASKS_ARG" --argjson t "$BO_TABLE" "$PD_JQ_DEFS$BO_JQ_DEFS"'
    . as $s
    | ($ids | if . == "" then null else split(",") end) as $want
    | [(.tasks // {}) | to_entries[]
       | select(.key | test("^[A-Z]{2}[0-9]+$"))
       | select($want == null or (.key as $k | $want | index($k)) != null)
       | select(.value.status == "blocked"
           and (.value.metadata.blocked_on | type) == "object"
           and ((.value.metadata.blocked_on.kind | tostring) as $k | $t[$k] != null and $k != "permission"))
       | .key as $id
       | .value.metadata.blocked_on as $b
       | ($b.detail | if type == "object" then . else {} end) as $d
       | ($b.kind == "user_action") as $native
       | ((.value.metadata.workspace_path? // $s.metadata.workspace_path? // "") | pd_bound(600)) as $cwd
       | {task_id: $id, kind: $b.kind, arm: "user_action", resume_leg: $t.user_action.closing_leg,
          request: (if $native then ($d.request | pd_bound(512)) else bo_lead($id; $b.kind) end),
          command: (if $native then ($d.command | pd_bound(512)) else "" end),
          verify: (if $native then ($d.verify | pd_bound(512)) else "" end)}
       | . + {truncated: (.command | pd_truncated(512)), cwd: $cwd}
       | if $native then .
         else . + {fallback_from: $b.kind}
           + (if $t[$b.kind].landed then {} else {owner_issue: $t[$b.kind].owner_issue} end) end
       | . + {_lines: ($d | bo_lines)}]' \
    "$STATE_PATH")
  needs=$(printf '%s' "$full" | jq -c 'map(del(._lines))')
  megatask=$(jq -r '(.tasks["PL\(.run_index // 0)"].metadata.megatask_group // "") | tostring' "$STATE_PATH")

  if [ -z "$megatask" ]; then
    # Each detail value is a data line inside a fence one backtick longer than its longest run,
    # so stage text can neither close the fence nor render as markup. A `!` line is offered only
    # for a native user_action whose command was not cut: a cut command pasted would run
    # something other than what the stage asked for.
    payloads=$(printf '%s' "$full" | jq -c "$PD_JQ_DEFS$BO_JQ_DEFS"'
      map((.cwd != "") as $has_cwd | {
        header: (.task_id | .[0:12]),
        question: (bo_lead(.task_id; .kind) + "\n\n"
          + ((._lines + (if $has_cwd then "\ncwd: \(.cwd)" else "" end)) | pd_fence)
          + (if .kind == "user_action" and .command != "" and (.truncated | not)
             then "\n\nTo run it yourself" + (if $has_cwd then ", from that directory (the cwd line above)" else "" end)
               + ", enter:\n\n" + ("! \(.command)" | pd_fence)
             else "" end)),
        multiSelect: false,
        options: [
          {label: "done", description: "The need above is met; the stage resumes from the step it blocked."},
          {label: "stop here", description: "Leave the stage parked and stop this run; a later --resume asks again."}
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
  escalated="[]"
  while IFS= read -r need; do
    [ -n "$need" ] || continue
    entry=$(jq -cn --arg k "$(printf '%s' "$need" | jq -r '.kind')" '{kind: $k}')
    if [ "$(printf '%s' "$need" | jq -r '.kind')" = "user_action" ]; then
      entry=$(jq -cn --argjson e "$entry" \
        --argjson h "$(bo_command_head "$(printf '%s' "$need" | jq -r '.command')")" '$e + $h')
    fi
    escalated=$(jq -cn --argjson e "$escalated" --argjson x "$entry" '$e + [$x]')
  done <<< "$(printf '%s' "$needs" | jq -c '.[]')"

  ws="$WS_JSON_ARG"
  [ -n "$ws" ] || ws="$(dirname -- "${STATE_PATH%/*}")/workspace.json"
  WS_REASON=""
  if write_workspace_parked "$ws"; then ws_written=true; fi

  if ! jq -nRe --arg b "$boundary" --argjson e "$escalated" '
      [inputs | fromjson? | select(type == "object" and .action == "escalation_parked"
        and .subject == $b and .metadata.kind == "user_action" and .metadata.escalated == $e)] | length > 0' \
    "$AUDIT" > /dev/null 2>&1; then
    corpflow_audit_row --file "$AUDIT" --actor orchestrator --action escalation_parked \
      --result block --subject "$boundary" \
      --meta "$(jq -cn --argjson e "$escalated" '{escalated: $e, reason: "parked_escalation", kind: "user_action"}')"
    if [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ]; then row_written=true; fi
  fi

  jq -cn --argjson n "$needs" --arg b "$boundary" --argjson e "$escalated" \
    --argjson ww "$ws_written" --arg wr "$WS_REASON" --argjson rw "$row_written" '
    {mode: "megatask_park", needs: $n, payloads: [],
     park: {boundary: $b, execution: {status: "failed", reason: "parked_escalation"},
            escalated: $e, workspace_written: $ww,
            workspace_reason: (if $ww then null else $wr end), audit_row_written: $rw}}'
}

cmd_resume() {
  local row closing ff="" oi="" head='{}' dr ap="" target rb
  is_task_id "$TASK_ARG" || die 2 "resume needs --task-id <STAGE><N>"
  [[ "$LEG_ARG" =~ ^[a-z_]+$ ]] || die 2 "resume needs --leg <leg>"
  resolve_state
  BO=$(jq -c --arg id "$TASK_ARG" '.tasks[$id].metadata.blocked_on // null' "$STATE_PATH")
  BO_KIND=$(printf '%s' "$BO" | jq -r 'if type == "object" then (.kind // "") | tostring else "" end')
  if [ -z "$BO_KIND" ] || [ "$BO_KIND" = "permission" ] || ! blocked_on_arm "$BO_KIND" > /dev/null; then
    die 1 "tasks.$TASK_ARG is not parked on a non-permission blocked_on"
  fi
  # Every parked non-permission need was parked by the user_action arm (native or fallback), so
  # that arm's closing leg is the one resume accepts. Landing another arm adds its own branch.
  closing=$(bo_field "$(blocked_on_arm user_action)" 5)
  [ "$LEG_ARG" = "$closing" ] || die 1 "--leg $LEG_ARG is not the closing leg ($closing) of tasks.$TASK_ARG"

  if [ "$BO_KIND" = "user_action" ]; then
    head=$(bo_command_head "$(printf '%s' "$BO" | jq -r '.detail.command // "" | tostring')")
  else
    ff="$BO_KIND"
    row=$(blocked_on_arm "$BO_KIND")
    if [ "$(bo_field "$row" 7)" != "yes" ]; then oi=$(bo_field "$row" 6); fi
  fi
  case "$BO_KIND" in
    artifact) ap=$(printf '%s' "$BO" | jq -r '.detail.path // "" | tostring') ;;
    correction)
      target=$(printf '%s' "$BO" | jq -r '.detail.target_task // "" | tostring')
      ap=$(jq -r --arg t "$target" '(.tasks[$t].metadata.artifact? // "") | tostring' "$STATE_PATH")
      ;;
  esac

  ledger --claim "$TASK_ARG" || die 2 "state-patch refused --claim $TASK_ARG"
  # `null`, not deletion: --task-meta has no unset, so a cleared park reads blocked_on == null.
  ledger --task-meta "$TASK_ARG" --set '{"blocked_on":null}' \
    || die 2 "state-patch refused clearing blocked_on on $TASK_ARG"
  dr=$(bo_next_ref "$BO_KIND")
  bo_row ok "$(bo_meta "$BO_KIND" user_action "$LEG_ARG" "$ff" "$oi" "$head" "$dr")"
  rb=$(bo_resume_block "$BO" user_action "$LEG_ARG" "$dr" "$ap")
  jq -cn --argjson rb "$rb" --argjson w "$BO_ROW_WRITTEN" '{resume_block: $rb, cleared: true, audit_row_written: $w}'
}

BO="" BO_KIND="" BO_SOURCE="" BO_ROW_WRITTEN=false AUDIT=""
case "$SUBCMD" in
  route) cmd_route ;;
  batch) cmd_batch ;;
  resume) cmd_resume ;;
  -h | --help | "") usage ;;
  *) die 2 "unknown subcommand: $SUBCMD" ;;
esac
