#!/usr/bin/env bats
# Contract tests for skills/agent-coordination/scripts/audit-dedup.sh
# (PATH-KEYED filename: agent-coordination__audit-dedup.bats — the AC-2 gate matches
# on path-derived stems, so a basename collision could never claim false coverage.)
#
# Contracts (from source + self-test):
#   Reads audit.jsonl (file arg, - for stdin, or default .context/logs/audit.jsonl).
#   For groups sharing metadata.dedupe_key: hook:* actor wins; agent rows dropped.
#   Rows without dedupe_key pass through unchanged (singletons).
#   exit 2 if jq not found; exit 1 if source file unreadable; exit 0 on success.
#   --self-test -> prints "self-test OK", exits 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/agent-coordination/scripts/audit-dedup.sh"
FIX_AUDIT="${FIXTURES}/skills/audit-dedup.jsonl"

# --- happy path -----------------------------------------------------------
@test "happy: hook row wins over agent row for same dedupe_key" {
  # The fixture has two rows for sessA:toolu1: developer (agent) + hook:audit-tooluse.
  # Output should contain exactly one row for that key, and it must be the hook.
  run_script "$SCRIPT" "$FIX_AUDIT"
  assert_success
  local actor
  actor="$(printf '%s\n' "$output" | jq -rs '.[] | select(.metadata.dedupe_key=="sessA:toolu1") | .actor')"
  [ "$actor" = "hook:audit-tooluse" ]
}

@test "happy: singleton (no dedupe_key) passes through unchanged" {
  # The orchestrator approval_received row has no dedupe_key -> must pass through.
  run_script "$SCRIPT" "$FIX_AUDIT"
  assert_success
  run jq -rs 'map(select(.action=="approval_received")) | length' <<< "$output"
  assert_output "1"
}

@test "happy: agent row without a matching hook row is kept" {
  # sessA:toolu2 has only a developer row (no hook row) -> kept as-is.
  # Script emits NDJSON (one object per line); slurp with jq -s.
  # Capture script output into a local var: bats' $output is clobbered by each
  # intermediate `run`, so it must NOT be reused across the two jq assertions.
  local out
  out="$(bash "$PLUGIN_ROOT/$SCRIPT" "$FIX_AUDIT")"
  run jq -rs '[.[] | select(.metadata.dedupe_key=="sessA:toolu2")] | length' <<< "$out"
  assert_output "1"
  run jq -rs '.[] | select(.metadata.dedupe_key=="sessA:toolu2") | .actor' <<< "$out"
  assert_output "developer"
}

# --- edge/boundary --------------------------------------------------------
@test "edge: stdin mode (- arg) produces the same result as file mode" {
  local from_file from_stdin
  from_file="$(bash "$PLUGIN_ROOT/$SCRIPT" "$FIX_AUDIT")"
  from_stdin="$(cat "$FIX_AUDIT" | bash "$PLUGIN_ROOT/$SCRIPT" -)"
  [ "$from_file" = "$from_stdin" ]
}

@test "edge: output row count is reduced when dedup collapses rows" {
  # Fixture: 4 input lines. sessA:toolu1 has agent+hook -> only hook kept.
  # So output should have 3 rows (orchestrator + toolu1-hook + toolu2-agent).
  run_script "$SCRIPT" "$FIX_AUDIT"
  assert_success
  run jq -rs 'length' <<< "$output"
  assert_output "3"
}

@test "edge: original arrival order of singleton rows is preserved" {
  # The orchestrator approval row (idx 0, no dedupe_key) must come first.
  run_script "$SCRIPT" "$FIX_AUDIT"
  assert_success
  # jq -r (not -rs) on first line of output extracts action without surrounding quotes.
  local first_action
  first_action="$(printf '%s\n' "$output" | head -1 | jq -r '.action')"
  [ "$first_action" = "approval_received" ]
}

# --- plugin-prefixed hook writers -----------------------------------------
# Sibling plugins mirror the hook under their own prefix, so `startswith("hook:")`
# alone stopped matching and hook authority silently degraded to first-by-index.
FIX_PREFIX="${FIXTURES}/skills/audit-dedup-plugin-prefix.jsonl"

@test "happy: canonical writer outranks the advisory plugin mirror" {
  local out
  out="$(bash "$PLUGIN_ROOT/$SCRIPT" "$FIX_PREFIX")"
  run jq -rs '.[] | select(.metadata.dedupe_key=="sessB:ag1:stop") | .subject' <<< "$out"
  assert_output "corpflow:developer"
}

@test "happy: prefixed hook row still beats an agent-emitted row" {
  local out
  out="$(bash "$PLUGIN_ROOT/$SCRIPT" "$FIX_PREFIX")"
  run jq -rs '.[] | select(.metadata.dedupe_key=="sessB:ag2:stop") | .actor' <<< "$out"
  assert_output "android-developer:hook:audit-subagent"
}

@test "edge: three writers for one key collapse to a single row" {
  local out
  out="$(bash "$PLUGIN_ROOT/$SCRIPT" "$FIX_PREFIX")"
  run jq -rs 'length' <<< "$out"
  assert_output "3"
}

@test "edge: cross-plugin agent keeps its plugin qualifier through dedup" {
  local out
  out="$(bash "$PLUGIN_ROOT/$SCRIPT" "$FIX_PREFIX")"
  run jq -rs '.[] | select(.metadata.dedupe_key=="sessB:ag3:stop") | .subject' <<< "$out"
  assert_output "apple-developer:ios-developer"
}

# --- failure / exit-code --------------------------------------------------
@test "failure: unreadable source file exits 1" {
  run_script "$SCRIPT" "/no/such/file.jsonl"
  assert_failure 1
}

@test "failure: malformed JSONL (unparseable lines) gracefully produces output (jq fromjson?)" {
  WD="$(mk_tmpworkdir)"
  printf '{"actor":"a","action":"x"}\nnot-json-at-all\n{"actor":"b","action":"y"}\n' > "$WD/mixed.jsonl"
  run_script "$SCRIPT" "$WD/mixed.jsonl"
  assert_success
  # The drop is no longer silent: it is counted on stderr, which bats merges into
  # $output. Assert the count there, and take the JSON row count from stdout alone
  # so the warning line is not fed to jq.
  assert_output --partial "1 unparseable row(s) skipped"
  local rows
  rows="$(bash "$PLUGIN_ROOT/$SCRIPT" "$WD/mixed.jsonl" 2>/dev/null | jq -rs 'length')"
  [ "$rows" = "2" ]
}

# --- self-test smoke (NON-counting) ---------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
