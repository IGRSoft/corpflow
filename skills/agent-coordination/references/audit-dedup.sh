#!/usr/bin/env bash
# Audit-trail dedup filter (igrsoft plugin v3.10.1+).
#
# Reads `.context/logs/audit.jsonl` (or stdin) and emits a deduped stream:
# for every group of rows sharing `metadata.dedupe_key`, prefer the row whose
# `actor` starts with "hook:" (hook authority per skills/agent-coordination/
# SKILL.md § Writers). Agent-emitted rows for the same key are dropped.
# Rows lacking `metadata.dedupe_key` pass through unchanged (one-shot events).
#
# Usage:
#   audit-dedup.sh [PATH_TO_AUDIT_JSONL]      # default: .context/logs/audit.jsonl
#   audit-dedup.sh -                          # read from stdin
#   audit-dedup.sh --self-test                # synthetic fixture, exits 0 on success
#
# Pipe into /cost-report aggregation to avoid double-counting effort/duration
# on (session, agent, tool) pairs that emit both hook and agent rows.
#
# Stability: input order within a dedup group is preserved (jq groups by key,
# then folds preferring hook:* actors); rows outside any group keep arrival order.
set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "audit-dedup: jq not found" >&2
  exit 2
fi

run_self_test() {
  local tmp; tmp=$(mktemp)
  cat > "$tmp" <<'JSONL'
{"ts":"2026-05-15T00:00:01Z","actor":"orchestrator","action":"approval_received","subject":"PL0","result":"ok"}
{"ts":"2026-05-15T00:00:02Z","actor":"developer","action":"tool_invoked","subject":"Write","result":"ok","metadata":{"dedupe_key":"sessA:toolu1"}}
{"ts":"2026-05-15T00:00:02Z","actor":"hook:audit-tooluse","action":"tool_invoked","subject":"Write","result":"ok","metadata":{"dedupe_key":"sessA:toolu1","duration_ms":42,"effort":"high"}}
{"ts":"2026-05-15T00:00:03Z","actor":"developer","action":"tool_invoked","subject":"Edit","result":"ok","metadata":{"dedupe_key":"sessA:toolu2"}}
{"ts":"2026-05-15T00:00:04Z","actor":"hook:audit-subagent","action":"subagent_stopped","subject":"developer","result":"ok","metadata":{"dedupe_key":"sessA:agX:taskY:stop"}}
JSONL
  local out; out=$("$0" "$tmp")
  rm -f "$tmp"
  # Expected: 4 rows (orchestrator approval + hook row for toolu1 [agent row dropped]
  # + developer row for toolu2 [no hook row, kept] + hook subagent_stopped).
  local n; n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  if [ "$n" != "4" ]; then
    echo "audit-dedup self-test FAIL: expected 4 rows, got $n" >&2
    return 1
  fi
  # The toolu1 row that survives MUST be the hook row.
  local actor; actor=$(printf '%s\n' "$out" | jq -rs '.[] | select(.metadata.dedupe_key=="sessA:toolu1") | .actor')
  if [ "$actor" != "hook:audit-tooluse" ]; then
    echo "audit-dedup self-test FAIL: expected hook row for sessA:toolu1, got actor=$actor" >&2
    return 1
  fi
  echo "audit-dedup: self-test OK"
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

SRC="${1:-.context/logs/audit.jsonl}"
if [ "$SRC" = "-" ]; then
  INPUT=$(cat)
elif [ -r "$SRC" ]; then
  INPUT=$(cat "$SRC")
else
  echo "audit-dedup: cannot read $SRC" >&2
  exit 1
fi

# Strategy:
#   1. Parse every line as JSON; attach original index for stable ordering.
#   2. Partition by presence of metadata.dedupe_key.
#   3. For grouped rows, keep the hook:* row if any, else the first by index.
#   4. Re-merge with ungrouped rows and sort by original index.
printf '%s' "$INPUT" | jq -ncR '
  [inputs | select(length > 0) | fromjson?] as $rows
  | $rows
  | to_entries
  | map(.value + {__idx: .key})
  | (map(select(.metadata.dedupe_key)) | group_by(.metadata.dedupe_key)
       | map(  (map(select(.actor | startswith("hook:"))) | first) // (sort_by(.__idx) | .[0])
            )) as $deduped
  | (map(select(.metadata.dedupe_key | not))) as $singletons
  | ($deduped + $singletons)
  | sort_by(.__idx)
  | map(del(.__idx))
  | .[]
' 2>/dev/null
