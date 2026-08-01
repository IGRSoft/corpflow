#!/usr/bin/env bats
# Wraps each comment hook's own --self-test so a regression in them turns the
# suite red; neither hook was reachable from the suite before.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

@test "happy: dv-comment-density-gate --self-test passes" {
  # run_script is a frozen API and does not scrub the environment, so an ambient
  # tuning override would silently retune the fixtures and flip this result.
  run env -u COMPANY_WORKFLOW_COMMENT_DENSITY_MAX -u COMPANY_WORKFLOW_COMMENT_DENSITY_WARN \
      -u COMPANY_WORKFLOW_COMMENT_DENSITY_MIN_LINES \
      bash "$PLUGIN_ROOT/hooks/dv-comment-density-gate.sh" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

@test "happy: comment-standard-context --self-test passes" {
  run_script hooks/comment-standard-context.sh --self-test
  assert_success
  assert_output --partial "self-test OK"
}
