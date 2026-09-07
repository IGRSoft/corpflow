#!/usr/bin/env bash
# SubagentStop → audit.jsonl writer (corpflow worktask plugin).
# Replaces prose-instructed `subagent_stopped` row emission. Pairs with
# state-merge.sh; both fire on SubagentStop, both target .context/.
#
# Dedupe: metadata.dedupe_key = "<session_id>:<agent_id>:stop".
#
# The runtime sends `agent_type: ""` (not null) for plugin agents, so `//` alone
# leaves the row anonymous. Reader-keyed fields go through `first_nonempty`,
# which rejects "" as well as null.
set -eu

SELF_TEST=0
if [ "${1:-}" = "--self-test" ]; then
  SELF_TEST=1
  # Cleared in the parent shell, not in read_stdin's subshell: jq inherits from
  # here, so the identity/stage ladder must resolve to its terminal fallback.
  unset CLAUDE_SUBAGENT_TYPE CLAUDE_TASK_METADATA_STAGE || true
fi

# The self-test payload carries the empty-string identity the runtime actually
# sends for plugin agents.
read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' '{"agent_type":"","agent_id":"agt_test","session_id":"sess_test","duration_ms":12345,"parent_agent_id":"agt_parent","background_tasks":[{"id":"bg1"},{"id":"bg2"}],"session_crons":[{"id":"cr1"}]}'
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
  def first_nonempty: map(select(type == "string" and . != "")) | first // "unknown";
  {
    ts: $ts,
    actor: "hook:audit-subagent",
    action: "subagent_stopped",
    subject: ([.agent_type, env.CLAUDE_SUBAGENT_TYPE] | first_nonempty),
    result: (.status // "ok"),
    metadata: {
      stage: ([.stage, env.CLAUDE_TASK_METADATA_STAGE] | first_nonempty),
      agent_id: ([.agent_id] | first_nonempty),
      duration_ms: ((.duration_ms // 0) | tonumber? // 0),
      effort: (.effort.level // env.CLAUDE_EFFORT // "unknown"),
      parent_agent_id: (.parent_agent_id // "none"),
      background_tasks_count: ((.background_tasks // []) | length),
      background_task_ids: ((.background_tasks // []) | map(.id // .task_id // "unknown")),
      session_crons_count: ((.session_crons // []) | length),
      session_cron_ids: ((.session_crons // []) | map(.id // .cron_id // "unknown")),
      dedupe_key: ((.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":stop")
    }
  }') || {
    echo "audit-subagent: jq parse failed" >&2
    exit 0
  }

if [ "$SELF_TEST" -eq 1 ]; then
  printf '%s\n' "$ROW" | jq -e '
    .metadata.dedupe_key == "sess_test:agt_test:stop"
    and .subject == "unknown"
    and .metadata.stage == "unknown"
    and .metadata.agent_id == "agt_test"
    and .metadata.parent_agent_id == "agt_parent"
    and .metadata.background_tasks_count == 2
    and .metadata.background_task_ids == ["bg1","bg2"]
    and .metadata.session_crons_count == 1
    and .metadata.session_cron_ids == ["cr1"]
  ' >/dev/null \
    || { echo "audit-subagent: self-test FAIL"; exit 1; }
  echo "audit-subagent: self-test OK"
  exit 0
fi

# A symlinked audit.jsonl turns this append into a write primitive against an arbitrary
# target. Refuse rather than follow — the guard hooks/model-switch-lib.sh carries for the
# hook rows it writes, and tests/shell/hooks/test-execution-gate.bats pins.
[ ! -L "$LOG_DIR/audit.jsonl" ] || exit 0
printf '%s\n' "$ROW" >> "$LOG_DIR/audit.jsonl"
exit 0
