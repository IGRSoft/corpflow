#!/usr/bin/env bash
# @description headless-poststop.sh — replays the installed plugin.json's `SubagentStop` hooks
#   for a headless child, because a `claude -p --agent` main session never fires SubagentStop
#   itself. The replay list is DATA, parsed from plugin.json at call time, not a hand-kept copy
#   — a hook added later to the SubagentStop array is replayed with no code change here.
#
#   Matcher rule: keep a group whose `matcher` is absent, or whose ERE matches the agent id
#   (the runtime matches SubagentStop matchers against `agent_type`, exactly as the live
#   `^corpflow:product-manager$` groups in plugin.json already do for PL/FN/ST). Run every kept
#   group's hooks in array order, piping one synthesized payload to each.
#
#   Verdict semantics mirror the live SubagentStop contract: a `decision:"block"` from ANY
#   hook makes the stage blocked (reasons aggregated across every hook that blocked, not just
#   the first); a hook's exit code never decides the verdict (the gates' own exit-0-always
#   contract). The resume cap is 2: `--attempt` is 1 (first run), 2 or 3 (after one or two
#   `--resume` round-trips). `--attempt 2|3` sets `stop_hook_active:true` in the payload,
#   matching what the real runtime sets on a resumed turn; a stage still blocked at attempt 3
#   is `escalate` — the two resumes are spent, and the caller (the orchestrator) hands the
#   stage to the error chain instead of a third `claude -p --resume`. This script only
#   replays the hooks; the orchestrator runs the actual resume round-trip between attempts.
#
#   Symbols: none exported — this file is a CLI.
#
# @exitcode 2  usage error or an unreadable plugin.json
#
# Minimum shell: bash 3.2+ (macOS default) — no associative arrays, no `local -n`.

set -uo pipefail

_HP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HP_PLUGIN_ROOT="$(cd "${_HP_DIR}/../../.." && pwd)"

usage() {
  cat >&2 << 'EOF2'
usage:
  headless-poststop.sh --task <ID> --orchestrator-session <uuid> --session <uuid>
                        --agent <plugin:agent>
                        [--workspace <path>] [--artifact <path>]
                        [--plugin-json <path>] [--effort-level <tier>]
                        [--duration-ms <n>] [--result-text <text>] [--attempt 1|2|3]

--orchestrator-session is the orchestrator's own session id (payload session_id).
--session is the headless child's uuid (payload agent_id) — the two are never the same
value once dispatch runs headless.

Prints one JSON line: {"blocked":bool,"reasons":[...],"additional_context":"...",
"hooks_run":[...],"escalate":bool}. Exit 0 whether or not a hook blocked — the
verdict lives in the payload, matching the gates' own exit-0-always contract.
EOF2
  exit 2
}

TASK=""
SESSION=""
ORCH_SESSION=""
AGENT=""
WORKSPACE=""
ARTIFACT=""
PLUGIN_JSON="${_HP_PLUGIN_ROOT}/.claude-plugin/plugin.json"
EFFORT_LEVEL=""
DURATION_MS="0"
RESULT_TEXT=""
ATTEMPT="1"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) TASK="${2:-}"; shift 2 ;;
    --session) SESSION="${2:-}"; shift 2 ;;
    --orchestrator-session) ORCH_SESSION="${2:-}"; shift 2 ;;
    --agent) AGENT="${2:-}"; shift 2 ;;
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --artifact) ARTIFACT="${2:-}"; shift 2 ;;
    --plugin-json) PLUGIN_JSON="${2:-}"; shift 2 ;;
    --effort-level) EFFORT_LEVEL="${2:-}"; shift 2 ;;
    --duration-ms) DURATION_MS="${2:-0}"; shift 2 ;;
    --result-text) RESULT_TEXT="${2:-}"; shift 2 ;;
    --attempt) ATTEMPT="${2:-1}"; shift 2 ;;
    -h | --help) usage ;;
    *)
      printf >&2 'headless-poststop.sh: unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

[ -n "$TASK" ] && [ -n "$SESSION" ] && [ -n "$ORCH_SESSION" ] && [ -n "$AGENT" ] || usage
command -v jq > /dev/null 2>&1 || {
  printf >&2 'headless-poststop.sh: jq is required\n'
  exit 2
}
[ -r "$PLUGIN_JSON" ] || {
  printf >&2 'headless-poststop.sh: cannot read %s\n' "$PLUGIN_JSON"
  exit 2
}
[[ "$ATTEMPT" =~ ^[123]$ ]] || usage

# Task id -> bare stage code: strip the trailing run digits (DV0 -> DV), the same shape
# every other stamped-task-id reader in this plugin already assumes.
STAGE="$(printf '%s' "$TASK" | sed -E 's/[0-9]+$//')"

STOP_HOOK_ACTIVE="false"
[ "$ATTEMPT" = "1" ] || STOP_HOOK_ACTIVE="true"

