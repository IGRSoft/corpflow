#!/usr/bin/env bash
# @description resolve-root.sh — the git arm of the root-resolution ladder (see
#   skills/shared/lib/README.md and hooks/model-switch-lib.sh). Every caller tries its
#   declared roots first (--state, CONTEXT_DIR, WORKSPACE_ROOT, CLAUDE_PROJECT_DIR, the
#   own-worktree-ledger rank); this script is what runs only once those all miss, and it
#   is the one place that walks git plumbing to answer "which .context/ owns this tree".
#
#   Two-step resolution, deliberately not one:
#     1. Git common dir — proves a git repository is reachable from cwd at all (honors
#        GIT_DIR/GIT_WORK_TREE the way `git rev-parse` already does; no extra handling
#        needed here). Nothing resolves => exit 1, the "no root anywhere" case every
#        caller falls back to cwd over — which this script refuses to do.
#     2. Main worktree — the FIRST `worktree <path>` record of
#        `git worktree list --porcelain`, physicalized. Deliberately NOT
#        `dirname(common-dir)`: that guess is wrong for a submodule (whose common dir
#        lives under `.git/modules/<name>`) and for `--separate-git-dir`. A linked
#        worktree's `.context/` is gitignored and never checked out there, so every
#        stream — main checkout, linked worktree, any subdirectory of either — must
#        land on the SAME main worktree to find the one real `.context/`.
#
#   The common-dir probe tries `--path-format=absolute` first and only trusts it when the
#   result starts with `/` and names a directory: old git versions that do not know the
#   flag echo it back as if it were a revision argument, and an unchecked value would be
#   read as a bogus path instead of a probe failure.
#
# @arg (none)      Print the main worktree's .context directory (existence unchecked).
# @arg --root      Print the main worktree itself.
# @arg --self-test Run the built-in self-test and exit.
# @arg -h | --help Show this header.
#
# @exitcode 0  Resolved; exactly one line on stdout.
# @exitcode 1  No git common dir resolves (outside any repository, or git absent).
# @exitcode 2  Usage error.
# @exitcode 3  The main worktree entry is a bare repository — it owns no `.context/`.
#
# Minimum shell: bash 3.2+ (macOS default).

set -Eeuo pipefail

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | head -30
}

