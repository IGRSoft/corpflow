#!/usr/bin/env bats
# Tests for hooks/lib/user-decision-lib.sh — the canonical digests, the chain walk, audit
# corroboration, the verifier and the covering-row search, sourced under a strict-mode caller.
#
# Every digest is a literal computed once from fixed bytes, and every mutation re-derives its own
# expectation with shasum rather than the library, so a hashing drift cannot move both sides.
# The ledger name is materialised only inside each test's temp dir (AD8): the chain fixture is
# ledger.chain3.jsonl, three rows with a clean chain and one corroborating audit row each.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="hooks/lib/user-decision-lib.sh"
UD_FIX="${FIXTURES}/worktask/user-decision"

# sha256 of ["Ship the ledger now?","Yes, ship it"].
C1="9a935cce7ef6f8d91d0199f2af4d2f99d30473698c82be2f92d44e02c009d120"
# sha256 of ["Should rung-3 answers be recorded?","Record with empty task_ids, Write nothing"].
C2="01850ed18109a41570375239783bf43789564c6e5117adc6eb2842c4f8b766dc"
# sha256 of ["Which targets must pass?","macOS, Linux"].
C3="b25f9084b8a0513709c4c49a8c5d73a23cdfa2987aad0aceb1143a6d108cb488"
# sha256 of each fixture line's stored bytes, without its LF.
S1="8dc86ec697af321ded72a7a6e1802c635983bc93429cf41614cb9cc7eb160143"
S2="5d6434cc1c1163c6123e84d06f435f36baf01a8795cbe7037870b76618b4e9df"
S3="3e76a5070a9c2f09342876521920b60d40a2d978a0ae35c2c47bf00817f133ad"
ID1="ud-20260917T101500Z-1"
ID2="ud-20260917T101600Z-2"
ID3="ud-20260917T101700Z-3"

setup() {
  WD="$(mk_tmpworkdir)"
  CTX="$WD/.context"
  mkdir -p "$CTX/logs"
  export STATE="$CTX/state.json"
  export LEDGER="$CTX/decisions.jsonl"
  export AUDIT="$CTX/logs/audit.jsonl"
  cp "$UD_FIX/state.rung1.json" "$STATE"
  cp "$UD_FIX/ledger.chain3.jsonl" "$LEDGER"
  cp "$UD_FIX/audit.chain3.jsonl" "$AUDIT"
}

# _lib <snippet> [args...] — the snippet with the library sourced under state-patch's strict mode;
# [args] reach it as "$@", so no path or text is spliced into the program string.
_lib() {
  local snippet="$1"
  shift
  run --separate-stderr bash -c "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; $snippet" _ "$@" < /dev/null
}

# _verify <id> <task> [expect] — ud_verify against this test's context; $status is its rc.
_verify() {
  # shellcheck disable=SC2016  # expanded by the inner shell, where $@ and $STATE are set
  _lib 'rc=0; ud_verify "$STATE" "$LEDGER" "$AUDIT" "$@" || rc=$?; exit "$rc"' "$@"
}

# _walk — ud_chain_walk over the ledger as one JSON array in $output.
_walk() {
  # shellcheck disable=SC2016  # expanded by the inner shell
  _lib 'ud_chain_walk "$LEDGER" | jq -sc .'
  assert_success
}

# _line <n> — the ledger's line n, without its LF.
_line() {
  sed -n "${1}p" "$LEDGER"
}

# _canon_sha <row json> — the AD2 digest of the row, derived independently of the library.
_canon_sha() {
  printf '%s' "$1" | jq -jc '[.question,.answer]' | shasum -a 256 | cut -d' ' -f1
}

# _set_line <n> <text> — replace line n; ENVIRON keeps awk from reading escapes in <text>.
_set_line() {
  L="$2" awk -v n="$1" 'NR == n { print ENVIRON["L"]; next } { print }' "$LEDGER" > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
}

