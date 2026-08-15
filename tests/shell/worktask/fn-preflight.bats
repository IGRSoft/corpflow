#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/fn-preflight.sh.
# Contracts (from header + agents/project-manager.md § FN Stage):
#   - attachments: both Conductor files present => exit 0; missing => exit 1
#   - resolve-issue: ranked first-match (state url > gh-issue.json > issue_number > branch)
#   - validate-pr: body carries Closes #<n> => pass; missing => BLOCKED exit 1;
#                  no issue resolvable => audit-defer row + exit 0
#   - continuity: ancestor => pass; diverged => diagnostic + audit row, exit 0 (non-blocking)
#   - unknown command/flag => exit 2
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
bats_require_minimum_version 1.5.0

SCRIPT="skills/worktask/scripts/fn-preflight.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/attachments"
  cat > "$WD/.context/state.json" <<'EOF'
{"version":1,"worktask_id":"wt-demo","run_index":2,"platform":"all",
 "plan_file":".context/planning-2.md","tasks":{"FN0":{"status":"in_progress"}},
 "facts":{},"handoffs":{},"metadata":{"github_issue_url":"https://github.com/o/r/issues/221"}}
EOF
}

mk_attachments() {
  printf 'pr\n' > "$WD/.context/attachments/PR instructions.md"
  printf 'rr\n' > "$WD/.context/attachments/Review request.md"
}

# A well-formed composed body: mandated heading + closing keyword, no leaks.
mk_body() {
  cat > "$WD/body.md" <<'EOF'
Summary of the work.

## Test plan

- bats tests/shell/worktask/fn-preflight.bats

Closes #221
EOF
}

# The observed-defect shape: a working-folder path line and an absolute path line.
mk_leaky_body() {
  cat > "$WD/body.md" <<'EOF'
Summary of the work.

Plan lives at .context/planning-2.md for reference.
Logs written to /Users/korich/secret/run.log during the run.

## Test plan

- bats tests/shell/worktask/fn-preflight.bats

Closes #221
EOF
}

# A visual-evidence row in attach-visual-evidence.sh `emit_pr` shape.
# $1 = run_index the row belongs to, $2 = result (ok|skipped).
mk_ve_row() {
  jq -cn --arg dk "wt-demo:$1:visual_evidence:pr" --arg r "$2" --argjson ri "$1" \
    '{ts:"2026-01-01T00:00:00Z", actor:"orchestrator",
      action:"visual_evidence_pr_emitted", result:$r,
      metadata:{worktask_id:"wt-demo", run_index:$ri, captures:0,
                host_tier:"none", reason:"fixture", dedupe_key:$dk}}' \
    >> "$WD/.context/logs/audit.jsonl"
}

no_screenshots() {
  jq '.metadata.requires_screenshots = false' "$WD/.context/state.json" > "$WD/s" \
    && mv "$WD/s" "$WD/.context/state.json"
}

@test "attachments: both present => exit 0" {
  cd "$WD"
  mk_attachments
  run bash "$PLUGIN_ROOT/$SCRIPT" attachments
  assert_success
  assert_output --partial "both present"
}

@test "attachments: missing Review request => BLOCKED exit 1" {
  cd "$WD"
  printf 'pr\n' > "$WD/.context/attachments/PR instructions.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" attachments
  assert_failure 1
  assert_output --partial "Review request.md"
}

@test "resolve-issue: state.json github_issue_url wins (rank 1)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" resolve-issue
  assert_success
  assert_output "221"
}

@test "resolve-issue: gh-issue.json .number used when url absent (rank 2)" {
  cd "$WD"
  jq 'del(.metadata.github_issue_url)' .context/state.json > s && mv s .context/state.json
  printf '{"number":314}\n' > .context/gh-issue.json
  run bash "$PLUGIN_ROOT/$SCRIPT" resolve-issue
  assert_success
  assert_output "314"
}

@test "resolve-issue: metadata.github_issue_number used (rank 3, megatask)" {
  cd "$WD"
  jq 'del(.metadata.github_issue_url) | .metadata.github_issue_number=99' \
    .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" resolve-issue
  assert_success
  assert_output "99"
}

@test "validate-pr: body with Closes #221 passes" {
  cd "$WD"
  printf 'Some work.\n\nCloses #221\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" validate-pr --body body.md
  assert_success
  assert_output --partial "closes #221"
}

