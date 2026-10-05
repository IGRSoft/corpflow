#!/usr/bin/env bats
# tests/shell/dv-screenshot/capture-entry.bats
# Target: skills/dv-screenshot-capture/scripts/capture.sh
# Covers: argument and guard errors (exit 2, nothing written), routing per platform through the
#         real adapter scripts against tool doubles, the ladder down to the tool_missing floor,
#         the size budget, the 5-capture cap, the summary and facts_screenshots shape, and that
#         hooks/dv-screenshot-gate.sh --check accepts every manifest it writes.
# Every run uses the --hide farm, so no real silicon, ImageMagick, Playwright, adb or swift on
# the host can leak in; doubles on $STUB_BIN are the only tools.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="skills/dv-screenshot-capture/scripts/capture.sh"
GATE="hooks/dv-screenshot-gate.sh"
WID="wt-cap"

setup() {
  WD="$(mk_tmpworkdir)"
  CTX="$WD/.context"
  mkdir -p "$CTX/logs"
  ledger web
  IMG="$CTX/images/$WID"
  MF="$IMG/screenshots-DV0.md"
  AUDIT_LOG="$CTX/logs/audit.jsonl"
}

teardown() {
  _test_helper_cleanup
}

ledger() { # <platform>
  jq -n --arg p "$1" --arg w "$WID" '{version: 2, worktask_id: $w, platform: $p,
    metadata: {requires_screenshots: true},
    tasks: {DV0: {status: "in_progress", metadata: {stage: "DV", agent: "corpflow:developer", platform: $p}}}}' \
    > "$CTX/state.json"
}

cap() { # [args...] — hermetic PATH: stubs + the allowlist farm, nothing else
  run_script_env --cwd "$WD" --hide pngquant --separate-stderr --env "WORKSPACE_ROOT=$WD" \
    "$SUT" --task-id DV0 "$@"
}

gate_check() { run bash "$PLUGIN_ROOT/$GATE" --check DV0 --state "$CTX/state.json"; }

git_repo() {
  git -C "$WD" init -q
  git -C "$WD" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

stub_png_writer() { # <name> — drains stdin (silicon reads a pipe), writes a PNG to the path after --output, else to the last argv
  stub_cmd "$1" --body 'out="${@: -1}"; prev=""
    for a in "$@"; do [ "$prev" = "--output" ] && out="$a"; prev="$a"; done
    cat > /dev/null 2>&1 || true; printf "\211PNG\r\n\032\nfixture" > "$out"; exit 0'
}

# Reads the last cap's stdout, so call it before gate_check replaces $output.
facts() { printf '%s\n' "$output" | sed -n 's/^facts_screenshots=//p'; }

# --- contract and validation --------------------------------------------------

@test "self-test passes" {
  run bash "$PLUGIN_ROOT/$SUT" --self-test
  assert_success
  assert_output --partial "0 failed"
}

@test "usage errors exit 2 and write nothing" {
  cap --capture diff --bogus x
  assert_failure 2
  run_script_env --cwd "$WD" --env "WORKSPACE_ROOT=$WD" "$SUT" --capture diff
  assert_failure 2
  cap --task-id dv0 --capture diff
  assert_failure 2
  cap
  assert_failure 2
  cap --capture BadSlug:https://x.test
  assert_failure 2
  cap --capture "a$(printf '%0.sa' {1..40})"
  assert_failure 2
  cap --capture a:https://x.test --capture a:https://y.test
  assert_failure 2
  cap --capture a --capture b --capture c --capture d --capture e --capture f
  assert_failure 2
  [[ "$stderr" == *screenshot_count_exceeded* ]]
  [ ! -e "$CTX/images" ]
}

@test "per-adapter argument checks: web needs a safe URL, flags stay on their platform" {
  cap --capture home
  assert_failure 2
  cap --capture 'home:javascript:alert(1)'
  assert_failure 2
  cap --capture home:https://x.test --product App --root-file "$WD/nope.swift"
  assert_failure 2
  cap --platform backend --capture diff --viewport 800x600
  assert_failure 2
  cap --platform backend --capture "diff:$WD/missing-list"
  assert_failure 2
  [ ! -e "$CTX/images" ]
}

@test "guard: no worktask resolved exits 2 with the guard line and creates nothing" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --separate-stderr --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --unset CONTEXT_DIR --env "GIT_CEILING_DIRECTORIES=$cwd" "$SUT" --task-id DV0 --capture diff
  assert_failure 2
  [[ "$stderr" == *'no worktask resolved'* ]]
  [ ! -e "$cwd/.context" ]
}

