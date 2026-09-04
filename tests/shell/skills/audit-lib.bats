#!/usr/bin/env bats
# Tests for skills/shared/lib/audit-lib.sh — the single audit.jsonl appender for the
# skills tree. Two families: the header contract every shared library in this plugin
# owes (anti-execution guard, include guard, no readonly, no load-time side effect),
# and the row contract its callers depend on (key order, symlink refusal, degradation).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/shared/lib/audit-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  LIB_PATH="$PLUGIN_ROOT/$LIB"
  LOG="$WD/logs/audit.jsonl"
}

teardown() {
  _test_helper_cleanup
}

# Run a snippet with the library sourced. Keeping this out of the arms means each arm
# shows only the behaviour it asserts.
withlib() {
  run bash -c "set -euo pipefail; . '$LIB_PATH'; $1"
}

# ---------------------------------------------------------------------------
# Header contract
# ---------------------------------------------------------------------------
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

@test "H3: the library declares no readonly and reads no plugin-root variable" {
  run grep -nE '^[[:space:]]*(readonly|declare -r)\b' "$LIB_PATH"
  assert_failure
  run grep -n 'CLAUDE_PLUGIN_ROOT' "$LIB_PATH"
  assert_failure
}

@test "H4: sourcing writes nothing and changes no directory" {
  run bash -c "set -euo pipefail; cd '$WD'; . '$LIB_PATH'; pwd -P; ls -A | wc -l"
  assert_success
  assert_line --index 0 "$(cd "$WD" && pwd -P)"
  assert_line --index 1 --regexp '^ *0$'
}

# ---------------------------------------------------------------------------
# Row contract
# ---------------------------------------------------------------------------
@test "R1: key order is ts, actor, action, subject, result, metadata" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s \
    --result ok --meta '{\"k\":1}'"
  assert_success
  run jq -rc 'keys_unsorted | join(",")' "$LOG"
  assert_output 'ts,actor,action,subject,result,metadata'
}

@test "R2: subject is omitted entirely when --subject is not passed" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok"
  run jq -rc 'keys_unsorted | join(",")' "$LOG"
  assert_output 'ts,actor,action,result,metadata'
}

@test "R3: an empty --subject still emits the key — absent and blank stay distinct" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject '' --result ok"
  run jq -r '.subject' "$LOG"
  assert_output ''
  run jq -e 'has("subject")' "$LOG"
  assert_success
}

@test "R4: the log directory is created when it does not exist" {
  [ ! -d "$WD/logs" ]
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok"
  assert_success
  [ -f "$LOG" ]
}

@test "R5: a symlinked audit.jsonl is refused, and the target is not written" {
  mkdir -p "$WD/logs"
  printf 'untouched\n' > "$WD/victim"
  ln -s "$WD/victim" "$LOG"
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok"
  assert_success
  run cat "$WD/victim"
  assert_output 'untouched'
}

@test "R6: metadata that is not valid JSON degrades but never drops the row" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok \
    --meta 'not json'"
  assert_success
  run jq -e '.action == "act" and .metadata._meta_invalid == true' "$LOG"
  assert_success
}

@test "R7: an omitted --meta becomes an empty object, not a dropped row" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok"
  run jq -rc '.metadata' "$LOG"
  assert_output '{}'
}

@test "R8: quotes, backslashes and newlines in a value cannot corrupt the line" {
  withlib "corpflow_audit_row --file '$LOG' --actor a \
    --action 'he said \"hi\"' --result ok --meta '{\"r\":\"a\\\\b\"}'"
  assert_success
  run wc -l < "$LOG"
  assert_output --regexp '^ *1$'
  run jq -r '.action' "$LOG"
  assert_output 'he said "hi"'
}

@test "R9: a missing required flag emits no row and returns 0" {
  withlib "corpflow_audit_row --file '$LOG' --action act --result ok; echo rc=\$?"
  assert_success
  assert_output 'rc=0'
  [ ! -e "$LOG" ]
}

@test "R10: a flag given with no value does not shift past the end under set -e" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok --meta"
  assert_success
  run jq -rc '.metadata' "$LOG"
  assert_output '{}'
}

@test "R11: an unwritable log directory never aborts the caller" {
  mkdir -p "$WD/logs"
  chmod 500 "$WD/logs"
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --result ok; echo rc=\$?"
  chmod 700 "$WD/logs"
  assert_success
  assert_output 'rc=0'
}

# ---------------------------------------------------------------------------
# jq-absent degradation — the shape web-capture.bats T10 pins for the adapters.
# ---------------------------------------------------------------------------
@test "R12: without jq the row is minimal, valid and carries no metadata key" {
  run_script_env --hide jq --source "$LIB" corpflow_audit_row \
    --file "$LOG" --actor web-capture-adapter --action captured \
    --subject 'wt/slug' --result ok --meta '{"bytes":15}'
  assert_success
  run jq -e '.actor == "web-capture-adapter" and .subject == "wt/slug" and (has("metadata") | not)' "$LOG"
  assert_success
}

@test "R13: without jq a quote in a value is reduced, not emitted into the literal" {
  run bash -c "PATH=/usr/bin:/bin; . '$LIB_PATH'; \
    _corpflow_audit_row_nojq TS 'a\"b' 'c d' ok 1 'wt/slug'"
  assert_success
  assert_output '{"ts":"TS","actor":"a_b","action":"c_d","subject":"wt/slug","result":"ok"}'
  run bash -c "printf '%s' '$output' | jq -e .actor"
  assert_success
}
