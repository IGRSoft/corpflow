#!/usr/bin/env bash
# @description fn-stream-merge.sh — FN multi-stream arm: one commit per stream tree, then
#   one `--no-ff` merge per stream into the combined branch (facts.branch).
#
#   Subcommands:
#     plan    Arm selection. multi iff the non-skipped DV rows span >=2 distinct physical
#             trees; otherwise single (reason one_dv_row for <=1 row, shared_tree when
#             every row resolves to one tree). Prints
#               arm=single reason=<one_dv_row|shared_tree>
#             or
#               arm=multi streams=<n>
#             followed by one "<task>\t<stream>\t<tree>" line per row, task-id order.
#     commit  In the row's tree: `add -u`, unstage that tree's own scoped landed set,
#             `commit -F` (hooks run). New files are not picked up: FN stages them
#             first. Prints
#               <committed|already_committed|nothing_to_commit> task=<ID> stream=<s>
#                 branch=<b> sha=<sha|-> excluded=<n> untracked=<n>
#             (one line), then
#               facts={"stream_branches":{"<s>":"<b>"}}
#             which FN passes to `state-patch.sh --facts`. This script never writes state.json.
#     merge   In the current tree: cut the combined branch from the base unless it
#             exists, then for each row in task-id order merge
#             refs/heads/<facts.stream_branches[<stream>]> with `merge --no-ff -m`, the
#             message pinned to "Merge branch '<b>' into <combined>" (git's subject for a
#             short name) because a full ref argument would put refs/heads/ in it. Prints
#               <merged|already_merged> stream=<s> branch=<b> sha=<sha>
#             per stream, then
#               combined=<b> head=<sha> base=<name>
#             Every precondition is checked before the first ref moves.
#
#   Blocked (exit 1), one line: blocked reason=<token> task=<ID|-> stream=<s|->
#     arm_single tree_unresolved stream_unset not_a_work_tree detached_head on_base_branch
#     branch_invalid staged_then_modified commit_failed combined_unresolved combined_is_base
#     base_unresolved base_unresolvable dirty_tree combined_foreign_commits
#     combined_checked_out_elsewhere switch_failed stream_branch_missing stream_branch_unknown
#     landed_path_in_stream merge_conflict (after merge --abort) merge_refused (git refused
#     to start the merge; nothing to abort) stream_is_combined (a stream tree's branch, or a
#     facts.stream_branches value, is facts.branch: committing there writes the PR head
#     directly and would make every combined commit look like stream work)
#     landed_path_unsafe (land-artifacts.sh --strict refused an entry in this tree's landed
#     set — a hand-edited ledger, not this run's own write) landed_set_unreadable
#     (land-artifacts.sh could not be run or exited outside 0/1 for this tree)
#   A combined-branch commit is foreign when it is in <base_ref>..<combined>, is not an
#   ancestor of any stream branch, and is not a two-parent merge whose second parent is.
#
#   Git verbs, exhaustive: add -u, restore --staged -- <paths>, commit -F, switch,
#   switch --no-track -c <combined> <base_ref>, merge --no-ff -m, merge --abort.
#   Never push, reset, rebase, amend, delete a branch, stash, update-ref, tag or skip hooks;
#   never writes the base branch.
#
#   Audit (branch-lib.sh audit_fn, stage FN): fn_stream_arm single|multi;
#   fn_stream_commit committed|already_committed|nothing_to_commit|blocked;
#   fn_stream_merge ok|blocked|escalate.
#
# @arg --state <path>         Ledger (default .context/state.json).
# @arg --task <DVk>           commit only: the row to commit.
# @arg --message-file <path>  commit only: the commit message.
# @arg -h | --help            Print this header on stdout and exit 0.
#
# @env FN_BASE_REF            Highest-priority base override (resolve_base_ref rank 1).
# @env AUDIT_DRY_RUN          1 => no audit rows.
#
# @exitcode 0  Done, or already done (idempotent re-run).
# @exitcode 1  Blocked; the line names the reason.
# @exitcode 2  Usage: unknown subcommand or flag, missing or unreadable --message-file,
#              bad or unknown --task. Nothing on stdout.
# @exitcode 3  jq missing, ledger unreadable, or branch-lib.sh unreachable.
# @exitcode 4  Escalate: `merge --abort` failed and the tree is left mid-merge.
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail
IFS=$'\n\t'

usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0"
  exit 0
}

die_usage() {
  printf >&2 'fn-stream-merge: %s\n' "$1"
  exit 2
}

die_input() {
  printf >&2 'fn-stream-merge: %s\n' "$1"
  exit 3
}

_resolve_script_dir() {
  local src="${BASH_SOURCE[0]:-$0}" dir
  while [ -h "$src" ]; do
    dir=$(CDPATH='' cd -- "$(dirname -- "$src")" && pwd -P)
    src=$(readlink "$src")
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  CDPATH='' cd -- "$(dirname -- "$src")" && pwd -P
}
SCRIPT_DIR="$(_resolve_script_dir 2> /dev/null)" || SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"

BRANCH_RE='^[A-Za-z0-9._/][A-Za-z0-9._/-]{0,199}$'

COMMAND=""
STATE_ARG=".context/state.json"
TASK_ARG=""
MSG_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    plan | commit | merge)
      [[ -z "$COMMAND" ]] || die_usage "one subcommand only"
      COMMAND="$1"
      shift
      ;;
    --state)
      [[ $# -ge 2 && -n "$2" ]] || die_usage "--state needs a path"
      STATE_ARG="$2"
      shift 2
      ;;
    --task)
      [[ $# -ge 2 ]] || die_usage "--task needs a task id"
      [[ "$2" =~ ^DV[0-9]+$ ]] || die_usage "bad --task: $2 (expected DV<k>)"
      TASK_ARG="$2"
      shift 2
      ;;
    --message-file)
      [[ $# -ge 2 && -n "$2" ]] || die_usage "--message-file needs a path"
      MSG_ARG="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[[ -n "$COMMAND" ]] || die_usage "no subcommand (plan | commit | merge)"
if [[ "$COMMAND" == "commit" ]]; then
  [[ -n "$TASK_ARG" ]] || die_usage "commit needs --task"
  [[ -n "$MSG_ARG" ]] || die_usage "commit needs --message-file"
  [[ -r "$MSG_ARG" && -s "$MSG_ARG" ]] || die_usage "--message-file unreadable or empty: $MSG_ARG"
else
  [[ -z "$TASK_ARG" && -z "$MSG_ARG" ]] || die_usage "--task and --message-file apply to commit only"
fi

command -v jq > /dev/null 2>&1 || die_input "jq not found"
if ! { [[ -r "$STATE_ARG" ]] && jq -e 'type == "object"' "$STATE_ARG" > /dev/null 2>&1; }; then
  die_input "ledger unreadable: $STATE_ARG"
fi

BRANCH_LIB_PATH="${SCRIPT_DIR}/branch-lib.sh"
if [ -r "$BRANCH_LIB_PATH" ]; then
  # shellcheck source=branch-lib.sh
  . "$BRANCH_LIB_PATH"
else
  die_input "branch-lib.sh unreachable at ${BRANCH_LIB_PATH} — plugin install broken"
fi

realpath_of() {
  [[ -n "${1:-}" ]] || return 1
  (CDPATH='' cd -- "$1" 2> /dev/null && pwd -P) || return 1
}

# audit_fn reads both as globals; absolute so a later cd into a stream tree keeps them.
STATE_PATH="$(realpath_of "$(dirname -- "$STATE_ARG")")/$(basename -- "$STATE_ARG")"
CONTEXT_DIR="$(dirname -- "$STATE_PATH")"
export STATE_PATH CONTEXT_DIR
if [[ -n "$MSG_ARG" ]]; then
  MSG_ARG="$(realpath_of "$(dirname -- "$MSG_ARG")")/$(basename -- "$MSG_ARG")"
fi

ACTION="fn_stream_arm"
case "$COMMAND" in
  commit) ACTION="fn_stream_commit" ;;
  merge) ACTION="fn_stream_merge" ;;
esac

blocked() { # $1=reason $2=task $3=stream
  printf 'blocked reason=%s task=%s stream=%s\n' "$1" "${2:--}" "${3:--}"
  audit_fn "$ACTION" blocked "$(meta_json reason "$1" task "${2:--}" stream "${3:--}")"
  exit 1
}

# "-" stands in for an empty field: TAB is IFS whitespace, so read would collapse it.
ROWS=$(jq -r '.tasks // {} | to_entries
  | map(select(.value.metadata.stage == "DV" and (.key | test("^DV[0-9]+$"))))
  | sort_by(.key | ltrimstr("DV") | tonumber)
  | map(select((.value.status // "") != "skipped"))
  | .[] | [.key, .value.metadata.stream, .value.metadata.workspace_path]
  | map(if (type == "string") and (. != "") then . else "-" end) | @tsv' "$STATE_PATH" 2> /dev/null) \
  || die_input "ledger unreadable: $STATE_ARG"

ROW_COUNT=0
[[ -z "$ROWS" ]] || ROW_COUNT=$(printf '%s\n' "$ROWS" | awk 'END { print NR }')

# Sets ARM (single|multi) and ARM_REASON; blocks when a multi-row ledger is malformed.
select_arm() {
  local id stream tree real reals="" distinct
  ARM="single"
  ARM_REASON="one_dv_row"
  [[ "$ROW_COUNT" -ge 2 ]] || return 0
  while IFS=$'\t' read -r id stream tree; do
    [[ "$tree" == /* ]] || blocked tree_unresolved "$id" "$stream"
    real=$(realpath_of "$tree") || blocked tree_unresolved "$id" "$stream"
    reals="${reals}${real}"$'\n'
  done <<< "$ROWS"
  distinct=$(printf '%s' "$reals" | LC_ALL=C sort -u | awk 'NF { n++ } END { print n + 0 }')
  if [[ "$distinct" -lt 2 ]]; then
    ARM_REASON="shared_tree"
    return 0
  fi
  while IFS=$'\t' read -r id stream tree; do
    [[ "$stream" != "-" ]] || blocked stream_unset "$id" "-"
  done <<< "$ROWS"
  ARM="multi"
  ARM_REASON="-"
}

# Base name and git ref for the cwd tree; blocks when either is unresolvable.
resolve_base() { # $1=task $2=stream
  BASE_NAME=$(resolve_base_ref)
  [[ -n "$BASE_NAME" ]] || blocked base_unresolved "$1" "$2"
  BASE_GIT_REF=$(resolve_git_ref "$BASE_NAME" || printf '')
  [[ -n "$BASE_GIT_REF" ]] || blocked base_unresolvable "$1" "$2"
}

# landed_for_tree <tree> <task> <stream> — fills LANDED[] from land-artifacts.sh's
# own --list-landed --strict for that ONE tree, never a global union: the same
# path landed into a sibling stream's tree must stay visible in this one. A
# refused (unsafe) or unreadable set blocks rather than silently excluding
# nothing, because this exclusion is what keeps a landed file out of a commit.
landed_for_tree() {
  local tree="$1" task="$2" stream="$3" land="${SCRIPT_DIR}/land-artifacts.sh" line out rc=0
  [ -r "$land" ] || die_input "land-artifacts.sh unreachable at ${land} — plugin install broken"
  LANDED=()
  out=$(bash "$land" --list-landed --tree "$tree" --strict --state "$STATE_PATH" < /dev/null 2> /dev/null) || rc=$?
  case "$rc" in
    0) ;;
    1) blocked landed_path_unsafe "$task" "$stream" ;;
    *) blocked landed_set_unreadable "$task" "$stream" ;;
  esac
  [[ -z "$out" ]] || while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    LANDED+=("$line")
  done <<< "$out"
}

cmd_plan() {
  select_arm
  if [[ "$ARM" == "single" ]]; then
    printf 'arm=single reason=%s\n' "$ARM_REASON"
    audit_fn fn_stream_arm single "$(meta_json reason "$ARM_REASON" rows "$ROW_COUNT")"
    return 0
  fi
  printf 'arm=multi streams=%s\n' "$ROW_COUNT"
  printf '%s\n' "$ROWS"
  audit_fn fn_stream_arm multi "$(meta_json streams "$ROW_COUNT")"
}

cmd_commit() {
  local row id stream tree real branch staged unstaged both result sha excluded=0 untracked untracked_landed
  local restore=()
  select_arm
  [[ "$ARM" == "multi" ]] || blocked arm_single "$TASK_ARG" "-"
  row=$(printf '%s\n' "$ROWS" | awk -F'\t' -v t="$TASK_ARG" '$1 == t { print; exit }')
  [[ -n "$row" ]] || die_usage "unknown --task: $TASK_ARG"
  IFS=$'\t' read -r id stream tree <<< "$row"
  real=$(realpath_of "$tree") || blocked tree_unresolved "$id" "$stream"
  cd -- "$real"
  [[ "$(git rev-parse --is-inside-work-tree 2> /dev/null || printf false)" == "true" ]] \
    || blocked not_a_work_tree "$id" "$stream"
  branch=$(git symbolic-ref --quiet --short HEAD 2> /dev/null || printf '')
  [[ -n "$branch" ]] || blocked detached_head "$id" "$stream"
  [[ "$branch" =~ $BRANCH_RE ]] || blocked branch_invalid "$id" "$stream"
  [[ "$branch" != "$(jq -r '.facts.branch // "" | strings' "$STATE_PATH" 2> /dev/null || printf '')" ]] \
    || blocked stream_is_combined "$id" "$stream"

  export WORKSPACE_ROOT="$real"
  resolve_base "$id" "$stream"
  [[ "$branch" != "${BASE_NAME#origin/}" ]] || blocked on_base_branch "$id" "$stream"

  landed_for_tree "$real" "$id" "$stream"

  # Same predicate as fn-preflight.sh staging: which bytes were meant is a human call.
  staged=$(git diff --cached --name-only 2> /dev/null || printf '')
  unstaged=$(git diff --name-only 2> /dev/null || printf '')
  if [[ -n "$staged" && -n "$unstaged" ]]; then
    both=$(printf '%s\n' "$staged" | grep -Fxf <(printf '%s\n' "$unstaged") 2> /dev/null || true)
    [[ -z "$both" ]] || blocked staged_then_modified "$id" "$stream"
  fi

  # A landed path already committed on the stream cannot be removed without a rewrite.
  if [[ "${#LANDED[@]}" -gt 0 ]] &&
     [[ -n "$(git diff --name-only "${BASE_GIT_REF}...HEAD" -- "${LANDED[@]}" 2> /dev/null || printf '')" ]]; then
    blocked landed_path_in_stream "$id" "$stream"
  fi

  git add -u || blocked commit_failed "$id" "$stream"
  if [[ "${#LANDED[@]}" -gt 0 ]]; then
    while IFS= read -r -d '' p; do
      restore+=("$p")
    done < <(git diff --cached --name-only -z -- "${LANDED[@]}" 2> /dev/null || true)
    if [[ "${#restore[@]}" -gt 0 ]]; then
      git restore --staged -- "${restore[@]}" || blocked commit_failed "$id" "$stream"
      excluded="${#restore[@]}"
    fi
  fi

  if git diff --cached --quiet 2> /dev/null; then
    if [[ "$(git rev-list --count "${BASE_GIT_REF}..HEAD" 2> /dev/null || printf 0)" -gt 0 ]]; then
      result="already_committed"
      sha=$(git rev-parse HEAD)
    else
      result="nothing_to_commit"
      sha="-"
    fi
  else
    git commit -q -F "$MSG_ARG" || blocked commit_failed "$id" "$stream"
    result="committed"
    sha=$(git rev-parse HEAD)
  fi

  untracked=$(git ls-files --others --exclude-standard 2> /dev/null | awk 'END { print NR }')
  if [[ "${#LANDED[@]}" -gt 0 ]]; then
    # Only the untracked half is dropped: a landed path already staged or
    # modified on this branch stays visible, exactly like the exclusion above.
    untracked_landed=$(git ls-files --others --exclude-standard -- "${LANDED[@]}" 2> /dev/null | awk 'END { print NR }')
    untracked=$((untracked - untracked_landed))
    [[ "$untracked" -ge 0 ]] || untracked=0
  fi
  if [[ "$untracked" -gt 0 ]]; then
    printf >&2 'fn-stream-merge: %s untracked path(s) in %s were not committed; stage them first if they belong to the stream\n' \
      "$untracked" "$real"
  fi

  printf '%s task=%s stream=%s branch=%s sha=%s excluded=%s untracked=%s\n' \
    "$result" "$id" "$stream" "$branch" "$sha" "$excluded" "$untracked"
  jq -cn --arg s "$stream" --arg b "$branch" '"facts=" + ({stream_branches: {($s): $b}} | tojson)' -r
  audit_fn fn_stream_commit "$result" \
    "$(meta_json task "$id" stream "$stream" branch "$branch" sha "$sha" excluded "$excluded")"
}

is_ancestor_of_any_stream() { # $1=commit; STREAM_REFS global
  local r
  for r in "${STREAM_REFS[@]}"; do
    git merge-base --is-ancestor "$1" "$r" 2> /dev/null && return 0
  done
  return 1
}

cmd_merge() {
  local top combined id stream tree real b c _p1 p2 extra current wt_path wt_line merged=()
  local streams=() branches=()
  STREAM_REFS=()
  select_arm
  [[ "$ARM" == "multi" ]] || blocked arm_single "-" "-"
  [[ "$(git rev-parse --is-inside-work-tree 2> /dev/null || printf false)" == "true" ]] \
    || blocked not_a_work_tree "-" "-"
  top=$(git rev-parse --show-toplevel)
  top=$(realpath_of "$top")
  export WORKSPACE_ROOT="${WORKSPACE_ROOT:-$top}"

  combined=$(jq -r '.facts.branch // "" | strings' "$STATE_PATH" 2> /dev/null || printf '')
  [[ -n "$combined" ]] || blocked combined_unresolved "-" "-"
  [[ "$combined" =~ $BRANCH_RE ]] || blocked branch_invalid "-" "-"
  resolve_base "-" "-"
  [[ "$combined" != "${BASE_NAME#origin/}" ]] || blocked combined_is_base "-" "-"
  if ! { git diff --quiet 2> /dev/null && git diff --cached --quiet 2> /dev/null; }; then
    blocked dirty_tree "-" "-"
  fi

  while IFS=$'\t' read -r id stream tree; do
    b=$(jq -r --arg s "$stream" '.facts.stream_branches[$s]? // "" | strings' "$STATE_PATH" 2> /dev/null || printf '')
    [[ -n "$b" ]] || blocked stream_branch_missing "$id" "$stream"
    [[ "$b" =~ $BRANCH_RE ]] || blocked branch_invalid "$id" "$stream"
    # Checked before STREAM_REFS grows: combined as a stream ref would vouch for every
    # commit on it and silence the foreign-commit guard.
    [[ "$b" != "$combined" ]] || blocked stream_is_combined "$id" "$stream"
    git rev-parse --verify --quiet "refs/heads/${b}^{commit}" > /dev/null 2>&1 \
      || blocked stream_branch_unknown "$id" "$stream"
    # Scoped to THIS row's own tree, never a sibling stream's: two trees can
    # legitimately land the same-named path, and only one of them may ship it.
    real=$(realpath_of "$tree") || blocked tree_unresolved "$id" "$stream"
    landed_for_tree "$real" "$id" "$stream"
    if [[ "${#LANDED[@]}" -gt 0 ]] &&
       [[ -n "$(git diff --name-only "${BASE_GIT_REF}...refs/heads/${b}" -- "${LANDED[@]}" 2> /dev/null || printf '')" ]]; then
      blocked landed_path_in_stream "$id" "$stream"
    fi
    streams+=("$stream")
    branches+=("$b")
    STREAM_REFS+=("refs/heads/${b}")
  done <<< "$ROWS"

  if git rev-parse --verify --quiet "refs/heads/${combined}^{commit}" > /dev/null 2>&1; then
    wt_path=""
    while IFS= read -r wt_line; do
      case "$wt_line" in
        "worktree "*) wt_path="${wt_line#worktree }" ;;
        "branch refs/heads/${combined}")
          if [[ "$(realpath_of "$wt_path" || printf '%s' "$wt_path")" != "$top" ]]; then
            blocked combined_checked_out_elsewhere "-" "-"
          fi
          ;;
      esac
    done <<< "$(git worktree list --porcelain 2> /dev/null || printf '')"

    while IFS=' ' read -r c _p1 p2 extra; do
      [[ -n "$c" ]] || continue
      is_ancestor_of_any_stream "$c" && continue
      if [[ -n "${p2:-}" && -z "${extra:-}" ]] && is_ancestor_of_any_stream "$p2"; then
        continue
      fi
      blocked combined_foreign_commits "-" "-"
    done <<< "$(git rev-list --parents "${BASE_GIT_REF}..refs/heads/${combined}" 2> /dev/null || printf '')"

    current=$(git symbolic-ref --quiet --short HEAD 2> /dev/null || printf '')
    if [[ "$current" != "$combined" ]]; then
      git switch -q "$combined" || blocked switch_failed "-" "-"
    fi
  else
    git switch -q --no-track -c "$combined" "$BASE_GIT_REF" || blocked switch_failed "-" "-"
  fi

  local i
  for ((i = 0; i < ${#streams[@]}; i++)); do
    stream="${streams[$i]}"
    b="${branches[$i]}"
    if git merge-base --is-ancestor "refs/heads/${b}" HEAD 2> /dev/null; then
      printf 'already_merged stream=%s branch=%s sha=%s\n' "$stream" "$b" "$(git rev-parse "refs/heads/${b}")"
      merged+=("${stream}:already_merged")
      continue
    fi
    # Full ref: a same-named tag would otherwise win git's ref disambiguation.
    if ! git merge -q --no-ff -m "Merge branch '${b}' into ${combined}" "refs/heads/${b}"; then
      if git rev-parse --verify --quiet MERGE_HEAD > /dev/null 2>&1; then
        if ! git merge --abort; then
          printf 'escalate reason=merge_abort_failed task=- stream=%s\n' "$stream"
          audit_fn fn_stream_merge escalate "$(meta_json reason merge_abort_failed stream "$stream" branch "$b")"
          exit 4
        fi
        blocked merge_conflict "-" "$stream"
      fi
      blocked merge_refused "-" "$stream"
    fi
    printf 'merged stream=%s branch=%s sha=%s\n' "$stream" "$b" "$(git rev-parse HEAD)"
    merged+=("${stream}:merged")
  done

  printf 'combined=%s head=%s base=%s\n' "$combined" "$(git rev-parse HEAD)" "$BASE_NAME"
  audit_fn fn_stream_merge ok "$(meta_json combined "$combined" head "$(git rev-parse HEAD)" \
    base "$BASE_NAME" streams "$(IFS=,; printf '%s' "${merged[*]}")")"
}

case "$COMMAND" in
  plan) cmd_plan ;;
  commit) cmd_commit ;;
  merge) cmd_merge ;;
esac
