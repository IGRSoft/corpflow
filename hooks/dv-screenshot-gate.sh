#!/usr/bin/env bash
# dv-screenshot-gate — SubagentStop gate: a stopping DV stream must leave visual evidence
# keyed by its own task id. No matcher in plugin.json; the gate scopes itself from the ledger.
#
# Usage:
#   dv-screenshot-gate.sh                live hook, payload on stdin. Exit is always 0; a block
#                                        travels as decision:block JSON with additionalContext.
#   dv-screenshot-gate.sh --check <TASK_ID> [--state <state.json>]
#                                        pure classifier: prints one line
#                                        `class=<name> task=<ID> manifest=<path|-> reason=<text>`,
#                                        writes nothing. Exit 0 captured, 1 invalid, 2 usage or
#                                        unresolved, 3 no_captures, 4 tool_missing_only. Exit 4 is
#                                        NOT resolve-worktask.sh's "unresolved"; never chain on rc.
#   dv-screenshot-gate.sh --self-test
#
# Scope: the task of the payload agent_id in facts.dispatched_agents[]; else the sole in_progress
# DV task whose metadata.agent is the payload agent_type (corpflow:developer matches any DV task).
# No-op when no DV task is in progress or no DV task names that agent_type; any other miss blocks.
# Evidence: images/<worktask_id>/screenshots-<TASK_ID>.md, else the `## <TASK_ID>` section of the
# legacy screenshots.md. Row grammar is owned by attach-visual-evidence.sh --validate-manifest.
# Classes 3 and 4 pass only on backend/systems: a task with no UI has nothing a missing capture
# tool could have shown. jq absent: live exit 0, --check exit 2.
set -eu

MODE=live
CHECK_TASK=""
CHECK_STATE=""
TASK_RE='^[A-Z]{2}[0-9]+$'
WID_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'

emit_class() { # <class> <task> <manifest> <reason>
  printf 'class=%s task=%s manifest=%s reason=%s\n' "$1" "$2" "$3" "$(printf '%s' "$4" | tr '\n' ' ')"
}

check_usage() {
  emit_class usage "${CHECK_TASK:--}" - "$1"
  exit 2
}

case "${1:-}" in
  --self-test) MODE=selftest ;;
  --check)
    MODE=check
    shift
    CHECK_TASK="${1:-}"
    if [ "$#" -gt 0 ]; then shift; fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --state)
          CHECK_STATE="${2:-}"
          [ -n "$CHECK_STATE" ] || check_usage "--state needs a path"
          shift 2
          ;;
        *) check_usage "unknown argument: $1" ;;
      esac
    done
    ;;
esac

_GATE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" 2> /dev/null && pwd -P)"
VALIDATOR="$_GATE_DIR/../skills/worktask/scripts/attach-visual-evidence.sh"

# Guarded source of the shared root ladder.
_LIB="$(dirname "$0")/model-switch-lib.sh"
_CF_OPTS=$-
set +e
# shellcheck source=hooks/model-switch-lib.sh
[ -f "$_LIB" ] && . "$_LIB"
case "$_CF_OPTS" in *e*) set -e ;; esac

resolve_ctx() {
  if command -v corpflow_context_root > /dev/null 2>&1; then
    corpflow_context_root
    return 0
  fi
  # Degraded: declared roots only, requiring an existing ledger — never cwd.
  if [ -n "${WORKSPACE_ROOT:-}" ] && [ -f "${WORKSPACE_ROOT}/.context/state.json" ]; then
    printf '%s' "${WORKSPACE_ROOT}/.context"
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/.context/state.json" ]; then
    printf '%s' "${CLAUDE_PROJECT_DIR}/.context"
  fi
}

