#!/usr/bin/env bats
# Tests for the re-entry reconcile order specified by
# skills/worktask/references/resume.md § Pending communication: a resumed session probes the
# decision ledger and reconciles the mailbox BEFORE the boundary batch asks anything, so a
# question the user already answered — or a peer already replied to — is never put twice.
#
# No script is under test here that is not already covered elsewhere; these cases pin the ORDER
# across the two stores, over the landed fixtures in tests/fixtures/worktask/user-decision/ and
# tests/fixtures/worktask/mailbox/.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

DISPATCH="skills/worktask/scripts/blocked-on-dispatch.sh"
MAILBOX="skills/worktask/scripts/mailbox.sh"
REPLY="skills/worktask/scripts/mailbox-reply.sh"
UD_FIX="${FIXTURES}/worktask/user-decision"
MB_FIX="${FIXTURES}/worktask/mailbox"

# The chain fixture covers DV0 twice: row 1 alone, row 3 with DV1. A probe given no --decision-ref
# takes the newest covering row, so DV0 resumes on row 3.
UD_NEWEST="ud-20260917T101700Z-3"
# The question row 1 answers is the one state.rung1.json parks DV0 on; a resume must never relay it.
UD_Q="Ship the ledger now?"
UD_A="Yes, ship it"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  STATE="$WD/.context/state.json"
  LEDGER="$WD/.context/decisions.jsonl"
  AUDIT="$WD/.context/logs/audit.jsonl"
  MBDIR="$WD/mailbox"
  mkdir -p "$MBDIR/requests" "$MBDIR/replies"
  chmod 700 "$MBDIR" "$MBDIR/requests" "$MBDIR/replies"
  # Exported for every case, not only the mailbox ones: an unset MAILBOX_DIR resolves the
  # developer's own mailbox, and a decision case would then read live asks.
  export MAILBOX_DIR="$MBDIR"
  unset GH_STUB_CALL_LOG GH_STUB_COMMENTS_JSON GH_STUB_FORCE_FAIL
}

# _ud_state — a run parked on a user_decision with the hook's own three-row chain and its audit
# corroboration, exactly as an earlier session would have left them behind.
_ud_state() {
  cp "$UD_FIX/state.rung1.json" "$STATE"
  cp "$UD_FIX/ledger.chain3.jsonl" "$LEDGER"
  cp "$UD_FIX/audit.chain3.jsonl" "$AUDIT"
}

_mb_state() {
  cp "$MB_FIX/state.peer.json" "$STATE"
}

_state_jq() {
  jq "$1" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

# _probe <task_id> — the decision probe § Pending communication runs before the batch.
_probe() {
  run --separate-stderr bash "$PLUGIN_ROOT/$DISPATCH" resume --task-id "$1" --leg resumed --state "$STATE"
}

# _relay <task_id> — the mailbox arm's closing leg, one per replied[] entry.
_relay() {
  run --separate-stderr env MAILBOX_DIR="$MBDIR" MAILBOX_NOW="${MAILBOX_NOW:-1789642800}" \
    bash "$PLUGIN_ROOT/$DISPATCH" resume --task-id "$1" --leg relayed --state "$STATE"
}

_batch() {
  run --separate-stderr bash "$PLUGIN_ROOT/$DISPATCH" batch --state "$STATE"
}

_mb() {
  local sub="$1"
  shift
  run_script_env --separate-stderr \
    --env "MAILBOX_DIR=$MBDIR" --env "MAILBOX_NOW=${MAILBOX_NOW:-1789642800}" \
    --env "GH_BIN=${GH_BIN:-$MB_FIX/gh-stub.sh}" \
    "$MAILBOX" "$sub" --state "$STATE" "$@"
}

# _mkreq <ask_id> <deadline-iso> <created_at-iso> <question> — the request file the ask left behind.
_mkreq() {
  jq -cn --arg id "$1" --arg dl "$2" --arg ca "$3" --arg q "$4" \
    '{ask_id: $id, from_task: "DR0", to: "backend-session", question: $q, deadline: $dl,
      created_at: $ca, reply_schema: {type: "string", minLength: 1, maxLength: 2000}}' \
    > "$MBDIR/requests/$1.json"
}

# _tree — every store the reconcile reads, for the write-nothing assertions.
_tree() {
  cat "$STATE"
  printf '\n--audit--\n'
  [ ! -f "$AUDIT" ] || cat "$AUDIT"
  printf '\n--ledger--\n'
  [ ! -f "$LEDGER" ] || cat "$LEDGER"
  printf '\n--mailbox--\n'
  find "$MBDIR" -type f -print0 2> /dev/null | LC_ALL=C sort -z | xargs -0 -n1 cat 2> /dev/null || true
}

# --- AC2: a decision from an earlier session --------------------------------------

@test "AC2: a decision recorded in an earlier session resumes the task, and the batch has nothing left to ask" {
  _ud_state

  _probe DV0
  assert_success
  jq -e --arg id "$UD_NEWEST" '.cleared == true and .audit_row_written == true
    and .resume_block.task_id == "DV0" and .resume_block.kind == "user_decision"
    and .resume_block.leg == "resumed" and .resume_block.resume_with == "decision_ref"
    and .resume_block.decision_ref == $id' <<< "$output" || fail "probe: $output"

  local needle
  for needle in "$UD_Q" "$UD_A"; do
    [[ "$output" != *"$needle"* ]] || fail "the resume relays decision text: $needle"
  done

  run jq -e '.tasks.DV0.status == "in_progress" and .tasks.DV0.metadata.blocked_on == null' "$STATE"
  assert_success

  _batch
  assert_success
  jq -e '[.needs[].task_id] | index("DV0") == null' <<< "$output" || fail "batch still asks DV0: $output"
}

