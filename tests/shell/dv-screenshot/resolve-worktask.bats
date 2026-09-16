#!/usr/bin/env bats
# Tests for skills/dv-screenshot-capture/scripts/resolve-worktask.sh, the capture skill's guard.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="skills/dv-screenshot-capture/scripts/resolve-worktask.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  printf '%s' '{"worktask_id":"wt-guard","tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"pending"},"QA0":{"status":"in_progress"}}}' \
    > "$WD/.context/state.json"
}

@test "a resolvable ledger prints the worktask and its sole in_progress DV task" {
  run_script_env --env "WORKSPACE_ROOT=$WD" --separate-stderr "$SUT"
  assert_success
  assert_output 'worktask_id=wt-guard task_id=DV0'
}

@test "--task-id naming a ledger task is echoed back" {
  run_script_env --env "WORKSPACE_ROOT=$WD" "$SUT" --task-id DV1
  assert_success
  assert_output 'worktask_id=wt-guard task_id=DV1'
}

@test "no ledger and no declared roots exits 4, prints nothing, creates no .context" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR --unset CONTEXT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$cwd" --separate-stderr "$SUT" --task-id DV0
  assert_failure 4
  assert_output ''
  [ -z "$stderr" ]
  [ ! -e "$cwd/.context" ]
}

@test "a malformed --task-id exits 2" {
  run_script_env --env "WORKSPACE_ROOT=$WD" --separate-stderr "$SUT" --task-id dv0
  assert_failure 2
  assert_output ''
  [[ "$stderr" == *'--task-id must match'* ]]
}

@test "a --task-id the ledger does not hold exits 2" {
  run_script_env --separate-stderr "$SUT" --state "$WD/.context/state.json" --task-id DV7
  assert_failure 2
  [[ "$stderr" == *'task DV7 is not in'* ]]
}

@test "two in_progress DV tasks and no --task-id prints task_id=-" {
  printf '%s' '{"worktask_id":"wt-guard","tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"in_progress"}}}' \
    > "$WD/two.json"
  run_script_env "$SUT" --state "$WD/two.json"
  assert_success
  assert_output 'worktask_id=wt-guard task_id=-'
}

@test "a ledger without a worktask_id is unresolved (exit 4)" {
  printf '%s' '{"tasks":{"DV0":{"status":"in_progress"}}}' > "$WD/.context/state.json"
  run_script_env --env "WORKSPACE_ROOT=$WD" "$SUT"
  assert_failure 4
  assert_output ''
}

@test "self-test smoke: --self-test passes (NON-counting)" {
  run bash "$PLUGIN_ROOT/$SUT" --self-test
  assert_success
  assert_output --partial '0 failed'
}
