#!/usr/bin/env bats
# Tests for hooks/user-decision-record.sh — PostToolUse AskUserQuestion appends one hash-chained
# ledger row per answered, scoped question; PreToolUse Write|Edit|Bash denies a ledger write.
#
# The ledger name is materialised only inside each test's temp dir: no fixture file carries it
# (AD8), and the fixture payloads hold __TRANSCRIPT__/__CTX__ placeholders filled in per test.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/user-decision-record.sh"
SELFTEST="hooks/lib/user-decision-record-selftest.sh"
UD_FIX="${FIXTURES}/worktask/user-decision"
Q1="Ship the ledger now?"
A1="Yes, ship it"
# sha256 of the bytes ["Ship the ledger now?","Yes, ship it"].
C1="9a935cce7ef6f8d91d0199f2af4d2f99d30473698c82be2f92d44e02c009d120"
# sha256 of the bytes ["Should rung-3 answers be recorded?","Record with empty task_ids, Write nothing"].
CS="01850ed18109a41570375239783bf43789564c6e5117adc6eb2842c4f8b766dc"

setup() {
  # Physical path: the Write/Edit arm compares a pwd -P target against the context root.
  WD="$(CDPATH='' cd -- "$(mk_tmpworkdir)" && pwd -P)"
  CTX="$WD/.context"
  mkdir -p "$CTX/logs" "$WD/transcripts"
  cp "$UD_FIX/state.rung1.json" "$CTX/state.json"
  LEDGER="$CTX/decisions.jsonl"
  AUDIT="$CTX/logs/audit.jsonl"
  TRANSCRIPT="$WD/transcripts/sess-ud-fixture.jsonl"
  cp "$UD_FIX/transcript.valid.jsonl" "$TRANSCRIPT"
  PAYLOAD_FILE="$WD/payload.json"
}

# _hook [root] — the hook as the harness runs it, stdin from $PAYLOAD_FILE, rooted at [root].
# Runs from $WD under a git ceiling: once state.json is removed, the root ladder's git ranks must
# find nothing rather than the checkout running this suite and its real audit log.
_hook() {
  # shellcheck disable=SC2016  # $1/$2 are the inner shell's positional args, expanded there
  run --separate-stderr env -u CLAUDE_PROJECT_DIR -u CONTEXT_DIR WORKSPACE_ROOT="${1:-$WD}" \
    GIT_CEILING_DIRECTORIES="${WD%/*}" \
    bash -c 'cd -- "$1" && exec bash "$2"' _ "$WD" "$PLUGIN_ROOT/$SCRIPT" < "$PAYLOAD_FILE"
}

# _post <fixture> [jq-filter] — stage a PostToolUse payload pointing at $TRANSCRIPT.
_post() {
  jq -c --arg tp "$TRANSCRIPT" ".transcript_path = \$tp | ${2:-.}" "$UD_FIX/$1" > "$PAYLOAD_FILE"
}

# _pre <fixture> [jq-filter] — stage a PreToolUse payload with __CTX__ resolved to $CTX.
_pre() {
  jq -c --arg ctx "$CTX" "(.tool_input.file_path? |= (if . == null then . else sub(\"__CTX__\"; \$ctx) end)) | ${2:-.}" \
    "$UD_FIX/$1" > "$PAYLOAD_FILE"
}

# _bash_cmd <command> — stage a PreToolUse Bash payload carrying <command>.
_bash_cmd() {
  jq -c --arg c "$1" '.tool_input.command = $c' "$UD_FIX/pre.bash-ledger-read.payload.json" > "$PAYLOAD_FILE"
}

_ledger_rows() {
  [ -f "$LEDGER" ] || {
    echo 0
    return 0
  }
  wc -l < "$LEDGER" | tr -d ' '
}

_count_action() {
  [ -f "$AUDIT" ] || {
    echo 0
    return 0
  }
  grep -c "\"action\":\"$1\"" "$AUDIT" || true
}

