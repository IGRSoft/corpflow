#!/usr/bin/env bats
# Tests for skills/worktask/scripts/blocked-on-dispatch.sh — route, batch and resume for a typed
# handoff.blocked_on return — against the fixtures under tests/fixtures/worktask/blocked-on/.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/blocked-on-dispatch.sh"
SELFTEST="skills/worktask/scripts/blocked-on-dispatch-selftest.sh"
LIB="skills/worktask/scripts/blocked-on-lib.sh"
PARK="skills/worktask/scripts/permission-park.sh"
PREFLIGHT="skills/worktask/scripts/autonomy-preflight.sh"
FIX="${FIXTURES}/worktask/blocked-on"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  STATE="$WD/.context/state.json"
  AUDIT="$WD/.context/logs/audit.jsonl"
  cp "$FIX/state.blocked-on.json" "$STATE"
  unset MILESTONE_MODE BLOCKED_ON_PREFLIGHT BLOCKED_ON_LAND
  # Every case, not only the peer ones: an unset MAILBOX_DIR would resolve the developer's own
  # mailbox and let a test write an ask into it.
  export MAILBOX_DIR="$WD/mailbox"
  export MAILBOX_NOW=1789646700
}

# _bo <subcommand> [args...] — the router against this test's ledger, stdout and stderr apart.
_bo() {
  local sub="$1"
  shift
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$sub" --state "$STATE" "$@"
}

_route() {
  _bo route --task-id "$1" --payload "$(cat "$FIX/$2.handoff.json")"
}

_rows() {
  [ -f "$AUDIT" ] || { echo 0; return 0; }
  jq -nR --arg a "${1:-blocked_on}" '[inputs | fromjson? | select(.action == $a)] | length' "$AUDIT"
}

