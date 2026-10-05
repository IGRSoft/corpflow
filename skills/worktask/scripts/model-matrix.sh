#!/usr/bin/env bash
# @description model-matrix.sh — CLI wrapper over model-matrix-lib.sh for callers that
#   cannot source bash (PL0's `--resolve <agent>` paste step, the benchmark's Python suite).
#   state-patch.sh sources the library directly; this file exists solely for that one class
#   of caller.
#
#   Path defaults: `--resolve` and `--resolved-json` take optional [state_path]
#   [corpflow_md_path]. When omitted they are derived from the same root ladder
#   state-patch.sh uses (`corpflow_context_dir`: CONTEXT_DIR, WORKSPACE_ROOT,
#   CLAUDE_PROJECT_DIR, git toplevel, resolve-root.sh) — state.json inside it, CORPFLOW.md
#   beside it. Without this the documented bare `--resolve <agent>` call read only the
#   built-in matrix, so a `state.models`/`CORPFLOW.md § Models` override never reached the
#   pair PL0 pastes into `--task-create`. An unresolvable root degrades to matrix-only.
#
# @exitcode 2 usage error
# @exitcode 3 model_matrix_rows extraction failure (see model-matrix-lib.sh)

set -euo pipefail

_MM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=model-matrix-lib.sh
. "${_MM_DIR}/model-matrix-lib.sh"

usage() {
  cat >&2 << 'EOF2'
usage:
  model-matrix.sh --rows [doc] [agents_dir]
  model-matrix.sh --resolve <agent> [state_path] [corpflow_md_path]
  model-matrix.sh --resolved-json [state_path] [corpflow_md_path]
  (omitted state_path/corpflow_md_path resolve from the CONTEXT_DIR root ladder)
EOF2
  exit 2
}

# _mm_default_paths [state_path] [corpflow_md_path] -> sets _mm_state _mm_corpflow.
# Explicit arguments win; an empty one falls back to the resolved root.
_mm_default_paths() {
  _mm_state="${1:-}"
  _mm_corpflow="${2:-}"
  [ -z "$_mm_state" ] || [ -z "$_mm_corpflow" ] || return 0
  if ! command -v corpflow_context_dir > /dev/null 2>&1; then
    local srl="${_MM_DIR}/../../shared/lib/state-read-lib.sh"
    # shellcheck source=../../shared/lib/state-read-lib.sh
    [ -r "$srl" ] && . "$srl"
  fi
  local ctx=""
  if command -v corpflow_context_dir > /dev/null 2>&1; then
    ctx=$(corpflow_context_dir 2> /dev/null) || ctx=""
  fi
  [ -n "$ctx" ] || return 0
  [ -n "$_mm_state" ] || _mm_state="${ctx}/state.json"
  if [ -z "$_mm_corpflow" ]; then
    local root="$ctx"
    case "$root" in */.context) root="${root%/.context}" ;; esac
    _mm_corpflow="${root}/CORPFLOW.md"
  fi
  return 0
}

[ "$#" -ge 1 ] || usage

case "$1" in
  --rows)
    shift
    model_matrix_rows "${1:-}" "${2:-}"
    ;;
  --resolve)
    shift
    [ "$#" -ge 1 ] || usage
    _mm_default_paths "${2:-}" "${3:-}"
    _mm_out=$(model_resolve "$1" "$_mm_state" "$_mm_corpflow") || {
      printf >&2 'model-matrix.sh: no pair resolved for %s\n' "$1"
      exit 2
    }
    printf '%s\n' "$_mm_out"
    ;;
  --resolved-json)
    shift
    command -v jq > /dev/null 2>&1 || {
      printf >&2 'model-matrix.sh --resolved-json requires jq\n'
      exit 2
    }
    _mm_default_paths "${1:-}" "${2:-}"
    # Capture before looping: `done < <(model_matrix_rows)` would discard the extractor's
    # exit 3 and print `{}` with exit 0 on a broken matrix — the fail-open model-matrix-lib.sh hardening rule 4 forbids
    # and state-patch.sh --resolve-models already closes the same way.
    _mm_rows=$(model_matrix_rows) || exit 3
    [ -n "$_mm_rows" ] || exit 3
    _mm_json='{}'
    while IFS=$'\t' read -r _mm_agent _mm_model _mm_effort; do
      _mm_row=$(model_resolve "$_mm_agent" "$_mm_state" "$_mm_corpflow") || continue
      _mm_rmodel="${_mm_row%%$'\t'*}"
      _mm_rrest="${_mm_row#*$'\t'}"
      _mm_reffort="${_mm_rrest%%$'\t'*}"
      _mm_rsource="${_mm_rrest##*$'\t'}"
      _mm_json=$(printf '%s' "$_mm_json" | jq -c --arg a "$_mm_agent" --arg m "$_mm_rmodel" \
        --arg e "$_mm_reffort" --arg s "$_mm_rsource" \
        '. + {($a): {model: $m, effort: $e, source: $s}}')
    done <<< "$_mm_rows"
    printf '%s\n' "$_mm_json"
    ;;
  -h | --help) usage ;;
  *)
    printf >&2 'model-matrix.sh: unknown argument: %s\n' "$1"
    usage
    ;;
esac
