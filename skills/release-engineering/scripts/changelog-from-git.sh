#!/usr/bin/env bash
# @description Generate a Keep-a-Changelog markdown section from a git commit range.
#              Classifies commits by all 10 conventional-commit types; non-conventional
#              commits are bucketed under "Other" (never dropped).
#              Compatible with Bash 3.2+ (macOS system bash).
# @arg $1  Git range, e.g. "v1.1.0..HEAD" or "abc123..def456" (required unless --self-test/--file)
# @arg --version VERSION  Version label for the section header (default: Unreleased)
# @arg --date DATE        Date string for the section header (default: today, YYYY-MM-DD)
# @arg --file PATH        Read pre-fetched commits from a file: NUL-separated whole
#                         messages, or one subject per line when it contains no NUL
# @arg --repo PATH        Path to git repo (default: current directory)
# @arg --self-test        Run built-in tests against a temp repo (no network)
# @exitcode 0  Success — markdown written to stdout
# @exitcode 1  Usage error or git failure
set -Eeuo pipefail
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# Commit parsing is shared with version-bump-from-git.sh so the two cannot
# disagree about which commits are breaking. A missing same-commit sibling means
# a broken install; `[ -r ]` first because `.` on a missing file is a special-
# builtin error that exits before any `if ! .` guard can run.
_CC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/conventional-commits-lib.sh"
if [ -r "$_CC_LIB" ]; then
  # shellcheck source=conventional-commits-lib.sh
  # shellcheck disable=SC1090
  . "$_CC_LIB"
else
  printf >&2 'changelog-from-git: helper library unreachable at %s — plugin install broken\n' \
    "$_CC_LIB"
  exit 1
fi

# ---------------------------------------------------------------------------
# Keep-a-Changelog section order — determines output ordering.
# Section content is accumulated in per-section temp files (_BUCKET_DIR).
# ---------------------------------------------------------------------------
_SECTIONS=("Added" "Changed" "Deprecated" "Removed" "Fixed" "Security" "Other")
_BUCKET_DIR=""

# ---------------------------------------------------------------------------
# init_buckets — create temp dir for section files; register EXIT cleanup.
# Must be called once before any parse_and_bucket calls.
# ---------------------------------------------------------------------------
init_buckets() {
  _BUCKET_DIR="$(mktemp -d)"
  # shellcheck disable=SC2064  # we intentionally expand _BUCKET_DIR now
  trap "rm -rf '${_BUCKET_DIR}'" EXIT
  local s
  for s in "${_SECTIONS[@]}"; do
    : > "${_BUCKET_DIR}/${s}"
  done
}

# ---------------------------------------------------------------------------
# section_append <section_name> <entry>
# Appends a single entry line to the named section file.
# No eval — entry text is passed as an argument and written with printf.
# ---------------------------------------------------------------------------
section_append() {
  local name="$1"
  local entry="$2"
  printf '%s\n' "$entry" >> "${_BUCKET_DIR}/${name}"
}

# ---------------------------------------------------------------------------
# parse_and_bucket <commit_message>
# Buckets one commit. Only its subject becomes the entry text; the body is read
# solely for a BREAKING CHANGE footer. Blank messages are skipped.
# ---------------------------------------------------------------------------
parse_and_bucket() {
  local raw="$1"
  local entry section

  if ! cc_parse "$raw"; then
    return 0
  fi

  if [[ "$CC_CONVENTIONAL" != "1" ]]; then
    section_append "Other" "$CC_SUBJECT"
    return 0
  fi

  section="$(cc_classify_section "$CC_TYPE" "$CC_BREAKING")"
  if [[ -z "$section" ]]; then
    return 0 # silent type
  fi

  local prefix=""
  if [[ "$CC_BREAKING" == "1" ]]; then
    prefix="**BREAKING**"
  fi

  if [[ -n "$CC_SCOPE" ]]; then
    if [[ -n "$prefix" ]]; then
      entry="${prefix} **${CC_SCOPE}**: ${CC_DESC}"
    else
      entry="**${CC_SCOPE}**: ${CC_DESC}"
    fi
  else
    if [[ -n "$prefix" ]]; then
      entry="${prefix}: ${CC_DESC}"
    else
      entry="${CC_DESC}"
    fi
  fi

  section_append "$section" "$entry"
}

