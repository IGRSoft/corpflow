#!/usr/bin/env bats
# Dedicated coverage-proxy file for model-matrix-lib.sh (coverage-proxy.bats requires one
# per script under skills/**/scripts/). effort-ladder.bats and dc-secure-model.bats already
# exercise these functions against the live doc and against R1-R3 fixtures; this file adds
# direct, script-scoped assertions on the three exported symbols so the script itself, not
# only its downstream consumers, has a dedicated regression home.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/model-matrix-lib.sh"

mml() { # <shell body>
  bash -c "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; $1"
}

# Every case gets its own config dir, so the operator's ~/.claude/CORPFLOW.md never leaks in
# (test_helper.bash sandboxes it suite-wide too) and a user-scope fixture never outlives its test.
setup() {
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/cfg"
  PROJ="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$CLAUDE_CONFIG_DIR" "$PROJ/.context"
}

# _models_md <path> <agent> <model> <effort> — a minimal `## Models` override file.
_models_md() {
  printf '## Models\n\n| Agent | Model | Effort |\n|---|---|---|\n| %s | %s | %s |\n' "$2" "$3" "$4" > "$1"
}

@test "model_matrix_rows returns one row per agents/*.md, tab-separated" {
  run mml "model_matrix_rows | wc -l | tr -d '[:space:]'"
  assert_success
  local agent_count
  agent_count=$(cd "$PLUGIN_ROOT/agents" && ls -1 ./*.md | wc -l | tr -d '[:space:]')
  assert_output "$agent_count"
}

@test "model_override_rows reads a project CORPFLOW.md # Models section, fail-open per row" {
  local doc="${BATS_TEST_TMPDIR}/CORPFLOW.md"
  cat > "$doc" << 'EOF'
## Models

| Agent | Model | Effort |
|-------|-------|--------|
| developer | sonnet | - |
| not-a-real-agent | opus | high |
EOF
  run mml "model_override_rows '$doc'"
  assert_success
  assert_line $'developer\tsonnet\t-\tok'
  assert_line --partial 'not-a-real-agent'
}

@test "model_resolve takes the first of two override rows for one agent, never a garbled pair" {
  local doc="${BATS_TEST_TMPDIR}/CORPFLOW.md"
  cat > "$doc" << 'EOF'
## Models

| Agent | Model | Effort |
|-------|-------|--------|
| developer | sonnet | - |
| developer | haiku | low |
EOF
  run mml "model_resolve developer '' '$doc'"
  assert_success
  assert_output $'sonnet\thigh\tproject-override'
}

@test "model_resolve ranks state.json over CORPFLOW.md over the built-in matrix" {
  local state="${BATS_TEST_TMPDIR}/state.json"
  printf '{"models":{"developer":{"model":"haiku","effort":"low"}}}' > "$state"
  run mml "model_resolve developer '$state'"
  assert_success
  assert_output $'haiku\tlow\tstate'
}

@test "model_resolve falls back to the built-in matrix with no state or override" {
  run mml "model_resolve developer"
  assert_success
  assert_output $'opus\thigh\tmatrix'
}

@test "user scope: a user-only ## Models resolves as user-override" {
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  run mml "corpflow_md_locate '$PROJ/.context' '## Models'"
  assert_success
  assert_output "$CLAUDE_CONFIG_DIR/CORPFLOW.md"$'\tuser'
  run mml "model_resolve developer '' '$CLAUDE_CONFIG_DIR/CORPFLOW.md'"
  assert_success
  assert_output $'sonnet\tlow\tuser-override'
}

@test "user scope: a project ## Models heading wins over the user file, per heading" {
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  _models_md "$PROJ/CORPFLOW.md" developer haiku medium
  run mml "corpflow_md_locate '$PROJ/.context' '## Models'"
  assert_success
  assert_output "$PROJ/CORPFLOW.md"$'\tproject'
  run mml "model_resolve developer '' '$PROJ/CORPFLOW.md'"
  assert_success
  assert_output $'haiku\tmedium\tproject-override'
}

@test "user scope: a project file without ## Models falls through to the user file" {
  printf '## Routing\n\n| Alias | Target |\n|---|---|\n' > "$PROJ/CORPFLOW.md"
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  run mml "corpflow_md_locate '$PROJ' '## Models'"
  assert_success
  assert_output "$CLAUDE_CONFIG_DIR/CORPFLOW.md"$'\tuser'
  run mml "corpflow_md_locate '$PROJ' '## Routing'"
  assert_success
  assert_output "$PROJ/CORPFLOW.md"$'\tproject'
}

@test "user scope: a garbled project ## Models still owns the heading, never the user file" {
  printf '## Models\n\nno table here\n' > "$PROJ/CORPFLOW.md"
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  run mml "corpflow_md_locate '$PROJ' '## Models'"
  assert_output "$PROJ/CORPFLOW.md"$'\tproject'
  run mml "model_override_rows '$PROJ/CORPFLOW.md'"
  assert_failure 3
  run mml "model_resolve developer '' '$PROJ/CORPFLOW.md'"
  assert_output $'opus\thigh\tmatrix'
}

@test "user scope: CLAUDE_CONFIG_DIR is honoured over HOME, HOME/.claude only when it is unset" {
  local home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$home/.claude"
  _models_md "$home/.claude/CORPFLOW.md" developer haiku low
  run env HOME="$home" bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_md_locate '' '## Models'"
  assert_failure 1
  run env -u CLAUDE_CONFIG_DIR HOME="$home" bash -c ". '$PLUGIN_ROOT/$LIB'; corpflow_md_locate '' '## Models'"
  assert_success
  assert_output "$home/.claude/CORPFLOW.md"$'\tuser'
  run env -u CLAUDE_CONFIG_DIR HOME="$home" bash -c \
    ". '$PLUGIN_ROOT/$LIB'; model_resolve developer '' '$home/.claude/CORPFLOW.md'"
  assert_output $'haiku\tlow\tuser-override'
}

@test "user scope: a bare project ## Models heading with no content falls through to the user file" {
  printf '## Routing\n\n| Alias | Target |\n|---|---|\n\n## Models\n\n' > "$PROJ/CORPFLOW.md"
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  run mml "corpflow_md_locate '$PROJ' '## Models'"
  assert_success
  assert_output "$CLAUDE_CONFIG_DIR/CORPFLOW.md"$'\tuser'
  printf '## Models\n\n### Notes\n' > "$PROJ/CORPFLOW.md"
  run mml "corpflow_md_locate '$PROJ' '## Models'"
  assert_output "$CLAUDE_CONFIG_DIR/CORPFLOW.md"$'\tuser'
}

@test "user scope: the user file is labelled user-override under any spelling of its path" {
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  ln -s "$CLAUDE_CONFIG_DIR" "${BATS_TEST_TMPDIR}/cfg-link"
  run mml "corpflow_md_source '${BATS_TEST_TMPDIR}/cfg-link/CORPFLOW.md'"
  assert_output "user-override"
  run mml "cd '$CLAUDE_CONFIG_DIR' && corpflow_md_source ./CORPFLOW.md"
  assert_output "user-override"
  run mml "corpflow_md_source '$PROJ/CORPFLOW.md'"
  assert_output "project-override"
}

@test "user scope: a project root that is the config dir reports user, matching its source label" {
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" developer sonnet low
  run mml "corpflow_md_locate '$CLAUDE_CONFIG_DIR/.context' '## Models'"
  assert_success
  assert_output "$CLAUDE_CONFIG_DIR/CORPFLOW.md"$'\tuser'
}

@test "user scope: no file carries the heading -> locate exits 1" {
  run mml "corpflow_md_locate '$PROJ' '## Models'"
  assert_failure 1
  assert_output ""
}

@test "state-patch --resolve-models stamps user-override and audits source and path" {
  command -v jq > /dev/null 2>&1 || skip "jq not available"
  mkdir -p "$PROJ/.context/logs"
  cp "$FIXTURES/worktask/state.sample.json" "$PROJ/.context/state.json"
  _models_md "$CLAUDE_CONFIG_DIR/CORPFLOW.md" qa-engineer opus -
  run env WORKSPACE_ROOT="$PROJ" CONTEXT_DIR="$PROJ/.context" \
    bash "$PLUGIN_ROOT/skills/worktask/scripts/state-patch.sh" --resolve-models
  assert_success
  run jq -e '.models_source == "user-override"
    and .models["qa-engineer"] == {model: "opus", effort: "medium", source: "user-override"}
    and .models.developer.source == "matrix"' "$PROJ/.context/state.json"
  assert_success
  run jq -se --arg p "$CLAUDE_CONFIG_DIR/CORPFLOW.md" \
    'map(select(.action == "model_override")) | length == 1
      and .[0].metadata.source == "user-override" and .[0].metadata.path == $p' \
    "$PROJ/.context/logs/audit.jsonl"
  assert_success
}

@test "model_matrix_rows exits 3 rather than executing when run directly" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
  assert_output --partial "source it, do not execute it directly"
}
