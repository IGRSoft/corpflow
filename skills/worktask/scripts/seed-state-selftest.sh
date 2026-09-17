#!/usr/bin/env bash
# seed-state-selftest.sh — the `--self-test` harness for seed-state.sh.
#
# Sourced, never executed. Every case runs the script as a child process, because its
# exits 3 and 4 would otherwise end self_test itself. It runs inside an `if`, so errexit
# is off here and each step checks its own status.
#
# Contract: defines `self_test`, returning 0 only when every case passes.

_ST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_ST_SCRIPT="$_ST_DIR/seed-state.sh"
_ST_PATCH="$_ST_DIR/state-patch.sh"
_ST_TD=""
_ST_ERR=""
_ST_OUT=""
_ST_RC=0
_ST_FAILS=0

# _st_run <cwd> <NAME=value|-> <args...> — sets _ST_OUT and _ST_RC; stderr to _ST_ERR.
_st_run() {
  local cwd=$1 kv=$2
  shift 2
  _ST_RC=0
  if [ "$kv" = "-" ]; then
    _ST_OUT=$(cd "$cwd" && bash "$_ST_SCRIPT" "$@" 2> "$_ST_ERR") || _ST_RC=$?
  else
    _ST_OUT=$(cd "$cwd" && env "$kv" bash "$_ST_SCRIPT" "$@" 2> "$_ST_ERR") || _ST_RC=$?
  fi
}

_st_repo() {
  mkdir -p "$1" \
    && git -c init.defaultBranch=main -C "$1" init -q \
    && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty --no-verify -m i
}

_st_case() {
  if "$2"; then
    printf 'seed-state self-test: ok   %s\n' "$1"
  else
    printf 'seed-state self-test: FAIL %s (rc=%s stderr=%s)\n' "$1" "$_ST_RC" \
      "$(head -c 200 "$_ST_ERR" 2> /dev/null | tr '\n' ' ')"
    _ST_FAILS=$((_ST_FAILS + 1))
  fi
}

_st_s1_shape() {
  local r="$_ST_TD/s1"
  _st_repo "$r" && mkdir "$r/.context" || return 1
  _st_run "$r" - --worktask-id wt-1 --goal hello --platform systems
  [ "$_ST_RC" -eq 0 ] || return 1
  [ "$_ST_OUT" = "$(printf 'result=seeded\nstate=%s\nrun_index=0\nplan_file=.context/planning-0.md' \
    "$r/.context/state.json")" ] || return 1
  jq -e --arg ws "$r" '
    (keys_unsorted == ["version","worktask_id","plan_file","platform","run_index",
                       "metadata","tasks","facts","handoffs"])
    and .version == 2 and .worktask_id == "wt-1" and .platform == "systems"
    and .plan_file == ".context/planning-0.md" and .run_index == 0
    and .metadata == {workspace_path: $ws}
    and .tasks == {PL0: {status: "in_progress"}}
    and .facts == {goal: "hello", files_modified: [], tests_added: [], decisions: [],
                   open_questions: [], verdicts: {}, dispatched_agents: []}
    and .handoffs == {}
    and ([paths | .[] | strings
          | select(. == "completed_via" or . == "last_error"
                   or . == "worktree" or . == "capabilities")] | length == 0)' \
    "$r/.context/state.json" > /dev/null
}

_st_s2_no_leftovers() {
  [ "$(ls -A "$_ST_TD/s1/.context")" = "state.json" ]
}

_st_s3_next_index() {
  local r="$_ST_TD/s3"
  _st_repo "$r" && mkdir "$r/.context" || return 1
  : > "$r/.context/planning-0.md"
  : > "$r/.context/planning-2.md"
  : > "$r/.context/planning-1a.md"
  : > "$r/.context/planning-.md"
  _st_run "$r" - --worktask-id wt-3 --goal g
  [ "$_ST_RC" -eq 0 ] || return 1
  jq -e '.run_index == 3 and .plan_file == ".context/planning-3.md" and .platform == "all"' \
    "$r/.context/state.json" > /dev/null
}

