#!/usr/bin/env bash
# @description model-switch-lib.sh — sourceable library shared by four hooks:
#   model-switch-gate.sh (PreModelSwitch decision), model-switch-audit.sh
#   (PostModelSwitch observer), test-execution-gate.sh (PreToolUse test-authority
#   gate) and state-merge.sh (SubagentStop ledger merge).
#
#   Dependency-free by construction: sources nothing, sets no shell options, probes
#   nothing at load time, no side effects at load. That keeps the shared point of
#   failure a LEAF — there is no load-order graph across consumers to get wrong.
#   Adding a `source` here is a design change, not a refactor.
#
#   Every symbol returns 0 on every path; failure is the empty string on stdout.
#   A non-zero return would abort a `set -e` consumer from inside a library whose
#   whole purpose is to keep those consumers fail-open.
#
#   Symbols: corpflow_workspace_root, corpflow_context_root, corpflow_active_stage,
#   corpflow_resolve_pin, corpflow_stage_and_pin, corpflow_model_family,
#   corpflow_switch_dest, corpflow_switch_origin, corpflow_switch_fields,
#   corpflow_hook_audit_row.
#
# Minimum shell: bash 3.2+ (macOS default). Correct under the union of its
# consumers' option sets, `set -euf -o pipefail`, while setting none of them.

# Anti-execution guard — MUST be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'model-switch-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard — MUST be the second statement. `readonly -f` below makes a second
# source a fatal redefinition attempt rather than a no-op, so four consumers that
# may transitively source each other need this to be idempotent.
[ -n "${_CORPFLOW_HOOK_LIB:-}" ] && return 0
_CORPFLOW_HOOK_LIB=1

# corpflow_workspace_root <mode> — echoes the absolute workspace root and also
# assigns it to _CORPFLOW_WS_ROOT, so a caller on a hot path can read the value
# without paying for a command substitution. <mode> is `read` (default) or `write`.
#
# Resolves independently of cwd: these hooks fire from isolation:worktree
# subagents whose cwd is a linked worktree where .context/ does not exist (it is
# gitignored, never carried into a worktree checkout). The git arm recovers that
# case — --git-common-dir points at the main checkout's .git, whose parent owns
# .context/.
#
# The probe arms are identical in both modes; only the tail differs, and that
# difference is the whole reason the flag exists. A WRITER must land its first
# write in the declared workspace even before .context/ exists, so `write` keeps
# WORKSPACE_ROOT in the tail. A READER must not: a path with no .context/ is
# indistinguishable from "no worktask running", which is the gate's silent-pass
# case. The `read` tail still honours CLAUDE_PROJECT_DIR while dropping
# WORKSPACE_ROOT — a pre-existing asymmetry, preserved deliberately.
corpflow_workspace_root() {
  local _cf_mode _cf_common _cf_parent
  _cf_mode="${1:-read}"
  _CORPFLOW_WS_ROOT=""
  if [ -n "${WORKSPACE_ROOT:-}" ] && [ -d "${WORKSPACE_ROOT}/.context" ]; then
    _CORPFLOW_WS_ROOT="${WORKSPACE_ROOT}"
    printf '%s' "$_CORPFLOW_WS_ROOT"; return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.context" ]; then
    _CORPFLOW_WS_ROOT="${CLAUDE_PROJECT_DIR}"
    printf '%s' "$_CORPFLOW_WS_ROOT"; return 0
  fi
  _cf_common=""
  _cf_common=$(git rev-parse --git-common-dir 2> /dev/null) || _cf_common=""
  if [ -n "$_cf_common" ]; then
    _cf_parent=$(cd "$(dirname "$_cf_common")" 2> /dev/null && pwd) || _cf_parent=""
    if [ -n "$_cf_parent" ] && [ -d "$_cf_parent/.context" ]; then
      _CORPFLOW_WS_ROOT="$_cf_parent"
      printf '%s' "$_CORPFLOW_WS_ROOT"; return 0
    fi
  fi
  if [ "$_cf_mode" = "write" ] && [ -n "${WORKSPACE_ROOT:-}" ]; then
    _CORPFLOW_WS_ROOT="${WORKSPACE_ROOT}"
    printf '%s' "$_CORPFLOW_WS_ROOT"; return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    _CORPFLOW_WS_ROOT="${CLAUDE_PROJECT_DIR}"
    printf '%s' "$_CORPFLOW_WS_ROOT"; return 0
  fi
  _CORPFLOW_WS_ROOT=$(pwd) || _CORPFLOW_WS_ROOT="."
  printf '%s' "$_CORPFLOW_WS_ROOT"
  return 0
}

