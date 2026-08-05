#!/usr/bin/env bats
# Tests for hooks/precompact-checkpoint.sh (DV0c) — PreCompact hook that copies
# state.json to a timestamped checkpoint and logs a precompact_checkpoint row.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/precompact-checkpoint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
}

@test "happy: copies state.json to a checkpoint and logs result=ok" {
  printf '%s' '{"run_index":0,"stages":{}}' > "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # A timestamped checkpoint file must now exist alongside state.json.
  run bash -c "ls $WD/.context/state.checkpoint-*.json"
  assert_success
  run jq -e '.action == "precompact_checkpoint" and .result == "ok" and .metadata.run_index == "0"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: absent state.json logs a skipped row and writes no checkpoint" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.result == "skipped" and .metadata.reason == "no state.json"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
  run bash -c "ls $WD/.context/state.checkpoint-*.json 2>/dev/null"
  assert_failure
}

@test "edge: checkpoint records pointers to planning/development artifacts" {
  printf '%s' '{"run_index":2,"stages":{}}' > "$WD/.context/state.json"
  printf '# plan\n' > "$WD/.context/planning-2.md"
  printf '# dev\n' > "$WD/.context/development-2.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '(.metadata.artifacts | length) == 2 and .metadata.run_index == "2"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

# --- checkpoint fidelity ------------------------------------------------------
# `ls state.checkpoint-*.json` only proved a file appeared. A hook that wrote an
# empty file, a truncated copy, or the wrong ledger satisfied it — which is the
# one failure mode that matters, since the checkpoint exists to be restored from.

@test "fidelity: the checkpoint is byte-for-byte the ledger it snapshotted" {
  local state="$WD/.context/state.json"
  # A non-trivial ledger: nested stages, arrays, unicode and a float.
  cat > "$state" <<'JSON'
{"version":1,"worktask_id":"wt-fidelity","run_index":3,"platform":"systems",
 "stages":{"PL":{"status":"complete","verdict":"ok"},
           "DV":{"status":"in_progress","progress":{"completed_batches":["B1","B2"],"ratio":0.75}}},
 "facts":{"files_modified":["a.md","b/c.md"],"note":"ünïcode — em dash"},
 "handoffs":{"PL→DV":{"summary":"go"}}}
JSON
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success

  local ckpt
  ckpt="$(ls "$WD/.context/"state.checkpoint-*.json)"
  [ -n "$ckpt" ]
  [ -s "$ckpt" ]
  # Semantic equality, key order independent.
  run bash -c 'diff <(jq -S . "$1") <(jq -S . "$2")' _ "$state" "$ckpt"
  assert_success
  assert_output ""
  # And the nested content really survived, not just a valid-JSON stub.
  run jq -r '.stages.DV.progress.completed_batches | join(",")' "$ckpt"
  assert_output "B1,B2"
  run jq -r '.facts.note' "$ckpt"
  assert_output "ünïcode — em dash"
}

@test "fidelity: the original ledger is left untouched by the checkpoint" {
  local state="$WD/.context/state.json"
  printf '%s' '{"run_index":0,"stages":{"DV":{"status":"in_progress"}}}' > "$state"
  local before
  before="$(cat "$state")"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run cat "$state"
  assert_output "$before"
}

@test "fidelity: a second checkpoint does not clobber the first" {
  local state="$WD/.context/state.json"
  printf '%s' '{"run_index":0,"stages":{},"facts":{"seq":1}}' > "$state"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # Timestamped names are second-resolution; make the second one distinct.
  sleep 1
  printf '%s' '{"run_index":0,"stages":{},"facts":{"seq":2}}' > "$state"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success

  run bash -c 'ls "$1"/.context/state.checkpoint-*.json | wc -l | tr -d " "' _ "$WD"
  assert_output "2"
  # Each snapshot kept its own generation of the ledger.
  run bash -c 'for f in "$1"/.context/state.checkpoint-*.json; do jq -r ".facts.seq" "$f"; done | sort | tr "\n" ","' _ "$WD"
  assert_output "1,2,"
}