@test "validate-pr: body missing the closing keyword => BLOCKED exit 1" {
  cd "$WD"
  printf 'Some work with no closing line.\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" validate-pr --body body.md
  assert_failure 1
  assert_output --partial "missing"
}

@test "validate-pr: case-insensitive Fixes/Resolves accepted" {
  cd "$WD"
  printf 'x\n\nfixes #221\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" validate-pr --body body.md
  assert_success
}

@test "validate-pr: no issue resolvable => audit-defer row + exit 0" {
  cd "$WD"
  # Strip every issue source; run outside a git repo dir so branch parse yields nothing.
  jq 'del(.metadata)' .context/state.json > s && mv s .context/state.json
  printf 'body without issue\n' > body.md
  run env GIT_CEILING_DIRECTORIES="$WD" bash "$PLUGIN_ROOT/$SCRIPT" validate-pr --body body.md
  assert_success
  assert_output --partial "audit-deferred"
  run grep -c '"reason":"no_issue_resolved"' .context/logs/audit.jsonl
  assert_output "1"
}

@test "validate-pr: missing --body => usage exit 2" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" validate-pr
  assert_failure 2
}

@test "continuity: ancestor HEAD passes (fast-forward safe)" {
  cd "$WD"
  git init -q .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "base"
  jq '.metadata.base_ref="'"$(git rev-parse --abbrev-ref HEAD)"'"' \
    .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" continuity
  assert_success
  assert_output --partial "fast-forward safe"
}

@test "continuity: a diverged HEAD records the cherry-pick fallback and still exits 0" {
  # Carried from DV2/DV3: only the ancestor arm was covered, so the branch that
  # actually changes FN0's merge strategy had no test at all.
  cd "$WD"
  git init -q .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "base"
  git branch -q integration
  # One commit on the checked-out branch that `integration` does not carry, so
  # HEAD is not an ancestor of it.
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "worktask work"
  jq '.metadata.base_ref="integration"' .context/state.json > s && mv s .context/state.json
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" continuity
  # Divergence is a documented fallback, not a hard block.
  assert_success
  [[ "$stderr" == *"diverged"* ]]
  [[ "$stderr" == *"cherry-pick"* ]]
  # commit_count is the observable that proves the divergence was MEASURED rather
  # than merely detected — a row with the right verdict but a wrong/zero count
  # would mean the operator is told nothing about how much work is at risk.
  run jq -se 'map(select(.action=="branch_continuity"))[-1]
              | [.result, .metadata.integration_branch, .metadata.commit_count]' \
    .context/logs/audit.jsonl
  assert_output --partial '"diverged_cherry_pick"'
  assert_output --partial '"integration"'
  assert_output --partial '1'
}

# ---------------------------------------------------------------------------
# pr-body — body-composition gate (REQ-4/REQ-5/REQ-6)
# ---------------------------------------------------------------------------

@test "F1: pr-body strips working-folder path lines and snapshots the original" {
  cd "$WD"
  no_screenshots
  mk_leaky_body
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  run cat body.md
  refute_output --partial ".context/planning-2.md"
  refute_output --partial "/Users/korich/secret"
  assert_output --partial "## Test plan"
  [ -f "$WD/.context/logs/pr-body-2.presanitise.md" ]
  run grep -c '"action":"pr_body_sanitised"' .context/logs/audit.jsonl
  assert_output "1"
}

@test "F2: pr-body blocks a body with no Test plan heading" {
  cd "$WD"
  no_screenshots
  printf 'Summary only.\n\nCloses #221\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_failure 1
  assert_output --partial "Test plan"
  run jq -r 'select(.action=="pr_body_gate") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "missing_test_plan_heading"
}

@test "F3: pr-body blocks when requires_screenshots and no visual-evidence row" {
  cd "$WD"
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_failure 1
  assert_output --partial "visual_evidence_pr_emitted"
  run jq -r 'select(.action=="pr_body_gate") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "missing_visual_evidence_row"
}