# _assert_refused <reason> [tool_use_id] — no ledger, silent success, one refusal row naming it.
_assert_refused() {
  assert_success
  assert_output ""
  [ ! -e "$LEDGER" ] || fail "a refusal wrote the ledger: $(cat "$LEDGER")"
  [ "$(_count_action user_decision_refused)" = 1 ] || fail "expected one refusal row, got $(_count_action user_decision_refused)"
  if [ -n "${2:-}" ]; then
    jq -e --arg r "$1" --arg t "$2" 'select(.action == "user_decision_refused")
      | .actor == "hook:user-decision" and .result == "skipped" and .subject == "AskUserQuestion"
      and .metadata == {reason: $r, tool_use_id: $t}' "$AUDIT" || fail "refusal row: $(cat "$AUDIT")"
  else
    jq -e --arg r "$1" 'select(.action == "user_decision_refused")
      | .actor == "hook:user-decision" and .result == "skipped" and .metadata == {reason: $r}' "$AUDIT" \
      || fail "refusal row: $(cat "$AUDIT")"
  fi
}

_assert_denied() {
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == "deny"' > /dev/null || fail "expected deny, got: $output"
}

_assert_allowed() {
  assert_success
  assert_output ""
  [ "$(_count_action user_decision_ledger_write_denied)" = 0 ] || fail "an allowed call wrote a deny row"
}

# --- AC1: the hook half ----------------------------------------------------------------------

@test "AC1: one answered AskUserQuestion on a parked task appends exactly one row whose scope covers that task" {
  _post post.valid.payload.json
  _hook
  assert_success
  assert_output ""
  [ "$(_ledger_rows)" = 1 ] || fail "expected one row, got $(_ledger_rows)"
  run jq -e --arg q "$Q1" --arg a "$A1" --arg c "$C1" '
    (keys_unsorted == ["id", "ts", "actor", "tool_use_id", "question", "answer", "scope", "sha256", "prev_sha256"])
    and (.id | test("^ud-[0-9]{8}T[0-9]{6}Z-1$"))
    and .actor == "hook:user-decision" and .tool_use_id == "toolu_01UdFixture0001"
    and .question == $q and .answer == $a
    and .scope == {worktask_id: "wt-ud-fixture", task_ids: ["DV0"], item: null}
    and .sha256 == $c and .prev_sha256 == null' "$LEDGER"
  assert_success
  [ -z "$(tail -c 1 "$LEDGER")" ] || fail "the row is not LF-terminated"
  run ls -l "$LEDGER"
  assert_output --regexp '^-rw-------'
}

@test "AC1: the recorded audit row names the row id, tool_use_id and row digest, and nothing is degraded" {
  _post post.valid.payload.json
  _hook
  assert_success
  local id
  id="$(jq -r .id "$LEDGER")"
  [ "$(_count_action user_decision_recorded)" = 1 ] || fail "expected one recorded row: $(cat "$AUDIT")"
  run jq -e --arg id "$id" --arg c "$C1" 'select(.action == "user_decision_recorded")
    | .actor == "hook:user-decision" and .result == "ok" and .subject == $id
    and (.metadata | keys_unsorted) == ["decision_id", "tool_use_id", "row_sha256", "item"]
    and .metadata == {decision_id: $id, tool_use_id: "toolu_01UdFixture0001", row_sha256: $c, item: null}' "$AUDIT"
  assert_success
  ! grep -qF '"result":"degraded"' "$AUDIT" || fail "a confirmed row was reported degraded"
}

@test "AC1: rung 1 covers every task parked on the same question, options and item, sorted" {
  jq '.tasks.DV1 = .tasks.DV0
    | .tasks.DC0 = (.tasks.DV0 | .metadata.blocked_on.detail.options = ["Yes, ship it"])' \
    "$UD_FIX/state.rung1.json" > "$CTX/state.json"
  _post post.valid.payload.json
  _hook
  assert_success
  run jq -ce '.scope.task_ids' "$LEDGER"
  assert_output '["DV0","DV1"]'
}

@test "AC1: rung 2 scopes a sweep header to its one task and item, and joins an array answer with ', '" {
  cp "$UD_FIX/state.rung2.json" "$CTX/state.json"
  _post post.sweep.payload.json
  _hook
  assert_success
  [ "$(_ledger_rows)" = 1 ] || fail "expected one row, got $(_ledger_rows)"
  run jq -e --arg c "$CS" '.answer == "Record with empty task_ids, Write nothing"
    and .scope == {worktask_id: "wt-ud-fixture", task_ids: ["AR0"], item: "sw-AR0-1"}
    and .sha256 == $c and .prev_sha256 == null' "$LEDGER"
  assert_success
  run jq -e 'select(.action == "user_decision_recorded") | .metadata.item == "sw-AR0-1"' "$AUDIT"
  assert_success
}

