#!/usr/bin/env bash
# @description state-read-lib.sh — the read side of .context/state.json, including the two
#   fields every worktask script needs before it can name anything (worktask_id, run_index).
#
#   The default is an explicit argument. A caller that probes for absence rather than
#   reading a value passes "" at the call site, where a reader can see it; a shared
#   non-empty default would make every probe look present.
#
#   Symbols: corpflow_state_str, corpflow_worktask_id, corpflow_run_index,
#   corpflow_inferred_ctx_ok, corpflow_context_dir, corpflow_context_dir_write.
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

# corpflow_inferred_ctx_ok <ctx-dir> [<git-toplevel>] — the one rule for readers and for
# state-patch.sh's writer refusal (exit 4): rc 0 when a ledger dir INFERRED from the cwd (ranks 5-6) may be used,
# rc 1 (nothing printed) when it lies inside a plugin root and the caller is not at its own git
# toplevel. A cwd nested in the plugin's checkout otherwise borrows that checkout's live ledger.
# A linked worktree's toplevel still reaches the main ledger (the self-hosted pipeline path).
#
# Plugin roots: this library's own tree, and the first host root `corpflow_plugin_root` reports
# (read in a fresh process from corpflow-base.sh).
# The optional toplevel reuses a probe the caller already paid for. Explicit ranks never call
# this; reader/writer parity is pinned by reader-ladder-nested.bats.
corpflow_inferred_ctx_ok() {
  local ctx="${1:-}" top="${2:-}" ctx_p top_p="" pwd_p libdir root root_p
  [ -n "$ctx" ] || return 1
  # A ctx that does not exist yet (first --task-create, first mailbox call) is judged by its
  # deepest existing ancestor with the missing tail re-appended; a symlinked tmp root (macOS
  # /var -> /private/var) would otherwise defeat the prefix comparison.
  local head="$ctx" tail="" base
  case "$head" in /*) ;; *) head="$PWD/$head" ;; esac
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    base="${head##*/}"
    tail="/${base}${tail}"
    head="${head%/*}"
  done
  [ -n "$head" ] || head="/"
  head=$(CDPATH='' cd -P -- "$head" 2> /dev/null && pwd -P) || return 1
  ctx_p="${head%/}${tail}"
  [ -n "$ctx_p" ] || return 1
  [ -n "$top" ] || top=$(git rev-parse --show-toplevel 2> /dev/null || true)
  if [ -n "$top" ]; then
    top_p=$(CDPATH='' cd -P -- "$top" 2> /dev/null && pwd -P) || top_p=""
  fi
  pwd_p=$(pwd -P 2> /dev/null || true)
  libdir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd -P)" || libdir=""

  # The host-root env ladder lives in corpflow-base.sh. A fresh process reads it with the
  # writer's own resolver and cannot collide with a hook's `readonly -f corpflow_workspace_root`.
  local host_root=""
  if [ -n "$libdir" ] && [ -r "$libdir/corpflow-base.sh" ]; then
    host_root=$(bash -c '. "$1" && corpflow_plugin_root' _ "$libdir/corpflow-base.sh" 2> /dev/null || true)
  fi

  for root in "${libdir:+$libdir/../../..}" "$host_root"; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    root_p=$(CDPATH='' cd -P -- "$root" 2> /dev/null && pwd -P) || continue
    [ -n "$root_p" ] && [ "$root_p" != "/" ] || continue
    case "$ctx_p/" in
      "$root_p/"*)
        [ -n "$top_p" ] && [ "$pwd_p" = "$top_p" ] && continue
        return 1
        ;;
    esac
  done
  return 0
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
# Ranks 5 and 6 are inferred from the cwd and pass corpflow_inferred_ctx_ok; a refusal ends the
# ladder (rc 1, nothing printed) rather than falling through to the next rank, which would swap
# one tree's ledger for another's. Ranks 2-4 are explicit and stay trusted.
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
    corpflow_inferred_ctx_ok "$top/.context" "$top" || return 1
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
    corpflow_inferred_ctx_ok "$out" "$top" || return 1
    printf '%s' "$out"
    return 0
  fi
  return 1
}

# corpflow_context_dir_write — the ladder for a WRITER that must land a ledger even where no
# ledger exists yet (a first --task-create in a fresh workdir). Prints the .context
# directory; always rc 0, because the last rank is unconditional.
#
#   1  $CONTEXT_DIR, verbatim
#   2  $WORKSPACE_ROOT/.context
#   3  $CLAUDE_PROJECT_DIR/.context
#   4  $(git -C "$PWD" rev-parse --show-toplevel)/.context
#   5  $PWD/.context
#
# Ranks 2 and 3 are honoured whenever the variable is set, not only when the directory
# already exists: the reader ladder above skips a declared root that has no .context yet,
# which for a writer would silently retarget the write at a lower rank.
#
# There is deliberately no resolve-root.sh rank and nothing derived from this file's own
# location. The main-worktree recovery answers "which ledger owns this git tree", so a
# workdir nested inside some other checkout (a benchmark arm under the plugin's own repo)
# was handed that checkout's live ledger. A writer must resolve from the caller's tree.
# Whether the answer is an acceptable place to write is the caller's call; this function
# only names it.
corpflow_context_dir_write() {
  if [ -n "${CONTEXT_DIR:-}" ]; then
    printf '%s' "$CONTEXT_DIR"
    return 0
  fi
  if [ -n "${WORKSPACE_ROOT:-}" ]; then
    printf '%s' "${WORKSPACE_ROOT}/.context"
    return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "${CLAUDE_PROJECT_DIR}/.context"
    return 0
  fi
  local top=""
  top=$(git -C "$PWD" rev-parse --show-toplevel 2> /dev/null || true)
  if [ -n "$top" ]; then
    printf '%s' "$top/.context"
    return 0
  fi
  printf '%s' "$PWD/.context"
  return 0
}
