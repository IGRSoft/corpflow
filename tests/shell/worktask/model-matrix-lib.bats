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

@test "model_matrix_rows exits 3 rather than executing when run directly" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
  assert_output --partial "source it, do not execute it directly"
}
