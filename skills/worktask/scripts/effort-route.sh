#!/usr/bin/env bash
# @description effort-route.sh — the route decision: whether a dispatch runs in-process at its
#   baseline tier or headless at a raised/lowered stamped tier.
#   Pure: reads the target agent's own frontmatter file and the caller's environment, writes
#   nothing, spawns nothing. headless-dispatch.sh consumes its `route` field; the orchestrator's
#   Step C.0a resolver and Step C.3 batch resolver both call this before choosing a surface.
#
#   Rule: route "headless" iff the stamped (requested) tier differs from the agent's baseline
#   tier, in EITHER direction — a lowering is as much a routed decision as a raise, because a
#   lowering is an explicit `CORPFLOW.md § Models` / `state.models` choice and skipping it would
#   leave `effort_resolved != stamped` for that case too. Two short-circuits, checked in this
#   order, always win over the comparison and always answer "inproc":
#     1. haiku ignores effort tiers outright (model-selection.md § xhigh routing neighbours).
#     2. CORPFLOW_HEADLESS_ROUTE=off is the one operator opt-out.
#   Per-stage routing outranks an operator-set CLAUDE_CODE_EFFORT_LEVEL (sw-AR0-1, FN-gate
#   decision): the env pin no longer short-circuits the route, and the headless child's own env
#   still carries CLAUDE_CODE_EFFORT_LEVEL=<stamped tier>.
#   Baseline comes from the target agent's own `effort:` frontmatter when the file has one
#   (`baseline_source: frontmatter`); a frontmatter-less agent (a platform-plugin stage agent)
#   needs the caller to pass the corpflow role's matrix tier explicitly via --role-baseline,
#   since this script has no notion of "which role a platform agent stands in for" — that
#   mapping lives in pl0-procedure.md, not here.
#
#   Symbols: none exported — this file is a CLI, never sourced (unlike effort-ladder.sh).
#
# @exitcode 2 usage error, invalid enum value, or an unresolved baseline
#
# Minimum shell: bash 3.2+ (macOS default) — no associative arrays, no `local -n`.

set -euo pipefail

_ER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=effort-ladder.sh
. "${_ER_DIR}/effort-ladder.sh"

# Three levels up from skills/worktask/scripts/ is the plugin root — same derivation
# model-matrix-lib.sh uses, so a caller that sources neither still gets the live agents/ tree.
_ER_PLUGIN_ROOT="$(cd "${_ER_DIR}/../../.." && pwd)"
_ER_DEFAULT_AGENTS_DIR="${_ER_PLUGIN_ROOT}/agents"

# Model aliases the route function accepts. `haiku` is here (it is a valid alias, just one
# effort ignores), `fable` too — the matrix's MODEL_ENUM omits it, but effort-ladder.sh's
# EFFORT_FULL_LADDER_RE already treats it as a full-ladder model, so this file's own enum
# must agree rather than re-derive a second list that could drift from it.
_ER_MODEL_ENUM_RE='^(opus|sonnet|haiku|fable)$'
_ER_AGENT_ID_RE='^[a-z0-9-]+:[a-z0-9-]+$'

usage() {
  cat >&2 << 'EOF2'
usage:
  effort-route.sh --agent <plugin:agent> --model <alias> --requested <tier>
                   [--agents-dir <dir>] [--role-baseline <tier>]

Prints one JSON route-decision line and exits 0, or exits 2 with an
error on stderr before printing anything.
EOF2
  exit 2
}

AGENT=""
MODEL=""
REQUESTED=""
AGENTS_DIR="$_ER_DEFAULT_AGENTS_DIR"
ROLE_BASELINE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --requested) REQUESTED="${2:-}"; shift 2 ;;
    --agents-dir) AGENTS_DIR="${2:-}"; shift 2 ;;
    --role-baseline) ROLE_BASELINE="${2:-}"; shift 2 ;;
    -h | --help) usage ;;
    *)
      printf >&2 'effort-route.sh: unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

[ -n "$AGENT" ] && [ -n "$MODEL" ] && [ -n "$REQUESTED" ] || usage

# --- validation before anything else is computed (fail closed before the spawn) -------------
if ! [[ "$AGENT" =~ $_ER_AGENT_ID_RE ]]; then
  printf >&2 'effort-route.sh: invalid agent id: %s\n' "$AGENT"
  exit 2
fi
if ! [[ "$MODEL" =~ $_ER_MODEL_ENUM_RE ]]; then
  printf >&2 'effort-route.sh: invalid model: %s\n' "$MODEL"
  exit 2
