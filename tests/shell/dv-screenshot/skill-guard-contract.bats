#!/usr/bin/env bats
# Contract test for the dv-screenshot-capture skill guard.
#
# The skill is model-invocable, so nothing in the harness stops a call made outside a
# worktask: its first step does. These predicates keep that step and the frontmatter that
# makes it necessary from drifting apart.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SKILL="skills/dv-screenshot-capture/SKILL.md"
GUARD_SCRIPT="skills/dv-screenshot-capture/scripts/resolve-worktask.sh"

_frontmatter() {
  awk 'NR == 1 && /^---[[:space:]]*$/ { on = 1; next }
       on && /^---[[:space:]]*$/ { exit }
       on { print }' "$PLUGIN_ROOT/$SKILL"
}

# H2 section plus its H3 children; `^## ` never matches a `###` heading.
_guard_section() {
  awk '/^## Worktask guard/ { on = 1; print; next }
       on && /^## / { exit }
       on { print }' "$PLUGIN_ROOT/$SKILL"
}

@test "frontmatter carries no disable-model-invocation key and no G3 comment" {
  local fm
  fm="$(_frontmatter)"
  [[ "$fm" == *"name: dv-screenshot-capture"* ]]
  run grep -n 'disable-model-invocation' <<< "$fm"
  assert_failure
  run grep -nE '^#[[:space:]]*G3:' <<< "$fm"
  assert_failure
}

@test "argument-hint names <task_id> directly after <worktask_id>" {
  run grep -E '^argument-hint:.*<worktask_id> <task_id>' <<< "$(_frontmatter)"
  assert_success
}

@test "the guard step runs resolve-worktask.sh with --task-id" {
  [ -f "$PLUGIN_ROOT/$GUARD_SCRIPT" ]
  local guard
  guard="$(_guard_section)"
  [ -n "$guard" ]
  run grep -F 'bash "${CLAUDE_SKILL_DIR}/scripts/resolve-worktask.sh" --task-id' <<< "$guard"
  assert_success
}

@test "the guard step stops on exit 4 with the no-worktask line and writes nothing" {
  local guard
  guard="$(_guard_section)"
  run grep -E '^\| exit 4' <<< "$guard"
  assert_success
  assert_output --partial 'no worktask resolved'
  assert_output --partial 'write nothing'
  assert_output --partial 'stop'
  run grep -E '^\| exit 2' <<< "$guard"
  assert_success
  assert_output --partial 'stderr'
}

@test "the guard section precedes the storage layout" {
  local guard_line storage_line
  guard_line="$(grep -n '^## Worktask guard' "$PLUGIN_ROOT/$SKILL" | head -1 | cut -d: -f1)"
  storage_line="$(grep -n '^## Storage layout' "$PLUGIN_ROOT/$SKILL" | head -1 | cut -d: -f1)"
  [ -n "$guard_line" ]
  [ -n "$storage_line" ]
  [ "$guard_line" -lt "$storage_line" ]
}

@test "no worktask-wide dv-NN capture name survives in the skill" {
  run grep -nE 'dv-(NN|[0-9]{2})-' "$PLUGIN_ROOT/$SKILL"
  assert_failure
}
