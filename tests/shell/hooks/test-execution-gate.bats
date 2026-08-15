#!/usr/bin/env bats
# Tests for hooks/test-execution-gate.sh — PreToolUse gate enforcing
# skills/shared/testing-strategy.md § Test-Execution Authority.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/test-execution-gate.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
}

state_with() {
  # state_with <stage> [<stage2>] — writes .context/state.json with the given
  # stage(s) in_progress.
  local s1="$1" s2="${2:-}"
  if [ -n "$s2" ]; then
    printf '{"stages":{"%s":{"status":"in_progress"},"%s":{"status":"in_progress"}}}' "$s1" "$s2" \
      > "$WD/.context/state.json"
  else
    printf '{"stages":{"%s":{"status":"in_progress"}}}' "$s1" > "$WD/.context/state.json"
  fi
}

bash_payload() {
  # bash_payload <command> -> JSON on stdout
  #
  # A malformed payload makes the hook fail OPEN: it emits nothing and writes
  # no audit row, which is byte-for-byte what a legitimate allow looks like.
  # Every "expected allow" case here asserts empty output, so a build failure
  # would pass as a green test. Guarding at the call sites is not enough —
  # most call this inline inside `<<< "$(bash_payload …)"`, where a non-zero
  # return is discarded by the redirection — so failures are recorded to a
  # file that teardown checks, which no subshell can swallow.
  local json payload
  json="$(jq -Rn --arg c "$1" '$c' 2>/dev/null)"
  payload="$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$json")"
  jq -e . >/dev/null 2>&1 <<< "$payload" \
    || printf 'bash_payload produced invalid JSON for: %s\n' "$1" >> "$WD/.payload-build-errors"
  printf '%s' "$payload"
}

teardown() {
  # Fails the test if any bash_payload call in it built an invalid payload.
  [ -s "$WD/.payload-build-errors" ] || return 0
  echo "--- payload build failures (a fixture may have passed vacuously) ---"
  cat "$WD/.payload-build-errors"
  return 1
}

@test "1: DV in progress + ./run-tests.sh via QA-only exemption does NOT apply -> DV full is denied (see 14); DV scoped allowed" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'tests/vendor/bats-core/bin/bats tests/shell/hooks/foo.bats')"
  assert_success
  [ -z "$output" ]
}

@test "2: QA + ./run-tests.sh -> allow (sole full-suite authority)" {
  state_with QA
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  [ -z "$output" ]
}

@test "3: DR + scoped bats -> deny + test_execution_blocked audit row" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'tests/vendor/bats-core/bin/bats tests/shell/hooks/foo.bats')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.action == "test_execution_blocked" and .metadata.stage == "DR" and .metadata.command_head == "bats"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "4: SR-dispatched delegate's own leaf Bash call inherits SR's banned authority -> deny (closes the delegation-path hole at the leaf, AR-1)" {
  state_with SR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'pytest tests/security/test_auth.py')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "5: no .context/state.json -> allow, no decision, no audit row (FO-4)" {
  rm -f "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "6: jq absent -> exit 0 silently, no decision (FO-9)" {
  state_with DR
  # The script probes for jq with `command -v jq`, so hiding jq is enough to
  # exercise the branch — no chroot and no skip. The old form set
  # PATH=/usr/bin:/bin and skipped whenever the host happened to have jq there,
  # which on most developer machines meant the branch never ran at all.
  run_script_env --hide jq --env "CLAUDE_PROJECT_DIR=$WD" \
    --stdin-string "$(bash_payload './run-tests.sh')" -- "$SCRIPT"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]

  # Falsification pair: the identical payload with jq present is denied, so the
  # silent allow above is attributable to jq's absence and nothing else.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "7: CORPFLOW_TEST_GATE=off -> allow even for a banned stage" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" CORPFLOW_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  [ -z "$output" ]
}

@test "8: DR + build-test --no-test -> allow (build-only carve-out, AC-6)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload '/system-developer:build-test --no-test')"
  assert_success
  [ -z "$output" ]
}

@test "9: DR + build-test (no flag) -> deny" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload '/system-developer:build-test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "10: two stages in_progress -> fail-open allow, no row (FO-7)" {
  state_with DR QA
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "11: exit code is 0 on every path, including a deny" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats foo.bats')"
  [ "$status" -eq 0 ]
}

