#!/usr/bin/env bats
# Tests for hooks/audit-tooluse.sh (DV0c) — PostToolUse → audit.jsonl writer
# emitting a `tool_invoked` row keyed "<session>:<tool_use_id>".
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/audit-tooluse.sh"
PAYLOAD="${FIXTURES}/hooks/audit-tooluse.payload.json"

setup() {
  WD="$(mk_tmpworkdir)"
  # The root ladder (hooks/model-switch-lib.sh) only honours a declared
  # CLAUDE_PROJECT_DIR/WORKSPACE_ROOT when .context/ already exists under it —
  # it never guesses cwd. Declare that fixture root up front so every test
  # below is exercising the write path, not the unresolved-root no-op. The ladder
  # answers only a context holding a ledger, so the fixture seeds one.
  mkdir -p "$WD/.context"
  printf '%s' '{"version":2,"tasks":{}}' > "$WD/.context/state.json"
}

@test "happy: writes tool_invoked row with tool, duration, effort, dedupe_key" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$PAYLOAD"
  assert_success
  run jq -e '
    .action == "tool_invoked"
    and .subject == "Write"
    and .metadata.kind == "tool"
    and .metadata.duration_ms == 42
    and .metadata.effort == "medium"
    and (.metadata.dedupe_key == "sess_fix:toolu_fix")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: --kind override and absent ids fall back to placeholders" {
  # Pin CLAUDE_EFFORT OFF so the placeholder is deterministic regardless of ambient env:
  # the script falls back .effort.level // env.CLAUDE_EFFORT // "unknown", so with no
  # .effort in the payload and CLAUDE_EFFORT unset the placeholder is "unknown".
  run env -u CLAUDE_EFFORT CLAUDE_PROJECT_DIR="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --kind mcp <<< '{"tool_name":"X"}'
  assert_success
  run jq -e '
    .metadata.kind == "mcp"
    and .metadata.duration_ms == 0
    and .metadata.effort == "unknown"
    and (.metadata.dedupe_key == "nosession:notoolid")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "ledger: a state-patch status call is audited with task_id and status" {
  # The stage-transition trail resume depends on: this Bash call is the ONLY signal
  # that a stage advanced.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress"},"tool_use_id":"t1","duration_ms":10,"session_id":"s1","effort":{"level":"high"}}'
  assert_success
  run jq -e '.subject == "state-patch" and .metadata.task_id == "DV1"
             and .metadata.status == "in_progress"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "ledger: an ordinary Bash call writes NO row" {
  # Widening the matcher to all of Bash must not turn the audit log into shell noise.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_use_id":"t2","duration_ms":5,"session_id":"s1"}'
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
}

@test "ledger: a non-status state-patch call still audits, without task fields" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-create QA0 --metadata {}"},"tool_use_id":"t4","duration_ms":9,"session_id":"s1"}'
  assert_success
  run jq -e '.subject == "state-patch" and (.metadata | has("task_id") | not)' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

# --- tool_input non-disclosure ----------------------------------------------
# audit.jsonl is committed and read by every downstream stage, while tool_input
# carries file contents, diffs and full shell command lines. The script derives
# only task_id/status from it today; these cases exist so that adding any other
# .tool_input field to the jq transform — a debugging convenience, typically —
# goes red instead of quietly shipping secrets into the trail.
#
# CANARY is chosen so it cannot arise from any field the row legitimately emits,
# which is what stops these assertions from passing by accident.
CANARY="zqCANARYzq_tool_input_must_not_leak_7f31a9"

# grep -c exits 1 on no-match and 2 on a missing file, so a leak check alone
# would pass vacuously when nothing was written. Every case below therefore
# pins the row's presence (or absence) separately.
refute_log_contains() {
  run grep -cF "$CANARY" "$WD/.context/logs/audit.jsonl"
  assert_failure
}

@test "leak: a Write payload's file content and path never reach the row" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/${CANARY}/.env\",\"content\":\"AWS_SECRET_ACCESS_KEY=${CANARY}\"},\"tool_use_id\":\"t10\",\"duration_ms\":7,\"session_id\":\"s1\"}"
  assert_success
  run jq -e '.subject == "Write"' "$WD/.context/logs/audit.jsonl"
  assert_success
  refute_log_contains
}

@test "leak: an Edit payload's old_string and new_string never reach the row" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/tmp/config.yml\",\"old_string\":\"token: old_${CANARY}\",\"new_string\":\"token: new_${CANARY}\"},\"tool_use_id\":\"t11\",\"duration_ms\":8,\"session_id\":\"s1\"}"
  assert_success
  run jq -e '.subject == "Edit"' "$WD/.context/logs/audit.jsonl"
  assert_success
  refute_log_contains
}

@test "leak: a filtered-out Bash command and its token never reach the row" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"curl -H 'Authorization: Bearer ${CANARY}' https://api.example.com\"},\"tool_use_id\":\"t12\",\"duration_ms\":6,\"session_id\":\"s1\"}"
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
  refute_log_contains
}

