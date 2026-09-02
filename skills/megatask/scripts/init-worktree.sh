#!/usr/bin/env bash
# @description Per-issue git worktree initialiser for megatask.
#
#   For each issue this script:
#     1. Resolves the base branch via sourced milestone-helpers.sh (issue body
#        base_branch: field → develop → master; no hardcoding).
#     2. Derives the branch name: <type>/{n}-{slug} (milestone-helpers
#        cmd_branch_name — type derived from the title, slug max 50 chars).
#     3. Excludes the batch's own scratch metadata from git BEFORE the worktree
#        exists, so it is never reported by `git status` (see exclude_scratch).
#     4. Runs: git fetch origin <base_branch>
#              git worktree add -b <branch> <worktree_path> origin/<base_branch>
#     5. Creates <worktree_path>/.context/
#     6. Stamps <worktree_path>/workspace.json v2.0 (schema: references/schemas.md).
#
#   Idempotent: if the worktree directory already exists the script skips creation
#   and reports "already exists" rather than erroring (safe to re-run on retry).
#
#   Usage:
#     bash init-worktree.sh --issue N --title "Add login flow" [OPTIONS]
#     bash init-worktree.sh --self-test
#
# @arg --issue <int>          Issue number (required).
# @arg --title <str>          Issue title used for slug derivation (required).
# @arg --group <str>          Megatask group token, e.g. milestone-1 (required).
# @arg --file <path>          Pre-fetched issue JSON (for base-branch resolution
#                             and workspace.json metadata; avoids network calls).
# @arg --repo-root <path>     Absolute path to the git repo root (default: $PWD).
# @arg --track <int>          Track number to record in workspace.json (default: 1).
# @arg --blocked-by <N,M,...> Comma-separated blocker issue numbers (default: "").
# @arg --blocks <N,M,...>     Comma-separated issue numbers this one blocks (default: "").
# @arg --labels <label,...>   Comma-separated labels for workspace.json.
# @arg --dry-run              Print planned actions; perform no mutations.
# @arg --self-test            Run built-in tests against a temp git repo; exit non-zero on fail.
# @arg -h, --help             Show usage.
#
# @exitcode 0  Success (or dry-run completed).
# @exitcode 1  Usage error / git failure.
# @exitcode 2  jq or milestone-helpers not found.
#
# Minimum Bash: 3.2 (no associative arrays used here). Tested on macOS + Linux.
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d (exit %d)\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Locate milestone-helpers.sh relative to this script's canonical directory.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HELPERS_PATH="${SCRIPT_DIR}/../../shared/milestone-helpers/scripts/milestone-helpers.sh"

die() {
  printf >&2 'init-worktree: %s\n' "$*"
  exit 1
}

require_tools() {
  command -v jq > /dev/null 2>&1 || {
    printf >&2 'init-worktree: jq is required but not found\n'
    exit 2
  }
  [[ -f "$HELPERS_PATH" ]] || {
    printf >&2 'init-worktree: milestone-helpers not found at %s\n' "$HELPERS_PATH"
    exit 2
  }
  command -v git > /dev/null 2>&1 || {
    printf >&2 'init-worktree: git is required but not found\n'
    exit 2
  }
}

