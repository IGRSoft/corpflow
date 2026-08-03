#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/branch-name.sh — the PL-stage entry
# point. Migrated from fn-preflight.bats's F18-F21c (rewritten for the ticket-less
# target and the new --goal/--check/--print-types argument surface), plus new cases.
# Canonical grammar/vocabulary/guard-ladder/exit-code contract:
# skills/shared/git-conventions.md § Branch Naming.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
bats_require_minimum_version 1.5.0

SCRIPT="skills/worktask/scripts/branch-name.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  cat > "$WD/.context/state.json" <<'EOF'
{"version":1,"worktask_id":"wt-demo","run_index":0,"platform":"systems",
 "plan_file":".context/planning-0.md","stages":{},"facts":{},"handoffs":{},"metadata":{}}
EOF
}

mk_branch_repo() {
  local branch="${1:-wt-abc123}" goal="${2:-Fix PR composition and branch naming}"
  git init -q -b "$branch" "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "work"
  jq --arg g "$goal" '.facts.goal = $g' "$WD/.context/state.json" > "$WD/s" \
    && mv "$WD/s" "$WD/.context/state.json"
}

# ---------------------------------------------------------------------------
# Migrated (6)
# ---------------------------------------------------------------------------

@test "M1: renames an anonymous branch to <type>/<slug>, no ticket" {
  cd "$WD"
  mk_branch_repo
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "->"
  assert_line --index 1 "target_branch=bugfix/fix-pr-composition-and-branch-naming"
  # `branch=` stays the FINAL line — four docs and every consumer specify that parse.
  assert_line --index "$((${#lines[@]} - 1))" "branch=bugfix/fix-pr-composition-and-branch-naming"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
  run jq -r 'select(.action=="branch_renamed") | .result' .context/logs/audit.jsonl
  assert_output "ok"
}

@test "M2: second run is a no-op (idempotency)" {
  cd "$WD"
  mk_branch_repo
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  local first
  first=$(git rev-parse --abbrev-ref HEAD)
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already conventional"
  run git rev-parse --abbrev-ref HEAD
  assert_output "$first"
}

@test "M3: refuses to rename a branch with an upstream" {
  cd "$WD"
  mk_branch_repo
  git remote add origin https://example.invalid/r.git
  git update-ref refs/remotes/origin/wt-abc123 HEAD
  git branch --set-upstream-to=origin/wt-abc123 wt-abc123 > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "upstream already tracked"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
  run jq -r 'select(.action=="branch_renamed") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "upstream_tracked"
}

@test "M4: self-disables under batch (MILESTONE_MODE) routing" {
  cd "$WD"
  mk_branch_repo
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "skipped (milestone_mode_env)"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
}

@test "M5: refuses to rename the integration branch itself" {
  cd "$WD"
  git init -q -b master "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "work"
  jq '.facts.goal = "Fix things" | .metadata.base_ref = "master"' .context/state.json > s \
    && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "integration branch"
  run git rev-parse --abbrev-ref HEAD
  assert_output "master"
}

@test "M6: BRANCH_NAME_PRINT=1 prints the bare target and renames nothing" {
  cd "$WD"
  mk_branch_repo
  run env BRANCH_NAME_PRINT=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
}

@test "detached HEAD prints branch= empty, never the literal token HEAD" {
  cd "$WD"
  mk_branch_repo
  git checkout -q --detach HEAD
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "detached HEAD"
  assert_line --index 1 "target_branch="
  assert_line --index 2 "branch="
}

# ---------------------------------------------------------------------------
# New (7)
# ---------------------------------------------------------------------------

@test "N1: fresh anonymous branch renames via an explicit --goal argument" {
  cd "$WD"
  git init -q -b anon-branch "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "work"
  run bash "$PLUGIN_ROOT/$SCRIPT" --goal "Add a new login flow"
  assert_success
  run git rev-parse --abbrev-ref HEAD
  assert_output "feature/add-a-new-login-flow"
}

@test "N2: target shape is feature/<slug> with no trailing -<digits> ticket segment" {
  cd "$WD"
  mk_branch_repo wt-xyz "Add a new login flow"
  run env BRANCH_NAME_PRINT=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_output --regexp -- '-[0-9]+$'
  assert_output "feature/add-a-new-login-flow"
}