_st_s4_exists() {
  local ctx="$_ST_TD/s1/.context"
  cp "$ctx/state.json" "$_ST_TD/s4.before" || return 1
  _st_run "$_ST_TD/s1" - --worktask-id other --goal changed
  [ "$_ST_RC" -eq 3 ] || return 1
  [ "$_ST_OUT" = "$(printf 'result=exists\nstate=%s' "$ctx/state.json")" ] || return 1
  cmp -s "$_ST_TD/s4.before" "$ctx/state.json" || return 1
  [ "$(ls -A "$ctx")" = "state.json" ]
}

_st_s5_goal_escaping() {
  local r="$_ST_TD/s5" mid goal want
  _st_repo "$r" && mkdir "$r/.context" || return 1
  mid=$(jq -nr '[97,1,10,133,98] | implode') || return 1
  goal="  \"q\\ \$(touch $_ST_TD/sentinel) $mid  "
  want="\"q\\ \$(touch $_ST_TD/sentinel) a b"
  _st_run "$r" - --worktask-id wt-5 --goal "$goal"
  [ "$_ST_RC" -eq 0 ] || return 1
  [ ! -e "$_ST_TD/sentinel" ] || return 1
  jq -e --arg want "$want" '.facts.goal == $want' "$r/.context/state.json" > /dev/null
}

_st_s6_goal_cap() {
  local r="$_ST_TD/s6" g
  _st_repo "$r" || return 1
  mkdir -p "$r/a/.context" "$r/b/.context" "$r/c/.context" || return 1
  g=$(jq -nr '[range(300) | 120] | implode') || return 1
  _st_run "$r" - --worktask-id wt-6 --goal "$g" --context-dir "$r/a/.context"
  [ "$_ST_RC" -eq 0 ] || return 1
  jq -e '(.facts.goal | length) == 240 and (.facts.goal | endswith("\u2026"))
    and (.facts.goal[0:239] == ([range(239) | 120] | implode))' \
    "$r/a/.context/state.json" > /dev/null || return 1
  g=$(jq -nr '[range(240) | 120] | implode') || return 1
  _st_run "$r" - --worktask-id wt-6 --goal "$g" --context-dir "$r/b/.context"
  [ "$_ST_RC" -eq 0 ] || return 1
  jq -e --arg g "$g" '.facts.goal == $g' "$r/b/.context/state.json" > /dev/null || return 1
  g=$(jq -nr '[range(241) | 128512] | implode') || return 1
  _st_run "$r" - --worktask-id wt-6 --goal "$g" --context-dir "$r/c/.context"
  [ "$_ST_RC" -eq 0 ] || return 1
  jq -e '(.facts.goal | length) == 240
    and (.facts.goal[0:239] == ([range(239) | 128512] | implode))
    and (.facts.goal | endswith("\u2026"))' "$r/c/.context/state.json" > /dev/null
}

_st_s7_worktree_own() {
  local m="$_ST_TD/s7main" wt="$_ST_TD/s7wt"
  _st_repo "$m" && mkdir "$m/.context" || return 1
  git -C "$m" worktree add -q --detach "$wt" 2> /dev/null && mkdir "$wt/.context" || return 1
  _st_run "$wt" "CLAUDE_PROJECT_DIR=$m" --worktask-id wt-7 --goal g
  [ "$_ST_RC" -eq 0 ] || return 1
  case "
$_ST_OUT
" in
    *"
state=$wt/.context/state.json
"*) ;;
    *) return 1 ;;
  esac
  [ ! -e "$m/.context/state.json" ]
}

_st_s7b_worktree_unresolved() {
  local m="$_ST_TD/s7main" wt="$_ST_TD/s7wt2"
  git -C "$m" worktree add -q --detach "$wt" 2> /dev/null || return 1
  _st_run "$wt" "CLAUDE_PROJECT_DIR=$m" --worktask-id wt-7b --goal g
  [ "$_ST_RC" -eq 4 ] && [ -z "$_ST_OUT" ] || return 1
  [ ! -e "$m/.context/state.json" ] && [ ! -e "$wt/.context" ]
}

_st_s7c_project_dir_inside() {
  local r="$_ST_TD/s7c"
  _st_repo "$r" && mkdir -p "$r/sub/.context" || return 1
  _st_run "$r" "CLAUDE_PROJECT_DIR=$r/sub" --worktask-id wt-7c --goal g
  [ "$_ST_RC" -eq 0 ] && [ -f "$r/sub/.context/state.json" ]
}

