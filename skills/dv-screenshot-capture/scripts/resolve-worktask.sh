#!/usr/bin/env bash
# @description  Resolves the worktask a DV capture belongs to, from the ledger alone.
#               Guard step of the dv-screenshot-capture skill: exit 4 means no worktask,
#               so the caller writes nothing.
#
# @arg  --task-id <ID>   task id (^[A-Z]{2}[0-9]+$) that must be a key of state.json .tasks
# @arg  --state <path>   ledger to read; skips root resolution
# @arg  --self-test      run built-in fixture tests
#
# @stdout  `worktask_id=<id> task_id=<ID|->` on exit 0; `-` when no --task-id was given and
#          the ledger has no single in_progress DV task
# @exitcode 0  a ledger resolved
# @exitcode 2  bad arguments, task id not in the ledger, malformed worktask_id, jq absent,
#              or a broken install (stderr says which)
# @exitcode 4  no worktask resolved: nothing printed, nothing created. The gate's --check uses
#              4 for tool_missing_only, so never chain the two scripts on a bare exit code.
#
# Minimum shell: Bash 3.2.

set -Eeuo pipefail
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

TASK_ID=""
TASK_SET=0
STATE=""
SELF_TEST=0

usage() {
  cat >&2 << 'EOF'
usage: resolve-worktask.sh [--task-id <TASK_ID>] [--state <state.json>] [--self-test]
  exit 0 resolved (prints worktask_id=<id> task_id=<ID|->), 2 usage/ledger error, 4 no worktask
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      [[ $# -ge 2 ]] || usage
      TASK_ID="$2"
      TASK_SET=1
      shift 2
      ;;
    --state)
      [[ $# -ge 2 ]] || usage
      STATE="$2"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    *) usage ;;
  esac
done

_ST_TMP=""
self_test() {
  local tmp self pass=0 fail=0 out rc
  tmp=$(mktemp -d)
  _ST_TMP="$tmp"
  trap '[[ -z "$_ST_TMP" ]] || rm -rf "$_ST_TMP"' EXIT
  self="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
  printf '{"worktask_id":"wt-st","tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"pending"},"QA0":{"status":"in_progress"}}}' > "$tmp/one.json"
  printf '{"worktask_id":"wt-st","tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"in_progress"}}}' > "$tmp/two.json"
  mkdir -p "$tmp/cwd"

  _case() { # <label> <want-rc> <want-stdout> <cmd...>
    local label="$1" want_rc="$2" want_out="$3"
    shift 3
    rc=0
    out=$(trap - ERR; "$@" 2> /dev/null) || rc=$?
    if [[ "$rc" == "$want_rc" ]] && [[ "$out" == "$want_out" ]]; then
      pass=$((pass + 1))
    else
      printf 'FAIL: %s (rc=%s out=%s)\n' "$label" "$rc" "$out"
      fail=$((fail + 1))
    fi
  }

  _case sole-dv 0 'worktask_id=wt-st task_id=DV0' bash "$self" --state "$tmp/one.json"
  _case given-task 0 'worktask_id=wt-st task_id=DV1' bash "$self" --state "$tmp/one.json" --task-id DV1
  _case ambiguous 0 'worktask_id=wt-st task_id=-' bash "$self" --state "$tmp/two.json"
  _case unknown-task 2 '' bash "$self" --state "$tmp/one.json" --task-id DV9
  _case bad-task 2 '' bash "$self" --state "$tmp/one.json" --task-id dv0
  # shellcheck disable=SC2016  # $1/$2 belong to the inner bash -c
  _case unresolved 4 '' env -u CONTEXT_DIR -u WORKSPACE_ROOT -u CLAUDE_PROJECT_DIR \
    GIT_CEILING_DIRECTORIES="$tmp" bash -c 'cd "$1" && bash "$2"' _ "$tmp/cwd" "$self"
  if [[ -e "$tmp/cwd/.context" ]]; then
    printf 'FAIL: unresolved run created .context\n'
    fail=$((fail + 1))
  fi

  printf 'self-test: %d passed, %d failed\n' "$pass" "$fail"
  [[ "$fail" -eq 0 ]]
}

if [[ "$SELF_TEST" -eq 1 ]]; then
  self_test
  exit $?
fi

task_re='^[A-Z]{2}[0-9]+$'
wid_re='^[A-Za-z0-9][A-Za-z0-9._-]*$'

if [[ "$TASK_SET" -eq 1 ]] && ! [[ $TASK_ID =~ $task_re ]]; then
  printf >&2 'resolve-worktask: --task-id must match ^[A-Z]{2}[0-9]+$ (got: %s)\n' "$TASK_ID"
  exit 2
fi
if ! command -v jq > /dev/null 2>&1; then
  printf >&2 'resolve-worktask: jq not found\n'
  exit 2
fi

if [[ -n "$STATE" ]]; then
  if [[ ! -f "$STATE" ]]; then
    printf >&2 'resolve-worktask: --state %s is not a file\n' "$STATE"
    exit 2
  fi
else
  _STATE_READ_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/state-read-lib.sh"
  if [ ! -r "$_STATE_READ_LIB" ]; then
    printf >&2 'resolve-worktask: plugin install broken — state-read-lib.sh not found\n'
    exit 2
  fi
  # shellcheck source=../../shared/lib/state-read-lib.sh
  . "$_STATE_READ_LIB"
  _CTX_RC=0
  _CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
  if [[ "$_CTX_RC" -eq 2 ]]; then
    printf >&2 'resolve-worktask: root resolver unreachable\n'
    exit 2
  fi
  [[ "$_CTX_RC" -eq 0 ]] || exit 4
  STATE="$_CTX_DIR/state.json"
  [[ -f "$STATE" ]] || exit 4
fi

WID=$(trap - ERR; jq -r 'if (.worktask_id|type) == "string" then .worktask_id else "" end' "$STATE" 2> /dev/null) || WID=""
[[ -n "$WID" ]] || exit 4
if ! [[ $WID =~ $wid_re ]]; then
  printf >&2 'resolve-worktask: worktask_id in %s is malformed\n' "$STATE"
  exit 2
fi

if [[ "$TASK_SET" -eq 1 ]]; then
  _HAS=$(trap - ERR; jq -r --arg t "$TASK_ID" '(.tasks|type) == "object" and (.tasks|has($t))' "$STATE" 2> /dev/null) || _HAS=false
  if [[ "$_HAS" != "true" ]]; then
    printf >&2 'resolve-worktask: task %s is not in %s\n' "$TASK_ID" "$STATE"
    exit 2
  fi
else
  TASK_ID=$(trap - ERR; jq -r '[(.tasks // {}) | objects | to_entries[]
      | select((.key | test("^DV[0-9]+$")) and .value.status? == "in_progress") | .key]
    | if length == 1 then .[0] else "-" end' "$STATE" 2> /dev/null) || TASK_ID="-"
fi

printf 'worktask_id=%s task_id=%s\n' "$WID" "$TASK_ID"
