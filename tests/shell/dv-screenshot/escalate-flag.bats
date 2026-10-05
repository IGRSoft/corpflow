#!/usr/bin/env bats
# Tests for skills/dv-screenshot-capture/scripts/escalate-flag.sh, DV's upward-only flag helper.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SUT="skills/dv-screenshot-capture/scripts/escalate-flag.sh"
GATE="hooks/dv-screenshot-gate.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  CTX="$WD/.context"
  REPO="$WD/repo"
  AUDIT="$CTX/logs/audit.jsonl"
  mkdir -p "$CTX" "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  printf 'base\n' > "$REPO/README.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m base
  git -C "$REPO" checkout -q -b work
}

# ledger <task-flag|-> <ledger-flag|-> [platform]; `-` leaves the key absent.
ledger() {
  jq -n --arg tf "$1" --arg lf "$2" --arg p "${3:-web}" '
    def kv(v): if v == "-" then {} else {requires_screenshots: (v | fromjson)} end;
    {version: 2, worktask_id: "wt", platform: $p,
     metadata: ({base_ref: "main"} + kv($lf)),
     tasks: {DV0: {status: "in_progress", metadata: ({stage: "DV", platform: $p} + kv($tf))}},
     facts: {dispatched_agents: []}}' > "$CTX/state.json"
}

commit_file() { # <path>
  mkdir -p "$REPO/$(dirname "$1")"
  printf 'x\n' > "$REPO/$1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add $1"
}

run_helper() { run_script_env --cwd "$REPO" --separate-stderr "$SUT" --task-id DV0 --context-dir "$CTX" "$@"; }

task_flag() { jq -c '.tasks.DV0.metadata.requires_screenshots' "$CTX/state.json"; }
ledger_flag() { jq -c '.metadata.requires_screenshots' "$CTX/state.json"; }
rows() { [ -f "$AUDIT" ] || { echo 0; return; }; grep -c screenshot_flag_escalated "$AUDIT" || true; }

@test "escalates on a committed web .tsx: both flags true, exactly one ok audit row" {
  ledger false false
  commit_file src/App.tsx
  run_helper
  assert_success
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(task_flag)" = true ]
  [ "$(ledger_flag)" = true ]
  [ "$(rows)" = 1 ]
  jq -e 'select(.action == "screenshot_flag_escalated") | .result == "ok" and .task_id == "DV0"
    and .subject == "wt/DV0" and .metadata.platform == "web" and .metadata.raised == ["task","ledger"]
    and .metadata.matched_count == 1 and .metadata.matched == ["src/App.tsx"]' "$AUDIT"
}

@test "escalates on an uncommitted (unstaged) modification of a tracked UI file" {
  ledger false false
  commit_file src/App.tsx
  git -C "$REPO" checkout -q -b more
  git -C "$REPO" branch -f main HEAD
  printf 'changed\n' >> "$REPO/src/App.tsx"
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(task_flag)" = true ]
}

@test "escalates on an untracked UI file" {
  ledger false false
  printf 'x\n' > "$REPO/Button.vue"
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(ledger_flag)" = true ]
}

@test "escalates on a deleted UI file" {
  ledger false false
  commit_file src/Old.tsx
  git -C "$REPO" branch -f main HEAD
  git -C "$REPO" rm -q src/Old.tsx
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
}

@test "noop when both flags are already true: ledger byte-identical, no audit row" {
  ledger true true
  commit_file src/App.tsx
  cp "$CTX/state.json" "$WD/before.json"
  run_helper
  assert_output 'requires_screenshots=true action=noop reason=already_true'
  cmp "$CTX/state.json" "$WD/before.json"
  [ "$(rows)" = 0 ]
}

@test "noop on non-UI platforms, ledger byte-identical" {
  local p
  for p in all systems backend; do
    ledger false false "$p"
    commit_file "src/$p.tsx"
    cp "$CTX/state.json" "$WD/before.json"
    run_helper
    assert_output 'requires_screenshots=false action=noop reason=platform_not_ui'
    cmp "$CTX/state.json" "$WD/before.json"
  done
  [ "$(rows)" = 0 ]
}

@test "noop when the change set has no UI path" {
  ledger false false
  commit_file docs/notes.md
  cp "$CTX/state.json" "$WD/before.json"
  run_helper
  assert_output 'requires_screenshots=false action=noop reason=no_ui_path'
  cmp "$CTX/state.json" "$WD/before.json"
}

