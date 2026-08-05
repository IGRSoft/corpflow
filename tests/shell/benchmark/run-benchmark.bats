#!/usr/bin/env bats
# Guard tests for benchmark/run-benchmark.sh.
#
# This script is the last barrier before PAID live LLM dispatch, so every test
# here exercises a refusal path only: a guard that fires (exit 64), --help, or
# the swift pre-flight. No test may take a path that reaches `bench-live`,
# `bench-deterministic` or a `swift build` — the assertions below therefore
# also pin that no workdir, record or history byte was written.
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