_st_s7d_outside_git() {
  local d="$_ST_TD/nogit"
  mkdir -p "$d/.context" || return 1
  _st_run "$d" - --worktask-id wt-7d --goal g
  [ "$_ST_RC" -eq 4 ] && [ ! -e "$d/.context/state.json" ]
}

_st_s8_task_create() {
  local r="$_ST_TD/s8" st
  _st_repo "$r" && mkdir "$r/.context" || return 1
  _st_run "$r" - --worktask-id wt-8 --goal g
  [ "$_ST_RC" -eq 0 ] || return 1
  st="$r/.context/state.json"
  cp "$st" "$_ST_TD/s8.before" || return 1
  local rc=0
  (cd "$r" && bash "$_ST_PATCH" --state "$st" --log "$_ST_TD/s8.log" --task-create DV0 \
    --metadata '{"agent":"x","effort":"high","isolation":"worktree","requires_screenshots":false,"workspace_path":"/abs"}') \
    > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && cmp -s "$_ST_TD/s8.before" "$st" || return 1
  rc=0
  (cd "$r" && bash "$_ST_PATCH" --state "$st" --log "$_ST_TD/s8.log" --task-create DV0 \
    --metadata '{"agent":"x","effort":"high","isolation":"worktree","base_ref":"origin/develop","requires_screenshots":false,"workspace_path":"/abs"}') \
    > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || return 1
  jq -e '.tasks.DV0.status == "pending" and .tasks.PL0.status == "in_progress"' "$st" > /dev/null
}

_st_s9_usage() {
  local r="$_ST_TD/s9"
  _st_repo "$r" && mkdir "$r/.context" || return 1
  _st_run "$r" - --worktask-id wt-9
  [ "$_ST_RC" -eq 2 ] && [ -z "$_ST_OUT" ] || return 1
  _st_run "$r" - --worktask-id wt-9 --goal g --bogus x
  [ "$_ST_RC" -eq 2 ] || return 1
  _st_run "$r" - --worktask-id wt-9 --goal g --workspace-path rel/path
  [ "$_ST_RC" -eq 2 ] || return 1
  _st_run "$r" - --worktask-id=wt-9 --goal g
  [ "$_ST_RC" -eq 2 ] || return 1
  _st_run "$r" - --worktask-id wt-9 --goal g --goal h
  [ "$_ST_RC" -eq 2 ] || return 1
  _st_run "$r" - --worktask-id wt-9 --goal
  [ "$_ST_RC" -eq 2 ] || return 1
  _st_run "$r" - --worktask-id 'bad id' --goal g
  [ "$_ST_RC" -eq 2 ] || return 1
  _st_run "$r" - --worktask-id wt-9 --goal g --platform 'iOS'
  [ "$_ST_RC" -eq 2 ] || return 1
  [ -z "$(ls -A "$r/.context")" ]
}

_st_s10_foreign_lock() {
  local r="$_ST_TD/s10" lock
  _st_repo "$r" && mkdir "$r/.context" || return 1
  lock="$r/.context/state.json.lock.d"
  mkdir "$lock" && printf 'other:1:0\n' > "$lock/owner" || return 1
  _st_run "$r" "STATE_LOCK_TIMEOUT_S=1" --worktask-id wt-10 --goal g
  [ "$_ST_RC" -eq 1 ] && [ -z "$_ST_OUT" ] || return 1
  [ "$(cat "$lock/owner")" = "other:1:0" ] || return 1
  [ "$(ls -A "$r/.context")" = "state.json.lock.d" ]
}

_st_s11_dangling_symlink() {
  local r="$_ST_TD/s11"
  _st_repo "$r" && mkdir "$r/.context" || return 1
  ln -s "$_ST_TD/missing-target" "$r/.context/state.json" || return 1
  _st_run "$r" - --worktask-id wt-11 --goal g
  [ "$_ST_RC" -eq 3 ] || return 1
  [ -L "$r/.context/state.json" ] && [ ! -e "$r/.context/state.json" ]
}

