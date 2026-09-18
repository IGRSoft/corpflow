#!/usr/bin/env bats
# Tests for skills/worktask/scripts/mailbox.sh — the orchestrator side of the durable
# cross-session mailbox (show/leg/comment/ingest-comments/scan/sweep) — against the
# fixtures under tests/fixtures/worktask/mailbox/. Covers AC1, AC3, AC4, AC6, AC7, AC13
# (architecture-0.md, planning-0.md § acceptance-criteria).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/mailbox.sh"
DISPATCH="skills/worktask/scripts/blocked-on-dispatch.sh"
FIX="${FIXTURES}/worktask/mailbox"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  STATE="$WD/.context/state.json"
  AUDIT="$WD/.context/logs/audit.jsonl"
  MBDIR="$WD/mailbox"
  mkdir -p "$MBDIR/requests" "$MBDIR/replies"
  chmod 700 "$MBDIR" "$MBDIR/requests" "$MBDIR/replies"
  cp "$FIX/state.peer.json" "$STATE"
  unset GH_STUB_CALL_LOG GH_STUB_COMMENTS_JSON GH_STUB_FORCE_FAIL GH_STUB_FORCE_FAIL_CODE
}

teardown() {
  # Belt-and-suspenders restore for the scrub_failed case below, which chmods this real
  # (non-fixture) sibling library 000 for the width of one call and restores it inline;
  # this guarantees the restore even if that test fails before reaching its own chmod back.
  chmod 644 "$PLUGIN_ROOT/skills/shared/scripts/path-scrub.sh" 2> /dev/null || true
  _test_helper_cleanup
}

# _mb <subcommand> [args...] — mailbox.sh against this test's ledger and mailbox dir.
# MAILBOX_NOW and GH_BIN are read from a caller-scoped `local` (dynamic scope), so a test
# overrides either by declaring it before calling _mb.
_mb() {
  local sub="$1"
  shift
  run_script_env --separate-stderr \
    --env "MAILBOX_DIR=$MBDIR" --env "MAILBOX_NOW=${MAILBOX_NOW:-1789642800}" \
    --env "GH_BIN=${GH_BIN:-$FIX/gh-stub.sh}" \
    "$SCRIPT" "$sub" --state "$STATE" "$@"
}

_ledger_jq() {
  jq "$1" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

# _mkreq <ask_id> <deadline-iso> <created_at-iso> <question> [to] — writes requests/<id>.json.
_mkreq() {
  local id="$1" dl="$2" ca="$3" q="$4" to="${5:-backend-session}"
  jq -cn --arg id "$id" --arg dl "$dl" --arg ca "$ca" --arg q "$q" --arg to "$to" \
    '{ask_id: $id, from_task: "DR0", to: $to, question: $q, deadline: $dl, created_at: $ca,
      reply_schema: {type: "string", minLength: 1, maxLength: 2000}}' \
    > "$MBDIR/requests/$id.json"
}

# _posted_leg <task> <ask_id> — the delivered/posted leg ingestion now requires before it will
# accept a comment for an ask. Without it a comment could answer an ask that never reached the issue.
_posted_leg() {
  jq -cn --arg t "$1" --arg a "$2" '{ts: "2026-09-17T14:01:00Z", actor: "orchestrator",
    action: "blocked_on", result: "blocked", subject: $t, task_id: $t,
    metadata: {kind: "peer_session", arm: "peer_session", leg: "delivered", ask_id: $a,
               transport: "comment", transport_result: "posted"}}' >> "$AUDIT"
}

# --- AC1: silent remote peer -------------------------------------------------------