@test "F4: pr-body passes with an ok row and a Visual evidence section" {
  cd "$WD"
  mk_ve_row 2 ok
  cat > body.md <<'EOF'
Summary.

## Visual evidence

![shot](https://example.invalid/a.png)

## Test plan

- bats

Closes #221
EOF
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
}

@test "F5: pr-body blocks when the ok row's section was dropped from the body" {
  cd "$WD"
  mk_ve_row 2 ok
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_failure 1
  run jq -r 'select(.action=="pr_body_gate") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "missing_visual_evidence_section"
}

@test "F6: pr-body passes on a skipped row with no section (nothing was captured)" {
  cd "$WD"
  mk_ve_row 2 skipped
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
}

@test "F7: pr-body ignores a row from an earlier run index" {
  cd "$WD"
  mk_ve_row 1 ok
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_failure 1
  run jq -r 'select(.action=="pr_body_gate") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "missing_visual_evidence_row"
}

@test "F8: MILESTONE_MODE=1 skips the gate on a body that fails F1-F3" {
  cd "$WD"
  printf 'Leak at /Users/korich/secret/run.log and no headings.\n' > body.md
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  assert_output --partial "skipped (milestone_mode_env)"
  run jq -r 'select(.action=="pr_body_gate") | .result' .context/logs/audit.jsonl
  assert_output "skipped"
  # The body must be untouched: batch routing keeps today's behaviour byte-for-byte.
  run cat body.md
  assert_output --partial "/Users/korich/secret/run.log"
}

@test "F9: metadata.milestone skips the gate" {
  cd "$WD"
  jq '.metadata.milestone = "v3.37"' .context/state.json > s && mv s .context/state.json
  printf 'Leak at /Users/korich/secret/run.log and no headings.\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  assert_output --partial "milestone_metadata"
}

@test "F10: workspace.json at \$PWD skips the gate" {
  cd "$WD"
  printf '{"git":{"base_branch":"master"}}\n' > workspace.json
  printf 'Leak at /Users/korich/secret/run.log and no headings.\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  assert_output --partial "workspace_record"
}

@test "F11: an IR stage (incident pipeline) skips the gate" {
  cd "$WD"
  jq '.tasks.IR0 = {"status":"completed"}' .context/state.json > s && mv s .context/state.json
  printf 'Leak at /Users/korich/secret/run.log and no headings.\n' > body.md
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  assert_output --partial "incident_pipeline"
}

@test "F12: an unreachable sanitiser library blocks and names the path" {
  cd "$WD"
  mkdir -p "$WD/lonely"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/lonely/fn-preflight.sh"
  # branch-lib.sh must ship alongside fn-preflight.sh — this test isolates the
  # OTHER sibling (publish-pl-issue.sh) being unreachable, not this one.
  cp "$PLUGIN_ROOT/skills/worktask/scripts/branch-lib.sh" "$WD/lonely/branch-lib.sh"
  no_screenshots
  mk_body
  run bash "$WD/lonely/fn-preflight.sh" pr-body --body body.md
  assert_failure 1
  assert_output --partial "sanitiser unavailable"
  assert_output --partial "$WD/lonely/publish-pl-issue.sh"
  run jq -r 'select(.action=="pr_body_gate") | .metadata.reason' .context/logs/audit.jsonl
  assert_output "sanitiser_unavailable"
}

@test "F13: all sanitises before validate-pr sees the body" {
  cd "$WD"
  mk_attachments
  no_screenshots
  mk_leaky_body
  run bash "$PLUGIN_ROOT/$SCRIPT" all --body body.md
  assert_success
  assert_output --partial "closes #221"
  run cat body.md
  refute_output --partial "/Users/korich/secret"
  assert_output --partial "Closes #221"
}

@test "F14: scope parity — each shared is_milestone_mode signal disables the gate" {
  cd "$WD"
  printf 'Leak at /Users/korich/secret/run.log and no headings.\n' > body.md
  # 1. MILESTONE_MODE env override
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  # 2. state.json .metadata.milestone
  jq '.metadata.milestone = "v3.37"' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  jq 'del(.metadata.milestone)' .context/state.json > s && mv s .context/state.json
  # 3. workspace.json under WORKSPACE_ROOT
  mkdir -p "$WD/ws"
  printf '{}\n' > "$WD/ws/workspace.json"
  run env WORKSPACE_ROOT="$WD/ws" bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
  assert_output --partial "workspace_record"
}

@test "F23: batch scope answers before the unreachable-library check ever runs" {
  cd "$WD"
  mkdir -p "$WD/lonely"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/lonely/fn-preflight.sh"
  cp "$PLUGIN_ROOT/skills/worktask/scripts/branch-lib.sh" "$WD/lonely/branch-lib.sh"
  printf 'Leak at /Users/korich/secret/run.log and no headings.\n' > body.md
  cp body.md body.orig.md
  run env MILESTONE_MODE=1 bash "$WD/lonely/fn-preflight.sh" pr-body --body body.md
  assert_success
  assert_output --partial "skipped (milestone_mode_env)"
  run diff body.md body.orig.md
  assert_success
}

@test "F22: the emitted dedupe key is the key the gate matches on (REQ-9)" {
  cd "$WD"
  no_screenshots
  # Producer: the real helper writes its own row for this run.
  run env WORKSPACE_ROOT="$WD" bash \
    "$PLUGIN_ROOT/skills/worktask/scripts/attach-visual-evidence.sh" --emit pr
  assert_success
  run jq -r 'select(.action=="visual_evidence_pr_emitted") | .metadata.dedupe_key' \
    .context/logs/audit.jsonl
  assert_output "wt-demo:2:visual_evidence:pr"
  # Consumer: the same row now has to satisfy a screenshot-requiring run.
  jq '.metadata.requires_screenshots = true' .context/state.json > s && mv s .context/state.json
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body --body body.md
  assert_success
}

# ---------------------------------------------------------------------------
# continuity — integration-branch resolution (REQ-11)
# ---------------------------------------------------------------------------

@test "F15: metadata.base_ref wins over the removed 'main' literal" {
  cd "$WD"
  git init -q -b master .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "base"
  jq '.metadata.base_ref = "master" | del(.git)' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" continuity
  assert_success
  assert_output --partial "ancestor of master"
  refute_output --partial "main"
}

@test "F16: origin/HEAD is used when neither state field is set" {
  cd "$WD"
  git init -q -b trunk .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "base"
  # Fabricate the remote default-branch pointer without a network remote.
  git update-ref refs/remotes/origin/trunk HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  jq 'del(.git) | del(.metadata.base_ref)' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" continuity
  assert_success
  assert_output --partial "trunk"
}

@test "F17: nothing resolvable => base_ref_unresolved audit row, exit 0" {
  cd "$WD"
  git init -q -b master .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "base"
  jq 'del(.git) | del(.metadata.base_ref)' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" continuity
  assert_success
  assert_output --partial "unresolvable"
  run jq -r 'select(.action=="branch_continuity") | .result' .context/logs/audit.jsonl
  assert_output "base_ref_unresolved"
}

@test "F17b: FN_BASE_REF outranks every state field" {
  cd "$WD"
  git init -q -b master .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "base"
  jq '.metadata.base_ref = "never-used"' \
    .context/state.json > s && mv s .context/state.json
  printf '{"git":{"base_branch":"also-not"}}\n' > workspace.json
  run env FN_BASE_REF=master bash "$PLUGIN_ROOT/$SCRIPT" continuity
  assert_success
  assert_output --partial "ancestor of master"
}

# ---------------------------------------------------------------------------
# branch-name removed from this validator (moved to the PL stage,
# skills/worktask/scripts/branch-name.sh) — the removed argument must be
# rejected, not silently accepted.
# ---------------------------------------------------------------------------

@test "the removed branch-name argument is rejected with a usage exit" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-name
  assert_failure 2
  assert_output --partial "unknown argument"
}

