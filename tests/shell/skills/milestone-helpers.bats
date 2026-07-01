#!/usr/bin/env bats
# Contract tests for skills/shared/milestone-helpers/scripts/milestone-helpers.sh
# Contracts (from script header + empirical verification):
#   branch-name <n> <title>     -> feature/{n}-{slug}  (slug max 50 chars, lowercase, no-punct)
#   priority-score <label...>   -> lowest integer score: 0=P0/critical…4=P4/backlog, 99=none
#   base-branch [<n>] [--file J] -> branch name ("master" default when no issue JSON)
#   usage error (no subcommand) -> exit 1
#   --self-test                  -> exit 0 "all tests passed"
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/shared/milestone-helpers/scripts/milestone-helpers.sh"

# --- branch-name: happy path ------------------------------------------------
@test "happy: branch-name produces feature/{n}-{slug} with lowercase no-punct" {
  run_script "$SCRIPT" branch-name 42 "Add OAuth Login Flow!!"
  assert_success
  assert_output "feature/42-add-oauth-login-flow"
}

@test "edge: branch-name slug is max 50 chars (long title truncated)" {
  local long_title="This is a very long feature title that should be truncated because it exceeds fifty characters by a lot"
  run_script "$SCRIPT" branch-name 1 "$long_title"
  assert_success
  # Strip the "feature/1-" prefix, slug portion must be ≤50 chars.
  local slug="${output#feature/1-}"
  [ "${#slug}" -le 50 ]
}

# --- priority-score ---------------------------------------------------------
@test "happy: priority-score returns min score when multiple labels given" {
  # P2 and P0 together should yield 0 (P0 wins).
  run_script "$SCRIPT" priority-score P2 P0
  assert_success
  assert_output "0"
}

@test "edge: priority-score returns 99 for unknown labels" {
  run_script "$SCRIPT" priority-score unknown-label
  assert_success
  assert_output "99"
}

@test "edge: priority-score P4 yields 4" {
  run_script "$SCRIPT" priority-score P4
  assert_success
  assert_output "4"
}

# --- base-branch ------------------------------------------------------------
@test "happy: base-branch with no args defaults to master" {
  run_script "$SCRIPT" base-branch
  assert_success
  assert_output "master"
}

# --- failure / usage --------------------------------------------------------
@test "failure: missing subcommand exits 1 and prints usage" {
  run_script "$SCRIPT"
  assert_failure 1
  assert_output --partial "Usage"
}

@test "failure: unknown subcommand exits 1" {
  run_script "$SCRIPT" frobulate
  assert_failure 1
}

# --- self-test smoke (NON-counting) ----------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "passed"
}
