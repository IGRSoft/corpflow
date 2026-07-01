#!/usr/bin/env bats
# tests/shell/dv-screenshot/size-budget.bats — DV0c
# Target: skills/dv-screenshot-capture/scripts/size-budget.sh
# Covers: small file → verdict=ok exit 0, warn-range file → verdict=warn exit 0,
#         oversize file (no pngquant) → moved to oversize/ exit 3.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/size-budget.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/images/wt-test"
}

# ---------------------------------------------------------------------------

@test "small file (<200KB) -> verdict=ok, exit 0, size_audit line on stdout" {
  SMALL="$WD/.context/images/wt-test/dv-01-small.png"
  # ~100 bytes — well under the 200 KB warn threshold
  printf '%0.sx' {1..100} > "$SMALL"
  run bash "$PLUGIN_ROOT/$SCRIPT" --path "$SMALL" --worktask-id wt-test --project-root "$WD"
  assert_success
  assert_output --partial "verdict=ok"
}

@test "warn-range file (200KB<=x<500KB) -> verdict=warn, exit 0" {
  WARN_FILE="$WD/.context/images/wt-test/dv-02-warn.png"
  # 250 000 bytes — in warn range
  dd if=/dev/zero bs=1 count=250000 2>/dev/null > "$WARN_FILE"
  run bash "$PLUGIN_ROOT/$SCRIPT" --path "$WARN_FILE" --worktask-id wt-test --project-root "$WD"
  assert_success
  assert_output --partial "verdict=warn"
}

@test "oversize file (>=500KB, no pngquant) -> moved to oversize/, exit 3, .gitignore updated" {
  OVER_FILE="$WD/.context/images/wt-test/dv-03-big.png"
  # 600 000 bytes — over hard limit
  dd if=/dev/zero bs=1 count=600000 2>/dev/null > "$OVER_FILE"
  # Ensure pngquant is not on PATH so quantization is skipped
  run bash -c "cd '$WD' && PATH='/usr/bin:/bin' bash '$PLUGIN_ROOT/$SCRIPT' \
    --path '$OVER_FILE' --worktask-id wt-test --project-root '$WD'"
  [ "$status" -eq 3 ]
  assert_output --partial "verdict=oversize"
  # File must be moved to oversize/
  [ ! -f "$OVER_FILE" ]
  [ -f "$WD/.context/images/wt-test/oversize/dv-03-big.png" ]
  # .gitignore must contain the oversize guard
  grep -qxF '.context/images/*/oversize/' "$WD/.gitignore"
}

@test "self-test smoke: --self-test exits 0 (NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "passed"
}
