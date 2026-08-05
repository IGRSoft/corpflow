#!/usr/bin/env bats
# Guard tests for examples/canvas-fixture/run-e2e.sh.
#
# The script resolves its own repo root from ${BASH_SOURCE} and `cd`s there
# before writing .context/{images,designs,logs}. Running the shipped copy in a
# test would therefore write into the real tree, so every test drives a
# RELOCATED copy inside a scratch root — which also makes relocation
# containment (nothing written outside that root) directly assertable.
#
# `--hide swift` is not a host workaround: it pins the graceful-degrade arm the
# script documents, so the result is identical on a Mac with Xcode and on CI.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="examples/canvas-fixture/run-e2e.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  ROOT="$WD/root"
  TMPHOME="$WD/tmp"
  mkdir -p "$ROOT/examples/canvas-fixture" \
           "$ROOT/skills/dv-screenshot-capture/scripts" \
           "$TMPHOME"
  cp "$PLUGIN_ROOT/$SUT" "$ROOT/examples/canvas-fixture/run-e2e.sh"
  chmod +x "$ROOT/examples/canvas-fixture/run-e2e.sh"
  ADAPTER="$ROOT/skills/dv-screenshot-capture/scripts/apple-canvas.sh"
}

teardown() {
  _test_helper_cleanup
}

# A stand-in adapter that emits the audit rows named in its argument list.
mk_adapter() {  # mk_adapter [action...]
  {
    echo '#!/usr/bin/env bash'
    echo 'mkdir -p .context/logs'
    local action
    for action in "$@"; do
      printf 'printf %s >> .context/logs/audit.jsonl\n' \
        "'{\"ts\":\"2020-01-01T00:00:00Z\",\"action\":\"$action\",\"result\":\"ok\"}\n'"
    done
    echo 'exit 0'
  } > "$ADAPTER"
  chmod +x "$ADAPTER"
}

run_e2e() {
  run_script_env --cwd "$ROOT" --hide swift --env "TMPDIR=$TMPHOME" \
    ./examples/canvas-fixture/run-e2e.sh "$@"
}

# ---------------------------------------------------------------------------
# T1 — the harness passes only when the adapter actually logged a render.
# ---------------------------------------------------------------------------
@test "T1: a canvas_render row makes the smoke pass" {
  mk_adapter canvas_render

  run_e2e

  assert_success
  assert_line '[PASS] canvas_render row present'
  assert_line '[run-e2e] summary: 1 pass / 0 fail'
}

@test "T2: no canvas_render row fails the smoke — the assertion is not decorative" {
  mk_adapter                                  # adapter runs, logs nothing

  run_e2e

  assert_failure 1
  assert_line '[FAIL] canvas_render row missing'
  assert_line '[run-e2e] summary: 0 pass / 1 fail'
}

@test "T3: an adapter that cannot run at all still fails rather than passing blind" {
  # No adapter on disk: the harness swallows the adapter's exit code by design,
  # so only the audit-row assertion stands between this and a false green.
  run_e2e

  assert_failure 1
  assert_line '[FAIL] canvas_render row missing'
  assert_output --partial '[run-e2e] apple-canvas.sh exit=127'
}

# ---------------------------------------------------------------------------
# T4 — the design-ref arm is conditional, and it is a real assertion.
# ---------------------------------------------------------------------------
@test "T4: with a design-ref present a missing visual_diff_run row fails" {
  mk_adapter canvas_render
  mkdir -p "$ROOT/.context/designs/canvas-fixture-smoke" \
           "$ROOT/.context/images/canvas-fixture-smoke"
  printf 'x' > "$ROOT/.context/designs/canvas-fixture-smoke/design-ref.png"
  printf 'x' > "$ROOT/.context/images/canvas-fixture-smoke/dv-01-canvas-fixture.png"

  run_e2e

  assert_failure 1
  assert_line '[FAIL] visual_diff_run row missing (design-ref present)'
  assert_line '[run-e2e] summary: 1 pass / 1 fail'
}

@test "T5: without a design-ref the visual-diff arm is skipped, not silently passed" {
  mk_adapter canvas_render

  run_e2e

  assert_success
  assert_line '[SKIP] visual_diff_run — no design-ref.png'
  refute_line '[PASS] visual_diff_run row present'
}

# ---------------------------------------------------------------------------
# T6 — graceful degrade without a Swift toolchain.
# ---------------------------------------------------------------------------
@test "T6: swift absent reports swift=0 and skips the preview assertion" {
  mk_adapter canvas_render

  run_e2e

  assert_success
  assert_line '[run-e2e] swift=0 magick=0'
  assert_line '[SKIP] preview_added — swift toolchain not installed'
}

# ---------------------------------------------------------------------------
# T7/T8 — containment. This is what makes the relocated copy the right harness.
# ---------------------------------------------------------------------------
@test "T7: every write lands under the resolved repo root and nowhere else" {
  mk_adapter canvas_render
  before="$(find "$WD" -newer "$ROOT/examples/canvas-fixture/run-e2e.sh" 2> /dev/null | wc -l)"

  run_e2e
  assert_success

  [ -f "$ROOT/.context/logs/audit.jsonl" ]
  [ -d "$ROOT/.context/images/canvas-fixture-smoke" ]
  [ -d "$ROOT/.context/designs/canvas-fixture-smoke" ]
  # The shipped tree must be untouched by the relocated run.
  [ ! -e "$PLUGIN_ROOT/.context/images/canvas-fixture-smoke" ]
  [ ! -e "$PLUGIN_ROOT/.context/designs/canvas-fixture-smoke" ]
  # And nothing escaped the scratch root into its parent.
  [ ! -e "$WD/.context" ]
}

@test "T8: the modified-files temp file is cleaned up on both the pass and fail paths" {
  mk_adapter canvas_render
  run_e2e
  assert_success
  assert_equal "$(find "$TMPHOME" -name 'canvas-fixture-mods-*' | wc -l | tr -d ' ')" '0'

  mk_adapter                                  # now the failing path
  run_e2e
  assert_failure 1
  assert_equal "$(find "$TMPHOME" -name 'canvas-fixture-mods-*' | wc -l | tr -d ' ')" '0'
}

# ---------------------------------------------------------------------------
# T9 — characterisation, NOT an endorsement. run-e2e.sh has no argument
# parsing at all: every argv slot is silently discarded. Pinned so the day
# someone adds a usage guard, this test goes red and forces the decision to be
# explicit. Routed as a follow-up in .context/development-0.md.
# ---------------------------------------------------------------------------
@test "T9: run-e2e.sh currently ignores all arguments (no usage guard exists)" {
  mk_adapter canvas_render

  run_e2e --not-a-real-flag extra-positional

  assert_success
  refute_output --partial 'usage'
  refute_output --partial 'unknown'
}
