#!/usr/bin/env bats
# Tests for skills/worktask/scripts/mailbox-reply.sh — the only writer of
# mailbox/replies/<ask_id>.json — against the fixtures under
# tests/fixtures/worktask/mailbox/. AC2/AC6 (untrusted input) and the documented sha256
# vector (architecture-0.md § schemas).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/mailbox-reply.sh"
FIX="${FIXTURES}/worktask/mailbox"

setup() {
  WD="$(mk_tmpworkdir)"
  MBDIR="$WD/mailbox"
  mkdir -p "$MBDIR/requests" "$MBDIR/replies"
  chmod 700 "$MBDIR" "$MBDIR/requests" "$MBDIR/replies"
}

# _mkreq <ask_id> <deadline-iso> <reply_schema-json> [question] [created_at] — writes
# requests/<id>.json directly, the same shape mailbox-lib.sh's mb_create_request writes.
_mkreq() {
  local id="$1" dl="$2" sc="$3" q="${4:-Pick one.}" ca="${5:-2026-09-17T00:00:00Z}"
  jq -cn --arg id "$id" --arg dl "$dl" --arg q "$q" --arg ca "$ca" --argjson sc "$sc" \
    '{ask_id: $id, from_task: "DR0", to: "peer", question: $q, deadline: $dl,
      created_at: $ca, reply_schema: $sc}' \
    > "$MBDIR/requests/$id.json"
}

# _reply <ask_id> <answer> [extra flags...] — feeds the answer through --answer-file -;
# MAILBOX_NOW is read from a caller-scoped `local NOW=...`, dynamic-scope default 11:00Z.
_reply() {
  local id="$1" ans="$2"
  shift 2
  run_script_env --separate-stderr --stdin-string "$ans" \
    --env "MAILBOX_DIR=$MBDIR" --env "MAILBOX_NOW=${NOW:-1789642800}" \
    "$SCRIPT" --ask-id "$id" --answer-file - --kind peer --session peer1 "$@"
}

@test "mailbox-reply: a traversal-shaped ask_id is refused before any path join; nothing is written" {
  _reply '../../etc/passwd' 'anything'
  [ "$status" -eq 1 ]
  [[ "$stderr" == fail:\ invalid_ask_id:* ]] || fail "stderr: $stderr"
  [ -z "$(find "$MBDIR/replies" -mindepth 1 2> /dev/null)" ]
}

@test "mailbox-reply: an unknown ask_id is refused; nothing is written" {
  _reply "ask-20260917t133000z-555555555555" "anything"
  [ "$status" -eq 1 ]
  [[ "$stderr" == fail:\ unknown_ask:* ]] || fail "stderr: $stderr"
  [ -z "$(find "$MBDIR/replies" -mindepth 1 2> /dev/null)" ]
}

@test "mailbox-reply: a reply_schema outside the documented subset is refused as bad_request" {
  local id
  id="$(jq -r '.ask_id' "$FIX/request.unknown-keyword.json")"
  cp "$FIX/request.unknown-keyword.json" "$MBDIR/requests/$id.json"
  _reply "$id" "OK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"fail: bad_request:"*"reply_schema is not the documented subset"* ]] || fail "stderr: $stderr"
  [ ! -e "$MBDIR/replies/$id.json" ]
}

@test "mailbox-reply: an answer outside its enum is refused as schema_invalid" {
  local id="ask-20260917t130500z-111111111111"
  _mkreq "$id" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":50,"enum":["yes","no"]}'
  _reply "$id" "maybe"
  [ "$status" -eq 1 ]
  [[ "$stderr" == fail:\ schema_invalid:* ]] || fail "stderr: $stderr"
  [ ! -e "$MBDIR/replies/$id.json" ]
}

@test "mailbox-reply: an answer over 65536 bytes is refused as too_long" {
  local id="ask-20260917t131000z-222222222222" big
  _mkreq "$id" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":4000}'
  big="$(head -c 70000 /dev/zero | tr '\0' 'a')"
  _reply "$id" "$big"
  [ "$status" -eq 1 ]
  [[ "$stderr" == fail:\ too_long:* ]] || fail "stderr: $stderr"
  [ ! -e "$MBDIR/replies/$id.json" ]
}

