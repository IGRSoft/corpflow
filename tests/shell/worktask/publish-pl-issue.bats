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

# PP1/PP2 — plan_file shape boundary (REQ-1/REQ-3). state.json may carry either a
# workspace-relative path or a bare basename; both must resolve, and a genuinely
# absent plan must name every candidate on stderr.
@test "PP1: bare-basename plan_file resolves against the state dir (REQ-1)" {
  cd "$WD"
  cp "$FIXTURES/worktask/mostly-paths-plan.md" "$WD/.context/planning-2.md"
  jq '.plan_file = "planning-2.md"' .context/state.json > s2 && mv s2 .context/state.json
  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # Reaching the strip-ratio abort proves the plan was read: plan_unreadable exits
  # 1 several guards earlier and never produces this reason.
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "sanitiser_aborted"
}

@test "PP2: absent plan_file exits 1 and names both candidates on stderr (REQ-3)" {
  cd "$WD"
  jq '.plan_file = "ghost-plan.md"' .context/state.json > s2 && mv s2 .context/state.json
  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 1
  assert_output --partial "FATAL plan_unreadable"
  assert_output --partial "ghost-plan.md"
  assert_output --partial ".context/ghost-plan.md"
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "plan_unreadable"
}

# Issue #375 regression. `facts.goal` is optional in the handoff protocol; when it was
# the only source, an unset value published the kebab worktask slug as the title and an
# empty Summary. The chain and the case-insensitive prefix guard are asserted here at
# suite level, not only inside --self-test, because this is the shape that shipped.
@test "#375: unset facts.goal falls back to the plan title, not the worktask slug" {
  cd "$WD"
  cp "$PLUGIN_ROOT/skills/worktask/references/fixtures/publish-pl-issue/13-frontmatter-title.md" \
    "$WD/.context/plan.md"
  jq 'del(.facts.goal) | .worktask_id = "ov-164-catalog-image-blinking"' \
    .context/state.json > s2 && mv s2 .context/state.json

  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 GH_ISSUE_SEARCH=0 \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial '--title "OV-164 Product list images are blinking before rendering"'
  refute_output --partial "ov-164-catalog-image-blinking"
  refute_output --partial "OV-164 OV-164"

  # The same run must render a non-empty Summary, from the plan's own anchor.
  [ -f "$WD/.context/logs/issue-body-0.tmp" ]
  run awk '/^## Summary$/ { s = 1; next } /^## / { s = 0 } s' "$WD/.context/logs/issue-body-0.tmp"
  assert_output --partial "blinks on every scroll"
}

@test "#375: every title source empty degrades to the slug AND audits the degradation" {
  cd "$WD"
  cp "$PLUGIN_ROOT/skills/worktask/references/fixtures/publish-pl-issue/13c-no-title-source.md" \
    "$WD/.context/plan.md"
  jq 'del(.facts.goal) | .worktask_id = "wt-no-sources"' \
    .context/state.json > s2 && mv s2 .context/state.json

  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 GH_ISSUE_SEARCH=0 \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial '--title "wt-no-sources"'
  run jq -r 'select(.metadata.reason=="title_fallback_worktask_id") | .metadata.title_source' \
    "$WD/.context/logs/audit.jsonl"
  assert_output "worktask_id"
}

@test "#375: facts.goal still wins every later rank (no happy-path regression)" {
  cd "$WD"
  cp "$PLUGIN_ROOT/skills/worktask/references/fixtures/publish-pl-issue/13-frontmatter-title.md" \
    "$WD/.context/plan.md"
  jq '.facts.goal = "OV-164 Ship the catalog image cache"' \
    .context/state.json > s2 && mv s2 .context/state.json

  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 GH_ISSUE_SEARCH=0 \
    bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial '--title "OV-164 Ship the catalog image cache"'
  run grep -c "Ship the catalog image cache" "$WD/.context/logs/issue-body-0.tmp"
  refute_output "0"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}

@test "sanitiser L7/L8: BOTH the current and the pre-3.42.0 artifact names are stripped" {
  cd "$WD"
  # publish-pl-issue.sh:300 is a redaction superset: it kept `analyzing` when
  # 3.42.0 renamed the AR artifact to `architecture`, because a leak filter that
  # forgets a name can only leak more. Nothing asserted that branch before, so a
  # cleanup pass could have dropped the token silently.
  {
    printf '## requirements\n\n'
    printf 'A clean requirement sentence that must survive sanitisation.\n'
    printf 'architecture-0.md\n'
    printf 'analyzing-3.md\n'
    for i in 1 2 3 4 5 6 7 8 9 10; do
      printf 'Clean narrative line %s carrying no forbidden token at all.\n' "$i"
    done
  } > "$WD/.context/plan.md"

  run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success

  # Ratio stayed under the abort threshold, so this exercises the emit path.
  run jq -r '.metadata.reason // "none"' <(tail -1 "$WD/.context/logs/audit.jsonl")
  refute_output "sanitiser_aborted"

  # Assert the artifact exists rather than skipping on its absence: a skip counts
  # as a pass, which would let all three assertions below silently not run -- the
  # exact vacuous-coverage failure this test was written to close.
  [ -f "$WD/.context/logs/issue-body-0.tmp" ]
  body="$(cat "$WD/.context/logs/issue-body-0.tmp")"
  printf '%s' "$body" | grep -q 'architecture-0.md' && {
    echo "current artifact name leaked into the issue body"; return 1; }
  printf '%s' "$body" | grep -q 'analyzing-3.md' && {
    echo "PERMANENT-SUPERSET regressed: legacy name leaked into the issue body"; return 1; }
  printf '%s' "$body" | grep -q 'Clean narrative line 1' || {
    echo "sanitiser over-stripped: clean prose did not survive"; return 1; }
  return 0
}