# classify_task <ctx> <worktask_id> <task_id> — sets G_CLASS G_REASON G_MANIFEST G_DETAIL G_TOOLS
# and returns the class exit code. Reads only; the images-beside count catches captures that no
# row references, which the validator cannot see.
classify_task() {
  local ctx="$1" wid="$2" tid="$3" img mf out rc beside
  G_MANIFEST="-"
  G_DETAIL=""
  G_TOOLS=""
  img="$ctx/images/$wid"
  mf=""
  if [ -f "$img/screenshots-$tid.md" ]; then
    mf="$img/screenshots-$tid.md"
  elif [ -f "$img/screenshots.md" ]; then
    mf="$img/screenshots.md"
  fi
  rc=2
  out="manifest not found"
  if [ -n "$mf" ]; then
    G_MANIFEST="$mf"
    if [ ! -f "$VALIDATOR" ]; then
      G_CLASS=usage
      G_REASON="manifest validator not found at $VALIDATOR"
      return 2
    fi
    out=$(bash "$VALIDATOR" --validate-manifest "$mf" --task-id "$tid" --images-dir "$img" 2> /dev/null) && rc=0 || rc=$?
  fi
  G_DETAIL="$out"
  beside=$(find "$img" -maxdepth 1 -type f \( -name "dv-$tid-*.png" -o -name "dv-$tid-*.jpg" \
    -o -name "dv-$tid-*.jpeg" -o -name "dv-$tid-*.webp" \) 2> /dev/null | grep -c . || true)

  case "$rc" in
    0)
      G_CLASS=captured
      G_REASON="valid capture rows"
      return 0
      ;;
    1)
      G_CLASS=invalid
      G_REASON=$(printf '%s\n' "$out" | grep -m1 '^line [0-9]*:' || printf '%s\n' "$out" | head -1)
      return 1
      ;;
    2 | 3)
      case "$out" in
        "manifest not found"* | *"carries no canonical capture rows"*) ;;
        *)
          G_CLASS=usage
          G_REASON="manifest validator exit $rc"
          return 2
          ;;
      esac
      ;;
    4)
      G_TOOLS=$(printf '%s\n' "$out" | sed -n 's/^tool_missing_only tools=//p' | head -1)
      if [ -z "$G_TOOLS" ]; then
        G_CLASS=usage
        G_REASON="manifest validator reported tool_missing_only without tools"
        return 2
      fi
      ;;
    *)
      G_CLASS=usage
      G_REASON="manifest validator exit $rc"
      return 2
      ;;
  esac

  if [ "${beside:-0}" -gt 0 ]; then
    G_CLASS=invalid
    G_REASON="images_unreferenced: ${beside} dv-$tid-* image(s) on disk but no capture row names them"
    return 1
  fi
  if [ "$rc" -eq 4 ]; then
    G_CLASS=tool_missing_only
    G_REASON="only tool_missing rows ($G_TOOLS)"
    return 4
  fi
  G_CLASS=no_captures
  G_REASON="no capture rows and no dv-$tid-* images"
  return 3
}

run_check() {
  local state ctx wid rc=0
  [[ $CHECK_TASK =~ $TASK_RE ]] || check_usage "task id must match ^[A-Z]{2}[0-9]+\$"
  command -v jq > /dev/null 2>&1 || check_usage "jq not found"
  if [ -n "$CHECK_STATE" ]; then
    state="$CHECK_STATE"
    ctx="$(dirname -- "$state")"
  else
    ctx="$(resolve_ctx)"
    state="$ctx/state.json"
  fi
  { [ -n "$ctx" ] && [ -f "$state" ]; } || check_usage "state.json unresolved"
  wid=$(jq -r 'if (.worktask_id|type) == "string" then .worktask_id else "" end' "$state" 2> /dev/null) || wid=""
  [[ $wid =~ $WID_RE ]] || check_usage "worktask_id unresolved in $state"
  classify_task "$ctx" "$wid" "$CHECK_TASK" || rc=$?
  emit_class "$G_CLASS" "$CHECK_TASK" "$G_MANIFEST" "$G_REASON"
  exit "$rc"
}