@test "guard: another worktask's id or a task the ledger lacks exits 2 without writing" {
  cap --worktask-id other --capture home:https://x.test
  assert_failure 2
  cap --task-id DV7 --capture home:https://x.test
  assert_failure 2
  [ ! -e "$CTX/images" ]
}

# --- routing ------------------------------------------------------------------

@test "web: Playwright double → web/playwright rows the gate accepts, numbered per task" {
  stub_png_writer playwright
  cap --capture home:https://x.test/ --capture settings:https://x.test/s --viewport 800x600
  assert_success
  assert_line --index 0 --regexp '^01 home web/playwright [0-9]+$'
  assert_line --index 1 --regexp '^02 settings web/playwright [0-9]+$'
  assert_line --index 2 "manifest=$MF"
  grep -q '^| 01 | home | dv-DV0-01-home.png | [0-9]* | web | web/playwright | home | 20[0-9-]*T[0-9:]*Z | — |$' "$MF"
  facts | jq -e --arg d "$IMG" 'length == 2 and all(.[]; (keys == ["bytes","design_ref","ok","path","platform","slug"])
    and .ok == true and .platform == "web" and (.bytes > 0) and (.path | startswith($d)))'
  gate_check
  assert_success
  assert_output --partial 'class=captured'
  # web-capture.sh writes screenshot_captured itself; the entry point adds no second row.
  assert_audit_row screenshot_captured --count 2
}

@test "web: Playwright absent → ladder to cli_fallback → tool_missing floor row, recorded" {
  cap --capture home:https://x.test/
  assert_success
  assert_line --index 0 '01 home cli_fallback tool_missing'
  grep -q '^| 01 | home | — | 0 | web | cli_fallback | tool_missing: silicon(absent), magick(absent), convert(absent) |' "$MF"
  grep -qF -- '- dv-DV0-01: web/playwright → cli_fallback (`tool_missing`, exit 2).' "$MF"
  grep -qF -- '- dv-DV0-01: silicon and ImageMagick both absent on PATH' "$MF"
  facts | jq -e '.[0].ok == false and .[0].bytes == 0 and .[0].slug == "home"'
  gate_check
  assert_failure 4
  assert_audit_row screenshot_platform_fallback --jq '.metadata.reason == "playwright_unavailable"'
  assert_audit_row screenshot_capture_failed --jq '.metadata.reason == "tool_missing"'
}

@test "android: adb double → android/adb row the gate accepts; the serial is forwarded" {
  ledger android
  stub_cmd adb --body '
    if [ "$1" = devices ]; then printf "List of devices attached\nemulator-5554\tdevice\n\n"; exit 0; fi
    printf "\211PNG\r\n\032\nfixturebytes"; exit 0'
  cap --capture home-screen:emulator-5554
  assert_success
  assert_line --index 0 --regexp '^01 home-screen android/adb [0-9]+$'
  grep -q '| 01 | home-screen | dv-DV0-01-home-screen.png | [0-9]* | android | android/adb |' "$MF"
  run stub_log adb
  assert_output --partial 'emulator-5554'
  gate_check
  assert_success
}

@test "meta-work (all): silicon double renders the annotated diff; file list reaches --files" {
  ledger all
  git_repo
  stub_png_writer silicon
  printf 'agents/developer.md\n' > "$WD/files.txt"
  cap --capture "skill-diff:$WD/files.txt" --base-ref HEAD
  assert_success
  assert_line --index 0 --regexp '^01 skill-diff cli_fallback [0-9]+$'
  grep -q '| 01 | skill-diff | dv-DV0-01-skill-diff.png | [0-9]* | all | cli_fallback | skill-diff |' "$MF"
  grep -q -- "--files $WD/files.txt" "$CTX"/logs/dv-capture-DV0-*.log
  gate_check
  assert_success
  assert_audit_row screenshot_platform_fallback --jq '.metadata.reason == "unknown_platform" and .actor == "dv-capture-entry"'
}

@test "backend: every image tool absent → exit 0 with the floor row; the gate classes it tool_missing_only" {
  ledger backend
  cap --capture diff
  assert_success
  assert_line --index 0 '01 diff cli_fallback tool_missing'
  [ "${#lines[@]}" -eq 3 ]
  gate_check
  assert_failure 4
  assert_output --partial 'class=tool_missing_only'
}

