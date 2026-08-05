#!/usr/bin/env bats
# Behavioural tests for skills/dv-screenshot-capture/scripts/web-capture.sh.
#
# Offline by construction: every Playwright entry point is a recording stub, so
# the network-fetch guard is proven by what the stub was NEVER asked to do
# rather than by an absence of evidence.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="skills/dv-screenshot-capture/scripts/web-capture.sh"
WT="wt-web"

setup() {
  WD="$(mk_tmpworkdir)"
  IMAGES=".context/images/$WT"
  AUDIT_LOG="$WD/.context/logs/audit.jsonl"
}

teardown() {
  _test_helper_cleanup
}

capture() {  # capture [extra args...] — always with the three required flags
  run_script_env --cwd "$WD" --stub-path --separate-stderr "$SUT" \
    --worktask-id "$WT" --slug hero-shot --url https://example.com/app "$@"
}

# A stub that behaves like a working Playwright CLI: the last argv slot is the
# output path, and a real capture is a non-empty PNG on disk.
stub_playwright_writing_png() {
  stub_cmd "$1" --body 'out="${@: -1}"; printf "\211PNG\r\n\032\nfixture" > "$out"; exit 0'
}

# ---------------------------------------------------------------------------
# T1 — argument contract.
# ---------------------------------------------------------------------------
@test "T1: a missing required flag prints usage and exits 1" {
  run_script_env --cwd "$WD" --separate-stderr "$SUT" --slug s --url https://example.com
  assert_failure 1
  assert_output ''
  [[ "$stderr" == *'--worktask-id required'* ]]
  [[ "$stderr" == *'usage: web-capture.sh'* ]]
}

@test "T2: a javascript: URL is rejected before any tool is reached" {
  stub_playwright_writing_png playwright
  run_script_env --cwd "$WD" --stub-path --separate-stderr "$SUT" \
    --worktask-id "$WT" --slug hero-shot --url 'javascript:alert(1)'
  assert_failure 1
  [[ "$stderr" == *'--url must be an http/https/file URL'* ]]
  # The allow-list must short-circuit ahead of dispatch, not after it.
  assert_equal "$(stub_log --count playwright)" '0'
  [ ! -d "$WD/.context/images" ]
}

# ---------------------------------------------------------------------------
# T3 — the offline guard. This is the load-bearing proof.
#
# NOTE (premise correction): the plan's shorthand was "`stub_log npx` is empty
# without --allow-npx-install". That cannot hold — the script deliberately
# probes `npx --no-install playwright --version`, which is itself an offline
# call. The real invariant is that `npx --yes` (the form that FETCHES over the
# network) is unreachable without the flag, so that is what is asserted.
# ---------------------------------------------------------------------------
@test "T3: without --allow-npx-install npx is never invoked with --yes" {
  # A local package that is not installed: the --no-install probe fails.
  stub_cmd npx --exit 1

  capture
  assert_failure 2
  assert_output "path=$IMAGES/dv-01-hero-shot.png bytes=0 ok=false error=tool_missing"

  # The probe ran (offline, --no-install) …
  assert_equal "$(stub_log --count npx)" '1'
  assert_equal "$(stub_log --argv npx --call 1)" '--no-install
playwright
--version'
  # … and the network-fetching form never did.
  refute_line --partial '--yes'
  [[ "$(stub_log npx)" != *'--yes'* ]]
}

@test "T4: --allow-npx-install is the only thing that unlocks the fetching form" {
  stub_cmd npx --body '
    case "$1" in
      --no-install) exit 1 ;;                 # package genuinely absent
      --yes) exit 0 ;;                        # fetch path — records but produces nothing
    esac'

  capture --allow-npx-install
  # No PNG was produced by the stub, so the adapter reports capture_failed (3),
  # not tool_missing (2) — the entry point WAS resolved.
  assert_failure 3
  assert_output "path=$IMAGES/dv-01-hero-shot.png bytes=0 ok=false error=capture_failed"
  [[ "$(stub_log npx)" == *'--yes playwright screenshot'* ]]
}

