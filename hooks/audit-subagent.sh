#!/usr/bin/env bash
# SubagentStop → audit.jsonl writer (igrsoft worktask plugin, v3.10.0+).
# Replaces prose-instructed `subagent_stopped` row emission. Pairs with
# cost-log.sh; both fire on SubagentStop, both target .context/logs/.
#
# Dedupe: metadata.dedupe_key = "<session_id>:<agent_id>:stop".
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' '{"agent_type":"igrsoft:developer","agent_id":"agt_test","session_id":"sess_test","duration_ms":12345,"parent_agent_id":"agt_parent","background_tasks":[{"id":"bg1"},{"id":"bg2"}],"session_crons":[{"id":"cr1"}]}'
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "audit-subagent: jq not found, skipping" >&2
  exit 0
fi

PAYLOAD=$(read_stdin)
LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.context/logs"
mkdir -p "$LOG_DIR"

ROW=$(printf '%s' "$PAYLOAD" | jq -c \
  --arg ts "$(date -u +%FT%TZ)" '
  {
    ts: $ts,
    actor: "hook:audit-subagent",
    action: "subagent_stopped",
    subject: (.agent_type // "unknown"),
    result: (.status // "ok"),
    metadata: {
      duration_ms: ((.duration_ms // 0) | tonumber? // 0),
      effort: (.effort.level // env.CLAUDE_EFFORT // "unknown"),
      parent_agent_id: (.parent_agent_id // "none"),
      background_tasks_count: ((.background_tasks // []) | length),
      background_task_ids: ((.background_tasks // []) | map(.id // .task_id // "unknown")),
      session_crons_count: ((.session_crons // []) | length),
      session_cron_ids: ((.session_crons // []) | map(.id // .cron_id // "unknown")),
      dedupe_key: ((.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":stop"),
      dedupe_key_extended: ((.parent_agent_id // "none") + ":" + (.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":stop")
    }
  }') || {
    echo "audit-subagent: jq parse failed" >&2
    exit 0
  }

if [ "$SELF_TEST" -eq 1 ]; then
  printf '%s\n' "$ROW" | jq -e '
    .metadata.dedupe_key == "sess_test:agt_test:stop"
    and .subject == "igrsoft:developer"
    and .metadata.parent_agent_id == "agt_parent"
    and .metadata.background_tasks_count == 2
    and .metadata.background_task_ids == ["bg1","bg2"]
    and .metadata.session_crons_count == 1
    and .metadata.session_cron_ids == ["cr1"]
    and .metadata.dedupe_key_extended == "agt_parent:sess_test:agt_test:stop"
  ' >/dev/null \
    || { echo "audit-subagent: self-test FAIL"; exit 1; }
  echo "audit-subagent: self-test OK"
  exit 0
fi

printf '%s\n' "$ROW" >> "$LOG_DIR/audit.jsonl"
exit 0
