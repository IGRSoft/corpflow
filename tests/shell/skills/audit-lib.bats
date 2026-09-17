#!/usr/bin/env bats
# Tests for skills/shared/lib/audit-lib.sh — the single audit.jsonl appender for the
# skills tree. Two families: the header contract every shared library in this plugin
# owes (anti-execution guard, include guard, no readonly, no load-time side effect),
# and the row contract its callers depend on (key order, required keys, symlink
# refusal, degradation).
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

# rejected <flags> <key>: the call writes nothing, leaves LAST_RC=1, survives set -e,
# and names <key> on exactly one stderr line.
rejected() {
  run --separate-stderr bash -c "set -euo pipefail; . '$LIB_PATH'
    corpflow_audit_row --file '$LOG' --actor a --action act --result ok $1
    echo \"rc=\$? last=\$CORPFLOW_AUDIT_LAST_RC\""
  assert_success
  assert_output 'rc=0 last=1'
  [ ! -e "$LOG" ] || fail "a row was written for: $1"
  [ "${#stderr_lines[@]}" -eq 1 ] || fail "expected one stderr line, got: $stderr"
  [[ "$stderr" == *"$2"* ]] || fail "stderr does not name $2: $stderr"
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
@test "R1: key order is ts, actor, action, subject, result, task_id, metadata" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s \
    --result ok --task-id DV0 --meta '{\"k\":1}'"
  assert_success
  run jq -rc 'keys_unsorted | join(",")' "$LOG"
  assert_output 'ts,actor,action,subject,result,task_id,metadata'
}

@test "R2: a missing or empty --subject is rejected, named, and survivable" {
  rejected "--task-id DV0" subject
  rejected "--subject '' --task-id DV0" subject
}

@test "R3: a missing or empty --task-id is rejected, named, and survivable" {
  rejected "--subject s" task_id
  rejected "--subject s --task-id ''" task_id
}

@test "R3b: both keys missing still costs exactly one stderr line" {
  rejected "" "subject and task_id"
}

@test "R3c: without jq the same rejection holds" {
  run_script_env --hide jq --separate-stderr --source "$LIB" corpflow_audit_row \
    --file "$LOG" --actor a --action act --subject s --result ok
  assert_success
  [ ! -e "$LOG" ]
  [[ "$stderr" == *task_id* ]]
}

@test "R4: the log directory is created when it does not exist" {
  [ ! -d "$WD/logs" ]
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok"
  assert_success
  [ -f "$LOG" ]
}

@test "R5: a symlinked audit.jsonl is refused, and the target is not written" {
  mkdir -p "$WD/logs"
  printf 'untouched\n' > "$WD/victim"
  ln -s "$WD/victim" "$LOG"
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok"
  assert_success
  run cat "$WD/victim"
  assert_output 'untouched'
}

@test "R6: metadata that is not valid JSON degrades but never drops the row" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok \
    --meta 'not json'"
  assert_success
  run jq -e '.action == "act" and .metadata._meta_invalid == true' "$LOG"
  assert_success
}

@test "R7: an omitted --meta becomes an empty object, not a dropped row" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok"
  run jq -rc '.metadata' "$LOG"
  assert_output '{}'
}

@test "R8: quotes, backslashes and newlines in a value cannot corrupt the line" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --subject s --task-id DV0 \
    --action 'he said \"hi\"' --result ok --meta '{\"r\":\"a\\\\b\"}'"
  assert_success
  run wc -l < "$LOG"
  assert_output --regexp '^ *1$'
  run jq -r '.action' "$LOG"
  assert_output 'he said "hi"'
}

@test "R9: a missing file, actor, action or result emits no row and returns 0" {
  withlib "corpflow_audit_row --file '$LOG' --action act --subject s --task-id DV0 --result ok; echo rc=\$?"
  assert_success
  assert_output 'rc=0'
  [ ! -e "$LOG" ]
}

@test "R10: a flag given with no value does not shift past the end under set -e" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok --meta"
  assert_success
  run jq -rc '.metadata' "$LOG"
  assert_output '{}'
}