# Echoes an absolute path to .context/. Read view of the resolver above; called
# as a plain function, not through $( ), so the hot path pays no extra fork.
corpflow_context_root() {
  corpflow_workspace_root read > /dev/null
  printf '%s' "${_CORPFLOW_WS_ROOT:-.}/.context"
  return 0
}

# Echoes the single in_progress stage code, or empty.
#
# Every ambiguity resolves to empty, never a guess: no state.json, no jq, an
# unparseable file, zero or more than one distinct stage, or an unrecognized
# token. Empty means there is no reliable "who is acting" answer.
corpflow_active_stage() {
  local _ctx="${1:-}" _state _stages
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
# whole decision keys on it. Match order: exactly one launched row for the agent
# id, else exactly one launched row for the stage, else empty — ambiguous is
# unresolved, never a guess. A settled dispatch (completed, failed) is not a live
# pin on either arm. A row without model_requested carries no pin.
corpflow_resolve_pin() {
  local _ctx="${1:-}" _stage="${2:-}" _agent_id="${3:-}" _state _out
  _state="$_ctx/state.json"
  [ -f "$_state" ] || { printf ''; return; }
  [ -n "$_stage" ] || { printf ''; return; }
  command -v jq > /dev/null 2>&1 || { printf ''; return; }

  _out=$(jq -r --arg stage "$_stage" --arg aid "$_agent_id" '
    (if (.facts|type=="object") and (.facts.dispatched_agents|type=="array")
       then .facts.dispatched_agents else [] end) as $rows
    | ( if ($aid | length) > 0
          then ($rows | map(select(.agent_id == $aid and .status == "launched")))
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
  _lower=$(printf '%s' "$_raw" | tr '[:upper:]' '[:lower:]') || _lower=""
  case "$_lower" in
    *opus*) printf 'opus' ;;
    *sonnet*) printf 'sonnet' ;;
    *haiku*) printf 'haiku' ;;
    *fable*) printf 'fable' ;;
    *) printf '' ;;
  esac
}

# The three ASSUMED-field coalesces (see model-switch-gate.sh's CONFIRMED/ASSUMED
# split), each written exactly once. The per-field accessors and the combined
# reader below all interpolate these, so the gate's decision and the audit row can
# never disagree about what a payload said, and a schema-drift fix is one edit.
_CORPFLOW_JQ_DEST='.to_model // .toModel // .requested_model // .requestedModel // .new_model // .newModel // ""'
_CORPFLOW_JQ_ORIGIN='.from_model // .fromModel // .current_model // .currentModel // ""'
_CORPFLOW_JQ_TRIGGER='.reason // .trigger // .source // ""'

# corpflow_switch_dest <payload> — echoes the destination model, or empty.
# corpflow_switch_origin <payload> — echoes the origin model, or empty.
#
# The single-field view. Hooks on the hot path use corpflow_switch_fields instead;
# these stay as the named, unit-tested API for one field at a time.
corpflow_switch_dest() {
  local _cf_payload _cf_out
  _cf_payload="${1:-}"
  [ -n "$_cf_payload" ] || { printf ''; return 0; }
  command -v jq > /dev/null 2>&1 || { printf ''; return 0; }
  _cf_out=$(printf '%s' "$_cf_payload" | jq -r "$_CORPFLOW_JQ_DEST" 2> /dev/null) || _cf_out=""
  printf '%s' "$_cf_out"
  return 0
}

corpflow_switch_origin() {
  local _cf_payload _cf_out
  _cf_payload="${1:-}"
  [ -n "$_cf_payload" ] || { printf ''; return 0; }
  command -v jq > /dev/null 2>&1 || { printf ''; return 0; }
  _cf_out=$(printf '%s' "$_cf_payload" | jq -r "$_CORPFLOW_JQ_ORIGIN" 2> /dev/null) || _cf_out=""
  printf '%s' "$_cf_out"
  return 0
}

