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
        # Sourced HERE, not at the top: the harness is test code the production path
        # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
        # `.` builtin is a special-builtin error that exits the shell immediately,
        # bypassing an `if ! . …` guard entirely.
        SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/changelog-from-git-selftest.sh"
        if [ -r "$SELFTEST_LIB_PATH" ]; then
          # shellcheck source=changelog-from-git-selftest.sh
          # shellcheck disable=SC1090
          . "$SELFTEST_LIB_PATH"
        else
          printf >&2 'changelog-from-git: self-test harness unreachable at %s — plugin install broken\n' \
            "$SELFTEST_LIB_PATH"
          exit 2
        fi
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