@test "--help never mentions the removed branch-name command" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --help
  assert_failure 2
  run bash -c "bash '$PLUGIN_ROOT/$SCRIPT' --help 2>&1 | grep -c 'branch-name'"
  assert_output "0"
}

# ---------------------------------------------------------------------------
# resolve-issue rank 4 — tightened to the leading <type>/<NNN>-<slug> shape
# ---------------------------------------------------------------------------

@test "resolve-issue: rank 4 resolves the leading <type>/<NNN>-<slug> branch shape" {
  cd "$WD"
  jq 'del(.metadata.github_issue_url)' .context/state.json > s && mv s .context/state.json
  rm -f .context/gh-issue.json
  git init -q -b "feature/42-add-login-flow" .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "work"
  run bash "$PLUGIN_ROOT/$SCRIPT" resolve-issue
  assert_success
  assert_output "42"
}

@test "AC-11: rank 4 does NOT resolve a bogus issue from a digit-terminated ticket-less slug" {
  cd "$WD"
  jq 'del(.metadata.github_issue_url)' .context/state.json > s && mv s .context/state.json
  rm -f .context/gh-issue.json
  git init -q -b "feature/migrate-to-swift-6" .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m "work"
  run bash "$PLUGIN_ROOT/$SCRIPT" resolve-issue
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# T4 — branch-lib.sh moved aside: fn-preflight.sh exits 3, no dispatch runs.
# ---------------------------------------------------------------------------

@test "T4: fn-preflight.sh exits 3 with the path on stderr when branch-lib.sh is unreachable" {
  cd "$WD"
  # Safe pattern (never mv the tracked file — an interrupt would leave the
  # plugin broken): copy fn-preflight.sh alone into a sibling-free temp dir,
  # deliberately without branch-lib.sh alongside it.
  mkdir -p "$WD/lonely"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/lonely/fn-preflight.sh"
  run --separate-stderr bash "$WD/lonely/fn-preflight.sh" attachments
  assert_failure 3
  # DR-3: prove the path lands on stderr, not merely somewhere in the merged
  # stream — this test's own name claims "with the path on stderr".
  [[ "$stderr" == *"branch-lib.sh"* ]]
  assert_output ""
  run bash "$WD/lonely/fn-preflight.sh" resolve-issue
  assert_failure 3
}

@test "pr-body: missing --body => usage exit 2" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" pr-body
  assert_failure 2
}

