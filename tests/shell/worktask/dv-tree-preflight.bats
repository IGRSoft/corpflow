#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/dv-tree-preflight.sh.
# Contracts (from the header + agents/developer.md § D0.0):
#   - resolved git root != assigned workspace => exit 1 naming BOTH paths
#   - resolved git root == assigned workspace => exit 0, silent under --quiet
#   - assigned workspace unresolvable         => WARN + exit 0 (never a false block)
#   - --assigned outranks state.json .metadata.workspace_path
#   - unknown flag                            => exit 2
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/dv-tree-preflight.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  REPO="$WD/repo"
  mkdir -p "$REPO/.context"
  (
    cd "$REPO"
    git init -q .
    git config user.email t@t.t
    git config user.name t
    printf 'x\n' > f.txt
    git add f.txt
    git commit -qm init
  )
  # Physical path: /tmp is a symlink on macOS and the script compares resolved paths.
  REPO_REAL="$(cd "$REPO" && pwd -P)"
}

@test "pass: the assigned workspace matching the resolved git root is silent (exit 0)" {
  cd "$REPO"
  run bash "$PLUGIN_ROOT/$SCRIPT" --assigned "$REPO" --quiet
  assert_success
  assert_output ""
}

@test "block: a mismatched assigned workspace exits 1 naming both paths" {
  mkdir -p "$WD/elsewhere"
  cd "$REPO"
  run bash "$PLUGIN_ROOT/$SCRIPT" --assigned "$WD/elsewhere"
  assert_failure 1
  assert_output --partial "MISMATCH"
  assert_output --partial "$REPO_REAL"
  assert_output --partial "elsewhere"
  assert_output --partial "Do NOT edit"
}

@test "resolve: state.json .metadata.workspace_path is used when --assigned is absent" {
  cd "$REPO"
  mkdir -p "$WD/elsewhere"
  jq -n --arg p "$WD/elsewhere" '{version:1, metadata:{workspace_path:$p}}' \
    > "$REPO/.context/state.json"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 1
  assert_output --partial "MISMATCH"
}

@test "resolve: --assigned outranks state.json .metadata.workspace_path" {
  cd "$REPO"
  mkdir -p "$WD/elsewhere"
  jq -n --arg p "$WD/elsewhere" '{version:1, metadata:{workspace_path:$p}}' \
    > "$REPO/.context/state.json"
  run bash "$PLUGIN_ROOT/$SCRIPT" --assigned "$REPO" --quiet
  assert_success
}

@test "degrade: an unresolvable assignment warns and never blocks" {
  cd "$REPO"
  # No --assigned, no workspace_path in state.json, no WORKSPACE_ROOT.
  WORKSPACE_ROOT="" run bash "$PLUGIN_ROOT/$SCRIPT" --state /nonexistent/state.json
  assert_success
  assert_output --partial "WARN"
}

@test "degrade: an assigned path that does not exist on disk warns, never blocks" {
  cd "$REPO"
  run bash "$PLUGIN_ROOT/$SCRIPT" --assigned "$WD/never-created"
  assert_success
  assert_output --partial "WARN"
}

@test "degrade: outside a git work tree the check is skipped, not failed" {
  cd "$WD"
  # A tmpdir that is not a repo; --assigned still points at the repo.
  run env -u GIT_DIR bash -c 'cd "$1" && GIT_CEILING_DIRECTORIES="$1" bash "$2" --assigned "$3"' \
    _ "$WD" "$PLUGIN_ROOT/$SCRIPT" "$REPO"
  assert_success
}

@test "contract: --self-test reaches ALL PASS" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "S1: matching tree passes silently"
  assert_output --partial "S2: mismatched tree blocks"
  assert_output --partial "S3: unresolved assignment warns"
  assert_output --partial "ALL PASS"
}

@test "usage: an unknown flag exits 2" {
  cd "$REPO"
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
  assert_output --partial "unknown argument"
}
