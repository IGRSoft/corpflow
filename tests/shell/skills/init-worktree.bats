#!/usr/bin/env bats
# Contract tests for skills/megatask/scripts/init-worktree.sh
# Contracts: --issue + --group required; --dry-run prints the planned branch
# (feature/{n}-{slug}), worktree_path (.worktrees/<group>/<n>), and the exact
# git fetch/worktree-add commands WITHOUT mutating anything; missing required
# args exit 1; --self-test runs against a temp git repo and exits 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/megatask/scripts/init-worktree.sh"

@test "happy: --dry-run prints planned branch and worktree path; no mutation" {
  WD="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --issue 7 --title "Add Feature" --group milestone-3 --dry-run --repo-root "$WD"
  assert_success
  assert_output --partial "branch:"
  assert_output --partial "feature/7-add-feature"
  assert_output --partial ".worktrees/milestone-3/7"
  # Dry-run performs no mutation: no .worktrees dir created under the repo root.
  [ ! -d "$WD/.worktrees" ]
}

@test "edge: dry-run shows the exact git fetch + worktree add commands" {
  WD="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --issue 12 --title "Logout" --group milestone-1 --dry-run --repo-root "$WD"
  assert_success
  assert_output --partial "git fetch origin master"
  assert_output --partial "git worktree add -b feature/12-logout"
}

@test "edge: slug derivation strips punctuation and lowercases the title" {
  WD="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --issue 5 --title "Add OAuth Login Flow!!" --group milestone-2 --dry-run --repo-root "$WD"
  assert_success
  assert_output --partial "feature/5-add-oauth-login-flow"
}

@test "failure: missing --issue exits 1" {
  WD="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --title "X" --group milestone-1 --dry-run --repo-root "$WD"
  assert_failure 1
}

@test "failure: non-numeric --issue exits 1" {
  WD="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --issue abc --title "X" --group milestone-1 --dry-run --repo-root "$WD"
  assert_failure 1
}

@test "failure: missing --group exits 1" {
  WD="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --issue 9 --title "X" --dry-run --repo-root "$WD"
  assert_failure 1
}

@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