@test "a present tool that renders nothing → exit 3, no row, failure in the summary and manifest" {
  ledger systems
  git_repo
  stub_cmd silicon --exit 1
  cap --capture diff --base-ref HEAD
  assert_failure 3
  assert_line --index 0 '01 diff cli_fallback failed:render_failed'
  grep -qF 'produced no image and no row (`render_failed`)' "$MF"
  ! grep -q '^| 01 ' "$MF"
  [[ "$stderr" == *'ended with no row'* ]]
}

@test "apple without --product or --canvas-files: delegation_unavailable, cli_fallback used and noted" {
  ledger apple
  cap --capture main-menu
  assert_success
  assert_line --index 0 '01 main-menu cli_fallback tool_missing'
  grep -qF -- '- main-menu: apple simulator capture is delegated to the platform agent (`delegation_unavailable`)' "$MF"
  assert_audit_row screenshot_platform_fallback --jq '.metadata.reason == "delegation_unavailable"'
}

@test "macOS app: macos_window batch writes its own rows once; the gate accepts the manifest" {
  ledger apple
  mkdir -p "$WD/app"
  printf '// swift-tools-version: 5.9\n' > "$WD/app/Package.swift"
  printf 'import SwiftUI\n@MainActor func captureRoot() -> some View { Text("x") }\n' > "$WD/root.swift"
  printf 'click 240 212\nwait 0.5\n' > "$WD/to-board.txt"
  stub_cmd swift --body '
    case "$1" in
      package)
        printf "%s\n" "{\"platforms\":[{\"platformName\":\"macos\",\"version\":\"15.0\"}],\"products\":[{\"name\":\"AppLib\",\"type\":{\"library\":[\"automatic\"]}}]}"
        exit 0 ;;
      build)
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
  run_script_env --cwd "$WD/app" --hide pngquant --separate-stderr --env "CORPFLOW_HOST_OS=macos" \
    "$SUT" --task-id DV0 --context-dir "$CTX" --product AppLib --root-file "$WD/root.swift" \
    --capture main-menu --capture "game-board:$WD/to-board.txt"
  assert_success
  assert_line --index 0 --regexp '^01 main-menu macos_window [0-9]+$'
  assert_line --index 1 --regexp '^02 game-board macos_window [0-9]+$'
  [ "$(grep -c 'macos_window' "$MF")" -eq 2 ]
  grep -qxF -- '- (none)' "$MF"
  facts | jq -e 'map(.slug) == ["main-menu","game-board"] and all(.[]; .ok)'
  gate_check
  assert_success
}

# --- budget and cap -------------------------------------------------------------

@test "size budget: an unquantizable PNG moves to oversize/, gets no row, and is listed link-only" {
  stub_cmd playwright --body 'out="${@: -1}"; { printf "\211PNG\r\n\032\n"; head -c 600000 /dev/zero; } > "$out"; exit 0'
  cap --capture hero:https://x.test/
  assert_success
  assert_line --index 0 --regexp '^01 hero web/playwright oversize$'
  [ -f "$IMG/oversize/dv-DV0-01-hero.png" ]
  [ ! -e "$IMG/dv-DV0-01-hero.png" ]
  ! grep -q '^| 01 ' "$MF"
  grep -q "^- $IMG/oversize/dv-DV0-01-hero.png: [0-9]* after quantize, exceeds 500 KB$" "$MF"
  facts | jq -e '.[0].ok == false and (.[0].path | endswith("/oversize/dv-DV0-01-hero.png"))'
  assert_audit_row screenshot_size_fail
}

@test "cap: four existing rows leave room for one; the rest are refused and audited" {
  stub_png_writer playwright
  cap --capture a:https://x.test/a --capture b:https://x.test/b --capture c:https://x.test/c --capture d:https://x.test/d
  assert_success
  cap --capture e:https://x.test/e --capture f:https://x.test/f
  assert_success
  assert_line --index 0 --regexp '^05 e web/playwright [0-9]+$'
  assert_line --index 1 -- '-- f - screenshot_count_exceeded'
  [ ! -e "$IMG/dv-DV0-06-f.png" ]
  facts | jq -e 'length == 1 and .[0].slug == "e"'
  assert_audit_row screenshot_count_exceeded --jq '.metadata.attempted_slug == "f"'
  gate_check
  assert_success
}

@test "a rerun that lands an image supersedes the slug's tool_missing row" {
  ledger all
  cap --capture diff
  assert_success
  grep -q 'tool_missing:' "$MF"
  git_repo
  stub_png_writer silicon
  cap --capture diff --base-ref HEAD
  assert_success
  assert_line --index 0 --regexp '^02 diff cli_fallback [0-9]+$'
  ! grep -q 'tool_missing:' "$MF"
  gate_check
  assert_success
}
