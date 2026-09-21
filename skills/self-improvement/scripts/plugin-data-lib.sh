#!/usr/bin/env bash
# @file        plugin-data-lib.sh
# @description Sourced library: resolves the self-improvement label dataset path.
#              Precedence (skills/self-improvement/SKILL.md § Where the dataset lives):
#                1. --dataset as given                              -> explicit
#                2. --plugin-data dir: non-empty, "$"-free, absolute -> plugin-data
#                3. CLAUDE_PLUGIN_DATA value passed in, same checks  -> env
#                4. ${CLAUDE_PROJECT_DIR:-.}/evals/<basename>        -> fallback
#              Rungs 2-3 resolve to <dir>/self-improvement/<basename>, created with
#              (umask 077; mkdir -p) so the dir is never briefly laxer than 0700.
#
# @usage       si_resolve_dataset "$DATASET" "$PLUGIN_DATA" "${CLAUDE_PLUGIN_DATA:-}" failure-labels.jsonl
# @output      Globals SI_DATASET_PATH and SI_DATASET_SOURCE; stdout stays free
#              because callers use it as their data channel.
# @return      0 resolved; 1 relative --plugin-data or mkdir failure. An invalid
#              env value is never an error: it is absent from the Bash tool env by
#              design, so it falls through to the fallback rung.
# @requires    bash >=3.2

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'plugin-data-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

[ -n "${_SI_PLUGIN_DATA_LIB:-}" ] && return 0
_SI_PLUGIN_DATA_LIB=1

# 0 absolute, 1 unset, 2 relative. A "$" means the placeholder was never substituted.
_si_dir_valid() {
  case "$1" in
    '') return 1 ;;
    *'$'*) return 1 ;;
    /*) return 0 ;;
    *) return 2 ;;
  esac
}

_si_dataset_dir() {
  local dir="${1%/}/self-improvement" basename="$2"
  (umask 077 && mkdir -p -- "$dir") || return 1
  printf '%s\n' "$dir/$basename"
}

si_resolve_dataset() {
  local dataset="$1" plugin_data="$2" env_value="$3" basename="$4"
  local rc resolved

  SI_DATASET_PATH=""
  SI_DATASET_SOURCE=""

  if [ -n "$dataset" ]; then
    SI_DATASET_PATH="$dataset"
    SI_DATASET_SOURCE="explicit"
    return 0
  fi

  rc=0
  _si_dir_valid "$plugin_data" || rc=$?
  if [ "$rc" -eq 0 ]; then
    resolved="$(_si_dataset_dir "$plugin_data" "$basename")" || {
      printf >&2 'plugin-data-lib: could not create %s/self-improvement\n' "${plugin_data%/}"
      return 1
    }
    SI_DATASET_PATH="$resolved"
    SI_DATASET_SOURCE="plugin-data"
    return 0
  elif [ "$rc" -eq 2 ]; then
    printf >&2 'plugin-data-lib: --plugin-data must be an absolute path, got: %s\n' "$plugin_data"
    return 1
  fi

  rc=0
  _si_dir_valid "$env_value" || rc=$?
  if [ "$rc" -eq 0 ]; then
    resolved="$(_si_dataset_dir "$env_value" "$basename")" || {
      printf >&2 'plugin-data-lib: could not create %s/self-improvement\n' "${env_value%/}"
      return 1
    }
    SI_DATASET_PATH="$resolved"
    SI_DATASET_SOURCE="env"
    return 0
  fi

  SI_DATASET_PATH="${CLAUDE_PROJECT_DIR:-.}/evals/$basename"
  # shellcheck disable=SC2034 # read by the sourcing caller
  SI_DATASET_SOURCE="fallback"
  printf >&2 'self-improvement: plugin data dir unavailable; using fallback dataset %s\n' \
    "$SI_DATASET_PATH"
  return 0
}
