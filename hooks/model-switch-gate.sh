#!/usr/bin/env bash
# model-switch-gate — PreModelSwitch gate refusing a mid-worktask re-tier away from
# the model a stage was dispatched with. No matcher in plugin.json; self-filters.
#
# PAYLOAD SCHEMA IS UNCONFIRMED. CC 2.1.251 postdates every doc in this repo and no
# live payload has been observed. Split, per the schema-drift discipline in
# skills/agent-coordination/references/headless-dispatch.md § Schema Versioning Watch:
#
#   CONFIRMED (every other hook payload in this plugin carries them):
#     session_id, agent_id
#   ASSUMED — read through a first-match coalesce, all equally speculative:
#     destination  to_model / toModel / requested_model / requestedModel / new_model / newModel
#     origin       from_model / fromModel / current_model / currentModel
#     trigger      reason / trigger / source
#
# The PIN is not assumed: it comes from this plugin's own
# .facts.dispatched_agents[].model_requested.
#
# Behavior:
#   - Exits 0 ALWAYS. A block travels in the stdout JSON, never in the exit code —
#     hook-monitoring.md § PreToolUse decisions records that an exit-2 block holds
#     even when its JSON fails schema validation, so a wrong field guess paired with
#     a non-zero exit would wedge every session that switches models.
#   - Fails OPEN structurally, not by discipline: BLOCK is reachable only once the
#     destination coalesce matches a real field. If every guess is wrong the
#     destination is empty and the ladder can only reach silent-pass or annotate.
#   - Silent for any session with no worktask ledger, no single in_progress stage,
#     or no unambiguous pin — zero side effects, no directory creation.
#   - CORPFLOW_MODEL_SWITCH_GATE=off disables rows 4-6. Process env only; an agent
#     cannot self-serve it from a command string.
#   - jq absent -> exit 0.
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

_LIB="$(dirname "$0")/model-switch-lib.sh"
if [ ! -f "$_LIB" ]; then
  echo "model-switch-gate: library missing at $_LIB" >&2
  exit 0
fi
# shellcheck source=hooks/model-switch-lib.sh
. "$_LIB"

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' '{"session_id":"sess_test","agent_id":"agt_test","to_model":"sonnet"}'
  else
    cat
  fi
}

# Appends one audit row. Refuses to append through a symlink, which would turn
# this into a write primitive against an arbitrary target.
write_row() {
  _wr_ctx="$1"; _wr_subject="$2"; _wr_action="$3"; _wr_result="$4"; _wr_meta="$5"
  _wr_dir="$_wr_ctx/logs"
  _wr_file="$_wr_dir/audit.jsonl"
  mkdir -p "$_wr_dir" 2> /dev/null || return 0
  [ ! -L "$_wr_file" ] || return 0
  _wr_ts=$(date -u +%FT%TZ 2> /dev/null) || _wr_ts="unknown"
  _wr_row=$(jq -cn --arg ts "$_wr_ts" --arg subject "$_wr_subject" --arg action "$_wr_action" \
    --arg result "$_wr_result" --argjson meta "$_wr_meta" '
    {ts:$ts, actor:"hook:model-switch-gate", action:$action, subject:$subject, result:$result, metadata:$meta}
  ' 2> /dev/null) || return 0
  { printf '%s\n' "$_wr_row" >> "$_wr_file"; } 2> /dev/null || return 0
}

# Classifies the trigger string into fallback | user | unknown.
classify_trigger() {
  _ct_raw=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  [ -n "$_ct_raw" ] || { printf 'unknown'; return; }
  case "$_ct_raw" in
    *fallback* | *404* | *not_found* | *notfound* | *unavailable* | *degrade* | *overload* | *error* | *retry*)
      printf 'fallback' ;;
    *user* | *manual* | *explicit* | *interactive* | *command* | *slash*)
      printf 'user' ;;
    *) printf 'unknown' ;;
  esac
}

