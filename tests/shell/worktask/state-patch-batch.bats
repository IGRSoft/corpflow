#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/state-patch.sh one-call ledger work:
#   - --digest: opt-in stdout read-back of the written ledger, <= 12 lines
#   - repeated --task-create <ID> [--metadata <json>]: one atomic merge, all-or-nothing
#   - --audit-row <json>: validated before any write, appended only after the main op succeeds
# Every refusal case asserts state.json (checksum) and audit.jsonl are untouched.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/state-patch.sh"

# Every non-PL/IR --task-create row needs the five dispatch-shape keys.
_meta() {
  jq -cn --argjson x "${1:-null}" \
    '{effort:"high",isolation:"worktree",base_ref:"origin/develop",requires_screenshots:false,workspace_path:"/tmp/wt"} + ($x // {})'
}

_sum() { shasum "$WD/.context/state.json" | cut -d' ' -f1; }

_audit_lines() {
  if [[ -f "$WD/.context/logs/audit.jsonl" ]]; then
    wc -l < "$WD/.context/logs/audit.jsonl" | tr -d ' '
  else
    printf '0'
  fi
}

sp() { bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/.context/state.json" "$@"; }

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  cp "$FIXTURES/worktask/state.sample.json" "$WD/.context/state.json"
  cp "$FIXTURES/worktask/development-0.sample.md" "$WD/.context/development-0.md"
  export WORKSPACE_ROOT="$WD"
}

# --- --digest ---------------------------------------------------------------------------

@test "digest: stage completion with --prev and --facts prints header, row, edge and facts" {
  cd "$WD"
  run --separate-stderr sp --stage DV --artifact .context/development-0.md --prev AR \
    --facts '{"files_modified":["a.sh","b.sh"]}' --digest
  assert_success
  [[ "$output" == $'state-patch ok\nDV0 completed\nedge AR→DV0\nfacts decisions=0 open_questions=0 files_modified=2' ]] \
    || fail "digest: $output"
}

@test "digest: an idempotent completion re-run still prints the digest" {
  cd "$WD"
  sp --stage DV --artifact .context/development-0.md --prev AR > /dev/null
  before="$(_sum)"
  run --separate-stderr sp --stage DV --artifact .context/development-0.md --prev AR --digest
  assert_success
  [[ "$output" == $'state-patch ok\nDV0 completed\nedge AR→DV0' ]] || fail "digest: $output"
  [[ "$(_sum)" == "$before" ]] || fail "idempotent re-run wrote"
}

@test "digest: --claim prints status with agent and model" {
  sp --task-create DV0 --metadata "$(_meta '{"agent":"corpflow:developer","model":"opus"}')"
  run --separate-stderr sp --claim DV0 --digest
  assert_success
  [[ "$output" == $'state-patch ok\nDV0 in_progress agent=corpflow:developer model=opus' ]] || fail "$output"
}

@test "digest: --task-create omits empty agent/model fields" {
  run --separate-stderr sp --task-create DV0 --metadata "$(_meta '{"model":"sonnet"}')" --digest
  assert_success
  [[ "$output" == $'state-patch ok\nDV0 pending model=sonnet' ]] || fail "$output"
}

@test "digest: absent flag keeps stdout byte-identical (empty) on every composed op" {
  cd "$WD"
  run --separate-stderr sp --task-create DV0 --metadata "$(_meta)" --task-create DR0 --metadata "$(_meta)" \
    --audit-row '{"action":"seed","result":"ok","subject":"plan"}'
  assert_success
  [[ -z "$output" ]] || fail "batched create printed: $output"
  run --separate-stderr sp --claim DV0 --audit-row '{"action":"claim","result":"ok","subject":"DV0"}'
  assert_success
  [[ -z "$output" ]] || fail "claim printed: $output"
  run --separate-stderr sp --stage DV --artifact .context/development-0.md --prev AR \
    --facts '{"files_modified":["a"]}'
  assert_success
  [[ -z "$output" ]] || fail "completion printed: $output"
}

@test "digest: ignored by --resolve-task-id, whose stdout stays the bare id" {
  sp --task-create DV0 --metadata "$(_meta)"
  run --separate-stderr sp --resolve-task-id DV --digest
  assert_success
  assert_output "DV0"
}

@test "digest: a refused op prints nothing on stdout" {
  sp --task-create DV0 --metadata "$(_meta)"
  sp --task-status DV0 completed
  run --separate-stderr sp --claim DV0 --digest
  [ "$status" -eq 4 ]
  [[ -z "$output" ]] || fail "refusal printed: $output"
}

