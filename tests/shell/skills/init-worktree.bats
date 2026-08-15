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

# --- real (non-dry-run) worktree creation ------------------------------------
# Every test above is --dry-run, i.e. asserts the printed plan. The script's
# actual effect — `git fetch origin <base>` then `git worktree add -b <branch>
# <path> origin/<base>` (:278-279) — was exercised only inside the script's own
# --self-test, which is the thing this suite exists to stop trusting.

@test "real run: creates the worktree, the branch, and the workspace record" {
  local origin repo
  # A local "remote" so `git fetch origin master` resolves without a network.
  origin="$(mk_git_fixture --branch master \
            --file 'README.md:seed\n' --commit 'chore: seed')"
  repo="$(mk_git_fixture --branch master --remote "$origin" \
          --file 'README.md:seed\n' --commit 'chore: seed')"

  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 7 --title "Add Feature" --group milestone-3 --repo-root "$repo"
  assert_success

  # The worktree directory exists and git knows about it.
  [ -d "$repo/.worktrees/milestone-3/7" ]
  run git -C "$repo" worktree list
  assert_output --partial ".worktrees/milestone-3/7"

  # It is checked out on the planned branch, not on the base branch.
  run git -C "$repo/.worktrees/milestone-3/7" rev-parse --abbrev-ref HEAD
  assert_output "feature/7-add-feature"

  # The branch exists in the parent repo's ref namespace too.
  run git -C "$repo" rev-parse --verify --quiet "refs/heads/feature/7-add-feature"
  assert_success
}

# --- scratch-metadata exclusion (REQ-2) --------------------------------------
# The binding contract is observable, not mechanical: a fresh worktree reports
# NOTHING to `git status`, so an unscoped `git add -A` during a conflict
# resolution cannot stage the batch's own workspace.json onto the branch.
#
# The status reads run with GIT_CONFIG_GLOBAL/SYSTEM neutralised: mk_git_fixture
# does not scrub them, and an operator whose ~/.gitignore_global already hides
# workspace.json or .worktrees/ would satisfy these assertions for free.

@test "exclusion: a freshly initialised worktree reports a clean git status" {
  local origin repo wt
  origin="$(mk_git_fixture --branch master \
            --file 'README.md:seed\n' --commit 'chore: seed')"
  repo="$(mk_git_fixture --branch master --remote "$origin" \
          --file 'README.md:seed\n' --commit 'chore: seed')"

  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 7 --title "Add Feature" --group milestone-3 --repo-root "$repo"
  assert_success

  wt="$repo/.worktrees/milestone-3/7"
  [ -f "$wt/workspace.json" ]

  run env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$wt" status --porcelain
  assert_success
  assert_output ""
}

@test "exclusion: no tracked file is modified by the exclusion" {
  local origin repo
  origin="$(mk_git_fixture --branch master \
            --file 'README.md:seed\n' --file '.gitignore:build/\n' \
            --commit 'chore: seed')"
  repo="$(mk_git_fixture --branch master --remote "$origin" \
          --file 'README.md:seed\n' --file '.gitignore:build/\n' \
          --commit 'chore: seed')"

  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 7 --title "Add Feature" --group milestone-3 --repo-root "$repo"
  assert_success

  # A mechanism that wrote the repo's tracked .gitignore would show up here.
  run env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$repo/.worktrees/milestone-3/7" status --porcelain --untracked-files=no
  assert_success
  assert_output ""
  run env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$repo" status --porcelain --untracked-files=no
  assert_success
  assert_output ""
}

@test "exclusion: --dry-run announces it and writes no exclude entry" {
  local repo
  repo="$(mk_git_fixture --branch master \
          --file 'README.md:seed\n' --commit 'chore: seed')"

  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 7 --title "Add Feature" --group milestone-3 --dry-run --repo-root "$repo"
  assert_success
  assert_output --partial "exclude (git common-dir info/exclude): /workspace.json"

  run grep -qxF -- '/workspace.json' "$repo/.git/info/exclude"
  assert_failure
}

@test "exclusion: repeated init does not duplicate the exclude patterns" {
  local origin repo excl
  origin="$(mk_git_fixture --branch master \
            --file 'README.md:seed\n' --commit 'chore: seed')"
  repo="$(mk_git_fixture --branch master --remote "$origin" \
          --file 'README.md:seed\n' --commit 'chore: seed')"

  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 7 --title "Add Feature" --group milestone-3 --repo-root "$repo"
  assert_success
  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 8 --title "Second Thing" --group milestone-3 --repo-root "$repo"
  assert_success

  excl="$repo/.git/info/exclude"
  run grep -cxF -- '/workspace.json' "$excl"
  assert_output "1"
  run grep -cxF -- '/.worktrees/' "$excl"
  assert_output "1"
}

@test "real run: a second issue in the same group gets its own worktree" {
  local origin repo
  origin="$(mk_git_fixture --branch master \
            --file 'README.md:seed\n' --commit 'chore: seed')"
  repo="$(mk_git_fixture --branch master --remote "$origin" \
          --file 'README.md:seed\n' --commit 'chore: seed')"

  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 7 --title "Add Feature" --group milestone-3 --repo-root "$repo"
  assert_success
  run_script_env --cwd "$repo" -- "$SCRIPT" \
    --issue 8 --title "Second Thing" --group milestone-3 --repo-root "$repo"
  assert_success

  [ -d "$repo/.worktrees/milestone-3/7" ]
  [ -d "$repo/.worktrees/milestone-3/8" ]
  run git -C "$repo/.worktrees/milestone-3/8" rev-parse --abbrev-ref HEAD
  assert_output "feature/8-second-thing"
  # The first worktree is untouched by the second run.
  run git -C "$repo/.worktrees/milestone-3/7" rev-parse --abbrev-ref HEAD
  assert_output "feature/7-add-feature"
}
