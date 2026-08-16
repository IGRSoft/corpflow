#!/usr/bin/env bats
# Contract tests for skills/shared/milestone-helpers/scripts/milestone-helpers.sh
# Contracts (from script header + empirical verification):
#   branch-name <n> <title>     -> feature/{n}-{slug}  (slug max 50 chars, lowercase, no-punct)
#   priority-score <label...>   -> lowest integer score: 0=P0/critical…4=P4/backlog, 99=none
#   base-branch [<n>] [--file J] -> branch name ("master" default when no issue JSON)
#   usage error (no subcommand) -> exit 1
#   --self-test                  -> exit 0 "all tests passed"
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/shared/milestone-helpers/scripts/milestone-helpers.sh"

# --- branch-name: happy path ------------------------------------------------
@test "happy: branch-name produces feature/{n}-{slug} with lowercase no-punct" {
  run_script "$SCRIPT" branch-name 42 "Add OAuth Login Flow!!"
  assert_success
  assert_output "feature/42-add-oauth-login-flow"
}

@test "edge: branch-name slug is max 50 chars (long title truncated)" {
  local long_title="This is a very long feature title that should be truncated because it exceeds fifty characters by a lot"
  run_script "$SCRIPT" branch-name 1 "$long_title"
  assert_success
  # Strip the "feature/1-" prefix, slug portion must be ≤50 chars.
  local slug="${output#feature/1-}"
  [ "${#slug}" -le 50 ]
}

# --- truncation shape + parity with branch-lib.sh ---------------------------
# The two branch-name implementations (this dispatcher for megatask, branch-lib.sh
# for worktask) slugify independently. These pin them to one convention: same body,
# same word-boundary truncation rule. Inputs stay short enough that the 48- vs
# 50-char budget difference — deliberately left alone — cannot confound the compare.

@test "edge: branch-name truncation ends on a whole word, never mid-word" {
  run_script "$SCRIPT" branch-name 164 \
    "Fix the reconstruction scan flow blinking before the first frame renders"
  assert_success
  assert_output "bugfix/164-fix-the-reconstruction-scan-flow-blinking-before"
}

# --- type derivation (batch branches are no longer fixed to feature/) --------
@test "happy: branch-name derives the type from the title" {
  run_script "$SCRIPT" branch-name 43 "Fix: crash on startup!!!"
  assert_success
  assert_output "bugfix/43-fix-crash-on-startup"

  run_script "$SCRIPT" branch-name 44 "Refactor the reconnect backoff"
  assert_success
  assert_output "refactor/44-refactor-the-reconnect-backoff"

  # Nothing defect-shaped in the title still yields the feature default.
  run_script "$SCRIPT" branch-name 45 "Add dark mode toggle"
  assert_success
  assert_output "feature/45-add-dark-mode-toggle"
}

@test "cross-check: the type matches branch-lib derive_type for the same title" {
  local title derived
  for title in \
    "Fix: crash on startup!!!" \
    "Refactor the reconnect backoff" \
    "Add dark mode toggle" \
    "Ship a hotfix for the release pipeline"; do
    derived="$(bash -c ". '$PLUGIN_ROOT/skills/worktask/scripts/branch-lib.sh'; derive_type \"\$1\"" _ "$title")"
    run_script "$SCRIPT" branch-name 7 "$title"
    assert_success
    [ "${output%%/*}" = "$derived" ]
  done
}

@test "failure: an unreachable branch-lib.sh stops the run (exit 2), never silently defaults" {
  # A copy outside the plugin tree cannot resolve its ../../../worktask sibling. A
  # `feature/` fallback here would be a plausible-looking wrong name on a real branch.
  WD="$(mk_tmpworkdir)"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/milestone-helpers.sh"
  run bash "$WD/milestone-helpers.sh" branch-name 42 "Fix crash on startup"
  assert_failure 2
  assert_output --partial "branch-lib.sh"
}

@test "cross-check: slug body is identical to branch-lib slug_body" {
  local title body
  for title in \
    "Add OAuth Login Flow!!" \
    "Fix: crash on startup!!!" \
    "---hello world---" \
    "Refactor the WebSocket reconnect backoff" \
    "Update deps: jq 1.7, gh 2.60 (security)"; do
    body="$(bash -c ". '$PLUGIN_ROOT/skills/worktask/scripts/branch-lib.sh'; slug_body \"\$1\"" _ "$title")"
    run_script "$SCRIPT" branch-name 7 "$title"
    assert_success
    # Strip whatever type was derived — this arm pins the slug body only.
    [ "${output#*/7-}" = "$body" ]
  done
}

@test "cross-check: an over-budget title truncates to the same slug as derive_slug" {
  local title="Fix the reconstruction scan flow blinking before the first frame renders"
  local derived
  derived="$(bash -c ". '$PLUGIN_ROOT/skills/worktask/scripts/branch-lib.sh'; derive_slug \"\$1\"" _ "$title")"
  run_script "$SCRIPT" branch-name 164 "$title"
  assert_success
  [ "${output#*/164-}" = "$derived" ]
}

