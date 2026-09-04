#!/usr/bin/env bats
# tests/shell/dv-screenshot/cli-fallback.bats — DV0c
# Target: skills/dv-screenshot-capture/scripts/cli-fallback.sh
# Covers: missing required args → exit 1, invalid slug → exit 1,
#         floor → exit 2 (tool_missing) / exit 3 (render_failed), never a .txt placeholder.
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

@test "floor: no image tool and no repo -> exit 2, error=tool_missing, no .txt written" {
  # Strip PATH so neither silicon nor magick resolves; $WD is not a git repo either,
  # so no render is attempted and the floor must report absence, not failure.
  run bash -c "cd '$WD' && PATH='/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --slug my-feature --run-index 0"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"error=tool_missing"* ]]
  # The floor must not write a placeholder that an existence check would accept.
  run bash -c "ls '$WD/.context/images/wt-test'/dv-01-my-feature.txt"
  assert_failure
}

@test "floor: a present tool that fails to render -> exit 3, error=render_failed" {
  mkdir -p "$WD/fakebin"
  printf '#!/bin/sh\nexit 1\n' > "$WD/fakebin/silicon"
  chmod +x "$WD/fakebin/silicon"
  git -C "$WD" init -q
  git -C "$WD" commit -q --allow-empty -m init
  run bash -c "cd '$WD' && PATH='$WD/fakebin:/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --slug my-feature --run-index 0 --base-ref HEAD"
  [ "$status" -eq 3 ]
  [[ "$output" == *"error=render_failed"* ]]
  run bash -c "ls '$WD/.context/images/wt-test'/dv-01-my-feature.txt"
  assert_failure
}

@test "audit row construction is guarded: a jq failure never aborts the capture" {
  # R-1.1a: the two screenshot_captured rows tail their jq with a fallback and
  # their audit call with `|| true`, matching the sibling capture adapters.
  run grep -c "2> /dev/null || printf '{}'" "$PLUGIN_ROOT/$SCRIPT"
  [ "$output" -ge 2 ]
  run grep -c ')" 2> /dev/null || true' "$PLUGIN_ROOT/$SCRIPT"
  [ "$output" -ge 2 ]
}

@test "self-test smoke: --self-test exits 0 with pass count (NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "passed"
}
