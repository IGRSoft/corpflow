#!/usr/bin/env bats
# Tests for skills/shared/lib/state-read-lib.sh — the two ledger fields every worktask
# script reads before it can name anything. The arms that matter are the degradation ones:
# the inline copies this replaces each carried their own fallback, and three of them
# deliberately used a different default from the rest.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/shared/lib/state-read-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  LIB_PATH="$PLUGIN_ROOT/$LIB"
  STATE="$WD/state.json"
  printf '%s' '{"version":2,"worktask_id":"wt-42","run_index":3}' > "$STATE"
}

teardown() {
  _test_helper_cleanup
}

withlib() {
  run bash -c "set -euo pipefail; . '$LIB_PATH'; $1"
}

@test "H1: executing the library directly is refused with exit 2" {
  run bash "$LIB_PATH"
  assert_failure 2
  assert_output --partial 'source it, do not execute it directly'
}

@test "H2: a double source is a no-op, not a re-definition error" {
  run bash -c "set -euo pipefail; . '$LIB_PATH'; . '$LIB_PATH'; echo ok"
  assert_success
  assert_output 'ok'
}

@test "H3: no readonly, no plugin-root variable, no load-time side effect" {
  run grep -nE '^[[:space:]]*(readonly|declare -r)\b' "$LIB_PATH"
  assert_failure
  run grep -n 'CLAUDE_PLUGIN_ROOT' "$LIB_PATH"
  assert_failure
  run bash -c "set -euo pipefail; cd '$WD'; . '$LIB_PATH'; ls -A | wc -l"
  assert_success
  assert_output --regexp '^ *1$'
}

@test "S1: both fields are read from the ledger" {
  withlib "corpflow_worktask_id '$STATE'; printf :; corpflow_run_index '$STATE'"
  assert_output 'wt-42:3'
}

@test "S2: an absent ledger yields the documented defaults, never an abort" {
  withlib "corpflow_worktask_id '$WD/nope.json'; printf :; corpflow_run_index '$WD/nope.json'"
  assert_success
  assert_output 'unknown:0'
}

@test "S3: an unparseable ledger degrades exactly like an absent one" {
  printf 'not json at all' > "$STATE"
  withlib "corpflow_worktask_id '$STATE'; printf :; corpflow_run_index '$STATE'"
  assert_success
  assert_output 'unknown:0'
}

@test "S4: a null field takes the default rather than the string 'null'" {
  printf '%s' '{"worktask_id":null,"run_index":null}' > "$STATE"
  withlib "corpflow_worktask_id '$STATE'; printf :; corpflow_run_index '$STATE'"
  assert_output 'unknown:0'
}

@test "S5: the default is an argument — an explicit empty default survives" {
  printf '%s' '{"version":2}' > "$STATE"
  withlib "printf '[%s]' \"\$(corpflow_worktask_id '$STATE' '')\""
  assert_output '[]'
}

@test "S6: run_index 0 is distinguishable from absent when the caller asks" {
  printf '%s' '{"run_index":0}' > "$STATE"
  withlib "printf '[%s]' \"\$(corpflow_run_index '$STATE' '')\""
  assert_output '[0]'
  printf '%s' '{}' > "$STATE"
  withlib "printf '[%s]' \"\$(corpflow_run_index '$STATE' '')\""
  assert_output '[]'
}

@test "S7: without jq the defaults apply and the caller still runs" {
  run_script_env --hide jq --source "$LIB" corpflow_worktask_id "$STATE"
  assert_success
  assert_output 'unknown'
}

@test "S8: corpflow_state_str reads an arbitrary path with its own default" {
  printf '%s' '{"metadata":{"base_ref":"develop"}}' > "$STATE"
  withlib "corpflow_state_str '$STATE' '.metadata.base_ref' none"
  assert_output 'develop'
  withlib "corpflow_state_str '$STATE' '.metadata.absent' none"
  assert_output 'none'
}

@test "S9: an unreadable ledger is a default, not a permission error on stderr" {
  chmod 000 "$STATE"
  withlib "corpflow_worktask_id '$STATE' 2>/dev/null"
  chmod 600 "$STATE"
  assert_success
  assert_output 'unknown'
}

# --- corpflow_context_dir: ranks 2-6 of the root-resolution ladder --------
# Every case below sets GIT_CEILING_DIRECTORIES to a fixture-owned directory and unsets
# every declared root not under test — rank 5 walks real git plumbing, and an
# uncontained cwd/env would resolve to THIS worktree's own live .context/state.json.

