#!/usr/bin/env bats
# Tests for skills/worktask/scripts/state-patch.sh --verify-decision — the read-only verifier CLI
# over the user-decision ledger (AD6): exit 0 valid with the question and answer printed, exit 5
# refused with null text, exit 2 on usage. Every call is wrapped in a snapshot of the temp tree,
# so a verify that writes a log, a lock, an audit row or the ledger itself fails the case.
#
# The chain fixture (ledger.chain3.jsonl + audit.chain3.jsonl) is three genuine hook rows in
# wt-ud-fixture: row 1 covers DV0, row 2 covers AR0 (sweep sw-AR0-1), row 3 covers DV0 and DV1.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/state-patch.sh"
UD_FIX="${FIXTURES}/worktask/user-decision"
ID1="ud-20260917T101500Z-1"
ID2="ud-20260917T101600Z-2"
ID3="ud-20260917T101700Z-3"
# sha256 of the fixture's row-3 line bytes: the prev a genuine row 4 would carry.
S3="3e76a5070a9c2f09342876521920b60d40a2d978a0ae35c2c47bf00817f133ad"
# sha256 of the fixture's row-1 line bytes.
S1="8dc86ec697af321ded72a7a6e1802c635983bc93429cf41614cb9cc7eb160143"

setup() {
  WD="$(mk_tmpworkdir)"
  CTX="$WD/.context"
  mkdir -p "$CTX/logs"
  STATE="$CTX/state.json"
  LEDGER="$CTX/decisions.jsonl"
  AUDIT="$CTX/logs/audit.jsonl"
  cp "$UD_FIX/state.rung1.json" "$STATE"
  cp "$UD_FIX/ledger.chain3.jsonl" "$LEDGER"
  cp "$UD_FIX/audit.chain3.jsonl" "$AUDIT"
}

# _snapshot — every path under the temp tree plus each file's digest, sorted.
_snapshot() {
  (
    cd "$WD" || exit 1
    find . -print | LC_ALL=C sort
    find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort
  )
}

# _vd [args...] — state-patch.sh against this test's state; fails the case if anything changed.
_vd() {
  local before
  before="$(_snapshot)"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$STATE" "$@"
  [ "$(_snapshot)" = "$before" ] || fail "--verify-decision wrote under the temp tree: $(diff <(printf '%s\n' "$before") <(_snapshot))"
}

_line() {
  sed -n "${1}p" "$LEDGER"
}

_canon_sha() {
  printf '%s' "$1" | jq -jc '[.question,.answer]' | shasum -a 256 | cut -d' ' -f1
}

_set_line() {
  L="$2" awk -v n="$1" 'NR == n { print ENVIRON["L"]; next } { print }' "$LEDGER" > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
}

# _row <id> <prev> <actor> <tool_use_id> — a row with a correct canonical digest, scoped to DV0.
_row() {
  local row
  row="$(jq -cn --arg id "$1" --arg prev "$2" --arg actor "$3" --arg tuid "$4" \
    '{id: $id, ts: "2026-09-17T10:20:00Z", actor: $actor, tool_use_id: $tuid,
      question: "Ship the ledger now?", answer: "Not yet",
      scope: {worktask_id: "wt-ud-fixture", task_ids: ["DV0"], item: null}, sha256: null, prev_sha256: $prev}')"
  printf '%s' "$row" | jq -c --arg s "$(_canon_sha "$row")" '.sha256 = $s'
}

# _audit_for <row json> <actor> — a user_decision_recorded row naming that row's id and digest.
_audit_for() {
  printf '%s' "$1" | jq -c --arg actor "$2" '{ts: "2026-09-17T10:20:00Z", actor: $actor,
    action: "user_decision_recorded", subject: .id, result: "ok", task_id: "DV0",
    metadata: {decision_id: .id, tool_use_id: .tool_use_id, row_sha256: .sha256, item: null}}'
}

# _assert_refused <id> <reason> [exact] — exit 5, null text, <reason> named; with [exact], the
# reasons array is exactly [<reason>].
_assert_refused() {
  [ "$status" -eq 5 ] || fail "want exit 5, got $status (stdout: $output, stderr: $stderr)"
  jq -e --arg id "$1" --arg r "$2" --arg exact "${3:-}" '.decision_ref == $id and .valid == false
    and .question == null and .answer == null and .scope == null and .row_index == null
    and (.reasons | index($r)) != null and ($exact == "" or .reasons == [$r])' <<< "$output" > /dev/null \
    || fail "want a refusal naming $2, got: $output"
}