@test "AC1: a silent remote peer expires at deadline+5; blocked_on becomes user_decision; one asked row; one batch need; a second sweep adds nothing" {
  local id="ask-20260917t090000z-aaaaaaaaaaaa"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-17T09:30:00Z" "2026-09-17T09:00:00Z" \
    "Which base branch does the API change target?"

  local MAILBOX_NOW=1789637410
  _mb sweep
  assert_success
  jq -e --arg t DR0 --arg a "$id" \
    '.expired == [{task_id: $t, ask_id: $a, routed: true}]' <<< "$output" || fail "output: $output"

  assert_audit_row blocked_on --file "$AUDIT" --subject DR0 --result blocked \
    --meta leg=expired --meta ask_id="$id" --count 1
  assert_audit_row blocked_on --file "$AUDIT" --subject DR0 --result blocked \
    --meta leg=asked --count 1

  run jq -e '.tasks.DR0.status == "blocked"
    and .tasks.DR0.metadata.blocked_on.kind == "user_decision"
    and .tasks.DR0.metadata.blocked_on.detail.question == "Which base branch does the API change target?"
    and .tasks.DR0.metadata.blocked_on.detail.options == []' "$STATE"
  assert_success

  _mb sweep
  assert_success
  jq -e '.expired == []' <<< "$output" || fail "second sweep output: $output"

  run bash "$PLUGIN_ROOT/$DISPATCH" batch --state "$STATE"
  assert_success
  jq -e '([.needs[].task_id]) == ["DR0"]' <<< "$output" || fail "batch output: $output"
}

# --- AC3: comment transport ---------------------------------------------------------

@test "AC3: comment --render-only renders <ask_id> blank-line <question> and equals its own path-scrub output" {
  local id="ask-20260917t100000z-bbbbbbbbbbbb" body expected
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" \
    "Which base branch should this land on?"

  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  export GH_STUB_CALL_LOG
  _mb comment --task-id DR0 --render-only
  assert_success
  body="$(jq -r '.body' <<< "$output")"

  expected="$(printf '%s\n\nWhich base branch should this land on?' "$id")"
  [ "$body" = "$expected" ] || fail "unexpected body: $body"
  [[ "$body" != *"/Users/"* ]] || fail "body leaks an absolute path"
  [[ "$body" != *".context/"* ]] || fail "body leaks an artifact path"

  run_script_env --stdin-string "$body" \
    --source skills/shared/scripts/path-scrub.sh corpflow_path_scrub
  assert_success
  [ "$output" = "$body" ] || fail "body is not its own path-scrub fixed point: $output"

  [ ! -e "$WD/gh-calls.log" ] || fail "render-only made a gh call"
}

@test "AC3: a question carrying an absolute path or a .context/ path is refused as scrub_failed, never partially redacted" {
  local id="ask-20260917t100050z-bbbbbbbbbbbe" q
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  q="$(cat "$FIX/question-with-paths.txt")"
  jq -cn --arg id "$id" --arg dl "2026-09-18T00:00:00Z" --arg ca "2026-09-17T09:00:00Z" --arg q "$q" \
    '{ask_id: $id, from_task: "DR0", to: "backend-session", question: $q, deadline: $dl,
      created_at: $ca, reply_schema: {type: "string", minLength: 1, maxLength: 2000}}' \
    > "$MBDIR/requests/$id.json"

  # D13 runs pd_bound (PD_JQ_DEFS) before sanitise_body; pd_bound's [[:cntrl:]] strip turns
  # every embedded newline into a space, so the question reaches sanitise_body as ONE line.
  # sanitise_body's L1/L2 drop a whole matching LINE, never a token inside it, so a question
  # carrying a host path or a .context/ reference anywhere loses its entire text rather than
  # being partially redacted — q ends up empty and the render refuses as scrub_failed. This
  # is the real, current behaviour (verified against the sourced functions directly); it is
  # stricter than a partial-redaction reading of AC3's "contains no absolute path" wording,
  # not a partial-redaction bug: no path and no other question text is ever posted either way.
  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  export GH_STUB_CALL_LOG
  _mb comment --task-id DR0 --render-only
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"scrub_failed"* ]] || fail "stderr: $stderr"
  [[ "$output" != *"/Users/"* ]] || fail "output leaks an absolute path"
  [[ "$output" != *".context/"* ]] || fail "output leaks an artifact path"
  [ ! -e "$WD/gh-calls.log" ] || fail "scrub_failed made a gh call"
}

