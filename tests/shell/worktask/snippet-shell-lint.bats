#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/snippet-shell-lint.sh.
# Contracts (from the header):
#   - rule a: an indented code block outside fences, one report per block
#   - rule b: a sh/shell/zsh/console fence, or an unlabelled fence with a shell body
#   - rule c: a bare *.sh run inside a bash fence; `.`, source, assignments and
#     `bash x.sh` are fine
#   - the section ends at the next heading of the same or higher level, outside fences
#   - exit 2 on a missing heading, an unreadable file or a bad flag
#   - default run (ENFORCEMENT): the four seed-path sections are clean —
#     commands/worktask.md, skills/worktask/references/initialization-patterns.md,
#     skills/worktask/references/handoff-protocol.md, skills/megatask/SKILL.md
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/snippet-shell-lint.sh"

# shellcheck disable=SC2016,SC1003 # fixtures are literal shell text, never expanded
setup() {
  WD="$(mk_tmpworkdir)"
  local f='```' tab
  tab="$(printf '\t')"
  printf '%s\n' '## Target A' 'prose' '' '    indented.sh --flag' '    second' '' \
    '    same block' 'back to prose' '' "${tab}tab-indented.sh" > "$WD/a.md"
  printf '%s\n' '## Target B' "${f}sh" 'echo hi' "$f" '' "$f" 'git status' "$f" \
    "${f}json" '{"run": "x.sh"}' "$f" > "$WD/b.md"
  printf '%s\n' '## Target C' "${f}bash" 'foo.sh --flag' 'if check.sh; then' '  echo ok' \
    'fi' 'a || "$R/b.sh"' "$f" > "$WD/c.md"
  printf '%s\n' '# Doc' '## Target N' 'Prose line.' "   ${f}bash" '   . lib.sh' \
    '   source lib.sh' '       indented body stays in the fence' '   X="$P/a.sh"' \
    '   out=$(bash a.sh)' '   V=1 bash a.sh' "   $f" "${f}json" '{"run": "x.sh"}' "$f" \
    "${f}bash" 'cmd --flag \' '  next.sh' 'echo "a; b.sh"' "$f" > "$WD/n.md"
  printf '%s\n' "${f}text" '## Target S' "$f" '## Target S' "${f}bash" '## not a heading' \
    "$f" "${f}bash" 'inside.sh' "$f" '## Next' "${f}bash" 'after.sh' "$f" > "$WD/s.md"
}

@test "rule a: indented code blocks are flagged once per block" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/a.md::## Target A"
  assert_failure 1
  assert_output --partial "$WD/a.md:4: rule-a:"
  assert_output --partial "$WD/a.md:10: rule-a:"
  refute_output --partial "$WD/a.md:7: rule-a:"
  assert_output --partial "$WD/a.md::## Target A: 2 violation(s)"
}

@test "rule b: a shell-labelled fence and an unlabelled shell fence are flagged; json is exempt" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/b.md::## Target B"
  assert_failure 1
  assert_output --partial "$WD/b.md:2: rule-b:"
  assert_output --partial "$WD/b.md:6: rule-b:"
  refute_output --partial "$WD/b.md:9:"
  assert_output --partial "2 violation(s)"
}

@test "rule c: bare .sh runs inside bash fences are flagged" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/c.md::## Target C"
  assert_failure 1
  assert_output --partial "$WD/c.md:3: rule-c:"
  assert_output --partial "$WD/c.md:4: rule-c:"
  assert_output --partial "$WD/c.md:7: rule-c:"
  assert_output --partial "3 violation(s)"
}

@test "negatives: sourcing, assignments, bash runs, continuations and json pass" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/n.md::## Target N"
  assert_success
  refute_output --partial "rule-"
  assert_output --partial "$WD/n.md::## Target N: ok"
}

@test "boundary: fenced heading lookalikes are ignored and later sections are not linted" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/s.md::## Target S"
  assert_failure 1
  assert_output --partial "$WD/s.md:9: rule-c:"
  refute_output --partial "$WD/s.md:13:"
  assert_output --partial "1 violation(s)"
}

@test "errors: a missing heading, an unreadable file or a bad flag exits 2" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/a.md::## No Such Heading"
  assert_failure 2
  [[ "$stderr" == *"heading not found"* ]] || fail "stderr: $stderr"
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/missing.md::## Target A"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/a.md"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
  printf '%s\n' '## Target U' '```bash' 'bash a.sh' > "$WD/u.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --target "$WD/u.md::## Target U"
  assert_failure 2
}

@test "enforcement: the default seed-path sections are clean, resolved from any cwd" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "commands/worktask.md::## Phase 1: Planning: ok"
  assert_output --partial "skills/worktask/references/initialization-patterns.md::## PL0 state.json Initialization: ok"
  assert_output --partial "skills/worktask/references/handoff-protocol.md::### PL0 seed (initial state): ok"
  assert_output --partial "skills/megatask/SKILL.md::### Seeding a track's PL: ok"
}

@test "self-test: --self-test exits 0 and reports ALL PASS" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}