# Prints `<noop|task|unresolved>\t<task id or ->`.
# shellcheck disable=SC2016  # jq programs: $names are jq variables, not shell expansions
SCOPE_JQ='
  (if (.facts|type) == "object" and (.facts.dispatched_agents|type) == "array"
     then .facts.dispatched_agents else [] end) as $rows
  | (if (.tasks|type) == "object" then .tasks else {} end) as $tasks
  | ([ $rows[] | select(type == "object" and $aid != "" and .agent_id == $aid)
       | .task_id | strings ] | unique) as $hit
  | if ($hit|length) == 1 then
      (if ($hit[0] | sub("[0-9]+$"; "")) == "DV" then "task\t\($hit[0])" else "noop\t-" end)
    elif ($hit|length) > 1 then "unresolved\t-"
    else
      [ $tasks | to_entries[] | select(.key | test("^DV[0-9]+$")) ] as $dv
      | [ $dv[] | select(.value.status? == "in_progress") ] as $live
      | if ($live|length) == 0 then "noop\t-"
        else
          (if $atype == "corpflow:developer" then $live
           else [ $live[] | select((.value.metadata.agent? // "") == $atype) ] end) as $cand
          | if ($cand|length) == 1 then "task\t\($cand[0].key)"
            elif ($cand|length) > 1 then "unresolved\t-"
            elif ([ $dv[] | select((.value.metadata.agent? // "") == $atype) ] | length) == 0 then "noop\t-"
            else "unresolved\t-" end
        end
    end'

# Task flag, then ledger flag, then true; `has` so a literal false survives.
# shellcheck disable=SC2016
FLAG_JQ='
  def flag(o): if (o|type) == "object" and (o|has("requires_screenshots"))
               then (o.requires_screenshots|tostring) else empty end;
  [ (if $t != "" then flag(.tasks[$t].metadata?) else empty end), flag(.metadata?), "true" ] | .[0]'

# append_row <payload> <log_dir> <action> <result> <metadata-json>
append_row() {
  local row
  row=$(printf '%s' "$1" | jq -c --arg ts "$(date -u +%FT%TZ)" --arg action "$3" --arg result "$4" \
    --argjson meta "$5" '
    {
      ts: $ts,
      actor: "hook:dv-screenshot-gate",
      action: $action,
      subject: (.agent_type // "unknown"),
      result: $result,
      metadata: ($meta + {
        dedupe_key: ((.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":screenshot-gate")
      })
    }') || {
    echo "dv-screenshot-gate: jq parse failed" >&2
    return 0
  }
  # Best-effort writes: under set -e a failure here would exit non-zero after the block JSON,
  # and a non-zero hook exit is non-blocking, so the stop would pass.
  mkdir -p "$2" || true
  # A symlinked audit.jsonl would turn this append into a write primitive; losing the row never unblocks.
  if [ ! -L "$2/audit.jsonl" ]; then
    printf '%s\n' "$row" >> "$2/audit.jsonl" || true
  fi
}

# gate_pass <payload> <ctx> <wid> <task> <class> <platform> <reason>
gate_pass() {
  append_row "$1" "$2/logs" screenshot_gate_pass ok "$(jq -cn --arg w "$3" --arg t "$4" \
    --arg c "$5" --arg p "$6" --arg r "$7" \
    '{worktask_id: $w, task_id: $t, class: $c, platform: $p, reason: $r}')"
}

# gate_block <payload> <ctx> <wid> <task> <class> <platform> <kind> <reason> <context>
gate_block() {
  jq -cn --arg reason "$8" --arg ac "$9" '
    {decision: "block", reason: $reason,
     hookSpecificOutput: {hookEventName: "SubagentStop", additionalContext: $ac}}' || {
    echo "dv-screenshot-gate: jq parse failed" >&2
    return 0
  }
  append_row "$1" "$2/logs" screenshot_gate_block block "$(jq -cn --arg w "$3" --arg t "$4" \
    --arg c "$5" --arg p "$6" --arg k "$7" --arg r "$8" --arg m "${G_MANIFEST:--}" \
    '{worktask_id: $w, task_id: $t, class: $c, platform: $p, block_kind: $k, reason: $r, missing_manifest: $m}')"
}

run_gate() {
  local payload="$1" ctx="$2" state="$2/state.json" aid atype scope verdict tid flag platform wid rc
  local capture="run the dv-screenshot-capture skill with this task_id; it picks the adapter for the platform and falls back to cli/fallback, so headless is not a skip reason"
  [ -f "$state" ] || return 0
  aid=$(printf '%s' "$payload" | jq -r '.agent_id // "" | strings' 2> /dev/null || true)
  atype=$(printf '%s' "$payload" | jq -r '.agent_type // "unknown" | strings' 2> /dev/null || echo unknown)

  if ! scope=$(jq -r --arg aid "$aid" --arg atype "$atype" "$SCOPE_JQ" "$state" 2> /dev/null); then
    [ "$atype" = "corpflow:developer" ] || return 0
    gate_block "$payload" "$ctx" unknown - usage unknown gate_unresolved \
      "gate_unresolved — state.json is not readable JSON" "Repair $state; the evidence gate cannot scope this stop without it."
    return 0
  fi
  verdict="${scope%%	*}"
  tid="${scope#*	}"
  case "$verdict" in
    noop) return 0 ;;
    task) ;;
    *) tid="" ;;
  esac

  wid=$(jq -r 'if (.worktask_id|type) == "string" then .worktask_id else "" end' "$state" 2> /dev/null || true)
  flag=$(jq -r --arg t "$tid" "$FLAG_JQ" "$state" 2> /dev/null || echo true)

  if [ -z "$tid" ]; then
    if [ "$flag" = "false" ]; then
      gate_pass "$payload" "$ctx" "$wid" - unresolved unknown "requires_screenshots=false"
      return 0
    fi
    gate_block "$payload" "$ctx" "$wid" - unresolved unknown task_unresolved \
      "task_unresolved — could not tell which DV task stopped (agent_id $aid not in facts.dispatched_agents, agent_type $atype ambiguous)" \
      "Record this agent in facts.dispatched_agents with its task_id, or keep exactly one in_progress DV task per agent; then $capture."
    return 0
  fi

  platform=$(jq -r --arg t "$tid" '(.tasks[$t].metadata.platform? | strings) // (.platform | strings) // "unknown"' \
    "$state" 2> /dev/null || echo unknown)
  if [ "$flag" = "false" ]; then
    gate_pass "$payload" "$ctx" "$wid" "$tid" unclassified "$platform" "requires_screenshots=false"
    return 0
  fi
  if ! [[ $wid =~ $WID_RE ]]; then
    gate_block "$payload" "$ctx" "$wid" "$tid" usage "$platform" gate_unresolved \
      "gate_unresolved — state.json worktask_id is missing or malformed" "Repair .worktask_id in $state."
    return 0
  fi

  rc=0
  classify_task "$ctx" "$wid" "$tid" || rc=$?
  case "$rc" in
    0)
      gate_pass "$payload" "$ctx" "$wid" "$tid" "$G_CLASS" "$platform" "captured"
      ;;
    1)
      gate_block "$payload" "$ctx" "$wid" "$tid" "$G_CLASS" "$platform" invalid_evidence \
        "invalid_evidence — $G_REASON" \
        "$G_DETAIL
Fix the rows for $tid in $G_MANIFEST: Path is a basename dv-$tid-NN-<slug>.<png|jpg|jpeg|webp> whose NN equals #, the file is a real image beside the manifest, and every capture on disk has a row."
      ;;
    3)
      case "$platform" in
        backend | systems)
          gate_pass "$payload" "$ctx" "$wid" "$tid" "$G_CLASS" "$platform" "no captures on $platform"
          ;;
        *)
          gate_block "$payload" "$ctx" "$wid" "$tid" "$G_CLASS" "$platform" no_captures \
            "no_captures — task $tid on platform $platform has no capture rows" \
            "$capture; expected manifest $ctx/images/$wid/screenshots-$tid.md"
          ;;
      esac
      ;;
    4)
      case "$platform" in
        backend | systems)
          gate_pass "$payload" "$ctx" "$wid" "$tid" "$G_CLASS" "$platform" "tool_missing on $platform"
          ;;
        *)
          gate_block "$payload" "$ctx" "$wid" "$tid" "$G_CLASS" "$platform" tool_missing_ui \
            "tool_missing_ui — $tid on platform $platform has only tool_missing rows ($G_TOOLS)" \
            "A tool_missing row passes only on backend/systems. Install a capture tool and $capture."
          ;;
      esac
      ;;
    *)
      gate_block "$payload" "$ctx" "$wid" "$tid" "${G_CLASS:-usage}" "$platform" gate_unresolved \
        "gate_unresolved — ${G_REASON:-classifier exit $rc}" "Repair the plugin install or the ledger so $tid can be classified."
      ;;
  esac
  return 0
}

if [ "$MODE" = "check" ]; then
  run_check
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "dv-screenshot-gate: jq not found, skipping" >&2
  exit 0
fi

# Body lives in lib/, sourced only here; it fails CLOSED when its cases are missing.
if [ "$MODE" = "selftest" ]; then
  _selftest_body="$(dirname "$0")/lib/dv-screenshot-gate-selftest.sh"
  if [ ! -f "$_selftest_body" ]; then
    echo "dv-screenshot-gate: self-test body missing at $_selftest_body" >&2
    exit 1
  fi
  # shellcheck source=hooks/lib/dv-screenshot-gate-selftest.sh
  . "$_selftest_body"
fi

PAYLOAD=$(cat)
CTX="$(resolve_ctx)"
[ -n "$CTX" ] || exit 0

run_gate "$PAYLOAD" "$CTX"
exit 0
