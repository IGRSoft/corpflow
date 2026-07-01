#!/usr/bin/env bats
# Contract tests for skills/worktask/references/desc-lint.sh.
# Contracts (from header + body):
#   - explicit-file mode: within cap => "N chars ok", exit 0
#   - over cap (multi-line block scalar joined) => "OVER", exit 1
#   - no-frontmatter file => skipped (no output line), exit 0
#   - --self-test => "ALL PASS", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/references/desc-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  printf -- '---\nname: a\ndescription: short and sweet\nmodel: sonnet\n---\nbody\n' > "$WD/ok.md"
  printf -- '# plain markdown, no frontmatter\n' > "$WD/plain.md"
  # build an over-cap multi-line block scalar (>250 chars joined)
  local long; long=$(printf 'x%.0s' $(seq 1 130))
  printf -- '---\nname: b\ndescription: |\n  %s\n  %s\nmodel: sonnet\n---\nbody\n' "$long" "$long" > "$WD/over.md"
}

@test "happy: a within-cap description passes (exit 0, 'ok')" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/ok.md"
  assert_success
  assert_output --partial "chars ok"
}

@test "edge: no-frontmatter file is skipped (exit 0, no lint line)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/plain.md"
  assert_success
  refute_output --partial "chars"
}

@test "failure: an over-cap multi-line description fails (exit 1, 'OVER')" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/over.md"
  assert_failure 1
  assert_output --partial "OVER"
  assert_output --partial "cap 250"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}