# --- exit 0 ----------------------------------------------------------------------------------

@test "exit 0: a genuine hook row verifies, prints its question and answer, and writes nothing" {
  _vd --verify-decision "$ID1" --task-id DV0
  assert_success
  jq -e --arg id "$ID1" '.decision_ref == $id and .task_id == "DV0" and .valid == true and .reasons == []
    and .question == "Ship the ledger now?" and .answer == "Yes, ship it"
    and .scope == {worktask_id: "wt-ud-fixture", task_ids: ["DV0"], item: null}
    and .row_index == 1 and .chain_rows == 3' <<< "$output"
  [ -z "$stderr" ] || fail "a valid verify printed to stderr: $stderr"
  [ ! -e "$CTX/logs/state-merge.log" ] || fail "the read-only op wrote state-merge.log"
  [ ! -e "$LEDGER.lock" ] || fail "the read-only op took the ledger lock"
}

@test "exit 0: --expect-answer with the exact answer verifies; a row covering two tasks verifies for each" {
  _vd --verify-decision "$ID1" --task-id DV0 --expect-answer "Yes, ship it"
  assert_success
  jq -e '.valid == true and .answer == "Yes, ship it"' <<< "$output"
  _vd --verify-decision "$ID3" --task-id DV1
  assert_success
  _vd --verify-decision "$ID3" --task-id DV0
  assert_success
}

@test "exit 0: --log does not make the read-only op write a log" {
  _vd --log "$CTX/logs/verify.log" --verify-decision "$ID1" --task-id DV0
  assert_success
  [ ! -e "$CTX/logs/verify.log" ]
}

# --- exit 5: AC2 provenance ------------------------------------------------------------------

@test "AC2: a row the orchestrator wrote itself is actor_mismatch with null text, and refuses every other id" {
  local forged
  forged="$(_row "ud-20260917T102000Z-4" "$S3" orchestrator toolu_01UdForged0004)"
  printf '%s\n' "$forged" >> "$LEDGER"
  _audit_for "$forged" orchestrator >> "$AUDIT"
  _vd --verify-decision "ud-20260917T102000Z-4" --task-id DV0
  _assert_refused "ud-20260917T102000Z-4" actor_mismatch exact
  [[ "$output" != *"Not yet"* ]] || fail "a forged row's answer reached stdout"
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" actor_mismatch
}

@test "AC2: a forged row stamped with the hook actor but no hook audit row is audit_uncorroborated" {
  local forged
  forged="$(_row "ud-20260917T102000Z-4" "$S3" hook:user-decision toolu_01UdForged0004)"
  printf '%s\n' "$forged" >> "$LEDGER"
  _vd --verify-decision "ud-20260917T102000Z-4" --task-id DV0
  _assert_refused "ud-20260917T102000Z-4" audit_uncorroborated exact

  # An audit row the orchestrator wrote for it corroborates nothing.
  _audit_for "$forged" orchestrator >> "$AUDIT"
  _vd --verify-decision "ud-20260917T102000Z-4" --task-id DV0
  _assert_refused "ud-20260917T102000Z-4" audit_uncorroborated exact

  # Uncorroborated is per row, not whole-ledger: the genuine rows still verify.
  _vd --verify-decision "$ID1" --task-id DV0
  assert_success
}

# --- exit 5: AC3 integrity -------------------------------------------------------------------

@test "AC3: an edited answer with its stale sha256 is sha256_mismatch, and the edit refuses every id" {
  _set_line 1 "$(_line 1 | jq -c '.answer = "Not yet"')"
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" sha256_mismatch
  [[ "$output" != *"Not yet"* ]] || fail "an edited row's answer reached stdout"
  _vd --verify-decision "$ID3" --task-id DV0
  _assert_refused "$ID3" sha256_mismatch
  _vd --verify-decision "$ID2" --task-id AR0
  _assert_refused "$ID2" chain_broken
}

@test "AC3: an edited middle row with a recomputed sha256 is chain_broken for every id" {
  local edited
  edited="$(_line 2 | jq -c '.answer = "Write nothing"')"
  _set_line 2 "$(printf '%s' "$edited" | jq -c --arg s "$(_canon_sha "$edited")" '.sha256 = $s')"
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" chain_broken exact
  _vd --verify-decision "$ID2" --task-id AR0
  _assert_refused "$ID2" chain_broken exact
}

