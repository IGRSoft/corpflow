#!/usr/bin/env bats
# Guard tests for benchmark/run-benchmark.sh.
#
# This script is the last barrier before PAID live LLM dispatch. T1-T13 exercise
# a refusal path only: a guard that fires (exit 64), --help, or the swift
# pre-flight, and each pins that no workdir, record or history byte was written.
#
# T14+ are a second class, added with the arm split: they exercise what the
# script does AFTER a dispatch returns, which no refusal path can reach. They run
# a COPY of the script inside a throwaway tree (see mk_bench_sandbox) whose
# bench-live is a fake record writer, so the real bench-live, bench-deterministic
# and swift build are still never reached and nothing dispatches or spends. Every
# one of them also asserts the real benchmark tree is untouched.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="benchmark/run-benchmark.sh"

setup() {
  WORKDIRS="$PLUGIN_ROOT/benchmark/workdirs"
  RESULTS="$PLUGIN_ROOT/benchmark/results"
  BEFORE_WORKDIRS="$(ls -1 "$WORKDIRS" 2> /dev/null | sort || true)"
  BEFORE_RESULTS="$(find "$RESULTS" -type f 2> /dev/null | sort || true)"
}

teardown() {
  _test_helper_cleanup
}

# Every refusal must leave the benchmark tree byte-untouched: a guard that fires
# after mkdir/rotation has already leaked state is not a guard.
assert_benchmark_tree_untouched() {
  assert_equal "$(ls -1 "$WORKDIRS" 2> /dev/null | sort || true)" "$BEFORE_WORKDIRS"
  assert_equal "$(find "$RESULTS" -type f 2> /dev/null | sort || true)" "$BEFORE_RESULTS"
}

# ---------------------------------------------------------------------------
# T1-T3 — the --live interlock. These flags only mean something on the paid
# path, so accepting them without --live would silently mislead the caller.
# ---------------------------------------------------------------------------
@test "T1: --stages without --live is refused with exit 64" {
  run_script_env --hide swift --separate-stderr "$SUT" --stages PL,AR,DV
  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --stages requires --live'
  assert_output ''
  assert_benchmark_tree_untouched
}

@test "T2: --without-arm without --live is refused with exit 64" {
  run_script_env --hide swift --separate-stderr "$SUT" --without-arm skip
  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --without-arm requires --live'
  assert_benchmark_tree_untouched
}

@test "T3: the =-joined spellings are held to the same interlock" {
  run_script_env --hide swift --separate-stderr "$SUT" --stages=PL
  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --stages requires --live'

  run_script_env --hide swift --separate-stderr "$SUT" --without-arm=real
  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --without-arm requires --live'
  assert_benchmark_tree_untouched
}

@test "T3b: --arm is held to the same interlock, both spellings" {
  run_script_env --hide swift --separate-stderr "$SUT" --arm with
  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --arm requires --live'

  run_script_env --hide swift --separate-stderr "$SUT" --arm=both
  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --arm requires --live'
  assert_benchmark_tree_untouched
}

# ---------------------------------------------------------------------------
# T4 — an unrecognised flag is never ignored. A typo'd guard flag that fell
# through to the default path would start a real run.
# ---------------------------------------------------------------------------
@test "T4: an unknown argument exits 64 and names the argument" {
  run_script_env --hide swift --separate-stderr "$SUT" --llive
  assert_failure 64
  assert_equal "$stderr" "run-benchmark.sh: unknown arg '--llive'"
  assert_benchmark_tree_untouched
}

@test "T5: an unknown argument after a valid one still refuses" {
  run_script_env --hide swift --separate-stderr "$SUT" --budget 10.00 --dry-run
  assert_failure 64
  assert_equal "$stderr" "run-benchmark.sh: unknown arg '--dry-run'"
  assert_benchmark_tree_untouched
}

# ---------------------------------------------------------------------------
# T6 — --help must answer before the toolchain probe, so it works on any host.
# ---------------------------------------------------------------------------
@test "T6: --help exits 0 ahead of the swift/python3 pre-flight" {
  run_script_env --hide swift --hide python3 --separate-stderr "$SUT" --help
  assert_success
  assert_output --partial 'dual-path TTT benchmark orchestrator'
  assert_output --partial 'benchmark/run-benchmark.sh --live'
  assert_equal "$stderr" ''
  assert_benchmark_tree_untouched
}