fi
if ! effort_rank "$REQUESTED" > /dev/null 2>&1; then
  printf >&2 'effort-route.sh: invalid requested effort: %s\n' "$REQUESTED"
  exit 2
fi
if [ -n "$ROLE_BASELINE" ] && ! effort_rank "$ROLE_BASELINE" > /dev/null 2>&1; then
  printf >&2 'effort-route.sh: invalid role-baseline effort: %s\n' "$ROLE_BASELINE"
  exit 2
fi

_ER_BARE="${AGENT##*:}"

# _er_agent_frontmatter_effort <file> -> the `effort:` scalar between the first two `---`
# fences, or empty. Deliberately NOT frontmatter-lib.sh's corpflow_fm_field: that reader is
# scoped to a `handoff:` block's nested keys, and an agent file's `effort:` sits at the
# frontmatter's own top level, beside `maxTurns:` — a different shape, so a different (much
# smaller) reader, rather than stretching the handoff reader to cover a key it was never
# written for.
_er_agent_frontmatter_effort() {
  local file="$1"
  [ -r "$file" ] || return 1
  awk '
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && /^effort:[[:space:]]*/ {
      sub(/^effort:[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$file" 2> /dev/null
}

BASELINE=""
BASELINE_SOURCE=""
_ER_AGENT_FILE="${AGENTS_DIR}/${_ER_BARE}.md"
if [ -f "$_ER_AGENT_FILE" ]; then
  _ER_FM_EFFORT="$(_er_agent_frontmatter_effort "$_ER_AGENT_FILE")"
  if [ -n "$_ER_FM_EFFORT" ] && effort_rank "$_ER_FM_EFFORT" > /dev/null 2>&1; then
    BASELINE="$_ER_FM_EFFORT"
    BASELINE_SOURCE="frontmatter"
  fi
fi
if [ -z "$BASELINE" ] && [ -n "$ROLE_BASELINE" ]; then
  BASELINE="$ROLE_BASELINE"
  BASELINE_SOURCE="role_matrix"
fi
if [ -z "$BASELINE" ]; then
  printf >&2 \
    'effort-route.sh: %s carries no effort: frontmatter and no --role-baseline was given\n' \
    "$AGENT"
  exit 2
fi

# --- short-circuits, each answers inproc regardless of the tier compare below ----------------
ROUTE="inproc"
REASON=""
TRANSPORT=""

# The in-process transport literal when a short-circuit or an equal-tier compare keeps the
# dispatch in-process: "frontmatter" when the baseline came from the agent's own file (Task()
# picks it up), "none" when it came from --role-baseline (no frontmatter to fall back to).
_er_inproc_transport() {
  if [ "$BASELINE_SOURCE" = "frontmatter" ]; then
    printf 'frontmatter'
  else
    printf 'none'
  fi
}

if [ "$MODEL" = "haiku" ]; then
  ROUTE="inproc"
  REASON="model_ignores_effort"
  TRANSPORT="none"
elif [ "${CORPFLOW_HEADLESS_ROUTE:-}" = "off" ]; then
  ROUTE="inproc"
  REASON="opted_out"
  TRANSPORT="$(_er_inproc_transport)"
elif [ "$REQUESTED" = "$BASELINE" ]; then
  ROUTE="inproc"
  REASON="tier_equal"
  TRANSPORT="$(_er_inproc_transport)"
else
  ROUTE="headless"
  REASON="tier_differs"
  TRANSPORT="dispatch-flag"
fi

if command -v jq > /dev/null 2>&1; then
  jq -cn \
    --arg agent "$AGENT" --arg model "$MODEL" --arg requested "$REQUESTED" \
    --arg baseline "$BASELINE" --arg baseline_source "$BASELINE_SOURCE" \
    --arg route "$ROUTE" --arg transport "$TRANSPORT" --arg reason "$REASON" \
    '{agent:$agent, model:$model, requested:$requested, baseline:$baseline,
      baseline_source:$baseline_source, route:$route, effort_transport:$transport,
      reason:$reason}'
else
  # jq-less degraded form: every value here already passed an enum/regex gate above, so a
  # bare printf cannot break the literal the way an unvalidated string would.
  printf '{"agent":"%s","model":"%s","requested":"%s","baseline":"%s","baseline_source":"%s","route":"%s","effort_transport":"%s","reason":"%s"}\n' \
    "$AGENT" "$MODEL" "$REQUESTED" "$BASELINE" "$BASELINE_SOURCE" "$ROUTE" "$TRANSPORT" "$REASON"
fi