@test "12: audit.jsonl records command_head only, never the full command" {
  state_with SR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats /secret/leak/path.bats -f token-abc123')"
  assert_success
  run jq -e '.metadata.command_head == "bats" and (.metadata.command_head | test("secret|token-abc123") | not)' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
  run jq -e '(.metadata | has("command")) | not' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "13: Task carrying the literal ban text -> allow + test_delegation_observed, NEVER a deny (AR-2 deadlock guard)" {
  state_with DR
  local payload='{"tool_name":"Task","tool_input":{"subagent_type":"corpflow:developer","prompt":"DO NOT execute tests: bats, pytest, cargo test are forbidden outside DV/QA"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
  refute_output --partial "deny"
  run jq -e '.action == "test_delegation_observed"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "14: DV + ./run-tests.sh -> deny (AR-3, mechanical half of AC-2 — DV never reaches full-suite)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.stage == "DV" and .metadata.class == "full_test_run"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "14a: DV + ./run-tests.sh --changed -> allow (bare still denies, per 14)" {
  # The arm used to ignore arguments, so the one feature built for DV was denied
  # to DV. Bare stays full_test_run (test 14) — only the argument form moves.
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh --changed')"
  assert_success
  [ -z "$output" ] || fail "DV was denied its own scoped selection: $output"
}

@test "14b: --changed classifies scoped_test_run, not merely not_test" {
  # An allowed run at DV writes no audit row, so "allow" alone cannot tell a
  # correct scoped classification from the arm falling through to not_test.
  # DR denies scoped and records the class, which makes the difference visible.
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh --changed')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.class == "scoped_test_run"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "14c: --base <ref> also classifies scoped, and the ref is not read as a command" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh --base master --changed')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.class == "scoped_test_run"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "14e: --print-selection is build_only — allowed even where scoped is denied" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh --changed --print-selection')"
  assert_success
  [ -z "$output" ] || fail "--print-selection runs nothing and must never deny: $output"
}

@test "14d: QA + ./run-tests.sh --changed -> still allowed (QA is not narrowed)" {
  state_with QA
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh --changed')"
  assert_success
  [ -z "$output" ]
}

@test "15: non-test Bash (git status) under a banned stage -> allow, no audit row (fast-path guard)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'git status')"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

@test "edge: unknown tool_name is out of scope -> allow, no row (FO-10 matcher drift)" {
  state_with DR
  local payload='{"tool_name":"Read","tool_input":{"file_path":"foo.txt"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "edge: mcp__*__test_* tool under a banned stage -> deny (B9 matcher widening)" {
  state_with DR
  local payload='{"tool_name":"mcp__XcodeBuildMCP__test_sim","tool_input":{}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

# --- DR remediation regression scenarios (developer-review-1.md P1-1..P1-4) ---

@test "P1-1: Task dispatch with NO .context/ at all -> zero filesystem side effects, no observe row" {
  rm -rf "$WD/.context"   # simulate a third-party repo with no worktask in flight
  local payload='{"tool_name":"Task","tool_input":{"subagent_type":"corpflow:developer","prompt":"go ahead and make the change to the algorithm"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
  [ ! -d "$WD/.context" ]
}

@test "P1-1: word-boundary token match — 'algorithm' does not trip the observe row (bare substring 'go' inside it)" {
  state_with DR
  local payload='{"tool_name":"Task","tool_input":{"subagent_type":"corpflow:developer","prompt":"refine the sorting algorithm and category logic"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "P1-2: pure build command on a multi-purpose runner ALLOWS at a banned stage (AC-6) — ./gradlew assembleDebug" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './gradlew assembleDebug')"
  assert_success
  [ -z "$output" ]
}

@test "P1-2: pure script execution on python3 ALLOWS at a banned stage (AC-6) — coverage_report.py" {
  state_with SR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'python3 tools/coverage_report.py')"
  assert_success
  [ -z "$output" ]
}

@test "P1-3: leading secret env assignment never reaches command_head in the audit row" {
  state_with SR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'API_KEY=sk-test-xyz pytest tests/')"
  assert_success
  run jq -e '.metadata.command_head == "pytest" and (.metadata.command_head | test("sk-test-xyz|API_KEY") | not)' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "P1-4: 'swift test -c release' still classifies as a test run (deny at DR, not build_only)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'swift test -c release')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "P1-4: 'swift test -c release' at DV still hits the AR-3 full-suite deny (bare -c is not a selection arg)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'swift test -c release')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "P2-13: '--list' does not over-match '--listener'" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats --listener foo.bats')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

