#!/usr/bin/env bats
# Contract tests for skills/worktask/references/handoff-harness.sh.
# Contracts (from header):
#   - default run (--out DIR): generates synthetic artifacts, computes token reduction,
#     reports >=30% on all stages (AC-12), "PASS: all stages"; exit 0
#   - --validate-frontmatter <file>: valid frontmatter => "ok: ... stage=X tokens=N", exit 0
#   - --validate-frontmatter <file>: missing frontmatter => "fail: missing", exit 1
#   - --validate-state <state.json>: valid state => "ok: ... idempotent=yes", exit 0
#   - --validate-state <bad>: invalid JSON => "fail: state.json invalid JSON", exit 1
#   - --self-test => "ALL PASS", exit 0
#   - unknown arg => usage exit 2
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/references/handoff-harness.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  # Use our shared DV fixture which has valid frontmatter + DV anchors.
  cp "$FIXTURES/worktask/development-0.sample.md" "$WD/development-0.md"
  cp "$FIXTURES/worktask/state.sample.json" "$WD/state.json"
  # A file with NO frontmatter (to trigger the "fail: missing" path).
  printf '# plain markdown\nno frontmatter here\n' > "$WD/plain.md"
  # Corrupt JSON for --validate-state failure test.
  printf 'not json {{' > "$WD/corrupt.json"
}

@test "happy: default run (--out DIR) reports token reduction >=30% on all stages" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --out "$WD/out"
  assert_success
  assert_output --partial "PASS: all stages"
  # spot-check that the table was printed
  assert_output --partial "%"
}

@test "happy: --validate-frontmatter on a valid DV artifact passes (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/development-0.md"
  assert_success
  assert_output --partial "ok:"
  assert_output --partial "stage=DV"
  assert_output --partial "tokens="
}

@test "edge: --validate-state on a valid state.json passes (exit 0, idempotent=yes)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-state "$WD/state.json"
  assert_success
  assert_output --partial "ok:"
  assert_output --partial "idempotent=yes"
}

@test "failure: --validate-frontmatter on a no-frontmatter file fails (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/plain.md"
  assert_failure 1
  assert_output --partial "fail:"
  assert_output --partial "missing frontmatter"
}

@test "failure: --validate-state on corrupt JSON fails (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-state "$WD/corrupt.json"
  assert_failure 1
  assert_output --partial "fail:"
  assert_output --partial "invalid JSON"
}

@test "failure: unknown argument exits 2 (usage)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}