_st_s12_rank5_escape() {
  local r="$_ST_TD/repo" x="$_ST_TD/repo-x" e="$_ST_TD/esc" out="$_ST_TD/outside"
  _st_repo "$r" && mkdir -p "$x/.context" || return 1
  _st_run "$r" "CLAUDE_PROJECT_DIR=$x" --worktask-id wt-12 --goal g
  [ "$_ST_RC" -eq 4 ] && [ ! -e "$x/.context/state.json" ] || return 1
  _st_repo "$e" && mkdir -p "$e/sub" "$out" || return 1
  ln -s "$out" "$e/sub/.context" || return 1
  _st_run "$e" "CLAUDE_PROJECT_DIR=$e/sub" --worktask-id wt-12 --goal g
  [ "$_ST_RC" -eq 4 ] && [ ! -e "$out/state.json" ]
}

_st_s13_blank_goal() {
  local r="$_ST_TD/s13" g
  _st_repo "$r" && mkdir "$r/.context" || return 1
  g=$(jq -nr '[32,9,10,32,1,32] | implode') || return 1
  _st_run "$r" - --worktask-id wt-13 --goal "$g"
  [ "$_ST_RC" -eq 2 ] && [ -z "$(ls -A "$r/.context")" ]
}

_st_s14_context_dir_rank() {
  local r="$_ST_TD/s14"
  _st_repo "$r" && mkdir -p "$r/flag" "$r/env" || return 1
  _st_run "$r" "CONTEXT_DIR=$r/env" --worktask-id wt-14 --goal g --context-dir "$r/flag"
  [ "$_ST_RC" -eq 0 ] && [ -f "$r/flag/state.json" ] && [ ! -e "$r/env/state.json" ] || return 1
  _st_run "$r" - --worktask-id wt-14 --goal g --context-dir "$r/missing"
  [ "$_ST_RC" -eq 4 ] && [ ! -e "$r/missing" ]
}

self_test() {
  unset CONTEXT_DIR WORKSPACE_ROOT CLAUDE_PROJECT_DIR CDPATH GIT_DIR GIT_WORK_TREE \
    GIT_INDEX_FILE GIT_COMMON_DIR STATE_LOCK_TIMEOUT_S
  _ST_TD=$(mktemp -d "${TMPDIR:-/tmp}/seed-state.XXXXXX") || return 1
  _ST_TD=$(cd "$_ST_TD" && pwd -P) || return 1
  trap 'rm -rf "$_ST_TD"' EXIT
  export HOME="$_ST_TD" XDG_CONFIG_HOME="$_ST_TD" GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$_ST_TD"
  _ST_ERR="$_ST_TD/stderr"
  _ST_FAILS=0

  if ! command -v jq > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; then
    printf >&2 'seed-state self-test: jq and git are required\n'
    return 1
  fi

  _st_case "S1 seed shape and stdout keys" _st_s1_shape
  _st_case "S2 no temp or lock left" _st_s2_no_leftovers
  _st_case "S3 next free planning index" _st_s3_next_index
  _st_case "S4 existing ledger refused byte-identical" _st_s4_exists
  _st_case "S5 goal escaping, nothing evaluated" _st_s5_goal_escaping
  _st_case "S6 goal capped at 240 codepoints" _st_s6_goal_cap
  _st_case "S7 linked worktree seeds its own ledger" _st_s7_worktree_own
  _st_case "S7b worktree without .context exits 4" _st_s7b_worktree_unresolved
  _st_case "S7c CLAUDE_PROJECT_DIR inside toplevel" _st_s7c_project_dir_inside
  _st_case "S7d outside git exits 4, never cwd" _st_s7d_outside_git
  _st_case "S8 state-patch --task-create accept/refuse" _st_s8_task_create
  _st_case "S9 usage errors exit 2" _st_s9_usage
  _st_case "S10 foreign lock times out intact" _st_s10_foreign_lock
  _st_case "S11 dangling symlink ledger exits 3" _st_s11_dangling_symlink
  _st_case "S12 rank-5 prefix or symlink escape exits 4" _st_s12_rank5_escape
  _st_case "S13 blank goal exits 2" _st_s13_blank_goal
  _st_case "S14 --context-dir outranks CONTEXT_DIR" _st_s14_context_dir_rank

  if [ "$_ST_FAILS" -eq 0 ]; then
    printf 'seed-state self-test: ALL PASS\n'
    return 0
  fi
  printf 'seed-state self-test: %s case(s) failed\n' "$_ST_FAILS"
  return 1
}