@test "edge: a single over-budget word survives whole rather than emptying the slug" {
  local word
  word="$(printf 'a%.0s' {1..80})"
  run_script "$SCRIPT" branch-name 1 "$word"
  assert_success
  assert_output "feature/1-${word}"
}

@test "edge: a multi-line title yields a single-line branch name" {
  run_script "$SCRIPT" branch-name 7 "$(printf 'Add login\nflow')"
  assert_success
  assert_output "feature/7-add-login-flow"
}

# --- priority-score ---------------------------------------------------------
@test "happy: priority-score returns min score when multiple labels given" {
  # P2 and P0 together should yield 0 (P0 wins).
  run_script "$SCRIPT" priority-score P2 P0
  assert_success
  assert_output "0"
}

@test "edge: priority-score returns 99 for unknown labels" {
  run_script "$SCRIPT" priority-score unknown-label
  assert_success
  assert_output "99"
}

@test "edge: priority-score P4 yields 4" {
  run_script "$SCRIPT" priority-score P4
  assert_success
  assert_output "4"
}

# --- base-branch ------------------------------------------------------------
@test "happy: base-branch with no args defaults to master" {
  run_script "$SCRIPT" base-branch
  assert_success
  assert_output "master"
}

# --- failure / usage --------------------------------------------------------
@test "failure: missing subcommand exits 1 and prints usage" {
  run_script "$SCRIPT"
  assert_failure 1
  assert_output --partial "Usage"
}

@test "failure: unknown subcommand exits 1" {
  run_script "$SCRIPT" frobulate
  assert_failure 1
}

# --- self-test smoke (NON-counting) ----------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "passed"
}

# --- base-branch --file (the arm init-worktree actually uses) ----------------
# `base-branch` with no args returning "master" is the default fallback (:169).
# The pre-fetched-JSON arm — `--file <issue.json>` at :136-137, which
# init-worktree.sh:82 calls on every real run — was untested, so a regression in
# the body parse would silently send every worktree to master.

@test "base-branch --file: base_branch in the issue body wins over the default" {
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"Some preamble.\nbase_branch: develop\nMore text."}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch 42 --file "$WD/issue.json"
  assert_success
  assert_output "develop"
}

@test "base-branch --file: the --file=<path> spelling is equivalent" {
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"base_branch: release/2.1"}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch "--file=$WD/issue.json"
  assert_success
  assert_output "release/2.1"
}

@test "base-branch --file: lowercase declarations tolerate indentation and padding" {
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"   base_branch:   feature/spike  \ntrailing"}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch --file "$WD/issue.json"
  assert_success
  assert_output "feature/spike"
}

@test "base-branch --file: a capitalised key is parsed case-insensitively" {
  # R4-DV2: the key was detected with `grep -Ei` but stripped with a case-SENSITIVE
  # sed, so `Base_Branch:` passed the grep, survived the strip, and was emitted as
  # the literal branch name `Base_Branch:feature/spike` — which init-worktree.sh:82
  # feeds straight into `git worktree add ... origin/<base>`. Detect and strip now
  # agree (sed `I` flag).
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"  Base_Branch:   feature/spike  \ntrailing"}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch --file "$WD/issue.json"
  assert_success
  assert_output "feature/spike"
}

@test "base-branch --file: an all-caps key is parsed case-insensitively" {
  # Second casing, distinct from the mixed-case arm above: the sed `I` flag must
  # cover the whole key, not just its first letter.
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"BASE_BRANCH: release/1.2\n"}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch --file "$WD/issue.json"
  assert_success
  assert_output "release/1.2"
}

@test "base-branch --file: the FIRST declaration wins when several appear" {
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"base_branch: first\nbase_branch: second"}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch --file "$WD/issue.json"
  assert_success
  assert_output "first"
}

@test "base-branch --file: a body with no declaration falls back, not errors" {
  WD="$(mk_tmpworkdir)"
  jq -n '{body:"No branch directive anywhere in this issue."}' > "$WD/issue.json"
  run_script "$SCRIPT" base-branch --file "$WD/issue.json"
  assert_success
  # develop only when it exists on origin; otherwise the master default.
  [[ "$output" = "master" || "$output" = "develop" ]]
}

@test "base-branch --file: an empty body and a missing file both degrade quietly" {
  WD="$(mk_tmpworkdir)"
  jq -n '{body:""}' > "$WD/empty.json"
  run_script "$SCRIPT" base-branch --file "$WD/empty.json"
  assert_success
  [[ "$output" = "master" || "$output" = "develop" ]]
  run_script "$SCRIPT" base-branch --file "$WD/does-not-exist.json"
  assert_success
  [[ "$output" = "master" || "$output" = "develop" ]]
}

@test "base-branch: an unknown argument is rejected (exit 1)" {
  run_script "$SCRIPT" base-branch --bogus
  assert_failure 1
}
