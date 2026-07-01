#!/usr/bin/env bats
# Contract tests for skills/worktask/references/attachments-preseed-test.sh.
# This script is a fixture-driven self-test harness for the FN pre-gate
# Conductor-attachments writer. Its external CLI contract:
#   - --self-test  => runs Test 1 (gated path), Test 2 (idempotency),
#                     Test 3 (defensive default); exit 0 on all pass, 1 on any fail
#   - no arg       => usage, exit 2
#   - unknown arg  => usage, exit 2
# NOTE: --self-test is this script's PRIMARY operational mode (the script exists
# to run those 3 scenarios), so asserting each of the three named scenarios is
# real contract coverage, not a bare smoke invocation.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/references/attachments-preseed-test.sh"

@test "happy: --self-test runs all three scenarios and passes (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "PASS: Test 1"
  assert_output --partial "PASS: Test 2 (idempotency)"
  assert_output --partial "PASS: Test 3 (defensive default"
  assert_output --partial "ALL TESTS PASSED"
}

@test "edge: invoked with no arguments prints usage and exits 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 2
  assert_output --partial "usage:"
}

@test "failure: an unknown argument prints usage and exits 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
  assert_output --partial "unknown arg"
}