# The synthesized SubagentStop payload carries only fields a real hook actually reads
# (agent_type, agent_id, session_id, cwd, effort.level, duration_ms, last_assistant_message,
# stop_hook_active). `session_id` is the orchestrator's own session — the live runtime's
# SubagentStop payload always names the calling session, never the subagent's — and
# `agent_id` is the headless child's uuid; the two are distinct fields even though a plain
# in-process SubagentStop never has to tell them apart. `effort` is omitted entirely, not
# emitted null, when the tier was never observed: no tier ever vouches for itself, including
# via a placeholder the reader might treat as a real value.
build_payload() {
  local ejson='{}'
  if [ -n "$EFFORT_LEVEL" ]; then
    ejson=$(jq -cn --arg l "$EFFORT_LEVEL" '{level:$l}')
  fi
  jq -cn \
    --arg session "$ORCH_SESSION" --arg agent_id "$SESSION" --arg agent "$AGENT" \
    --arg cwd "$WORKSPACE" --arg text "$RESULT_TEXT" --argjson duration "$DURATION_MS" \
    --argjson stop_active "$STOP_HOOK_ACTIVE" --argjson effort "$ejson" \
    '{hook_event_name:"SubagentStop", session_id:$session, agent_id:$agent_id,
      agent_type:$agent, cwd:$cwd, stop_hook_active:$stop_active,
      duration_ms:$duration, effort:$effort, last_assistant_message:$text,
      headless:true}'
}
PAYLOAD="$(build_payload)"

# _hp_matches <matcher> -> 0 when the group applies: no matcher, or its ERE matches $AGENT.
_hp_matches() {
  local matcher="$1"
  [ -n "$matcher" ] || return 0
  [[ "$AGENT" =~ $matcher ]]
}

BLOCKED=0
REASONS_FILE="$(mktemp)"
CONTEXT_FILE="$(mktemp)"
HOOKS_RUN_FILE="$(mktemp)"
trap 'rm -f "$REASONS_FILE" "$CONTEXT_FILE" "$HOOKS_RUN_FILE"' EXIT

GROUP_COUNT="$(jq '(.hooks.SubagentStop // []) | length' "$PLUGIN_JSON")"
_hp_i=0
while [ "$_hp_i" -lt "$GROUP_COUNT" ]; do
  MATCHER="$(jq -r --argjson i "$_hp_i" '.hooks.SubagentStop[$i].matcher // ""' "$PLUGIN_JSON")"
  if _hp_matches "$MATCHER"; then
    HOOK_COUNT="$(jq --argjson i "$_hp_i" '(.hooks.SubagentStop[$i].hooks // []) | length' \
      "$PLUGIN_JSON")"
    _hp_j=0
    while [ "$_hp_j" -lt "$HOOK_COUNT" ]; do
      RAW_CMD="$(jq -r --argjson i "$_hp_i" --argjson j "$_hp_j" \
        '.hooks.SubagentStop[$i].hooks[$j].command // ""' "$PLUGIN_JSON")"
      # Plain parameter substitution, never eval: the only variable the manifest's `command`
      # field is documented to carry is this one.
      CMD="${RAW_CMD/\$\{CLAUDE_PLUGIN_ROOT\}/$_HP_PLUGIN_ROOT}"
      # bash 3.2 has no `mapfile`; build the array line by line instead.
      ARGS=()
      while IFS= read -r _hp_arg; do
        [ -n "$_hp_arg" ] && ARGS[${#ARGS[@]}]="$_hp_arg"
      done < <(jq -r --argjson i "$_hp_i" --argjson j "$_hp_j" \
        '.hooks.SubagentStop[$i].hooks[$j].args[]? // empty' "$PLUGIN_JSON")

      HOOK_OUT="$(printf '%s' "$PAYLOAD" \
        | CLAUDE_PLUGIN_ROOT="$_HP_PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$WORKSPACE" \
          CLAUDE_TASK_ID="$TASK" CLAUDE_TASK_METADATA_STAGE="$STAGE" \
          CLAUDE_AGENT_NAME="$AGENT" CLAUDE_ARTIFACT_PATH="$ARTIFACT" \
          CLAUDE_DURATION_MS="$DURATION_MS" \
          bash "$CMD" ${ARGS[@]+"${ARGS[@]}"} 2> /dev/null)"
      printf '%s\n' "$CMD" >> "$HOOKS_RUN_FILE"

      if printf '%s' "$HOOK_OUT" | jq -e '.decision == "block"' > /dev/null 2>&1; then
        BLOCKED=1
        printf '%s' "$HOOK_OUT" | jq -r '.reason // "blocked"' >> "$REASONS_FILE"
        printf '%s' "$HOOK_OUT" \
          | jq -r '.hookSpecificOutput.additionalContext // ""' >> "$CONTEXT_FILE"
      fi
      _hp_j=$((_hp_j + 1))
    done
  fi
  _hp_i=$((_hp_i + 1))
done

REASONS_JSON="$(jq -R -s 'split("\n") | map(select(length > 0))' "$REASONS_FILE")"
CONTEXT="$(grep -v '^$' "$CONTEXT_FILE" 2> /dev/null | paste -sd ' ' - || true)"
HOOKS_RUN_JSON="$(jq -R -s 'split("\n") | map(select(length > 0))' "$HOOKS_RUN_FILE")"

ESCALATE="false"
[ "$BLOCKED" -eq 1 ] && [ "$ATTEMPT" = "3" ] && ESCALATE="true"

jq -cn --argjson blocked "$([ "$BLOCKED" -eq 1 ] && echo true || echo false)" \
  --argjson reasons "$REASONS_JSON" --arg context "$CONTEXT" \
  --argjson hooks_run "$HOOKS_RUN_JSON" --argjson escalate "$ESCALATE" \
  '{blocked:$blocked, reasons:$reasons, additional_context:$context,
    hooks_run:$hooks_run, escalate:$escalate}'
