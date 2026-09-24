#!/usr/bin/env bash
# @description corpflow-base.sh — the path-resolution primitives a script needs before it
#   can reach anything else: its own physical directory, and the plugin root.
#
#   Mirrored, not shared: skills/shared/lib/corpflow-base.sh and hooks/lib/corpflow-base.sh
#   are byte-identical, pinned by tests/shell/skills/corpflow-base.bats. A hook cannot
#   reach skills/shared/lib/ without first resolving a plugin root, which this file
#   supplies. Edit one, edit both.
#
#   Symbols: corpflow_script_dir, corpflow_plugin_root.
#
# Minimum shell: bash 3.2+ (macOS default).

# Anti-execution guard — must be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'corpflow-base.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_BASE_LIB:-}" ] && return 0
_CORPFLOW_BASE_LIB=1

# Not `readonly`: consumer bats suites source this file twice per process, and a second
# readonly assignment is rc 1, which kills a `set -e` caller.

# Bounds the upward walk in corpflow_plugin_root. Both mirrors sit two or three levels
# under the root; the slack absorbs a deeper future home without an unbounded walk.
_CORPFLOW_ROOT_MAX_DEPTH=6

# Physical directory of <file> (default "$0"); rc 1 when unresolvable.
#
# CDPATH='' suppresses the extra line a set CDPATH makes `cd` echo into this capture. The
# readlink loop plus `pwd -P` follow a symlinked script to its real directory, so sibling
# resolution cannot be redirected onto a file planted next to the symlink. Callers pass
# their own "${BASH_SOURCE[0]:-$0}" — here BASH_SOURCE[0] is this library.
corpflow_script_dir() {
  local src="${1:-$0}" dir
  while [ -h "$src" ]; do
    dir=$(CDPATH='' cd -- "$(dirname -- "$src")" && pwd -P) || return 1
    src=$(readlink "$src")
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  CDPATH='' cd -- "$(dirname -- "$src")" && pwd -P
}

# Plugin root on stdout, rc 1 when unresolved. Candidates are tried in order and accepted
# only when they hold the .claude-plugin/plugin.json marker; empty ones are skipped so a
# caller may pass an unset variable positionally.
#
# The plugin-root environment variable is deliberately unnamed here: an exact-match allowlist
# (tests/shell/skills/plugin-root-refs.bats) pins which files may read it, and a library
# sourced by everything cannot be on that list. Callers honouring it pass it as a candidate,
# keeping that rung and its failure policy where the allowlist can see them.
#
# The fallback walks up from this file's directory, not the caller's: a library's depth below
# the root is fixed, a caller's is not.
# Callable with no candidates at all: bash gives a bare call an empty "$@", so the loop
# simply falls through to the self-location walk.
# shellcheck disable=SC2120
corpflow_plugin_root() {
  local candidate dir depth=0
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/.claude-plugin/plugin.json" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  dir=$(corpflow_script_dir "${BASH_SOURCE[0]}") || return 1
  while [ "$depth" -le "$_CORPFLOW_ROOT_MAX_DEPTH" ]; do
    if [ -f "$dir/.claude-plugin/plugin.json" ]; then
      printf '%s' "$dir"
      return 0
    fi
    [ "$dir" = "/" ] && break
    dir=$(dirname "$dir")
    depth=$((depth + 1))
  done
  return 1
}