@test "AC3: an edited last row with a recomputed sha256 leaves no chain break but loses its audit corroboration" {
  local edited
  edited="$(_line 3 | jq -c '.answer = "Linux"')"
  _set_line 3 "$(printf '%s' "$edited" | jq -c --arg s "$(_canon_sha "$edited")" '.sha256 = $s')"
  _vd --verify-decision "$ID3" --task-id DV0
  _assert_refused "$ID3" audit_uncorroborated exact
}

@test "AC3: an inserted row, even with a correct digest, prev and a hook audit row, is chain_broken for every id" {
  local forged
  forged="$(_row "ud-20260917T101630Z-2" "$S1" hook:user-decision toolu_01UdForged0002)"
  { _line 1; printf '%s\n' "$forged"; _line 2; _line 3; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _audit_for "$forged" hook:user-decision >> "$AUDIT"
  _vd --verify-decision "ud-20260917T101630Z-2" --task-id DV0
  _assert_refused "ud-20260917T101630Z-2" chain_broken exact
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" chain_broken exact
}

# --- exit 5: AC4 scope and the remaining reasons ---------------------------------------------

@test "AC4: a valid row whose scope does not cover --task-id is scope_not_covering" {
  _vd --verify-decision "$ID1" --task-id DR0
  _assert_refused "$ID1" scope_not_covering exact
  _vd --verify-decision "$ID2" --task-id DV0
  _assert_refused "$ID2" scope_not_covering exact
  _vd --verify-decision "$ID1" --task-id DV1
  _assert_refused "$ID1" scope_not_covering exact
}

@test "a row recorded for another worktask is worktask_mismatch" {
  jq '.worktask_id = "wt-other"' "$UD_FIX/state.rung1.json" > "$STATE"
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" worktask_mismatch exact
}

@test "a missing corroborating audit row, or no audit log at all, is audit_uncorroborated" {
  grep -vF "\"subject\":\"$ID1\"" "$UD_FIX/audit.chain3.jsonl" > "$AUDIT"
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" audit_uncorroborated exact
  _vd --verify-decision "$ID3" --task-id DV0
  assert_success

  rm -f "$AUDIT"
  _vd --verify-decision "$ID3" --task-id DV0
  _assert_refused "$ID3" audit_uncorroborated exact
}

@test "--expect-answer that differs by a byte is answer_mismatch with null text" {
  _vd --verify-decision "$ID1" --task-id DV0 --expect-answer "Not yet"
  _assert_refused "$ID1" answer_mismatch exact
  _vd --verify-decision "$ID1" --task-id DV0 --expect-answer "yes, ship it"
  _assert_refused "$ID1" answer_mismatch exact
  _vd --verify-decision "$ID1" --task-id DV0 --expect-answer ""
  _assert_refused "$ID1" answer_mismatch exact
}

@test "an id absent from the ledger, or no ledger at all, is not_found" {
  _vd --verify-decision "ud-20260917T101500Z-9" --task-id DV0
  _assert_refused "ud-20260917T101500Z-9" not_found exact
  rm -f "$LEDGER"
  _vd --verify-decision "$ID1" --task-id DV0
  _assert_refused "$ID1" not_found exact
}

# --- exit 2 ----------------------------------------------------------------------------------

@test "exit 2: a missing --task-id is a usage error" {
  _vd --verify-decision "$ID1"
  [ "$status" -eq 2 ] || fail "want exit 2, got $status"
  [[ "$stderr" == *"requires --task-id"* ]] || fail "stderr: $stderr"
}

@test "exit 2: a malformed id is a usage error, never a refusal" {
  local bad
  for bad in "ud-nope" "ud-20260917T101500Z-0" "ud-20260917T101500Z-1;id" "../ud-20260917T101500Z-1" " $ID1"; do
    _vd --verify-decision "$bad" --task-id DV0
    [ "$status" -eq 2 ] || fail "'$bad': want exit 2, got $status (stdout: $output)"
  done
}

@test "exit 2: a ledger version other than 2 is refused before any verify" {
  jq '.version = 3' "$UD_FIX/state.rung1.json" > "$STATE"
  _vd --verify-decision "$ID1" --task-id DV0
  [ "$status" -eq 2 ] || fail "want exit 2, got $status"
  [[ "$stderr" == *"unsupported"* ]] || fail "stderr: $stderr"
}