_ledger_jq() {
  jq "$1" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

# _correction_state — swap in the AC1 ledger: DV0, DR0, QA0 and FN0 completed and chained through
# blocked_by, DC0 the correcting stage, DV1 a downstream task that never completed. The default
# fixture chains nothing, so there the re-open has no consumer to park and no dependent to settle.
_correction_state() {
  cp "$FIX/state.correction.json" "$STATE"
}

# _correction_payload <target_task> — the correction fixture retargeted, so the refusal cases
# differ from the accepted one in exactly the field under test and keep its marker finding.
_correction_payload() {
  jq -c --arg t "$1" '.blocked_on.detail.target_task = $t' "$FIX/correction.handoff.json"
}

# _settle <target> [changed] — the ledger op the orchestrator runs at the RE-OPENED TARGET's own
# completion boundary (D5), never this router. --changed is its documented test seam.
_settle() {
  local target="$1"
  shift
  run --separate-stderr bash "$PLUGIN_ROOT/skills/worktask/scripts/state-patch.sh" \
    --state "$STATE" --task-settle-stale "$target" "$@"
}

# _stub_preflight <check-id> <status> — a preflight double that reports one check, so the probe's
# verdict is the test's choice rather than the host's.
_stub_preflight() {
  local rj
  rj="$(jq -cn --arg c "$1" --arg s "$2" \
    '{version: 1, result: "fail", ran_at: "unknown", platforms: [], checks: [{id: $c, kind: "permission", status: $s, detail: "stub"}], tools_absent: []}')"
  stub_cmd preflight --stdout "result_json=$rj"
  export BLOCKED_ON_PREFLIGHT="$STUB_BIN/preflight"
}

_assert_audit_clean() {
  local needle
  [ -f "$AUDIT" ] || return 0
  for needle in "$@"; do
    ! grep -qF -- "$needle" "$AUDIT" || fail "audit.jsonl leaks: $needle"
  done
}

# _land_stub <landed-path> [list-landed-exit] — a BLOCKED_ON_LAND double so the artifact arm's
# landed verdict is this test's choice, not land-artifacts.sh's. --check-path refuses only a
# ../-prefixed path (dotdot), so a case controls unsafety by the path it sends; --list-landed
# ignores --tree/--state and answers from the one fixed path baked in here. Every call's mode word
# ($1) appends to land-calls.log, so a case can assert --list-landed was never reached.
_land_stub() {
  local landed="$1" rc="${2:-0}"
  LAND_STUB="$WD/land-stub.sh"
  LAND_CALLS="$WD/land-calls.log"
  : > "$LAND_CALLS"
  cat > "$LAND_STUB" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$LAND_CALLS"
case "\$1" in
  --check-path)
    case "\$2" in
      ../*) printf 'reason=dotdot\n'; exit 1 ;;
      *) exit 0 ;;
    esac
    ;;
  --list-landed)
    printf '%s\n' "$landed"
    exit $rc
    ;;
esac
EOF
  chmod +x "$LAND_STUB"
  export BLOCKED_ON_LAND="$LAND_STUB"
}

# Marker text for the user_decision cases: any of it in the audit log or a resume block is a leak.
UD_Q="UD-QUESTION-TEXT which release train carries the router?"
UD_A="UD-ANSWER-ALPHA"
UD_B="UD-ANSWER-BETA"

# _ud_payload — a user_decision return carrying the marker question and options.
_ud_payload() {
  jq -cn --arg q "$UD_Q" --arg a "$UD_A" --arg b "$UD_B" '{verdict: "blocked",
    blocked_on: {kind: "user_decision", detail: {question: $q, options: [$a, $b], recommended: $a},
                 resume_with: "decision_ref"}}'
}

# _ud_record <task_ids json> <answer> [no-audit] — appends one row to the ledger as the hook would:
# ordinal id, canonical [question,answer] digest, prev = sha256 of the previous line's bytes, and
# (unless no-audit) its user_decision_recorded audit row. Digests come from shasum, not the lib.
# Sets UD_ID to the new row's id.
_ud_record() {
  local ledger="$WD/.context/decisions.jsonl" n=1 prev=null sha row
  if [ -s "$ledger" ]; then
    n=$(($(wc -l < "$ledger") + 1))
    prev="\"$(tail -n 1 "$ledger" | tr -d '\n' | shasum -a 256 | cut -d' ' -f1)\""
  fi
  UD_ID="ud-20260917T101500Z-$n"
  sha="$(jq -jcn --arg q "$UD_Q" --arg a "$2" '[$q, $a]' | shasum -a 256 | cut -d' ' -f1)"
  row="$(jq -cn --arg id "$UD_ID" --arg tuid "toolu_01UdDispatch000$n" --arg q "$UD_Q" --arg a "$2" \
    --argjson t "$1" --arg sha "$sha" --argjson prev "$prev" '
    {id: $id, ts: "2026-09-17T10:15:00Z", actor: "hook:user-decision", tool_use_id: $tuid,
     question: $q, answer: $a, scope: {worktask_id: "wt-blocked-on-fixture", task_ids: $t, item: null},
     sha256: $sha, prev_sha256: $prev}')"
  printf '%s\n' "$row" >> "$ledger"
  if [ "${3:-}" = "no-audit" ]; then return 0; fi
  printf '%s' "$row" | jq -c '{ts: "2026-09-17T10:15:00Z", actor: "hook:user-decision",
    action: "user_decision_recorded", subject: .id, result: "ok", task_id: .scope.task_ids[0],
    metadata: {decision_id: .id, tool_use_id: .tool_use_id, row_sha256: .sha256, item: null}}' >> "$AUDIT"
}

# _tree — the ledger, audit log and ledger file as they stand, for write-nothing assertions.
_tree() {
  cat "$STATE"
  printf '\n--audit--\n'
  [ ! -f "$AUDIT" ] || cat "$AUDIT"
  printf '\n--ledger--\n'
  [ ! -f "$WD/.context/decisions.jsonl" ] || cat "$WD/.context/decisions.jsonl"
  [ ! -e "$WD/.context/decisions.jsonl.lock" ] || printf 'LOCK\n'
}

# --- route -------------------------------------------------------------------------

@test "route: a permission return names the permission arm and writes nothing; the park writes the one denied row" {
  local before
  before="$(cat "$STATE")"
  _route FN0 permission
  assert_success
  jq -e '.arm == "permission" and .kind == "permission" and .leg == null and .source == "blocked_on"
    and .parked == false and .audit_row_written == false' <<< "$output"
  [ "$(cat "$STATE")" = "$before" ] || fail "route changed the ledger for a permission need"
  [ ! -f "$AUDIT" ] || fail "route wrote an audit row for a permission need"

  run --separate-stderr bash "$PLUGIN_ROOT/$PARK" park --state "$STATE" --task-id FN0 \
    --detail "$(jq -c '.blocked_on.detail' "$FIX/permission.handoff.json")"
  assert_success
  [ "$(_rows permission_denied)" = 1 ] || fail "expected exactly one permission_denied row, got $(_rows permission_denied)"
  [ "$(_rows blocked_on)" = 0 ] || fail "the permission arm must write no blocked_on row"
}

@test "route: a correction parks the source natively and writes one opened row carrying no finding" {
  _route DC0 correction
  assert_success
  jq -e '.task_id == "DC0" and .kind == "correction" and .arm == "correction" and .leg == "opened"
    and .source == "blocked_on" and .parked == true and .audit_row_written == true
    and (has("fallback_from") | not) and (has("owner_issue") | not)
    and (has("decision_ref") | not)' <<< "$output"
  run jq -e --slurpfile h "$FIX/correction.handoff.json" \
    '.tasks.DC0.status == "blocked" and .tasks.DC0.metadata.blocked_on == $h[0].blocked_on' "$STATE"
  assert_success
  [ "$(_rows)" = 1 ] || fail "expected one blocked_on row, got $(_rows)"
  run jq -e 'select(.action == "blocked_on")
    | .actor == "orchestrator" and .subject == "DC0" and .task_id == "DC0" and .result == "blocked"
    and (.metadata | keys_unsorted) == ["kind", "arm", "leg"]
    and .metadata == {kind: "correction", arm: "correction", leg: "opened"}' "$AUDIT"
  assert_success
  _assert_audit_clean "CORRECTION-FINDING-TEXT" "evidence_ref" "blocked-on-dispatch.sh:120"
  # The finding travels on stdin, so it must not reach the ledger writer's own log either.
  [ ! -f "$WD/.context/logs/state-merge.log" ] \
    || ! grep -qF "CORRECTION-FINDING-TEXT" "$WD/.context/logs/state-merge.log" \
    || fail "state-merge.log leaks the finding"
}

@test "AC1: a documentation stage corrects a development stage — target re-opened, consumers stale" {
  _correction_state
  _route DC0 correction
  assert_success
  jq -e '.arm == "correction" and .leg == "opened" and .parked == true' <<< "$output"

  # R2: re-opened, round bumped, source stage stamped; the prior verdict and artifact survive.
  run jq -e '.tasks.DV0.status == "pending" and .tasks.DV0.metadata.fix_round == 1
    and .tasks.DV0.metadata.gate_from_stage == "DC" and .tasks.DV0.verdict == "ok"
    and .tasks.DV0.metadata.artifact == "development-0.md"' "$STATE"
  assert_success
  # R3: the finding verbatim, with the two refs that have no other channel into the brief.
  run jq -r '.tasks.DV0.metadata.gate_blockers[0]' "$STATE"
  assert_success
  assert_output --partial "CORRECTION-FINDING-TEXT: route exits 0 on a refused write"
  assert_output --partial "evidence_ref: skills/worktask/scripts/blocked-on-dispatch.sh:120"
  assert_output --partial "source_task: DC0"
  [ "$(jq -r '.tasks.DV0.metadata.gate_blockers | length' "$STATE")" = 1 ]

  # R4/D3: transitive completed consumers parked, keeping verdict and artifact; the source, the
  # side-effect stage (FN0) and the downstream task that never completed (DV1) are untouched.
  run jq -e '.tasks.DR0.status == "stale" and .tasks.DR0.verdict == "ok"
    and .tasks.DR0.metadata.artifact == "review-0.md"
    and (.tasks.DR0 | has("rework_pending") | not)
    and .tasks.QA0.status == "stale" and .tasks.QA0.verdict == "ok"
    and .tasks.FN0.status == "completed" and .tasks.DV1.status == "in_progress"
    and .tasks.PL0.status == "completed"
    and .tasks.DC0.status == "blocked"' "$STATE"
  assert_success
  # R7/AC8: one opened leg, enums and ids only.
  run jq -sc '[.[] | select(.action == "blocked_on") | [.result, .metadata.leg]]' "$AUDIT"
  assert_output '[["blocked","opened"]]'
  _assert_audit_clean "CORRECTION-FINDING-TEXT" "route exits 0 on a refused write"
}

@test "route: re-routing a still-open correction writes no second opened row and bumps no round" {
  _correction_state
  _route DC0 correction
  assert_success
  _route DC0 correction
  assert_success
  jq -e '.arm == "correction" and .leg == "opened" and .parked == true
    and .audit_row_written == false' <<< "$output"
  [ "$(_rows)" = 1 ] || fail "expected one blocked_on row, got $(_rows)"
  run jq -e '.tasks.DV0.metadata.fix_round == 1 and .tasks.DV0.status == "pending"' "$STATE"
  assert_success
}

@test "route: a correction target that is absent, is the source, or is not completed refuses and writes nothing" {
  local before spec want
  _correction_state
  before="$(cat "$STATE")"
  for spec in 'DV9|names no task in this ledger' \
    'DC0|is tasks.DC0 itself' \
    'DV1|tasks.DV1 is in_progress; a correction re-opens a completed task only'; do
    want="${spec#*|}"
    _bo route --task-id DC0 --payload "$(_correction_payload "${spec%%|*}")"
    [ "$status" -eq 1 ] || fail "${spec%%|*}: exit $status, want 1"
    [[ "$stderr" == *"$want"* ]] || fail "${spec%%|*}: stderr lacks '$want': $stderr"
    [ "$(printf '%s\n' "$stderr" | grep -c '^fail:')" = 1 ] || fail "${spec%%|*}: want exactly one fail: line"
  done
  [ "$(cat "$STATE")" = "$before" ] || fail "a refused correction changed the ledger"
  [ ! -f "$AUDIT" ] || fail "a refused correction wrote an audit row"

  # The same refusal after a correction landed: the target is `pending`, so a SECOND, different
  # correction against it is refused rather than bumping the round twice.
  _route DC0 correction
  assert_success
  before="$(cat "$STATE")"
  _bo route --task-id QA0 --payload "$(_correction_payload DV0)"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"tasks.DV0 is pending"* ]] || fail "stderr: $stderr"
  [ "$(cat "$STATE")" = "$before" ] || fail "a refused correction changed the ledger"
}

@test "AC2: a stale dependent re-verifies on a cited change and stands on an uncited one" {
  _correction_state
  _route DC0 correction
  assert_success
  run jq -e '.tasks.DR0.status == "stale" and .tasks.QA0.status == "stale"' "$STATE"
  assert_success

  # DR0 cites the lib (anchored, through metadata.consumes); QA0 cites the dispatch bats (line-
  # suffixed, through facts.files_read). One settle call therefore exercises both directions and
  # both citation sources, with D2's normalisation on each.
  _settle DV0 --changed "skills/worktask/scripts/blocked-on-lib.sh"
  assert_success
  jq -e '.settled == [{task: "DR0", to: "pending", reason: "cited-file-changed"},
                      {task: "QA0", to: "completed", reason: "no-cited-file-changed"}]' <<< "$output"
  run jq -e '.tasks.DR0.status == "pending" and .tasks.QA0.status == "completed"
    and .tasks.QA0.verdict == "ok"' "$STATE"
  assert_success

  # A change set left empty only BY the .context/ exclusion is known, not unknown: the target
  # rewrote its own artifact and nothing else, so the dependent's earlier result stands.
  _ledger_jq '.tasks.DR0.status = "stale"'
  _settle DV0 --changed ".context/development-0.md"
  assert_success
  jq -e '.settled == [{task: "DR0", to: "completed", reason: "no-cited-file-changed"}]' <<< "$output"
  run jq -e '.tasks.DR0.status == "completed" and .tasks.DR0.verdict == "ok"' "$STATE"
  assert_success
}

@test "route: a native user_action row carries a redacted head of at most 4 tokens, never the request or command" {
  _route DV1 user_action
  assert_success
  jq -e '.arm == "user_action" and .leg == "requested" and (has("fallback_from") | not)' <<< "$output"
  run jq -e 'select(.action == "blocked_on")
    | (.metadata | keys_unsorted) == ["kind", "arm", "leg", "command_head", "truncated"]
    and (.metadata.command_head | split(" ") | length) <= 4
    and (.metadata.truncated | type) == "boolean"' "$AUDIT"
  assert_success
  _assert_audit_clean "hunter2hunter2" "/Users/alice" "Boot the iPhone 16" \
    "$(jq -r '.blocked_on.detail.command' "$FIX/user_action.handoff.json")"
  [ ! -f "$WD/.context/logs/state-merge.log" ] || ! grep -qF "hunter2hunter2" "$WD/.context/logs/state-merge.log" \
    || fail "state-merge.log leaks the need's command"
}

@test "route: a host_environment probe that passes clears the need, writes probed with decision_ref, and resumes" {
  _stub_preflight gh-pr-create pass
  _route FN0 host_environment
  assert_success
  jq -e '.arm == "host_environment" and .leg == "probed" and .parked == false
    and .decision_ref == "blocked_on:FN0:host_environment:1"
    and .resume_block.decision_ref == .decision_ref and .resume_block.do_not_rerun == true
    and (.resume_block.instruction | contains("Do not re-run any step that already completed."))' <<< "$output"
  run jq -e '.tasks.FN0.status == "in_progress" and .tasks.FN0.metadata.blocked_on == null' "$STATE"
  assert_success
  run jq -e 'select(.action == "blocked_on") | .result == "ok"
    and .metadata == {kind: "host_environment", arm: "host_environment", leg: "probed", decision_ref: "blocked_on:FN0:host_environment:1"}' "$AUDIT"
  assert_success
  stub_log --argv preflight | grep -qx -- '--platform' || fail "the probe did not pass the ledger platforms"
  ! stub_log --argv preflight | grep -qx -- '--harness' || fail "--harness is only for git-reset-hard"
  _assert_audit_clean "HOST-OBSERVED-TEXT"
}

@test "route: a host_environment probe that still fails writes probed, then parks as a user_action with no owner_issue" {
  _stub_preflight gh-pr-create fail
  _route FN0 host_environment
  assert_success
  jq -e '.arm == "user_action" and .leg == "requested" and .fallback_from == "host_environment"
    and (has("owner_issue") | not) and .parked == true and .audit_row_written == true' <<< "$output"
  run jq -e '.tasks.FN0.status == "blocked" and .tasks.FN0.metadata.blocked_on.kind == "host_environment"' "$STATE"
  assert_success
  run jq -sc '[.[] | select(.action == "blocked_on") | .metadata.leg]' "$AUDIT"
  assert_output '["probed","requested"]'
  _assert_audit_clean "HOST-OBSERVED-TEXT"
}

@test "route: the real preflight skipping under a megatask run proves nothing, so the need parks" {
  run --separate-stderr env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT" route --state "$STATE" \
    --task-id FN0 --payload "$(cat "$FIX/host_environment.handoff.json")"
  assert_success
  jq -e '.arm == "user_action" and .fallback_from == "host_environment" and .parked == true' <<< "$output"
  [ -r "$PLUGIN_ROOT/$PREFLIGHT" ]
}

@test "route: git-reset-hard re-probes with --harness" {
  _stub_preflight git-reset-hard pass
  _bo route --task-id FN0 --payload \
    '{"verdict":"blocked","blocked_on":{"kind":"host_environment","detail":{"check":"git-reset-hard","observed":"no rule"},"resume_with":"decision_ref"}}'
  assert_success
  stub_log --argv preflight | grep -qx -- '--harness' || fail "git-reset-hard must add --harness"
}

@test "route: each invalid return exits 1 with one named fail: line and writes nothing" {
  local spec name want before
  before="$(cat "$STATE")"
  for spec in 'invalid-unknown-kind|fail: blocked_on.kind "coffee_break" is not one of' \
    'invalid-unknown-resume-with|fail: blocked_on.resume_with "carrier_pigeon" is not one of' \
    'invalid-missing-detail|fail: blocked_on.detail is missing or empty'; do
    name="${spec%%|*}" want="${spec#*|}"
    _route QA0 "$name"
    [ "$status" -eq 1 ] || fail "$name: exit $status, want 1"
    [[ "$stderr" == *"$want"* ]] || fail "$name: stderr lacks '$want': $stderr"
    [ "$(printf '%s\n' "$stderr" | grep -c '^fail:')" = 1 ] || fail "$name: want exactly one fail: line"
  done
  _bo route --task-id QA0 --payload '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0"},"resume_with":"artifact_path"}}'
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"missing required key: path"* ]]
  _bo route --task-id QA0 --payload '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"x"},"resume_with":"reply_ref"}}'
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"must be artifact_path"* ]]
  [ "$(cat "$STATE")" = "$before" ] || fail "an invalid return changed the ledger"
  [ ! -f "$AUDIT" ] || fail "an invalid return wrote an audit row"
}

@test "route: the legacy cross_session_ask alias routes as peer_session; blocked_on wins when both are present" {
  _route DR0 legacy-cross-session-ask
  assert_success
  jq -e '.kind == "peer_session" and .source == "cross_session_ask" and .arm == "peer_session"
    and .parked == true and (has("fallback_from") | not)
    and (.ask_id | test("^ask-[0-9]{8}t[0-9]{6}z-[0-9a-f]{12}$"))
    and .message == ("mailbox ask " + .ask_id)' <<< "$output"
  run jq -e '.tasks.DR0.metadata.blocked_on == {kind: "peer_session",
    detail: {to: "backend-session", question: "Which base branch does the API change target?"}, resume_with: "reply_ref"}' "$STATE"
  assert_success
  _bo route --task-id QA0 --payload "$(jq -c '. + {cross_session_ask: {to: "x", question: "y"}}' "$FIX/artifact.handoff.json")"
  assert_success
  jq -e '.kind == "artifact" and .source == "blocked_on"' <<< "$output"
}

@test "route: a peer_session return writes the request, parks and records ask_id; the deadline is clamped; a retry reuses it" {
  _route DR0 peer_session
  assert_success
  local ask
  ask="$(jq -r '.ask_id' <<< "$output")"
  # The fixture asks for 2026-09-20T00:00:00Z, more than 24 h out, so the clamp caps it at
  # MAILBOX_NOW + 86400. A stage cannot park a task beyond a day by naming a far deadline.
  jq -e '.arm == "peer_session" and .parked == true and .audit_row_written == false and .leg == null
    and .deadline == "2026-09-18T12:05:00Z"' <<< "$output"
  run jq -e --arg a "$ask" '.tasks.DR0.status == "blocked" and .tasks.DR0.metadata.ask_id == $a' "$STATE"
  assert_success
  run jq -e --arg a "$ask" '.ask_id == $a and .from_task == "DR0" and .to == "backend-session"
    and (has("options") | not) and .reply_schema == {type: "string", minLength: 1, maxLength: 2000}' \
    "$MAILBOX_DIR/requests/$ask.json"
  assert_success
  [ "$(_rows)" = 0 ] || fail "the route itself must write no leg row"

  _route DR0 peer_session
  assert_success
  jq -e --arg a "$ask" '.reused == true and .ask_id == $a' <<< "$output"
  [ "$(find "$MAILBOX_DIR/requests" -name 'ask-*.json' | wc -l | tr -d ' ')" = 1 ] \
    || fail "a retried return minted a second request"
}

@test "route: an unusable mailbox falls back to user_action and clears any stale ask_id" {
  ln -s /nonexistent "$WD/mailbox"
  # A leftover id from an earlier ask on this task: left in place it would make the next turn
  # re-announce that old question, and keep the need out of `batch` so nobody is asked at all.
  _ledger_jq '.tasks.DR0.metadata.ask_id = "ask-20260917t090000z-aaaaaaaaaaaa"'
  _route DR0 peer_session
  assert_success
  jq -e '.kind == "peer_session" and .arm == "user_action" and .leg == "requested" and .parked == true
    and .fallback_from == "peer_session" and .ask_id == null and (has("owner_issue") | not)' <<< "$output"
  run jq -e '.tasks.DR0.status == "blocked" and (.tasks.DR0.metadata.ask_id? // null) == null' "$STATE"
  assert_success
  _assert_audit_clean "Which base branch does the API change target?"
}

@test "route: usage errors and a missing ledger exit 2" {
  _bo route --task-id 'DV1;id' --payload '{}'
  [ "$status" -eq 2 ]
  _bo route --task-id DV1
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" route --state "$WD/nope.json" --task-id DV1 \
    --payload "$(cat "$FIX/user_action.handoff.json")"
  [ "$status" -eq 2 ]
}

@test "route: artifact — a path the ladder refuses parks the fallback and never reads the landed set" {
  _land_stub "../x" 0
  _bo route --task-id QA0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"../x"},"resume_with":"artifact_path"}}'
  assert_success
  jq -e '.arm == "user_action" and .leg == "requested" and .fallback_from == "artifact"
    and (has("owner_issue") | not) and .parked == true' <<< "$output"
  grep -qx -- "--check-path" "$LAND_CALLS" || fail "the path must go through --check-path"
  ! grep -qx -- "--list-landed" "$LAND_CALLS" || fail "a refused path must not reach --list-landed"
  run jq -sc '[.[] | select(.action == "blocked_on") | .metadata.leg]' "$AUDIT"
  assert_output '["requested"]'
}

@test "route: artifact — a producer_task that is not a task id parks the fallback without calling LAND" {
  _land_stub "docs/out.md" 0
  _bo route --task-id QA0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"nope","path":"docs/out.md"},"resume_with":"artifact_path"}}'
  assert_success
  jq -e '.arm == "user_action" and .fallback_from == "artifact" and .parked == true' <<< "$output"
  [ ! -s "$LAND_CALLS" ] || fail "a bad producer_task must not reach the LAND double at all"
}

@test "route: artifact — no workspace_path parks as a user_action fallback without checking the landed set" {
  _land_stub "docs/out.md" 0
  _bo route --task-id PL0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"docs/out.md"},"resume_with":"artifact_path"}}'
  assert_success
  jq -e '.kind == "artifact" and .arm == "user_action" and .leg == "requested" and .fallback_from == "artifact"
    and (has("owner_issue") | not) and .parked == true and .audit_row_written == true' <<< "$output"
  run jq -e '.tasks.PL0.status == "blocked" and .tasks.PL0.metadata.blocked_on.kind == "artifact"' "$STATE"
  assert_success
  run jq -e 'select(.action == "blocked_on")
    | .metadata == {kind: "artifact", arm: "user_action", leg: "requested", fallback_from: "artifact"}' "$AUDIT"
  assert_success
  ! grep -qx -- "--list-landed" "$LAND_CALLS" || fail "no workspace_path must not reach --list-landed"
}

@test "route: artifact — a path already landed in its tree claims the task and resumes" {
  _land_stub "docs/out.md" 0
  _bo route --task-id QA0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"docs/out.md"},"resume_with":"artifact_path"}}'
  assert_success
  jq -e '.task_id == "QA0" and .kind == "artifact" and .arm == "artifact" and .leg == "landed"
    and .source == "blocked_on" and .parked == false and .audit_row_written == true
    and .decision_ref == "blocked_on:QA0:artifact:1"
    and .resume_block.artifact_path == "docs/out.md" and .resume_block.do_not_rerun == true
    and (has("fallback_from") | not) and (has("owner_issue") | not)' <<< "$output"
  run jq -e '.tasks.QA0.status == "in_progress" and .tasks.QA0.metadata.blocked_on == null' "$STATE"
  assert_success
  run jq -e 'select(.action == "blocked_on") | .result == "ok"
    and .metadata == {kind: "artifact", arm: "artifact", leg: "landed", decision_ref: "blocked_on:QA0:artifact:1"}' "$AUDIT"
  assert_success
}

@test "route: artifact — a strict --list-landed refusal is treated as not landed and parks the fallback" {
  _land_stub "docs/out.md" 1
  _bo route --task-id QA0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"docs/out.md"},"resume_with":"artifact_path"}}'
  assert_success
  jq -e '.arm == "user_action" and .leg == "requested" and .fallback_from == "artifact"
    and (has("owner_issue") | not) and .parked == true' <<< "$output"
  run jq -sc '[.[] | select(.action == "blocked_on") | .metadata.leg]' "$AUDIT"
  assert_output '["requested"]'
}

# --- batch -------------------------------------------------------------------------

@test "batch: parked needs become one prompt; only a native user_action offers a ! line" {
  _route DV1 user_action
  _route DC0 correction
  _route DR0 peer_session
  _route FN0 permission
  _bo batch
  assert_success
  # DR0 holds an open peer ask: another session owes the answer, so the user is not asked for it.
  jq -e '.mode == "ask" and ([.needs[].task_id] | sort) == ["DC0", "DV1"]
    and all(.needs[]; .cwd == "/tmp/wt")
    and (.needs[] | select(.task_id == "DV1") | .arm == "user_action" and .resume_leg == "verified")
    and (.needs[] | select(.task_id == "DC0") | .arm == "correction" and .resume_leg == "closed"
         and (has("fallback_from") | not) and (has("owner_issue") | not) and .command == ""
         and .request == "DC0 found the defect below in another task\u0027s work. Answer done once it is fixed.")
    and (.needs[] | select(.task_id == "DV1") | (has("fallback_from") | not) and .truncated == false)
    and (.payloads | length) == 1 and (.payloads[0].questions | length) == 2
    and all(.payloads[0].questions[]; [.options[].label] == ["done", "stop here"])' <<< "$output"
  jq -e '[.needs[].task_id, .payloads[0].questions[].header] | index("DR0") == null' <<< "$output"
  jq -e '.payloads[0].questions[] | select(.header == "DV1") | .question | contains("! xcrun simctl boot")' <<< "$output"
  jq -e '[.payloads[0].questions[] | select(.header != "DV1") | .question | contains("! ")] | any | not' <<< "$output"
  jq -e '.payloads[0].questions[] | select(.header == "DC0") | .question | contains("finding: CORRECTION-FINDING-TEXT")' <<< "$output"
}

@test "batch: under a megatask per-issue run the boundary parks the issue with one redacted escalation row" {
  _ledger_jq '.tasks.PL0.metadata.megatask_group = "milestone-1"'
  printf '%s' '{"version":"2.0","execution":{"status":"in_progress","retry_count":0}}' > "$WD/workspace.json"
  _route DV1 user_action
  _route DC0 correction
  _bo batch --boundary DV1
  assert_success
  jq -e '.mode == "megatask_park" and .payloads == [] and .park.workspace_written == true
    and .park.audit_row_written == true' <<< "$output"
  _bo batch --boundary DV1
  assert_success
  [ "$(_rows escalation_parked)" = 1 ] || fail "expected one escalation_parked row, got $(_rows escalation_parked)"
  run jq -e 'select(.action == "escalation_parked") | .subject == "DV1" and .metadata.kind == "user_action"
    and ([.metadata.escalated[] | select(.kind == "user_action") | keys_unsorted] == [["kind", "command_head", "truncated"]])
    and ([.metadata.escalated[] | select(.kind == "correction")] == [{kind: "correction"}])' "$AUDIT"
  assert_success
  run jq -e '.execution.status == "failed" and .execution.reason == "parked_escalation"' "$WD/workspace.json"
  assert_success
  _assert_audit_clean "hunter2hunter2" "CORRECTION-FINDING-TEXT" "Boot the iPhone 16"
}

# --- resume ------------------------------------------------------------------------

@test "resume: the correction closing leg clears the park, writes closed and hands back the target artifact" {
  _correction_state
  _route DC0 correction
  _bo resume --task-id DC0 --leg requested
  [ "$status" -eq 1 ]
  _bo resume --task-id DC0 --leg closed
  assert_success
  jq -e '.cleared == true and .audit_row_written == true
    and .resume_block.kind == "correction" and .resume_block.arm == "correction"
    and .resume_block.leg == "closed"
    and .resume_block.decision_ref == "blocked_on:DC0:correction:1"
    and .resume_block.resume_with == "artifact_path" and .resume_block.artifact_path == "development-0.md"
    and .resume_block.do_not_rerun == true' <<< "$output"
  run jq -e '.tasks.DC0.status == "in_progress" and .tasks.DC0.metadata.blocked_on == null' "$STATE"
  assert_success
  run jq -sc '[.[] | select(.action == "blocked_on") | [.result, .metadata.leg, .metadata.decision_ref]]' "$AUDIT"
  assert_output '[["blocked","opened",null],["ok","closed","blocked_on:DC0:correction:1"]]'
  # The resume settles nothing: the dependents parked by the route stay stale until the RE-OPENED
  # TARGET completes and the orchestrator runs --task-settle-stale there (D5).
  run jq -e '.tasks.DR0.status == "stale" and .tasks.QA0.status == "stale"' "$STATE"
  assert_success

  # A second round: the target has to complete again before another correction can re-open it,
  # and that round gets its own ref and its own fix_round.
  _ledger_jq '.tasks.DV0.status = "completed"'
  _route DC0 correction
  [ "$(jq -r '.audit_row_written' <<< "$output")" = true ] || fail "a need raised again after resume must write a new opened row"
  run jq -e '.tasks.DV0.metadata.fix_round == 2' "$STATE"
  assert_success
  _bo resume --task-id DC0 --leg closed
  assert_success
  [ "$(jq -r '.resume_block.decision_ref' <<< "$output")" = "blocked_on:DC0:correction:2" ]
  _assert_audit_clean "CORRECTION-FINDING-TEXT"
}

@test "resume: a correction answered in batch still resumes on the user_action closing leg" {
  _route DC0 correction
  assert_success
  _bo resume --task-id DC0 --leg verified
  assert_success
  jq -e '.cleared == true and .resume_block.arm == "user_action" and .resume_block.leg == "verified"
    and .resume_block.resume_with == "artifact_path"
    and .resume_block.artifact_path == "development-0.md"
    and .resume_block.decision_ref == "blocked_on:DC0:correction:1"' <<< "$output"
  run jq -e 'select(.action == "blocked_on" and .metadata.leg == "verified")
    | .metadata == {kind: "correction", arm: "user_action", leg: "verified",
                    fallback_from: "correction", decision_ref: "blocked_on:DC0:correction:1"}' "$AUDIT"
  assert_success
}

@test "resume: a task not parked on a non-permission need is refused and the ledger is unchanged" {
  local before
  before="$(cat "$STATE")"
  _bo resume --task-id DV1 --leg verified
  [ "$status" -eq 1 ]
  _ledger_jq '.tasks.FN0.metadata.blocked_on = {kind: "permission", detail: {tool: "Bash", command: "x", classifier_reason: "r", allow_rule: ""}, resume_with: "decision_ref"} | .tasks.FN0.status = "blocked"'
  before="$(cat "$STATE")"
  _bo resume --task-id FN0 --leg verified
  [ "$status" -eq 1 ]
  [ "$(cat "$STATE")" = "$before" ]
  [ "$(_rows)" = 0 ]
}

@test "resume: artifact --leg landed refuses until the path lands, then claims and clears it" {
  local before
  _land_stub "" 1
  _bo route --task-id DR0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"docs/x.md"},"resume_with":"artifact_path"}}'
  assert_success
  jq -e '.arm == "user_action" and .fallback_from == "artifact"' <<< "$output"

  before="$(cat "$STATE")"
  _bo resume --task-id DR0 --leg landed
  [ "$status" -eq 1 ]
  [ "$(cat "$STATE")" = "$before" ] || fail "an un-landed --leg landed resume changed the ledger"
  [ "$(_rows)" = 1 ] || fail "an un-landed --leg landed resume must write no new row"

  _land_stub "docs/x.md" 0
  _bo resume --task-id DR0 --leg landed
  assert_success
  jq -e '.cleared == true and .audit_row_written == true
    and .resume_block.kind == "artifact" and .resume_block.arm == "artifact" and .resume_block.leg == "landed"
    and .resume_block.decision_ref == "blocked_on:DR0:artifact:1"
    and .resume_block.artifact_path == "docs/x.md" and .resume_block.do_not_rerun == true' <<< "$output"
  run jq -e '.tasks.DR0.status == "in_progress" and .tasks.DR0.metadata.blocked_on == null' "$STATE"
  assert_success
  run jq -sc '[.[] | select(.action == "blocked_on") | [.result, .metadata.leg, .metadata.decision_ref]]' "$AUDIT"
  assert_output '[["blocked","requested",null],["ok","landed","blocked_on:DR0:artifact:1"]]'
}

@test "resume: artifact --leg verified still resumes via the user_action fallback, with no owner_issue" {
  _land_stub "" 1
  _bo route --task-id DC0 --payload \
    '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"docs/y.md"},"resume_with":"artifact_path"}}'
  assert_success

  _bo resume --task-id DC0 --leg landed
  [ "$status" -eq 1 ] || fail "the wrong leg must not resume an un-landed artifact need"

  _bo resume --task-id DC0 --leg verified
  assert_success
  jq -e '.cleared == true and .audit_row_written == true
    and .resume_block.kind == "artifact" and .resume_block.arm == "user_action" and .resume_block.leg == "verified"
    and .resume_block.resume_with == "artifact_path" and .resume_block.artifact_path == "docs/y.md"
    and .resume_block.decision_ref == "blocked_on:DC0:artifact:1"' <<< "$output"
  run jq -e 'select(.action == "blocked_on" and .metadata.leg == "verified")
    | .metadata == {kind: "artifact", arm: "user_action", leg: "verified", fallback_from: "artifact",
                     decision_ref: "blocked_on:DC0:artifact:1"}' "$AUDIT"
  assert_success
}

# --- user_decision: the landed native arm (#395) -----------------------------------

@test "route: a user_decision return parks natively with one asked row, no fallback fields and no question text" {
  _route DV1 user_decision
  assert_success
  jq -e '.task_id == "DV1" and .kind == "user_decision" and .arm == "user_decision" and .leg == "asked"
    and .source == "blocked_on" and .parked == true and .audit_row_written == true
    and (has("fallback_from") | not) and (has("owner_issue") | not) and (has("decision_ref") | not)' <<< "$output"
  run jq -e --slurpfile h "$FIX/user_decision.handoff.json" \
    '.tasks.DV1.status == "blocked" and .tasks.DV1.metadata.blocked_on == $h[0].blocked_on' "$STATE"
  assert_success
  [ "$(_rows)" = 1 ] || fail "expected one blocked_on row, got $(_rows)"
  run jq -e 'select(.action == "blocked_on")
    | .actor == "orchestrator" and .subject == "DV1" and .result == "blocked"
    and .metadata == {kind: "user_decision", arm: "user_decision", leg: "asked"}' "$AUDIT"
  assert_success

  _route DV1 user_decision
  assert_success
  jq -e '.audit_row_written == false' <<< "$output"
  [ "$(_rows)" = 1 ] || fail "a re-route wrote a second asked row"
  _assert_audit_clean "Ship the router behind a flag?" "no-flag"
}

@test "batch: user_decision needs sharing one question ask it once, verbatim and unfenced, headed by the lowest task id" {
  _route QA0 user_decision
  _route DV1 user_decision
  _route DR0 user_decision
  _bo route --task-id FN0 --payload "$(_ud_payload)"
  _route DC0 correction
  _bo batch
  assert_success
  jq -e '.mode == "ask"
    and ([.needs[] | select(.kind == "user_decision") | .task_id] | sort) == ["DR0", "DV1", "FN0", "QA0"]
    and all(.needs[] | select(.kind == "user_decision"); .arm == "user_decision" and .resume_leg == "resumed")
    and (.payloads | length) == 1 and (.payloads[0].questions | length) == 3' <<< "$output" || fail "batch: $output"
  jq -e '[.payloads[0].questions[] | select(.question == "Ship the router behind a flag?")]
    | length == 1 and .[0].header == "DR0" and .[0].multiSelect == false
    and .[0].options == [{label: "flag", description: "Recommended"}, {label: "no-flag", description: "Offered by DR0"}]' <<< "$output" \
    || fail "grouped question: $output"
  jq -e --arg q "$UD_Q" --arg a "$UD_A" --arg b "$UD_B" '[.payloads[0].questions[] | select(.question == $q)]
    | length == 1 and .[0].header == "FN0"
    and .[0].options == [{label: $a, description: "Recommended"}, {label: $b, description: "Offered by FN0"}]' <<< "$output" \
    || fail "second question: $output"
  jq -e '[.payloads[0].questions[] | select(.header == "DR0" or .header == "FN0") | .question | contains("`")] | any | not' <<< "$output" \
    || fail "a user_decision question was fenced"
  jq -e '.payloads[0].questions[] | select(.header == "DC0") | [.options[].label] == ["done", "stop here"]' <<< "$output"
}

@test "resume: a user_decision with no valid covering row exits 1 and writes nothing" {
  local before
  _bo route --task-id DV1 --payload "$(_ud_payload)"
  assert_success

  before="$(_tree)"
  _bo resume --task-id DV1 --leg resumed
  [ "$status" -eq 1 ] || fail "no ledger: want exit 1, got $status"
  [ "$(_tree)" = "$before" ] || fail "a refused resume (no ledger) wrote"

  _ud_record '["DR0"]' "$UD_A"
  _ud_record '["DV1"]' "$UD_A" no-audit
  before="$(_tree)"
  _bo resume --task-id DV1 --leg resumed
  [ "$status" -eq 1 ] || fail "uncovered/uncorroborated: want exit 1, got $status"
  [[ "$stderr" == *"no valid, unconsumed user-decision row covers tasks.DV1"* ]] || fail "stderr: $stderr"
  _bo resume --task-id DV1 --leg resumed --decision-ref "$UD_ID"
  [ "$status" -eq 1 ] || fail "an uncorroborated explicit ref: want exit 1, got $status"
  _bo resume --task-id DV1 --leg resumed --decision-ref "ud-20260917T101500Z-1"
  [ "$status" -eq 1 ] || fail "a ref scoped to DR0: want exit 1, got $status"
  _bo resume --task-id DV1 --leg resumed --decision-ref "ud-20260917T101500Z-9"
  [ "$status" -eq 1 ] || fail "an absent ref: want exit 1, got $status"
  _bo resume --task-id DV1 --leg verified
  [ "$status" -eq 1 ] || fail "a non-closing leg: want exit 1, got $status"
  [ "$(_tree)" = "$before" ] || fail "a refused resume wrote"
  [ -z "$output" ] || fail "a refused resume printed to stdout: $output"
  run jq -e '.tasks.DV1.status == "blocked" and .tasks.DV1.metadata.blocked_on.kind == "user_decision"' "$STATE"
  assert_success
}

@test "resume: a valid hook row clears the need, writes resumed with its ud- ref, and relays no answer text" {
  _bo route --task-id DV1 --payload "$(_ud_payload)"
  assert_success
  _ud_record '["DV1"]' "$UD_A"
  local id="$UD_ID"

  _bo resume --task-id DV1 --leg resumed
  assert_success
  jq -e --arg id "$id" '.cleared == true and .audit_row_written == true
    and .resume_block.task_id == "DV1" and .resume_block.kind == "user_decision"
    and .resume_block.arm == "user_decision" and .resume_block.leg == "resumed"
    and .resume_block.decision_ref == $id and .resume_block.resume_with == "decision_ref"
    and .resume_block.do_not_rerun == true
    and (.resume_block.instruction | contains("--verify-decision " + $id + " --task-id DV1"))' <<< "$output" \
    || fail "resume: $output"
  local needle
  for needle in "$UD_Q" "$UD_A" "$UD_B"; do
    [[ "$output" != *"$needle"* ]] || fail "the resume output relays need or answer text: $needle"
  done
  run jq -e '.tasks.DV1.status == "in_progress" and .tasks.DV1.metadata.blocked_on == null' "$STATE"
  assert_success
  run jq -sc '[.[] | select(.action == "blocked_on") | .metadata.leg]' "$AUDIT"
  assert_output '["asked","resumed"]'
  run jq -e --arg id "$id" 'select(.action == "blocked_on" and .metadata.leg == "resumed")
    | .result == "ok" and .subject == "DV1"
    and .metadata == {kind: "user_decision", arm: "user_decision", leg: "resumed", decision_ref: $id}' "$AUDIT"
  assert_success
  _assert_audit_clean "$UD_Q" "$UD_A" "$UD_B"

  # The row is consumed: the same need raised again does not resume on it a second time.
  _bo route --task-id DV1 --payload "$(_ud_payload)"
  assert_success
  jq -e '.audit_row_written == true' <<< "$output"
  _bo resume --task-id DV1 --leg resumed
  [ "$status" -eq 1 ] || fail "a consumed row resumed again: exit $status, $output"
}

@test "resume: --decision-ref picks a named covering row over the newest one" {
  _bo route --task-id DV1 --payload "$(_ud_payload)"
  assert_success
  _ud_record '["DV1"]' "$UD_A"
  local first="$UD_ID"
  _ud_record '["DV1"]' "$UD_B"
  _bo resume --task-id DV1 --leg resumed --decision-ref "$first"
  assert_success
  jq -e --arg id "$first" '.resume_block.decision_ref == $id' <<< "$output"
}

# --- static contracts --------------------------------------------------------------

@test "AC6: no audit row call in the router passes need text as metadata" {
  run grep -nE -- '--meta(-kv)? [^|]*(\.detail|\$cmd|request|question|finding|observed)' "$PLUGIN_ROOT/$SCRIPT"
  [ "$status" -eq 1 ] || fail "an audit row call passes need text: $output"
  run grep -nE 'blocked-on-lib\.sh' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ -r "$PLUGIN_ROOT/$LIB" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  [ -r "$PLUGIN_ROOT/$SELFTEST" ]
  run_script_env "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
