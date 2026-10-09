#!/usr/bin/env bats
# effort-route.sh — the pure route decision.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/effort-route.sh"

setup() {
  # The route reads the operator opt-in from the environment; a value leaking in from the
  # shell running the suite would flip every in-process expectation below.
  unset CORPFLOW_HEADLESS_ROUTE
}

route() { # <agent> <model> <tier> [extra args]
  run_script "$SCRIPT" --agent "corpflow:$1" --model "$2" --requested "$3" "${@:4}"
}

route_on() { # same arguments as route(), under the headless opt-in
  run env CORPFLOW_HEADLESS_ROUTE=on bash "$PLUGIN_ROOT/$SCRIPT" \
    --agent "corpflow:$1" --model "$2" --requested "$3" "${@:4}"
}

field() { jq -r --arg k "$1" '.[$k]' <<< "$output"; }

# --- default: in-process, the tier rides the Agent tool's effort parameter -----

@test "default: any tier on a full-ladder model -> inproc/agent-param" {
  local m t
  for m in opus sonnet fable; do
    for t in low medium high xhigh max; do
      route developer "$m" "$t"
      assert_success
      [ "$(field route)" = "inproc" ]
      [ "$(field effort_transport)" = "agent-param" ]
      [ "$(field reason)" = "inproc_default" ]
      [ "$(field requested)" = "$t" ]
    done
  done
}

@test "the route line carries no baseline fields" {
  route developer opus xhigh
  assert_success
  run jq -e 'has("baseline") or has("baseline_source")' <<< "$output"
  assert_failure
}

@test "the resolver one-rung bump (effort_for_resolver output) rides agent-param" {
  # effort_for_resolver('high','opus') == 'xhigh' — feed it straight through as --requested.
  bumped=$(bash -c ". '$PLUGIN_ROOT/skills/worktask/scripts/effort-ladder.sh'; effort_for_resolver high opus")
  route developer opus "$bumped"
  assert_success
  [ "$(field effort_transport)" = "agent-param" ]
  [ "$(field requested)" = "xhigh" ]
}

# --- haiku: no effort parameter at all ------------------------------------------

@test "haiku ignores effort -> inproc/none/model_ignores_effort" {
  route technical-writer haiku xhigh
  assert_success
  [ "$(field route)" = "inproc" ]
  [ "$(field effort_transport)" = "none" ]
  [ "$(field reason)" = "model_ignores_effort" ]
}

@test "haiku wins over the headless opt-in" {
  route_on technical-writer haiku low
  assert_success
  [ "$(field route)" = "inproc" ]
  [ "$(field effort_transport)" = "none" ]
}

# --- CORPFLOW_HEADLESS_ROUTE=on: the opt-in headless surface ---------------------

@test "opt-in: a non-haiku dispatch routes headless/dispatch-flag" {
  route_on developer opus high
  assert_success
  [ "$(field route)" = "headless" ]
  [ "$(field effort_transport)" = "dispatch-flag" ]
  [ "$(field reason)" = "headless_opt_in" ]
}

@test "any value other than on keeps the default" {
  run env CORPFLOW_HEADLESS_ROUTE=off bash "$PLUGIN_ROOT/$SCRIPT" \
    --agent corpflow:developer --model opus --requested xhigh
  assert_success
  [ "$(field route)" = "inproc" ]
  [ "$(field effort_transport)" = "agent-param" ]
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
  route developer opus bogus
  assert_failure 2
}

@test "a removed baseline flag is a usage error" {
  route designer sonnet high --role-baseline medium
  assert_failure 2
  refute_output --partial '{"agent"'
}

@test "usage with missing required flags exits 2" {
  run_script "$SCRIPT" --agent corpflow:developer
  assert_failure 2
}