@test "unknown command => exit 2 via usage" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" bogus-cmd
  assert_failure 2
  assert_output --partial "unknown argument"
}

# ---------------------------------------------------------------------------
# SR0 rework — SR-4 (MEDIUM, CWE-427): CDPATH=. must not corrupt LIB_PATH
# resolution or spuriously trip the exit-3 unreachable-library guard.
# ---------------------------------------------------------------------------

@test "SR-4: CDPATH=. does not corrupt library resolution (attachments still dispatches)" {
  cd "$WD"
  mk_attachments
  run env CDPATH=. bash "$PLUGIN_ROOT/$SCRIPT" attachments
  assert_success
  refute_output --partial "unreachable"
}

@test "SR-2/SR-4: a symlinked fn-preflight.sh still resolves its real sibling branch-lib.sh" {
  cd "$WD"
  mk_attachments
  mkdir -p linked
  ln -s "$PLUGIN_ROOT/$SCRIPT" linked/fn-preflight.sh
  run bash linked/fn-preflight.sh attachments
  assert_success
  refute_output --partial "unreachable"
}

# ---------------------------------------------------------------------------
# AC-10 case 8 (R6) — branch-divergence: has anything outside the pipeline
# renamed the local branch since the naming step?
#
# The comparison base is the `to` of the last `branch_renamed / ok` row, NOT
# facts.branch. That choice is what makes the check useful AND what makes R4
# structurally unable to trip it — both are asserted below, because the
# orthogonality is a design claim, not an accident.
# ---------------------------------------------------------------------------

mk_div_repo() {
  local branch="${1:-feature/add-a-new-login-flow}"
  git init -q -b "$branch" "$WD"
  git -C "$WD" -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m work
}

# The row branch-name.sh writes on a successful rename.
mk_renamed_ok_row() {
  jq -cn --arg to "$1" \
    '{ts:"2026-01-01T00:00:00Z", actor:"product-manager", action:"branch_renamed",
      subject:"PL2", result:"ok", task_id:"PL0",
      metadata:{from:"moab-v1", to:$to, origin_stage:"PL",
                dedupe_key:"wt-demo:2:branch_renamed"}}' \
    >> "$WD/.context/logs/audit.jsonl"
}