@test "AC1: a second call chains onto the first — ordinal 2 and prev_sha256 = sha256 of row 1's line bytes" {
  jq '.facts.open_questions = [{id: "sw-AR0-1", summary: "Record rung-3 answers?", class: "scope"}]' \
    "$UD_FIX/state.rung1.json" > "$CTX/state.json"
  _post post.valid.payload.json
  _hook
  assert_success
  _post post.sweep.payload.json
  _hook
  assert_success
  [ "$(_ledger_rows)" = 2 ] || fail "expected two rows, got $(_ledger_rows)"
  local line1_sha
  line1_sha="$(head -n 1 "$LEDGER" | tr -d '\n' | shasum -a 256 | cut -d' ' -f1)"
  run jq -se --arg p "$line1_sha" '(.[1].id | endswith("-2")) and .[1].prev_sha256 == $p' "$LEDGER"
  assert_success
}

@test "AC1: a fork subagent's call (agent_id present) is still the user's answer and records" {
  _post post.valid.payload.json '.agent_id = "agent-fork-1"'
  _hook
  assert_success
  [ "$(_ledger_rows)" = 1 ] || fail "expected one row, got $(_ledger_rows)"
}

# --- AC2: provenance refusals ----------------------------------------------------------------

@test "AC2: a tool other than AskUserQuestion writes no row; bad_event carries no tool_use_id" {
  _post post.bad-event.payload.json
  _hook
  _assert_refused bad_event
}

# --- MCP-proxied ask tool (Conductor) --------------------------------------------------------

MCP_TOOL="mcp__conductor__AskUserQuestion"

# _mcp_post <response-text> — the valid payload as an MCP proxy delivers it: its tool name and a
# text content array in place of the answers object; the transcript's call carries the same name.
_mcp_post() {
  jq -c --arg tp "$TRANSCRIPT" --arg tn "$MCP_TOOL" --arg t "$1" \
    '.transcript_path = $tp | .tool_name = $tn | .tool_response = [{type: "text", text: $t}]' \
    "$UD_FIX/post.valid.payload.json" > "$PAYLOAD_FILE"
  sed "s/\"name\":\"AskUserQuestion\"/\"name\":\"$MCP_TOOL\"/" "$UD_FIX/transcript.valid.jsonl" > "$TRANSCRIPT"
}

@test "R1: an mcp__<server>__AskUserQuestion text answer records one row with the numbered answer" {
  _mcp_post "User responses:
1. $A1"
  _hook
  assert_success
  assert_output ""
  [ "$(_ledger_rows)" = 1 ] || fail "expected one row, got $(_ledger_rows); audit: $(cat "$AUDIT" 2> /dev/null)"
  run jq -e --arg q "$Q1" --arg a "$A1" --arg c "$C1" '.question == $q and .answer == $a and .sha256 == $c
    and .scope.task_ids == ["DV0"]' "$LEDGER"
  assert_success
}

@test "R1: a lookalike tool name refuses as bad_event; unnumbered or miscounted text refuses as no_answer" {
  _post post.valid.payload.json '.tool_name = "mcp__x__AskUserQuestionEvil"'
  _hook
  _assert_refused bad_event

  local text
  for text in "User responses:
$A1" "User responses:
1. $A1
2. extra" "1. $A1" "User responses:
2. $A1"; do
    rm -f "$AUDIT" "$LEDGER"
    _mcp_post "$text"
    _hook
    _assert_refused no_answer toolu_01UdFixture0001
  done
}

@test "R1: an MCP answer whose transcript call carries another tool name refuses as transcript_miss" {
  _mcp_post "User responses:
1. $A1"
  cp "$UD_FIX/transcript.valid.jsonl" "$TRANSCRIPT"
  _hook
  _assert_refused transcript_miss toolu_01UdFixture0001
}

