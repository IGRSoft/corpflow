#!/usr/bin/env bash
# permission-park-selftest.sh — the `--self-test` harness for permission-park.sh.
#
# SOURCED, never executed: permission-park.sh loads this file only on `--self-test`, so the
# production path never pays for it. Drives the real CLI end to end against a throwaway ledger
# through the real state-patch.sh, never a stub.
#
# Contract: defines `self_test`, returning 0 when every case passes.

self_test() {
  local self td state out rc fails=0
  self="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/permission-park.sh"
  command -v jq > /dev/null 2>&1 || { echo "permission-park: self-test FAIL (jq missing)"; return 1; }
  td=$(mktemp -d) || return 1
  # shellcheck disable=SC2064  # expand now: td is local and gone by the time EXIT fires
  trap "rm -rf '$td'" EXIT
  mkdir -p "$td/.context/logs"
  state="$td/.context/state.json"
  printf '%s' '{"version":2,"run_index":0,"facts":{},"tasks":{
    "PL0":{"status":"completed","metadata":{}},
    "FN0":{"status":"in_progress","metadata":{"retry_count":2}},
    "DR0":{"status":"in_progress","metadata":{}}}}' > "$state"

  _st_pass() { printf '  ok   %s\n' "$1"; }
  _st_fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
  _st_run() {
    env -u WORKSPACE_ROOT -u CONTEXT_DIR -u CLAUDE_PROJECT_DIR bash "$self" "$@" 2> /dev/null
  }

  rc=0
  out=$(_st_run classify --payload '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"},"reason":"Blocked by classifier"}') || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.allow_rule == "Bash(gh pr merge 1)"' > /dev/null 2>&1; then
    _st_pass "classify: a PermissionDenied event yields the four-key detail"
  else
    _st_fail "classify: a PermissionDenied event yields the four-key detail"
  fi

  rc=0
  _st_run classify --payload 'build finished, 3 warnings' > /dev/null || rc=$?
  if [ "$rc" -eq 1 ]; then
    _st_pass "classify: ordinary text is not a denial (exit 1)"
  else
    _st_fail "classify: ordinary text is not a denial (exit 1)"
  fi

  rc=0
  _st_run classify --payload "$(printf 'Bash(gh pr merge 1)\n  Blocked by classifier\n')" > /dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then
    rc=0
    _st_run classify --payload 'Error: Blocked by classifier' > /dev/null || rc=$?
  else
    rc=0
  fi
  if [ "$rc" -eq 1 ]; then
    _st_pass "classify: text path recovers Tool(command); no tool line is not parkable"
  else
    _st_fail "classify: text path recovers Tool(command); no tool line is not parkable"
  fi

  _st_run park --state "$state" --task-id FN0 --detail "$out" > /dev/null || true
  _st_run park --state "$state" --task-id FN0 --detail "$out" > /dev/null || true
  if jq -e '.tasks.FN0.status == "blocked" and .tasks.FN0.metadata.retry_count == 2
      and .tasks.FN0.metadata.blocked_on.kind == "permission"' "$state" > /dev/null 2>&1 \
    && [ "$(grep -c '"action":"permission_denied"' "$td/.context/logs/audit.jsonl")" = "1" ] \
    && ! grep -qF 'classifier' "$td/.context/logs/audit.jsonl"; then
    _st_pass "park: blocked, retry_count untouched, one redacted row across two parks"
  else
    _st_fail "park: blocked, retry_count untouched, one redacted row across two parks"
  fi

  out=$(_st_run batch --state "$state") || true
  if printf '%s' "$out" | jq -e '.mode == "ask" and (.payloads | length) == 1
      and (.payloads[0].questions | length) == 1' > /dev/null 2>&1; then
    _st_pass "batch: one payload for the parked need"
  else
    _st_fail "batch: one payload for the parked need"
  fi

  out=$(_st_run resume --state "$state" --task-id FN0 --answer grant) || true
  if printf '%s' "$out" | jq -e '.cleared and .resume_block.do_not_rerun
      and .resume_block.command == "gh pr merge 1"' > /dev/null 2>&1 \
    && jq -e '.tasks.FN0.status == "in_progress" and .tasks.FN0.metadata.blocked_on == null' \
      "$state" > /dev/null 2>&1 \
    && [ "$(grep -c '"action":"permission_resumed"' "$td/.context/logs/audit.jsonl")" = "1" ]; then
    _st_pass "resume: claims back to in_progress, clears blocked_on, records the answer"
  else
    _st_fail "resume: claims back to in_progress, clears blocked_on, records the answer"
  fi

  if [ "$fails" -eq 0 ]; then
    echo "permission-park: self-test OK"
    return 0
  fi
  echo "permission-park: self-test FAIL ($fails)"
  return 1
}