# Reads with the same AD-9-tolerant idiom the script uses: one corrupt line in the fixture
# must not break the assertion helper either.
div_row() {
  jq -rs -R "[ split(\"\n\")[] | fromjson? | objects
    | select(.action==\"branch_divergence_detected\") | .$1 ] | (last // \"\")" \
    "$WD/.context/logs/audit.jsonl"
}

@test "branch-divergence: a third-party rename is detected and classed third_party" {
  cd "$WD"
  mk_div_repo "which-stages-ran-tests"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  assert_output --partial "renamed by something outside the pipeline"
  run div_row 'metadata.class'
  assert_output "third_party"
  run div_row 'result'
  assert_output "warn"
  run div_row 'metadata.local'
  assert_output "which-stages-ran-tests"
  run div_row 'metadata.renamed_to'
  assert_output "feature/add-a-new-login-flow"
  run div_row 'metadata.source'
  assert_output "fn_preflight"
}

@test "branch-divergence: local matching the ok row is expected, not third_party" {
  cd "$WD"
  mk_div_repo "feature/add-a-new-login-flow"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  assert_output --partial "class=expected"
  run div_row 'metadata.class'
  assert_output "expected"
}

# The deferred / no-op arms never renamed anything, so there is no ok row and nothing
# can be classed third_party — divergence there is designed, not external.
@test "branch-divergence: no branch_renamed ok row means expected, never third_party" {
  cd "$WD"
  mk_div_repo "moab-v1"
  jq -cn '{ts:"2026-01-01T00:00:00Z", actor:"product-manager", action:"branch_renamed",
           subject:"PL2", result:"skipped", task_id:"PL0",
           metadata:{reason:"host_workspace_worktree", branch:"moab-v1",
                     target:"feature/add-a-new-login-flow", origin_stage:"PL",
                     dedupe_key:"wt-demo:2:branch_renamed"}}' \
    >> .context/logs/audit.jsonl
  jq '.facts.branch = "feature/add-a-new-login-flow"' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  run div_row 'metadata.class'
  assert_output "expected"
  run div_row 'metadata.renamed_to'
  assert_output ""
}

# R4 rewrites facts.branch and never touches git. Because the base is the ok row's `to`
# and not facts.branch, a refinement cannot look like an external rename.
@test "branch-divergence: an R4 refinement cannot trip the check (orthogonality)" {
  cd "$WD"
  mk_div_repo "feature/add-a-new-login-flow"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  # Exactly what refine-branch-target.sh does: the LEDGER moves, git does not.
  jq '.facts.branch = "feature/derive-branch-names-from-a-title"' .context/state.json > s \
    && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  run div_row 'metadata.class'
  assert_output "expected"
  # The row still records the disagreement it saw — it just does not call it third_party.
  run div_row 'metadata.ledger'
  assert_output "feature/derive-branch-names-from-a-title"
  run div_row 'metadata.local'
  assert_output "feature/add-a-new-login-flow"
  # Had the check compared against facts.branch, this would have been third_party.
  refute_output "feature/derive-branch-names-from-a-title"
}

@test "branch-divergence: non-blocking — exit 0 on every arm, including detection" {
  cd "$WD"
  mk_div_repo "which-stages-ran-tests"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  # no repo at all
  rm -rf .git
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  # no audit log at all
  rm -f .context/logs/audit.jsonl
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
}

@test "branch-divergence: jq unavailable — skipped, exit 0, no row" {
  cd "$WD"
  mk_div_repo "which-stages-ran-tests"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  local nobin tool p
  nobin="$WD/nobin"
  mkdir -p "$nobin"
  for tool in git grep sed tr cut date mkdir bash sh env printf true false cat awk readlink dirname basename; do
    p=$(command -v "$tool" 2> /dev/null) || continue
    ln -sf "$p" "$nobin/$tool"
  done
  run env PATH="$nobin" bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  assert_output --partial "jq unavailable"
  run bash -c "grep -c branch_divergence_detected .context/logs/audit.jsonl || true"
  assert_output "0"
}

# AD-9 idiom: one unparsable line must not blind the scan.
@test "branch-divergence: a corrupt audit line does not blind the scan" {
  cd "$WD"
  mk_div_repo "which-stages-ran-tests"
  printf 'not json at all\n' >> .context/logs/audit.jsonl
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  run div_row 'metadata.class'
  assert_output "third_party"
}

@test "branch-divergence: the most recent ok row wins" {
  cd "$WD"
  mk_div_repo "feature/second-name"
  mk_renamed_ok_row "feature/first-name"
  mk_renamed_ok_row "feature/second-name"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  run div_row 'metadata.class'
  assert_output "expected"
  run div_row 'metadata.renamed_to'
  assert_output "feature/second-name"
}

