#!/usr/bin/env bats
# Tests for hooks/test-execution-promote.sh — the PostToolUse companion that
# turns the gate's pending marker into a durable dedupe sentinel, and only when
# the tool actually produced a result.
#
# The gate's own suite covers what a promotion means for a later invocation;
# this file covers the promotion decision itself, plus the key parity between the
# two hooks that makes the whole handshake work rather than silently orphaning
# every marker.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

GATE="hooks/test-execution-gate.sh"
PROMOTE="hooks/test-execution-promote.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  git -C "$WD" init -q
  git -C "$WD" config user.email t@example.com
  git -C "$WD" config user.name t
  git -C "$WD" config commit.gpgsign false
  echo seed > "$WD/src.txt"
  git -C "$WD" add -A
  git -C "$WD" commit -qm init
  printf '{"run_index":0,"tasks":{"QA0":{"status":"in_progress"}}}' > "$WD/.context/state.json"
  RUNS="$WD/.context/logs/.test-runs"
}

gate_run() {
  # gate_run <command> — the PreToolUse half; leaves exactly one .pending marker.
  local payload
  payload="$(jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$GATE"
}

post_run() {
  # post_run <command> <tool_response json> — the PostToolUse half.
  local payload
  payload="$(jq -cn --arg c "$1" --argjson r "$2" \
    '{tool_name:"Bash", tool_input:{command:$c}, tool_response:$r}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
}

count_files() { find "$RUNS" -type f -name "$1" 2>/dev/null | wc -l | tr -d ' '; }

@test "a result promotes the marker: one durable sentinel, no pending left behind" {
  gate_run './run-tests.sh'
  [ "$(count_files '*.pending')" = "1" ]

  post_run './run-tests.sh' '{"stdout":"7 tests, 0 failures"}'
  assert_success
  [ "$(count_files '*.pending')" = "0" ]
  [ "$(count_files '*')" = "1" ]
}

@test "key parity: the promoted sentinel carries EXACTLY the key the gate recorded" {
  # The assertion that makes AD-3's key-drift failure detectable. Two hooks
  # deriving the key independently would orphan every marker and disable
  # suppression permanently, with no test failing and no row written.
  #
  # The marker's NAME is fingerprint-free, so the gate's full key is read out of
  # the marker's third field rather than from its filename.
  gate_run './run-tests.sh --changed'
  local pending expected
  pending="$(find "$RUNS" -name '*.pending' | head -1)"
  [ -n "$pending" ]
  expected="$(awk '{print $3}' "$pending")"
  [ -n "$expected" ]

  post_run './run-tests.sh --changed' '{"stdout":"ok"}'
  local promoted
  promoted="$(find "$RUNS" -type f ! -name '*.pending' | head -1)"
  [ "$(basename "$promoted")" = "$expected" ]
}

@test "a run that dirties the tree still promotes under the gate's original key" {
  # The drift the fingerprint-free marker name exists to remove: a runner that
  # writes .pytest_cache / coverage output / .build between PreToolUse and
  # PostToolUse changes the tree, so a post-run fingerprint names a marker the
  # gate never wrote and NOTHING is ever recorded.
  gate_run './run-tests.sh'
  local pending expected
  pending="$(find "$RUNS" -name '*.pending' | head -1)"
  expected="$(awk '{print $3}' "$pending")"

  mkdir -p "$WD/.pytest_cache"
  echo 'cachedata' > "$WD/.pytest_cache/v"
  echo 'coverage' > "$WD/coverage.out"

  post_run './run-tests.sh' '{"stdout":"7 tests, 0 failures"}'
  assert_success
  [ "$(count_files '*.pending')" = "0" ]
  [ -f "$RUNS/$expected" ]
}

@test "an empty tool_response discards the marker (the 1.0s zero-test abort)" {
  gate_run './run-tests.sh'
  post_run './run-tests.sh' '""'
  assert_success
  [ "$(count_files '*')" = "0" ]
}

@test "an error flag discards the marker" {
  gate_run './run-tests.sh'
  post_run './run-tests.sh' '{"error":"scheme not found"}'
  assert_success
  [ "$(count_files '*')" = "0" ]
}

