#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/ack-check.sh and the `state-patch.sh --ack`
# row it reads. Exit contract: 0 clear, 1 not-delivered, 2 usage, 3 acted_on mismatch.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/ack-check.sh"
PATCH="skills/worktask/scripts/state-patch.sh"

setup() {
  ACK="$FIXTURES/worktask/ack"
  WD="$(mk_tmpworkdir)"
}

@test "supersede: B acked and named in acted_on reports A superseded, B acked, match (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.supersede.jsonl" \
    --artifact "$ACK/development-acted-m2.md"
  assert_success
  assert_line "msg DV0-m1 superseded send=ok"
  assert_line "msg DV0-m2 acked send=ok"
  assert_line "acted_on DV0-m2 expected=DV0-m2 match"
  assert_line "verdict: clear"
  refute_output --partial "DV1-m1"
}

@test "supersede: acted_on naming the superseded A is a mismatch (exit 3)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.supersede.jsonl" \
    --artifact "$ACK/development-acted-m1.md"
  assert_failure 3
  assert_line "acted_on DV0-m1 expected=DV0-m2 mismatch"
  assert_line "verdict: mismatch"
}

@test "unacked: a send ok with no ack is not delivered and not acted on, even when claimed (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.unacked.jsonl" \
    --artifact "$ACK/development-acted-m1.md"
  assert_failure 1
  assert_line "msg DV0-m1 not-delivered send=ok"
  assert_line "verdict: not-delivered"
  refute_output --partial " match"
  refute_output --partial "expected=DV0-m1"
}

@test "unacked: delivery-only mode prints no acted_on line and still exits 1" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.unacked.jsonl"
  assert_failure 1
  refute_output --partial "acted_on"
}

@test "legacy: send rows without msg_id are ignored; an orphan ack is informational (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.legacy.jsonl"
  assert_success
  assert_line "orphan-ack DV0-m9"
  assert_line "verdict: clear"
  [[ "$output" != msg\ * && "$output" != *$'\n'msg\ * ]] || fail "legacy rows reported: $output"
}

@test "no audit log: nothing was sent, so the result is clear (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --context "$WD/.context"
  assert_success
  assert_output "verdict: clear"
}

@test "usage: bad or missing --task, unreadable or handoff-less artifact all exit 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task bogus --audit "$ACK/audit.unacked.jsonl"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --audit "$ACK/audit.unacked.jsonl"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.unacked.jsonl" --artifact "$WD/nope.md"
  assert_failure 2
  printf '# plain markdown\n' > "$WD/plain.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.unacked.jsonl" --artifact "$WD/plain.md"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit
  assert_failure 2
}

@test "end-to-end: --ack writes the row ack-check reads, state.json byte-identical" {
  mkdir -p "$WD/.context/logs"
  jq -n '{version: 2, worktask_id: "wt-ack", plan_file: ".context/planning-0.md",
      platform: "all", run_index: 0,
      tasks: {DV0: {status: "in_progress", metadata: {stage: "DV", agent: "corpflow:developer"}}},
      facts: {decisions: [], open_questions: []}, handoffs: {}, metadata: {}}' \
    > "$WD/.context/state.json"
  grep -v '"message_ack"' "$ACK/audit.supersede.jsonl" > "$WD/.context/logs/audit.jsonl"
  cp "$WD/.context/state.json" "$WD/state.before"

  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --context "$WD/.context"
  assert_failure 1
  assert_line "msg DV0-m2 not-delivered send=ok"

  run_script_env --cwd "$WD" --env "WORKSPACE_ROOT=$WD" "$PATCH" \
    --state "$WD/.context/state.json" --ack DV0 DV0-m2
  assert_success
  assert_audit_row message_ack --file "$WD/.context/logs/audit.jsonl" \
    --actor agent:state-patch --subject DV0 --result ok --meta msg_id=DV0-m2 \
    --jq '.task_id == "DV0"' --count 1
  cmp -s "$WD/.context/state.json" "$WD/state.before" || fail "--ack rewrote state.json"

  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --context "$WD/.context" \
    --artifact "$ACK/development-acted-m2.md"
  assert_success
  assert_line "msg DV0-m2 acked send=ok"
  assert_line "acted_on DV0-m2 expected=DV0-m2 match"
  assert_line "verdict: clear"
}