@test "context_dir: rank 2 — CONTEXT_DIR wins when it is a directory" {
  local ctxdir
  ctxdir="$(mk_tmpworkdir)"
  run_script_env --cwd "$WD" --env "CONTEXT_DIR=$ctxdir" --unset WORKSPACE_ROOT \
    --unset CLAUDE_PROJECT_DIR --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source "$LIB" corpflow_context_dir
  assert_success
  assert_output "$ctxdir"
}

@test "context_dir: rank 3 — WORKSPACE_ROOT/.context outranks CLAUDE_PROJECT_DIR" {
  local ws cp
  ws="$(mk_tmpworkdir)"; mkdir -p "$ws/.context"
  cp="$(mk_tmpworkdir)"; mkdir -p "$cp/.context"
  run_script_env --cwd "$WD" --unset CONTEXT_DIR --env "WORKSPACE_ROOT=$ws" \
    --env "CLAUDE_PROJECT_DIR=$cp" --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source "$LIB" corpflow_context_dir
  assert_success
  assert_output "$ws/.context"
}

@test "context_dir: rank 4 — CLAUDE_PROJECT_DIR/.context is used when WORKSPACE_ROOT misses" {
  local cp
  cp="$(mk_tmpworkdir)"; mkdir -p "$cp/.context"
  run_script_env --cwd "$WD" --unset CONTEXT_DIR --unset WORKSPACE_ROOT \
    --env "CLAUDE_PROJECT_DIR=$cp" --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source "$LIB" corpflow_context_dir
  assert_success
  assert_output "$cp/.context"
}

@test "context_dir: rank 5 — toplevel/.context/state.json FILE outranks the resolver" {
  local repo
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  mkdir -p "$repo/.context"
  printf '{}' > "$repo/.context/state.json"
  run_script_env --cwd "$repo" --unset CONTEXT_DIR --unset WORKSPACE_ROOT \
    --unset CLAUDE_PROJECT_DIR --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source "$LIB" corpflow_context_dir
  assert_success
  # git rev-parse --show-toplevel resolves physically; /tmp is itself a symlink on macOS.
  local want
  want="$(cd "$repo" && pwd -P)/.context"
  [ "$output" = "$want" ]
}

@test "context_dir: rank 6 — resolve-root.sh recovers the linked-worktree case" {
  local repo wt
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  mkdir -p "$repo/.context"
  wt="$WD/wt"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$wt" -b wtb 2>/dev/null \
    || skip "git worktree unavailable"
  run_script_env --cwd "$wt" --unset CONTEXT_DIR --unset WORKSPACE_ROOT \
    --unset CLAUDE_PROJECT_DIR --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source "$LIB" corpflow_context_dir
  assert_success
  local want
  want="$(cd "$repo" && pwd -P)/.context"
  [ "$output" = "$want" ]
}

@test "context_dir: unresolved — no declared root and no git repo above cwd is rc 1, empty" {
  local outside
  outside="$(mk_tmpworkdir)"
  run_script_env --cwd "$outside" --unset CONTEXT_DIR --unset WORKSPACE_ROOT \
    --unset CLAUDE_PROJECT_DIR --env "GIT_CEILING_DIRECTORIES=$outside" \
    --source "$LIB" corpflow_context_dir
  [ "$status" -eq 1 ]
  assert_output ""
}

@test "context_dir: resolver unreachable is rc 2, distinct from an unresolved ladder" {
  # A lib copy with no ../scripts/resolve-root.sh sibling — the install-is-broken case,
  # never reachable from the real tree but exercised here in isolation.
  # run_script_env's --source resolves relative to PLUGIN_ROOT, which the isolated copy
  # deliberately is not under, so this sources it directly.
  local isolib
  isolib="$WD/isolated/lib/state-read-lib.sh"
  mkdir -p "$(dirname "$isolib")"
  cp "$LIB_PATH" "$isolib"
  run env -u CONTEXT_DIR -u WORKSPACE_ROOT -u CLAUDE_PROJECT_DIR \
    GIT_CEILING_DIRECTORIES="$WD" \
    bash -c "cd '$WD' && set -euo pipefail; . '$isolib'; corpflow_context_dir"
  [ "$status" -eq 2 ]
  assert_output ""
}