@test "UI paths under .context/ are not the change set" {
  ledger false false
  mkdir -p "$REPO/.context/designs"
  printf 'x\n' > "$REPO/.context/designs/mock.html"
  run_helper
  assert_output 'requires_screenshots=false action=noop reason=no_ui_path'
}

@test "bare Kotlin outside /ui/ and res/ is not a UI path on android" {
  ledger false false android
  commit_file app/src/main/java/com/acme/Repo.kt
  run_helper
  assert_output 'requires_screenshots=false action=noop reason=no_ui_path'
  commit_file app/src/main/java/com/acme/ui/Profile.kt
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
}

@test "never writes false: a true task flag stays true in every arm" {
  local arm
  for arm in "true false" "false true" "true true" "true -" "- true"; do
    # shellcheck disable=SC2086
    ledger $arm
    commit_file "src/${RANDOM}.tsx"
    run_helper
    assert_success
    [ "$(task_flag)" != false ]
    [ "$(ledger_flag)" != false ]
  done
}

@test "source holds one write payload and it is the true literal" {
  run grep -c 'requires_screenshots":true' "$PLUGIN_ROOT/$SUT"
  assert_output 1
  run grep -E 'requires_screenshots"? *: *"?false' "$PLUGIN_ROOT/$SUT"
  assert_failure
}

@test "warn: unresolvable base writes nothing and appends one warn row" {
  ledger false false
  jq '.metadata.base_ref = "no-such-ref" | .tasks.DV0.metadata.base_ref = "no-such-ref"' "$CTX/state.json" > "$WD/s.json"
  mv "$WD/s.json" "$CTX/state.json"
  commit_file src/App.tsx
  cp "$CTX/state.json" "$WD/before.json"
  run_helper
  assert_success
  assert_output 'requires_screenshots=false action=warn reason=base_unresolvable'
  cmp "$CTX/state.json" "$WD/before.json"
  [ "$(rows)" = 1 ]
  jq -e 'select(.action == "screenshot_flag_escalated") | .result == "warn" and .metadata.raised == []' "$AUDIT"
}

@test "warn: a non-git directory writes nothing and appends one warn row" {
  ledger false false
  local plain="$WD/plain"
  mkdir -p "$plain"
  cp "$CTX/state.json" "$WD/before.json"
  run_script_env --cwd "$plain" --env "GIT_CEILING_DIRECTORIES=$WD" --separate-stderr "$SUT" --task-id DV0 --context-dir "$CTX"
  assert_success
  assert_output 'requires_screenshots=false action=warn reason=not_a_git_repo'
  cmp "$CTX/state.json" "$WD/before.json"
  [ "$(rows)" = 1 ]
}

@test "a malformed ledger fails the task-id guard and is left untouched" {
  printf 'not json' > "$CTX/state.json"
  run_helper
  assert_failure 2
  [ "$(cat "$CTX/state.json")" = 'not json' ]
}

@test "idempotent: a re-run after escalation is a noop and adds no second row" {
  ledger false false
  commit_file src/App.tsx
  run_helper
  run_helper
  assert_output 'requires_screenshots=true action=noop reason=already_true'
  [ "$(rows)" = 1 ]
}

@test "heal: task already true, ledger false raises only the ledger" {
  ledger true false
  commit_file src/App.tsx
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(ledger_flag)" = true ]
  jq -e 'select(.action == "screenshot_flag_escalated") | .metadata.raised == ["ledger"]' "$AUDIT"
}

@test "absent keys read as true, like the gate: noop" {
  ledger - -
  commit_file src/App.tsx
  run_helper
  assert_output 'requires_screenshots=true action=noop reason=already_true'
}

@test "parity: the JSON string \"false\" counts as false, as the gate reads it" {
  ledger '"false"' '"false"'
  commit_file src/App.tsx
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(task_flag)" = true ]
}

@test "a large matched list still exits 0 with one line, raised flags and one capped audit row" {
  ledger false false
  local i
  for i in $(seq 1 2000); do : > "$REPO/page-$i-with-a-long-file-name-to-fill-the-pipe.css"; done
  run_helper
  assert_success
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(task_flag)" = true ]
  [ "$(ledger_flag)" = true ]
  [ "$(rows)" = 1 ]
  jq -e 'select(.action == "screenshot_flag_escalated") | .metadata.matched_count == 2000 and (.metadata.matched | length) == 10' "$AUDIT"
}

