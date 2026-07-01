#!/usr/bin/env bats
# tests/shell/dv-screenshot/cli-fallback.bats — DV0c
# Target: skills/dv-screenshot-capture/scripts/cli-fallback.sh
# Covers: missing required args → exit 1, invalid slug → exit 1,
#         tool_missing floor → exit 2 + .txt placeholder + ok=false error=tool_missing.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/cli-fallback.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
}

# ---------------------------------------------------------------------------

@test "arg error: missing --worktask-id exits 1" {
  run bash -c "cd '$WD' && bash '$PLUGIN_ROOT/$SCRIPT' --slug my-feature"
  [ "$status" -eq 1 ]
}

@test "arg error: invalid slug (uppercase) exits 1" {
  run bash -c "cd '$WD' && bash '$PLUGIN_ROOT/$SCRIPT' --worktask-id wt-test --slug MyFeature"
  [ "$status" -eq 1 ]
}

@test "arg error: invalid slug (>40 chars) exits 1" {
  LONG_SLUG="a$(printf '%0.sa' {1..40})"  # 41 chars
  run bash -c "cd '$WD' && bash '$PLUGIN_ROOT/$SCRIPT' --worktask-id wt-test --slug '$LONG_SLUG'"
  [ "$status" -eq 1 ]
}

@test "tool_missing floor: silicon+magick absent -> exit 2, .txt placeholder, ok=false error=tool_missing" {
  # Strip PATH to ensure neither silicon nor magick is found; also not a real git repo.
  # The script should fall through to the .txt placeholder floor.
  run bash -c "cd '$WD' && PATH='/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --slug my-feature --run-index 0"
  [ "$status" -eq 2 ]
  # stdout must contain ok=false error=tool_missing
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"error=tool_missing"* ]]
  # .txt placeholder must exist
  run bash -c "ls '$WD/.context/images/wt-test'/dv-01-my-feature.txt"
  assert_success
}

@test "self-test smoke: --self-test exits 0 with pass count (NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "passed"
}
