#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/section-lint.sh.
# Contracts (from header + body):
#   - explicit-file mode: all sections within cap => "N sections, all ≤ cap ok", exit 0
#   - over cap => "file:line: N chars (cap 1000) — OVER :: heading", exit 1
#   - heading-lookalikes inside fenced blocks never start a section
#   - a tilde fence wrapping backtick fences is ONE block (marker-aware toggle)
#   - --self-test => "ALL PASS", exit 0
#   - default repo mode: every tracked section in agents/, commands/, skills/
#     (minus fixture/test-vector md) is ≤ 1000 chars => exit 0 (ENFORCEMENT)
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/section-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  printf -- '---\nname: a\ndescription: d\n---\npreamble\n## ok\nshort body\n' > "$WD/ok.md"
  { printf -- '## big\n'; printf 'x%.0s' $(seq 1 1100); printf '\n'; } > "$WD/over.md"
  printf -- '## real\n```markdown\n## fake heading\n```\ntail\n' > "$WD/fenced.md"
  printf -- '## real\n~~~markdown\n```bash\ninner\n```\n## fake\n~~~\n' > "$WD/tilde.md"
}

@test "happy: a file with all sections within cap passes (exit 0, 'ok')" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/ok.md"
  assert_success
  assert_output --partial "sections, all ≤ cap ok"
}

@test "failure: an over-cap section fails (exit 1, 'OVER', 'cap 1000', file:line)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/over.md"
  assert_failure 1
  assert_output --partial "OVER"
  assert_output --partial "cap 1000"
  assert_output --partial "$WD/over.md:1:"
}

@test "edge: a heading inside a fenced block does not start a section" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/fenced.md"
  assert_success
  assert_output --partial "1 sections"
}

@test "edge: a tilde fence with nested backtick fences counts as one block" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/tilde.md"
  assert_success
  assert_output --partial "1 sections"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

@test "enforcement: every tracked section in agents/, commands/, skills/ is ≤ 1000 chars" {
  cd "$PLUGIN_ROOT"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial " 0 sections over cap"
}
