#!/usr/bin/env bash
# @description host-os-lib.sh — the one host-operating-system probe every script in this
#   plugin may branch on; no caller may call `uname` itself (portability-lint.sh P007).
#
#   `host_os` echoes exactly one of a closed vocabulary, never empty, so a caller's `case`
#   always has a real arm to land on — including the unrecognised-host default arm.
#   Memoised per process; `CORPFLOW_HOST_OS` overrides `uname` for tests and operators.
#
#   Sources nothing, sets no shell options, does no work at load beyond idempotent
#   variable init.
#
#   Symbols: host_os, host_is_macos, host_is_linux.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'host-os-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_HOST_OS_LIB:-}" ] && return 0
_CORPFLOW_HOST_OS_LIB=1

# Not `readonly`: consumer bats suites source this file more than once per process, and a
# second `readonly` assignment is rc 1 that kills a `set -e` caller (branch-lib.sh's BRANCH_TYPES note documents
# the same defect class).
_HOST_OS_CACHE=""

# host_os -> one of macos|linux|bsd|windows|unknown on stdout, rc always 0.
#
# CORPFLOW_HOST_OS, when set to a vocabulary value, wins over `uname` — the test seam and
# operator escape hatch. An out-of-vocabulary override is ignored, never trusted verbatim,
# so a typo cannot smuggle a sixth value past every caller's `case`.
host_os() {
  if [ -n "$_HOST_OS_CACHE" ]; then
    printf '%s\n' "$_HOST_OS_CACHE"
    return 0
  fi

  local _override="${CORPFLOW_HOST_OS:-}"
  case "$_override" in
    macos | linux | bsd | windows | unknown)
      _HOST_OS_CACHE="$_override"
      printf '%s\n' "$_HOST_OS_CACHE"
      return 0
      ;;
  esac

  local _uname
  _uname=$(uname -s 2> /dev/null) || _uname=""
  case "$_uname" in
    Darwin) _HOST_OS_CACHE=macos ;;
    Linux) _HOST_OS_CACHE=linux ;;
    FreeBSD | OpenBSD | NetBSD | DragonFly) _HOST_OS_CACHE=bsd ;;
    CYGWIN* | MINGW* | MSYS*) _HOST_OS_CACHE=windows ;;
    *) _HOST_OS_CACHE=unknown ;;
  esac
  printf '%s\n' "$_HOST_OS_CACHE"
}

# host_is_macos / host_is_linux -> rc 0/1, no output. Convenience predicates for the two
# hosts this plugin actually runs and tests on; every other branch reads `host_os` directly.
host_is_macos() {
  [ "$(host_os)" = macos ]
}

host_is_linux() {
  [ "$(host_os)" = linux ]
}
