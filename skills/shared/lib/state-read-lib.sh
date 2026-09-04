#!/usr/bin/env bash
# @description state-read-lib.sh — the read side of .context/state.json. The two fields every
#   worktask script needs before it can name anything (worktask_id, run_index) were spelled
#   out in an inline `jq -r … // <default>` at 31 sites, and the SAME field carried three
#   different defaults across them.
#
#   The library does NOT unify those defaults. It makes the default an explicit argument
#   with the majority spelling as its value, so a caller that wants "" or empty — because it
#   probes for absence rather than reading a value — has to say so at the call site where a
#   reader can see it. Collapsing the three into one would have silently changed the two
#   probes into readers that always look present.
#
#   Symbols: corpflow_state_str, corpflow_worktask_id, corpflow_run_index.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — MUST be the first statement.
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

# The worktask id, defaulting to the spelling 25 of the 31 inline sites used. Pass "" for
# the absence-probe semantics.
corpflow_worktask_id() {
  corpflow_state_str "${1:-}" '.worktask_id' "${2-unknown}"
}

# The run index, defaulting to 0 — the value every path-building caller assumes when the
# ledger has not recorded one. Pass "" to tell absent from zero.
corpflow_run_index() {
  corpflow_state_str "${1:-}" '.run_index' "${2-0}"
}
