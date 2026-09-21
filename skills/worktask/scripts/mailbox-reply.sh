#!/usr/bin/env bash
# @description mailbox-reply.sh — the only writer of mailbox/replies/<ask_id>.json. Checks
#   the ask_id grammar and an untrusted answer against its request's reply_schema, stamps
#   answered_by and ts, and computes the one documented sha256 before the atomic no-clobber
#   write. Used identically for a same-machine peer reply, an accepted reply comment (via
#   mailbox.sh ingest-comments) and a user-typed answer: the caller always passes an
#   already-untrusted answer through --answer-file, never through argv or a heredoc.
#
# Usage:
#   mailbox-reply.sh --ask-id <id> --answer-file <path|-> --kind peer|user --session <s>
#                     [--mailbox-dir <dir>]
#   mailbox-reply.sh --self-test
#
# @arg (default)  Order of operations: the ask_id grammar, then the session grammar, then the
#                 answer is read (capped at 65536 bytes) and its trailing LF run stripped, then
#                 the request must exist and parse and name this ask_id, then its reply_schema
#                 must be the documented subset, then the deadline must not have passed, then the
#                 answer must satisfy the schema, then the reply is written no-clobber. Prints
#                 {"ask_id","reply_ref","sha256"} on success.
# @arg --self-test  Sources mailbox-reply-selftest.sh and runs self_test.
#
# @env MAILBOX_DIR  Test seam (absolute path); see mailbox-lib.sh mb_dir. --mailbox-dir sets the
#                    same variable for this invocation only.
# @env MAILBOX_NOW   Test seam (epoch int); see mailbox-lib.sh mb_now.
#
# @exitcode 0 written
# @exitcode 1 refused; exactly one `fail: <reason>: <detail>` line on stderr, reason one of
#             invalid_ask_id, bad_session, too_long, unknown_ask, bad_request, late,
#             schema_invalid, duplicate. Nothing is written.
# @exitcode 2 usage error, mailbox unavailable, or no sha256 tool installed
#
# Minimum shell: bash 3.2+. Requires jq.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

die() {
  printf >&2 'mailbox-reply: %s\n' "$2"
  exit "$1"
}

fail() {
  printf >&2 'fail: %s: %s\n' "$1" "$2"
  exit 1
}

usage() {
  sed -n '/^# Usage:/,/^# @arg --self-test/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
  exit 2
}

if [ "${1:-}" = "--self-test" ]; then
  # shellcheck source=skills/worktask/scripts/mailbox-reply-selftest.sh
  . "$SCRIPT_DIR/mailbox-reply-selftest.sh"
  self_test
  exit $?
fi

command -v jq > /dev/null 2>&1 || die 2 "jq is required"
_MR_LIB="$SCRIPT_DIR/mailbox-lib.sh"
[ -r "$_MR_LIB" ] || die 2 "plugin install broken — missing $_MR_LIB"
# shellcheck disable=SC1090
. "$_MR_LIB"

ASK_ARG="" ANSWER_FILE="" KIND_ARG="" SESSION_ARG="" MB_DIR_ARG=""
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage
  case "$1" in
    --ask-id) ASK_ARG="$2" ;;
    --answer-file) ANSWER_FILE="$2" ;;
    --kind) KIND_ARG="$2" ;;
    --session) SESSION_ARG="$2" ;;
    --mailbox-dir) MB_DIR_ARG="$2" ;;
    *) usage ;;
  esac
  shift 2
done

[ -n "$ASK_ARG" ] || usage
[ -n "$ANSWER_FILE" ] || usage
case "$KIND_ARG" in
  peer | user) ;;
  *) usage ;;
esac
[ -n "$SESSION_ARG" ] || usage
# shellcheck disable=SC2034  # read by mb_dir() in the sourced mailbox-lib.sh, not this file
[ -z "$MB_DIR_ARG" ] || MAILBOX_DIR="$MB_DIR_ARG"

# --- order of operations -------------------------------------------------------------
mb_valid_ask_id "$ASK_ARG" || fail invalid_ask_id "$ASK_ARG does not match the ask_id grammar"

[[ "$SESSION_ARG" =~ ^[A-Za-z0-9][A-Za-z0-9._:@-]{0,99}$ ]] \
  || fail bad_session "session does not match the session grammar"

# A sentinel byte after the capped read, stripped after capture: command substitution trims
# every trailing newline on its own, which would otherwise hide a true too_long answer whose
# extra bytes were themselves newlines. wc -c (never `${#var}`) counts raw bytes regardless of
# locale, matching the byte cap `head -c` already enforced.
if [ "$ANSWER_FILE" = "-" ]; then
  ANSWER_RAW=$(
    head -c 65537
    printf 'x'
  )