@test "N3: already-conventional long form (feature/) is a no-op" {
  cd "$WD"
  mk_branch_repo "feature/already-named-thing"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already conventional"
  run git rev-parse --abbrev-ref HEAD
  assert_output "feature/already-named-thing"
}

@test "N4: already-conventional short form (feat/) is a no-op" {
  cd "$WD"
  mk_branch_repo "feat/221-already-named"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already conventional"
  run git rev-parse --abbrev-ref HEAD
  assert_output "feat/221-already-named"
}

@test "N4b: an existing fix/<slug> branch is non-conventional and gets renamed to bugfix/" {
  cd "$WD"
  mk_branch_repo "fix/legacy-crash-on-startup" "Fix crash on startup"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "->"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/fix-crash-on-startup"
}

@test "N4c: a goal containing hotfix yields hotfix/<slug>, not bugfix/<slug>" {
  cd "$WD"
  mk_branch_repo "wt-abc123" "Ship a hotfix for the login crash"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run git rev-parse --abbrev-ref HEAD
  assert_output "hotfix/ship-a-hotfix-for-the-login-crash"
}

@test "N4d: a goal carrying an issue key yields <type>/<ticket>-<slug> (D2)" {
  cd "$WD"
  mk_branch_repo "wt-abc123" "OV-164 Product images blink on catalog open"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/ov-164-product-images-blink-on-catalog-open"
}

@test "N4e: a long ticketed goal never lands on a mid-word slug (D3)" {
  cd "$WD"
  mk_branch_repo "wt-abc123" \
    "OV-164 Product list images are blinking before rendering on the catalog screen"
  run env BRANCH_NAME_PRINT=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output "bugfix/ov-164-product-list-images-are-blinking-before"
}

@test "N4f: a goal ending in the word fix is a bugfix, not a feature (D4)" {
  cd "$WD"
  mk_branch_repo "wt-abc123" "Images blink on catalog open, investigate and fix"
  run env BRANCH_NAME_PRINT=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output "bugfix/images-blink-on-catalog-open-investigate-and-fix"
}

@test "N4g: the shipped fix/catalog-image-blinking branch is renamed, not accepted (D1)" {
  cd "$WD"
  mk_branch_repo "fix/catalog-image-blinking" "Catalog images blink before rendering"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "->"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/catalog-images-blink-before-rendering"
}

@test "N4h: an existing ticketed branch is conventional and never churned (D2)" {
  cd "$WD"
  mk_branch_repo "bugfix/ov-156-reconstruction-scan-flow" "OV-156 reconstruction scan flow"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already conventional"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/ov-156-reconstruction-scan-flow"
}

@test "N5: upstream present is a no-op (exit 0)" {
  cd "$WD"
  mk_branch_repo
  git remote add origin https://example.invalid/r.git
  git update-ref refs/remotes/origin/wt-abc123 HEAD
  git branch --set-upstream-to=origin/wt-abc123 wt-abc123 > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "N6: on the integration branch is a no-op (exit 0)" {
  cd "$WD"
  git init -q -b master "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "work"
  jq '.metadata.base_ref = "master"' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

# Guard ladder, unchanged by the ticket/slug/type work — every arm still a no-op or a
# refusal, never a failure. Arms: already conventional (N3/N4/N4h), upstream tracked
# (M3/N5), integration branch (M5/N6), target exists (below + SR-1), detached HEAD /
# not a repo (the detached-HEAD case above).
@test "N6b: target exists is still a no-op when the target carries a ticket segment" {
  cd "$WD"
  mk_branch_repo "wt-abc123" "OV-156 reconstruction scan flow"
  git branch feature/ov-156-reconstruction-scan-flow
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already exists"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
  run jq -r 'select(.action=="branch_renamed") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "target_exists"
}

@test "N7: self-disables under incident (INCIDENT_MODE) routing" {
  cd "$WD"
  mk_branch_repo
  run env INCIDENT_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "skipped (incident_mode_env)"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
}

# ---------------------------------------------------------------------------
# already_conventional audit row (sign-off 3 / AC-9)
# ---------------------------------------------------------------------------

@test "already_conventional emits a noop audit row, not just a stdout partial" {
  cd "$WD"
  mk_branch_repo "feature/already-named-thing"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "no-op"
  run jq -r 'select(.action=="branch_renamed") | .result' .context/logs/audit.jsonl
  assert_output "noop"
  run jq -r 'select(.action=="branch_renamed") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "already_conventional"
}

@test "audit row records origin_stage PL and actor product-manager" {
  cd "$WD"
  mk_branch_repo
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -r 'select(.action=="branch_renamed") | .actor' .context/logs/audit.jsonl
  assert_output "product-manager"
  run jq -r 'select(.action=="branch_renamed") | .metadata.origin_stage' .context/logs/audit.jsonl
  assert_output "PL"
  run jq -r 'select(.action=="branch_renamed") | .subject' .context/logs/audit.jsonl
  assert_output "PL0"
}

# ---------------------------------------------------------------------------
# Batch-created shape recognised + the binding feature/lyon assertion (AC-4/AC-5)
# ---------------------------------------------------------------------------

@test "a batch-created feature/42-<slug> branch is recognised as conventional" {
  b=$(bash "$PLUGIN_ROOT/skills/shared/milestone-helpers/scripts/milestone-helpers.sh" \
    branch-name 42 "Add login flow")
  run bash "$PLUGIN_ROOT/$SCRIPT" --check "$b"
  assert_success
}

@test "AC-5 (binding): feature/lyon is recognised as conventional via --check only" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --check "feature/lyon"
  assert_success
}

@test "--check: a non-conventional name returns exit 1, silent" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --check "wt-abc123"
  assert_failure 1
  assert_output ""
}