# --- DR Round 2 regression scenarios (developer-review-1.md § Round 2) ---

@test "N1: 'xcodebuild test -scheme X' denies at a banned stage (prefilter previously omitted xcodebuild)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild test -scheme X')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "N1 sibling: 'xcodebuild archive -scheme X' (no test subcommand) still allows" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild archive -scheme X')"
  assert_success
  [ -z "$output" ]
}

@test "N4: 'npm run test' (package.json-script form) denies at a banned stage" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'npm run test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "N4 sibling: 'npm run lint' (non-test script) still allows" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'npm run lint')"
  assert_success
  [ -z "$output" ]
}

# --- SR Round 4 regression scenarios (security-review-1.md) ---

@test "SR-H1: 'swift build --build-tests' (compile-tests-without-running) ALLOWS at DV (was falsely denied)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'swift build --build-tests')"
  assert_success
  [ -z "$output" ]
}

@test "SR-H1: 'cat docs/build-test.md' ALLOWS at a banned stage (unanchored substring fixed)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'cat docs/build-test.md')"
  assert_success
  [ -z "$output" ]
}

@test "SR-H1 non-regression: '/system-developer:build-test' (no flag) still DENIES at a banned stage" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload '/system-developer:build-test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "SR-H1 non-regression: '/system-developer:build-test --no-test' still ALLOWS (build-only carve-out intact)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload '/system-developer:build-test --no-test')"
  assert_success
  [ -z "$output" ]
}

@test "RK4 structural item 1: CORPFLOW_TEST_GATE=off writes ONE test_gate_disabled row, not one per call" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" CORPFLOW_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats foo.bats')"
  assert_success
  run env CLAUDE_PROJECT_DIR="$WD" CORPFLOW_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'pytest tests/')"
  assert_success
  run jq -e '.action == "test_gate_disabled" and .metadata.vector == "CORPFLOW_TEST_GATE"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
  local row_count
  row_count="$(grep -c 'test_gate_disabled' "$WD/.context/logs/audit.jsonl")"
  [ "$row_count" -eq 1 ]
}

@test "SR-M1: build-only collection/compile-without-run forms allow at a banned stage" {
  state_with DR
  for cmd in 'cargo test --no-run' 'ctest -N' 'ctest --show-only' 'npx jest --listTests' 'pytest --co'; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    [ -z "$output" ] || fail "expected allow for: $cmd (got: $output)"
  done
}

@test "SR item 3: gradle pure-build task prefixes (install/assemble/compile) allow despite containing 'test'" {
  state_with DR
  for cmd in './gradlew installDebugAndroidTest' './gradlew assembleAndroidTest' './gradlew compileDebugUnitTestKotlin'; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    [ -z "$output" ] || fail "expected allow for: $cmd (got: $output)"
  done
}

@test "SR-M2: quoted env-value with a space no longer defeats classification (deny direction)" {
  state_with SR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'FOO="a b" pytest tests/')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "SR-M2: quoted env-value with a space no longer produces a false deny (allow direction)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'MSG="see pytest docs" ls -la')"
  assert_success
  [ -z "$output" ]
}

@test "SR2-H1: command_head is redacted, never a secret fragment, across ;/&&/||/pipe/newline shapes" {
  state_with SR
  local cmds=(
    'PYTEST_ADDOPTS="--token ghp_LEAKME123"; pytest tests/'
    'GIT_ASKPASS="echo hunter2" && bats tests/a.bats'
    'true | pytest tests/'
  )
  for cmd in "${cmds[@]}"; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
  done
  # Newline-separated: the realistic self-inflicted shape (a multi-line Bash tool_input.command).
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$(printf 'SECRET=hunter2\npytest tests/')")"
  assert_success
  run bash -c "grep -c 'command_head\":\"redacted\"' '$WD/.context/logs/audit.jsonl'"
  local redacted_count="$output"
  [ "$redacted_count" -ge 4 ]
  run bash -c "grep -i 'hunter2\|ghp_LEAKME123' '$WD/.context/logs/audit.jsonl'"
  assert_failure
}

