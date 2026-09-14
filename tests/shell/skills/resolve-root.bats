#!/usr/bin/env bats
# Tests for skills/shared/scripts/resolve-root.sh — the git arm of the shared
# root-resolution ladder. Declared roots (--state, CONTEXT_DIR, WORKSPACE_ROOT,
# CLAUDE_PROJECT_DIR) are a caller's concern; this file targets the git-plumbing
# arm on its own.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/shared/scripts/resolve-root.sh"

setup() {
  WD="$(mk_tmpworkdir)"
}

_physical() {
  (cd "$1" && pwd -P)
}

@test "main checkout: no args prints <main>/.context" {
  local repo
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  run_script_env --cwd "$repo" --env "GIT_CEILING_DIRECTORIES=$WD" "$SCRIPT"
  assert_success
  assert_output "$(_physical "$repo")/.context"
}

@test "--root: prints the main checkout itself" {
  local repo
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  run_script_env --cwd "$repo" --env "GIT_CEILING_DIRECTORIES=$WD" "$SCRIPT" --root
  assert_success
  assert_output "$(_physical "$repo")"
}

@test "linked worktree: resolves to the MAIN checkout's .context, not its own" {
  local repo wt
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  wt="$WD/wt"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$wt" -b wtb 2>/dev/null \
    || skip "git worktree unavailable"
  run_script_env --cwd "$wt" --env "GIT_CEILING_DIRECTORIES=$WD" "$SCRIPT"
  assert_success
  assert_output "$(_physical "$repo")/.context"
}

@test "subdirectories: main and linked worktree subdirs answer the same" {
  local repo wt want
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  wt="$WD/wt"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$wt" -b wtb 2>/dev/null \
    || skip "git worktree unavailable"
  mkdir -p "$repo/a/b" "$wt/c/d"
  want="$(_physical "$repo")/.context"

  run_script_env --cwd "$repo/a/b" --env "GIT_CEILING_DIRECTORIES=$WD" "$SCRIPT"
  assert_success
  assert_output "$want"

  run_script_env --cwd "$wt/c/d" --env "GIT_CEILING_DIRECTORIES=$WD" "$SCRIPT"
  assert_success
  assert_output "$want"
}

@test "outside a repo: non-zero exit, empty stdout" {
  local outside="$WD/outside"
  mkdir -p "$outside"
  run_script_env --cwd "$outside" --env "GIT_CEILING_DIRECTORIES=$WD" "$SCRIPT"
  assert_failure
  assert_output ""
}

@test "bare main worktree: exit 3, empty stdout" {
  local bare wt2
  bare="$WD/bare.git"
  git init -q --bare "$bare"
  wt2="$WD/bw"
  git -C "$bare" -c user.name=t -c user.email=t@t worktree add -q "$wt2" -b b2 2>/dev/null \
    || skip "git worktree unavailable"
  run_script_env --cwd "$bare" --env "GIT_CEILING_DIRECTORIES=$WD" --separate-stderr "$SCRIPT"
  assert_failure 3
  assert_output ""
}

@test "usage: an unrecognized argument exits 2" {
  run_script_env "$SCRIPT" --bogus
  assert_failure 2
}

@test "usage: -h exits 0 and prints the header" {
  run_script_env "$SCRIPT" -h
  assert_success
  assert_output --partial "resolve-root.sh"
}

@test "--self-test passes" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "8 passed, 0 failed"
}

@test "parity: state-read-lib and model-switch-lib agree on the same fixture with CONTEXT_DIR unset" {
  local repo wt from_skills from_hooks
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  mkdir -p "$repo/.context"
  wt="$WD/wt"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$wt" -b wtb 2>/dev/null \
    || skip "git worktree unavailable"

  run_script_env --cwd "$wt" --unset CONTEXT_DIR --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source skills/shared/lib/state-read-lib.sh corpflow_context_dir
  assert_success
  from_skills="$output"

  run_script_env --cwd "$wt" --unset CONTEXT_DIR --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source hooks/model-switch-lib.sh corpflow_context_root
  assert_success
  from_hooks="$output"

  [ -n "$from_skills" ]
  [ "$from_skills" = "$from_hooks" ]
}

@test "parity: no .context anywhere → both resolvers agree on empty, not the resolver's git root" {
  local repo wt from_skills from_hooks
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  wt="$WD/wt"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$wt" -b wtb 2>/dev/null \
    || skip "git worktree unavailable"

  # corpflow_context_dir returns 1 with no .context anywhere; only stdout matters here.
  run_script_env --cwd "$wt" --unset CONTEXT_DIR --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source skills/shared/lib/state-read-lib.sh corpflow_context_dir
  from_skills="$output"
  assert_output ""

  run_script_env --cwd "$wt" --unset CONTEXT_DIR --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$WD" \
    --source hooks/model-switch-lib.sh corpflow_context_root
  from_hooks="$output"
  assert_output ""

  [ "$from_skills" = "" ]
  [ "$from_hooks" = "" ]
}