@test "R1 (QA): an object-shaped content wrapper ({content:[...]}) normalizes the same as a bare array" {
  jq -c --arg tp "$TRANSCRIPT" --arg tn "$MCP_TOOL" --arg t "User responses:
1. $A1" \
    '.transcript_path = $tp | .tool_name = $tn | .tool_response = {content: [{type: "text", text: $t}]}' \
    "$UD_FIX/post.valid.payload.json" > "$PAYLOAD_FILE"
  sed "s/\"name\":\"AskUserQuestion\"/\"name\":\"$MCP_TOOL\"/" "$UD_FIX/transcript.valid.jsonl" > "$TRANSCRIPT"
  _hook
  assert_success
  assert_output ""
  [ "$(_ledger_rows)" = 1 ] || fail "expected one row, got $(_ledger_rows); audit: $(cat "$AUDIT" 2> /dev/null)"
  run jq -e --arg q "$Q1" --arg a "$A1" --arg c "$C1" '.question == $q and .answer == $a and .sha256 == $c
    and .scope.task_ids == ["DV0"]' "$LEDGER"
  assert_success
}

@test "R1: the hook's and the library's ask-tool patterns are the same literal" {
  local hook lib
  hook="$(grep -E "^_UD_ASK_TOOL_RE=" "$PLUGIN_ROOT/$SCRIPT" | cut -d= -f2-)"
  lib="$(grep -E "^UD_ASK_TOOL_RE=" "$PLUGIN_ROOT/hooks/lib/user-decision-lib.sh" | cut -d= -f2-)"
  [ -n "$hook" ] && [ "$hook" = "$lib" ] || fail "hook=$hook lib=$lib"
}

@test "AC2: a tool_use_id outside ^[A-Za-z0-9_-]{1,128}\$ refuses as bad_event" {
  local bad
  for bad in 'toolu bad' 'toolu;rm' '' "$(printf '%0129d' 0 | tr 0 x)"; do
    rm -f "$AUDIT"
    _post post.valid.payload.json ".tool_use_id = \"$bad\""
    _hook
    _assert_refused bad_event
  done
}

@test "AC2: a tool_use_id absent from the transcript writes no row (transcript_miss)" {
  cp "$UD_FIX/transcript.missing-id.jsonl" "$TRANSCRIPT"
  _post post.valid.payload.json
  _hook
  _assert_refused transcript_miss toolu_01UdFixture0001
}

@test "AC2: a transcript not named <session_id>.jsonl, or a symlinked one, refuses as transcript_miss" {
  _post post.valid.payload.json '.session_id = "sess-other"'
  _hook
  _assert_refused transcript_miss toolu_01UdFixture0001

  rm -f "$AUDIT"
  mv "$TRANSCRIPT" "$WD/real.jsonl"
  ln -s "$WD/real.jsonl" "$TRANSCRIPT"
  _post post.valid.payload.json
  _hook
  _assert_refused transcript_miss toolu_01UdFixture0001
}

@test "AC2: answers already in the transcript's own tool_use.input refuse as pre_answered" {
  cp "$UD_FIX/transcript.pre-answered.jsonl" "$TRANSCRIPT"
  _post post.valid.payload.json
  _hook
  _assert_refused pre_answered toolu_01UdFixture0001
}

@test "AC2: tool_input.answers alone is no pre-answer signal — the permission UI fills it for real answers" {
  _post post.valid.payload.json ".tool_input.answers = {\"$Q1\": \"$A1\"}"
  _hook
  assert_success
  [ "$(_ledger_rows)" = 1 ] || fail "expected one row, got $(_ledger_rows)"
}

@test "AC2: an idle auto-answer (tool_response.afkTimeoutMs) refuses as idle_auto_answer" {
  _post post.idle.payload.json
  _hook
  _assert_refused idle_auto_answer toolu_01UdFixture0001
}

@test "AC2: a response with no per-question answers refuses as no_answer" {
  _post post.valid.payload.json '.tool_response.answers = {}'
  _hook
  _assert_refused no_answer toolu_01UdFixture0001
}

@test "AC2: an answer that is neither a string nor an array of strings refuses as answer_shape" {
  _post post.answer-shape.payload.json
  _hook
  _assert_refused answer_shape toolu_01UdFixture0001
}

@test "AC2: a header naming no parked task or sweep item (rung 3) writes nothing and refuses as no_scope" {
  _post post.valid.payload.json '.tool_input.questions[0].header = "Approve"'
  _hook
  _assert_refused no_scope toolu_01UdFixture0001
}