# run_gate <payload> <ctx> -> echoes decision JSON (block/confirm/annotate) or
# nothing. Returns 0 always.
run_gate() {
  _payload="$1"
  _ctx="$2"

  command -v jq > /dev/null 2>&1 || return 0

  # Hatch first — cheapest check, and a control switching off must not be silent.
  # Gated on state.json existing so a shell-profile-wide export cannot materialize
  # .context/logs/ in every unrelated directory.
  if [ "${CORPFLOW_MODEL_SWITCH_GATE:-}" = "off" ] && [ -f "$_ctx/state.json" ]; then
    _sentinel="$_ctx/logs/.model-switch-gate-off-noted"
    if [ ! -f "$_sentinel" ]; then
      # `|| :` — under set -e a failed touch here would be a non-zero hook exit.
      { mkdir -p "$_ctx/logs" && : > "$_sentinel"; } 2> /dev/null || :
      write_row "$_ctx" "CORPFLOW_MODEL_SWITCH_GATE" "model_switch_gate_disabled" "ok" \
        '{"vector":"CORPFLOW_MODEL_SWITCH_GATE"}'
    fi
    return 0
  fi

  # An unparseable payload is not a switch this gate can describe, so it earns
  # silence rather than a row-2 annotation about a destination that was never
  # there.
  printf '%s' "$_payload" | jq -e . > /dev/null 2>&1 || return 0

  # Row 1 — no worktask, no single acting stage, or no unambiguous pin.
  _stage=$(corpflow_active_stage "$_ctx")
  [ -n "$_stage" ] || return 0

  _agent_id=$(printf '%s' "$_payload" | jq -r '.agent_id // ""' 2> /dev/null || printf '')
  _pin_pair=$(corpflow_resolve_pin "$_ctx" "$_stage" "$_agent_id")
  [ -n "$_pin_pair" ] || return 0
  _pin=${_pin_pair%% *}
  _task_id=${_pin_pair##* }

  _dest=$(printf '%s' "$_payload" | jq -r '
    .to_model // .toModel // .requested_model // .requestedModel
    // .new_model // .newModel // ""' 2> /dev/null || printf '')
  _origin=$(printf '%s' "$_payload" | jq -r '
    .from_model // .fromModel // .current_model // .currentModel // ""' 2> /dev/null || printf '')
  _trigger_raw=$(printf '%s' "$_payload" | jq -r '
    .reason // .trigger // .source // ""' 2> /dev/null || printf '')

  _pin_family=$(corpflow_model_family "$_pin")
  _dest_family=$(corpflow_model_family "$_dest")

  # Row 2 — destination unresolvable. Every wrong-guess path lands here, which is
  # what makes the fail-open property structural rather than conventional.
  if [ -z "$_dest_family" ]; then
    _ac="Stage $_stage (task $_task_id) is pinned to '$_pin', but this PreModelSwitch payload carried no field this gate recognizes as a destination model. Passing the switch through unblocked; verify dispatched_agents[].model_resolved before attributing this stage's cost."
    jq -cn --arg r "$_ac" '{
      decision: "annotate",
      reason: $r,
      hookSpecificOutput: {hookEventName: "PreModelSwitch", additionalContext: $r}
    }' 2> /dev/null || return 0
    write_row "$_ctx" "$_task_id" "model_switch_annotated" "ok" \
      "$(jq -cn --arg s "$_stage" --arg t "$_task_id" --arg p "$_pin" \
        '{stage:$s, task_id:$t, pinned:$p, kind:"destination_unresolved"}')"
    return 0
  fi

  # Row 3 — same family, different spelling. An alias and a resolved id are not a
  # re-tier.
  if [ "$_pin_family" = "$_dest_family" ]; then
    return 0
  fi

  _trigger=$(classify_trigger "$_trigger_raw")

  # Row 4 — error recovery. Blocking a fallback would strand the stage worse than
  # the re-tier does.
  if [ "$_trigger" = "fallback" ]; then
    _ac="Stage $_stage (task $_task_id) pinned '$_pin' but is falling back to '$_dest'. Allowed as error recovery. This stage did not run on the model it requested — re-check dispatched_agents[].model_resolved before attributing cost."
    jq -cn --arg r "$_ac" '{
      decision: "annotate",
      reason: $r,
      hookSpecificOutput: {hookEventName: "PreModelSwitch", additionalContext: $r}
    }' 2> /dev/null || return 0
    write_row "$_ctx" "$_task_id" "model_switch_annotated" "ok" \
      "$(jq -cn --arg s "$_stage" --arg t "$_task_id" --arg p "$_pin" \
        --arg d "$_dest" --arg o "$_origin" \
        '{stage:$s, task_id:$t, pinned:$p, requested:$d, origin:$o, kind:"fallback"}')"
    return 0
  fi

  # Row 5 — explicit human action. Confirm rather than refuse; the operator may
  # have a reason the ledger cannot see.
  if [ "$_trigger" = "user" ]; then
    _ac="Stage $_stage (task $_task_id) is pinned to '$_pin' via metadata.model. Switching to '$_dest' will run the rest of this stage off-tier. Confirm only if that is intended; otherwise cancel and re-dispatch the stage with an explicit metadata.model override."
    jq -cn --arg r "$_ac" '{
      decision: "confirm",
      reason: $r,
      hookSpecificOutput: {hookEventName: "PreModelSwitch", permissionDecision: "ask", additionalContext: $r}
    }' 2> /dev/null || return 0
    write_row "$_ctx" "$_task_id" "model_switch_confirm_requested" "ok" \
      "$(jq -cn --arg s "$_stage" --arg t "$_task_id" --arg p "$_pin" \
        --arg d "$_dest" --arg o "$_origin" \
        '{stage:$s, task_id:$t, pinned:$p, requested:$d, origin:$o, kind:"user"}')"
    return 0
  fi

  # Row 6 — families differ with no recognized trigger.
  _ac="Stage $_stage (task $_task_id) is pinned to '$_pin' via metadata.model; this switch would move it to '$_dest' with no recognized override trigger. To proceed: re-dispatch the stage with an explicit metadata.model override, or a human operator may restart with CORPFLOW_MODEL_SWITCH_GATE=off in the process environment — an agent cannot self-serve this."
  jq -cn --arg r "$_ac" '{
    decision: "block",
    reason: $r,
    hookSpecificOutput: {hookEventName: "PreModelSwitch", permissionDecision: "deny", additionalContext: $r}
  }' 2> /dev/null || return 0
  write_row "$_ctx" "$_task_id" "model_switch_blocked" "block" \
    "$(jq -cn --arg s "$_stage" --arg t "$_task_id" --arg p "$_pin" \
      --arg d "$_dest" --arg o "$_origin" --arg tr "$_trigger_raw" \
      '{stage:$s, task_id:$t, pinned:$p, requested:$d, origin:$o, trigger_raw:$tr, kind:"unrecognized_trigger"}')"
  return 0
}

# This arm fails CLOSED: a self-test that cannot find its cases reports failure,
# never "OK".
if [ "$SELF_TEST" -eq 1 ]; then
  _selftest_body="$(dirname "$0")/lib/model-switch-gate-selftest.sh"
  if [ ! -f "$_selftest_body" ]; then
    echo "model-switch-gate: self-test body missing at $_selftest_body" >&2
    exit 1
  fi
  . "$_selftest_body"
fi

PAYLOAD=$(read_stdin)
CTX=$(corpflow_context_root)
run_gate "$PAYLOAD" "$CTX"
exit 0