@test "--print-types: emits the 13-token vocabulary, one per line, no fix" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --print-types
  assert_success
  assert_equal "${#lines[@]}" 13
  assert_line "feature"
  assert_line "feat"
  assert_line "bugfix"
  assert_line "hotfix"
  refute_line "fix"
}

# ---------------------------------------------------------------------------
# T4 (branch-name.sh half) — branch-lib.sh unreachable.
# ---------------------------------------------------------------------------

@test "T4: unreachable branch-lib.sh — rename mode exits 0 with a warning and a noop row" {
  cd "$WD"
  mk_branch_repo
  # Safe pattern (never mv the tracked library — an interrupt would leave the
  # plugin broken): copy branch-name.sh alone into a sibling-free temp dir.
  mkdir -p lonely
  cp "$PLUGIN_ROOT/$SCRIPT" lonely/branch-name.sh
  run --separate-stderr bash lonely/branch-name.sh
  assert_success
  # DR-3: the warning is on stderr specifically, not merely "present somewhere"
  # in the merged stream that --separate-stderr would otherwise hide.
  assert [ -n "$stderr" ]
  [[ "$stderr" == *"branch-lib.sh"* ]]
  assert_output --partial "library unreachable — skipped"
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch=wt-abc123"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
  run jq -r 'select(.action=="branch_renamed") | .result' .context/logs/audit.jsonl
  assert_output "noop"
  run jq -r 'select(.action=="branch_renamed") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "branch_lib_unreachable"
  run jq -r 'select(.action=="branch_renamed") | .metadata.origin_stage' .context/logs/audit.jsonl
  assert_output "PL"
}

@test "T4: unreachable branch-lib.sh — --check exits 2 with a diagnostic" {
  cd "$WD"
  mkdir -p lonely
  cp "$PLUGIN_ROOT/$SCRIPT" lonely/branch-name.sh
  run --separate-stderr bash lonely/branch-name.sh --check "feature/lyon"
  assert_failure 2
  [[ "$stderr" == *"branch-lib.sh"* ]]
}

# ---------------------------------------------------------------------------
# Usage / argument surface
# ---------------------------------------------------------------------------

@test "--goal without a value is a usage error (exit 2)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --goal
  assert_failure 2
}

@test "--state without a value is a usage error (exit 2)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state
  assert_failure 2
}

@test "--context without a value is a usage error (exit 2)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --context
  assert_failure 2
}

@test "--check without a value is a usage error (exit 2)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --check
  assert_failure 2
}

@test "unknown argument is a usage error (exit 2)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
}

@test "-h/--help exits 2 and prints the header" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --help
  assert_failure 2
  assert_output --partial "branch-name.sh"
}

# ---------------------------------------------------------------------------
# SR0 rework — SR-1 (HIGH, CWE-78/88), SR-4 (MEDIUM, CWE-427), SR-3
# (MEDIUM, CWE-778), SR-5 (LOW).
# ---------------------------------------------------------------------------

