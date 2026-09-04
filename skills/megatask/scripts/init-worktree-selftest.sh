#!/usr/bin/env bash
# init-worktree-selftest.sh — the `--self-test` harness for init-worktree.sh.
#
# SOURCED, never executed: init-worktree.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every fixture passes.

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
self_test() {
  require_tools

  local failures=0
  local pass_count=0
  local td
  td=$(mktemp -d -t init-worktree-selftest.XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -rf '$td'" EXIT

  st_pass() {
    pass_count=$((pass_count + 1))
    printf 'PASS: %s\n' "$1"
  }
  st_fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1"
  }
  st_check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then st_pass "$desc"; else
      st_fail "$desc -- expected $(printf '%q' "$expected") got $(printf '%q' "$actual")"
    fi
  }

  # ---------------------------------------------------------------
  # Set up a minimal bare git repo + working clone so worktree add works.
  # ---------------------------------------------------------------
  local bare="${td}/remote.git"
  local repo="${td}/repo"

  git init --bare "$bare" -q
  git clone "$bare" "$repo" -q 2> /dev/null

  # Commit something so origin/master (or main) exists.
  git -C "$repo" config user.email 'test@example.com'
  git -C "$repo" config user.name 'Test'
  touch "${repo}/README"
  git -C "$repo" add README
  git -C "$repo" commit -q -m 'init'

  # Detect default branch name.
  local default_branch
  default_branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)

  git -C "$repo" push -q origin "$default_branch"

  # ---------------------------------------------------------------
  # Test A: --dry-run does not mutate anything.
  # ---------------------------------------------------------------
  OPT_ISSUE="42" OPT_TITLE="Add login flow" OPT_GROUP="milestone-1" \
    OPT_FILE="" OPT_TRACK="1" OPT_BLOCKED_BY="" OPT_BLOCKS="" OPT_LABELS="" \
    OPT_DRY_RUN=1 run_init "$repo" > "$td/dry_out.txt"

  if grep -q 'dry-run' "$td/dry_out.txt"; then
    st_pass "dry-run: produced output"
  else
    st_fail "dry-run: no output"
  fi

  if [[ ! -d "${repo}/.worktrees" ]]; then
    st_pass "dry-run: no .worktrees created"
  else
    st_fail "dry-run: .worktrees was created (should not be)"
  fi

  if grep -q 'feature/42-add-login-flow' "$td/dry_out.txt"; then
    st_pass "dry-run: correct branch name in output"
  else
    st_fail "dry-run: branch name missing from output"
  fi

  if grep -q 'exclude (git common-dir info/exclude): /workspace.json' "$td/dry_out.txt"; then
    st_pass "dry-run: announces the scratch exclusion"
  else
    st_fail "dry-run: exclusion not announced"
  fi

  if ! grep -qxF -- '/workspace.json' "${repo}/.git/info/exclude" 2> /dev/null; then
    st_pass "dry-run: exclude file not written"
  else
    st_fail "dry-run: exclude file was written (should not be)"
  fi

  # ---------------------------------------------------------------
  # Test B: Normal init creates worktree, .context, workspace.json.
  # ---------------------------------------------------------------
  OPT_ISSUE="42" OPT_TITLE="Add login flow" OPT_GROUP="milestone-1" \
    OPT_FILE="" OPT_TRACK="2" OPT_BLOCKED_BY="41" OPT_BLOCKS="60" \
    OPT_LABELS="P1,feature" OPT_DRY_RUN=0 run_init "$repo"

  local wt="${repo}/.worktrees/milestone-1/42"

  if [[ -d "$wt" ]]; then
    st_pass "init: worktree directory created"
  else
    st_fail "init: worktree directory missing"
  fi

  if [[ -d "${wt}/.context" ]]; then
    st_pass "init: .context directory created"
  else
    st_fail "init: .context directory missing"
  fi

  if [[ -f "${wt}/workspace.json" ]]; then
    st_pass "init: workspace.json created"
  else
    st_fail "init: workspace.json missing"
  fi

  # Validate workspace.json schema fields.
  local ws_version ws_isolation ws_issue ws_branch ws_status ws_track
  ws_version=$(jq -r '.version' "${wt}/workspace.json" 2> /dev/null || echo "")
  ws_isolation=$(jq -r '.isolation' "${wt}/workspace.json" 2> /dev/null || echo "")
  ws_issue=$(jq -r '.issue.number' "${wt}/workspace.json" 2> /dev/null || echo "")
  ws_branch=$(jq -r '.git.branch_name' "${wt}/workspace.json" 2> /dev/null || echo "")
  ws_status=$(jq -r '.execution.status' "${wt}/workspace.json" 2> /dev/null || echo "")
  ws_track=$(jq -r '.worktask.track' "${wt}/workspace.json" 2> /dev/null || echo "")

  st_check "workspace.json: version" "2.0" "$ws_version"
  st_check "workspace.json: isolation" "worktree" "$ws_isolation"
  st_check "workspace.json: issue.number" "42" "$ws_issue"
  st_check "workspace.json: branch" "feature/42-add-login-flow" "$ws_branch"
  st_check "workspace.json: status" "in_progress" "$ws_status"
  st_check "workspace.json: track" "2" "$ws_track"

  local ws_blocked ws_blocks
  ws_blocked=$(jq -c '.dependency.blocked_by' "${wt}/workspace.json" 2> /dev/null || echo "")
  ws_blocks=$(jq -c '.dependency.blocks' "${wt}/workspace.json" 2> /dev/null || echo "")

  st_check "workspace.json: blocked_by" "[41]" "$ws_blocked"
  st_check "workspace.json: blocks" "[60]" "$ws_blocks"

  # Branch must exist in worktree repo.
  local wt_branch
  wt_branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2> /dev/null || echo "")
  st_check "git: worktree branch" "feature/42-add-login-flow" "$wt_branch"

  # ---------------------------------------------------------------
  # Test B2: scratch exclusion contract (REQ-2 / AC-2).
  # ---------------------------------------------------------------
  # Hermetic: the operator's global excludes file may already hide
  # workspace.json and .worktrees/, which would satisfy these assertions
  # without the code doing anything.
  local -a hermetic
  hermetic=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git)

  st_check "exclusion: worktree status is clean" "" \
    "$("${hermetic[@]}" -C "$wt" status --porcelain)"
  st_check "exclusion: no tracked file modified" "" \
    "$("${hermetic[@]}" -C "$wt" status --porcelain --untracked-files=no)"
  # Documented consequence: the rule is checkout-wide, so the main checkout's
  # own .worktrees/ is hidden too. Asserted so a narrower mechanism cannot
  # change it silently.
  st_check "exclusion: main checkout status is clean" "" \
    "$("${hermetic[@]}" -C "$repo" status --porcelain)"

  # -v names the source, so the assertion cannot be satisfied by some other
  # ignore file that happens to hide the same name.
  if "${hermetic[@]}" -C "$wt" check-ignore -v -- workspace.json | grep -q 'info/exclude'; then
    st_pass "exclusion: workspace.json ignored via the common-dir exclude"
  else
    st_fail "exclusion: workspace.json not ignored by our exclude file"
  fi

  mkdir -p -- "${wt}/src/sub"
  : > "${wt}/src/sub/workspace.json"
  if "${hermetic[@]}" -C "$wt" status --porcelain --untracked-files=all \
    | grep -q 'src/sub/workspace.json'; then
    st_pass "exclusion: nested workspace.json stays visible"
  else
    st_fail "exclusion: nested workspace.json was hidden (pattern not anchored)"
  fi
  rm -rf -- "${wt}/src"

  # ---------------------------------------------------------------
  # Test C: Idempotency — running again does not error.
  # ---------------------------------------------------------------
  OPT_ISSUE="42" OPT_TITLE="Add login flow" OPT_GROUP="milestone-1" \
    OPT_FILE="" OPT_TRACK="2" OPT_BLOCKED_BY="" OPT_BLOCKS="" \
    OPT_LABELS="" OPT_DRY_RUN=0 run_init "$repo" 2> /dev/null
  st_pass "idempotent: second run did not error"

  # exclude_scratch is also called directly: the early return above skips it on
  # an existing worktree, and a repeat batch must not accumulate duplicates.
  exclude_scratch "$repo" "${SCRATCH_PATTERNS[@]}"
  exclude_scratch "$repo" "${SCRATCH_PATTERNS[@]}"
  st_check "idempotent: /workspace.json listed once" "1" \
    "$(grep -cxF -- '/workspace.json' "${repo}/.git/info/exclude")"
  st_check "idempotent: /.worktrees/ listed once" "1" \
    "$(grep -cxF -- '/.worktrees/' "${repo}/.git/info/exclude")"
  st_check "idempotent: provenance header written once" "1" \
    "$(grep -cxF -- "$SCRATCH_HEADER" "${repo}/.git/info/exclude")"

  # ---------------------------------------------------------------
  # Test D: Second distinct issue on same repo.
  # ---------------------------------------------------------------
  OPT_ISSUE="57" OPT_TITLE="Settings sidebar" OPT_GROUP="milestone-1" \
    OPT_FILE="" OPT_TRACK="1" OPT_BLOCKED_BY="42" OPT_BLOCKS="" \
    OPT_LABELS="P1" OPT_DRY_RUN=0 run_init "$repo"

  local wt57="${repo}/.worktrees/milestone-1/57"
  if [[ -d "$wt57" ]]; then
    st_pass "second issue: worktree created"
  else
    st_fail "second issue: worktree missing"
  fi

  st_check "second issue: branch" "feature/57-settings-sidebar" \
    "$(git -C "$wt57" rev-parse --abbrev-ref HEAD 2> /dev/null || echo "")"

  # ---------------------------------------------------------------
  trap - EXIT
  rm -rf "$td"

  if [[ "$failures" -eq 0 ]]; then
    printf 'init-worktree: self-test OK (%d checks passed)\n' "$pass_count"
    return 0
  else
    printf 'init-worktree: self-test FAILED (%d/%d checks failed)\n' \
      "$failures" "$((failures + pass_count))"
    return 1
  fi
}
