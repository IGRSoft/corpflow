#!/usr/bin/env bash
# Stop event multiplexer for PL/FN/ST worktask-boundary agents (v3.10.0+).
# Wired via agent frontmatter `hooks:`.
#
# Writes one canonical `stage_completion_hook` row to
# .context/logs/audit.jsonl. PushNotification at PL/FN approval gates is
# handled by the sibling `type: "mcp_tool"` hook entry in plugin.json —
# keeping this bash hook portable (no MCP server dependency).
set -eu

STAGE="unknown"
SELF_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) shift; STAGE="${1:-unknown}" ;;
    --self-test) SELF_TEST=1 ;;
  esac
  shift
done

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' '{"agent_type":"company-workflow:product-manager","agent_id":"agt_pl","session_id":"sess_test","parent_agent_id":"agt_parent","background_tasks":[{"id":"bg1"},{"id":"bg2"}],"session_crons":[{"id":"cr1"}]}'
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "agent-stop: jq not found, skipping" >&2
  exit 0
fi

PAYLOAD=$(read_stdin)
LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.context/logs"
mkdir -p "$LOG_DIR"

ROW=$(printf '%s' "$PAYLOAD" | jq -c \
  --arg ts "$(date -u +%FT%TZ)" \
  --arg stage "$STAGE" '
  {
    ts: $ts,
    actor: "hook:agent-stop",
    action: "stage_completion_hook",
    subject: (.agent_type // "unknown"),
    result: "ok",
    metadata: {
      stage: $stage,
      effort: (.effort.level // env.CLAUDE_EFFORT // "unknown"),
      parent_agent_id: (.parent_agent_id // "none"),
      background_tasks_count: ((.background_tasks // []) | length),
      background_task_ids: ((.background_tasks // []) | map(.id // .task_id // "unknown")),
      session_crons_count: ((.session_crons // []) | length),
      session_cron_ids: ((.session_crons // []) | map(.id // .cron_id // "unknown")),
      dedupe_key: ((.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":stage:" + $stage),
      dedupe_key_extended: ((.parent_agent_id // "none") + ":" + (.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":stage:" + $stage)
    }
  }') || {
    echo "agent-stop: jq parse failed" >&2
    exit 0
  }

if [ "$SELF_TEST" -eq 1 ]; then
  printf '%s\n' "$ROW" | jq -e '
    .action == "stage_completion_hook"
    and (.metadata.stage | type) == "string"
    and (.metadata.dedupe_key | startswith("sess_test:agt_pl:stage:"))
    and .metadata.parent_agent_id == "agt_parent"
    and .metadata.background_tasks_count == 2
    and .metadata.background_task_ids == ["bg1","bg2"]
    and .metadata.session_crons_count == 1
    and .metadata.session_cron_ids == ["cr1"]
    and (.metadata.dedupe_key_extended | startswith("agt_parent:sess_test:agt_pl:stage:"))
  ' >/dev/null \
    || { echo "agent-stop: self-test FAIL"; exit 1; }
  echo "agent-stop: self-test OK"
  exit 0
fi

printf '%s\n' "$ROW" >> "$LOG_DIR/audit.jsonl"
exit 0