# git-legal, shell-hostile: `;`, `|`, `&`, backtick and `$(` are all permitted
# in a ref name by `git check-ref-format --branch`, but not by bash. No space
# (git rejects a space in a ref name outright) — mirrors security-review-0.md's
# executed PoC shape exactly (`fix/a$(id>/tmp/...)`).
HOSTILE_BRANCH='fix/a$(id>/tmp/branch-name-sr1-marker)'

mk_hostile_repo() {
  local marker="$1"
  rm -f "$marker"
  git init -q -b main "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m work
  git -C "$WD" branch -m "$HOSTILE_BRANCH"
}

@test "SR-1 (HIGH, PoC): upstream_tracked arm never emits the raw hostile branch" {
  cd "$WD"
  local marker="/tmp/branch-name-sr1-marker-a"
  mk_hostile_repo "$marker"
  git remote add origin https://example.invalid/r.git
  git update-ref "refs/remotes/origin/${HOSTILE_BRANCH}" HEAD
  git branch --set-upstream-to="origin/${HOSTILE_BRANCH}" "$HOSTILE_BRANCH" > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "upstream already tracked"
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch="
  refute_output --partial 'fix/a$('
  [ ! -e "$marker" ]
}

@test "SR-1: on_integration_branch arm never emits the hostile branch in the branch= line" {
  cd "$WD"
  local marker="/tmp/branch-name-sr1-marker-b"
  mk_hostile_repo "$marker"
  jq --arg b "$HOSTILE_BRANCH" '.metadata.base_ref = $b' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "integration branch"
  # The human-readable diagnostic MAY echo the raw name (operator-facing log
  # text, never re-interpolated) — only the `branch=` line is the contract
  # surface FN consumes, and that line specifically must never carry it.
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch="
  [ ! -e "$marker" ]
}

@test "SR-1: jq_unavailable arm never emits the raw hostile branch" {
  cd "$WD"
  local marker="/tmp/branch-name-sr1-marker-c"
  mk_hostile_repo "$marker"
  local nobin
  nobin="$WD/nobin"
  mkdir -p "$nobin"
  local tool
  for tool in git grep sed tr cut date mkdir bash sh env printf true false cat awk readlink dirname; do
    local p
    p=$(command -v "$tool" 2> /dev/null) || continue
    ln -sf "$p" "$nobin/$tool"
  done
  run env PATH="$nobin" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch="
  refute_output --partial 'fix/a$('
  [ ! -e "$marker" ]
}

@test "SR-1: fn_batch_scope (MILESTONE_MODE) arm never emits the raw hostile branch" {
  cd "$WD"
  local marker="/tmp/branch-name-sr1-marker-d"
  mk_hostile_repo "$marker"
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch="
  refute_output --partial 'fix/a$('
  [ ! -e "$marker" ]
}

@test "SR-1: target_exists arm never emits the raw hostile branch" {
  cd "$WD"
  local marker="/tmp/branch-name-sr1-marker-e"
  mk_hostile_repo "$marker"
  jq '.facts.goal = "Add login flow"' .context/state.json > s && mv s .context/state.json
  git branch feature/add-login-flow
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already exists"
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch="
  refute_output --partial 'fix/a$('
  [ ! -e "$marker" ]
}

@test "SR-5: no arm emits the literal token HEAD — detached + batch/incident + library-unreachable" {
  cd "$WD"
  mk_branch_repo
  git checkout -q --detach HEAD
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_line "branch=HEAD"
  assert_line --index "$(( ${#lines[@]} - 1 ))" "branch="

  run env INCIDENT_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_line "branch=HEAD"

  mkdir -p lonely
  cp "$PLUGIN_ROOT/$SCRIPT" lonely/branch-name.sh
  run bash lonely/branch-name.sh
  assert_success
  refute_line "branch=HEAD"
}

@test "SR-3: a completed rename never exits 0 silently when the audit sink is unwritable" {
  cd "$WD"
  mk_branch_repo
  mkdir -p ro/logs
  chmod 500 ro/logs
  run bash "$PLUGIN_ROOT/$SCRIPT" --context ro
  chmod 700 ro/logs
  assert_success
  assert_output --partial "->"
  assert_output --partial "audit row NOT recorded"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
}

@test "SR-4: CDPATH=. does not corrupt LIB_PATH or skip the guard ladder" {
  cd "$WD"
  mk_branch_repo
  run env CDPATH=. bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_output --partial "unreachable"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
}

