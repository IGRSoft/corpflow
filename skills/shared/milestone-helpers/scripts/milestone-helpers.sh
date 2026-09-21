#!/usr/bin/env bash
# @description Canonical dispatcher for slug/branch/priority/base-branch logic used by
#              megatask scripts. Source or invoke directly.
#
# @usage       bash milestone-helpers.sh <subcommand> [args...]
#
# Subcommands:
#   branch-name <issue-int> <title>      -> <type>/{n}-{slug}  (slug max 50 chars,
#                                           truncated on a word boundary)
#   priority-score <label...>            -> integer score (0=P0/critical … 99=none)
#   base-branch [<issue-int>] [--file J] -> resolved base branch name
#   has-pr <issue-int> [--file J]        -> yes | no
#   filter-prs --file J                  -> compact TSV: <number> <status>
#   orchestrator-update --file J [--path P] [--issue N] [field=value ...]
#                                        -> updated JSON written atomically to --path
#   workspace-init <issue-int> <title>   -> emit resolved branch + paths (no side effects)
#   --self-test                          -> run built-in tests, exit non-zero on failure
#
# @arg  subcommand  string  One of the commands listed above
# @exitcode 0  Success
# @exitcode 1  Usage / logic error
# @exitcode 2  Dependency missing (jq, or branch-lib.sh for branch-name)
#
# Slug-length canon: 50 chars (resolves SKILL.md vs implementations.md drift;
# megatask/SKILL.md §Branch Naming is the authority).
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d (exit %d)\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SLUG_MAX=50

readonly PRIORITY_NONE=99

# _priority_score_for_label <label>
# Returns integer score for a single label via case (Bash 3.2-compatible).
# Mirrors megatask/SKILL.md § Dependency & Blocker Resolution (DAG) exactly.
_priority_score_for_label() {
  case "$1" in
    P0 | priority:critical) printf '0' ;;
    P1 | priority:high) printf '1' ;;
    P2 | priority:medium) printf '2' ;;
    P3 | priority:low) printf '3' ;;
    P4 | priority:backlog) printf '4' ;;
    *) printf '%d' "$PRIORITY_NONE" ;;
  esac
}

# ---------------------------------------------------------------------------
# Utility: require jq
# ---------------------------------------------------------------------------
_require_jq() {
  command -v jq > /dev/null 2>&1 || {
    printf >&2 'milestone-helpers: jq is required but not found\n'
    exit 2
  }
}

# ---------------------------------------------------------------------------
# Utility: require branch-lib.sh (branch TYPE vocabulary)
# `BRANCH_TYPES`/`derive_type` in branch-lib.sh are the repo's single
# machine-readable type vocabulary (git-conventions.md § Type vocabulary), so it is
# sourced rather than copied. Absence is fatal, never a silent `feature/` fallback:
# a wrong-but-plausible branch name is worse than a loud stop.
# ---------------------------------------------------------------------------
_require_branch_lib() {
  declare -F derive_type > /dev/null 2>&1 && return 0
  local lib
  lib="$(dirname -- "${BASH_SOURCE[0]}")/../../../worktask/scripts/branch-lib.sh"
  [[ -r "$lib" ]] || {
    printf >&2 'milestone-helpers: branch-lib.sh not readable at %s — cannot derive branch type\n' "$lib"
    exit 2
  }
  # shellcheck source=/dev/null
  . "$lib"
}

# ---------------------------------------------------------------------------
# _slug_body <title>
# Uncapped kebab body. `tr '\n' ' '` runs first — an embedded newline would
# otherwise survive sed's and cut's line-oriented view into a two-line branch name
# that `git worktree add` rejects. Must stay byte-identical to `slug_body` in
# skills/worktask/scripts/branch-lib.sh (pinned by a cross-check test).
# ---------------------------------------------------------------------------
_slug_body() {
  printf '%s' "${1:-}" \
    | tr '\n' ' ' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//'
}