# --- AC3: a reply that landed while the session was gone ---------------------------

@test "AC3: a reply delivered during the interruption is relayed by reference, never re-asked" {
  _mb_state
  local id="ask-20260917t110000z-406406406406"
  _state_jq ".tasks.DR0.metadata.ask_id = \"$id\""
  _mkreq "$id" "2026-09-18T00:00:00Z" "2026-09-17T09:00:00Z" "Which repo owns the shared schema?"

  _mb leg --task-id DR0 --ask-id "$id" --leg sent --transport message
  assert_success
  _mb leg --task-id DR0 --ask-id "$id" --leg delivered --transport message --result ok
  assert_success

  # The peer answers while this run is not looking; only the files carry it into the next session.
  run_script_env --separate-stderr --stdin-string "The schema lives in the API repo." \
    --env "MAILBOX_DIR=$MBDIR" --env "MAILBOX_NOW=1789642800" \
    "$REPLY" --ask-id "$id" --answer-file - --kind peer --session backend-peer
  assert_success

  _mb scan
  assert_success
  jq -e --arg a "$id" '.replied == [{task_id: "DR0", ask_id: $a}] and .open == []' \
    <<< "$output" || fail "scan: $output"

  _relay DR0
  assert_success
  jq -e --arg a "$id" '.cleared == true
    and .resume_block.resume_with == "reply_ref"
    and .resume_block.reply_ref == ("mailbox/replies/" + $a + ".json")' <<< "$output" || fail "relay: $output"

  run jq -sc '[.[] | select(.action == "blocked_on" and .subject == "DR0") | .metadata.leg]' "$AUDIT"
  assert_success
  assert_output '["sent","delivered","answered","relayed"]'

  run jq -e '.tasks.DR0.status == "in_progress" and .tasks.DR0.metadata.blocked_on == null' "$STATE"
  assert_success
}

# --- AC4: an ask whose deadline passed during the interruption ----------------------

@test "AC4: an ask past its deadline expires into a user_decision and the batch asks it exactly once" {
  _mb_state
  local id="ask-20260917t090000z-aaaaaaaaaaaa"
  _mkreq "$id" "2026-09-17T09:30:00Z" "2026-09-17T09:00:00Z" \
    "Which base branch does the API change target?"

  local MAILBOX_NOW=1789637410
  _mb sweep
  assert_success
  jq -e --arg a "$id" '.expired == [{task_id: "DR0", ask_id: $a, routed: true}]' \
    <<< "$output" || fail "sweep: $output"

  run jq -e '.tasks.DR0.status == "blocked"
    and .tasks.DR0.metadata.blocked_on.kind == "user_decision"
    and .tasks.DR0.metadata.blocked_on.detail.question == "Which base branch does the API change target?"' "$STATE"
  assert_success

  # No decision ledger exists in this tree, so the probe refuses and leaves the need for the batch,
  # which is where a swept ask is asked — once.
  _probe DR0
  [ "$status" -eq 1 ] || fail "a swept need resumed off a decision: exit $status, $output"

  _batch
  assert_success
  jq -e '[.needs[] | select(.task_id == "DR0")] | length == 1' <<< "$output" || fail "needs: $output"
  jq -e '[.payloads[].questions[] | select(.header == "DR0")] | length == 1' \
    <<< "$output" || fail "questions: $output"
}

# --- AC5: a ledger that does not verify --------------------------------------------

@test "AC5: a broken hash chain refuses the probe, writes nothing, and leaves the task parked" {
  _ud_state
  # Rewrite one row's answer: its stored sha256 no longer matches, which breaks the chain from
  # that row on. AD6 trust is whole-ledger, so no row covers anything afterwards.
  local row2
  row2="$(sed -n '2p' "$LEDGER" | jq -c '.answer = "Tampered answer"')"
  L="$row2" awk 'NR == 2 { print ENVIRON["L"]; next } { print }' "$LEDGER" > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"

  local before
  before="$(_tree)"
  _probe DV0
  [ "$status" -eq 1 ] || fail "a broken chain resumed: exit $status, $output"
  [[ "$stderr" == *"no valid, unconsumed user-decision row covers tasks.DV0"* ]] || fail "stderr: $stderr"
  [ -z "$output" ] || fail "a refused probe printed to stdout: $output"
  [ "$(_tree)" = "$before" ] || fail "a refused probe wrote under the temp tree"

  run jq -e '.tasks.DV0.status == "blocked"
    and .tasks.DV0.metadata.blocked_on.kind == "user_decision"' "$STATE"
  assert_success

  _batch
  assert_success
  jq -e '[.needs[] | select(.task_id == "DV0")] | length == 1' <<< "$output" || fail "needs: $output"
}

# --- AC6: the summary is gone, the stores are not ----------------------------------

@test "AC6: with the working summary emptied by a compaction the probe decides identically" {
  _ud_state
  # The shape a compaction leaves: the facts and handoffs the orchestrator was carrying are gone.
  _state_jq '.facts = {} | .handoffs = {}'

  _probe DV0
  assert_success
  jq -e --arg id "$UD_NEWEST" '.cleared == true and .resume_block.decision_ref == $id
    and .resume_block.resume_with == "decision_ref"' <<< "$output" || fail "probe: $output"

  run jq -e '.tasks.DV0.status == "in_progress" and .tasks.DV0.metadata.blocked_on == null' "$STATE"
  assert_success

  _batch
  assert_success
  jq -e '[.needs[].task_id] | index("DV0") == null' <<< "$output" || fail "batch still asks DV0: $output"
}