# ---------------------------------------------------------------------------
# target_branch= — the derived remote name survives every no-op arm (Defect A),
# and the host-workspace arm (Defect C). The failure this closes: a run whose
# local rename was blocked stamped an empty/non-conventional `facts.branch`, so
# FN pushed the host-assigned name as the PR head.
# ---------------------------------------------------------------------------

# A linked worktree — the shape every worktree-based host provisions, and the only
# signal a host workspace reliably leaves (no workspace.json in $PWD).
mk_worktree_repo() {
  local branch="${1:-moab-v1}" goal="${2:-OV-166 Show all layers instead of zero at full score}"
  mkdir -p "$WD/main"
  git init -q -b master "$WD/main"
  git -C "$WD/main" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m work
  git -C "$WD/main" worktree add -b "$branch" "$WD/wt" > /dev/null 2>&1
  mkdir -p "$WD/wt/.context/logs"
  jq --arg g "$goal" '.facts.goal = $g' "$WD/.context/state.json" > "$WD/wt/.context/state.json"
}

# The documented Step 3c stamping rule, executed rather than paraphrased
# (commands/worktask.md § Step 3c — validate before stamping).
stamp_from_output() {
  local out="$1" local_branch target stamp
  local_branch=$(printf '%s\n' "$out" | sed -n 's/^branch=//p' | tail -n 1)
  target=$(printf '%s\n' "$out" | sed -n 's/^target_branch=//p' | tail -n 1)
  stamp="$local_branch"
  if [ -z "$stamp" ] || ! bash "$PLUGIN_ROOT/$SCRIPT" --check "$stamp"; then
    [ -n "$target" ] && stamp="$target"
  fi
  printf '%s' "$stamp"
}

@test "TB-1: host workspace — local name kept, conventional target emitted, HEAD untouched" {
  mk_worktree_repo
  cd "$WD/wt"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "host workspace"
  assert_line "target_branch=feature/ov-166-show-all-layers-instead-of-zero-at-full"
  run git rev-parse --abbrev-ref HEAD
  assert_output "moab-v1"
  run jq -r 'select(.action=="branch_renamed") | .result' .context/logs/audit.jsonl
  assert_output "skipped"
  run jq -r 'select(.action=="branch_renamed") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "host_workspace_worktree"
}

@test "TB-2: host workspace — the acceptance trio (local name, facts.branch, PR head)" {
  mk_worktree_repo
  cd "$WD/wt"
  local out
  out=$(bash "$PLUGIN_ROOT/$SCRIPT")
  # 1. the host's branch↔workspace mapping is intact
  run git rev-parse --abbrev-ref HEAD
  assert_output "moab-v1"
  # 2. + 3. what the orchestrator stamps, and therefore what FN pushes as the head
  run stamp_from_output "$out"
  assert_output "feature/ov-166-show-all-layers-instead-of-zero-at-full"
}

@test "TB-3: batch routing still wins over the host-workspace arm" {
  mk_worktree_repo
  cd "$WD/wt"
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "skipped (milestone_mode_env)"
  # /megatask names its own branches — a target here would invite a stamp it never planned.
  assert_line "target_branch="
  run git rev-parse --abbrev-ref HEAD
  assert_output "moab-v1"
}

@test "TB-3b: a subdirectory of a PLAIN repo is not a host workspace (rename still happens)" {
  cd "$WD"
  mk_branch_repo
  mkdir -p src/deep
  cd src/deep
  # git answers --git-dir absolutely and --git-common-dir relatively from here; a raw
  # string compare would read every nested cwd as a linked worktree.
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/.context/state.json" --context "$WD/.context"
  assert_success
  assert_line --index 0 --partial "->"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
}

@test "TB-3c: a subdirectory INSIDE a host workspace is still detected" {
  mk_worktree_repo
  mkdir -p "$WD/wt/src/deep"
  cd "$WD/wt/src/deep"
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/wt/.context/state.json" --context "$WD/wt/.context"
  assert_success
  assert_line --index 0 --partial "host workspace"
  assert_line "target_branch=feature/ov-166-show-all-layers-instead-of-zero-at-full"
  run git rev-parse --abbrev-ref HEAD
  assert_output "moab-v1"
}