@test "T7: --help wins even when an invalid guard combination precedes it" {
  # --help is consumed inside the parse loop, before the interlock below it.
  run_script_env --hide swift "$SUT" --stages PL --help
  assert_success
  assert_output --partial 'dual-path TTT benchmark orchestrator'
}

# ---------------------------------------------------------------------------
# T8/T9 — the toolchain pre-flight runs before ANY filesystem mutation.
# ---------------------------------------------------------------------------
# fail() colourises; compare the message, not the escape sequences.
plain_stderr() {
  printf '%s' "$stderr" | sed $'s/\033\\[[0-9;]*m//g'
}

@test "T8: swift absent fails before a workdir or record is created" {
  run_script_env --hide swift --separate-stderr "$SUT"
  assert_failure 1
  assert_equal "$(plain_stderr)" '[benchmark] swift toolchain not found (required)'
  assert_output ''
  assert_benchmark_tree_untouched
}

@test "T9: python3 absent fails the same way, before any mutation" {
  # A resolvable swift so the probe below it is the one that fires — otherwise
  # the farm hides both and this test would silently re-run T8.
  stub_cmd swift --exit 0
  run_script_env --hide python3 --separate-stderr "$SUT"
  assert_failure 1
  assert_equal "$(plain_stderr)" '[benchmark] python3 not found (required — Python harness)'
  assert_benchmark_tree_untouched
}

# ---------------------------------------------------------------------------
# T10 — the guards sit ahead of the pre-flight, so a refusal is attributable to
# the guard and not to a missing toolchain.
# ---------------------------------------------------------------------------
@test "T10: --stages is refused with 64 even when the toolchain resolves" {
  # Both prerequisites resolve, so a removed guard would sail past the
  # pre-flight instead of failing on it — and the stubs mean that sailing past
  # still cannot start a Swift build or a harness dispatch.
  stub_cmd swift --exit 0
  stub_cmd python3 --exit 0

  run_script_env --stub-path --separate-stderr "$SUT" --stages DV

  assert_failure 64
  assert_equal "$stderr" 'run-benchmark.sh: --stages requires --live'
  # Not the pre-flight's exit 1 — the distinct code is what proves the ordering.
  refute_output --partial 'toolchain'
  assert_equal "$(stub_log --count swift)" '0'
  assert_equal "$(stub_log --count python3)" '0'
  assert_benchmark_tree_untouched
}

# ---------------------------------------------------------------------------
# T11-T13 — the --arm value itself. It picks a run id and a results directory,
# so an unvalidated value would reach a path; and a typo that fell through to
# bench-live would only be caught after the workdir already existed.
# ---------------------------------------------------------------------------
@test "T11: an --arm value outside the enum is refused with 64 and named" {
  stub_cmd swift --exit 0
  stub_cmd python3 --exit 0

  run_script_env --stub-path --separate-stderr "$SUT" --live --arm sideways

  assert_failure 64
  assert_equal "$stderr" \
    "run-benchmark.sh: --arm must be with, without or both (got 'sideways')"
  assert_equal "$(stub_log --count swift)" '0'
  assert_equal "$(stub_log --count python3)" '0'
  assert_benchmark_tree_untouched
}

@test "T12: a path-shaped --arm value cannot reach a directory name" {
  stub_cmd swift --exit 0
  stub_cmd python3 --exit 0

  run_script_env --stub-path --separate-stderr "$SUT" --live --arm=../../etc

  assert_failure 64
  assert_equal "$stderr" \
    "run-benchmark.sh: --arm must be with, without or both (got '../../etc')"
  assert_benchmark_tree_untouched
}

@test "T13: --arm with no value refuses instead of consuming the next flag" {
  run_script_env --hide swift --separate-stderr "$SUT" --live --arm
  assert_failure
  assert_output ''
  assert_benchmark_tree_untouched
}