# ---------------------------------------------------------------------------
# _slug_cap <kebab-body> [budget]
# Caps the body, dropping the trailing PARTIAL segment rather than cutting mid-word.
# One whole word always survives — even one longer than the budget — because an
# empty slug would emit the nameless `<type>/{n}-`. Mirrors `derive_slug` in
# branch-lib.sh minus its ticket budget: the issue number sits outside this cap.
# ---------------------------------------------------------------------------
_slug_cap() {
  local body="${1:-}" budget="${2:-$SLUG_MAX}" keep next

  if [[ "${#body}" -le "$budget" ]]; then
    printf '%s' "$body" | sed -e 's/-*$//'
    return 0
  fi

  # A cut landing exactly on a separator already ends on a whole word; stripping
  # back unconditionally would throw away a word that fit.
  next=$(printf '%s' "$body" | cut -c$((budget + 1))-$((budget + 1)))
  keep=$(printf '%s' "$body" | cut -c1-"$budget")
  if [[ "$next" != "-" ]]; then
    if [[ "${keep%-*}" == "$keep" ]]; then
      keep=${body%%-*}
    else
      keep=${keep%-*}
    fi
  fi
  printf '%s' "$keep" | sed -e 's/-*$//'
}

# ---------------------------------------------------------------------------
# cmd_branch_name <issue-int> <title>
# Emits:  {type}/{n}-{slug} — type derived from the title, `feature` when nothing
#         in it reads as a defect/refactor/chore (branch-lib.sh `derive_type`).
# ---------------------------------------------------------------------------
cmd_branch_name() {
  local issue_num="$1"
  local title="$2"

  # Validate issue number is a positive integer
  [[ "$issue_num" =~ ^[0-9]+$ ]] || {
    printf >&2 'branch-name: issue number must be a positive integer, got: %s\n' "$issue_num"
    exit 1
  }

  _require_branch_lib

  local type slug
  type=$(derive_type "$title")
  slug=$(_slug_cap "$(_slug_body "$title")" "$SLUG_MAX")

  printf '%s/%s-%s\n' "$type" "$issue_num" "$slug"
}

# ---------------------------------------------------------------------------
# cmd_priority_score <label...>
# Emits:  integer (0=highest, 99=none)
# ---------------------------------------------------------------------------
cmd_priority_score() {
  local best=$PRIORITY_NONE
  local label score
  for label in "$@"; do
    score=$(_priority_score_for_label "$label")
    ((score < best)) && best=$score
  done
  printf '%d\n' "$best"
}

# ---------------------------------------------------------------------------
# cmd_base_branch [<issue-int>] [--file J]
# Resolution order: issue body base_branch: field -> develop -> master
# Accepts pre-fetched gh issue JSON via --file to avoid network calls.
# ---------------------------------------------------------------------------
cmd_base_branch() {
  _require_jq
  local issue_num=""
  local json_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        json_file="$2"
        shift 2
        ;;
      --file=*)
        json_file="${1#--file=}"
        shift
        ;;
      [0-9]*)
        issue_num="$1"
        shift
        ;;
      *)
        printf >&2 'base-branch: unknown argument: %s\n' "$1"
        exit 1
        ;;
    esac
  done

  local body=""

  # Obtain issue body: from --file, from network, or skip
  if [[ -n "$json_file" ]]; then
    body=$(jq -r '.body // ""' -- "$json_file" 2> /dev/null || true)
  elif [[ -n "$issue_num" ]]; then
    [[ "$issue_num" =~ ^[0-9]+$ ]] || {
      printf >&2 'base-branch: issue number must be a positive integer\n'
      exit 1
    }
    if command -v gh > /dev/null 2>&1; then
      body=$(gh issue view "$issue_num" --json body --jq '.body // ""' 2> /dev/null || true)
    fi
  fi

  # 1. Parse base_branch: from body
  if [[ -n "$body" ]]; then
    local extracted
    extracted=$(printf '%s' "$body" \
      | grep -Ei '^[[:space:]]*base_branch:[[:space:]]*[a-zA-Z0-9/_.-]+' \
      | head -n1 \
      | sed 's/.*base_branch:[[:space:]]*//I' \
      | tr -d '[:space:]' \
      || true)
    if [[ -n "$extracted" ]]; then
      printf '%s\n' "$extracted"
      return 0
    fi
  fi

  # 2. Check if develop exists on remote (thin, optional)
  if git ls-remote --heads origin develop > /dev/null 2>&1 \
    && git ls-remote --heads origin develop | grep -q 'refs/heads/develop'; then
    printf 'develop\n'
    return 0
  fi

  # 3. Default
  printf 'master\n'
}

