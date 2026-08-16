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

# ---------------------------------------------------------------------------
# Self-test — temp git repo, no network, no external deps
# ---------------------------------------------------------------------------
run_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  local script="${BASH_SOURCE[0]}"
  local G=(git -C "$tmpdir")
  "${G[@]}" init -q
  "${G[@]}" config user.email "test@example.com"
  "${G[@]}" config user.name "Test"
  "${G[@]}" commit -q --allow-empty -m "chore: init"
  "${G[@]}" tag v0.0.0

  local fail=0

  # expect_bump <expected> <label> <args...>
  expect_bump() {
    local expected="$1" label="$2"
    shift 2
    local got
    got="$(bash "$script" "$@" 2> /dev/null)" || {
      printf >&2 'FAIL: %s — exited non-zero\n' "$label"
      fail=1
      return 0
    }
    if [[ "$got" != "$expected" ]]; then
      printf >&2 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$got"
      fail=1
    fi
  }

  # from_subjects <expected> <label> <subject>...
  from_subjects() {
    local expected="$1" label="$2"
    shift 2
    local f="$tmpdir/subjects.$$.txt"
    printf '%s\n' "$@" > "$f"
    expect_bump "$expected" "$label" --file "$f"
    rm -f "$f"
  }

  # --- aggregation: highest severity wins, not last-commit-wins ---
  from_subjects minor "mixed 3x fix + 1x feat" \
    "fix: one" "fix: two" "feat: add thing" "fix: three"
  from_subjects patch "fix-only range" "fix: one" "fix: two"
  from_subjects none "silent types only" \
    "docs: readme" "chore: deps" "test: coverage" "ci: pipeline"
  from_subjects patch "refactor and perf are patch" \
    "refactor: tidy" "perf: cache"

  # --- breaking is independent of commit type ---
  from_subjects major "header ! on feat" "fix: one" "feat!: drop v1"
  from_subjects major "header ! on fix" "fix!: change return type"
  from_subjects none "non-conventional alone does not bump" \
    "Merge branch 'main'" "wip"

  # --- footer form, which needs a multi-line record ---
  local nulfile="$tmpdir/records.bin"
  printf 'chore: retire the shim\n\nBREAKING CHANGE: callers must migrate.\n\0' \
    > "$nulfile"
  expect_bump major "BREAKING CHANGE footer on chore" --file "$nulfile"

  printf 'feat: add thing\n\nbut this is a breaking change: not really\n\0' \
    > "$nulfile"
  expect_bump minor "lowercase prose is not a footer" --file "$nulfile"

  # --- git range: empty, single-commit, and mixed ---
  expect_bump none "empty range" "HEAD..HEAD" --repo "$tmpdir"

  "${G[@]}" commit -q --allow-empty -m "fix: single commit range"
  expect_bump patch "single-commit range" "v0.0.0..HEAD" --repo "$tmpdir"

  "${G[@]}" commit -q --allow-empty -m "feat(api): add endpoint"
  "${G[@]}" commit -q --allow-empty -m "docs: mention it"
  expect_bump minor "multi-commit range aggregates" "v0.0.0..HEAD" --repo "$tmpdir"

  "${G[@]}" commit -q --allow-empty \
    -m "chore: retire shim" -m "BREAKING CHANGE: callers must migrate."
  expect_bump major "footer via real git range" "v0.0.0..HEAD" --repo "$tmpdir"

  # --- the two scripts must agree on which commits are breaking ---
  local changelog cl_out
  changelog="$(dirname "$script")/changelog-from-git.sh"
  cl_out="$(bash "$changelog" "v0.0.0..HEAD" --repo "$tmpdir" 2> /dev/null)"
  if ! grep -q 'BREAKING' <<< "$cl_out"; then
    printf >&2 'FAIL: bump says major but changelog marked nothing BREAKING\n'
    fail=1
  fi

  # --- usage errors ---
  if bash "$script" > /dev/null 2>&1; then
    printf >&2 'FAIL: no range and no --file should exit 1\n'
    fail=1
  fi
  if bash "$script" --file "/tmp/does-not-exist-xy12" > /dev/null 2>&1; then
    printf >&2 'FAIL: unreadable --file should exit 1\n'
    fail=1
  fi

  rm -rf "$tmpdir"
  trap - EXIT

  if [[ "$fail" -eq 0 ]]; then
    printf 'self-test: PASS\n'
    exit 0
  fi
  printf >&2 'self-test: FAIL\n'
  exit 1
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
      --self-test) run_self_test ;;
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