# ---------------------------------------------------------------------------
# render_sections <version> <date>
# Writes Keep-a-Changelog markdown to stdout from the current bucket files.
# ---------------------------------------------------------------------------
render_sections() {
  local version="$1" date="$2"

  if [[ "$version" == "Unreleased" ]]; then
    printf '## [Unreleased]\n'
  else
    printf '## [%s] - %s\n' "$version" "$date"
  fi

  local has_content=0
  local section bucket entry
  for section in "${_SECTIONS[@]}"; do
    bucket="${_BUCKET_DIR}/${section}"
    # Skip empty bucket files
    [[ -s "$bucket" ]] || continue
    has_content=1
    printf '\n### %s\n' "$section"
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      printf '%s\n' "- ${entry}"
    done < "$bucket"
  done

  if [[ "$has_content" -eq 0 ]]; then
    printf '\n_(no changelog-worthy commits in this range)_\n'
  fi
}

# ---------------------------------------------------------------------------
# Self-test — spins up a temp git repo, no network, no external deps
# ---------------------------------------------------------------------------
run_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Note: EXIT trap is registered by init_buckets; we add our own cleanup here
  # by nesting inside a subshell so the outer EXIT trap is not clobbered.
  # We use a flag + explicit cleanup instead.
  local test_cleanup_done=0
  trap '
    [[ "$test_cleanup_done" -eq 0 ]] && rm -rf "$tmpdir"
    test_cleanup_done=1
  ' EXIT

  local script="${BASH_SOURCE[0]}"

  # Init repo
  git -C "$tmpdir" init -q
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"

  # Base commit + tag to form the lower bound of our range
  git -C "$tmpdir" commit -q --allow-empty -m "chore: init"
  git -C "$tmpdir" tag v0.0.0

  # Seed all 10 conventional types + a breaking feat + a non-conventional commit
  git -C "$tmpdir" commit -q --allow-empty -m "feat(auth): add OAuth2 login"
  git -C "$tmpdir" commit -q --allow-empty -m "fix: resolve crash on empty input"
  git -C "$tmpdir" commit -q --allow-empty -m "docs: update README"
  git -C "$tmpdir" commit -q --allow-empty -m "style: reformat with prettier"
  git -C "$tmpdir" commit -q --allow-empty -m "refactor(api): extract helper module"
  git -C "$tmpdir" commit -q --allow-empty -m "perf: cache DB results"
  git -C "$tmpdir" commit -q --allow-empty -m "test: add unit tests for parser"
  git -C "$tmpdir" commit -q --allow-empty -m "chore: bump dependency versions"
  git -C "$tmpdir" commit -q --allow-empty -m "ci: update GitHub Actions workflow"
  git -C "$tmpdir" commit -q --allow-empty -m "build: switch to esbuild"
  git -C "$tmpdir" commit -q --allow-empty -m "feat!: remove legacy v1 endpoints"
  git -C "$tmpdir" commit -q --allow-empty \
    -m "fix: drop the compat shim" -m "BREAKING CHANGE: callers must migrate."
  git -C "$tmpdir" commit -q --allow-empty \
    -m "chore: retire the shim" -m "BREAKING CHANGE: callers must migrate."
  git -C "$tmpdir" commit -q --allow-empty -m "Non-conventional commit message"

  local fail=0

  # --- Test 1: standard range run via --repo ---
  local output
  output="$(bash "$script" "v0.0.0..HEAD" --repo "$tmpdir" --version "1.0.0" --date "2024-01-15" 2> /dev/null)"

  grep -q 'auth.*OAuth2 login' <<< "$output" || {
    printf >&2 'FAIL: feat(auth) not in Added\n'
    fail=1
  }
  grep -q 'BREAKING.*legacy v1 endpoints' <<< "$output" || {
    printf >&2 'FAIL: breaking feat! not marked BREAKING\n'
    fail=1
  }
  grep -q 'crash on empty input' <<< "$output" || {
    printf >&2 'FAIL: fix not in Fixed\n'
    fail=1
  }
  grep -q 'BREAKING.*drop the compat shim' <<< "$output" || {
    printf >&2 'FAIL: BREAKING CHANGE footer not marked BREAKING\n'
    fail=1
  }
  grep -q 'BREAKING.*retire the shim' <<< "$output" || {
    printf >&2 'FAIL: breaking commit of a silent type was suppressed\n'
    fail=1
  }
  grep -q 'extract helper module' <<< "$output" || {
    printf >&2 'FAIL: refactor not in Changed\n'
    fail=1
  }
  grep -q 'cache DB results' <<< "$output" || {
    printf >&2 'FAIL: perf not in Changed\n'
    fail=1
  }
  local suppressed
  for suppressed in "update README" "reformat with prettier" "add unit tests" \
    "bump dependency" "update GitHub Actions" "switch to esbuild"; do
    if grep -q "$suppressed" <<< "$output"; then
      printf >&2 'FAIL: suppressed type appeared in output: %s\n' "$suppressed"
      fail=1
    fi
  done
  grep -q 'Non-conventional commit message' <<< "$output" || {
    printf >&2 'FAIL: non-conventional commit dropped (should be Other)\n'
    fail=1
  }
  grep -q '\[1\.0\.0\].*2024-01-15' <<< "$output" || {
    printf >&2 'FAIL: version header not found\n'
    fail=1
  }

  # --- Test 2: empty range emits "no changelog-worthy" notice ---
  local empty_out
  empty_out="$(bash "$script" "HEAD..HEAD" --repo "$tmpdir" 2> /dev/null)"
  grep -q 'no changelog-worthy' <<< "$empty_out" || {
    printf >&2 'FAIL: empty range did not emit no-content notice\n'
    fail=1
  }

  # --- Test 3: --file bypasses git entirely; blank lines are skipped ---
  local subjects_file="$tmpdir/subjects.txt"
  printf '%s\n' "feat: from file entry" "   " "" "fix: also from file" > "$subjects_file"
  local file_out
  file_out="$(bash "$script" --file "$subjects_file" 2> /dev/null)"
  grep -q 'from file entry' <<< "$file_out" || {
    printf >&2 'FAIL: --file feat not in Added\n'
    fail=1
  }
  grep -q 'also from file' <<< "$file_out" || {
    printf >&2 'FAIL: --file fix not in Fixed\n'
    fail=1
  }

  # --- Test 4: uppercase type normalised; scope parentheses stripped ---
  local scope_file="$tmpdir/scope.txt"
  printf '%s\n' "FEAT(dashboard): uppercase type" > "$scope_file"
  local scope_out
  scope_out="$(bash "$script" --file "$scope_file" 2> /dev/null)"
  grep -q 'dashboard.*uppercase type' <<< "$scope_out" || {
    printf >&2 'FAIL: uppercase type or scope not handled\n'
    fail=1
  }

  test_cleanup_done=1
  rm -rf "$tmpdir"

  if [[ "$fail" -eq 0 ]]; then
    printf 'self-test: PASS\n'
    exit 0
  else
    printf >&2 'self-test: FAIL\n'
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat >&2 << USAGE
Usage: changelog-from-git.sh [--repo PATH] <git-range> [--version V] [--date D]
       changelog-from-git.sh --file PATH [--version V] [--date D]
       changelog-from-git.sh --self-test