# ---------------------------------------------------------------------------
# T14+ — post-dispatch behaviour, in a sandbox (see the file header).
#
# mk_bench_sandbox prints a throwaway benchmark tree: a copy of the SUT, a fake
# bench-live that writes a record instead of dispatching, a no-op bench-report,
# and a symlink to the REAL benchmarkkit so the rotation under test is the
# production code rather than a re-implementation of it.
#
# FAKE_SHAPE selects what the fake writes: auto (mirrors --arm), force_arm (an
# `arm` record from paired flags — the fail-closed case) or joined (a bench-pair
# style record). The template is a real stored record, so rotation sees a real
# shape.
# ---------------------------------------------------------------------------
mk_bench_sandbox() {
  local t
  t="$(mk_tmpworkdir)"
  mkdir -p "$t/benchmark/harness/bin" "$t/benchmark/results/runs/live" \
           "$t/benchmark/ttt-template"
  cp "$PLUGIN_ROOT/benchmark/run-benchmark.sh" "$t/benchmark/run-benchmark.sh"
  ln -s "$PLUGIN_ROOT/benchmark/harness/benchmarkkit" "$t/benchmark/harness/benchmarkkit"
  cp "$PLUGIN_ROOT/benchmark/results/history.json" "$t/benchmark/results/history.json"

  cat > "$t/benchmark/harness/bin/bench-live" <<'PYEOF'
import json, os, sys
argv = sys.argv[1:]
opts = {}
i = 0
while i < len(argv):
    opts[argv[i]] = argv[i + 1]
    i += 2
with open(os.environ["FAKE_TEMPLATE"]) as f:
    record = json.load(f)
record["run_id"] = opts["--workdir"]
record["mode"] = "live"
shape = os.environ.get("FAKE_SHAPE", "auto")
arm = opts.get("--arm")
if shape == "force_arm":
    record["arm"] = "with"
elif shape == "joined":
    record["joined_from"] = {"with": "a", "without": "b", "observed_gap_s": 12}
elif arm in ("with", "without"):
    record["arm"] = arm
with open(opts["--record"], "w") as f:
    json.dump(record, f, indent=2)
with open(os.environ["FAKE_ARGV_LOG"], "a") as f:
    f.write(" ".join(argv) + "\n")
PYEOF
  printf 'import sys\n' > "$t/benchmark/harness/bin/bench-report"

  : > "$t/argv.log"
  printf '%s\n' "$t"
}

# Freezes the clock so "the same second" is the condition under test, and keeps
# the untimed warm-up from needing a toolchain.
sandbox_stubs() {
  stub_cmd swift --exit 0
  stub_cmd date --stdout '20260101T000000Z'
}

run_sandbox() { # run_sandbox <sandbox> <shape> [args...]
  local t="$1" shape="$2"; shift 2
  local template
  template="$(find "$PLUGIN_ROOT/benchmark/results/runs/live" -name '*.json' \
                | LC_ALL=C sort | tail -1)"
  run_script_env --stub-path --separate-stderr \
    --env "FAKE_TEMPLATE=$template" \
    --env "FAKE_ARGV_LOG=$t/argv.log" \
    --env "FAKE_SHAPE=$shape" \
    "$t/benchmark/run-benchmark.sh" "$@"
}

hist_live_count() {
  python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("live",[])))' \
    "$1/benchmark/results/history.json"
}

hist_digest() { shasum -a 256 < "$1/benchmark/results/history.json"; }

# The sandbox is not a git checkout, so the SUT's sha falls back — resolved the
# same way here rather than hard-coded, so the assertions pin the run-id FORMAT
# and survive a BATS_TMPDIR that happens to sit inside a repository.
sandbox_sha() { git -C "$1" rev-parse --short=7 HEAD 2> /dev/null || echo "nogit"; }