@test "digest: a long batch is capped at 12 lines" {
  args=()
  for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
    args+=(--task-create "DV$i" --metadata "$(_meta)")
  done
  run --separate-stderr sp "${args[@]}" --digest
  assert_success
  [ "${#lines[@]}" -le 12 ] || fail "digest has ${#lines[@]} lines"
  [[ "${lines[0]}" == "state-patch ok" ]]
  [[ "${lines[${#lines[@]} - 1]}" == "tasks +4 more" ]] || fail "$output"
}

# --- batched --task-create --------------------------------------------------------------

@test "batch: N pairs seed N rows, each --metadata bound to the id before it" {
  run sp --task-create DV0 --metadata "$(_meta '{"agent":"a-dv"}')" \
    --task-create DR0 --metadata "$(_meta '{"agent":"a-dr"}')" \
    --task-create PL1
  assert_success
  run jq -c '[.tasks.DV0.metadata.agent, .tasks.DR0.metadata.agent, .tasks.PL1.metadata, .tasks.DR0.status]' \
    "$WD/.context/state.json"
  assert_output '["a-dv","a-dr",{},"pending"]'
}

@test "batch: one row missing a required key refuses all, state.json byte-unchanged" {
  before="$(_sum)"
  run sp --task-create DV0 --metadata "$(_meta)" --task-create DR0 --metadata '{"effort":"high"}' \
    --audit-row '{"action":"seed","result":"ok","subject":"plan"}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"DR0: metadata missing required key(s)"* ]] || fail "$output"
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
  [[ "$(_audit_lines)" == "0" ]] || fail "audit row written on refusal"
}

@test "batch: an off-ladder effort on a later row refuses all" {
  before="$(_sum)"
  run sp --task-create DV0 --metadata "$(_meta)" --task-create DR0 --metadata "$(_meta '{"effort":"turbo"}')"
  [ "$status" -eq 2 ]
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
}

@test "batch: a malformed id anywhere refuses all" {
  before="$(_sum)"
  run sp --task-create DV0 --metadata "$(_meta)" --task-create XX9 --metadata "$(_meta)"
  [ "$status" -eq 2 ]
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
}

@test "batch: a repeated id is a usage error" {
  before="$(_sum)"
  run sp --task-create DV0 --metadata "$(_meta)" --task-create DV0 --metadata "$(_meta)"
  [ "$status" -eq 2 ]
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
}

@test "batch: mixing with another ledger op is exit 2" {
  sp --task-create DV0 --metadata "$(_meta)"
  before="$(_sum)"
  run sp --task-create DR0 --metadata "$(_meta)" --task-create QA0 --metadata "$(_meta)" --claim DV0
  [ "$status" -eq 2 ]
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
}

@test "batch: --metadata ahead of the first --task-create binds to nothing and refuses" {
  before="$(_sum)"
  run sp --metadata "$(_meta)" --task-create DV0 --task-create DR0 --metadata "$(_meta)"
  [ "$status" -eq 2 ]
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
}

@test "batch: existing rows are per-row no-ops; all-existing is byte-identical" {
  sp --task-create DV0 --metadata "$(_meta '{"agent":"keep"}')"
  run sp --task-create DV0 --metadata "$(_meta '{"agent":"overwrite"}')" --task-create DR0 --metadata "$(_meta)"
  assert_success
  run jq -r '.tasks.DV0.metadata.agent + " " + .tasks.DR0.status' "$WD/.context/state.json"
  assert_output "keep pending"
  before="$(_sum)"
  run sp --task-create DV0 --task-create DR0
  assert_success
  [[ "$(_sum)" == "$before" ]] || fail "all-existing batch rewrote state.json"
}

@test "batch: a single --task-create keeps the legacy --metadata-anywhere binding" {
  run sp --metadata "$(_meta '{"agent":"pre"}')" --task-create DV0
  assert_success
  run jq -r '.tasks.DV0.metadata.agent' "$WD/.context/state.json"
  assert_output "pre"
}

# --- --audit-row ------------------------------------------------------------------------

@test "audit-row: composed with --claim appends after the write with the claimed id and default actor" {
  sp --task-create DV0 --metadata "$(_meta)"
  run sp --claim DV0 --audit-row '{"action":"claim","result":"ok","subject":"DV0","metadata":{"k":"v"}}' \
    --audit-row '{"action":"note","result":"ok","subject":"x","actor":"corpflow:developer","task_id":"PL0"}'
  assert_success
  run jq -sc 'map({actor, action, task_id, metadata})' "$WD/.context/logs/audit.jsonl"
  assert_output '[{"actor":"corpflow:unknown","action":"claim","task_id":"DV0","metadata":{"k":"v"}},{"actor":"corpflow:developer","action":"note","task_id":"PL0","metadata":{}}]'
}