# ---------------------------------------------------------------------------
# cmd_has_pr <issue-int> [--file J]
# Emits: yes | no
# Accepts pre-fetched gh timeline JSON via --file.
# ---------------------------------------------------------------------------
cmd_has_pr() {
  _require_jq
  local issue_num=""
  local json_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        json_file="$2"
        shift 2
        ;;
      --file=*)
        json_file="${1#--file=}"
        shift
        ;;
      [0-9]*)
        issue_num="$1"
        shift
        ;;
      *)
        printf >&2 'has-pr: unknown argument: %s\n' "$1"
        exit 1
        ;;
    esac
  done

  [[ -n "$issue_num" ]] || {
    printf >&2 'has-pr: issue number required\n'
    exit 1
  }
  [[ "$issue_num" =~ ^[0-9]+$ ]] || {
    printf >&2 'has-pr: issue number must be a positive integer\n'
    exit 1
  }

  local timeline_json
  if [[ -n "$json_file" ]]; then
    timeline_json=$(cat -- "$json_file")
  elif command -v gh > /dev/null 2>&1; then
    timeline_json=$(gh api \
      "repos/{owner}/{repo}/issues/${issue_num}/timeline" \
      --paginate 2> /dev/null || printf '[]')
  else
    # Cannot check — conservatively say no
    printf 'no\n'
    return 0
  fi

  local found
  found=$(printf '%s' "$timeline_json" \
    | jq -r '[.[] | select(.event == "cross-referenced" and (.source.issue.pull_request != null))] | length' \
      2> /dev/null || printf '0')

  if [[ "$found" -gt 0 ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# ---------------------------------------------------------------------------
# cmd_filter_prs --file J
# Input:  JSON array of issue objects (each with .number, .title, .labels[].name)
#         plus optional .timeline or pre-checked .has_pr boolean field.
# Output: compact TSV lines: <number> TAB <status>
#         status = skipped_has_pr | to_process
# ---------------------------------------------------------------------------
cmd_filter_prs() {
  _require_jq
  local json_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        json_file="$2"
        shift 2
        ;;
      --file=*)
        json_file="${1#--file=}"
        shift
        ;;
      *)
        printf >&2 'filter-prs: unknown argument: %s\n' "$1"
        exit 1
        ;;
    esac
  done

  [[ -n "$json_file" ]] || {
    printf >&2 'filter-prs: --file J required\n'
    exit 1
  }

  # Emit TSV. If .has_pr field is present use it; otherwise default to to_process.
  jq -r '.[] | [
    (.number | tostring),
    (if .has_pr == true then "skipped_has_pr" else "to_process" end)
  ] | @tsv' -- "$json_file"
}

# ---------------------------------------------------------------------------
# cmd_orchestrator_update --file J --path P --issue N [field=value ...]
# Atomically patches orchestrator.json for a single issue.
# field=value pairs update .issues[] where .number==N:
#   status=completed  track=null  etc.
# Also recomputes top-level .progress counts.
# ---------------------------------------------------------------------------
cmd_orchestrator_update() {
  _require_jq
  local json_file=""
  local out_path=""
  local issue_num=""
  local -a kv_pairs=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        json_file="$2"
        shift 2
        ;;
      --file=*)
        json_file="${1#--file=}"
        shift
        ;;
      --path)
        out_path="$2"
        shift 2
        ;;
      --path=*)
        out_path="${1#--path=}"
        shift
        ;;
      --issue)
        issue_num="$2"
        shift 2
        ;;
      --issue=*)
        issue_num="${1#--issue=}"
        shift
        ;;
      *=*)
        kv_pairs+=("$1")
        shift
        ;;
      *)
        printf >&2 'orchestrator-update: unknown argument: %s\n' "$1"
        exit 1
        ;;
    esac
  done

  [[ -n "$json_file" ]] || {
    printf >&2 'orchestrator-update: --file J required\n'
    exit 1
  }
  [[ -n "$out_path" ]] || {
    printf >&2 'orchestrator-update: --path P required\n'
    exit 1
  }
  [[ -n "$issue_num" ]] || {
    printf >&2 'orchestrator-update: --issue N required\n'
    exit 1
  }
  [[ "$issue_num" =~ ^[0-9]+$ ]] || {
    printf >&2 'orchestrator-update: issue number must be a positive integer\n'
    exit 1
  }

  # Build a JSON object from kv_pairs
  local updates_json="{}"
  local pair key val
  for pair in "${kv_pairs[@]+"${kv_pairs[@]}"}"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    # Treat "null" literally; integers as numbers; else strings
    if [[ "$val" == "null" ]]; then
      updates_json=$(printf '%s' "$updates_json" | jq --arg k "$key" '. + {($k): null}')
    elif [[ "$val" =~ ^-?[0-9]+$ ]]; then
      updates_json=$(printf '%s' "$updates_json" | jq --arg k "$key" --argjson v "$val" '. + {($k): $v}')
    else
      updates_json=$(printf '%s' "$updates_json" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
    fi
  done

  local tmp_out
  tmp_out=$(mktemp)
  trap 'rm -f "$tmp_out"' EXIT

  jq \
    --argjson n "$issue_num" \
    --argjson updates "$updates_json" \
    '
      .issues = [.issues[] |
        if .number == ($n | tonumber)
        then . + $updates
        else .
        end
      ] |
      .progress = {
        total:       (.issues | length),
        completed:   [.issues[] | select(.status == "completed")]   | length,
        in_progress: [.issues[] | select(.status == "in_progress")] | length,
        pending:     [.issues[] | select(.status == "pending")]     | length,
        failed:      [.issues[] | select(.status == "failed")]      | length,
        blocked:     [.issues[] | select(.status == "blocked")]     | length
      }
    ' -- "$json_file" > "$tmp_out"

  mv -- "$tmp_out" "$out_path"
  trap - EXIT
}

