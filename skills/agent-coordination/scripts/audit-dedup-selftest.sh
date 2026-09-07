#!/usr/bin/env bash
# audit-dedup-selftest.sh — the `--self-test` harness for audit-dedup.sh.
#
# SOURCED, never executed: audit-dedup.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_test`, returning 0 when every case passes.

run_self_test() {
  local tmp; tmp=$(mktemp)
  cat > "$tmp" <<'JSONL'
{"ts":"2026-05-15T00:00:01Z","actor":"orchestrator","action":"approval_received","subject":"PL0","result":"ok"}
{"ts":"2026-05-15T00:00:02Z","actor":"developer","action":"tool_invoked","subject":"Write","result":"ok","metadata":{"dedupe_key":"sessA:toolu1"}}
{"ts":"2026-05-15T00:00:02Z","actor":"hook:audit-tooluse","action":"tool_invoked","subject":"Write","result":"ok","metadata":{"dedupe_key":"sessA:toolu1","duration_ms":42,"effort":"high"}}
{"ts":"2026-05-15T00:00:03Z","actor":"developer","action":"tool_invoked","subject":"Edit","result":"ok","metadata":{"dedupe_key":"sessA:toolu2"}}
{"ts":"2026-05-15T00:00:04Z","actor":"hook:audit-subagent","action":"subagent_stopped","subject":"developer","result":"ok","metadata":{"dedupe_key":"sessA:agX:stop"}}
{"ts":"2026-05-15T00:00:05Z","actor":"developer","action":"subagent_stopped","subject":"developer","result":"ok","metadata":{"dedupe_key":"sessA:agY:stop"}}
{"ts":"2026-05-15T00:00:05Z","actor":"hook:audit-subagent","action":"subagent_stopped","subject":"developer","result":"ok","metadata":{"dedupe_key":"sessA:agY:stop"}}
{"ts":"2026-05-15T00:00:06Z","actor":"apple-developer:hook:audit-subagent","action":"subagent_stopped","subject":"","result":"ok","metadata":{"advisory":true,"dedupe_key":"sessA:agZ:stop"}}
{"ts":"2026-05-15T00:00:06Z","actor":"hook:audit-subagent","action":"subagent_stopped","subject":"corpflow:developer","result":"ok","metadata":{"dedupe_key":"sessA:agZ:stop"}}
JSONL
  local out; out=$("$0" "$tmp")
  rm -f "$tmp"
  # Expected: 6 rows (orchestrator approval + hook row for toolu1 [agent row dropped]
  # + developer row for toolu2 [no hook row, kept] + hook subagent_stopped for agX
  # + hook row for agY [agent row dropped] + canonical hook row for agZ [advisory
  # plugin mirror dropped]).
  local n; n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  if [ "$n" != "6" ]; then
    echo "audit-dedup self-test FAIL: expected 6 rows, got $n" >&2
    return 1
  fi
  # The toolu1 row that survives MUST be the hook row.
  local actor; actor=$(printf '%s\n' "$out" | jq -rs '.[] | select(.metadata.dedupe_key=="sessA:toolu1") | .actor')
  if [ "$actor" != "hook:audit-tooluse" ]; then
    echo "audit-dedup self-test FAIL: expected hook row for sessA:toolu1, got actor=$actor" >&2
    return 1
  fi
  # Same key from both a hook and an agent writer must collapse to the hook row.
  local actor2; actor2=$(printf '%s\n' "$out" | jq -rs '.[] | select(.metadata.dedupe_key == "sessA:agY:stop") | .actor')
  if [ "$actor2" != "hook:audit-subagent" ]; then
    echo "audit-dedup self-test FAIL: expected hook row to win for sessA:agY, got actor=$actor2" >&2
    return 1
  fi
  # The advisory plugin mirror must lose to the canonical writer, or the surviving
  # row carries the mirror's empty subject and the agent goes unnamed downstream.
  local actor3; actor3=$(printf '%s\n' "$out" | jq -rs '.[] | select(.metadata.dedupe_key == "sessA:agZ:stop") | .subject')
  if [ "$actor3" != "corpflow:developer" ]; then
    echo "audit-dedup self-test FAIL: expected canonical row for sessA:agZ, got subject=$actor3" >&2
    return 1
  fi
  # A malformed row must not silently vanish: the parseable rows still dedupe and
  # the drop is named on stderr.
  local tmp2; tmp2=$(mktemp)
  {
    printf '{ not json at all\n'
    printf '{"ts":"2026-05-15T00:00:01Z","actor":"orchestrator","action":"approval_received","subject":"PL0","result":"ok"}\n'
  } > "$tmp2"
  local err2; err2=$(mktemp)
  local out2; out2=$("$0" "$tmp2" 2> "$err2")
  local n2; n2=$(printf '%s\n' "$out2" | grep -c '[^[:space:]]' || true)
  if [ "$n2" != "1" ]; then
    echo "audit-dedup self-test FAIL: expected the 1 parseable row to survive, got $n2" >&2
    rm -f "$tmp2" "$err2"; return 1
  fi
  if ! grep -q '1 unparseable row' "$err2"; then
    echo "audit-dedup self-test FAIL: unparseable row was dropped silently" >&2
    rm -f "$tmp2" "$err2"; return 1
  fi
  rm -f "$tmp2" "$err2"
  echo "audit-dedup: self-test OK"
}
