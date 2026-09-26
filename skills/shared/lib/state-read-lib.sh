#!/usr/bin/env bash
# @description state-read-lib.sh — the read side of .context/state.json, including the two
#   fields every worktask script needs before it can name anything (worktask_id, run_index).
#
#   The default is an explicit argument. A caller that probes for absence rather than
#   reading a value passes "" at the call site, where a reader can see it; a shared
#   non-empty default would make every probe look present.
#
#   Symbols: corpflow_state_str, corpflow_worktask_id, corpflow_run_index,
#   corpflow_context_dir.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — must be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'state-read-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_STATE_READ_LIB:-}" ] && return 0
_CORPFLOW_STATE_READ_LIB=1

# Not `readonly`: consumer bats suites source this file twice per process, and a second
# readonly assignment is rc 1, which kills a `set -e` caller.

# corpflow_state_str <state-file> <jq-path> [default]
#
# Prints the scalar at <jq-path>, or <default> (empty when omitted) when the file is
# absent, unreadable, not JSON, or the path is null. Always rc 0: every caller of this
# read is naming a branch, a log file or an audit subject, and none of them wants a
# missing ledger to abort a `set -e` shell from inside a field read.
#
# jq's own `//` handles null-or-false; the `||` handles jq itself failing (absent binary,
# unparseable file). Both are needed — neither covers the other's case.
corpflow_state_str() {
  local file="${1:-}" path="${2:-}" default="${3:-}" out
  [ -n "$path" ] || return 0
  if [ -r "$file" ] && command -v jq > /dev/null 2>&1; then
    out=$(jq -r --arg d "$default" "$path // \$d" "$file" 2> /dev/null) || out="$default"
  else
    out="$default"
  fi
  # A literal JSON null reaching -r prints "null"; no caller wants that as an id.
  [ "$out" = "null" ] && out="$default"
  printf '%s' "$out"
}

# The worktask id, defaulting to "unknown". Pass "" for the absence-probe semantics.
corpflow_worktask_id() {
  corpflow_state_str "${1:-}" '.worktask_id' "${2-unknown}"
}

# The run index, defaulting to 0 — the value every path-building caller assumes when the
# ledger has not recorded one. Pass "" to tell absent from zero.
corpflow_run_index() {
  corpflow_state_str "${1:-}" '.run_index' "${2-0}"
}

# corpflow_context_dir — ranks 2-6 of the root-resolution ladder (rank 1, --state, is a
# caller-side concern this library never sees). Prints the absolute .context directory
# and returns 0 on the first rank that matches; nothing is printed otherwise.
#
#   2  $CONTEXT_DIR, if it names a directory
#   3  $WORKSPACE_ROOT/.context, if it exists
#   4  $CLAUDE_PROJECT_DIR/.context, if it exists
#   5  $(git rev-parse --show-toplevel)/.context/state.json, if that FILE exists —
#      subdirectory-invariant and never creates a ledger, which is what makes it safe to
#      try before falling back to the resolver
#   6  `resolve-root.sh`'s stdout, if that directory exists
#
# Returns 1 when every rank misses (the caller decides what "unresolved" means — for a
# writer that is usually "skip the write", never "fall back to cwd"). Returns 2 only when
# resolve-root.sh itself cannot be reached — a broken install, not an unresolved ladder —
# so a caller can tell "no root here" apart from "the plugin install is broken".
corpflow_context_dir() {
  if [ -n "${CONTEXT_DIR:-}" ] && [ -d "${CONTEXT_DIR}" ]; then
    printf '%s' "$CONTEXT_DIR"
    return 0
  fi
  if [ -n "${WORKSPACE_ROOT:-}" ] && [ -d "${WORKSPACE_ROOT}/.context" ]; then
    printf '%s' "${WORKSPACE_ROOT}/.context"
    return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}/.context" ]; then
    printf '%s' "${CLAUDE_PROJECT_DIR}/.context"
    return 0
  fi

  local top=""
  top=$(git rev-parse --show-toplevel 2> /dev/null || true)
  if [ -n "$top" ] && [ -f "$top/.context/state.json" ]; then
    printf '%s' "$top/.context"
    return 0
  fi

  local libdir resolver out
  libdir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd -P)"
  [ -n "$libdir" ] || return 2
  resolver="$libdir/../scripts/resolve-root.sh"
  [ -r "$resolver" ] || return 2

  out=$(bash "$resolver" 2> /dev/null || true)
  if [ -n "$out" ] && [ -d "$out" ]; then
    printf '%s' "$out"
    return 0
  fi
  return 1
}