@test "AC2: a replayed tool_use_id writes no second row (replay)" {
  _post post.valid.payload.json
  _hook
  assert_success
  local before
  before="$(shasum -a 256 < "$LEDGER")"
  _hook
  assert_success
  assert_output ""
  [ "$(shasum -a 256 < "$LEDGER")" = "$before" ] || fail "the replay changed the ledger"
  run jq -e 'select(.action == "user_decision_refused") | .metadata == {reason: "replay", tool_use_id: "toolu_01UdFixture0001"}' "$AUDIT"
  assert_success
}

@test "AC2: a ledger whose last line lacks its LF is left byte-identical (ledger_torn)" {
  printf '%s' '{"id":"ud-20260917T101500Z-1"}' > "$LEDGER"
  _post post.valid.payload.json
  _hook
  assert_success
  assert_output ""
  [ "$(cat "$LEDGER")" = '{"id":"ud-20260917T101500Z-1"}' ] || fail "a torn ledger was appended to"
  run jq -e 'select(.action == "user_decision_refused") | .metadata.reason == "ledger_torn"' "$AUDIT"
  assert_success
}

@test "AC2: a symlinked ledger is never written through (ledger_symlink)" {
  printf 'untouched\n' > "$WD/elsewhere.txt"
  ln -s "$WD/elsewhere.txt" "$LEDGER"
  _post post.valid.payload.json
  _hook
  assert_success
  assert_output ""
  [ "$(cat "$WD/elsewhere.txt")" = "untouched" ] || fail "the symlink target was written"
  [ -L "$LEDGER" ] || fail "the symlink was replaced by a ledger"
  run jq -e 'select(.action == "user_decision_refused") | .metadata.reason == "ledger_symlink"' "$AUDIT"
  assert_success
}

@test "AC2: no state.json means no context — silent, no ledger, no audit row" {
  rm -f "$CTX/state.json"
  _post post.valid.payload.json
  _hook
  assert_success
  assert_output ""
  [ ! -e "$LEDGER" ] || fail "a ledger was written without state.json"
  [ "$(_count_action user_decision_refused)" = 0 ] || fail "a refusal row was written without state.json"
}

# --- AC6: the write guard --------------------------------------------------------------------

@test "AC6: a Write to the ledger is denied with one block row carrying only tool, dedupe_key, command_head, truncated" {
  _pre pre.write-ledger.payload.json
  _hook
  _assert_denied
  [ ! -e "$LEDGER" ] || fail "the guard itself created the ledger"
  [ "$(_count_action user_decision_ledger_write_denied)" = 1 ] || fail "expected one deny row"
  run jq -e 'select(.action == "user_decision_ledger_write_denied")
    | .actor == "hook:user-decision" and .result == "block" and .subject == "Write"
    and (.metadata | keys_unsorted | . - ["redaction"]) == ["tool", "dedupe_key", "command_head", "truncated"]
    and .metadata.tool == "Write"' "$AUDIT"
  assert_success
}

@test "AC6: an Edit to the ledger, and a Write under its lock dir, are denied" {
  _pre pre.edit-ledger.payload.json
  _hook
  _assert_denied

  mkdir -p "$LEDGER.lock"
  _pre pre.write-ledger.payload.json ".tool_input.file_path = \"$LEDGER.lock/owner\""
  _hook
  _assert_denied
}

@test "AC6: a Write through a dot-dot path that resolves to the ledger is denied" {
  mkdir -p "$CTX/logs/sub"
  _pre pre.write-ledger.payload.json ".tool_input.file_path = \"$CTX/logs/sub/../../decisions.jsonl\""
  _hook
  _assert_denied
}

@test "AC6: a Write to the ledger is denied when the workspace root is reached through a symlink" {
  ln -s "$WD" "$WD/rootlink"
  _pre pre.write-ledger.payload.json
  _hook "$WD/rootlink"
  _assert_denied
}

