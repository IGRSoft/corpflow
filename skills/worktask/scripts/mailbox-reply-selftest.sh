#!/usr/bin/env bash
# mailbox-reply-selftest.sh — the `--self-test` harness for mailbox-reply.sh.
#
# SOURCED, never executed: mailbox-reply.sh loads this file only on the `--self-test` path, so
# the production reply path never pays for it. Requests are written directly into a throwaway
# MAILBOX_DIR (bypassing mailbox-lib.sh's own writer), because this harness tests
# mailbox-reply.sh's reader and validator, not request creation.
#
# Contract: defines `self_test`, returning 0 when every case passes.

self_test() {
  local self td fails=0
  self="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/mailbox-reply.sh"
  command -v jq > /dev/null 2>&1 || {
    echo "mailbox-reply: self-test FAIL (jq missing)"
    return 1
  }
  td=$(mktemp -d) || return 1
  # shellcheck disable=SC2064  # expand now: td is local and gone by the time EXIT fires
  trap "rm -rf '$td'" EXIT
  mkdir -p "$td/mailbox/requests" "$td/mailbox/replies"

  _st_pass() { printf '  ok   %s\n' "$1"; }
  _st_fail() {
    printf '  FAIL %s\n' "$1"
    fails=$((fails + 1))
  }

  # _mkreq <ask_id> <deadline-iso> <reply_schema-json> [question] — writes requests/<id>.json
  # directly; mailbox-reply.sh's own request grammar and schema checks are what is under test.
  _mkreq() {
    jq -cn --arg id "$1" --arg dl "$2" --arg q "${4:-Pick one.}" --argjson sc "$3" \
      '{ask_id: $id, from_task: "DR0", to: "peer", question: $q, deadline: $dl,
        created_at: "2026-09-17T00:00:00Z", reply_schema: $sc}' \
      > "$td/mailbox/requests/$1.json"
  }

  # _st_run <ask_id> <answer-text> [--kind K] [--session S] — env MAILBOX_DIR/MAILBOX_NOW fixed
  # for the whole harness; stdout/stderr captured apart so a fail: reason can be asserted.
  local OUT="" ERR="" RC=0
  _st_run() {
    local id="$1" ans="$2" kind="peer" session="peer1"
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --kind) kind="$2"; shift 2 ;;
        --session) session="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    RC=0
    OUT=$(printf '%s' "$ans" \
      | env MAILBOX_DIR="$td/mailbox" MAILBOX_NOW=1789646700 \
        bash "$self" --ask-id "$id" --answer-file - --kind "$kind" --session "$session" \
        2> "$td/stderr.tmp") || RC=$?
    ERR=$(cat "$td/stderr.tmp" 2> /dev/null)
  }

  # ---- AC2: a schema-invalid reply is rejected -------------------------------------
  _mkreq "ask-20260917t000001z-000000000001" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":5}'
  _st_run "ask-20260917t000001z-000000000001" "too long answer"
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q '^fail: schema_invalid:' \
    && [ ! -e "$td/mailbox/replies/ask-20260917t000001z-000000000001.json" ]; then
    _st_pass "AC2: a schema-invalid reply is rejected and writes nothing"
  else
    _st_fail "AC2: a schema-invalid reply is rejected and writes nothing (rc=$RC err=$ERR)"
  fi

  # ---- AC2: a valid reply gets the documented sha256 -------------------------------
  _mkreq "ask-20260917t120000z-0123456789ab" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":2000}'
  _st_run "ask-20260917t120000z-0123456789ab" "Use option B." --session reviewer-session
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" \
    | jq -e '.ask_id == "ask-20260917t120000z-0123456789ab"
      and .reply_ref == "mailbox/replies/ask-20260917t120000z-0123456789ab.json"
      and .sha256 == "17c68893bdb74b6cfac0239b27a60fdf5e46651128f0d349af20f957d6875558"' \
      > /dev/null 2>&1; then
    _st_pass "AC2: a valid reply gets the documented sha256"
  else
    _st_fail "AC2: a valid reply gets the documented sha256 (rc=$RC out=$OUT)"
  fi

  # ---- AC2/AC6: a reply to an unknown ask_id is rejected ---------------------------
  _st_run "ask-20260917t000009z-000000000009" "anything"
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q '^fail: unknown_ask:'; then
    _st_pass "AC2/AC6: a reply to an unknown ask_id is rejected"
  else
    _st_fail "AC2/AC6: a reply to an unknown ask_id is rejected (rc=$RC err=$ERR)"
  fi

  # ---- AC6: a traversal-shaped ask_id is rejected before any path join -------------
  _st_run '../../etc/passwd' "anything"
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q '^fail: invalid_ask_id:'; then
    _st_pass "AC6: a traversal-shaped ask_id is rejected"
  else
    _st_fail "AC6: a traversal-shaped ask_id is rejected (rc=$RC err=$ERR)"
  fi

  # ---- AC6: an over-long answer is rejected ----------------------------------------
  _mkreq "ask-20260917t000002z-000000000002" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":4000}'
  RC=0
  ERR=""
  OUT=$(
    head -c 70000 /dev/zero | tr '\0' 'a' \
      | env MAILBOX_DIR="$td/mailbox" MAILBOX_NOW=1789646700 \
        bash "$self" --ask-id ask-20260917t000002z-000000000002 --answer-file - --kind peer --session peer1 \
        2> "$td/stderr.tmp"
  ) || RC=$?
  ERR=$(cat "$td/stderr.tmp" 2> /dev/null)
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q '^fail: too_long:'; then
    _st_pass "AC6: an over-long answer is rejected"
  else
    _st_fail "AC6: an over-long answer is rejected (rc=$RC err=$ERR)"
  fi

  # ---- AC6: a duplicate reply is rejected; the first writer wins -------------------
  _mkreq "ask-20260917t000003z-000000000003" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":2000}'
  _st_run "ask-20260917t000003z-000000000003" "first"
  _st_run "ask-20260917t000003z-000000000003" "second"
  local kept
  kept=$(jq -r '.answer' "$td/mailbox/replies/ask-20260917t000003z-000000000003.json" 2> /dev/null)
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q '^fail: duplicate:' && [ "$kept" = "first" ]; then
    _st_pass "AC6: a duplicate reply is rejected and the first writer wins"
  else
    _st_fail "AC6: a duplicate reply is rejected and the first writer wins (rc=$RC err=$ERR kept=$kept)"
  fi

  # ---- AC6: a late reply (now at or past the deadline) is rejected -----------------
  _mkreq "ask-20260917t000004z-000000000004" "2026-09-17T00:00:00Z" '{"type":"string","maxLength":2000}'
  _st_run "ask-20260917t000004z-000000000004" "too late"
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q '^fail: late:'; then
    _st_pass "AC6: a late reply is rejected"
  else
    _st_fail "AC6: a late reply is rejected (rc=$RC err=$ERR)"
  fi

  if [ "$fails" -eq 0 ]; then
    echo "mailbox-reply: self-test OK"
    return 0
  fi
  echo "mailbox-reply: self-test FAIL ($fails)"
  return 1
}