# ---------------------------------------------------------------------------
# cmd_workspace_init <issue-int> <title>
# Emits compact key=value lines (no side effects, no network):
#   branch=<type>/{n}-{slug}
#   worktree_path=.worktrees/{group}/{n}
#   context_path=.worktrees/{group}/{n}/.context
# Optional env vars: MEGATASK_GROUP (default milestone-0)
# ---------------------------------------------------------------------------
cmd_workspace_init() {
  local issue_num="$1"
  local title="$2"

  [[ "$issue_num" =~ ^[0-9]+$ ]] || {
    printf >&2 'workspace-init: issue number must be a positive integer\n'
    exit 1
  }

  local branch
  branch=$(cmd_branch_name "$issue_num" "$title")

  local group="${MEGATASK_GROUP:-milestone-0}"
  local worktree_path=".worktrees/${group}/${issue_num}"
  local context_path="${worktree_path}/.context"

  printf 'branch=%s\n' "$branch"
  printf 'worktree_path=%s\n' "$worktree_path"
  printf 'context_path=%s\n' "$context_path"
}

# ---------------------------------------------------------------------------
# Self-test helpers (module-level so they are visible inside cmd_self_test)
# ---------------------------------------------------------------------------
_ST_FAILURES=0
_ST_PASS_COUNT=0

_st_check() {
  local desc="$1" expected="$2" result="$3"
  if [[ "$result" == "$expected" ]]; then
    printf 'PASS: %s\n' "$desc"
    ((_ST_PASS_COUNT++)) || true
  else
    printf 'FAIL: %s -- expected %q got %q\n' "$desc" "$expected" "$result"
    ((_ST_FAILURES++)) || true
  fi
}