@test "SR2-H2: classify_segment recursion is capped — 'bash -c \"bash -c pytest\"' does not chase two levels into a deny" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bash -c '"'"'bash -c "pytest tests/"'"'"'')"
  assert_success
  [ -z "$output" ]
}

@test "doc-honesty bypass fix: time/nohup/command/exec wrappers now classify on the real runner (deny direction)" {
  state_with DR
  for cmd in 'time pytest tests/' 'nohup pytest tests/' 'command bats foo.bats' 'exec pytest tests/'; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
      || fail "expected deny for: $cmd"
  done
}

@test "doc-honesty bypass fix: 'bash -lc' combined short option is now chased" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "bash -lc 'pytest tests/'")"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "SR info item: a symlinked audit.jsonl is refused, never written through" {
  state_with DR
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats foo.bats')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

@test "SR2-M1: the Skill branch redacts command_head the same as the Bash branch (no secret leak via build-test flags)" {
  state_with DR
  local payload='{"tool_name":"Skill","tool_input":{"command":"/system-developer:build-test --token sk-live-9x8y --scheme App"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.command_head == "redacted"' "$WD/.context/logs/audit.jsonl"
  assert_success
  run bash -c "grep -i 'sk-live-9x8y' '$WD/.context/logs/audit.jsonl'"
  assert_failure
}

# --- DR Round 3 regression scenarios (developer-review-1.md § Round 3) ---

@test "R3-1: Skill payload in its real {skill,args} shape — '--no-test' in args ALLOWS at DR (build-only carve-out)" {
  state_with DR
  local payload='{"tool_name":"Skill","tool_input":{"skill":"system-developer:build-test","args":"--no-test"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
}

@test "R3-1: same {skill,args} shape WITHOUT --no-test -> deny at DR" {
  state_with DR
  local payload='{"tool_name":"Skill","tool_input":{"skill":"system-developer:build-test","args":"--scheme App"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R3-1: {skill,args} with no args field at all -> deny (bare build-test is a full run)" {
  state_with DR
  local payload='{"tool_name":"Skill","tool_input":{"skill":"system-developer:build-test"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R3-1: args-carried secret never reaches command_head (redaction survives the recombination)" {
  state_with DR
  local payload='{"tool_name":"Skill","tool_input":{"skill":"system-developer:build-test","args":"--token sk-live-9x8y"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  run jq -e '.metadata.command_head == "redacted"' "$WD/.context/logs/audit.jsonl"
  assert_success
  run bash -c "grep -i 'sk-live-9x8y' '$WD/.context/logs/audit.jsonl'"
  assert_failure
}

@test "R3-2: 'make test' and 'make test-ios' deny at DR (both were dropped by the zero-fork prefilter)" {
  state_with DR
  for cmd in 'make test' 'make test-ios'; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
      || fail "expected deny for: $cmd"
  done
}

@test "R3-2: 'make test' at DV hits the full-suite deny (a named full runner, never scoped)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'make test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.class == "full_test_run" and .metadata.command_head == "make"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "R3-2 sibling: 'make build' still allows at DR (the widened prefilter did not swallow every make target)" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'make build')"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "R3-3: xcodebuild's action AFTER its options is a test run -> deny at DR (was read as _subcmd='-scheme')" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild -scheme MyApp -destination generic/platform=iOS test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R3-3: trailing-action and action-first xcodebuild shapes classify IDENTICALLY" {
  state_with DR
  for cmd in 'xcodebuild test -scheme MyApp' 'xcodebuild -scheme MyApp test'; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
  done
  # Order-invariance is what this asserts; `-scheme MyApp` is non-selecting, so
  # the shared class is full_test_run. Deny at DR is unchanged either way.
  run jq -s -e 'map(.metadata.class) | unique | length == 1 and .[0] == "full_test_run"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "R3-3: 'xcodebuild test-without-building' (executes a prebuilt bundle) -> deny at DR" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild -scheme MyApp test-without-building')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R3-3: '-only-testing:' selection still classifies scoped, not full" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild -scheme MyApp -only-testing:MyAppTests/LoginTests test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.class == "scoped_test_run"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "R3-3 siblings: non-executing xcodebuild actions still ALLOW at DR (word-exact action match)" {
  state_with DR
  # `build-for-testing` compiles a test bundle without running it; `-scheme
  # MyTests` must not read as the `test` action on a substring match.
  for cmd in 'xcodebuild -scheme MyApp build' 'xcodebuild archive -scheme X' 'xcodebuild -scheme MyApp build-for-testing' 'xcodebuild -scheme MyTests build'; do
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    [ -z "$output" ] || fail "expected allow for: $cmd (got: $output)"
  done
}