@test "AC3: comment posts through the gh stub exactly once and writes sent/delivered legs" {
  local id="ask-20260917t100100z-bbbbbbbbbbbc"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" "Pick a base branch."

  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  export GH_STUB_CALL_LOG
  _mb comment --task-id DR0
  assert_success
  jq -e '.posted == true and .result == "posted"' <<< "$output" || fail "output: $output"

  [ -f "$WD/gh-calls.log" ] || fail "expected exactly one gh call"
  [ "$(wc -l < "$WD/gh-calls.log" | tr -d ' ')" -eq 1 ]
  grep -q -- '--body-file' "$WD/gh-calls.log"
  grep -q '^issue comment 999 ' "$WD/gh-calls.log"

  assert_audit_row blocked_on --file "$AUDIT" --subject DR0 --result blocked \
    --meta leg=sent --meta ask_id="$id" --count 1
  assert_audit_row blocked_on --file "$AUDIT" --subject DR0 --result blocked \
    --meta leg=delivered --meta ask_id="$id" --meta transport_result=posted --count 1
}

@test "AC3: an unreadable path-scrub library yields scrub_failed and no gh call" {
  local id="ask-20260917t100200z-bbbbbbbbbbbd" scrub
  scrub="$PLUGIN_ROOT/skills/shared/scripts/path-scrub.sh"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" "Pick a base branch."

  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  export GH_STUB_CALL_LOG
  chmod 000 "$scrub"
  _mb comment --task-id DR0 --render-only
  chmod 644 "$scrub"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"scrub_failed"* ]] || fail "stderr: $stderr"
  [ ! -e "$WD/gh-calls.log" ] || fail "scrub_failed made a gh call"
}

# --- AC4: same-machine order ---------------------------------------------------------

@test "AC4: same-machine order — sent, delivered, answered, relayed; resume carries reply_ref; a repeated sent writes nothing" {
  local id="ask-20260917t110000z-cccccccccccc"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" \
    "Which repo owns the shared schema?" "peer-session"

  _mb leg --task-id DR0 --ask-id "$id" --leg sent --transport message
  assert_success
  jq -e '.written == true' <<< "$output" || fail "output: $output"

  _mb leg --task-id DR0 --ask-id "$id" --leg sent --transport message
  assert_success
  jq -e '.written == false' <<< "$output" || fail "repeated sent output: $output"

  _mb leg --task-id DR0 --ask-id "$id" --leg delivered --transport message --result ok
  assert_success
  jq -e '.written == true' <<< "$output" || fail "output: $output"

  run_script_env --separate-stderr --stdin-string "Use branch main." \
    --env "MAILBOX_DIR=$MBDIR" --env "MAILBOX_NOW=1789642800" \
    skills/worktask/scripts/mailbox-reply.sh --ask-id "$id" --answer-file - \
    --kind peer --session backend-peer
  assert_success

  _mb scan
  assert_success
  jq -e --arg t DR0 --arg a "$id" '.replied == [{task_id: $t, ask_id: $a}] and .open == []' \
    <<< "$output" || fail "scan output: $output"

  run --separate-stderr env MAILBOX_DIR="$MBDIR" MAILBOX_NOW=1789642800 \
    bash "$PLUGIN_ROOT/$DISPATCH" resume --task-id DR0 --leg relayed --state "$STATE"
  assert_success
  jq -e --arg a "$id" '.cleared == true
    and (.resume_block.reply_ref | test("^mailbox/replies/ask-[0-9]{8}t[0-9]{6}z-[0-9a-f]{12}\\.json$"))
    and (.resume_block.reply_ref == ("mailbox/replies/" + $a + ".json"))' \
    <<< "$output" || fail "resume output: $output"

  run jq -sc --arg t DR0 '[.[] | select(.action == "blocked_on" and .subject == $t) | .metadata.leg]' "$AUDIT"
  assert_success
  assert_output '["sent","delivered","answered","relayed"]'
}

# --- AC6: ingest filter --------------------------------------------------------------

