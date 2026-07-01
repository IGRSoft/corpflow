#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/state-patch.sh (AC-4 priority).
# Contracts asserted (from the script header + body):
#   - atomic completion merge into .context/state.json (stages.<S>.status=completed)
#   - idempotent re-run leaves state.json byte-identical
#   - disk-guard hard-halt exits 2 below DISK_MIN_GB
#   - absent artifact / absent state.json => no-op exit 0
#   - --self-test => "ALL PASS" exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/state-patch.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  cp "$FIXTURES/worktask/state.sample.json" "$WD/.context/state.json"
  cp "$FIXTURES/worktask/development-0.sample.md" "$WD/.context/development-0.md"
}

@test "happy: merges completed DV verdict into stages.DV (atomic)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run jq -r '.stages.DV.verdict' .context/state.json
  assert_output "ok"
  run jq -r '.stages.DV.artifact' .context/state.json
  assert_output --partial "development-0.md"
}

@test "happy: --stage with no --artifact resolves via run_index=0 from state.json" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run jq -r '.stages.DV.artifact' .context/state.json
  assert_output --partial "development-0.md"
}

@test "edge: idempotent re-run leaves state.json byte-identical" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  cp .context/state.json snap
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  run diff -q .context/state.json snap
  assert_success
}

@test "edge: absent artifact for an un-run stage is a no-op (exit 0, state unchanged)" {
  cd "$WD"
  cp .context/state.json snap
  # No testing-*.md / QA artifact exists in the fixture workdir.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage QA
  assert_success
  run diff -q .context/state.json snap
  assert_success
}

@test "edge: absent state.json is F1 fallback no-op (exit 0)" {
  cd "$WD"
  rm -f .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  [ ! -f .context/state.json ]
}

@test "failure: disk-guard hard-halt exits 2 below DISK_MIN_GB" {
  cd "$WD"
  # CONTRACT NOTE: --disk-check takes NO value (the parser sets root="." and shifts
  # once). The analyzing-0.md worked example's `--disk-check .` is WRONG — the
  # trailing "." is then parsed as an unknown argument and exits 2 via usage. The
  # real disk-guard halt is exercised with a bare --disk-check.
  DISK_MIN_GB=99999999 run bash "$PLUGIN_ROOT/$SCRIPT" \
    --stage DV --artifact .context/development-0.md --disk-check
  assert_failure 2
  assert_output --partial "HALT"
}

@test "failure: unknown argument exits 2 via usage" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus-flag
  assert_failure 2
  assert_output --partial "unknown argument"
}

@test "contract: --self-test runs T1-T5 green but T6 fails (KNOWN BUG, smoke, NON-counting)" {
  # CONTRACT SURPRISE: the in-script self-test T6 invokes
  #   --disk-check /nonexistent_mountpoint_selftest
  # but --disk-check ignores its value argument, so "/nonexistent..." is parsed as
  # an unknown argument and the self-test aborts at exit 2 -> self-test exits 1.
  # T1-T5 all pass ("ok"); the suite never reaches "ALL PASS" in this environment.
  # We assert the REAL current behavior (do not fix the script per plan scope).
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_failure 1
  assert_output --partial "T1: explicit artifact"
  assert_output --partial "T5: absent artifact"
  refute_output --partial "ALL PASS"
}
