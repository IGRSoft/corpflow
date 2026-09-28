#!/usr/bin/env bash
# @description corpflow-base.sh — the path-resolution primitives a script needs before it
#   can reach anything else: its own physical directory, and the plugin root.
#
#   Mirrored, not shared: skills/shared/lib/corpflow-base.sh and hooks/lib/corpflow-base.sh
#   are byte-identical, pinned by tests/shell/skills/corpflow-base.bats. A hook cannot
#   reach skills/shared/lib/ without first resolving a plugin root, which this file
#   supplies. Edit one, edit both.
#
#   Symbols: corpflow_script_dir, corpflow_plugin_root, corpflow_init_base_paths,
#   corpflow_plugin_path, corpflow_workspace_root.
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

# True when a directory is a Corpflow plugin root in any supported package layout.
corpflow_is_plugin_root() {
  local candidate="${1:-}"
  [ -n "$candidate" ] && [ -d "$candidate" ] || return 1
  [ -f "$candidate/plugin.json" ] \
    || [ -f "$candidate/.codex-plugin/plugin.json" ] \
    || [ -f "$candidate/.claude-plugin/plugin.json" ]
}

# Plugin root on stdout, rc 1 when unresolved. Explicit candidates are tried in order. With
# no arguments, the host-neutral value wins, followed by Codex's documented PLUGIN_ROOT and
# Claude Code's CLAUDE_PLUGIN_ROOT compatibility input.
#
# The fallback walks up from this file's directory, not the caller's: a library's depth below
# the root is fixed, a caller's is not.
# Callable with no candidates at all: bash gives a bare call an empty "$@", so the loop
# simply falls through to the self-location walk.
# shellcheck disable=SC2120
corpflow_plugin_root() {
  local candidate dir depth=0
  if [ "$#" -eq 0 ]; then
    set -- "${BASE_PLUGIN_ROOT:-}" "${PLUGIN_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}"
  fi
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    if corpflow_is_plugin_root "$candidate"; then
      # pwd -L makes a relative candidate absolute while preserving the spelling of a
      # symlinked installation. Consumers get an absolute root without being silently moved
      # from a host-owned install link to its cache target.
      dir=$(CDPATH='' cd -- "$candidate" && pwd -L) || continue
      corpflow_is_plugin_root "$dir" || continue
      printf '%s' "$dir"
      return 0
    fi
  done
  dir=$(corpflow_script_dir "${BASH_SOURCE[0]}") || return 1
  while [ "$depth" -le "$_CORPFLOW_ROOT_MAX_DEPTH" ]; do
    if corpflow_is_plugin_root "$dir"; then
      printf '%s' "$dir"
      return 0
    fi
    [ "$dir" = "/" ] && break
    dir=$(dirname "$dir")
    depth=$((depth + 1))
  done
  return 1
}

# Workspace root on stdout, rc 1 when unresolved. WORKSPACE_ROOT is already provider-neutral;
# payload cwd is the second rung, followed by Claude Code's legacy project directory and a
# validated git toplevel. Every accepted value is physical and absolute.
corpflow_workspace_root() {
  local payload_cwd="${1:-}" candidate root
  for candidate in "${WORKSPACE_ROOT:-}" "$payload_cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    [ -n "$candidate" ] || continue
    if [ -d "$candidate" ]; then
      root=$(CDPATH='' cd -- "$candidate" && pwd -P) || continue
      printf '%s' "$root"
      return 0
    fi
    # Host-provided workspace paths may name a not-yet-created checkout. Preserve that
    # legacy contract when the value is already absolute; Git discovery below remains
    # restricted to a real, validated repository root.
    case "$candidate" in
      /*) printf '%s' "${candidate%/}"; return 0 ;;
    esac
  done
  command -v git >/dev/null 2>&1 || return 1
  root=$(git -C "${payload_cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -d "$root" ] || return 1
  CDPATH='' cd -- "$root" && pwd -P
}

# Resolve and export the canonical provider-neutral paths used by shared Corpflow code.
# BASE_PLUGIN_DATA is optional because source checkouts and non-hook invocations have no
# host-owned writable plugin-data directory.
corpflow_init_base_paths() {
  local payload_cwd="${1:-}" root workspace
  root=$(corpflow_plugin_root) || return 1
  BASE_PLUGIN_ROOT="$root"
  export BASE_PLUGIN_ROOT

  BASE_PLUGIN_DATA="${BASE_PLUGIN_DATA:-${PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-}}}"
  if [ -n "$BASE_PLUGIN_DATA" ]; then
    export BASE_PLUGIN_DATA
  fi

  workspace=$(corpflow_workspace_root "$payload_cwd" 2>/dev/null) || workspace=""
  if [ -n "$workspace" ]; then
    WORKSPACE_ROOT="$workspace"
    export WORKSPACE_ROOT
  fi
  return 0
}

# Print an absolute path below BASE_PLUGIN_ROOT. The lexical guard deliberately rejects
# traversal before joining; callers that need a real existing path may apply -e/-f afterwards.
corpflow_plugin_path() {
  local relative="${1:-}"
  [ -n "$relative" ] || return 2
  case "$relative" in
    /* | .. | ../* | */../* | */..) return 2 ;;
  esac
  [ -n "${BASE_PLUGIN_ROOT:-}" ] || corpflow_init_base_paths || return 1
  printf '%s/%s' "${BASE_PLUGIN_ROOT%/}" "${relative#./}"
}