@test "contract: --self-test reaches ALL PASS" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test: supersede-mismatch exits 3: ok"
  assert_output --partial "self-test: run-scope-unacked-later-run exits 0: ok"
  assert_output --partial "self-test: ALL PASS"
}

@test "run scope: a run-0 supersede log does not judge a run-1 artifact that received no message (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 1 --audit "$ACK/audit.run-scope.jsonl" \
    --artifact "$ACK/development-run1.md"
  assert_success
  assert_line "acted_on missing expected=none match"
  assert_line "verdict: clear"
  refute_output --partial "msg DV0-"
  refute_output --partial "orphan-ack"

  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.run-scope.jsonl" \
    --artifact "$ACK/development-run1.md"
  assert_failure 3
  assert_line "acted_on missing expected=DV0-m2 mismatch"
}

@test "run scope: run 0 ending on an unacked superseding message blocks run 0 only" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 1 --audit "$ACK/audit.run-scope-unacked.jsonl" \
    --artifact "$ACK/development-run1.md"
  assert_success
  assert_line "verdict: clear"
  refute_output --partial "not-delivered"

  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 0 --audit "$ACK/audit.run-scope-unacked.jsonl"
  assert_failure 1
  assert_line "msg DV0-m1 superseded send=ok"
  assert_line "msg DV0-m2 not-delivered send=ok"
  assert_line "verdict: not-delivered"
}

@test "run scope: send rows without run_index count as run 0" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 0 --audit "$ACK/audit.supersede.jsonl" \
    --artifact "$ACK/development-acted-m2.md"
  assert_success
  assert_line "msg DV0-m2 acked send=ok"
  assert_line "acted_on DV0-m2 expected=DV0-m2 match"

  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 1 --audit "$ACK/audit.supersede.jsonl" \
    --artifact "$ACK/development-acted-m2.md"
  assert_failure 3
  assert_line "acted_on DV0-m2 expected=none mismatch"
}

@test "run scope: in-scope sends are judged; a never-sent ack stays an orphan, an other-run ack is dropped" {
  cp "$ACK/audit.run-scope.jsonl" "$WD/audit.jsonl"
  printf '%s\n' \
    '{"action":"reattach_send_result","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m3","run_index":1}}' \
    '{"action":"message_ack","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m3"}}' \
    '{"action":"message_ack","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m9"}}' \
    >> "$WD/audit.jsonl"
  sed 's/acted_on_msg_id: DV0-m2/acted_on_msg_id: DV0-m3/' "$ACK/development-acted-m2.md" > "$WD/acted-m3.md"

  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 1 --audit "$WD/audit.jsonl" --artifact "$WD/acted-m3.md"
  assert_success
  assert_line "msg DV0-m3 acked send=ok"
  assert_line "orphan-ack DV0-m9"
  assert_line "acted_on DV0-m3 expected=DV0-m3 match"
  refute_output --partial "DV0-m1"
  refute_output --partial "DV0-m2"
}

@test "run scope: malformed --run-index, or a malformed run_index on a scoped send row, exits 2" {
  local bad
  for bad in x -1 1.5 1234567890 ""; do
    run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index "$bad" --audit "$ACK/audit.run-scope.jsonl"
    assert_failure 2
  done
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$ACK/audit.run-scope.jsonl" --run-index
  assert_failure 2

  printf '%s\n' '{"action":"reattach_send_result","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m1","run_index":"one"}}' \
    > "$WD/bad-run.jsonl"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --run-index 0 --audit "$WD/bad-run.jsonl"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --task DV0 --audit "$WD/bad-run.jsonl"
  assert_failure 1
}