@test "T5: no npx and no playwright binary exits 2 tool_missing" {
  run_script_env --cwd "$WD" --hide npx --hide playwright --separate-stderr "$SUT" \
    --worktask-id "$WT" --slug hero-shot --url https://example.com/app
  assert_failure 2
  assert_output "path=$IMAGES/dv-01-hero-shot.png bytes=0 ok=false error=tool_missing"
  [[ "$stderr" == *'Playwright not available'* ]]
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --actor web-capture-adapter --result ok \
    --jq '.metadata.reason == "playwright_unavailable" and .metadata.used_adapter == "cli_fallback"'
}

# ---------------------------------------------------------------------------
# T6 — the canonical dv-NN naming, and that NN never resets.
# ---------------------------------------------------------------------------
@test "T6: a successful capture lands at .context/images/<id>/dv-NN-<slug>.png" {
  stub_playwright_writing_png playwright

  capture
  assert_success
  assert_output "path=$IMAGES/dv-01-hero-shot.png bytes=15 ok=true error=null"
  [ -s "$WD/$IMAGES/dv-01-hero-shot.png" ]

  assert_audit_row screenshot_captured --file "$AUDIT_LOG" --result ok \
    --jq '.metadata.slug == "hero-shot" and .metadata.bytes == 15
          and .metadata.adapter == "web/playwright"'
}

@test "T7: NN is monotonic across reruns and does not reset" {
  mkdir -p "$WD/$IMAGES"
  printf 'x' > "$WD/$IMAGES/dv-01-earlier.png"
  printf 'x' > "$WD/$IMAGES/dv-02-earlier.png"
  stub_playwright_writing_png playwright

  capture
  assert_success
  assert_output --partial "dv-03-hero-shot.png"

  capture --slug second-shot
  assert_success
  assert_output --partial "dv-04-second-shot.png"
}

# ---------------------------------------------------------------------------
# T8 — a zero-byte PNG is a failed capture, never a pass.
# ---------------------------------------------------------------------------
@test "T8: an empty output file is classified capture_failed and removed" {
  stub_cmd playwright --body 'out="${@: -1}"; : > "$out"; exit 0'

  capture
  assert_failure 3
  assert_output "path=$IMAGES/dv-01-hero-shot.png bytes=0 ok=false error=capture_failed"
  [ ! -e "$WD/$IMAGES/dv-01-hero-shot.png" ]
  assert_audit_row screenshot_captured --file "$AUDIT_LOG" --absent
}

@test "T9: a Playwright timeout log is classified playwright_timeout" {
  stub_cmd playwright --body 'printf "page.goto: Timeout 30000ms exceeded.\n" >&2; exit 1'

  capture
  assert_failure 3
  assert_audit_row screenshot_platform_fallback --file "$AUDIT_LOG" \
    --jq '.metadata.reason == "playwright_timeout"'
}

# ---------------------------------------------------------------------------
# T10 — jq absent: the audit row degrades to the hand-built form, and the
# capture itself still succeeds.
# ---------------------------------------------------------------------------
@test "T10: jq absent falls back to minimal audit JSON without failing the capture" {
  stub_playwright_writing_png playwright
  run_script_env --cwd "$WD" --hide jq --separate-stderr "$SUT" \
    --worktask-id "$WT" --slug hero-shot --url https://example.com/app

  assert_success
  assert_output "path=$IMAGES/dv-01-hero-shot.png bytes=15 ok=true error=null"

  # The fallback branch emits a valid row with no metadata object at all.
  assert_audit_row screenshot_captured --file "$AUDIT_LOG" \
    --actor web-capture-adapter --result ok \
    --jq 'has("metadata") | not'
}

@test "T11: --self-test passes without a browser, a network or a repo" {
  run_script_env --cwd "$WD" --hide npx --hide playwright "$SUT" --self-test
  assert_success
  assert_output --partial 'self-test: 7 passed, 0 failed'
}
