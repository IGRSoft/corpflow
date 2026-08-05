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

# --- R4.2: edge-keyword matching (reverse/forward pair, distinct observables) ---
# The old regex /(?i)blocks?\s*:?[^\n]*/ was unanchored, so the "Block" inside
# "Blocked by" was read as the "Blocks" keyword. A "Blocked by #N" body therefore
# minted a spurious reverse edge (this->N) on top of the correct one (N->this),
# forming a 2-cycle that failed an acyclic graph outright. Fixed to \bblocks?\b.
#
# The two tests below deliberately observe DIFFERENT fields — the reverse-edge test
# reads the ROOT issue's blocked_by, the forward-edge test reads the LEAF's — so a
# regression in one direction cannot be masked by the other still passing.

@test "edge: 'Blocked by #N' yields the correct wave order and no reverse edge" {
  WD="$(mk_tmpworkdir)"
  printf '[{"issue":1,"title":"A","labels":["P0"],"body":"root"},{"issue":2,"title":"B","labels":["P1"],"body":"Blocked by #1"}]' > "$WD/bb.json"
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$WD/bb.json" --group m)"
  # Observable A: the root must stay unblocked. Under the old regex it was
  # blocked_by [2], which is what made the graph cyclic.
  run jq -c '.issues[] | select(.number==1) | [.level, .status, .blocked_by]' <<< "$orch_json"
  assert_output '[0,"ready",[]]'
  # Observable B: the wave order itself, which the old regex could not produce at
  # all (the run died at exit 5 before emitting any JSON).
  run jq -c '.topological_order' <<< "$orch_json"
  assert_output '[1,2]'
  # A spurious edge would also surface here as a self-edge/external warning.
  run jq -c '.dependency_warnings' <<< "$orch_json"
  assert_output '[]'
}

@test "edge: 'Blocks: #N' creates the forward edge in the correct direction" {
  WD="$(mk_tmpworkdir)"
  printf '[{"issue":1,"title":"A","labels":["P0"],"body":"Blocks: #2"},{"issue":2,"title":"B","labels":["P1"],"body":"leaf"}]' > "$WD/fw.json"
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$WD/fw.json" --group m)"
  # Distinct observable from the test above: the LEAF's blocked_by list.
  run jq -c '.issues[] | select(.number==2) | [.level, .status, .blocked_by]' <<< "$orch_json"
  assert_output '[1,"blocked",[1]]'
}

@test "edge: singular 'Block: #N' still registers as a forward edge" {
  # The fix is \bblocks?\b, not \bblocks\b: dropping the optional plural would have
  # silently stopped creating edges for a spelling the old regex accepted.
  WD="$(mk_tmpworkdir)"
  printf '[{"issue":1,"title":"A","labels":["P0"],"body":"Block: #2"},{"issue":2,"title":"B","labels":["P1"],"body":"leaf"}]' > "$WD/sg.json"
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$WD/sg.json" --group m)"
  run jq -c '.issues[] | select(.number==2) | .blocked_by' <<< "$orch_json"
  assert_output '[1]'
}

@test "edge: the word 'blocker' in prose does not create an edge" {
  # Trailing \b: "blocker" is not the keyword. The old unanchored regex read it as
  # one and built a real dependency out of a passing mention.
  WD="$(mk_tmpworkdir)"
  printf '[{"issue":1,"title":"A","labels":["P0"],"body":"see blocker #2 for context"},{"issue":2,"title":"B","labels":["P1"],"body":"leaf"}]' > "$WD/pr.json"
  local orch_json
  orch_json="$(bash "$PLUGIN_ROOT/$SCRIPT" --file "$WD/pr.json" --group m)"
  run jq -c '[.issues[] | .blocked_by] | flatten' <<< "$orch_json"
  assert_output '[]'
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