# _forged <id> <prev> [actor] — a row with a correct canonical digest and the given prev.
_forged() {
  local row
  row="$(jq -cn --arg id "$1" --arg prev "$2" --arg actor "${3:-hook:user-decision}" \
    '{id: $id, ts: "2026-09-17T10:16:30Z", actor: $actor, tool_use_id: "toolu_01UdForged0001",
      question: "Ship the ledger now?", answer: "Not yet",
      scope: {worktask_id: "wt-ud-fixture", task_ids: ["DV0"], item: null}, sha256: null, prev_sha256: $prev}')"
  printf '%s' "$row" | jq -c --arg s "$(_canon_sha "$row")" '.sha256 = $s'
}

# _append_row <id> <question-json> <answer-json> <scope-jq> <tool_use_id> — one well-chained row
# plus its corroborating audit row; digests come from shasum, not the library.
_append_row() {
  local prev row
  prev="$(tail -n 1 "$LEDGER" | tr -d '\n' | shasum -a 256 | cut -d' ' -f1)"
  row="$(jq -cn --arg id "$1" --argjson q "$2" --argjson a "$3" --arg t "$5" --arg prev "$prev" \
    "{id: \$id, ts: \"2026-09-17T10:18:00Z\", actor: \"hook:user-decision\", tool_use_id: \$t,
      question: \$q, answer: \$a, scope: $4, sha256: null, prev_sha256: \$prev}")"
  row="$(printf '%s' "$row" | jq -c --arg s "$(_canon_sha "$row")" '.sha256 = $s')"
  printf '%s\n' "$row" >> "$LEDGER"
  printf '%s' "$row" | jq -c '{ts: "2026-09-17T10:18:00Z", actor: "hook:user-decision",
    action: "user_decision_recorded", subject: .id, result: "ok", task_id: .scope.task_ids[0],
    metadata: {decision_id: .id, tool_use_id: .tool_use_id, row_sha256: .sha256, item: .scope.item}}' >> "$AUDIT"
}

# _assert_refused_all <reason> <id>... — every id is refused with null text and names <reason>.
_assert_refused_all() {
  local reason="$1" id
  shift
  for id in "$@"; do
    _verify "$id" DV0
    [ "$status" -eq 1 ] || fail "$id: rc $status, want 1 (output: $output)"
    jq -e --arg r "$reason" --arg id "$id" '.decision_ref == $id and .valid == false
      and .question == null and .answer == null and .scope == null and .row_index == null
      and (.reasons | index($r)) != null' <<< "$output" > /dev/null \
      || fail "$id: expected a refusal naming $reason, got $output"
  done
}

# --- load contract ----------------------------------------------------------------------------

@test "executing the library directly is refused" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
  assert_output --partial "source it, do not execute it directly"
}

@test "a double source is a no-op under set -euo pipefail, and the lib defines no corpflow_ symbol" {
  _lib ". '$PLUGIN_ROOT/$LIB'; printf '%s' \"\$UD_ACTOR\""
  assert_success
  assert_output "hook:user-decision"
  run grep -nE '^[[:space:]]*corpflow_[A-Za-z0-9_]*[[:space:]]*\(\)' "$PLUGIN_ROOT/$LIB"
  assert_failure 1
}

# --- AC3: canonical digests -------------------------------------------------------------------

@test "AC3: ud_digest prints the pinned SHA-256 of the empty string and of abc" {
  _lib 'printf "" | ud_digest; printf "\n"; printf abc | ud_digest'
  assert_success
  [ "${lines[0]}" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ] || fail "empty: ${lines[0]}"
  [ "${lines[1]}" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ] || fail "abc: ${lines[1]}"
}

@test "AC3: ud_row_sha256 hashes each fixture row to its pinned [question,answer] digest, from a file and from stdin" {
  local i want
  for i in 1 2 3; do
    case "$i" in 1) want="$C1" ;; 2) want="$C2" ;; 3) want="$C3" ;; esac
    _line "$i" > "$WD/row$i.json"
    # shellcheck disable=SC2016  # expanded by the inner shell
    _lib 'ud_row_sha256 "$1"; printf "\n"; ud_row_sha256 - < "$1"' "$WD/row$i.json"
    assert_success
    [ "${lines[0]}" = "$want" ] || fail "row $i from a file: ${lines[0]}"
    [ "${lines[1]}" = "$want" ] || fail "row $i from stdin: ${lines[1]}"
    [ "$(jq -r .sha256 "$WD/row$i.json")" = "$want" ] || fail "fixture row $i stores a different sha256"
  done
}

