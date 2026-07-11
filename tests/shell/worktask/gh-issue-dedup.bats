#!/usr/bin/env bats
# Cross-run GitHub-issue dedup for skills/worktask/scripts/publish-pl-issue.sh.
# Contract (skills/gh-issue-dedup): one .context/ ↔ one GitHub issue.
#   - FIRST run creates the issue AND writes the run-independent .context/gh-issue.json
#     anchor (state.json is re-seeded per run, so it cannot carry the binding).
#   - A LATER run in the same .context/ resolves the anchor and posts a marker-deduped
#     follow-up COMMENT instead of opening a duplicate issue.
#   - Comment idempotency: re-running the same run_index does not double-post.
#   - Recovery: with no local anchor, an exact-title single-hit `gh issue list` search
#     reuses the existing issue; an ambiguous (multi-hit) result is refused → create.
#   - Same-run resume (anchor.created_run_index == run_index) → already_published.
#
# The mock gh records create vs comment calls to files under GH_MOCK_DIR and mirrors
# posted comment bodies into comments.txt so `issue view` reflects them (idempotency).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/publish-pl-issue.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/bin" "$WD/mock"
  export GH_MOCK_DIR="$WD/mock"

  # Clean plan (no paths → low strip ratio → reaches the publish branch).
  cat > "$WD/.context/plan.md" <<'MD'
## requirements
- REQ-1: Subsequent worktasks in one context reuse the GitHub issue.
## acceptance-criteria
- AC-1: A second run comments instead of creating a duplicate issue.
## scope
In scope: issue dedup. Out of scope: unrelated changes.
## complexity
Score: 8 out of 50 (Low).
## stages
PL0 then DV0
MD

  # Mock gh: records calls, mirrors comment bodies into comments.txt.
  cat > "$WD/bin/gh" <<'EOS'
#!/usr/bin/env bash
D="${GH_MOCK_DIR:?}"
case "$1" in
  auth) exit 0 ;;
  repo) echo '{"visibility":"PUBLIC"}'; exit 0 ;;
  label) exit 0 ;;
  issue)
    case "$2" in
      view) cat "$D/comments.txt" 2>/dev/null; exit 0 ;;
      comment)
        bf=""; shift 2
        while [ $# -gt 0 ]; do
          case "$1" in --body-file) bf="$2"; shift 2 ;; *) shift ;; esac
        done
        if [ -z "$bf" ] || [ "$bf" = "-" ]; then cat >> "$D/comments.txt"; else cat "$bf" >> "$D/comments.txt"; fi
        echo "comment" >> "$D/comment-calls"
        echo "https://github.com/o/r/issues/42#issuecomment-1"; exit 0 ;;
      create)
        echo "create" >> "$D/create-calls"
        echo "https://github.com/o/r/issues/99"; exit 0 ;;
      list) cat "$D/search-result.json" 2>/dev/null || echo '[]'; exit 0 ;;
    esac ;;
esac
exit 0
EOS
  chmod +x "$WD/bin/gh"

  # Mock git: satisfy Guard 5 (remote present) without a real repo.
  cat > "$WD/bin/git" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "remote" ] && [ "$2" = "get-url" ] && { echo "git@github.com:o/r.git"; exit 0; }
[ "$1" = "rev-parse" ] && { echo "feature/test"; exit 0; }
exit 0
EOS
  chmod +x "$WD/bin/git"

  # state.json with a given run_index; facts.goal drives TITLE.
  write_state() { # $1=run_index
    jq -cn --argjson ri "$1" \
      '{version:1, worktask_id:"dedup0", run_index:$ri, plan_file:".context/plan.md", platform:"all", facts:{goal:"Dedup follow-up worktasks in one context"}, metadata:{}}' \
      > "$WD/.context/state.json"
  }
  # Anchor written by a prior run.
  write_anchor() { # $1=created_run_index
    jq -cn --argjson ri "$1" \
      '{version:1, url:"https://github.com/o/r/issues/42", number:42, created_run_index:$ri, created_worktask_id:"dedup0", created_at:"2026-01-01T00:00:00Z", last_commented_run_index:$ri}' \
      > "$WD/.context/gh-issue.json"
  }
  LAST_AUDIT() { tail -1 "$WD/.context/logs/audit.jsonl"; }
  RUN() { cd "$WD"; run env PATH="$WD/bin:$PATH" WORKSPACE_ROOT="$WD" "$@" bash "$PLUGIN_ROOT/$SCRIPT"; }
}

