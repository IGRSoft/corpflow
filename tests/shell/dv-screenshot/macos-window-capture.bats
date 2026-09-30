#!/usr/bin/env bats
# tests/shell/dv-screenshot/macos-window-capture.bats
# Target: skills/dv-screenshot-capture/scripts/macos-window-capture.sh
# Covers: self-test, argument and step-grammar errors, the 5-shot cap, ledger guards,
#         tool_missing and host-build failure routing, and the happy path end to end
#         (numbered PNGs, a manifest the gate accepts, audit rows) against a `swift` double,
#         so no toolchain or window server is needed.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/macos-window-capture.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/app/.context/logs"
  CTX="$WD/app/.context"
  printf '%s' '{"version":2,"worktask_id":"wt-test","platform":"apple","tasks":{"DV0":{"status":"in_progress","metadata":{"platform":"apple","agent":"corpflow:developer"}}}}' \
    > "$CTX/state.json"
  printf '// swift-tools-version: 5.9\n' > "$WD/app/Package.swift"
  printf 'import SwiftUI\n@MainActor func captureRoot() -> some View { Text("x") }\n' > "$WD/root.swift"
  printf '# menu first\nshot main-menu S1 main menu\nclick 240 212\nwait 0.5\nshot game-board\n' > "$WD/steps.txt"
}

# The `swift` double: dump-package reports one library product; build installs a host that
# writes a real PNG signature for every `shot <name>` step it reads, so the script's own
# signature check and manifest writer run for real.
stub_swift() { # [build-exit]
  export CORPFLOW_HOST_OS=macos
  stub_cmd swift --body '
    case "$1" in
      package)
        printf "%s\n" "{\"platforms\":[{\"platformName\":\"macos\",\"version\":\"15.0\"}],\"products\":[{\"name\":\"AppKitLib\",\"type\":{\"library\":[\"automatic\"]}},{\"name\":\"app\",\"type\":{\"executable\":null}}]}"
        exit 0 ;;
      build)
        [ "'"${1:-0}"'" = 0 ] || { echo "/x/CaptureRoot.swift:2:1: error: boom"; exit 1; }
        mkdir -p "$3/.build/debug"
        cat > "$3/.build/debug/WindowCaptureHost" <<"HOST"
#!/usr/bin/env bash
while read -r verb name; do
  [ "$verb" = shot ] && printf "\211PNG\r\n\032\nhost" > "$1/$name.png"
done
exit 0
HOST
        chmod +x "$3/.build/debug/WindowCaptureHost"
        exit 0 ;;
    esac
    exit 0'
}

capture() { # [extra args...]
  run_script_env --cwd "$WD/app" --stub-path --env "CONTEXT_DIR=$CTX" "$SCRIPT" \
    --worktask-id wt-test --task-id DV0 --product AppKitLib \
    --root-file "$WD/root.swift" --steps "$WD/steps.txt" "$@"
}

@test "self-test passes" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "0 failed"
}

@test "happy: numbered PNGs, a manifest the gate accepts, audit rows and a facts array" {
  stub_swift
  capture
  assert_success
  assert_line --partial "dv-DV0-01-main-menu.png bytes="
  assert_line --partial "dv-DV0-02-game-board.png bytes="
  assert_output --partial "manifest=$CTX/images/wt-test/screenshots-DV0.md"
  assert_output --partial 'facts_screenshots=[{"slug":"main-menu"'
  run grep -c '| macos_window |' "$CTX/images/wt-test/screenshots-DV0.md"
  assert_output "2"
  run grep -F '| S1 main menu |' "$CTX/images/wt-test/screenshots-DV0.md"
  assert_success
  run bash "$PLUGIN_ROOT/skills/worktask/scripts/attach-visual-evidence.sh" --validate-manifest \
    "$CTX/images/wt-test/screenshots-DV0.md" --task-id DV0 --images-dir "$CTX/images/wt-test"
  assert_success
  run jq -se 'map(select(.action == "screenshot_captured" and .task_id == "DV0")) | length == 2' \
    "$CTX/logs/audit.jsonl"
  assert_success
  # A second run continues the task's numbering and appends to the same table.
  printf 'shot settings\n' > "$WD/steps.txt"
  capture
  assert_success
  assert_output --partial "dv-DV0-03-settings.png"
  run grep -c '| macos_window |' "$CTX/images/wt-test/screenshots-DV0.md"
  assert_output "3"
}