@test "branch-divergence: detached HEAD is expected, never third_party" {
  cd "$WD"
  mk_div_repo "feature/add-a-new-login-flow"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  git checkout -q --detach HEAD
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  run div_row 'metadata.class'
  assert_output "expected"
  run div_row 'metadata.local'
  assert_output ""
}

@test "branch-divergence: is not part of the all pipeline" {
  cd "$WD"
  mk_div_repo "which-stages-ran-tests"
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  mk_attachments
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" all --body "$WD/body.md"
  run bash -c "grep -c branch_divergence_detected .context/logs/audit.jsonl || true"
  assert_output "0"
}

# Companion to AC-10/3d: `fromjson?` alone survives an unparsable line but NOT a
# well-formed non-object one, which parses and then dies on `.action` — silently
# suppressing detection of a real third-party rename.
@test "branch-divergence: a well-formed non-object audit line does not suppress detection" {
  cd "$WD"
  mk_div_repo "which-stages-ran-tests"
  printf '123\n[1,2]\n"a bare string"\n' >> .context/logs/audit.jsonl
  mk_renamed_ok_row "feature/add-a-new-login-flow"
  run bash "$PLUGIN_ROOT/$SCRIPT" branch-divergence
  assert_success
  run div_row 'metadata.class'
  assert_output "third_party"
  run div_row 'metadata.renamed_to'
  assert_output "feature/add-a-new-login-flow"
}

# ---------------------------------------------------------------------------
# issue-close-required (REQ-9). GitHub honours a `Closes #N` trailer only on a
# merge into the DEFAULT branch, so any other integration branch silently leaves
# the issue open. Standalone, read-only, exit 0 always.
# ---------------------------------------------------------------------------

# A repo whose origin/HEAD points at <default>, with an issue-bearing state.json.
_mk_repo_with_default() {
  local default="$1"
  cd "$WD"
  git init -q -b "$default" .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m base
  git update-ref "refs/remotes/origin/$default" HEAD
  git symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$default"
}

@test "issue-close-required: a non-default integration branch requires an explicit close" {
  _mk_repo_with_default main
  jq '.metadata.base_ref="develop"' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" issue-close-required
  assert_success
  assert_output --partial "issue-close-required: yes"
  assert_output --partial "gh issue close 221"
  run jq -se 'map(select(.action=="issue_close_required"))[-1] | [.result, .metadata.base]' \
    .context/logs/audit.jsonl
  assert_output --partial '"required"'
  assert_output --partial '"develop"'
}

@test "issue-close-required: the repository default branch is a silent no-op" {
  _mk_repo_with_default main
  jq '.metadata.base_ref="main"' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" issue-close-required
  assert_success
  assert_output --partial "issue-close-required: no"
  refute_output --partial "gh issue close"
  run jq -se 'map(select(.action=="issue_close_required"))[-1] | .result' \
    .context/logs/audit.jsonl
  assert_output --partial '"not_required"'
}

@test "issue-close-required: an origin/ prefix on either side is not a false positive" {
  _mk_repo_with_default main
  jq '.metadata.base_ref="origin/main"' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" issue-close-required
  assert_success
  assert_output --partial "issue-close-required: no"
}

@test "issue-close-required: an unresolved integration branch degrades non-blocking" {
  cd "$WD"
  git init -q .
  git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m base
  # No base_ref in state.json and no origin/HEAD to fall back on.
  jq 'del(.metadata.base_ref)' .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" issue-close-required
  assert_success
  assert_output --partial "unresolved"
  refute_output --partial "gh issue close"
}

@test "issue-close-required: a required close with no resolvable issue says so and still exits 0" {
  _mk_repo_with_default main
  jq '.metadata.base_ref="develop" | del(.metadata.github_issue_url)' \
    .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" issue-close-required
  assert_success
  assert_output --partial "close it manually"
  run jq -se 'map(select(.action=="issue_close_required"))[-1] | .result' \
    .context/logs/audit.jsonl
  assert_output --partial '"issue_unresolved"'
}

@test "issue-close-required: it is NOT part of 'all' (cannot perturb the pre-PR battery)" {
  _mk_repo_with_default main
  jq '.metadata.base_ref="develop"' .context/state.json > s && mv s .context/state.json
  mk_attachments
  mk_body
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$WD/body.md" all
  refute_output --partial "issue-close-required"
}
