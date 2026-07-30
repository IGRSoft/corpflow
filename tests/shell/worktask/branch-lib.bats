#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/branch-lib.sh.
# Structural tests (T1-T3) pin the R-4 residual risk (architecture-0.md):
# an unreachable library is the only failure mode this file may have.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/branch-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  cat > "$WD/.context/state.json" <<'EOF'
{"version":1,"worktask_id":"wt-demo","run_index":0,"platform":"systems",
 "plan_file":".context/planning-0.md","stages":{},"facts":{},"handoffs":{},"metadata":{}}
EOF
}

mk_no_jq_path() {
  local dir="$WD/nobin" tool p
  mkdir -p "$dir"
  for tool in git grep sed tr cut date mkdir bash sh env printf true false cat; do
    p=$(command -v "$tool" 2> /dev/null) || continue
    ln -sf "$p" "$dir/$tool"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T1 — double-source, one process, no state.json, strict mode: rc 0, no output.
# ---------------------------------------------------------------------------
@test "T1: branch-lib.sh sources twice cleanly under set -euo pipefail" {
  cd "$WD"
  run bash -c "set -euo pipefail; IFS=\$'\n\t'; . '$PLUGIN_ROOT/$LIB'; . '$PLUGIN_ROOT/$LIB'"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# T2 — symbol inventory: all 10 required functions defined after one source.
# ---------------------------------------------------------------------------
@test "T2: all 10 required symbols are defined after sourcing" {
  cd "$WD"
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    for f in branch_type_regex branch_is_conventional resolve_goal derive_type \
             derive_slug target_branch_name meta_json audit_fn fn_batch_scope \
             resolve_base_ref; do
      type -t \"\$f\" > /dev/null 2>&1 || { printf 'MISSING: %s\n' \"\$f\"; exit 1; }
    done
    exit 0
  "
  assert_success
}

# ---------------------------------------------------------------------------
# T3 — grep-based dependency-free structural assertion.
# ---------------------------------------------------------------------------
@test "T3: branch-lib.sh sources nothing, sets no options, no readonly, no global IFS" {
  run bash -c "grep -Ec '^[[:space:]]*(\.|source)[[:space:]]' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
  run bash -c "grep -Ec '^[[:space:]]*(set|shopt|trap)[[:space:]]' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
  run bash -c "grep -c '^readonly' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
  run bash -c "grep -Ec '^[[:space:]]*IFS=' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
}

# ---------------------------------------------------------------------------
# derive_type / derive_slug / target_branch_name — pure unit tests.
# ---------------------------------------------------------------------------
@test "derive_type: unmatched goal falls back to feature (not feat)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Add login flow'"
  assert_success
  assert_output "feature"
}

@test "derive_type: fix keywords map to fix" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Fix crash on startup'"
  assert_success
  assert_output "fix"
}

@test "derive_type: revert keyword maps to revert" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Revert the last release'"
  assert_success
  assert_output "revert"
}

@test "derive_type: never emits feat or style — output subset of BRANCH_TYPES emit set" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    for g in 'random goal' 'fix bug' 'refactor module' 'perf tuning' 'add docs' \
             'chore bump deps' 'ci pipeline' 'build packaging' 'test coverage' 'revert x'; do
      t=\$(derive_type \"\$g\")
      case \"\$t\" in feat|style) printf 'BAD: %s -> %s\n' \"\$g\" \"\$t\"; exit 1 ;; esac
    done
    exit 0
  "
  assert_success
}

@test "derive_slug: kebab-cases, trims, and caps at 48 chars" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_slug 'Fix: crash on startup!!!'"
  assert_success
  assert_output "fix-crash-on-startup"
}

@test "derive_slug: multi-line goal collapses to a single-line slug (regression)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_slug \$'Fix PR composition\nand branch naming'"
  assert_success
  refute_output --partial $'\n'
  assert_output "fix-pr-composition-and-branch-naming"
}

@test "target_branch_name: composes <type>/<slug>" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; target_branch_name feature add-login-flow"
  assert_success
  assert_output "feature/add-login-flow"
}

@test "target_branch_name: empty slug returns 1, no output" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; target_branch_name feature ''"
  assert_failure
  assert_output ""
}

# ---------------------------------------------------------------------------
# branch_is_conventional — AC-4 / AC-5.
# ---------------------------------------------------------------------------
@test "AC-4: milestone-helpers batch output is accepted by branch_is_conventional" {
  b=$(bash "$PLUGIN_ROOT/skills/shared/milestone-helpers/scripts/milestone-helpers.sh" \
    branch-name 42 "Add login flow")
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional '$b'"
  assert_success
}

@test "AC-5 (binding): feature/lyon is recognised as conventional" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'feature/lyon'"
  assert_success
}

@test "branch_is_conventional: a non-conventional name returns 1" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'wt-abc123'"
  assert_failure 1
}

@test "branch_is_conventional: already-conventional short form (feat) is accepted" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'feat/221-thing'"
  assert_success
}

# ---------------------------------------------------------------------------
# resolve_goal — ranked fallbacks (sign-offs 4/5/6).
# ---------------------------------------------------------------------------
@test "resolve_goal: explicit argument wins over the ledger" {
  cd "$WD"
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal 'explicit goal'"
  assert_success
  assert_output "explicit goal"
}

@test "resolve_goal: empty explicit argument ranks past to facts.goal (shell -z semantics)" {
  cd "$WD"
  jq '.facts.goal = "Ledger goal here"' .context/state.json > s && mv s .context/state.json
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal ''"
  assert_success
  assert_output "Ledger goal here"
}

@test "resolve_goal: empty goal AND empty facts.goal falls back to worktask_id" {
  cd "$WD"
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal ''"
  assert_success
  assert_output "wt-demo"
}

@test "resolve_goal: jq-less run cannot read the ledger — refuses down to empty" {
  cd "$WD"
  jq '.facts.goal = "Ledger goal here"' .context/state.json > s && mv s .context/state.json
  local nobin
  nobin=$(mk_no_jq_path)
  run env PATH="$nobin" bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal ''"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# fn_batch_scope — parity migration (F14 intent).
# ---------------------------------------------------------------------------
@test "fn_batch_scope: MILESTONE_MODE=1 self-disables" {
  cd "$WD"
  run env MILESTONE_MODE=1 bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; fn_batch_scope && printf '%s' \"\$SCOPE_REASON\""
  assert_success
  assert_output "milestone_mode_env"
}

@test "fn_batch_scope: no batch/incident signal returns 1" {
  cd "$WD"
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; fn_batch_scope"
  assert_failure 1
}