@test "parity: the gate's own FLAG_JQ reads the flag the helper acted on" {
  local jqsrc
  jqsrc=$(awk "/^FLAG_JQ='/{f=1; sub(/^FLAG_JQ='/,\"\")} f{ if (\$0 ~ /'\$/){sub(/'\$/,\"\"); print; exit} print}" "$PLUGIN_ROOT/$GATE")
  ledger '"false"' '"false"'
  commit_file src/App.tsx
  [ "$(jq -r --arg t DV0 "$jqsrc" "$CTX/state.json")" = false ]
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ "$(jq -r --arg t DV0 "$jqsrc" "$CTX/state.json")" = true ]
}

@test "a task id that is not a ledger key is a usage failure" {
  ledger false false
  run_script_env --cwd "$REPO" --separate-stderr "$SUT" --task-id DV9 --context-dir "$CTX"
  assert_failure 2
  assert_output ''
}

@test "the gate honours an escalation: a no-capture stop passes before and blocks after" {
  ledger false false
  jq '.tasks.DV0.metadata.agent = "system-developer:bash-developer"' "$CTX/state.json" > "$WD/s.json"
  mv "$WD/s.json" "$CTX/state.json"
  commit_file src/App.tsx
  local payload="$PLUGIN_ROOT/tests/fixtures/hooks/dv-screenshot-gate-bash-developer.payload.json"
  run_script_env --env "WORKSPACE_ROOT=$WD" --stdin-file "$payload" "$GATE"
  assert_success
  assert_output ''
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  run_script_env --env "WORKSPACE_ROOT=$WD" --stdin-file "$payload" "$GATE"
  assert_success
  echo "$output" | jq -e '.decision == "block" and (.reason | startswith("no_captures"))'
}

@test "--invoker: gate adds matched=<n> to an escalated line and labels the row; dv stdout is unchanged" {
  ledger false false
  commit_file src/App.tsx
  run_script_env --cwd "$REPO" --separate-stderr "$SUT" --task-id DV0 --context-dir "$CTX" --invoker gate
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched matched=1'
  jq -e 'select(.action == "screenshot_flag_escalated") | .metadata.invoker == "gate"' "$AUDIT"
  ledger false false
  rm -f "$AUDIT"
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  jq -e 'select(.action == "screenshot_flag_escalated") | .metadata.invoker == "dv"' "$AUDIT"
}

@test "--invoker: any other value is a usage failure and writes nothing" {
  ledger false false
  commit_file src/App.tsx
  cp "$CTX/state.json" "$WD/before.json"
  run_script_env --cwd "$REPO" --separate-stderr "$SUT" --task-id DV0 --context-dir "$CTX" --invoker other
  assert_failure 2
  cmp "$CTX/state.json" "$WD/before.json"
}

@test "every git call in the helper disables core.fsmonitor, and a repo fsmonitor hook never runs" {
  run bash -c "grep -cE '^[^#]*(^|[ (])git ' '$PLUGIN_ROOT/$SUT'"
  [ "$output" -ge 5 ]
  run bash -c "grep -E '^[^#]*(^|[ (])git ' '$PLUGIN_ROOT/$SUT' | grep -vc 'git -c core.fsmonitor=false'"
  assert_output 0
  ledger false false
  commit_file src/App.tsx
  printf 'x\n' > "$REPO/Extra.tsx"
  printf '#!/bin/sh\ntouch "%s/fsmonitor-ran"\nexit 0\n' "$WD" > "$WD/fsm.sh"
  chmod +x "$WD/fsm.sh"
  git -C "$REPO" config core.fsmonitor "$WD/fsm.sh"
  # Control: the same git commands the helper runs, without the flag, do fire the hook.
  git -C "$REPO" diff --name-only HEAD > /dev/null 2>&1
  git -C "$REPO" ls-files --others --exclude-standard > /dev/null 2>&1
  [ -e "$WD/fsmonitor-ran" ]
  rm -f "$WD/fsmonitor-ran"
  run_helper
  assert_output 'requires_screenshots=true action=escalated reason=ui_path_matched'
  [ ! -e "$WD/fsmonitor-ran" ]
}