@test "T14: a single-arm run lands in live-arm/ and never enters history" {
  local t; t="$(mk_bench_sandbox)"
  sandbox_stubs
  local before_digest; before_digest="$(hist_digest "$t")"
  local before_count; before_count="$(hist_live_count "$t")"
  local sha; sha="$(sandbox_sha "$t")"

  run_sandbox "$t" auto --live --arm with

  assert_success
  # An arm-suffixed id in its own directory: neither the analyzer's newest-in-
  # live/ fallback nor a reader of history can mistake it for a full run.
  assert_equal "$(ls "$t/benchmark/results/runs/live-arm")" \
    "live-20260101T000000Z-$sha-with.json"
  assert_equal "$(ls "$t/benchmark/results/runs/live")" ''
  assert_equal "$(hist_digest "$t")" "$before_digest"
  assert_equal "$(hist_live_count "$t")" "$before_count"
  assert_output --partial 'arm record kept out of history'
  assert_output --partial 'bench-pair'
  # The flag reached the seam verbatim.
  assert_equal "$(grep -c -- '--arm with$' "$t/argv.log")" '1'
  assert_benchmark_tree_untouched
}

@test "T15: two runs of the same arm in the same second do not collide" {
  local t; t="$(mk_bench_sandbox)"
  sandbox_stubs
  local sha; sha="$(sandbox_sha "$t")"

  run_sandbox "$t" auto --live --arm without
  assert_success
  run_sandbox "$t" auto --live --arm without
  assert_success

  # Same timestamp, same commit, same arm — only the uniquifier separates them.
  assert_equal "$(ls "$t/benchmark/results/runs/live-arm" | LC_ALL=C sort | tr '\n' ' ')" \
    "live-20260101T000000Z-$sha-without-2.json live-20260101T000000Z-$sha-without.json "
  assert_equal "$(ls "$t/benchmark/workdirs" | wc -l | tr -d ' ')" '2'
  assert_benchmark_tree_untouched
}

@test "T16: a paired run in the same sandbox DOES rotate" {
  # The control for T14: without it, a sandbox that simply never rotates would
  # make the guard look present when it is not.
  local t; t="$(mk_bench_sandbox)"
  sandbox_stubs
  local before_count; before_count="$(hist_live_count "$t")"
  local sha; sha="$(sandbox_sha "$t")"

  run_sandbox "$t" auto --live

  assert_success
  assert_equal "$(ls "$t/benchmark/results/runs/live-arm" 2>/dev/null)" ''
  assert_equal "$(ls "$t/benchmark/results/runs/live")" "live-20260101T000000Z-$sha.json"
  assert_equal "$(hist_live_count "$t")" "$((before_count + 1))"
  assert_output --partial 'live record rotated into history'
  assert_benchmark_tree_untouched
}

@test "T17: paired flags cannot rotate a record that carries an arm" {
  # Fail-closed: the second guard keys on the record, so a future caller that
  # points --record at an arm record still cannot get it into history.
  local t; t="$(mk_bench_sandbox)"
  sandbox_stubs
  local before_digest; before_digest="$(hist_digest "$t")"

  run_sandbox "$t" force_arm --live --arm both

  assert_success
  assert_equal "$(hist_digest "$t")" "$before_digest"
  assert_output --partial 'carries an arm discriminator'
  refute_output --partial 'rotated into history'
  assert_benchmark_tree_untouched
}

@test "T18: a joined record rotates exactly as a paired record does" {
  local t; t="$(mk_bench_sandbox)"
  sandbox_stubs
  local before_count; before_count="$(hist_live_count "$t")"

  run_sandbox "$t" joined --live

  assert_success
  assert_equal "$(hist_live_count "$t")" "$((before_count + 1))"
  assert_output --partial 'live record rotated into history'
  # joined_from survives the rotation, so the join stays auditable from history.
  assert_equal "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["live"][-1]["joined_from"]["observed_gap_s"])' \
    "$t/benchmark/results/history.json")" '12'
  assert_benchmark_tree_untouched
}

@test "T19: --arm both keeps the legacy identity and the legacy directory" {
  local t; t="$(mk_bench_sandbox)"
  sandbox_stubs
  local sha; sha="$(sandbox_sha "$t")"

  run_sandbox "$t" auto --live --arm both

  assert_success
  assert_equal "$(ls "$t/benchmark/results/runs/live")" "live-20260101T000000Z-$sha.json"
  assert_equal "$(ls "$t/benchmark/results/runs/live-arm" 2>/dev/null)" ''
  assert_equal "$(grep -c -- '--arm both$' "$t/argv.log")" '1'
  assert_benchmark_tree_untouched
}