# corpflow_switch_fields <payload> — echoes one TAB-separated line,
# `agent_id \t destination \t origin \t trigger`, or the EMPTY STRING when the
# payload is not parseable JSON. That empty answer folds the callers' separate
# `jq -e .` validity probe into this one, so a decision costs one jq over the
# payload instead of five.
#
# @tsv, not string interpolation: these are untrusted payload values, and @tsv
# escapes an embedded tab or newline rather than letting it invent a field. A
# parseable payload with none of the assumed fields yields three empty fields,
# which is a different answer from unparseable and must stay distinguishable.
corpflow_switch_fields() {
  local _cf_payload _cf_out
  _cf_payload="${1:-}"
  [ -n "$_cf_payload" ] || { printf ''; return 0; }
  command -v jq > /dev/null 2>&1 || { printf ''; return 0; }
  _cf_out=$(printf '%s' "$_cf_payload" | jq -r "
    [ (.agent_id // \"\"), ($_CORPFLOW_JQ_DEST), ($_CORPFLOW_JQ_ORIGIN), ($_CORPFLOW_JQ_TRIGGER) ]
    | map(tostring) | @tsv" 2> /dev/null) || _cf_out=""
  printf '%s' "$_cf_out"
  return 0
}

# corpflow_stage_and_pin <ctx> <agent_id> — echoes one TAB-separated line,
# `stage \t model_requested \t task_id`, with empty fields for every ambiguity.
#
# The combined view of corpflow_active_stage and corpflow_resolve_pin: both read
# the same state.json for the same decision, and the pin lookup needs the stage,
# so asking twice pays two jq processes to re-parse one file. Semantics are those
# two functions' exactly — every ambiguity resolves to empty, never a guess — and
# the parity is what the lib suite asserts.
corpflow_stage_and_pin() {
  local _cf_ctx _cf_aid _cf_state _cf_out
  _cf_ctx="${1:-}"
  _cf_aid="${2:-}"
  _cf_state="$_cf_ctx/state.json"
  [ -f "$_cf_state" ] || { printf ''; return 0; }
  command -v jq > /dev/null 2>&1 || { printf ''; return 0; }
  _cf_out=$(jq -r --arg aid "$_cf_aid" '
    (if (.tasks|type=="object") then
       (.tasks | to_entries | map(select(.value.status=="in_progress"))
         | map(.key | sub("[0-9]+$"; "")) | unique)
     else [] end) as $codes
    | (if ($codes|length) == 1 then $codes[0] else "" end) as $one
    | (if ($one | test("^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)$")) then $one else "" end) as $stage
    | (if (.facts|type=="object") and (.facts.dispatched_agents|type=="array")
         then .facts.dispatched_agents else [] end) as $rows
    | (if ($aid | length) > 0
         then ($rows | map(select(.agent_id == $aid and .status == "launched")))
         else [] end) as $byid
    | (if ($byid | length) == 1
         then $byid
         else ($rows | map(select(.stage == $stage and .status == "launched")))
       end) as $cand
    | (if ($stage | length) > 0 and ($cand | length) == 1
          and ((($cand[0].model_requested // "") | length) > 0)
          and ((($cand[0].task_id // "") | length) > 0)
        then [($cand[0].model_requested), ($cand[0].task_id)]
        else ["", ""] end) as $pin
    | [$stage, $pin[0], $pin[1]] | @tsv
  ' "$_cf_state" 2> /dev/null) || _cf_out=""
  printf '%s' "$_cf_out"
  return 0
}

# corpflow_hook_audit_row --ctx C --actor A --action ACT --result R --meta JSON [--subject S]
#
# Named apart from the row appender in skills/shared/lib/audit-lib.sh on purpose: the two
# shared one name until 4.0.29. They take incompatible flags (--ctx here, a file path there)
# and skip unknown ones silently, so a consumer of both got last-loaded-wins, and a call
# carrying the other's flags wrote nothing and returned 0. `readonly -f` below turns the
# opposite load order into a hard redefinition error instead. Two names cannot collide; one
# name with two shapes is the silent-write class this release set out to remove.
#
# Appends one row to <ctx>/logs/audit.jsonl. Returns 0 always, including on every
# refusal — an audit failure must never become a hook's exit code.
#
# Flag-parsed rather than positional on purpose: the three call-site shapes differ
# only in whether `subject` is present, and two adjacent free-form strings
# (`action`, `result`) in a positional signature make a transposition produce a
# VALID ROW THAT LIES, which is the worst failure an audit log has. `result` and
# `actor` are held to closed sets for the same reason: a transposition then drops
# the row loudly instead of recording a plausible falsehood.
#
# `subject` is emitted only when given and non-empty. That is a contract, not an
# optimisation: it forecloses `subject: ""` ever meaning "blank" rather than
# "absent", and it is what lets one writer serve test-execution-gate's
# subject-less rows and the model-switch hooks' subject-bearing ones.
#
# Malformed `--meta` degrades to {"_meta_invalid":true} rather than dropping the
# row: losing metadata beats losing a result:"block" row.
corpflow_hook_audit_row() {
  local _cf_ctx="" _cf_actor="" _cf_action="" _cf_result="" _cf_meta="" _cf_subject=""
  local _cf_dir _cf_file _cf_ts _cf_row
  while [ "$#" -gt 0 ]; do
    case "${1:-}" in
      --ctx)     _cf_ctx="${2:-}" ;;
      --actor)   _cf_actor="${2:-}" ;;
      --action)  _cf_action="${2:-}" ;;
      --result)  _cf_result="${2:-}" ;;
      --meta)    _cf_meta="${2:-}" ;;
      --subject) _cf_subject="${2:-}" ;;
      *) shift; continue ;;
    esac
    # Never `shift 2` blind: a flag given with no value would shift past $# and
    # abort a `set -e` caller from inside the appender.
    if [ "$#" -gt 1 ]; then shift 2; else shift; fi
  done

  [ -n "$_cf_ctx" ] || return 0
  [ -n "$_cf_action" ] || return 0
  command -v jq > /dev/null 2>&1 || return 0

  case "$_cf_actor" in hook:?*) : ;; *) return 0 ;; esac
  case "$_cf_result" in ok | block | degraded) : ;; *) return 0 ;; esac

  [ -n "$_cf_meta" ] || _cf_meta="{}"
  printf '%s' "$_cf_meta" | jq -e . > /dev/null 2>&1 || _cf_meta='{"_meta_invalid":true}'

  _cf_dir="$_cf_ctx/logs"
  _cf_file="$_cf_dir/audit.jsonl"
  mkdir -p "$_cf_dir" 2> /dev/null || return 0
  # A symlinked audit.jsonl would turn this append into a write primitive against
  # an arbitrary target.
  [ ! -L "$_cf_file" ] || return 0
  _cf_ts=$(date -u +%FT%TZ 2> /dev/null) || _cf_ts="unknown"
  [ -n "$_cf_ts" ] || _cf_ts="unknown"

  # Key order is pinned by construction, not by jq's sort: assert with
  # keys_unsorted, never keys.
  _cf_row=$(jq -cn --arg ts "$_cf_ts" --arg actor "$_cf_actor" --arg action "$_cf_action" \
    --arg subject "$_cf_subject" --arg result "$_cf_result" --argjson meta "$_cf_meta" '
    {ts: $ts, actor: $actor, action: $action}
    + (if ($subject | length) > 0 then {subject: $subject} else {} end)
    + {result: $result, metadata: $meta}
  ' 2> /dev/null) || return 0
  { printf '%s\n' "$_cf_row" >> "$_cf_file"; } 2> /dev/null || return 0
  return 0
}

# readonly -f makes self-test isolation un-violable rather than merely checkable:
# a body that tried to redefine a library symbol is refused, the original survives,
# and the refusal does not abort a `set -e` shell. Requires the include guard above.
readonly -f corpflow_workspace_root corpflow_context_root corpflow_active_stage \
  corpflow_resolve_pin corpflow_stage_and_pin corpflow_model_family \
  corpflow_switch_dest corpflow_switch_origin corpflow_switch_fields \
  corpflow_hook_audit_row