_st_pass_if() {
  local desc="$1" cond="$2"
  if [[ "$cond" == "true" ]]; then
    printf 'PASS: %s\n' "$desc"
    ((_ST_PASS_COUNT++)) || true
  else
    printf 'FAIL: %s\n' "$desc"
    ((_ST_FAILURES++)) || true
  fi
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
cmd_self_test() {
  _ST_FAILURES=0
  _ST_PASS_COUNT=0

  # --- branch-name ---
  _st_check "branch basic" \
    "feature/42-add-login-flow" \
    "$(cmd_branch_name 42 "Add login flow")"

  # Type is derived, not fixed: a defect title yields `bugfix/`.
  _st_check "branch special chars + derived type" \
    "bugfix/43-fix-crash-on-startup" \
    "$(cmd_branch_name 43 "Fix: crash on startup!!!")"

  _st_check "branch derived type: refactor" \
    "refactor/44-refactor-the-reconnect-backoff" \
    "$(cmd_branch_name 44 "Refactor the reconnect backoff")"

  _st_check "branch derived type: leading build verb -> feat" \
    "feat/7-build-multiplatform-leaderboard" \
    "$(cmd_branch_name 7 "Build multiplatform leaderboard")"

  _st_check "branch leading hyphen stripped" \
    "feature/5-hello-world" \
    "$(cmd_branch_name 5 "---hello world---")"

  # Over-budget titles truncate on a word boundary, never mid-word.
  _st_check "branch truncation keeps whole words" \
    "bugfix/164-fix-the-reconstruction-scan-flow-blinking-before" \
    "$(cmd_branch_name 164 "Fix the reconstruction scan flow blinking before the first frame renders")"

  local long_slug slug_part
  long_slug=$(cmd_branch_name 1 "This is a very long feature title that should be truncated because it exceeds fifty characters")
  slug_part="${long_slug#feature/1-}"
  if [[ "${#slug_part}" -le 50 && "${#slug_part}" -gt 0 && "${slug_part}" != *- ]]; then
    _st_pass_if "branch slug length <= 50 (got ${#slug_part})" "true"
  else
    _st_pass_if "branch slug length <= 50 (got ${#slug_part})" "false"
  fi

  # Documented exception: one whole word always survives, even over budget —
  # the alternative is an empty slug, i.e. the nameless `feature/1-`.
  _st_check "branch single over-budget word survives intact" \
    "feature/1-$(printf 'a%.0s' {1..80})" \
    "$(cmd_branch_name 1 "$(printf 'a%.0s' {1..80})")"

  # A multi-line title must not yield a multi-line branch name.
  _st_check "branch multi-line title collapses to one line" \
    "feature/7-add-login-flow" \
    "$(cmd_branch_name 7 "$(printf 'Add login\nflow')")"

  # --- priority-score ---
  _st_check "priority P0" "0" "$(cmd_priority_score P0)"
  _st_check "priority critical" "0" "$(cmd_priority_score priority:critical)"
  _st_check "priority P1" "1" "$(cmd_priority_score P1)"
  _st_check "priority P3" "3" "$(cmd_priority_score P3)"
  _st_check "priority none (unknown labels)" "99" "$(cmd_priority_score bug enhancement)"
  _st_check "priority mixed picks lowest" "1" "$(cmd_priority_score bug P1 P3)"
  _st_check "priority no args" "99" "$(cmd_priority_score)"

  # --- has-pr with --file ---
  local tmp_dir
  tmp_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" EXIT

  cat > "$tmp_dir/timeline_with_pr.json" << 'EOF'
[
  {"event":"cross-referenced","source":{"issue":{"number":99,"pull_request":{"url":"https://github.com/owner/repo/pull/99"}}}},
  {"event":"labeled"}
]
EOF
  _st_check "has-pr yes" "yes" \
    "$(cmd_has_pr 1 --file "$tmp_dir/timeline_with_pr.json")"

  cat > "$tmp_dir/timeline_no_pr.json" << 'EOF'
[
  {"event":"labeled"},
  {"event":"cross-referenced","source":{"issue":{"number":10}}}
]
EOF
  _st_check "has-pr no (no pull_request field)" "no" \
    "$(cmd_has_pr 2 --file "$tmp_dir/timeline_no_pr.json")"

  printf '[]' > "$tmp_dir/empty_timeline.json"
  _st_check "has-pr empty timeline" "no" \
    "$(cmd_has_pr 3 --file "$tmp_dir/empty_timeline.json")"

  # --- filter-prs ---
  cat > "$tmp_dir/issues.json" << 'EOF'
[
  {"number":10,"title":"Issue A","has_pr":true},
  {"number":11,"title":"Issue B","has_pr":false},
  {"number":12,"title":"Issue C"}
]
EOF
  local filter_out
  filter_out=$(cmd_filter_prs --file "$tmp_dir/issues.json")
  _st_check "filter-prs line count" "3" \
    "$(printf '%s\n' "$filter_out" | grep -c . | tr -d ' ')"
  _st_check "filter-prs has_pr=true -> skipped_has_pr" "skipped_has_pr" \
    "$(printf '%s' "$filter_out" | awk 'NR==1{print $2}')"
  _st_check "filter-prs has_pr=false -> to_process" "to_process" \
    "$(printf '%s' "$filter_out" | awk 'NR==2{print $2}')"
  _st_check "filter-prs has_pr missing -> to_process" "to_process" \
    "$(printf '%s' "$filter_out" | awk 'NR==3{print $2}')"

  # --- orchestrator-update ---
  cat > "$tmp_dir/orch_in.json" << 'EOF'
{
  "issues": [
    {"number":10,"status":"in_progress","track":1},
    {"number":11,"status":"pending","track":null}
  ],
  "progress": {}
}
EOF
  local orch_out="$tmp_dir/orch_out.json"
  cmd_orchestrator_update \
    --file "$tmp_dir/orch_in.json" \
    --path "$orch_out" \
    --issue 10 \
    status=completed track=null

  _st_check "orchestrator-update issue status" "completed" \
    "$(jq -r '.issues[] | select(.number==10) | .status' "$orch_out")"
  _st_check "orchestrator-update progress.completed" "1" \
    "$(jq -r '.progress.completed' "$orch_out")"
  _st_check "orchestrator-update progress.in_progress" "0" \
    "$(jq -r '.progress.in_progress' "$orch_out")"
  _st_check "orchestrator-update untouched issue unchanged" "pending" \
    "$(jq -r '.issues[] | select(.number==11) | .status' "$orch_out")"

  # --- workspace-init ---
  local ws_out
  ws_out=$(MEGATASK_GROUP=milestone-7 cmd_workspace_init 42 "Add login flow")
  _st_check "workspace-init branch" "branch=feature/42-add-login-flow" \
    "$(printf '%s' "$ws_out" | grep '^branch=')"
  _st_check "workspace-init worktree_path" "worktree_path=.worktrees/milestone-7/42" \
    "$(printf '%s' "$ws_out" | grep '^worktree_path=')"
  _st_check "workspace-init context_path" "context_path=.worktrees/milestone-7/42/.context" \
    "$(printf '%s' "$ws_out" | grep '^context_path=')"

  # --- workspace-init default group ---
  ws_out=$(cmd_workspace_init 99 "Default Group Test")
  _st_check "workspace-init default group" "worktree_path=.worktrees/milestone-0/99" \
    "$(printf '%s' "$ws_out" | grep '^worktree_path=')"

  trap - EXIT
  rm -rf "$tmp_dir"

  if [[ $_ST_FAILURES -eq 0 ]]; then
    printf 'milestone-helpers: self-test OK (%d checks passed)\n' "$_ST_PASS_COUNT"
    return 0
  else
    printf 'milestone-helpers: self-test FAILED (%d of %d checks failed)\n' \
      "$_ST_FAILURES" "$((_ST_FAILURES + _ST_PASS_COUNT))"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------
usage() {
  cat >&2 << 'USAGE'
Usage: milestone-helpers.sh <subcommand> [args...]

Subcommands:
  branch-name <issue-int> <title>
  priority-score <label...>
  base-branch [<issue-int>] [--file J]
  has-pr <issue-int> [--file J]
  filter-prs --file J
  orchestrator-update --file J --path P --issue N [field=value ...]
  workspace-init <issue-int> <title>
  --self-test
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

subcommand="$1"
shift

case "$subcommand" in
  branch-name)
    [[ $# -ge 2 ]] || {
      printf >&2 'branch-name: requires <issue-int> <title>\n'
      exit 1
    }
    cmd_branch_name "$1" "$2"
    ;;
  priority-score)
    cmd_priority_score "$@"
    ;;
  base-branch)
    cmd_base_branch "$@"
    ;;
  has-pr)
    [[ $# -ge 1 ]] || {
      printf >&2 'has-pr: requires <issue-int>\n'
      exit 1
    }
    cmd_has_pr "$@"
    ;;
  filter-prs)
    cmd_filter_prs "$@"
    ;;
  orchestrator-update)
    cmd_orchestrator_update "$@"
    ;;
  workspace-init)
    [[ $# -ge 2 ]] || {
      printf >&2 'workspace-init: requires <issue-int> <title>\n'
      exit 1
    }
    cmd_workspace_init "$1" "$2"
    ;;
  --self-test | self-test)
    cmd_self_test
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    printf >&2 'milestone-helpers: unknown subcommand: %s\n' "$subcommand"
    usage
    ;;
esac
