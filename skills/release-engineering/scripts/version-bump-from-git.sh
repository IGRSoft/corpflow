#!/usr/bin/env bash
# @description Determine the SemVer bump a git commit range requires.
#              Aggregates by highest severity: any breaking commit wins the
#              range, else any feat, else any fix/refactor/perf.
#              Compatible with Bash 3.2+ (macOS system bash).
# @arg $1  Git range, e.g. "v1.1.0..HEAD" (required unless --self-test/--file)
# @arg --repo PATH        Path to git repo (default: current directory)
# @arg --file PATH        Read pre-fetched commits from a file: NUL-separated whole
#                         messages, or one subject per line when it contains no NUL
# @arg --explain          Write the per-commit breakdown to stderr
# @arg --self-test        Run built-in tests against a temp repo (no network)
# @exitcode 0  Success — one of major|minor|patch|none written to stdout
# @exitcode 1  Usage error or git failure
set -Eeuo pipefail
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# A missing same-commit sibling means a broken install; `[ -r ]` first because
# `.` on a missing file exits before any `if ! .` guard can run.
_CC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/conventional-commits-lib.sh"
if [ -r "$_CC_LIB" ]; then
  # shellcheck source=conventional-commits-lib.sh
  # shellcheck disable=SC1090
  . "$_CC_LIB"
else
  printf >&2 'version-bump-from-git: helper library unreachable at %s — plugin install broken\n' \
    "$_CC_LIB"
  exit 1
fi

# ---------------------------------------------------------------------------
# aggregate_bump <records-file> <explain-flag>
# Prints the range's bump. `none` is a successful verdict, not an error: a
# docs-and-chore-only range legitimately releases nothing.
# ---------------------------------------------------------------------------
aggregate_bump() {
  local records="$1" explain="$2"
  local result="none" msg commit_bump

  while IFS= read -r -d '' msg || [[ -n "$msg" ]]; do
    if ! cc_parse "$msg"; then
      continue
    fi
    commit_bump="$(cc_bump_for "$CC_TYPE" "$CC_BREAKING")"
    result="$(cc_bump_max "$result" "$commit_bump")"
    if [[ "$explain" == "1" ]]; then
      printf >&2 '%-6s %s\n' "$commit_bump" "$CC_SUBJECT"
    fi
  done < "$records"

  printf '%s' "$result"
}

usage() {
  cat >&2 << USAGE
Usage: version-bump-from-git.sh [--repo PATH] <git-range> [--explain]
       version-bump-from-git.sh --file PATH [--explain]
       version-bump-from-git.sh --self-test

Options:
  <git-range>   Git log range (e.g. v1.1.0..HEAD). Required unless --file given.
  --repo PATH   Path to git repository (default: current directory).
  --file PATH   Read commits from file instead of git: NUL-separated whole
                messages, or one subject per line if it holds no NUL.
  --explain     Write the per-commit bump breakdown to stderr.
  --self-test   Run built-in tests against a temp repo (no network).

Output: one of major|minor|patch|none on stdout. \`none\` means the range
contains nothing release-worthy — it is a success, not an error.
USAGE
  exit 1
}

main() {
  local range="" input_file="" repo_path="" explain=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-test)
        # Sourced HERE, not at the top: the harness is test code the production path
        # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
        # `.` builtin is a special-builtin error that exits the shell immediately,
        # bypassing an `if ! . …` guard entirely.
        SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/version-bump-from-git-selftest.sh"
        if [ -r "$SELFTEST_LIB_PATH" ]; then
          # shellcheck source=version-bump-from-git-selftest.sh
          # shellcheck disable=SC1090
          . "$SELFTEST_LIB_PATH"
        else
          printf >&2 'version-bump-from-git: self-test harness unreachable at %s — plugin install broken\n' \
            "$SELFTEST_LIB_PATH"
          exit 2
        fi
        run_self_test
        ;;
      --explain)
        explain=1
        shift
        ;;
      --file)
        [[ $# -lt 2 ]] && usage
        input_file="$2"
        shift 2
        ;;
      --repo)
        [[ $# -lt 2 ]] && usage
        repo_path="$2"
        shift 2
        ;;
      --help | -h) usage ;;
      --)
        shift
        break
        ;;
      -*)
        printf >&2 'Unknown option: %s\n' "$1"
        usage
        ;;
      *)
        if [[ -z "$range" ]]; then
          range="$1"
          shift
        else
          printf >&2 'Unexpected argument: %s\n' "$1"
          usage
        fi
        ;;
    esac
  done

  if [[ -z "$input_file" && -z "$range" ]]; then
    printf >&2 'error: git range required (or --file)\n'
    usage
  fi

  local workdir
  workdir="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand workdir now, not at trap time
  trap "rm -rf '${workdir}'" EXIT

  # Staged through a file so a git or read failure aborts here; a process
  # substitution would swallow it and report a confident `none`.
  local records="${workdir}/records"
  cc_collect_records "$range" "$repo_path" "$input_file" > "$records"

  printf '%s\n' "$(aggregate_bump "$records" "$explain")"
}

main "$@"