else
  [ -r "$ANSWER_FILE" ] || die 2 "cannot read --answer-file $ANSWER_FILE"
  ANSWER_RAW=$(
    head -c 65537 < "$ANSWER_FILE"
    printf 'x'
  )
fi
ANSWER_RAW="${ANSWER_RAW%x}"
ANSWER_LEN=$(printf '%s' "$ANSWER_RAW" | wc -c | tr -d ' ')
[ "$ANSWER_LEN" -le 65536 ] || fail too_long "answer exceeds 65536 bytes"

while :; do
  case "$ANSWER_RAW" in
    *$'\n') ANSWER_RAW="${ANSWER_RAW%$'\n'}" ;;
    *) break ;;
  esac
done
ANSWER="$ANSWER_RAW"

# An unusable mailbox is an install or environment fault, not a claim about this ask: report it as
# exit 2 so a caller never reads "unknown ask" and concludes the id was wrong.
mb_dir > /dev/null 2>&1 || die 2 "mailbox unavailable"

REQUEST=$(mb_read_request "$ASK_ARG" 2> /dev/null) || fail unknown_ask "no request for $ASK_ARG"
[ -n "$REQUEST" ] || fail unknown_ask "no request for $ASK_ARG"

REQ_ASK_ID=$(printf '%s' "$REQUEST" | jq -r '.ask_id // ""')
[ "$REQ_ASK_ID" = "$ASK_ARG" ] || fail bad_request "request ask_id does not match"

SCHEMA=$(printf '%s' "$REQUEST" | jq -c '.reply_schema // {}')
SCHEMA_OK=$(jq -n --argjson sc "$SCHEMA" "$MB_JQ_DEFS"'$sc | mb_schema_ok' 2> /dev/null) || SCHEMA_OK=false
[ "$SCHEMA_OK" = "true" ] || fail bad_request "reply_schema is not the documented subset"

DEADLINE=$(printf '%s' "$REQUEST" | jq -r '.deadline // ""')
DEADLINE_EPOCH=$(jq -rn --arg d "$DEADLINE" "$MB_JQ_DEFS"'($d | mb_epoch) // empty' 2> /dev/null) || DEADLINE_EPOCH=""
[ -n "$DEADLINE_EPOCH" ] || fail bad_request "request deadline is not ISO-8601"
NOW=$(mb_now)
[ "$NOW" -lt "$DEADLINE_EPOCH" ] || fail late "now is at or past the deadline"

ANSWER_OK=$(jq -n --arg a "$ANSWER" --argjson sc "$SCHEMA" "$MB_JQ_DEFS"'$a | mb_answer_ok($sc)' 2> /dev/null) || ANSWER_OK=false
[ "$ANSWER_OK" = "true" ] || fail schema_invalid "answer does not satisfy the request's reply_schema"

TS=$(jq -rn --argjson t "$NOW" '($t | todate)' 2> /dev/null) || TS=""
[ -n "$TS" ] || die 2 "cannot stamp the reply"

SHA=$(jq -j -n --arg a "$ASK_ARG" --arg k "$KIND_ARG" --arg s "$SESSION_ARG" --arg t "$TS" --arg ans "$ANSWER" \
  "$MB_JQ_DEFS"'mb_hash_input($a;$k;$s;$t;$ans)' | mb_sha256) || die 2 "no sha256 tool available"
[ -n "$SHA" ] || die 2 "no sha256 tool available"

REPLY_JSON=$(jq -cn --arg id "$ASK_ARG" --arg ans "$ANSWER" --arg k "$KIND_ARG" --arg s "$SESSION_ARG" \
  --arg ts "$TS" --arg sha "$SHA" \
  '{ask_id: $id, answer: $ans, answered_by: {session: $s, kind: $k}, ts: $ts, sha256: $sha}')

DIR=$(mb_dir) || die 2 "mailbox unavailable"
WRC=0
mb_write_nc "$DIR/replies" "$ASK_ARG" "$REPLY_JSON" || WRC=$?
case "$WRC" in
  0) : ;;
  1) fail duplicate "a reply for $ASK_ARG already exists" ;;
  *) die 2 "mailbox unavailable" ;;
esac

jq -cn --arg id "$ASK_ARG" --arg rr "mailbox/replies/$ASK_ARG.json" --arg sha "$SHA" \
  '{ask_id: $id, reply_ref: $rr, sha256: $sha}'