@test "probe: unnumbered shots under the host dir, no manifest and no audit row" {
  stub_swift
  capture --probe
  assert_success
  assert_output --partial "probe=$CTX/tools/WindowCaptureHost/probe/main-menu.png"
  [ ! -e "$CTX/images/wt-test/screenshots-DV0.md" ]
  [ ! -e "$CTX/logs/audit.jsonl" ] || ! grep -q screenshot_captured "$CTX/logs/audit.jsonl"
}

@test "arg errors: missing --product, bad step grammar and a sixth shot all exit 1" {
  run_script_env --cwd "$WD/app" --env "CONTEXT_DIR=$CTX" "$SCRIPT" \
    --worktask-id wt-test --task-id DV0 --root-file "$WD/root.swift" --steps "$WD/steps.txt"
  [ "$status" -eq 1 ]
  printf 'click 10\n' > "$WD/steps.txt"
  capture
  [ "$status" -eq 1 ]
  assert_output --partial "bad step at line 1"
  printf 'shot a\nshot b\nshot c\nshot d\nshot e\nshot f\n' > "$WD/steps.txt"
  capture
  [ "$status" -eq 1 ]
  assert_output --partial "screenshot_count_exceeded"
  [ ! -e "$CTX/images" ]
}

@test "ledger: another worktask or a task the ledger lacks exits 1 without writing" {
  run_script_env --cwd "$WD/app" --env "CONTEXT_DIR=$CTX" "$SCRIPT" \
    --worktask-id other --task-id DV0 --product AppKitLib --root-file "$WD/root.swift" --steps "$WD/steps.txt"
  [ "$status" -eq 1 ]
  run_script_env --cwd "$WD/app" --env "CONTEXT_DIR=$CTX" "$SCRIPT" \
    --worktask-id wt-test --task-id DV4 --product AppKitLib --root-file "$WD/root.swift" --steps "$WD/steps.txt"
  [ "$status" -eq 1 ]
  [ ! -e "$CTX/images" ]
}

@test "tool_missing: no swift exits 2 with the contract line and a fallback audit row" {
  run_script_env --cwd "$WD/app" --hide swift --env "CONTEXT_DIR=$CTX" "$SCRIPT" \
    --worktask-id wt-test --task-id DV0 --product AppKitLib --root-file "$WD/root.swift" --steps "$WD/steps.txt"
  [ "$status" -eq 2 ]
  assert_output --partial "dv-DV0-01-main-menu.png bytes=0 ok=false error=tool_missing"
  run jq -se 'map(select(.action == "screenshot_platform_fallback")) | length == 1' "$CTX/logs/audit.jsonl"
  assert_success
}

@test "unknown product exits 1 and names the library products" {
  stub_swift
  run_script_env --cwd "$WD/app" --stub-path --env "CONTEXT_DIR=$CTX" "$SCRIPT" \
    --worktask-id wt-test --task-id DV0 --product Nope --root-file "$WD/root.swift" --steps "$WD/steps.txt"
  [ "$status" -eq 1 ]
  assert_output --partial "library products: AppKitLib"
}

@test "host build failure exits 3, surfaces the error line and lands no image" {
  stub_swift 1
  capture
  [ "$status" -eq 3 ]
  assert_output --partial "error: boom"
  assert_output --partial "error=capture_failed"
  run find "$CTX/images/wt-test" -name 'dv-DV0-*'
  assert_output ""
}
