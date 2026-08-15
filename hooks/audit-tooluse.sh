#!/usr/bin/env bash
# PostToolUse → audit.jsonl writer (corpflow worktask plugin).
# Reads CC hook stdin JSON (tool_name, tool_input, tool_use_id, duration_ms,
# effort.level, session_id) and appends one canonical row to
# .context/logs/audit.jsonl with actor "hook:audit-tooluse".
#
# Dedupe rule: paired with optional agent-emitted rows via
# metadata.dedupe_key = "<session_id>:<tool_use_id>". Readers prefer the
# hook row when both exist (see skills/agent-coordination/SKILL.md).
#
# Self-test: pass --self-test to feed a synthetic fixture and assert schema.
set -eu

SELF_TEST=0
KIND="tool"
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1 ;;
    --kind) shift; KIND="${1:-tool}" ;;
  esac
  shift
done

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    printf '%s' '{"tool_name":"Write","tool_use_id":"toolu_test","duration_ms":42,"session_id":"sess_test","effort":{"level":"medium"}}'
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "audit-tooluse: jq not found, skipping" >&2
  exit 0
fi

PAYLOAD=$(read_stdin)
LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.context/logs"

# The matcher covers all of Bash so stage transitions (state-patch.sh) are seen; every
# other Bash call is ordinary work and must not reach the audit log. Filtering here
# rather than in the matcher is what keeps the trail signal-only.
printf '%s' "$PAYLOAD" | jq -e '.tool_name != "Bash" or ((.tool_input.command // "") | test("state-patch\\.sh"))' \
  >/dev/null 2>&1 || exit 0

ROW=$(printf '%s' "$PAYLOAD" | jq -c \
  --arg ts "$(date -u +%FT%TZ)" \
  --arg actor "hook:audit-tooluse" \
  --arg kind "$KIND" '
  # Collect into an array first: a bare capture(...)? yields ZERO outputs on no-match,
  # which would silently drop the whole row instead of just the two extra fields.
  ([(.tool_input.command // "")
    | capture("--task-status\\s+(?<id>[A-Z]{2}[0-9]+)\\s+(?<st>[a-z_]+)")?] | first) as $patch
  | {
    ts: $ts,
    actor: $actor,
    action: "tool_invoked",
    subject: (if .tool_name == "Bash" then "state-patch" else (.tool_name // "unknown") end),
    result: "ok",
    metadata: ({
      kind: $kind,
      duration_ms: ((.duration_ms // 0) | tonumber? // 0),
      effort: (.effort.level // env.CLAUDE_EFFORT // "unknown"),
      dedupe_key: ((.session_id // "nosession") + ":" + (.tool_use_id // "notoolid"))
    } + (if $patch then {task_id: $patch.id, status: $patch.st} else {} end))
  }') || {
    echo "audit-tooluse: jq parse failed" >&2
    exit 0
  }

if [ "$SELF_TEST" -eq 1 ]; then
  printf '%s\n' "$ROW" | jq -e '.metadata.dedupe_key == "sess_test:toolu_test" and .metadata.duration_ms == 42 and .metadata.effort == "medium"' >/dev/null \
    || { echo "audit-tooluse: self-test FAIL"; exit 1; }
  echo "audit-tooluse: self-test OK"
  exit 0
fi

# Only the write path creates the directory, so a filtered-out call leaves no trace.
mkdir -p "$LOG_DIR"
printf '%s\n' "$ROW" >> "$LOG_DIR/audit.jsonl"
exit 0