@test "SR2-L2: CORPFLOW_TEST_GATE=off with NO .context/ at all creates nothing (no test_gate_disabled pollution)" {
  rm -rf "$WD/.context"
  run env CLAUDE_PROJECT_DIR="$WD" CORPFLOW_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats foo.bats')"
  assert_success
  [ -z "$output" ]
  [ ! -d "$WD/.context" ]
}

# --- R1/R2: non-selecting runner flags no longer read as scoping ---

@test "R1-1: multi-flag 'xcodebuild test' denies at DV (every executable invocation carries flags)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild test -project a.xcodeproj -scheme overlay -destination generic/platform=iOS')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.class == "full_test_run" and .metadata.command_head == "xcodebuild"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "R1-2: '-only-testing:' keeps a scoped xcodebuild run ALLOWED at DV (the over-deny direction)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild test -project a.xcodeproj -scheme s -only-testing:UnitTests/LogTests')"
  assert_success
  [ -z "$output" ]
}

@test "R1-3: QA remains the sole full-suite authority for the same multi-flag command" {
  state_with QA
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild test -project a.xcodeproj -scheme s -destination d')"
  assert_success
  [ -z "$output" ]
}

@test "R1-4: 'xcodebuild build' with the same flags still ALLOWS at DV (not test execution)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild build -project a.xcodeproj -scheme s')"
  assert_success
  [ -z "$output" ]
}

@test "R1-5: 'gradle test -p .' denies at DV (project-dir is not a selector)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'gradle test -p .')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R1-6: 'dotnet test MySolution.sln' denies at DV (the solution positional names what to build)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'dotnet test MySolution.sln')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R1-7: 'npm test -- --ci' denies at DV (the separator is not an argument)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'npm test -- --ci')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R2-1: 'cargo test --release' denies at DV (a build configuration is not a selection)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'cargo test --release')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R2-2: 'cargo test --release foo' still ALLOWS at DV (a real selector survives the strip)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'cargo test --release foo')"
  assert_success
  [ -z "$output" ]
}

@test "R1-8: a value-consuming flag missing its value must not swallow the token that follows" {
  # The surviving token must NOT be in the explicit selector list: that limb
  # matches on the whole segment BEFORE the strip runs, so an `-only-testing:`
  # case here passes with the guard deleted and proves nothing. `-MyScheme`
  # reaches the strip, and this case flips to a deny when the guard is removed.
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild test -project a -scheme -MyScheme')"
  assert_success
  [ -z "$output" ]
}

@test "R1-8 companion: '-only-testing:' after a valueless flag also allows (decided by the selector limb, not the guard)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'xcodebuild test -scheme -only-testing:UnitTests/LogTests')"
  assert_success
  [ -z "$output" ]
}

@test "R1-9: 'go test ./...' is UNCHANGED by the strip (whole-tree positionals stay a policy limit)" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'go test ./...')"
  assert_success
  [ -z "$output" ]
}

@test "R9: FN has no test-execution authority -> deny" {
  # Passes the day it is written: the stage limb already denies every stage but
  # DV/QA. Kept as a parity lock so a later edit to that limb cannot quietly
  # drop the row — not a bug catch, so do not delete it as a never-failing test.
  state_with FN
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'swift test')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.stage == "FN"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

# --- P1-2: quoted multi-word flag values are ONE token ---

@test "R1-10: a simulator destination denies at DV in all three quoting forms" {
  # A destination containing a space is the NORMAL shape for an iOS project and
  # is what the reported incident actually passed; before the tokenizer only the
  # space-free forms denied, so the fix missed its own motivating case.
  state_with DV
  local base='xcodebuild test -project a.xcodeproj -scheme overlay -destination '
  local cmd
  for dest in 'generic/platform=iOS' '"platform=iOS Simulator,name=iPhone 16 Pro"' "'platform=iOS Simulator,name=iPhone 16 Pro'"; do
    rm -f "$WD/.context/logs/audit.jsonl"
    cmd="${base}${dest}"
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
      || fail "expected deny for: $cmd"
  done
}