@test "AC3: quotes, a backslash, non-ASCII and a slash hash through the one canonical form to a pinned digest" {
  jq -cn --arg q 'Say "hi" \ now' --arg a 'café / ok' '{question: $q, answer: $a}' > "$WD/escapes.json"
  # shellcheck disable=SC2016  # expanded by the inner shell
  _lib 'ud_row_sha256 "$1"' "$WD/escapes.json"
  assert_success
  # sha256 of the bytes ["Say \"hi\" \\ now","café / ok"].
  assert_output "44c765d2786aabdc33a977c5ba7590dedd483aea12914af988fdebd8d20f5961"
}

@test "AC3: ud_row_sha256 refuses a missing or symlinked row file with rc 2" {
  # shellcheck disable=SC2016  # expanded by the inner shell
  _lib 'rc=0; ud_row_sha256 "$1" || rc=$?; exit "$rc"' "$WD/absent.json"
  assert_failure 2
  _line 1 > "$WD/row1.json"
  ln -s "$WD/row1.json" "$WD/link.json"
  # shellcheck disable=SC2016  # expanded by the inner shell
  _lib 'rc=0; ud_row_sha256 "$1" || rc=$?; exit "$rc"' "$WD/link.json"
  assert_failure 2
}

@test "AC3: ud_line_sha256 digests stored line bytes, and each fixture prev_sha256 is the line before it" {
  # shellcheck disable=SC2016  # expanded by the inner shell
  _lib 'ud_line_sha256 "$1"; printf "\n"; ud_line_sha256 "$2"; printf "\n"; ud_line_sha256 "$3"' \
    "$(_line 1)" "$(_line 2)" "$(_line 3)"
  assert_success
  [ "${lines[0]}" = "$S1" ] && [ "${lines[1]}" = "$S2" ] && [ "${lines[2]}" = "$S3" ] \
    || fail "line digests: $output"
  run jq -se --arg s1 "$S1" --arg s2 "$S2" \
    'map(.prev_sha256) == [null, $s1, $s2]' "$LEDGER"
  assert_success
}

# --- AC3: chain walk --------------------------------------------------------------------------

@test "AC3: the fixture chain walks as three clean rows carrying their ids and line digests" {
  _walk
  jq -e --arg i1 "$ID1" --arg i2 "$ID2" --arg i3 "$ID3" --arg s1 "$S1" --arg s2 "$S2" --arg s3 "$S3" '
    length == 3 and all(.[]; .reasons == []) and map(.index) == [1, 2, 3]
    and map(.id) == [$i1, $i2, $i3] and map(.line_sha256) == [$s1, $s2, $s3]' <<< "$output"
}

@test "AC3: an edited middle row is sha256_mismatch there and chain_broken on the row after it" {
  _set_line 2 "$(_line 2 | jq -c '.answer = "Write nothing"')"
  _walk
  jq -e '.[0].reasons == [] and .[1].reasons == ["sha256_mismatch"] and .[2].reasons == ["chain_broken"]' <<< "$output" \
    || fail "walk: $output"
}

@test "AC3: an edited middle row whose sha256 is recomputed still breaks the chain at the next row" {
  local edited
  edited="$(_line 2 | jq -c '.answer = "Write nothing"')"
  _set_line 2 "$(printf '%s' "$edited" | jq -c --arg s "$(_canon_sha "$edited")" '.sha256 = $s')"
  _walk
  jq -e '.[0].reasons == [] and .[1].reasons == [] and .[2].reasons == ["chain_broken"]' <<< "$output" \
    || fail "walk: $output"
}

