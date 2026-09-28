#!/usr/bin/env bash
# Resolve a generic Codex SubagentStop to Corpflow's stage-specific completion hook.
set -u

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 0
# shellcheck source=hooks/lib/corpflow-base.sh
. "$SELF_DIR/lib/corpflow-base.sh" || exit 0

PAYLOAD_FILE=$(mktemp "${TMPDIR:-/tmp}/corpflow-codex-stop.XXXXXX") || exit 0
NORMALIZED_FILE=$(mktemp "${TMPDIR:-/tmp}/corpflow-codex-stop-normalized.XXXXXX") || {
  rm -f "$PAYLOAD_FILE"
  exit 0
}
trap 'rm -f "$PAYLOAD_FILE" "$NORMALIZED_FILE"' EXIT
cat > "$PAYLOAD_FILE"
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD_CWD=$(jq -r '.cwd // empty | strings' "$PAYLOAD_FILE" 2>/dev/null) || PAYLOAD_CWD=""
corpflow_init_base_paths "$PAYLOAD_CWD" || exit 0
STATE="${WORKSPACE_ROOT:-}/.context/state.json"
[ -f "$STATE" ] || exit 0

AGENT_ID=$(jq -r '.agent_id // empty | strings' "$PAYLOAD_FILE" 2>/dev/null) || AGENT_ID=""
[ -n "$AGENT_ID" ] || exit 0
ROW=$(jq -c --arg aid "$AGENT_ID" '[.facts.dispatched_agents[]? | select(.agent_id == $aid)][-1] // empty' "$STATE" 2>/dev/null) || ROW=""
[ -n "$ROW" ] || exit 0
STAGE=$(printf '%s' "$ROW" | jq -r '.stage // empty')
case "$STAGE" in PL|FN|ST) ;; *) exit 0 ;; esac
AGENT_TYPE=$(printf '%s' "$ROW" | jq -r '.subagent_type // "unknown"')

jq --arg at "$AGENT_TYPE" '.agent_type = $at' "$PAYLOAD_FILE" > "$NORMALIZED_FILE" 2>/dev/null || exit 0
BASE_TASK_STAGE="$STAGE"
BASE_AGENT_NAME="$AGENT_TYPE"
BASE_TASK_ID=$(printf '%s' "$ROW" | jq -r '.task_id // empty')
export BASE_TASK_STAGE BASE_AGENT_NAME BASE_TASK_ID
CLAUDE_PLUGIN_ROOT="$BASE_PLUGIN_ROOT"
CLAUDE_PROJECT_DIR="${WORKSPACE_ROOT:-}"
export CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR

exec bash "$BASE_PLUGIN_ROOT/hooks/agent-stop.sh" --stage "$STAGE" < "$NORMALIZED_FILE"
