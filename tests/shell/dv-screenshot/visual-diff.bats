#!/usr/bin/env bats
# tests/shell/dv-screenshot/visual-diff.bats — DV0c
# Target: skills/dv-screenshot-capture/scripts/visual-diff.sh
# Covers: missing reference → deferred exit 0, missing candidate → exit 3,
#         magick absent → deferred exit 0, missing required args → exit 2.
#
# Tests that require magick to exist install a minimal fake shim via mk_tmpworkdir.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/visual-diff.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/images/wt-test"
  # Fake magick shim used by tests that need magick present but not really
  mkdir -p "$WD/bin"
  printf '#!/bin/bash\nexit 0\n' > "$WD/bin/magick"
  chmod +x "$WD/bin/magick"
}

# ---------------------------------------------------------------------------

@test "magick absent -> deferred exit 0 + audit reason=imagemagick_not_found" {
  # Drop PATH to a minimal set so no magick is found.
  CAND="$WD/candidate.png"
  REF="$WD/reference.png"
  printf 'fake' > "$CAND"
  printf 'fake' > "$REF"
  run bash -c "cd '$WD' && PATH='/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --reference '$REF' --candidate '$CAND' --worktask-id wt-test --slug diff-test"
  assert_success
  run jq -e '.action == "visual_diff_run" and .result == "deferred" and .metadata.reason == "imagemagick_not_found"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "reference not found -> deferred exit 0 + audit reason=reference_not_found" {
  # Use fake magick shim so the magick-not-found early exit is bypassed.
  CAND="$WD/candidate.png"
  printf 'fake' > "$CAND"
  # reference path does not exist
  run bash -c "cd '$WD' && PATH='$WD/bin:/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --reference '$WD/nonexistent-ref.png' --candidate '$CAND' \
    --worktask-id wt-test --slug diff-test"
  assert_success
  run jq -e '.action == "visual_diff_run" and .result == "deferred" and .metadata.reason == "reference_not_found"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "candidate not found -> exit 3 + audit reason=candidate_not_found" {
  # Use fake magick shim so the magick-not-found early exit is bypassed.
  REF="$WD/reference.png"
  printf 'fake' > "$REF"
  # candidate path does not exist
  run bash -c "cd '$WD' && PATH='$WD/bin:/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --reference '$REF' --candidate '$WD/nonexistent-cand.png' \
    --worktask-id wt-test --slug diff-test"
  [ "$status" -eq 3 ]
  run jq -e '.action == "visual_diff_run" and .result == "error" and .metadata.reason == "candidate_not_found"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "missing required args -> exit 2 (arg error)" {
  run bash -c "cd '$WD' && bash '$PLUGIN_ROOT/$SCRIPT' --worktask-id wt-test"
  [ "$status" -eq 2 ]
}