@test "AC6: every Bash write shape naming the ledger is denied" {
  local cmd
  _pre pre.bash-ledger-write.payload.json
  _hook
  _assert_denied
  # shellcheck disable=SC2016  # the $( ) shape is the literal command text under test
  for cmd in \
    'echo x > .context/decisions.jsonl' \
    'cat /tmp/forged >> .context/decisions.jsonl' \
    'printf x | tee -a .context/decisions.jsonl' \
    "sed -i '' 's/Not yet/Yes/' .context/decisions.jsonl" \
    'mv /tmp/forged .context/decisions.jsonl' \
    'cp /tmp/forged .context/decisions.jsonl' \
    'truncate -s 0 .context/decisions.jsonl' \
    'dd if=/tmp/forged of=.context/decisions.jsonl' \
    'jq -c . /tmp/forged > .context/decisions.jsonl' \
    'cat $(echo .context/decisions.jsonl)' \
    'eval "cat .context/decisions.jsonl"' \
    'ls /tmp | xargs cat .context/decisions.jsonl' \
    'A=1 perl -pi -e s/a/b/ .context/decisions.jsonl'; do
    _bash_cmd "$cmd"
    _hook
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null \
      || fail "expected deny for: $cmd (got: $output)"
  done
}

@test "AC6: read-only Bash commands on the ledger pass" {
  local cmd
  _pre pre.bash-ledger-read.payload.json
  _hook
  _assert_allowed
  for cmd in \
    'cat .context/decisions.jsonl' \
    'grep -c DV0 .context/decisions.jsonl' \
    'tail -n 1 .context/decisions.jsonl 2>/dev/null' \
    'cat .context/decisions.jsonl | wc -l' \
    'shasum -a 256 .context/decisions.jsonl && ls -l .context/decisions.jsonl'; do
    _bash_cmd "$cmd"
    _hook
    _assert_allowed
  done
}

@test "AC6: executing the hook script is denied; bash -n, shellcheck and editing its source pass" {
  local cmd
  for cmd in \
    'bash hooks/user-decision-record.sh < /tmp/p.json' \
    './hooks/user-decision-record.sh' \
    'source hooks/user-decision-record.sh --lib-only' \
    '. hooks/user-decision-record.sh --lib-only' \
    'exec hooks/user-decision-record.sh'; do
    _bash_cmd "$cmd"
    _hook
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null \
      || fail "expected deny for: $cmd (got: $output)"
  done
  for cmd in 'bash -n hooks/user-decision-record.sh' 'shellcheck hooks/user-decision-record.sh'; do
    _bash_cmd "$cmd"
    _hook
    _assert_allowed
  done
  _pre pre.write-ledger.payload.json ".tool_input.file_path = \"$WD/hooks/user-decision-record.sh\""
  _hook
  _assert_allowed
}

@test "AC6: the fast path and a tree with no state.json both allow a ledger write untouched" {
  _bash_cmd 'git status --short'
  _hook
  _assert_allowed
  rm -f "$CTX/state.json"
  _pre pre.write-ledger.payload.json
  _hook
  assert_success
  assert_output ""
}

# --- AC7: no question or answer text in audit ------------------------------------------------

@test "AC7: recorded, refused and denied rows never carry the question or answer text" {
  _post post.valid.payload.json
  _hook
  _post post.valid.payload.json
  _hook
  _post post.idle.payload.json '.tool_use_id = "toolu_01UdFixture0003"'
  _hook
  _pre pre.write-ledger.payload.json
  _hook
  _pre pre.bash-ledger-write.payload.json
  _hook
  [ "$(_count_action user_decision_recorded)" -ge 1 ] || fail "no recorded row to inspect"
  [ "$(_count_action user_decision_refused)" -ge 1 ] || fail "no refused row to inspect"
  [ "$(_count_action user_decision_ledger_write_denied)" -ge 1 ] || fail "no deny row to inspect"
  local needle
  for needle in "$Q1" "$A1" 'Not yet' 'Land it in this release' '"question"' '"answer"'; do
    ! grep -qF -- "$needle" "$AUDIT" || fail "audit.jsonl carries: $needle"
  done
}

# --- AC5: the selftest -----------------------------------------------------------------------

@test "AC5: the selftest passes — pinned canonical digests, row-1 null prev, row-2 chained prev" {
  run env -u WORKSPACE_ROOT -u CLAUDE_PROJECT_DIR -u CONTEXT_DIR bash "$PLUGIN_ROOT/$SELFTEST"
  assert_success
  assert_output --partial "user-decision-record: self-test OK"
  refute_output --partial "FAIL"
}
