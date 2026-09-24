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
  # Recording gh double (mock_gh) rather than a bare `exit 0` script: it still
  # satisfies `command -v gh` and every probe, but every invocation is captured
  # so tests can assert what the script actually asked GitHub to do.
  mock_gh --default-exit 0
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

@test "happy: opt-out stamped on PL0's task metadata (the /worktask Step 4 site) defers opted_out" {
  cd "$WD"
  # /worktask Step 4 writes the flag on tasks.PL0.metadata, never on run-level
  # .metadata; a reader of the run-level key alone would publish anyway.
  jq '.tasks.PL0.metadata.no_gh_issue = true' .context/state.json > s2 && mv s2 .context/state.json
  run env GH_BIN=/nonexistent/gh-tripwire WORKSPACE_ROOT="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
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
  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 \
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
  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 \
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
  # RK5 (stderr honesty): this test's name claims the candidates are named "on
  # stderr", but a plain `run` merges the streams, so it passed either way.
  run_script_env --cwd "$WD" --stub-path --env "WORKSPACE_ROOT=$WD" \
    --env DRY_RUN=1 --separate-stderr -- "$SCRIPT"
  assert_failure 1
  [[ "$stderr" == *"FATAL plan_unreadable"* ]]
  [[ "$stderr" == *"ghost-plan.md"* ]]
  [[ "$stderr" == *".context/ghost-plan.md"* ]]
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

  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 GH_ISSUE_SEARCH=0 \
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

  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 GH_ISSUE_SEARCH=0 \
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

  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 GH_ISSUE_SEARCH=0 \
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

@test "sanitiser L7/L8: current artifact names are stripped, clean prose survives" {
  cd "$WD"
  {
    printf '## requirements\n\n'
    printf 'A clean requirement sentence that must survive sanitisation.\n'
    printf 'architecture-0.md\n'
    printf 'development-3.md\n'
    printf 'development-3-web.md\n'
    for i in 1 2 3 4 5 6 7 8 9 10; do
      printf 'Clean narrative line %s carrying no forbidden token at all.\n' "$i"
    done
  } > "$WD/.context/plan.md"

  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" DRY_RUN=1 bash "$PLUGIN_ROOT/$SCRIPT"
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
  printf '%s' "$body" | grep -q 'development-3.md' && {
    echo "artifact name leaked into the issue body"; return 1; }
  printf '%s' "$body" | grep -q 'development-3-web.md' && {
    echo "per-stream artifact name leaked into the issue body"; return 1; }
  printf '%s' "$body" | grep -q 'Clean narrative line 1' || {
    echo "sanitiser over-stripped: clean prose did not survive"; return 1; }
  return 0
}

@test "publish: the create path invokes gh issue create with the rendered body and records the URL" {
  cd "$WD"
  # A plan that survives sanitisation (strip ratio <=50%) reaches the create
  # branch. Routing the probes through mock_gh keeps the run offline while the
  # recorder captures the exact argv the script would send to GitHub.
  cat > "$WD/.context/publish-plan.md" <<'MD'
# Add a rate limiter to the ingest queue

## requirements

The ingest queue must reject bursts above the configured ceiling.
Callers receive a retriable error rather than a dropped message.

## acceptance-criteria

AC-1: a burst above the ceiling is rejected with a retriable error.
AC-2: traffic below the ceiling is unaffected.

## scope

In scope: the ingest queue admission check and its metrics.
Out of scope: the downstream consumer and its retry policy.

## complexity

Score: 12/50 (Low).
MD
  jq '.plan_file = ".context/publish-plan.md"' .context/state.json > s2 && mv s2 .context/state.json
  # owner/repo is parsed from `git remote get-url origin`; without it the script
  # defers with reason=no_remote long before the create branch.
  mk_git_fixture --dir "$WD" --remote 'git@github.com:o/r.git' >/dev/null
  mock_gh --default-exit 0 \
    --route 'auth status=0:' \
    --route 'repo view=0:private' \
    --route 'issue list=0:[]' \
    --route 'issue view=0:' \
    --route 'label list=0:' \
    --route 'label create=0:' \
    --route 'issue create=0:https://github.com/o/r/issues/42'

  run env PATH="$STUB_PATH" WORKSPACE_ROOT="$WD" ASSET_HOST_MODE=none \
    GH_ISSUE_SEARCH=0 bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success

  # Locate the create invocation among the recorded calls.
  local n=0 idx=0 line
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in "issue create "*) idx="$n" ;; esac
  done <<< "$(stub_log gh)"
  [ "$idx" -gt 0 ] || fail "gh issue create was never invoked; calls were:
$(stub_log gh)
audit: $(cat "$WD/.context/logs/audit.jsonl")
script output: $output"

  run stub_log --argv gh --call "$idx"
  assert_line "issue"
  assert_line "create"
  assert_line "--title"
  assert_line "--body-file"
  # The --body-file argument must carry a real path, not an empty placeholder.
  local body_arg=0 want_next=0
  while IFS= read -r line; do
    if [ "$want_next" -eq 1 ]; then [ -n "$line" ] && body_arg=1; break; fi
    [ "$line" = "--body-file" ] && want_next=1
  done <<< "$output"
  [ "$body_arg" -eq 1 ]

  # The returned URL is persisted for the idempotency guard and audited.
  run jq -r '.metadata.github_issue_url' "$WD/.context/state.json"
  assert_output "https://github.com/o/r/issues/42"
  assert_audit_row github_issue_created --file "$WD/.context/logs/audit.jsonl" \
    --jq '.metadata.url == "https://github.com/o/r/issues/42"'
}