@test "AC6: ingest-comments accepts exactly the OWNER reply, ignores the rest with reasons, and writes no login or body text" {
  local id="ask-20260917t140000z-2223456789ab"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T14:00:00Z" "Pick A or B." "peer"
  _posted_leg DR0 "$id"

  local MAILBOX_NOW=1789657200
  GH_STUB_COMMENTS_JSON="$FIX/comments.mixed.json"
  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  export GH_STUB_COMMENTS_JSON GH_STUB_CALL_LOG
  _mb ingest-comments
  assert_success
  jq -e '.ingested == 1' <<< "$output" || fail "output: $output"

  [ "$(jq -r '.answer' "$MBDIR/replies/$id.json")" = "Use option B." ]
  [ "$(jq -r '.answered_by.session' "$MBDIR/replies/$id.json")" = "gh:alice-owner" ]
  [ "$(jq -r '.answered_by.kind' "$MBDIR/replies/$id.json")" = "peer" ]

  run jq -sc --arg t DR0 '[.[] | select(.action == "mailbox_ingest" and .subject == $t)]' "$AUDIT"
  assert_success
  [ "$(jq 'length' <<< "$output")" -eq 1 ] || fail "mailbox_ingest rows: $output"
  jq -e --arg id "$id" '.[0].metadata.ask_id == $id and .[0].metadata.ignored == 3
    and (.[0].metadata.reasons | sort) == ["author", "bot", "stale"]
    and (.[0].metadata | has("login") | not)' <<< "$output" || fail "row: $output"

  ! grep -qF "Use option B." "$AUDIT"
  ! grep -qF "I think C." "$AUDIT"
  ! grep -qF "alice-owner" "$AUDIT"
}

# --- AC5/G4: no branch leaves an ask parked forever ------------------------------------

@test "AC5: an ask whose request file is unreadable still expires; the question comes from the ledger" {
  local id="ask-20260917t141500z-3334456789ab"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\"
    | .tasks.DR0.metadata.blocked_on.detail.question = \"LEDGER-FALLBACK-QUESTION\""
  # No request file at all: the record that held the deadline and the schema is gone, so nothing
  # can arrive on this ask any more.
  local MAILBOX_NOW=1789657200
  _mb sweep
  assert_success
  jq -e --arg a "$id" '.expired | length == 1 and .[0].ask_id == $a and .[0].routed == true' <<< "$output" \
    || fail "output: $output"
  run jq -e '.tasks.DR0.metadata.blocked_on.kind == "user_decision"
    and .tasks.DR0.metadata.blocked_on.detail.question == "LEDGER-FALLBACK-QUESTION"
    and .tasks.DR0.metadata.blocked_on.detail.options == []' "$STATE"
  assert_success
  run jq -sc --arg a "$id" '[.[] | select(.action == "blocked_on" and .metadata.ask_id == $a
    and .metadata.leg == "expired")] | length' "$AUDIT"
  assert_output 1
  ! grep -qF "LEDGER-FALLBACK-QUESTION" "$AUDIT"
}

@test "AC5: an unparseable request falls back to the ledger deadline and expires there, clamped" {
  local id="ask-20260917t141600z-4445456789ab"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\"
    | .tasks.DR0.metadata.blocked_on.detail.question = \"LEDGER-DEADLINE-QUESTION\"
    | .tasks.DR0.metadata.blocked_on.detail.deadline = \"2026-09-17T15:00:00Z\""
  printf 'not json\n' > "$MBDIR/requests/$id.json"
  local MAILBOX_NOW=1789650000   # 2026-09-17T13:00:00Z — before the ledger deadline
  _mb sweep
  assert_success
  jq -e '.expired == []' <<< "$output" || fail "early sweep expired it: $output"
  MAILBOX_NOW=1789657300         # 2026-09-17T15:01:40Z — past the ledger deadline plus its grace
  _mb sweep
  assert_success
  jq -e --arg a "$id" '.expired | length == 1 and .[0].ask_id == $a' <<< "$output" || fail "output: $output"
}

# --- static contracts: the poll and the pagination -------------------------------------

