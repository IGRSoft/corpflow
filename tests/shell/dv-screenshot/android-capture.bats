#!/usr/bin/env bats
# Behavioural tests for skills/dv-screenshot-capture/scripts/android-capture.sh.
#
# The load-bearing case is the --serial injection guard (_valid_serial): it must
# reject before `adb` is ever reached,
# which is provable only with a recording stub — an empty call log is the
# evidence that no dispatch happened.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="skills/dv-screenshot-capture/scripts/android-capture.sh"
WT="wt-android"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  printf '%s' '{"version":2,"worktask_id":"wt-android","tasks":{"DV0":{"status":"in_progress"}}}' \
    > "$WD/.context/state.json"
  export WORKSPACE_ROOT="$WD"
  IMAGES="$WD/.context/images/$WT"
  AUDIT_LOG="$WD/.context/logs/audit.jsonl"
}

teardown() {
  _test_helper_cleanup
}

capture() {
  run_script_env --cwd "$WD" --stub-path --separate-stderr "$SUT" \
    --worktask-id "$WT" --task-id DV0 --slug home-screen "$@"
}

# A stub adb that lists the given serials as online and streams a valid PNG.
stub_adb_with_devices() {
  local list=""
  local s
  for s in "$@"; do list="${list}${s}\tdevice\n"; done
  stub_cmd adb --body "
    if [ \"\$1\" = devices ]; then
      printf 'List of devices attached\n${list}\n'
      exit 0
    fi
    printf '\211PNG\r\n\032\nfixturebytes'
    exit 0"
}

# ---------------------------------------------------------------------------
# T1/T2 — the injection guard. Rejection must happen with adb untouched.
# ---------------------------------------------------------------------------
@test "T1: --serial with a shell metacharacter payload is rejected, adb never invoked" {
  stub_adb_with_devices emulator-5554

  capture --serial 'foo; rm -rf /'

  assert_failure 1
  [[ "$stderr" == *'--serial must match [A-Za-z0-9._:-]+ (got: foo; rm -rf /)'* ]]
  # The proof: the guard short-circuits ahead of dispatch.
  assert_equal "$(stub_log --count adb)" '0'
  assert_equal "$(stub_log adb)" ''
  # And it never reached path setup either.
  [ ! -d "$WD/.context/images" ]
}

@test "T2: --serial with command substitution is rejected literally, never expanded" {
  stub_adb_with_devices emulator-5554

  capture --serial '$(whoami)'

  assert_failure 1
  # The value is echoed back verbatim — if any layer had expanded it, the
  # username would appear here instead.
  [[ "$stderr" == *'(got: $(whoami))'* ]]
  [[ "$stderr" != *"(got: $(id -un))"* ]]
  assert_equal "$(stub_log --count adb)" '0'
}

@test "T3: well-formed serials are accepted — emulator and host:port forms" {
  stub_adb_with_devices emulator-5554 192.168.1.10:5555

  capture --serial emulator-5554
  assert_success
  assert_output "path=$IMAGES/dv-DV0-01-home-screen.png bytes=20 ok=true error=null"
  assert_equal "$(stub_log --argv adb --call 2)" '-s
emulator-5554
exec-out
screencap
-p'

  capture --serial 192.168.1.10:5555 --slug over-tcp
  assert_success
  assert_output "path=$IMAGES/dv-DV0-02-over-tcp.png bytes=20 ok=true error=null"
}

# ---------------------------------------------------------------------------
# T4 — tool absence.
# ---------------------------------------------------------------------------
@test "T4: adb absent exits 2 tool_missing with a fallback audit row" {
  run_script_env --cwd "$WD" --hide adb --separate-stderr "$SUT" \
    --worktask-id "$WT" --task-id DV0 --slug home-screen

  assert_failure 2
  assert_output "path=$IMAGES/dv-DV0-01-home-screen.png bytes=0 ok=false error=tool_missing"
  [[ "$stderr" == *'adb not on PATH'* ]]
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --actor android-capture-adapter --result ok \
    --jq '.metadata.reason == "adb_unavailable" and .metadata.used_adapter == "cli_fallback"'
}

# ---------------------------------------------------------------------------
# T5-T7 — device resolution.
# ---------------------------------------------------------------------------
@test "T5: two online devices without --serial is an ambiguity, not a guess" {
  stub_adb_with_devices emulator-5554 R58M12345XY

  capture

  assert_failure 3
  assert_output "path=$IMAGES/dv-DV0-01-home-screen.png bytes=0 ok=false error=capture_failed"
  [[ "$stderr" == *'2 online devices; pass --serial'* ]]
  # It refused at the resolution step: only `adb devices` ran, no screencap.
  assert_equal "$(stub_log --count adb)" '1'
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "multiple_devices"'
}

@test "T6: a valid-format serial that is not attached is serial_not_found" {
  stub_adb_with_devices emulator-5554

  capture --serial emulator-9999

  assert_failure 3
  [[ "$stderr" == *'--serial emulator-9999 is not among the online devices'* ]]
  assert_equal "$(stub_log --count adb)" '1'
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "serial_not_found"'
}

@test "T7: offline and unauthorized handsets do not count as attached" {
  stub_cmd adb --body '
    if [ "$1" = devices ]; then
      printf "List of devices attached\n0123456789ABCDEF\toffline\n9876543210\tunauthorized\n\n"
      exit 0
    fi
    printf "\211PNG\r\n\032\nfixturebytes"
    exit 0'

  capture

  assert_failure 3
  [[ "$stderr" == *'no online adb device'* ]]
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "no_device_attached"'
}

# ---------------------------------------------------------------------------
# T8/T9 — the file is the evidence, never the exit code alone.
# ---------------------------------------------------------------------------
@test "T8: a stream that is not a PNG is screencap_corrupt and is deleted" {
  stub_cmd adb --body '
    if [ "$1" = devices ]; then printf "List of devices attached\nemulator-5554\tdevice\n\n"; exit 0; fi
    printf "<!DOCTYPE html>not a png at all"
    exit 0'

  capture

  assert_failure 3
  assert_output "path=$IMAGES/dv-DV0-01-home-screen.png bytes=0 ok=false error=capture_failed"
  [ ! -e "$IMAGES/dv-DV0-01-home-screen.png" ]
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "screencap_corrupt"'
  assert_audit_row screenshot_captured --file "$AUDIT_LOG" --absent
}

@test "T9: a failing adb server is screencap_failed, distinct from a corrupt stream" {
  stub_cmd adb --body '
    if [ "$1" = devices ]; then printf "List of devices attached\nemulator-5554\tdevice\n\n"; exit 0; fi
    printf "error: device offline\n" >&2
    exit 1'

  capture

  assert_failure 3
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "screencap_failed"'
}

@test "T10: an adb-devices failure is adb_server_unreachable" {
  stub_cmd adb --exit 1 --stderr 'cannot connect to daemon'

  capture

  assert_failure 3
  [[ "$stderr" == *'`adb devices` failed (exit 1)'* ]]
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "adb_server_unreachable"'
}

# ---------------------------------------------------------------------------
# T11 — the slug is a path component; it is validated like one.
# ---------------------------------------------------------------------------
@test "T11: a traversal slug is rejected before any directory is created" {
  stub_adb_with_devices emulator-5554

  run_script_env --cwd "$WD" --stub-path --separate-stderr "$SUT" \
    --worktask-id "$WT" --task-id DV0 --slug '../../escaped'

  assert_failure 1
  [[ "$stderr" == *'--slug must be kebab-case'* ]]
  assert_equal "$(stub_log --count adb)" '0'
  [ ! -e "$WD/../escaped" ]
}

@test "T12: --self-test passes with no adb, no device and no network" {
  run_script_env --cwd "$WD" --hide adb "$SUT" --self-test
  assert_success
  assert_output --partial 'self-test: 8 passed, 0 failed'
}

@test "T13: no declared root exits 1 before adb is reached and creates nothing under cwd" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  stub_adb_with_devices emulator-5554
  run_script_env --cwd "$cwd" --stub-path --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --unset CONTEXT_DIR --env "GIT_CEILING_DIRECTORIES=$cwd" --separate-stderr "$SUT" \
    --worktask-id "$WT" --task-id DV0 --slug home-screen
  assert_failure 1
  [ ! -e "$cwd/.context" ]
  assert_equal "$(stub_log --count adb)" '0'
}

@test "T14: a ledger for another worktask exits 1; a missing --task-id is a usage error" {
  stub_adb_with_devices emulator-5554
  run_script_env --cwd "$WD" --stub-path --separate-stderr "$SUT" --worktask-id other --task-id DV0 --slug home-screen
  assert_failure 1
  [[ "$stderr" == *'does not match'* ]]
  run_script_env --cwd "$WD" --stub-path --separate-stderr "$SUT" --worktask-id "$WT" --slug home-screen
  assert_failure 1
  [[ "$stderr" == *'--task-id required'* ]]
  assert_equal "$(stub_log --count adb)" '0'
}
