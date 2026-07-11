#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/publish-pl-issue.sh (AC-4 priority).
# Asserted contracts (from script header + entrypoint):
#   - opt-out (NO_GH_ISSUE=true) => defer reason=opted_out, exit 0
#   - idempotency (metadata.github_issue_url set) => defer reason=already_published
#   - milestone-mode (MILESTONE_MODE=1) => defer reason=milestone_mode, exit 0,
#     BEFORE any gh probe (no issue create/comment)
#   - two-pass sanitiser strip-ratio >50% => defer reason=sanitiser_aborted,
#     writes .context/logs/issue-body-<run_index>.aborted.tmp, exit 0
#   - {{asset:<basename>}} token resolution => rewritten to ![base](url) via mock tier
#   - catastrophic: missing/corrupt state.json => exit 1
#   - --self-test => "pass=N fail=0", exit 0
#
# All gh side effects are avoided: every operational test hits an early-exit guard
# (opt-out/idempotency/milestone) or the strip-ratio abort (which exits BEFORE the
# issue-create branch). Where a guard requires gh to "pass", a no-op gh stub on
# PATH + DRY_RUN=1 satisfies the probes without any live API call.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/publish-pl-issue.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/designs" "$WD/bin"
  cp "$FIXTURES/worktask/publish-state.sample.json" "$WD/.context/state.json"
  cp "$FIXTURES/worktask/mostly-paths-plan.md" "$WD/.context/plan.md"
  cp "$FIXTURES/worktask/sanitiser-input.md" "$WD/.context/clean-plan.md"
  # tiny valid PNG header used as the {{asset:preview.png}} source
  printf '\x89PNG\r\n\x1a\n' > "$WD/.context/designs/preview.png"
  # no-op gh stub: satisfies `command -v gh` and `gh auth status` without API calls
  cat > "$WD/bin/gh" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
  chmod +x "$WD/bin/gh"
  LAST_AUDIT() { tail -1 "$WD/.context/logs/audit.jsonl"; }
}

@test "happy: milestone-mode (MILESTONE_MODE=1) defers before any gh probe" {
  cd "$WD"
  # GH_BIN points at a tripwire that FAILS if invoked — proves milestone-mode
  # exits before any gh call (Guard 2.5 precedes Guard 3/4).
  run env GH_BIN=/nonexistent/gh-tripwire MILESTONE_MODE=1 WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "milestone_mode"
  run jq -r '.result' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "deferred"
}

@test "happy: opt-out (NO_GH_ISSUE=true) defers reason=opted_out exit 0" {
  cd "$WD"
  run env NO_GH_ISSUE=true WORKSPACE_ROOT="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "opted_out"
}

@test "edge: idempotency — pre-set github_issue_url defers already_published" {
  cd "$WD"
  jq '.metadata.github_issue_url = "https://github.com/o/r/issues/7"' \
    .context/state.json > s2 && mv s2 .context/state.json
  run env WORKSPACE_ROOT="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "already_published"
}

@test "edge: two-pass sanitiser strip-ratio >50% aborts and resolves {{asset:}} token" {
  cd "$WD"
  # mostly-paths plan -> strip>50% -> sanitiser_aborted; the design-preview anchor
  # carries {{asset:preview.png}} which resolve_design_assets rewrites to a hosted
  # ![]() line in the aborted-body tmp using the gist mock base.
  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # audit row records the abort with a strip_ratio > 50
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "sanitiser_aborted"
  run jq -r '.metadata.strip_ratio > 50' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "true"
  # aborted body persisted
  [ -f "$WD/.context/logs/issue-body-0.aborted.tmp" ]
  # {{asset:preview.png}} resolved to a hosted markdown image line
  run cat "$WD/.context/logs/issue-body-0.aborted.tmp"
  assert_output --partial "![preview.png](https://mock.gist/raw/preview.png)"
  refute_output --partial "{{asset:"
  # forbidden local paths were line-stripped (L1 .context/, L2 /Users/)
  refute_output --partial ".context/planning"
  refute_output --partial "/Users/korich/secret"
}

@test "failure: missing state.json is catastrophic (exit 1)" {
  cd "$WD"
  rm -f .context/state.json
  run env WORKSPACE_ROOT="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 1
}

@test "failure: corrupt (non-JSON) state.json is catastrophic (exit 1)" {
  cd "$WD"
  printf 'not json {{{' > .context/state.json
  run env WORKSPACE_ROOT="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 1
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}