@test "R11: an unwritable log directory never aborts the caller" {
  mkdir -p "$WD/logs"
  chmod 500 "$WD/logs"
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok; echo rc=\$?"
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
    --subject 'wt/slug' --task-id unknown --result ok --meta '{"bytes":15}'
  assert_success
  run jq -e '.actor == "web-capture-adapter" and .subject == "wt/slug" and .task_id == "unknown" and (has("metadata") | not)' "$LOG"
  assert_success
}

@test "R13: without jq a quote in a value is reduced, not emitted into the literal" {
  run bash -c "PATH=/usr/bin:/bin; . '$LIB_PATH'; \
    _corpflow_audit_row_nojq TS 'a\"b' 'c d' ok 'wt/slug' 'D\"V0'"
  assert_success
  assert_output '{"ts":"TS","actor":"a_b","action":"c_d","subject":"wt/slug","result":"ok","task_id":"D_V0"}'
  run bash -c "printf '%s' '$output' | jq -e .actor"
  assert_success
}

# ---------------------------------------------------------------------------
# task_id and the write-status out-parameter
# ---------------------------------------------------------------------------
@test "R14: without jq task_id still sits between result and metadata" {
  run_script_env --hide jq --source "$LIB" corpflow_audit_row \
    --file "$LOG" --actor a --action act --subject s --result ok --task-id FN3 --meta-kv k=v
  run jq -rc 'keys_unsorted | join(",")' "$LOG"
  assert_output 'ts,actor,action,subject,result,task_id,metadata'
}

@test "R15: a lost row is reported through CORPFLOW_AUDIT_LAST_RC, not the return code" {
  mkdir -p "$WD/logs"
  printf 'untouched\n' > "$WD/victim"
  ln -s "$WD/victim" "$LOG"
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok; \
    echo rc=\$? last=\$CORPFLOW_AUDIT_LAST_RC"
  assert_success
  assert_output 'rc=0 last=1'
}

@test "R16: a written row sets CORPFLOW_AUDIT_LAST_RC to 0" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok; \
    echo last=\$CORPFLOW_AUDIT_LAST_RC"
  assert_success
  assert_output 'last=0'
}

# ---------------------------------------------------------------------------
# --meta-kv — the flat pairs that survive a jq-less host
# ---------------------------------------------------------------------------
@test "R17: --meta-kv pairs merge over --meta and win on a key collision" {
  withlib "corpflow_audit_row --file '$LOG' --actor a --action act --subject s --task-id DV0 --result ok \
    --meta '{\"keep\":1,\"reason\":\"old\"}' --meta-kv reason=new --meta-kv extra=two"
  run jq -rc '.metadata' "$LOG"
  assert_output '{"keep":1,"reason":"new","extra":"two"}'
}

@test "R18: without jq a --meta-kv pair still reaches the row" {
  run_script_env --hide jq --source "$LIB" corpflow_audit_row \
    --file "$LOG" --actor orchestrator --action fn_attachments_preseed_failed \
    --subject FN0 --task-id unknown --result error --meta-kv reason=base_branch_unresolved
  assert_success
  run jq -r '.metadata.reason' "$LOG"
  assert_output 'base_branch_unresolved'
}

@test "R19: without jq a quoting-hostile --meta-kv value cannot inject a key" {
  run_script_env --hide jq --source "$LIB" corpflow_audit_row \
    --file "$LOG" --actor a --action act --subject s --task-id DV0 --result error \
    --meta-kv 'reason=x" ,"injected":"y'
  assert_success
  run jq -e . "$LOG"
  assert_success
  run jq -r '.injected // .metadata.injected // "absent"' "$LOG"
  assert_output 'absent'
}

@test "R20: without jq and without --meta-kv there is no metadata key at all" {
  run_script_env --hide jq --source "$LIB" corpflow_audit_row \
    --file "$LOG" --actor a --action act --subject s --task-id DV0 --result ok --meta '{"dropped":1}'
  assert_success
  run jq -e 'has("metadata") | not' "$LOG"
  assert_success
}
