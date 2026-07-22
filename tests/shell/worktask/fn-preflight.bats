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

@test "unknown command => exit 2 via usage" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" bogus-cmd
  assert_failure 2
  assert_output --partial "unknown argument"
}