@test "AC3: an inserted row breaks the chain even with a correct digest and prev" {
  local forged
  forged="$(_forged "ud-20260917T101630Z-2" "$S1")"
  { _line 1; printf '%s\n' "$forged"; _line 2; _line 3; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _walk
  jq -e 'length == 4 and .[0].reasons == [] and .[1].reasons == []
    and (.[2].reasons | index("chain_broken")) != null
    and (.[3].reasons | index("chain_broken")) != null' <<< "$output" || fail "walk: $output"
}

@test "AC3: reordered rows break the chain" {
  { _line 1; _line 3; _line 2; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _walk
  jq -e '.[0].reasons == [] and (.[1].reasons | index("chain_broken")) != null
    and (.[2].reasons | index("chain_broken")) != null' <<< "$output" || fail "walk: $output"
}

@test "AC3: a deleted middle row breaks the chain" {
  { _line 1; _line 3; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _walk
  jq -e --arg i3 "$ID3" 'length == 2 and .[0].reasons == []
    and .[1].id == $i3 and .[1].reasons == ["chain_broken"]' <<< "$output" || fail "walk: $output"
}

@test "AC3: a non-JSON line or a reordered key set is malformed_row" {
  _set_line 2 'not json'
  _walk
  jq -e '.[1].reasons == ["malformed_row"] and .[1].id == null' <<< "$output" || fail "non-JSON: $output"

  cp "$UD_FIX/ledger.chain3.jsonl" "$LEDGER"
  _set_line 2 "$(_line 2 | jq -c '{answer, id, ts, actor, tool_use_id, question, scope, sha256, prev_sha256}')"
  _walk
  jq -e '.[1].reasons == ["malformed_row"]' <<< "$output" || fail "key order: $output"
}

@test "AC3: a replayed copy of a row is duplicate_id and duplicate_tool_use on both copies" {
  _line 3 >> "$LEDGER"
  _walk
  jq -e '(.[2].reasons | index("duplicate_id")) != null and (.[2].reasons | index("duplicate_tool_use")) != null
    and (.[3].reasons | index("duplicate_id")) != null and (.[3].reasons | index("chain_broken")) != null' <<< "$output" \
    || fail "walk: $output"
}

# --- AC3: the verifier -----------------------------------------------------------------------

@test "AC3: an intact chain verifies, and only then are question, answer and scope printed" {
  _verify "$ID1" DV0
  assert_success
  jq -e --arg id "$ID1" '.decision_ref == $id and .task_id == "DV0" and .valid == true and .reasons == []
    and .question == "Ship the ledger now?" and .answer == "Yes, ship it"
    and .scope == {worktask_id: "wt-ud-fixture", task_ids: ["DV0"], item: null}
    and .row_index == 1 and .chain_rows == 3' <<< "$output"
  _verify "$ID3" DV1 "macOS, Linux"
  assert_success
  jq -e '.valid == true and .row_index == 3' <<< "$output"
}

@test "AC3: an edit to the last row refuses every id in the ledger" {
  _set_line 3 "$(_line 3 | jq -c '.answer = "Linux"')"
  _assert_refused_all sha256_mismatch "$ID1" "$ID2" "$ID3"
}

@test "AC3: an inserted row refuses every id in the ledger" {
  { _line 1; _forged "ud-20260917T101630Z-2" "$S1"; _line 2; _line 3; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _assert_refused_all chain_broken "$ID1" "$ID2" "$ID3" "ud-20260917T101630Z-2"
}

@test "AC3: reordered rows refuse every id in the ledger" {
  { _line 1; _line 3; _line 2; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _assert_refused_all chain_broken "$ID1" "$ID2" "$ID3"
}

@test "AC3: a deleted middle row refuses the survivors, and its own id as not_found" {
  { _line 1; _line 3; } > "$LEDGER.new"
  mv "$LEDGER.new" "$LEDGER"
  _assert_refused_all chain_broken "$ID1" "$ID3"
  _assert_refused_all not_found "$ID2"
}

@test "ud_verify: a symlinked ledger, a missing ledger and a malformed id" {
  mv "$LEDGER" "$WD/real.jsonl"
  ln -s "$WD/real.jsonl" "$LEDGER"
  _assert_refused_all ledger_symlink "$ID1"
  rm -f "$LEDGER"
  _assert_refused_all not_found "$ID1"
  _verify "ud-nope" DV0
  assert_failure 2
  assert_output "{}"
  _verify "ud-20260917T101500Z-0" DV0
  assert_failure 2
}

# --- corroboration and the covering-row search ------------------------------------------------

@test "ud_audit_corroborates: a matching hook row passes; a wrong tool_use_id, a conflicting digest or a non-hook actor does not" {
  # shellcheck disable=SC2016  # expanded by the inner shell
  local probe='rc=0; ud_audit_corroborates "$AUDIT" "$@" || rc=$?; exit "$rc"'
  _lib "$probe" "$ID1" toolu_01UdFixture0001 "$C1"
  assert_success
  _lib "$probe" "$ID1" toolu_01UdOther0009 "$C1"
  assert_failure 1

  jq -c --arg id "$ID1" 'select(.subject == $id) | .metadata.row_sha256 = ("0" * 64)' "$UD_FIX/audit.chain3.jsonl" >> "$AUDIT"
  _lib "$probe" "$ID1" toolu_01UdFixture0001 "$C1"
  assert_failure 1

  jq -c --arg id "$ID1" 'select(.subject == $id) | .actor = "orchestrator"' "$UD_FIX/audit.chain3.jsonl" > "$AUDIT"
  _lib "$probe" "$ID1" toolu_01UdFixture0001 "$C1"
  assert_failure 1
}

@test "ud_find_covering: the newest valid unconsumed row answering the parked question; a consuming blocked_on row skips it; an edit anywhere finds nothing" {
  # shellcheck disable=SC2016  # expanded by the inner shell
  local probe='ud_find_covering "$STATE" "$LEDGER" "$AUDIT" "$1"'
  # Row 3 is newer and names DV0, but asks another question than the one DV0 is parked on.
  _lib "$probe" DV0
  assert_success
  assert_output "$ID1"

  jq -cn --arg dr "$ID1" '{ts: "2026-09-17T10:20:00Z", actor: "orchestrator", action: "blocked_on", subject: "DV0",
    result: "ok", task_id: "DV0", metadata: {kind: "user_decision", arm: "user_decision", leg: "resumed", decision_ref: $dr}}' >> "$AUDIT"
  _lib "$probe" DV0
  assert_success
  assert_output ""

  _lib "$probe" DR0
  assert_success
  assert_output ""

  cp "$UD_FIX/audit.chain3.jsonl" "$AUDIT"
  _set_line 2 "$(_line 2 | jq -c '.answer = "Write nothing"')"
  _lib "$probe" DV0
  assert_success
  assert_output ""
}

@test "R4: a sweep answer naming the parked task is not a cover; the row with the parked question and item is" {
  # shellcheck disable=SC2016  # expanded by the inner shell
  local probe='ud_find_covering "$STATE" "$LEDGER" "$AUDIT" "$1"'
  # DV1 parked on row 3's question, but the newest row naming DV1 is a sweep answer to another.
  jq '.tasks.DV1 = {status: "blocked", metadata: {stage: "DV", blocked_on: {kind: "user_decision",
      detail: {question: "Which targets must pass?", options: ["macOS", "Linux"], item: null}}}}' \
    "$STATE" > "$STATE.new" && mv "$STATE.new" "$STATE"
  _append_row "ud-20260917T101800Z-4" '"Should rung-3 answers be recorded?"' '"Record with empty task_ids"' \
    '{worktask_id: "wt-ud-fixture", task_ids: ["DV1"], item: "sw-DV1-3"}' toolu_01UdSweep0004
  _lib "$probe" DV1
  assert_success
  assert_output "$ID3"

  # The parked item must match too: a sweep-parked DV1 is not covered by a null-item row.
  jq '.tasks.DV1.metadata.blocked_on.detail.item = "sw-DV1-9"' "$STATE" > "$STATE.new" && mv "$STATE.new" "$STATE"
  _lib "$probe" DV1
  assert_success
  assert_output ""

  # A task that is not parked on a user_decision has no cover at all.
  jq '.tasks.DV1.status = "in_progress"' "$STATE" > "$STATE.new" && mv "$STATE.new" "$STATE"
  _lib "$probe" DV1
  assert_success
  assert_output ""
}
