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

SCRIPT="skills/worktask/scripts/fn-preflight.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/attachments"
  cat > "$WD/.context/state.json" <<'EOF'
{"version":1,"worktask_id":"wt-demo","run_index":2,"platform":"all",
 "plan_file":".context/planning-2.md","stages":{"FN":{"status":"in_progress"}},
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
  jq '.git={"base_branch":"'"$(git rev-parse --abbrev-ref HEAD)"'"}' \
    .context/state.json > s && mv s .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" continuity
  assert_success
  assert_output --partial "fast-forward safe"
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
  jq '.stages.IR = {"status":"completed"}' .context/state.json > s && mv s .context/state.json
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
  jq '.metadata.base_ref = "never-used" | .git = {"base_branch":"also-not"}' \
    .context/state.json > s && mv s .context/state.json
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
  refute_output "6"
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
  run bash "$WD/lonely/fn-preflight.sh" attachments
  assert_failure 3
  assert_output --partial "branch-lib.sh"
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
