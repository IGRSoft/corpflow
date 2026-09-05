#!/usr/bin/env bats
# Tests for skills/shared/lib/state-read-lib.sh — the two ledger fields every worktask
# script reads before it can name anything. The arms that matter are the degradation ones:
# the inline copies this replaces each carried their own fallback, and three of them
# deliberately used a different default from the rest.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/shared/lib/state-read-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  LIB_PATH="$PLUGIN_ROOT/$LIB"
  STATE="$WD/state.json"
  printf '%s' '{"version":2,"worktask_id":"wt-42","run_index":3}' > "$STATE"
}

teardown() {
  _test_helper_cleanup
}

withlib() {
  run bash -c "set -euo pipefail; . '$LIB_PATH'; $1"
}

@test "H1: executing the library directly is refused with exit 2" {
  run bash "$LIB_PATH"
  assert_failure 2
  assert_output --partial 'source it, do not execute it directly'
}

@test "H2: a double source is a no-op, not a re-definition error" {
  run bash -c "set -euo pipefail; . '$LIB_PATH'; . '$LIB_PATH'; echo ok"
  assert_success
  assert_output 'ok'
}

@test "H3: no readonly, no plugin-root variable, no load-time side effect" {
  run grep -nE '^[[:space:]]*(readonly|declare -r)\b' "$LIB_PATH"
  assert_failure
  run grep -n 'CLAUDE_PLUGIN_ROOT' "$LIB_PATH"
  assert_failure
  run bash -c "set -euo pipefail; cd '$WD'; . '$LIB_PATH'; ls -A | wc -l"
  assert_success
  assert_output --regexp '^ *1$'
}

@test "S1: both fields are read from the ledger" {
  withlib "corpflow_worktask_id '$STATE'; printf :; corpflow_run_index '$STATE'"
  assert_output 'wt-42:3'
}

@test "S2: an absent ledger yields the documented defaults, never an abort" {
  withlib "corpflow_worktask_id '$WD/nope.json'; printf :; corpflow_run_index '$WD/nope.json'"
  assert_success
  assert_output 'unknown:0'
}

@test "S3: an unparseable ledger degrades exactly like an absent one" {
  printf 'not json at all' > "$STATE"
  withlib "corpflow_worktask_id '$STATE'; printf :; corpflow_run_index '$STATE'"
  assert_success
  assert_output 'unknown:0'
}

@test "S4: a null field takes the default rather than the string 'null'" {
  printf '%s' '{"worktask_id":null,"run_index":null}' > "$STATE"
  withlib "corpflow_worktask_id '$STATE'; printf :; corpflow_run_index '$STATE'"
  assert_output 'unknown:0'
}

@test "S5: the default is an argument — an explicit empty default survives" {
  printf '%s' '{"version":2}' > "$STATE"
  withlib "printf '[%s]' \"\$(corpflow_worktask_id '$STATE' '')\""
  assert_output '[]'
}

@test "S6: run_index 0 is distinguishable from absent when the caller asks" {
  printf '%s' '{"run_index":0}' > "$STATE"
  withlib "printf '[%s]' \"\$(corpflow_run_index '$STATE' '')\""
  assert_output '[0]'
  printf '%s' '{}' > "$STATE"
  withlib "printf '[%s]' \"\$(corpflow_run_index '$STATE' '')\""
  assert_output '[]'
}

@test "S7: without jq the defaults apply and the caller still runs" {
  run_script_env --hide jq --source "$LIB" corpflow_worktask_id "$STATE"
  assert_success
  assert_output 'unknown'
}

@test "S8: corpflow_state_str reads an arbitrary path with its own default" {
  printf '%s' '{"metadata":{"base_ref":"develop"}}' > "$STATE"
  withlib "corpflow_state_str '$STATE' '.metadata.base_ref' none"
  assert_output 'develop'
  withlib "corpflow_state_str '$STATE' '.metadata.absent' none"
  assert_output 'none'
}

@test "S9: an unreadable ledger is a default, not a permission error on stderr" {
  chmod 000 "$STATE"
  withlib "corpflow_worktask_id '$STATE' 2>/dev/null"
  chmod 600 "$STATE"
  assert_success
  assert_output 'unknown'
}
