#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/desc-lint.sh.
# Contracts (from header + body):
#   - explicit-file mode: within cap => "N chars ok", exit 0
#   - over cap (multi-line block scalar joined) => "OVER", exit 1
#   - no-frontmatter file => skipped (no output line), exit 0
#   - --self-test => "ALL PASS", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/desc-lint.sh"

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

# --- cap boundary ------------------------------------------------------------
# The cap is an inclusive <=250: 250 passes, 251 does not. Asserting only a
# far-over case (260+) left the comparison operator itself untested — a `>=`
# slip would have gone unnoticed.

_desc_file() {
  # _desc_file <path> <n> — frontmatter whose joined description is exactly n chars.
  local path="$1" n="$2" body
  body="$(printf 'x%.0s' $(seq 1 "$n"))"
  printf -- '---\nname: a\ndescription: %s\nmodel: sonnet\n---\nbody\n' "$body" > "$path"
}

@test "boundary: 249 chars is within cap (exit 0)" {
  _desc_file "$WD/b249.md" 249
  run_script_env -- "$SCRIPT" "$WD/b249.md"
  assert_success
  assert_output --partial "b249.md: 249 chars ok"
}

@test "boundary: exactly 250 chars is within cap (inclusive, exit 0)" {
  _desc_file "$WD/b250.md" 250
  run_script_env -- "$SCRIPT" "$WD/b250.md"
  assert_success
  assert_output --partial "b250.md: 250 chars ok"
}

@test "boundary: 251 chars is over cap (exit 1)" {
  _desc_file "$WD/b251.md" 251
  run_script_env -- "$SCRIPT" "$WD/b251.md"
  assert_failure 1
  assert_output --partial "251 chars (cap 250) — OVER"
}

@test "boundary: one over-cap file among many fails the whole run" {
  _desc_file "$WD/b250.md" 250
  _desc_file "$WD/b251.md" 251
  run_script_env -- "$SCRIPT" "$WD/ok.md" "$WD/b250.md" "$WD/b251.md"
  assert_failure 1
  assert_output --partial "b251.md: 251 chars"
  # The within-cap files are still reported, not short-circuited away.
  assert_output --partial "b250.md: 250 chars ok"
}

# --- default (no-argument) mode ----------------------------------------------

@test "default mode: this repo's own agents/commands/skills are all within cap" {
  # No-argument mode cds to the repo root and lints agents/*.md, commands/*.md
  # and skills/*/SKILL.md, filtering the ok lines so only violations print.
  # These descriptions are ambient context in every session, so an over-cap one
  # is a real defect. Nothing in the suite exercised this mode before; when it
  # was added it immediately failed on skills/cross-plugin-handoff/SKILL.md.
  run_script_env --cwd "$PLUGIN_ROOT" -- "$SCRIPT"
  assert_success
  assert_output ""
}

@test "default mode: an over-cap file in the default set is found and named" {
  # Falsification arm for the test above, whose clean tree prints nothing: this
  # proves the no-arg glob really walks agents/ and reports what it finds.
  local repo body
  body="$(printf 'x%.0s' $(seq 1 251))"
  repo="$(mk_git_fixture \
    --file "agents/bad.md:---\nname: bad\ndescription: ${body}\n---\nbody\n" \
    --file 'agents/good.md:---\nname: good\ndescription: fine\n---\nbody\n')"
  run_script_env --cwd "$repo" -- "$SCRIPT"
  assert_failure 1
  assert_output --partial "agents/bad.md: 251 chars (cap 250) — OVER"
  refute_output --partial "agents/good.md"
}
