#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/branch-name.sh — the PL-stage entry
# point. Migrated from fn-preflight.bats's F18-F21c (rewritten for the ticket-less
# target and the new --goal/--check/--print-types argument surface), plus new cases.
# Canonical grammar/vocabulary/guard-ladder/exit-code contract:
# skills/shared/git-conventions.md § Branch Naming.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

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
  assert_line --index 1 "branch=fix/fix-pr-composition-and-branch-naming"
  run git rev-parse --abbrev-ref HEAD
  assert_output "fix/fix-pr-composition-and-branch-naming"
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
  assert_output "fix/fix-pr-composition-and-branch-naming"
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
  assert_line --index 1 "branch="
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

@test "--print-types: emits the 12-token vocabulary, one per line" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --print-types
  assert_success
  assert_equal "${#lines[@]}" 12
  assert_line "feature"
  assert_line "feat"
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
  run bash lonely/branch-name.sh
  assert_success
  assert_output --partial "branch-lib.sh"
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
  run bash lonely/branch-name.sh --check "feature/lyon"
  assert_failure 2
  assert_output --partial "branch-lib.sh"
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
  assert_output "fix/fix-pr-composition-and-branch-naming"
}

@test "SR-4: CDPATH=. does not corrupt LIB_PATH or skip the guard ladder" {
  cd "$WD"
  mk_branch_repo
  run env CDPATH=. bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_output --partial "unreachable"
  run git rev-parse --abbrev-ref HEAD
  assert_output "fix/fix-pr-composition-and-branch-naming"
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
  assert_output "fix/fix-pr-composition-and-branch-naming"
}