# Prints the physical git common dir on stdout and returns 0, or prints nothing and
# returns 1. Used only to prove "a repository is reachable from here" — the main
# worktree computation below never reads this value, so a submodule's common dir under
# `.git/modules/<name>` is never mistaken for a worktree root.
_cf_common_dir() {
  local raw=""
  raw=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || raw=""
  if [ -n "$raw" ]; then
    case "$raw" in
      /*)
        if [ -d "$raw" ]; then
          (cd "$raw" 2> /dev/null && pwd -P) && return 0
        fi
        ;;
    esac
  fi

  raw=$(git rev-parse --git-common-dir 2> /dev/null) || raw=""
  [ -n "$raw" ] || return 1

  case "$raw" in
    /*)
      [ -d "$raw" ] || return 1
      (cd "$raw" && pwd -P) && return 0
      return 1
      ;;
    *)
      if [ -d "$raw" ]; then
        (cd "$raw" && pwd -P) && return 0
        return 1
      fi
      local top=""
      top=$(git rev-parse --show-toplevel 2> /dev/null) || top=""
      if [ -n "$top" ] && [ -d "$top/$raw" ]; then
        (cd "$top/$raw" && pwd -P) && return 0
      fi
      return 1
      ;;
  esac
}

# Prints the physical path of the main worktree and returns 0; returns 1 when
# `git worktree list` yields nothing usable; returns 3 (nothing printed but a stderr
# note) when the first record is a bare repository.
_cf_main_worktree() {
  local out line path="" bare=0
  out=$(git worktree list --porcelain 2> /dev/null) || out=""
  [ -n "$out" ] || return 1

  # Only the FIRST record (up to its blank-line terminator) matters — later linked
  # worktrees have no bearing on which one is main.
  while IFS= read -r line; do
    case "$line" in
      "") break ;;
      worktree\ *) path="${line#worktree }" ;;
      bare) bare=1 ;;
    esac
  done <<EOF_WT
$out
EOF_WT

  [ -n "$path" ] || return 1

  if [ "$bare" -eq 1 ]; then
    printf >&2 'resolve-root.sh: main worktree is a bare repository — it owns no .context/\n'
    return 3
  fi

  [ -d "$path" ] || return 1
  (cd "$path" && pwd -P) && return 0
  return 1
}

_cf_self_test() {
  local tmp bare_tmp pass=0 fail=0
  tmp=$(mktemp -d) || { printf >&2 'resolve-root.sh --self-test: mktemp -d failed\n'; return 1; }
  bare_tmp=$(mktemp -d) || { rm -rf "$tmp"; printf >&2 'resolve-root.sh --self-test: mktemp -d failed\n'; return 1; }
  # mktemp -d can hand back a symlinked path (macOS /var -> /private/var); the script
  # under test always answers physically, so the fixture must compare physical to physical.
  tmp=$(cd "$tmp" && pwd -P)
  bare_tmp=$(cd "$bare_tmp" && pwd -P)
  # Values are expanded NOW, not at trap time: `tmp`/`bare_tmp` are function-locals and
  # would be gone by the time an EXIT trap fires after this function returns.
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}' '${bare_tmp}'" EXIT INT TERM

  local self
  self="$(cd "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")"

  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1

  # <label> <cwd> <want_out> <want_rc> [self-args...] — cds into cwd in a subshell so
  # neither this function's nor the caller's PWD ever moves.
  check() {
    local label="$1" cwd="$2" want_out="$3" want_rc="$4"; shift 4
    local out rc
    set +e
    out=$(cd "$cwd" && "$self" "$@" 2> /dev/null)
    rc=$?
    set -e
    if [ "$rc" -eq "$want_rc" ] && [ "$out" = "$want_out" ]; then
      printf '%s: ok\n' "$label"
      pass=$((pass + 1))
    else
      printf >&2 '%s: FAIL (rc=%s want_rc=%s out=%s want_out=%s)\n' "$label" "$rc" "$want_rc" "$out" "$want_out"
      fail=$((fail + 1))
    fi
  }

  local G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null)
  ( cd "$tmp" && "${G[@]}" init -q main ) > /dev/null
  ( cd "$tmp/main" && "${G[@]}" commit -q --allow-empty -m init ) > /dev/null
  ( cd "$tmp/main" && "${G[@]}" worktree add -q ../wt -b t ) > /dev/null
  mkdir -p "$tmp/main/a/b" "$tmp/wt/c/d"

  local ctx="$tmp/main/.context"
  local root="$tmp/main"

  export GIT_CEILING_DIRECTORIES="$tmp"
  check "main checkout" "$tmp/main" "$ctx" 0
  check "linked worktree" "$tmp/wt" "$ctx" 0
  check "subdir of main" "$tmp/main/a/b" "$ctx" 0
  check "subdir of linked worktree" "$tmp/wt/c/d" "$ctx" 0
  check "--root from linked worktree" "$tmp/wt" "$root" 0 --root

  mkdir -p "$tmp/outside"
  check "outside any repo" "$tmp/outside" "" 1

  ( cd "$bare_tmp" && "${G[@]}" init -q --bare bare.git ) > /dev/null
  ( cd "$bare_tmp" && "${G[@]}" -C bare.git worktree add -q ../bw -b b ) > /dev/null
  export GIT_CEILING_DIRECTORIES="$bare_tmp"
  check "bare main worktree" "$bare_tmp/bare.git" "" 3

  check "usage error" "$tmp" "" 2 --bogus

  printf 'resolve-root.sh --self-test: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

main() {
  local mode="ctx"
  case "${1:-}" in
    "") : ;;
    --root) mode="root"; shift ;;
    --self-test) _cf_self_test; exit $? ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac

  if [ "$#" -gt 0 ]; then
    usage >&2
    exit 2
  fi

  _cf_common_dir > /dev/null || exit 1

  local main_wt="" rc=0
  if main_wt=$(_cf_main_worktree); then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 3 ]; then
    exit 3
  fi
  if [ "$rc" -ne 0 ] || [ -z "$main_wt" ]; then
    exit 1
  fi

  if [ "$mode" = "root" ]; then
    printf '%s\n' "$main_wt"
  else
    printf '%s\n' "$main_wt/.context"
  fi
}

main "$@"