@test "is_error on the response discards; on the envelope only the output decides" {
  gate_run './run-tests.sh'
  post_run './run-tests.sh' '{"is_error":true,"stdout":"partial"}'
  [ "$(count_files '*')" = "0" ]

  # An envelope-level is_error is the transport saying the call failed, which is
  # what a RED SUITE looks like too. Output present -> a run happened.
  gate_run './run-tests.sh'
  local payload
  payload="$(jq -cn '{tool_name:"Bash", tool_input:{command:"./run-tests.sh"},
                      tool_response:{stdout:"partial"}, is_error:true}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*.pending')" = "0" ]
  [ "$(count_files '*')" = "1" ]

  # Same envelope with nothing to show for it: an abort, and it must stay inert.
  rm -rf "$RUNS"
  gate_run './run-tests.sh'
  payload="$(jq -cn '{tool_name:"Bash", tool_input:{command:"./run-tests.sh"},
                      tool_response:"", is_error:true}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*')" = "0" ]
}

@test "a PostToolUseFailure payload promotes on output and on error text alone" {
  # A non-zero runner exit fires PostToolUseFailure instead of PostToolUse, which
  # is why the hook is registered on both.
  gate_run './run-tests.sh'
  local payload
  payload="$(jq -cn '{hook_event_name:"PostToolUseFailure", tool_name:"Bash",
                      tool_input:{command:"./run-tests.sh"},
                      tool_response:{stdout:"3 failed, 9 passed"},
                      error:"pytest exited 1"}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*.pending')" = "0" ]
  [ "$(count_files '*')" = "1" ]

  # A failing tool carries no tool_response at all — the error string is the
  # whole envelope. Discarding here would suppress green runs only and leave
  # every red rerun unsuppressed, which is the inverse of the intent.
  rm -rf "$RUNS"
  gate_run './run-tests.sh --changed'
  payload="$(jq -cn '{hook_event_name:"PostToolUseFailure", tool_name:"Bash",
                      tool_input:{command:"./run-tests.sh --changed"},
                      error:"3 failed, 9 passed"}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*.pending')" = "0" ]
  [ "$(count_files '*')" = "1" ]
}

@test "an interrupted PostToolUseFailure discards — a cancelled call produced no evidence" {
  gate_run './run-tests.sh'
  local payload
  payload="$(jq -cn '{hook_event_name:"PostToolUseFailure", tool_name:"Bash",
                      tool_input:{command:"./run-tests.sh"},
                      error:"Interrupted by user", is_interrupt:true}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*')" = "0" ]
}

@test "a missing tool_response key discards — absence is not a result" {
  gate_run './run-tests.sh'
  local payload
  payload="$(jq -cn '{tool_name:"Bash", tool_input:{command:"./run-tests.sh"}}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*')" = "0" ]
}

@test "a non-test tool call touches nothing (no directory, no marker, no cost)" {
  local payload
  payload="$(jq -cn '{tool_name:"Bash", tool_input:{command:"git status"},
                      tool_response:{stdout:"clean"}}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ -z "$output" ]
  [ ! -d "$RUNS" ]
}

@test "CORPFLOW_TEST_DEDUPE=off promotes nothing — the hatch covers both halves" {
  gate_run './run-tests.sh'
  local payload
  payload="$(jq -cn '{tool_name:"Bash", tool_input:{command:"./run-tests.sh"},
                      tool_response:{stdout:"ok"}}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" \
    --env "CORPFLOW_TEST_DEDUPE=off" --stdin-string "$payload" "$PROMOTE"
  assert_success
  [ "$(count_files '*.pending')" = "1" ]
  [ "$(count_files '*')" = "1" ]
}

@test "exit code is 0 on every path, including an unparseable payload" {
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string 'not json' "$PROMOTE"
  assert_success
  [ -z "$output" ]
}

@test "promoting twice is idempotent — the second call finds no pending and leaves the sentinel" {
  gate_run './run-tests.sh'
  post_run './run-tests.sh' '{"stdout":"ok"}'
  local first
  first="$(cat "$(find "$RUNS" -type f | head -1)")"

  post_run './run-tests.sh' '{"stdout":"ok"}'
  assert_success
  [ "$(count_files '*')" = "1" ]
  [ "$(cat "$(find "$RUNS" -type f | head -1)")" = "$first" ]
}

@test "the Skill branch promotes through the same shared derivation" {
  local pre post
  pre="$(jq -cn '{tool_name:"Skill", tool_input:{skill:"/system-developer:build-test"}}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$pre" "$GATE"
  [ "$(count_files '*.pending')" = "1" ]

  post="$(jq -cn '{tool_name:"Skill", tool_input:{skill:"/system-developer:build-test"},
                   tool_response:{stdout:"ok"}}')"
  run_script_env --cwd "$WD" --env "CLAUDE_PROJECT_DIR=$WD" --stdin-string "$post" "$PROMOTE"
  assert_success
  [ "$(count_files '*.pending')" = "0" ]
  [ "$(count_files '*')" = "1" ]
}
