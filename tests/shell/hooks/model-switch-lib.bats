#!/usr/bin/env bats
# Tests for hooks/model-switch-lib.sh — the sourced-only library shared by the
# PreModelSwitch gate and the PostModelSwitch observer.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="hooks/model-switch-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
}

# Ledger with one in_progress stage and one launched, pinned dispatch row.
_ledger() {
  printf '%s' '{"version":1,"worktask_id":"wt-ms",
    "tasks":{"DV0":{"status":"in_progress"}},
    "facts":{"dispatched_agents":[
      {"stage":"DV","task_id":"DV0","subagent_type":"corpflow:developer",
       "agent_id":"agt_dv","model_requested":"opus","status":"launched"}]}}' \
    > "$WD/.context/state.json"
}

# --- corpflow_context_root ----------------------------------------------------

@test "context_root: WORKSPACE_ROOT wins when it holds a .context" {
  run_script_env --cwd "$WD" --env "WORKSPACE_ROOT=$WD" --env "CLAUDE_PROJECT_DIR=/nonexistent" \
    --source "$LIB" corpflow_context_root
  assert_success
  assert_output "$WD/.context"
}

@test "context_root: CLAUDE_PROJECT_DIR is used when WORKSPACE_ROOT is unset" {
  run_script_env --cwd "$WD" --unset WORKSPACE_ROOT --env "CLAUDE_PROJECT_DIR=$WD" \
    --source "$LIB" corpflow_context_root
  assert_success
  assert_output "$WD/.context"
}

@test "context_root: an env var pointing at a dir with no .context is skipped for git" {
  # The worktree case: cwd is a linked checkout with no .context of its own, so
  # resolution must fall through to the main checkout that owns it.
  local main sub
  main="$(mk_tmpworkdir)"
  mkdir -p "$main/.context"
  sub="$main/sub"
  mkdir -p "$sub"
  run_script_env --cwd "$sub" --unset WORKSPACE_ROOT --env "CLAUDE_PROJECT_DIR=$sub" \
    --source "$LIB" corpflow_context_root
  assert_success
  # No .context under $sub and no git repo above it, so it degrades to the
  # declared dir rather than inventing one.
  assert_output "$sub/.context"
}

@test "context_root: git common dir recovers the linked-worktree case" {
  local repo wt
  repo="$(mk_git_fixture --file 'a.txt:hi' --commit 'init')"
  mkdir -p "$repo/.context"
  wt="$repo/wt"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q -b wt-branch "$wt" 2>/dev/null \
    || skip "git worktree unavailable"
  run_script_env --cwd "$wt" --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --source "$LIB" corpflow_context_root
  assert_success
  # The git arm resolves through `cd && pwd`, so compare physical paths: on macOS
  # $TMPDIR is itself a symlink and a literal comparison would fail on that alone.
  local want
  want="$(cd "$repo" && pwd -P)/.context"
  [ "$output" = "$want" ]
}

# --- corpflow_active_stage ----------------------------------------------------

@test "active_stage: a single in_progress stage resolves to its code" {
  _ledger
  run_script_env --cwd "$WD" --source "$LIB" corpflow_active_stage "$WD/.context"
  assert_success
  assert_output "DV"
}

@test "active_stage: two distinct in_progress stages resolve to empty (never a guess)" {
  printf '%s' '{"tasks":{"DV0":{"status":"in_progress"},"QA0":{"status":"in_progress"}}}' \
    > "$WD/.context/state.json"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_active_stage "$WD/.context"
  assert_success
  assert_output ""
}

@test "active_stage: parallel tracks of ONE stage still resolve (DV0+DV1 -> DV)" {
  printf '%s' '{"tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"in_progress"}}}' \
    > "$WD/.context/state.json"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_active_stage "$WD/.context"
  assert_success
  assert_output "DV"
}

@test "active_stage: absent state.json resolves to empty" {
  run_script_env --cwd "$WD" --source "$LIB" corpflow_active_stage "$WD/.context"
  assert_success
  assert_output ""
}

# --- corpflow_resolve_pin -----------------------------------------------------

@test "resolve_pin: exact agent_id match yields the pin and task id" {
  _ledger
  run_script_env --cwd "$WD" --source "$LIB" corpflow_resolve_pin "$WD/.context" DV agt_dv
  assert_success
  assert_output "opus DV0"
}

@test "resolve_pin: degrades to the single launched row when agent_id is absent" {
  _ledger
  run_script_env --cwd "$WD" --source "$LIB" corpflow_resolve_pin "$WD/.context" DV ""
  assert_success
  assert_output "opus DV0"
}

@test "resolve_pin: two launched rows for one stage are ambiguous -> empty" {
  printf '%s' '{"tasks":{"DV0":{"status":"in_progress"}},
    "facts":{"dispatched_agents":[
      {"stage":"DV","task_id":"DV0","subagent_type":"x","model_requested":"opus","status":"launched"},
      {"stage":"DV","task_id":"DV1","subagent_type":"x","model_requested":"sonnet","status":"launched"}]}}' \
    > "$WD/.context/state.json"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_resolve_pin "$WD/.context" DV ""
  assert_success
  assert_output ""
}

@test "resolve_pin: a row carrying no model_requested carries no pin" {
  printf '%s' '{"tasks":{"DV0":{"status":"in_progress"}},
    "facts":{"dispatched_agents":[
      {"stage":"DV","task_id":"DV0","subagent_type":"x","status":"launched"}]}}' \
    > "$WD/.context/state.json"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_resolve_pin "$WD/.context" DV ""
  assert_success
  assert_output ""
}

@test "resolve_pin: a completed row is not a live pin" {
  printf '%s' '{"tasks":{"DV0":{"status":"in_progress"}},
    "facts":{"dispatched_agents":[
      {"stage":"DV","task_id":"DV0","subagent_type":"x","model_requested":"opus","status":"completed"}]}}' \
    > "$WD/.context/state.json"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_resolve_pin "$WD/.context" DV ""
  assert_success
  assert_output ""
}

# --- corpflow_model_family ----------------------------------------------------
# ANTI-VACUITY PAIR: the matcher must collapse alias-vs-resolved-id onto one
# family AND still separate genuinely different tiers. A matcher that always
# returned the same value, or always empty, fails one of these two.

@test "model_family: ANTI-VACUITY — alias and resolved id collapse to one family" {
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "opus"
  assert_output "opus"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "claude-opus-5-20260615"
  assert_output "opus"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "OPUS"
  assert_output "opus"
}

@test "model_family: ANTI-VACUITY — different tiers stay different" {
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "claude-sonnet-5"
  assert_output "sonnet"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "haiku"
  assert_output "haiku"
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "claude-fable-5"
  assert_output "fable"
}

@test "model_family: an unrecognized string is empty, not a family" {
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family "gpt-9"
  assert_success
  assert_output ""
  run_script_env --cwd "$WD" --source "$LIB" corpflow_model_family ""
  assert_success
  assert_output ""
}

@test "contract: the library refuses to be executed directly" {
  run bash "$PLUGIN_ROOT/$LIB"
  [ "$status" -eq 2 ]
  assert_output --partial "source it, do not execute it directly"
}
