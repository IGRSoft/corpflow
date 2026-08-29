#!/usr/bin/env bash
# @description model-switch-lib.sh — sourceable library shared by model-switch-gate.sh
#   (PreModelSwitch decision hook) and model-switch-audit.sh (PostModelSwitch observer).
#
#   Dependency-free by construction: sources nothing, sets no shell options, probes
#   nothing at load time, no side effects at load.
#
#   Symbols: corpflow_context_root, corpflow_active_stage, corpflow_resolve_pin,
#   corpflow_model_family.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'model-switch-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Echoes an absolute path to .context/.
#
# Resolves independently of cwd: PreModelSwitch can fire from an
# isolation:worktree subagent, whose cwd is a linked worktree where .context/
# does not exist (it is gitignored, never carried into a worktree checkout).
# The git arm recovers that case — --git-common-dir points at the main
# checkout's .git, whose parent owns .context/.
corpflow_context_root() {
  local _common _parent
  if [ -n "${WORKSPACE_ROOT:-}" ] && [ -d "${WORKSPACE_ROOT}/.context" ]; then
    printf '%s' "${WORKSPACE_ROOT}/.context"; return
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.context" ]; then
    printf '%s' "${CLAUDE_PROJECT_DIR}/.context"; return
  fi
  if _common=$(git rev-parse --git-common-dir 2> /dev/null) && [ -n "$_common" ]; then
    _parent=$(cd "$(dirname "$_common")" 2> /dev/null && pwd) || _parent=""
    if [ -n "$_parent" ] && [ -d "$_parent/.context" ]; then
      printf '%s' "$_parent/.context"; return
    fi
  fi
  # No "env var wins even when .context/ is absent" arm: this library only reads.
  # A path with no .context/ is indistinguishable from "no worktask running",
  # which is the gate's silent-pass case.
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then printf '%s' "${CLAUDE_PROJECT_DIR}/.context"; return; fi
  printf '%s' "$(pwd)/.context"
}

# Echoes the single in_progress stage code, or empty.
#
# Every ambiguity resolves to empty, never a guess: no state.json, no jq, an
# unparseable file, zero or more than one distinct stage, or an unrecognized
# token. Empty means there is no reliable "who is acting" answer.
corpflow_active_stage() {
  local _ctx="$1" _state _stages
  _state="$_ctx/state.json"
  [ -f "$_state" ] || { printf ''; return; }
  command -v jq > /dev/null 2>&1 || { printf ''; return; }

  # Ledger keys are numbered (DV0, DV1) but the pin is per stage CODE, so
  # parallel tracks of one stage collapse to a single unambiguous answer.
  _stages=$(jq -r '
    if (.tasks|type=="object") then
      (.tasks | to_entries | map(select(.value.status=="in_progress"))
        | map(.key | sub("[0-9]+$"; "")) | unique)
    else [] end
    | join(",")
  ' "$_state" 2> /dev/null) || { printf ''; return; }

  case "$_stages" in
    *,* | "") printf ''; return ;;
  esac

  case "$_stages" in
    PL | AR | TL | DV | DR | SR | QA | DC | RE | FN | ST | IR | ET) printf '%s' "$_stages" ;;
    *) printf '' ;;
  esac
}

# Echoes "<model_requested> <task_id>" for the pinned stage, or empty.
#
# Reads .facts.dispatched_agents[] (schema: handoff-protocol.md § facts —
# dispatched_agents). This is the gate's one non-guessed input, which is why the
# whole decision keys on it. Match order: exact agent_id, else exactly one
# launched row for the stage, else empty — ambiguous is unresolved, never a
# guess. A row without model_requested carries no pin.
corpflow_resolve_pin() {
  local _ctx="$1" _stage="$2" _agent_id="${3:-}" _state _out
  _state="$_ctx/state.json"
  [ -f "$_state" ] || { printf ''; return; }
  [ -n "$_stage" ] || { printf ''; return; }
  command -v jq > /dev/null 2>&1 || { printf ''; return; }

  _out=$(jq -r --arg stage "$_stage" --arg aid "$_agent_id" '
    (if (.facts|type=="object") and (.facts.dispatched_agents|type=="array")
       then .facts.dispatched_agents else [] end) as $rows
    | ( if ($aid | length) > 0
          then ($rows | map(select(.agent_id == $aid)))
          else [] end ) as $byid
    | ( if ($byid | length) == 1
          then $byid
          else ($rows | map(select(.stage == $stage and .status == "launched")))
        end ) as $cand
    | if ($cand | length) == 1
        and (($cand[0].model_requested // "") | length) > 0
        and (($cand[0].task_id // "") | length) > 0
      then "\($cand[0].model_requested) \($cand[0].task_id)"
      else "" end
  ' "$_state" 2> /dev/null) || { printf ''; return; }

  printf '%s' "$_out"
}

# Echoes opus|sonnet|haiku|fable, or empty.
#
# Normalizes an alias and a fully-resolved id onto one family so a difference in
# SPELLING is never read as a re-tier. Unrecognized yields empty, which callers
# read as "cannot compare" — not as "different".
corpflow_model_family() {
  local _raw _lower
  _raw="${1:-}"
  [ -n "$_raw" ] || { printf ''; return; }
  # tr, not ${x,,}: bash 3.2 has no case-conversion expansion.
  _lower=$(printf '%s' "$_raw" | tr '[:upper:]' '[:lower:]')
  case "$_lower" in
    *opus*) printf 'opus' ;;
    *sonnet*) printf 'sonnet' ;;
    *haiku*) printf 'haiku' ;;
    *fable*) printf 'fable' ;;
    *) printf '' ;;
  esac
}
