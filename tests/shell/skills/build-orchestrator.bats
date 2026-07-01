#!/usr/bin/env bats
# Contract tests for skills/megatask/scripts/build-orchestrator.sh
# Contracts: emits orchestrator.json v3.1 (keys: version, group, configuration
# {parallel_tracks, isolation:"worktree"}, issues, tracks, topological_order,
# dependency_warnings); blocked_by edges from "Depends on/Blocked by #N";
# level/status assignment; cycle -> exits non-zero (jq error() = exit 5 propagated);
# non-array input -> exit 1; jq absent -> exit 2; --self-test exits 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/megatask/scripts/build-orchestrator.sh"
ISSUES="${FIXTURES}/skills/orchestrator-issues.json"
CYCLE="${FIXTURES}/skills/orchestrator-cycle.json"

@test "happy: builds v3.1 orchestrator with worktree isolation and 4 issues" {
  # Capture script output once into a variable; do not re-run for each field.
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$ISSUES" --group milestone-9 --milestone-num 9)"
  run jq -r '.version' <<< "$orch_json"
  assert_output "3.1"
  run jq -r '.configuration.isolation' <<< "$orch_json"
  assert_output "worktree"
  run jq -r '.issues | length' <<< "$orch_json"
  assert_output "4"
}

@test "edge: dependency edges and topological levels are assigned" {
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$ISSUES" --group milestone-9)"
  # #41 has no blockers -> level 0, ready.
  run jq -r '.issues[] | select(.number==41) | .level' <<< "$orch_json"
  assert_output "0"
  run jq -r '.issues[] | select(.number==41) | .status' <<< "$orch_json"
  assert_output "ready"
  # #60 depends on #42 and #57 -> blocked, both in blocked_by.
  run jq -c '.issues[] | select(.number==60) | .blocked_by | sort' <<< "$orch_json"
  assert_output "[42,57]"
  run jq -r '.issues[] | select(.number==60) | .status' <<< "$orch_json"
  assert_output "blocked"
}

@test "edge: workspace path follows .worktrees/<group>/<n> convention" {
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$ISSUES" --group milestone-9)"
  run jq -r '.issues[] | select(.number==42) | .workspace' <<< "$orch_json"
  assert_output ".worktrees/milestone-9/42"
}

@test "failure: a dependency cycle exits non-zero with a clear error" {
  # jq's error() propagates as exit 5; the script ERR trap re-emits it.
  run_script "$SCRIPT" --file "$CYCLE" --group milestone-1
  assert_failure
  assert_output --partial "cycle"
}

@test "KNOWN BUG: 'Blocked by #N' phrasing triggers a false cycle (build-orchestrator.sh:146)" {
  # The "Blocks: #N" edge regex /(?i)blocks?\s*:?[^\n]*/ ALSO matches "Blocked by"
  # (because "blocks?" matches the "Block" in "Blocked"), so a body using "Blocked by #N"
  # gets a spurious reverse edge (this->N) on top of the correct blocked_by edge (N->this),
  # forming a 2-cycle. An otherwise-acyclic graph is then wrongly rejected as a cycle (exit 5).
  # Asserted-as-is and REPORTED, not fixed (plan scope = report contract bugs, don't fix here).
  WD="$(mk_tmpworkdir)"
  printf '[{"issue":1,"title":"A","labels":["P0"],"body":"root"},{"issue":2,"title":"B","labels":["P1"],"body":"Blocked by #1"}]' > "$WD/bb.json"
  run_script "$SCRIPT" --file "$WD/bb.json" --group m
  assert_failure
  assert_output --partial "cycle"
}

@test "failure: non-array JSON input exits 1" {
  WD="$(mk_tmpworkdir)"
  printf '{"not":"an array"}\n' > "$WD/bad.json"
  run_script "$SCRIPT" --file "$WD/bad.json"
  assert_failure 1
}

@test "failure: bad --milestone-num (non-integer) exits 1" {
  run_script "$SCRIPT" --file "$ISSUES" --milestone-num abc
  assert_failure 1
}

@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