@test "first run: create publishes the issue and writes the .context/gh-issue.json anchor" {
  write_state 0
  RUN GH_ISSUE_SEARCH=0
  assert_success
  # created, not commented
  [ -f "$WD/mock/create-calls" ]
  [ ! -f "$WD/mock/comment-calls" ]
  # anchor persisted with url + number parsed from the create URL
  [ -f "$WD/.context/gh-issue.json" ]
  run jq -r '.url' "$WD/.context/gh-issue.json"; assert_output "https://github.com/o/r/issues/99"
  run jq -r '.number' "$WD/.context/gh-issue.json"; assert_output "99"
  run jq -r '.result' <(LAST_AUDIT); assert_output "ok"
  run jq -r '.metadata.mode' <(LAST_AUDIT); assert_output "create"
}

@test "later run: existing anchor → comment on the issue, no duplicate create" {
  write_state 1
  write_anchor 0
  RUN GH_ISSUE_SEARCH=0
  assert_success
  [ -f "$WD/mock/comment-calls" ]
  [ ! -f "$WD/mock/create-calls" ]
  # follow-up marker + heading posted
  run cat "$WD/mock/comments.txt"
  assert_output --partial "<!-- worktask-plan:dedup0:1 -->"
  assert_output --partial "Follow-up worktask — run #1"
  # anchor advanced last_commented_run_index, kept created_run_index
  run jq -r '.last_commented_run_index' "$WD/.context/gh-issue.json"; assert_output "1"
  run jq -r '.created_run_index' "$WD/.context/gh-issue.json"; assert_output "0"
  run jq -r '.result' <(LAST_AUDIT); assert_output "ok"
  run jq -r '.metadata.mode' <(LAST_AUDIT); assert_output "comment"
}

@test "comment idempotency: re-running the same run does not double-post" {
  write_state 1
  write_anchor 0
  # simulate the run-1 comment already present on the issue
  printf '<!-- worktask-plan:dedup0:1 -->\n## Follow-up worktask — run #1\n' > "$WD/mock/comments.txt"
  RUN GH_ISSUE_SEARCH=0
  assert_success
  [ ! -f "$WD/mock/comment-calls" ]
  [ ! -f "$WD/mock/create-calls" ]
  run jq -r '.result' <(LAST_AUDIT); assert_output "deferred"
  run jq -r '.metadata.reason' <(LAST_AUDIT); assert_output "comment_already_present"
}

@test "same-run resume: anchor created in this run → already_published (no create, no comment)" {
  write_state 0
  write_anchor 0
  RUN GH_ISSUE_SEARCH=0
  assert_success
  [ ! -f "$WD/mock/create-calls" ]
  [ ! -f "$WD/mock/comment-calls" ]
  run jq -r '.result' <(LAST_AUDIT); assert_output "deferred"
  run jq -r '.metadata.reason' <(LAST_AUDIT); assert_output "already_published"
}

@test "recovery: lost anchor + exact-title single search hit → comment, backfill anchor" {
  write_state 1
  # no anchor on disk; GitHub returns exactly one exact-title open issue
  printf '[{"number":42,"title":"Dedup follow-up worktasks in one context","url":"https://github.com/o/r/issues/42"}]\n' \
    > "$WD/mock/search-result.json"
  RUN
  assert_success
  [ -f "$WD/mock/comment-calls" ]
  [ ! -f "$WD/mock/create-calls" ]
  # anchor backfilled so future runs resolve locally
  [ -f "$WD/.context/gh-issue.json" ]
  run jq -r '.number' "$WD/.context/gh-issue.json"; assert_output "42"
  run jq -r '.metadata.resolved_via' <(LAST_AUDIT); assert_output "search"
}

@test "recovery guard: ambiguous multi-hit search is refused → create (no false reuse)" {
  write_state 1
  # two issues share the exact title → ambiguous → must NOT be reused
  printf '[{"number":42,"title":"Dedup follow-up worktasks in one context","url":"https://github.com/o/r/issues/42"},{"number":77,"title":"Dedup follow-up worktasks in one context","url":"https://github.com/o/r/issues/77"}]\n' \
    > "$WD/mock/search-result.json"
  RUN
  assert_success
  [ -f "$WD/mock/create-calls" ]
  [ ! -f "$WD/mock/comment-calls" ]
  run jq -r '.metadata.mode' <(LAST_AUDIT); assert_output "create"
}
