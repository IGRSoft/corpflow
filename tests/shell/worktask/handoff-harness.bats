#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/handoff-harness.sh.
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

SCRIPT="skills/worktask/scripts/handoff-harness.sh"

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

# ---------------------------------------------------------------------------
# AR→DV architecture-reference gate (--state / --strict, 3.42.0).
# Ships warn-only: violations are `warn:` + exit 0 unless --strict is passed.
# The cases above this block are the AC-6 legacy pin — they must keep passing
# unmodified, since a bare --validate-frontmatter never runs this gate.
# ---------------------------------------------------------------------------

# Writes a DV artifact whose only variable is the refs block.
dv_artifact() {
  local path="$1" refs="$2"
  {
    printf -- '---\n'
    printf 'handoff:\n'
    printf '  stage: DV\n'
    printf '  verdict: ok\n'
    printf '  summary: "gate fixture"\n'
    printf '  files_touched: [a.md]\n'
    printf '  next_stage_focus: "DR reviews"\n'
    printf '  refs:\n'
    printf '    %s\n' "$refs"
    printf -- '---\n\n# Development\n'
  } > "$path"
}

# state.sample.json has PL only; the gate keys off stages.AR presence.
state_with_ar() {
  jq '.stages.AR = {"status":"completed","verdict":"ok"}' "$WD/state.json" > "$WD/state-ar.json"
}

@test "ar-gate: AR in state + missing ref => warn, exit 0 (default warn-only rollout)" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json"
  assert_success
  assert_output --partial "warn: AR completed but DV refs.decisions missing"
  refute_output --partial "fail:"
}

@test "ar-gate: AR in state + missing ref + --strict => fail, exit 1" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json" --strict
  assert_failure 1
  assert_output --partial "fail: AR completed but DV refs.decisions missing"
}

@test "ar-gate: AR in state + dangling ref => warn exit 0; --strict => fail exit 1" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'decisions: architecture-9.md#decisions'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json"
  assert_success
  assert_output --partial "warn: DV architecture ref dangling"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json" --strict
  assert_failure 1
  assert_output --partial "fail: DV architecture ref dangling"
}

@test "ar-gate: AR in state + valid ref whose file exists => silent, exit 0 in both modes" {
  state_with_ar
  dv_artifact "$WD/dv.md" 'decisions: architecture-0.md#decisions'
  printf -- '---\nhandoff:\n  stage: AR\n---\n\n# Architecture\n\n## decisions\n' > "$WD/architecture-0.md"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json"
  assert_success
  refute_output --partial "AR completed but"
  refute_output --partial "architecture ref dangling"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state-ar.json" --strict
  assert_success
  refute_output --partial "fail:"
}

@test "ar-gate: no AR in state + no ref => silent, exit 0" {
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state.json"
  assert_success
  refute_output --partial "AR completed but"
  refute_output --partial "but state has no stages.AR"
}

@test "ar-gate: inverse guard — no AR in state + architecture ref => warn, exit 0 in BOTH modes" {
  dv_artifact "$WD/dv.md" 'decisions: architecture-0.md#decisions'
  printf -- '---\nhandoff:\n  stage: AR\n---\n\n# Architecture\n' > "$WD/architecture-0.md"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state.json"
  assert_success
  assert_output --partial "warn: DV references architecture-0.md#decisions but state has no stages.AR entry"

  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --state "$WD/state.json" --strict
  assert_success
  assert_output --partial "warn: DV references architecture-0.md#decisions but state has no stages.AR entry"
  refute_output --partial "fail:"
}

@test "ar-gate: AC-6 legacy pin — no --state means the gate never runs" {
  # Same artifact that warns under --state with AR present: silent without it.
  dv_artifact "$WD/dv.md" 'dev: development.md#files-changed'
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md"
  assert_success
  assert_output --partial "ok:"
  refute_output --partial "AR completed but"

  # --strict alone is inert without a state file.
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-frontmatter "$WD/dv.md" --strict
  assert_success
  refute_output --partial "fail:"
}