Options:
  <git-range>        Git log range (e.g. v1.1.0..HEAD). Required unless --file given.
  --repo PATH        Path to git repository (default: current directory).
  --version VERSION  Version label for section header.  Default: Unreleased
  --date DATE        Date for section header (YYYY-MM-DD).  Default: today
  --file PATH        Read commits from file instead of git: NUL-separated whole
                     messages, or one subject per line if it holds no NUL.
  --self-test        Run built-in tests against a temp repo (no network).

Output: Keep-a-Changelog markdown section written to stdout.
USAGE
  exit 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local range="" version="Unreleased" date="" input_file="" repo_path=""

  date="$(date +%Y-%m-%d)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-test)
        run_self_test
        ;;
      --version)
        [[ $# -lt 2 ]] && usage
        version="$2"
        shift 2
        ;;
      --date)
        [[ $# -lt 2 ]] && usage
        date="$2"
        shift 2
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
      --help | -h)
        usage
        ;;
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

  # Validate
  if [[ -z "$input_file" && -z "$range" ]]; then
    printf >&2 'error: git range required (or --file)\n'
    usage
  fi

  # Initialise section buckets (temp files; EXIT trap wired inside)
  init_buckets

  # Staged through a file so a git or read failure aborts here; a process
  # substitution would swallow it and render an empty-but-successful changelog.
  local records="${_BUCKET_DIR}/.records"
  cc_collect_records "$range" "$repo_path" "$input_file" > "$records"

  local msg
  while IFS= read -r -d '' msg || [[ -n "$msg" ]]; do
    parse_and_bucket "$msg"
  done < "$records"

  render_sections "$version" "$date"
}

main "$@"