@test "audit-row: batched --task-create defaults task_id to the first id" {
  run sp --task-create DV0 --metadata "$(_meta)" --task-create DR0 --metadata "$(_meta)" \
    --audit-row '{"action":"seed","result":"ok","subject":"plan"}'
  assert_success
  run jq -r '.task_id' "$WD/.context/logs/audit.jsonl"
  assert_output "DV0"
}

@test "audit-row: stage completion uses the resolved task id" {
  cd "$WD"
  run sp --stage DV --artifact .context/development-0.md --prev AR \
    --audit-row '{"action":"stage_done","result":"ok","subject":"DV0"}'
  assert_success
  run jq -r '.task_id + " " + .action' "$WD/.context/logs/audit.jsonl"
  assert_output "DV0 stage_done"
}

@test "audit-row: none appended when the main op refuses" {
  sp --task-create DV0 --metadata "$(_meta)"
  sp --task-status DV0 completed
  before="$(_sum)"
  run sp --claim DV0 --audit-row '{"action":"claim","result":"ok","subject":"DV0"}'
  [ "$status" -eq 4 ]
  [[ "$(_audit_lines)" == "0" ]] || fail "row appended on refusal"
  [[ "$(_sum)" == "$before" ]]
}

@test "audit-row: bad JSON, missing key, empty value or unknown key is exit 2 with nothing written" {
  sp --task-create DV0 --metadata "$(_meta)"
  before="$(_sum)"
  for row in '{"action":"x"' '{"action":"x","result":"ok"}' '{"action":"","result":"ok","subject":"s"}' \
    '{"action":"x","result":"ok","subject":"s","extra":1}' '[1]' '{"action":"x","result":"ok","subject":"s","task_id":"bogus"}'; do
    run sp --claim DV0 --audit-row "$row"
    [ "$status" -eq 2 ] || fail "row $row: status $status"
    [[ "$output" == *"invalid --audit-row"* ]] || fail "row $row: $output"
  done
  [[ "$(_sum)" == "$before" ]] || fail "claim landed despite a bad row"
  [[ "$(_audit_lines)" == "0" ]] || fail "row appended"
}

@test "audit-row: standalone appends rows only, state.json untouched" {
  sp --task-create DV0 --metadata "$(_meta)"
  before="$(_sum)"
  run --separate-stderr sp --audit-row '{"action":"note","result":"ok","subject":"s"}' --task-id DV0 --digest
  assert_success
  [[ "$output" == $'state-patch ok\nDV0 pending\naudit +1' ]] || fail "$output"
  [[ "$(_sum)" == "$before" ]] || fail "state.json changed"
  run jq -r '.task_id' "$WD/.context/logs/audit.jsonl"
  assert_output "DV0"
}

@test "audit-row: standalone with an unknown task id or no ledger refuses" {
  run sp --audit-row '{"action":"note","result":"ok","subject":"s","task_id":"QA7"}'
  [ "$status" -eq 1 ]
  [[ "$(_audit_lines)" == "0" ]]
  rm -f "$WD/.context/state.json"
  run sp --audit-row '{"action":"note","result":"ok","subject":"s"}'
  [ "$status" -eq 1 ]
  [[ "$(_audit_lines)" == "0" ]]
}

@test "audit-row: does not compose with --ack" {
  sp --task-create DV0 --metadata "$(_meta)"
  run sp --ack DV0 msg-1 --audit-row '{"action":"x","result":"ok","subject":"s"}'
  [ "$status" -eq 2 ]
  [[ "$(_audit_lines)" == "0" ]]
}

@test "audit-row + digest: standalone --facts reports both" {
  run --separate-stderr sp --facts '{"decisions":[{"id":"d1","summary":"s","stage":"AR0"}]}' --task-id PL0 \
    --audit-row '{"action":"facts","result":"ok","subject":"facts"}' --digest
  assert_success
  [[ "$output" == $'state-patch ok\nPL0 completed\nfacts decisions=1 open_questions=0 files_modified=0\naudit +1' ]] \
    || fail "$output"
  run jq -r '.task_id' "$WD/.context/logs/audit.jsonl"
  assert_output "PL0"
}