@test "leak: a state-patch call still emits task fields but not its payload" {
  # The positive control for the three cases above: this row MUST carry task_id
  # and status, so an assertion broad enough to forbid every tool_input-derived
  # field — or a "fix" that stopped auditing Bash entirely — fails here.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash skills/worktask/scripts/state-patch.sh --task-status DV1 done --note ${CANARY}\"},\"tool_use_id\":\"t13\",\"duration_ms\":11,\"session_id\":\"s1\"}"
  assert_success
  run jq -e '.subject == "state-patch" and .metadata.task_id == "DV1"
             and .metadata.status == "done"' "$WD/.context/logs/audit.jsonl"
  assert_success
  refute_log_contains
}

@test "failure: malformed JSON exits 0 and writes no row" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< 'xxx'
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

# Companion to the audit-subagent arm of the same name.
@test "SR: a symlinked audit.jsonl is refused, never written through" {
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$PAYLOAD"
  assert_success
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

# --- root resolution ---------------------------------------------------

@test "unresolved root -> rc 0, no .context materialized under cwd" {
  local fresh
  fresh="$(mk_tmpworkdir)"
  run env -u WORKSPACE_ROOT -u CLAUDE_PROJECT_DIR -u CONTEXT_DIR \
    GIT_CEILING_DIRECTORIES="$fresh" \
    bash -c "cd '$fresh' && bash '$PLUGIN_ROOT/$SCRIPT'" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress"},"tool_use_id":"t20","duration_ms":10,"session_id":"s1"}'
  assert_success
  [ ! -d "$fresh/.context" ]
}

@test "linked-worktree cwd, no declared root -> row lands in main's ledger" {
  local base main wt
  base="$(mk_tmpworkdir)"
  main="$base/main"
  wt="$base/wt"
  mkdir -p "$main"
  local G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
  ( cd "$main" && "${G[@]}" init -q \
    && "${G[@]}" commit -q --allow-empty -m init \
    && "${G[@]}" worktree add -q "$wt" -b t ) >/dev/null
  # Physical path: mktemp -d can hand back a symlinked path (macOS /var), while
  # the resolver always answers physically — compare physical to physical.
  main="$(cd "$main" && pwd -P)"
  mkdir -p "$main/.context"
  printf '%s' '{"version":2,"tasks":{}}' > "$main/.context/state.json"

  run env -u WORKSPACE_ROOT -u CLAUDE_PROJECT_DIR -u CONTEXT_DIR \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    bash -c "cd '$wt' && bash '$PLUGIN_ROOT/$SCRIPT'" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress"},"tool_use_id":"t21","duration_ms":10,"session_id":"s1"}'
  assert_success
  run jq -e '.subject == "state-patch" and .metadata.task_id == "DV1"' \
    "$main/.context/logs/audit.jsonl"
  assert_success
  [ ! -d "$wt/.context" ]
}

# _linked_pair -> sets MAIN and WT: a main checkout plus one linked worktree, physical paths.
_linked_pair() {
  local base
  base="$(mk_tmpworkdir)"
  base="$(cd "$base" && pwd -P)"
  MAIN="$base/main"
  WT="$base/wt"
  mkdir -p "$MAIN"
  local G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
  ( cd "$MAIN" && "${G[@]}" init -q \
    && "${G[@]}" commit -q --allow-empty -m init \
    && "${G[@]}" worktree add -q "$WT" -b t ) >/dev/null
}

@test "AC-5: a linked worktree's own ledger receives the row when main has none" {
  _linked_pair
  mkdir -p "$WT/.context"
  printf '%s' '{"version":2,"tasks":{}}' > "$WT/.context/state.json"
  run env -u WORKSPACE_ROOT -u CLAUDE_PROJECT_DIR -u CONTEXT_DIR \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    bash -c "cd '$WT' && bash '$PLUGIN_ROOT/$SCRIPT'" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress"},"tool_use_id":"t22","duration_ms":10,"session_id":"s1"}'
  assert_success
  run jq -e '.metadata.task_id == "DV1"' "$WT/.context/logs/audit.jsonl"
  assert_success
  [ ! -e "$MAIN/.context" ]
}

@test "AC-5: a declared WORKSPACE_ROOT whose context has no state.json writes nothing anywhere" {
  _linked_pair
  mkdir -p "$WT/.context"
  run env -u CLAUDE_PROJECT_DIR -u CONTEXT_DIR WORKSPACE_ROOT="$WT" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    bash -c "cd '$WT' && bash '$PLUGIN_ROOT/$SCRIPT'" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress"},"tool_use_id":"t23","duration_ms":10,"session_id":"s1"}'
  assert_success
  [ -z "$(ls -A "$WT/.context")" ] || fail "wrote into a context with no ledger: $(ls -A "$WT/.context")"
  [ ! -e "$MAIN/.context" ]
}