@test "contract: ingestion reads every page, scopes the fetch, and polls GitHub only for a posted ask" {
  # jq -s, not gh --slurp: --slurp needs gh >= 2.42 and an older gh would quietly return page 1.
  run grep -nE -- '--paginate' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_output --partial "slurp"
  run grep -nE 'jq -s -c' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # since= bounds the fetch to the oldest open ask; per_page and the cap bound one page and the walk.
  run grep -nE 'since=.*per_page=100' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run grep -nE 'MAILBOX_INGEST_MAX' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # Without the gate, a message-transport ask would spend one API call a minute on an issue
  # nobody was asked on.
  run grep -nE 'posted_open. -eq 1 . && .* -ge 60' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run grep -nE 'transport_result.* == .posted' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # A spin loop at MAILBOX_POLL_SECONDS=0 would burn a core until the deadline.
  run grep -nE 'poll. -ge 1 .. poll=1' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "AC6/AC13: ingest refuses an ask its task opted out of, and one whose comment never posted" {
  local id="ask-20260917t142000z-5556456789ab"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T14:00:00Z" "Pick A or B." "peer"
  local MAILBOX_NOW=1789657200
  GH_STUB_COMMENTS_JSON="$FIX/comments.mixed.json"
  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  export GH_STUB_COMMENTS_JSON GH_STUB_CALL_LOG

  # No posted leg yet: the ask went out by message, or its comment was refused, so a comment
  # naming its ask_id answers a question that was never published there.
  _mb ingest-comments
  assert_success
  jq -e '.ingested == 0' <<< "$output" || fail "accepted without a posted leg: $output"
  [ ! -f "$MBDIR/replies/$id.json" ]
  [ ! -f "$WD/gh-calls.log" ] || fail "called gh with nothing eligible"

  # Now it is posted, but the task opted out of GitHub: the send side honours that, and so must
  # the receive side.
  _posted_leg DR0 "$id"
  _ledger_jq '.tasks.DR0.metadata.no_gh_issue = true'
  _mb ingest-comments
  assert_success
  jq -e '.ingested == 0' <<< "$output" || fail "ingested under the opt-out: $output"
  [ ! -f "$MBDIR/replies/$id.json" ]
  [ ! -f "$WD/gh-calls.log" ] || fail "called gh under the opt-out"

  # With the opt-out lifted and the ask posted, the same comment is accepted.
  _ledger_jq 'del(.tasks.DR0.metadata.no_gh_issue)'
  _mb ingest-comments
  assert_success
  jq -e '.ingested == 1' <<< "$output" || fail "output: $output"
  [ "$(jq -r '.answer' "$MBDIR/replies/$id.json")" = "Use option B." ]
}

# --- AC7: audit redaction -------------------------------------------------------------

@test "AC7: no leg or ingest row carries the question or answer text" {
  local id="ask-20260917t150000z-dddddddddddd" q="AC7-UNIQUE-QUESTION-TOKEN" ans="AC7-UNIQUE-ANSWER-TOKEN"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" "$q" "peer"

  _mb leg --task-id DR0 --ask-id "$id" --leg sent --transport message
  assert_success
  _mb leg --task-id DR0 --ask-id "$id" --leg delivered --transport message --result ok
  assert_success

  run_script_env --separate-stderr --stdin-string "$ans" \
    --env "MAILBOX_DIR=$MBDIR" --env "MAILBOX_NOW=1789642800" \
    skills/worktask/scripts/mailbox-reply.sh --ask-id "$id" --answer-file - \
    --kind peer --session backend-peer
  assert_success

  _mb scan
  assert_success

  run --separate-stderr env MAILBOX_DIR="$MBDIR" MAILBOX_NOW=1789642800 \
    bash "$PLUGIN_ROOT/$DISPATCH" resume --task-id DR0 --leg relayed --state "$STATE"
  assert_success

  [ -f "$AUDIT" ]
  ! grep -qF "$q" "$AUDIT"
  ! grep -qF "$ans" "$AUDIT"
}

# --- AC13: opt-out (q1) ---------------------------------------------------------------

@test "AC13: opt-out (no_gh_issue) skips gh entirely; the delivered leg records opted_out" {
  cp "$FIX/state.peer-optout.json" "$STATE"
  local id="ask-20260917t160000z-eeeeeeeeeeee"
  _ledger_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" "Pick A or B." "peer"

  GH_STUB_CALL_LOG="$WD/gh-calls.log"
  GH_STUB_FORCE_FAIL=1
  export GH_STUB_CALL_LOG GH_STUB_FORCE_FAIL
  _mb comment --task-id DR0
  assert_success
  jq -e '.posted == false and .result == "opted_out"' <<< "$output" || fail "output: $output"
  [ ! -e "$WD/gh-calls.log" ] || fail "opted_out made a gh call"

  assert_audit_row blocked_on --file "$AUDIT" --subject DR0 --result blocked \
    --meta leg=delivered --meta ask_id="$id" --meta transport_result=opted_out --count 1
  assert_audit_row blocked_on --file "$AUDIT" --subject DR0 --result blocked --meta leg=sent --absent
}
