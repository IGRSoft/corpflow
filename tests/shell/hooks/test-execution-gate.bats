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
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')"
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
  local fakebin
  fakebin="$(mk_tmpworkdir)"
  # PATH with no jq: only core utilities the script's own shebang needs.
  run env CLAUDE_PROJECT_DIR="$WD" PATH="/usr/bin:/bin" bash -c '
    command -v jq >/dev/null 2>&1 && exit 77   # skip guard: real jq still on PATH
    exec bash "'"$PLUGIN_ROOT/$SCRIPT"'"
  ' <<< "$(bash_payload './run-tests.sh')"
  if [ "$status" -eq 77 ]; then
    skip "jq present on /usr/bin:/bin in this environment; branch not exercisable without a chroot"
  fi
  assert_success
  [ -z "$output" ]
}

@test "7: IGRSOFT_TEST_GATE=off -> allow even for a banned stage" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" IGRSOFT_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload './run-tests.sh')"
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
  local payload='{"tool_name":"Task","tool_input":{"subagent_type":"igrsoft:developer","prompt":"DO NOT execute tests: bats, pytest, cargo test are forbidden outside DV/QA"}}'
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
  local payload='{"tool_name":"Task","tool_input":{"subagent_type":"igrsoft:developer","prompt":"go ahead and make the change to the algorithm"}}'
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$payload"
  assert_success
  [ -z "$output" ]
  [ ! -d "$WD/.context" ]
}

@test "P1-1: word-boundary token match — 'algorithm' does not trip the observe row (bare substring 'go' inside it)" {
  state_with DR
  local payload='{"tool_name":"Task","tool_input":{"subagent_type":"igrsoft:developer","prompt":"refine the sorting algorithm and category logic"}}'
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

@test "RK4 structural item 1: IGRSOFT_TEST_GATE=off writes ONE test_gate_disabled row, not one per call" {
  state_with DR
  run env CLAUDE_PROJECT_DIR="$WD" IGRSOFT_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats foo.bats')"
  assert_success
  run env CLAUDE_PROJECT_DIR="$WD" IGRSOFT_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'pytest tests/')"
  assert_success
  run jq -e '.action == "test_gate_disabled" and .metadata.vector == "IGRSOFT_TEST_GATE"' \
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
  run jq -s -e 'map(.metadata.class) | unique | length == 1 and .[0] == "scoped_test_run"' \
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

@test "SR2-L2: IGRSOFT_TEST_GATE=off with NO .context/ at all creates nothing (no test_gate_disabled pollution)" {
  rm -rf "$WD/.context"
  run env CLAUDE_PROJECT_DIR="$WD" IGRSOFT_TEST_GATE=off bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(bash_payload 'bats foo.bats')"
  assert_success
  [ -z "$output" ]
  [ ! -d "$WD/.context" ]
}