@test "mailbox-reply: a reply at or past the deadline is refused as late" {
  local id="ask-20260917t090500z-333333333333"
  _mkreq "$id" "2026-09-17T09:00:00Z" '{"type":"string","maxLength":2000}'
  _reply "$id" "too late"
  [ "$status" -eq 1 ]
  [[ "$stderr" == fail:\ late:* ]] || fail "stderr: $stderr"
  [ ! -e "$MBDIR/replies/$id.json" ]
}

@test "mailbox-reply: a duplicate reply is refused; the first writer wins and the file is unchanged" {
  local id="ask-20260917t132000z-444444444444"
  _mkreq "$id" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":2000}'
  _reply "$id" "first"
  [ "$status" -eq 0 ]
  local before
  before="$(cat "$MBDIR/replies/$id.json")"
  _reply "$id" "second"
  [ "$status" -eq 1 ]
  [[ "$stderr" == fail:\ duplicate:* ]] || fail "stderr: $stderr"
  [ "$(cat "$MBDIR/replies/$id.json")" = "$before" ]
  [ "$(jq -r '.answer' "$MBDIR/replies/$id.json")" = "first" ]
}

@test "mailbox-reply: the documented sha256 vector" {
  local id NOW=1789646700
  id="$(jq -r '.ask_id' "$FIX/request.valid.json")"
  [ "$id" = "ask-20260917t120000z-0123456789ab" ]
  cp "$FIX/request.valid.json" "$MBDIR/requests/$id.json"
  _reply "$id" "Use option B." --session reviewer-session
  [ "$status" -eq 0 ]
  jq -e '.ask_id == "ask-20260917t120000z-0123456789ab"
    and .reply_ref == "mailbox/replies/ask-20260917t120000z-0123456789ab.json"
    and .sha256 == "17c68893bdb74b6cfac0239b27a60fdf5e46651128f0d349af20f957d6875558"' \
    <<< "$output" || fail "output: $output"
}

@test "mailbox-reply: reply_ref is relative, matching the documented ERE" {
  local id="ask-20260917t134000z-666666666666" rr
  _mkreq "$id" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":2000}'
  _reply "$id" "ok"
  [ "$status" -eq 0 ]
  rr="$(jq -r '.reply_ref' <<< "$output")"
  [[ "$rr" =~ ^mailbox/replies/ask-[0-9]{8}t[0-9]{6}z-[0-9a-f]{12}\.json$ ]] || fail "reply_ref: $rr"
  [[ "$rr" != /* ]] || fail "reply_ref must not be absolute: $rr"
}

@test "mailbox-reply: the reply file is written 0600; the mailbox dirs stay 0700" {
  local id="ask-20260917t135000z-777777777777" mode d
  _mkreq "$id" "2026-09-18T00:00:00Z" '{"type":"string","maxLength":2000}'
  _reply "$id" "ok"
  [ "$status" -eq 0 ]
  mode="$(stat -f '%Lp' "$MBDIR/replies/$id.json" 2> /dev/null || stat -c '%a' "$MBDIR/replies/$id.json")"
  [ "$mode" = "600" ] || fail "reply file mode: $mode"
  for d in "$MBDIR" "$MBDIR/requests" "$MBDIR/replies"; do
    mode="$(stat -f '%Lp' "$d" 2> /dev/null || stat -c '%a' "$d")"
    [ "$mode" = "700" ] || fail "$d mode: $mode"
  done
}

@test "mailbox-reply: a symlinked mailbox dir is refused; the real target is untouched" {
  local real link
  real="$WD/real-target"
  mkdir -p "$real"
  link="$WD/mailbox-link"
  ln -s "$real" "$link"
  run_script_env --separate-stderr --stdin-string "anything" \
    "$SCRIPT" --ask-id "ask-20260917t136000z-888888888888" --answer-file - \
    --kind peer --session peer1 --mailbox-dir "$link"
  # Exit 2, not a refusal: a symlinked mailbox is an unusable environment, and calling it
  # "unknown ask" would blame the id the caller passed.
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"mailbox unavailable"* ]] || fail "stderr: $stderr"
  [ -z "$(find "$real" -mindepth 1 2> /dev/null)" ]
}