@test "TB-4: upstream_tracked keeps the branch AND emits the derived target" {
  cd "$WD"
  mk_branch_repo "wt-abc123" "OV-166 Show all layers instead of zero at full score"
  git remote add origin https://example.invalid/r.git
  git update-ref refs/remotes/origin/wt-abc123 HEAD
  git branch --set-upstream-to=origin/wt-abc123 wt-abc123 > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "upstream already tracked"
  assert_line "target_branch=feature/ov-166-show-all-layers-instead-of-zero-at-full"
  # branch= unchanged from before this feature: the non-conventional local name is gated out.
  assert_line --index "$((${#lines[@]} - 1))" "branch="
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
}

@test "TB-5: target_exists keeps the branch AND emits the derived target" {
  cd "$WD"
  mk_branch_repo "wt-abc123" "OV-156 reconstruction scan flow"
  git branch feature/ov-156-reconstruction-scan-flow
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "already exists"
  assert_line "target_branch=feature/ov-156-reconstruction-scan-flow"
  run git rev-parse --abbrev-ref HEAD
  assert_output "wt-abc123"
}

@test "TB-6: jq_unavailable emits the target derived from an explicit --goal" {
  cd "$WD"
  mk_branch_repo
  local nobin tool p
  nobin="$WD/nobin"
  mkdir -p "$nobin"
  for tool in git grep sed tr cut date mkdir bash sh env printf true false cat awk readlink dirname; do
    p=$(command -v "$tool" 2> /dev/null) || continue
    ln -sf "$p" "$nobin/$tool"
  done
  run env PATH="$nobin" bash "$PLUGIN_ROOT/$SCRIPT" --goal "Add a new login flow"
  assert_success
  assert_line --index 0 --partial "target unresolvable"
  # The arm refuses the RENAME (batch scope is unknowable without jq); naming the PR
  # head needs no ledger read when the goal came in on argv.
  assert_line "target_branch=feature/add-a-new-login-flow"
}

@test "TB-7: no target on the arms that must not propose one" {
  cd "$WD"
  # already conventional — branch= is already the answer
  mk_branch_repo "feature/already-named-thing"
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line "target_branch="
  assert_line --index "$((${#lines[@]} - 1))" "branch=feature/already-named-thing"

  # integration branch — never a PR head under any name
  rm -rf "$WD/.git"
  git init -q -b master "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m work
  jq '.facts.goal = "Add a new login flow" | .metadata.base_ref = "master"' \
    .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 --partial "integration branch"
  assert_line "target_branch="
}

@test "TB-8: library unreachable emits both lines, target empty (nothing can derive it)" {
  cd "$WD"
  mk_branch_repo
  mkdir -p lonely
  cp "$PLUGIN_ROOT/$SCRIPT" lonely/branch-name.sh
  run bash lonely/branch-name.sh
  assert_success
  assert_line "target_branch="
  assert_line --index "$((${#lines[@]} - 1))" "branch=wt-abc123"
}

@test "TB-9 (SR-1): a shell-hostile current branch reaches neither emitted line" {
  cd "$WD"
  local marker="/tmp/branch-name-sr1-marker-f"
  mk_hostile_repo "$marker"
  jq '.facts.goal = "Add login flow"' .context/state.json > s && mv s .context/state.json
  git branch feature/add-login-flow
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # target_branch= carries the DERIVED name — conventional by construction, so the
  # hostile current name cannot ride along on either contract line.
  assert_line "target_branch=feature/add-login-flow"
  assert_line --index "$((${#lines[@]} - 1))" "branch="
  refute_output --partial 'fix/a$('
  [ ! -e "$marker" ]
}

@test "TB-10: BRANCH_NAME_PRINT dry run still prints the bare target, no key=value lines" {
  cd "$WD"
  mk_branch_repo
  run env BRANCH_NAME_PRINT=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
  refute_output --partial "target_branch="
}

@test "SR-2/SR-4: a symlinked script still resolves the real sibling branch-lib.sh" {
  cd "$WD"
  mk_branch_repo
  mkdir -p linked
  ln -s "$PLUGIN_ROOT/skills/worktask/scripts/branch-name.sh" linked/branch-name.sh
  run bash linked/branch-name.sh
  assert_success
  refute_output --partial "unreachable"
  run git rev-parse --abbrev-ref HEAD
  assert_output "bugfix/fix-pr-composition-and-branch-naming"
}