# Companion to the attach-visual-evidence arm of the same name: the symlink refusal
# was pinned only for the hook-side emitter, and all four worktask emitters appended
# through a symlink. audit_row returns 1 here, which every call site already tolerates.
@test "SR: a symlinked audit.jsonl is refused, never written through" {
  cd "$WD"
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  rm -f "$WD/.context/logs/audit.jsonl"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  jq '.metadata.github_issue_url = "https://github.com/o/r/issues/7"' \
    .context/state.json > s2 && mv s2 .context/state.json
  run env WORKSPACE_ROOT="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

# ---------------------------------------------------------------------------
# _atomic_json — the tmp → fsync → mv tail the four JSON writers in
# publish-pl-issue-lib.sh each spelled out. The four copies left a truncated temp
# file on disk beside the ledger when jq died part-way; this one never renames a
# partial document and never leaves the temp behind.
# ---------------------------------------------------------------------------
lib_only() {  # lib_only <snippet> — run a snippet with the helper library loaded
  run bash -c "cd '$WD'; PUBLISH_LIB_ONLY=1 . '$PLUGIN_ROOT/$SCRIPT' > /dev/null 2>&1; $1"
}

@test "atomic: a complete document replaces the target" {
  printf '{"a":1}' > "$WD/t.json"
  lib_only "printf '%s' '{\"a\":2}' | _atomic_json t.json; echo rc=\$?; cat t.json; echo"
  assert_success
  assert_line --index 0 'rc=0'
  assert_line --index 1 '{"a":2}'
}

@test "atomic: an empty producer leaves the target untouched and rc 1" {
  printf '{"a":1}' > "$WD/t.json"
  lib_only "true | _atomic_json t.json; echo rc=\$?; cat t.json; echo"
  assert_line --index 0 'rc=1'
  assert_line --index 1 '{"a":1}'
}

@test "atomic: a failing jq neither replaces the target nor leaves a temp file" {
  printf '{"a":1}' > "$WD/t.json"
  lib_only "jq '.a | error(\"boom\")' t.json 2>/dev/null | _atomic_json t.json; echo rc=\$?; \
    cat t.json; echo; ls t.json.tmp.* 2>/dev/null | wc -l"
  assert_line --index 0 'rc=1'
  assert_line --index 1 '{"a":1}'
  assert_line --index 2 --regexp '^ *0$'
}

# ---------------------------------------------------------------------------
# title_cap_word_boundary — the live title cap trims to a whole-word
# prefix within the limit rather than the old mid-word cut.
# ---------------------------------------------------------------------------
@test "title word boundary: spaced title over 100 ends on a whole word plus ellipsis" {
  local input="" expected="" i
  for i in 1 2 3 4 5 6 7 8 9 10 11; do input="${input}abcdefghi "; done
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if [ "$i" = 1 ]; then expected="abcdefghi"; else expected="$expected abcdefghi"; fi
  done
  expected="${expected}…"
  lib_only "printf '%s' '$input' | title_cap_word_boundary 100"
  assert_success
  assert_equal "$output" "$expected"
}

@test "title word boundary: no-whitespace title over 100 hard-cuts to 99 plus ellipsis" {
  local input expected
  input="$(head -c 120 /dev/zero | tr '\0' 'x')"
  expected="$(head -c 99 /dev/zero | tr '\0' 'x')…"
  lib_only "printf '%s' '$input' | title_cap_word_boundary 100"
  assert_success
  assert_equal "$output" "$expected"
}

@test "title word boundary: title of 100 or fewer is unchanged" {
  local input="Short title well under the one hundred character cap"
  lib_only "printf '%s' '$input' | title_cap_word_boundary 100"
  assert_success
  assert_equal "$output" "$input"
}

@test "title word boundary: trailing punctuation trimmed before ellipsis" {
  lib_only "printf '%s' 'hello, world again' | title_cap_word_boundary 12"
  assert_success
  assert_equal "$output" "hello…"
}

@test "title word boundary: legacy fixed-100 title is matched by recovery search" {
  cd "$WD"
  local raw="" i
  for i in 1 2 3 4 5 6 7 8 9 10; do raw="${raw}abcdefghij "; done
  printf '%s' "$raw" > "$WD/raw.txt"

  cat > "$WD/legacy.sh" <<EOS
PUBLISH_LIB_ONLY=1 . '$PLUGIN_ROOT/$SCRIPT' > /dev/null 2>&1
title_legacy_cut < '$WD/raw.txt'
EOS
  run bash "$WD/legacy.sh"
  assert_success
  local legacy="$output"

  mock_gh --default-exit 0 \
    --route "issue list=0:[{\"number\":9,\"title\":\"$legacy\",\"url\":\"https://github.com/o/r/issues/9\"}]"

  cat > "$WD/probe.sh" <<EOS
PUBLISH_LIB_ONLY=1 . '$PLUGIN_ROOT/$SCRIPT' > /dev/null 2>&1
TITLE=\$(head -1 '$WD/raw.txt' | sanitise_body | tr -d '\n' | title_cap_word_boundary 100)
TITLE_LEGACY=\$(title_legacy_cut < '$WD/raw.txt')
GH_ISSUE_SEARCH=1 DRY_RUN=0 GH_BIN=gh PATH="\$STUB_PATH" resolve_context_issue_search
printf 'rc=%s number=%s' \$? "\$RESOLVED_ISSUE_NUMBER"
EOS
  run bash "$WD/probe.sh"
  assert_success
  assert_output --partial 'rc=0 number=9'
}
