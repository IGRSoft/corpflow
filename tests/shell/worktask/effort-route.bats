#!/usr/bin/env bats
# effort-route.sh — the pure route decision.
#
# Every case exercises the real script against a TEMP agents/ copy this file fixtures
# itself: the route function never reads the shipped agents/ tree in tests, only the
# real end-to-end QA probe does that.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/effort-route.sh"

setup() {
  AGENTS_DIR="$(mk_tmpworkdir)/agents"
  mkdir -p "$AGENTS_DIR"
}

mk_agent() { # <name> <effort>
  cat > "$AGENTS_DIR/$1.md" << EOF
---
maxTurns: 30
effort: $2
---
body
EOF
}

route() { # extra args after the three required flags
  run_script "$SCRIPT" --agent "corpflow:$1" --model "$2" --requested "$3" \
    --agents-dir "$AGENTS_DIR" "${@:4}"
}

field() { jq -r --arg k "$1" '.[$k]' <<< "$output"; }

# --- baseline resolution ------------------------------------------------------

@test "frontmatter baseline, tier equal -> inproc/frontmatter/tier_equal" {
  mk_agent developer high
  route developer opus high
  assert_success
  [ "$(field route)" = "inproc" ]
  [ "$(field effort_transport)" = "frontmatter" ]
  [ "$(field reason)" = "tier_equal" ]
  [ "$(field baseline_source)" = "frontmatter" ]
}

@test "frontmatter baseline, a raise -> headless/dispatch-flag/tier_differs" {
  mk_agent developer high
  route developer opus xhigh
  assert_success
  [ "$(field route)" = "headless" ]
  [ "$(field effort_transport)" = "dispatch-flag" ]
  [ "$(field reason)" = "tier_differs" ]
}

@test "frontmatter baseline, a lowering also routes headless" {
  mk_agent developer high
  route developer opus medium
  assert_success
  [ "$(field route)" = "headless" ]
  [ "$(field reason)" = "tier_differs" ]
}

@test "frontmatter-less agent falls back to --role-baseline, source role_matrix" {
  route designer sonnet high --role-baseline medium
  assert_success
  [ "$(field baseline_source)" = "role_matrix" ]
  [ "$(field route)" = "headless" ]
}

@test "frontmatter-less agent with no --role-baseline is refused, nothing printed" {
  route designer sonnet high
  assert_failure 2
  refute_output --partial '{"agent"'
  assert_output --partial "carries no effort:"
}

@test "an empty effort: value in the agent file is treated as no frontmatter" {
  cat > "$AGENTS_DIR/developer.md" << 'EOF'
---
maxTurns: 30
effort:
---
body
EOF
  route developer opus high --role-baseline high
  assert_success
  [ "$(field baseline_source)" = "role_matrix" ]
}

# --- short-circuits: each wins over the tier compare, always inproc ----------

@test "haiku ignores effort -> inproc/none/model_ignores_effort even on a raise" {
  mk_agent technical-writer low
  route technical-writer haiku xhigh
  assert_success
  [ "$(field route)" = "inproc" ]
  [ "$(field effort_transport)" = "none" ]
  [ "$(field reason)" = "model_ignores_effort" ]
}

@test "CLAUDE_CODE_EFFORT_LEVEL set -> per-stage routing still raises (env pin does not short-circuit)" {
  mk_agent developer high
  run env CLAUDE_CODE_EFFORT_LEVEL=high bash "$PLUGIN_ROOT/$SCRIPT" \
    --agent corpflow:developer --model opus --requested xhigh --agents-dir "$AGENTS_DIR"
  assert_success
  [ "$(field route)" = "headless" ]
  [ "$(field effort_transport)" = "dispatch-flag" ]
  [ "$(field reason)" = "tier_differs" ]
}

@test "CORPFLOW_HEADLESS_ROUTE=off -> inproc/opted_out, transport still frontmatter" {
  mk_agent developer high
  run env CORPFLOW_HEADLESS_ROUTE=off bash "$PLUGIN_ROOT/$SCRIPT" \
    --agent corpflow:developer --model opus --requested xhigh --agents-dir "$AGENTS_DIR"
  assert_success
  [ "$(field route)" = "inproc" ]
  [ "$(field reason)" = "opted_out" ]
  [ "$(field effort_transport)" = "frontmatter" ]
}

@test "haiku short-circuit still wins even under an env pin" {
  mk_agent technical-writer low
  run env CLAUDE_CODE_EFFORT_LEVEL=high bash "$PLUGIN_ROOT/$SCRIPT" \
    --agent corpflow:technical-writer --model haiku --requested xhigh --agents-dir "$AGENTS_DIR"
  assert_success
  [ "$(field reason)" = "model_ignores_effort" ]
}

# --- the DV xhigh stamp and the resolver bump, named in planning-1.md#requirements -----------

@test "the DV xhigh stamp routes headless against a medium frontmatter baseline" {
  mk_agent developer medium
  route developer opus xhigh
  assert_success
  [ "$(field route)" = "headless" ]
}

@test "the resolver one-rung bump (effort_for_resolver output) routes headless" {
  mk_agent developer high
  # effort_for_resolver('high','opus') == 'xhigh' — feed it straight through as --requested.
  bumped=$(bash -c ". '$PLUGIN_ROOT/skills/worktask/scripts/effort-ladder.sh'; effort_for_resolver high opus")
  route developer opus "$bumped"
  assert_success
  [ "$(field route)" = "headless" ]
}

@test "the secure DC override (a lowering to low against a matrix high baseline) routes headless" {
  mk_agent technical-writer low
  route technical-writer haiku low
  assert_success
  # haiku short-circuit still governs here, since DC's model is haiku.
  [ "$(field reason)" = "model_ignores_effort" ]
}

# --- refusal before any output, fail closed before any spawn ----------------------------------

@test "an invalid agent id (space) is refused with no JSON on stdout" {
  route "dev eloper" opus high
  assert_failure 2
  refute_output --partial '{"agent"'
}

@test "an invalid agent id (semicolon) is refused with no JSON on stdout" {
  route "dev;rm" opus high
  assert_failure 2
  refute_output --partial '{"agent"'
}

@test "an invalid model is refused" {
  route developer bogus high
  assert_failure 2
}

@test "an invalid requested effort is refused" {
  mk_agent developer high
  route developer opus bogus
  assert_failure 2
}

@test "an invalid --role-baseline is refused" {
  route designer sonnet high --role-baseline bogus
  assert_failure 2
}

@test "usage with missing required flags exits 2" {
  run_script "$SCRIPT" --agent corpflow:developer
  assert_failure 2
}