ts() { date -u +%FT%TZ 2> /dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# ---------------------------------------------------------------------------
# exclude_scratch  <repo_root> <pattern>...  — idempotent, exact-line matched.
#
# Writes to the COMMON git dir because git has no per-worktree exclude file:
# .git/worktrees/<n>/info/exclude is never consulted. The exclusion is thus
# checkout-wide (sibling worktrees are covered too) — bounded, because ignore
# rules never mask a tracked file. The tracked .gitignore is left alone: editing
# it would commit the exclusion, which is the failure this prevents.
# ---------------------------------------------------------------------------
exclude_scratch() {
  local repo_root="$1"
  shift
  local common excl p
  common=$(git -C "$repo_root" rev-parse --git-common-dir) || return 1
  # rev-parse answers relatively (".git") when run from the main checkout.
  case "$common" in
    /*) ;;
    *) common="${repo_root}/${common}" ;;
  esac
  excl="${common}/info/exclude"
  mkdir -p -- "${common}/info"
  [[ -f "$excl" ]] || : > "$excl"
  # Provenance for the operator who meets the checkout-wide consequence in this
  # file rather than in the docs. Not a pattern, so it cannot collide below.
  grep -qxF -- "$SCRATCH_HEADER" "$excl" || printf '%s\n' "$SCRATCH_HEADER" >> "$excl"
  for p in "$@"; do
    grep -qxF -- "$p" "$excl" || printf '%s\n' "$p" >> "$excl"
  done
}

# Leading slash anchors each pattern to a worktree root, so a nested
# src/sub/workspace.json stays visible.
SCRATCH_PATTERNS=('/workspace.json' '/.worktrees/')
SCRATCH_HEADER='# megatask scratch — skills/megatask/scripts/init-worktree.sh'

# ---------------------------------------------------------------------------
# resolve_base_branch  <repo_root> <issue_num> [<json_file>]
# Delegates entirely to milestone-helpers cmd_base_branch — no hardcoding.
#
# Runs in <repo_root>: the helper's develop-vs-master probe is a `git ls-remote`
# against the AMBIENT repo, so resolving it from the caller's cwd picks a branch
# from one repo and step 7 then fetches it in another. A caller standing in a repo
# with `develop` initialising a worktree in one without it got exit 128.
# Subshell, so the -C discipline in step 7 still holds for everything else.
# ---------------------------------------------------------------------------
resolve_base_branch() {
  local repo_root="$1"
  local issue_num="$2"
  local json_file="${3:-}"

  if [[ -n "$json_file" ]]; then
    (cd -- "$repo_root" && bash -- "$HELPERS_PATH" base-branch "$issue_num" --file "$json_file")
  else
    (cd -- "$repo_root" && bash -- "$HELPERS_PATH" base-branch "$issue_num")
  fi
}

# ---------------------------------------------------------------------------
# derive_branch  <issue_num> <title>
# Delegates to milestone-helpers cmd_branch_name.
# ---------------------------------------------------------------------------
derive_branch() {
  bash -- "$HELPERS_PATH" branch-name "$1" "$2"
}

# ---------------------------------------------------------------------------
# csv_to_json_int_array <"N,M,..."> → [N,M,...]
# Converts a comma-separated list of integers to a JSON array.
# Empty input → [].
# ---------------------------------------------------------------------------
csv_to_json_int_array() {
  local csv="$1"
  if [[ -z "$csv" ]]; then
    printf '[]'
    return
  fi
  # Split on comma, strip spaces, validate integers, build JSON array.
  printf '%s' "$csv" \
    | tr ',' '\n' \
    | sed 's/[[:space:]]//g' \
    | grep -E '^[0-9]+$' \
    | jq -R 'tonumber' \
    | jq -s '.'
}

# ---------------------------------------------------------------------------
# build_workspace_json — emits workspace.json v2.0 to stdout.
# ---------------------------------------------------------------------------
build_workspace_json() {
  local issue_num="$1"
  local title="$2"
  local labels_json="$3" # JSON array string e.g. '["P1","feature"]'
  local branch="$4"
  local base_branch="$5"
  local base_branch_src="$6"
  local worktree_path="$7"
  local _group="$8" # received but not embedded in workspace.json; worktree_path encodes it
  local track="$9"
  local blocked_by_json="${10}"
  local blocks_json="${11}"
  local created_at
  created_at=$(ts)

  jq -cn \
    --argjson issue_num "$issue_num" \
    --arg title "$title" \
    --argjson labels "$labels_json" \
    --arg branch "$branch" \
    --arg base_branch "$base_branch" \
    --arg base_branch_src "$base_branch_src" \
    --arg worktree_path "$worktree_path" \
    --argjson track "$track" \
    --argjson blocked_by "$blocked_by_json" \
    --argjson blocks_arr "$blocks_json" \
    --arg created_at "$created_at" \
    '{
      "version": "2.0",
      "isolation": "worktree",
      "created_at": $created_at,
      "issue": {
        "number": $issue_num,
        "title": $title,
        "labels": $labels
      },
      "git": {
        "branch_name": $branch,
        "base_branch": $base_branch,
        "base_branch_source": $base_branch_src,
        "worktree_path": $worktree_path
      },
      "worktask": {
        "track": $track,
        "complexity_score": null
      },
      "dependency": {
        "blocked_by": $blocked_by,
        "blocks": $blocks_arr
      },
      "execution": {
        "current_stage": null,
        "retry_count": 0,
        "status": "in_progress",
        "pr": null
      },
      "task_ids": {}
    }'
}

# ---------------------------------------------------------------------------
# run_init  — core initialisation logic
# Called in both normal and self-test paths.
# $1 = repo_root (absolute), all other config from OPT_* vars.
# ---------------------------------------------------------------------------
run_init() {
  local repo_root="$1"

  # Validate integer issue number (injection safety).
  [[ "$OPT_ISSUE" =~ ^[0-9]+$ ]] || die "--issue must be a positive integer, got: $OPT_ISSUE"
  [[ "$OPT_TRACK" =~ ^[0-9]+$ ]] || die "--track must be a positive integer, got: $OPT_TRACK"

  local worktree_path="${repo_root}/.worktrees/${OPT_GROUP}/${OPT_ISSUE}"

  # 1. Resolve base branch.
  local base_branch base_branch_src
  base_branch=$(resolve_base_branch "$repo_root" "$OPT_ISSUE" "${OPT_FILE:-}")
  # Determine source label (mirrors SKILL.md §Base Branch Resolution).
  if [[ -n "${OPT_FILE:-}" ]]; then
    local _body
    _body=$(jq -r '.body // ""' -- "$OPT_FILE" 2> /dev/null || true)
    if printf '%s' "$_body" | grep -Eiq '^[[:space:]]*base_branch:[[:space:]]*[a-zA-Z0-9/_.-]+'; then
      base_branch_src="issue_body"
    elif [[ "$base_branch" == "develop" ]]; then
      base_branch_src="develop_fallback"
    else
      base_branch_src="master_default"
    fi
  elif [[ "$base_branch" == "develop" ]]; then
    base_branch_src="develop_fallback"
  else
    base_branch_src="master_default"
  fi

  # 2. Derive feature branch name.
  local branch
  branch=$(derive_branch "$OPT_ISSUE" "$OPT_TITLE")

  # 3. Build labels JSON array.
  local labels_json
  if [[ -n "${OPT_LABELS:-}" ]]; then
    labels_json=$(printf '%s' "$OPT_LABELS" \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
      | grep -v '^$' \
      | jq -R '.' \
      | jq -s '.')
  elif [[ -n "${OPT_FILE:-}" ]]; then
    labels_json=$(jq -c '[.labels[]? | if type=="string" then . else .name // "" end | select(. != "")]' \
      -- "$OPT_FILE" 2> /dev/null || printf '[]')
  else
    labels_json='[]'
  fi

  # 4. Build blocked_by / blocks JSON arrays.
  local blocked_by_json blocks_json
  blocked_by_json=$(csv_to_json_int_array "${OPT_BLOCKED_BY:-}")
  blocks_json=$(csv_to_json_int_array "${OPT_BLOCKS:-}")

  # ------------------------------------------------------------------
  # Dry-run: print planned actions and return.
  # ------------------------------------------------------------------
  if [[ "$OPT_DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] issue #%s: %s\n' "$OPT_ISSUE" "$OPT_TITLE"
    printf '  base_branch:     %s (%s)\n' "$base_branch" "$base_branch_src"
    printf '  branch:          %s\n' "$branch"
    printf '  worktree_path:   %s\n' "$worktree_path"
    printf '  context_path:    %s/.context\n' "$worktree_path"
    printf '  track:           %s\n' "$OPT_TRACK"
    printf '  blocked_by:      %s\n' "$blocked_by_json"
    printf '  blocks:          %s\n' "$blocks_json"
    printf '  labels:          %s\n' "$labels_json"
    local _p
    for _p in "${SCRATCH_PATTERNS[@]}"; do
      printf '  exclude (git common-dir info/exclude): %s\n' "$_p"
    done
    printf '  git fetch origin %s\n' "$base_branch"
    printf '  git worktree add -b %s %s origin/%s\n' "$branch" "$worktree_path" "$base_branch"
    printf '  mkdir -p %s/.context\n' "$worktree_path"
    printf '  write workspace.json v2.0 -> %s/workspace.json\n' "$worktree_path"
    return 0
  fi

  # ------------------------------------------------------------------
  # Idempotency check.
  # ------------------------------------------------------------------
  if [[ -d "$worktree_path" ]]; then
    printf 'init-worktree: worktree already exists, skipping: %s\n' "$worktree_path" >&2
    return 0
  fi

  # ------------------------------------------------------------------
  # 5. Ensure .worktrees/<group> directory exists.
  # ------------------------------------------------------------------
  local group_dir="${repo_root}/.worktrees/${OPT_GROUP}"
  mkdir -p -- "$group_dir"

  # ------------------------------------------------------------------
  # 6. Exclude scratch metadata BEFORE the worktree exists, so workspace.json
  # is never briefly visible to a `git add -A` racing the initialiser.
  # ------------------------------------------------------------------
  exclude_scratch "$repo_root" "${SCRATCH_PATTERNS[@]}"

  # ------------------------------------------------------------------
  # 7. git fetch + worktree add.
  # Uses -C flag so no cd is required; prevents cwd drift.
  # Branch name and base_branch are validated/derived, not user-interpolated.
  # ------------------------------------------------------------------
  git -C "$repo_root" fetch origin -- "$base_branch"
  git -C "$repo_root" worktree add -b "$branch" "$worktree_path" "origin/${base_branch}"

  # ------------------------------------------------------------------
  # 8. Create .context directory.
  # ------------------------------------------------------------------
  mkdir -p -- "${worktree_path}/.context"

  # ------------------------------------------------------------------
  # 9. Stamp workspace.json v2.0 (atomic write).
  # ------------------------------------------------------------------
  local ws_tmp
  ws_tmp=$(mktemp -t init-worktree-ws.XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -f '$ws_tmp'" EXIT

  build_workspace_json \
    "$OPT_ISSUE" \
    "$OPT_TITLE" \
    "$labels_json" \
    "$branch" \
    "$base_branch" \
    "$base_branch_src" \
    ".worktrees/${OPT_GROUP}/${OPT_ISSUE}" \
    "$OPT_GROUP" \
    "$OPT_TRACK" \
    "$blocked_by_json" \
    "$blocks_json" \
    > "$ws_tmp"

  mv -f -- "$ws_tmp" "${worktree_path}/workspace.json"
  trap - EXIT

  printf 'init-worktree: created worktree for #%s at %s (branch: %s)\n' \
    "$OPT_ISSUE" "$worktree_path" "$branch"
}

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

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
OPT_ISSUE=""
OPT_TITLE=""
OPT_GROUP=""
OPT_FILE=""
OPT_REPO_ROOT=""
OPT_TRACK="1"
OPT_BLOCKED_BY=""
OPT_BLOCKS=""
OPT_LABELS=""
OPT_DRY_RUN=0
SELF_TEST_MODE=0

usage() {
  cat >&2 << 'USAGE'
Usage: init-worktree.sh [OPTIONS]

Required:
  --issue <int>            Issue number
  --title <str>            Issue title (used for branch slug)
  --group <str>            Megatask group token (e.g. milestone-1)

Optional:
  --file <path>            Pre-fetched issue JSON (for base-branch + labels)
  --repo-root <path>       Absolute git repo root (default: $PWD)
  --track <int>            Track number (default: 1)
  --blocked-by <N,M,...>   Comma-separated blocker issue numbers
  --blocks <N,M,...>       Comma-separated issues this one blocks
  --labels <label,...>     Comma-separated labels for workspace.json
  --dry-run                Print planned actions; no mutations
  --self-test              Run built-in tests; exit non-zero on failure
  -h, --help               Show this help
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      OPT_ISSUE="$2"
      shift 2
      ;;
    --issue=*)
      OPT_ISSUE="${1#--issue=}"
      shift
      ;;
    --title)
      OPT_TITLE="$2"
      shift 2
      ;;
    --title=*)
      OPT_TITLE="${1#--title=}"
      shift
      ;;
    --group)
      OPT_GROUP="$2"
      shift 2
      ;;
    --group=*)
      OPT_GROUP="${1#--group=}"
      shift
      ;;
    --file)
      OPT_FILE="$2"
      shift 2
      ;;
    --file=*)
      OPT_FILE="${1#--file=}"
      shift
      ;;
    --repo-root)
      OPT_REPO_ROOT="$2"
      shift 2
      ;;
    --repo-root=*)
      OPT_REPO_ROOT="${1#--repo-root=}"
      shift
      ;;
    --track)
      OPT_TRACK="$2"
      shift 2
      ;;
    --track=*)
      OPT_TRACK="${1#--track=}"
      shift
      ;;
    --blocked-by)
      OPT_BLOCKED_BY="$2"
      shift 2
      ;;
    --blocked-by=*)
      OPT_BLOCKED_BY="${1#--blocked-by=}"
      shift
      ;;
    --blocks)
      OPT_BLOCKS="$2"
      shift 2
      ;;
    --blocks=*)
      OPT_BLOCKS="${1#--blocks=}"
      shift
      ;;
    --labels)
      OPT_LABELS="$2"
      shift 2
      ;;
    --labels=*)
      OPT_LABELS="${1#--labels=}"
      shift
      ;;
    --dry-run)
      OPT_DRY_RUN=1
      shift
      ;;
    --self-test | self-test)
      SELF_TEST_MODE=1
      shift
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      printf >&2 'init-worktree: unknown option: %s\n' "$1"
      usage
      ;;
  esac
done

require_tools

if [[ "$SELF_TEST_MODE" -eq 1 ]]; then
  self_test
  exit $?
fi

# Validate required args.
[[ -n "$OPT_ISSUE" ]] || die "--issue <int> is required"
[[ -n "$OPT_TITLE" ]] || die "--title <str> is required"
[[ -n "$OPT_GROUP" ]] || die "--group <str> is required"

# Repo root: explicit flag > git toplevel > PWD.
if [[ -z "$OPT_REPO_ROOT" ]]; then
  OPT_REPO_ROOT=$(git rev-parse --show-toplevel 2> /dev/null || pwd -P)
fi

export OPT_ISSUE OPT_TITLE OPT_GROUP OPT_FILE OPT_TRACK OPT_BLOCKED_BY OPT_BLOCKS OPT_LABELS OPT_DRY_RUN

run_init "$OPT_REPO_ROOT"
