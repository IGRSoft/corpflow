#!/usr/bin/env bats
# host-os-lib.sh — the one host-operating-system probe callers may branch on
# (architecture-0.md AD-1). Contract under test: host_os() echoes exactly one of the
# closed vocabulary macos|linux|bsd|windows|unknown, never empty; CORPFLOW_HOST_OS is a
# test/operator seam that wins over uname when it carries a vocabulary value and is
# ignored (never trusted verbatim) otherwise; the result is memoised per process; the
# anti-execution guard fires when the file is run directly; the include guard is
# set -e-safe under a double source.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/host-os-lib.sh"

# --- vocabulary: CORPFLOW_HOST_OS as the test seam ---------------------------

@test "CORPFLOW_HOST_OS=macos wins over uname" {
  run env CORPFLOW_HOST_OS=macos bash -c '. "$1"; host_os' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  assert_output "macos"
}

@test "CORPFLOW_HOST_OS=linux wins over uname" {
  run env CORPFLOW_HOST_OS=linux bash -c '. "$1"; host_os' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  assert_output "linux"
}

@test "CORPFLOW_HOST_OS=bsd and =windows are accepted, exercising every vocabulary arm" {
  run env CORPFLOW_HOST_OS=bsd bash -c '. "$1"; host_os' _ "$PLUGIN_ROOT/$LIB"
  assert_output "bsd"
  run env CORPFLOW_HOST_OS=windows bash -c '. "$1"; host_os' _ "$PLUGIN_ROOT/$LIB"
  assert_output "windows"
}

@test "an out-of-vocabulary CORPFLOW_HOST_OS is ignored, not trusted verbatim" {
  # A typo must not smuggle a 6th value past every caller's `case`; the real uname
  # result on this runner (whatever it is) must win instead.
  run env CORPFLOW_HOST_OS=Darwin bash -c '. "$1"; host_os' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  refute_output "Darwin"
  case "$output" in
    macos | linux | bsd | windows | unknown) ;;
    *) fail "out-of-vocabulary override leaked through as '$output'" ;;
  esac
}

@test "an unrecognised uname result falls back to the documented unknown, never empty" {
  run env CORPFLOW_HOST_OS="" bash -c '
    uname() { echo "PlanNine"; }
    . "$1"
    host_os
  ' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  assert_output "unknown"
}

@test "host_os never prints empty even when uname itself is unavailable" {
  run env CORPFLOW_HOST_OS="" bash -c '
    uname() { return 127; }
    . "$1"
    host_os
  ' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  [ -n "$output" ] || fail "host_os printed nothing"
  assert_output "unknown"
}

# --- memoisation --------------------------------------------------------------
#
# Memoisation lives in `_HOST_OS_CACHE`, a plain shell variable — it can only be
# observed across two DIRECT invocations of `host_os` in the same shell frame, never
# across `$(host_os)` command substitutions (each one forks a subshell, so the
# assignment made inside it never reaches the caller). These tests redirect stdout
# with `>` instead, which does not fork, to actually exercise the cache rather than
# just proving `host_os` is deterministic.

@test "the result is memoised: a later CORPFLOW_HOST_OS change does not affect the cached value" {
  run env CORPFLOW_HOST_OS=linux bash -c '
    . "$1"
    host_os > "$2/first"
    export CORPFLOW_HOST_OS=macos
    host_os > "$2/second"
    cat "$2/first" "$2/second"
  ' _ "$PLUGIN_ROOT/$LIB" "$BATS_TEST_TMPDIR"
  assert_success
  assert_output "linux
linux"
}

@test "_HOST_OS_CACHE holds the memoised value directly after the first direct call" {
  run env CORPFLOW_HOST_OS=bsd bash -c '
    . "$1"
    host_os > /dev/null
    printf "%s\n" "$_HOST_OS_CACHE"
  ' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  assert_output "bsd"
}

# --- predicates ----------------------------------------------------------------

@test "host_is_macos and host_is_linux agree with host_os and are mutually exclusive" {
  run env CORPFLOW_HOST_OS=macos bash -c '
    . "$1"
    host_is_macos && echo "macos:yes"
    host_is_linux || echo "linux:no"
  ' _ "$PLUGIN_ROOT/$LIB"
  assert_line "macos:yes"
  assert_line "linux:no"

  run env CORPFLOW_HOST_OS=linux bash -c '
    . "$1"
    host_is_linux && echo "linux:yes"
    host_is_macos || echo "macos:no"
  ' _ "$PLUGIN_ROOT/$LIB"
  assert_line "linux:yes"
  assert_line "macos:no"
}

@test "host_is_macos/host_is_linux print nothing — rc only, no stdout" {
  run env CORPFLOW_HOST_OS=bsd bash -c '. "$1"; host_is_macos; echo "rc=$?"' _ "$PLUGIN_ROOT/$LIB"
  assert_output "rc=1"
}

# --- anti-execution guard -------------------------------------------------------

@test "executing the file directly refuses with exit 2 and a stderr message" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
  assert_output --partial "source it, do not execute it directly"
}

# --- include guard: set -e safety under a double source -------------------------

@test "sourcing the lib twice under set -e does not abort (include guard is not readonly)" {
  run env CORPFLOW_HOST_OS=macos bash -c '
    set -euo pipefail
    . "$1"
    . "$1"
    host_os
  ' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  assert_output "macos"
}