@test "R1-11: 'dotnet test \"My Solution.sln\"' denies (a quoted solution positional is still non-selecting)" {
  state_with DV
  local cmd='dotnet test "My Solution.sln"'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "R1-12: a quoted destination PLUS a real selector still ALLOWS at DV" {
  state_with DV
  local cmd='xcodebuild test -project a -scheme overlay -destination "platform=iOS Simulator,name=iPhone 16 Pro" -only-testing:UnitTests/LogTests'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
  assert_success
  [ -z "$output" ]
}

@test "R1-13: an unterminated quote strips nothing and ALLOWS (ambiguous parse degrades to today's behaviour)" {
  state_with DV
  local cmd='xcodebuild test -project a -scheme overlay -destination "platform=iOS Simulator'
  local payload
  payload="$(bash_payload "$cmd")"
  [ -n "$payload" ]
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
}

# --- P1-A: `-c` is value-taking on some runners and valueless on others ---

@test "R1-14: 'go test -c' compiles and runs nothing -> ALLOWS at DV and at a banned stage" {
  # Go's -c is valueless; the shared value-consuming strip ate the following
  # token (or ran off the end of the line) and denied a compile as a full run.
  for stage in DV DR; do
    state_with "$stage"
    for cmd in 'go test -c' 'go test -c ./pkg'; do
      run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
      assert_success
      [ -z "$output" ] || fail "expected allow at $stage for: $cmd (got: $output)"
    done
  done
}

@test "R1-15: rspec's '-c' is --colour, not a config path -> the spec file still selects" {
  state_with DV
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'rspec -c spec/models/user_spec.rb')"
  assert_success
  [ -z "$output" ]
}

@test "R1-16: value-taking '-c' runners are unaffected — the value is still consumed" {
  state_with DV
  for cmd in 'swift test -c release' 'dotnet test -c Release' 'go test' 'rspec'; do
    rm -f "$WD/.context/logs/audit.jsonl"
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
      || fail "expected deny for: $cmd"
  done
}

@test "R1-17: gradle's task is found order-independently — flags-before-task denies the same" {
  # A first-token read saw `-p` here, mistook the project dir for a surviving
  # positional, and let the full run through as scoped.
  state_with DV
  for cmd in 'gradle -p . test' './gradlew -p app testDebugUnitTest'; do
    rm -f "$WD/.context/logs/audit.jsonl"
    run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload "$cmd")"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
      || fail "expected deny for: $cmd"
  done
  # The over-deny guard: a real selector still allows in the same shape.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'gradle -p . test --tests com.foo.Bar')"
  assert_success
  [ -z "$output" ]
}

# --- dispatch coupling: the gate is only live while state.json says a stage is ---

@test "D1: RE + ./run-tests.sh -> deny (RE holds no test-execution authority)" {
  state_with RE
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  run jq -e '.metadata.stage == "RE" and .metadata.class == "full_test_run"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "D2: a ledger with NO stage in_progress fails open — the same command ALLOWS" {
  # The other half of D1, and the coupling that broke silently: the orchestrator
  # marked stages in_progress in the Task System only, so state.json never named
  # an acting stage after PL and every deny above was unreachable in a live run.
  # skills/worktask/SKILL.md step 5 mirrors the mark into state.json; without it
  # this allow is what the whole pipeline gets, at every stage.
  printf '{"stages":{"PL":{"status":"completed"},"RE":{"status":"completed"}}}' > "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "D3: SKILL.md step 5 mirrors the in_progress mark into state.json" {
  # The instruction IS the fix — nothing else makes the gate reachable — and the
  # orchestrator executes this block, so drift here re-inerts every case above.
  local skill="$PLUGIN_ROOT/skills/worktask/SKILL.md"
  run grep -A6 'TaskUpdate({ taskId: task.id, status: "in_progress" });' "$skill"
  assert_success
  assert_output --partial 'atomicMergeStateJson({ stages: { [full.metadata.stage]: { status: "in_progress" } } });'
}

@test "R1-18: flags-before-task build-only gradle tasks ALLOW at a banned stage (was a false deny)" {
  # `gradle -p . assembleAndroidTest` compiles a test APK and runs nothing;
  # the first-token read classified it a scoped test run and denied it at DR.
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'gradle -p . assembleAndroidTest')"
  assert_success
  [ -z "$output" ]
}
