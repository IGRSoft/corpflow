#!/usr/bin/env bash
# @description Generate a Keep-a-Changelog markdown section from a git commit range.
#              Classifies commits by all 10 conventional-commit types; non-conventional
#              commits are bucketed under "Other" (never dropped).
#              Compatible with Bash 3.2+ (macOS system bash).
# @arg $1  Git range, e.g. "v1.1.0..HEAD" or "abc123..def456" (required unless --self-test/--file)
# @arg --version VERSION  Version label for the section header (default: Unreleased)
# @arg --date DATE        Date string for the section header (default: today, YYYY-MM-DD)
# @arg --file PATH        Read pre-fetched commit subjects from a file (one per line)
# @arg --repo PATH        Path to git repo (default: current directory)
# @arg --self-test        Run built-in tests against a temp repo (no network)
# @exitcode 0  Success — markdown written to stdout
# @exitcode 1  Usage error or git failure
set -Eeuo pipefail
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

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
# classify_type <type_lowercase> <breaking_flag>
# Prints the KCL section name, or empty string for silent types.
# ---------------------------------------------------------------------------
classify_type() {
  local type="$1"
  case "$type" in
    feat) printf 'Added' ;;
    fix) printf 'Fixed' ;;
    refactor | perf) printf 'Changed' ;;
    docs | style | test | chore | ci | build) printf '' ;; # suppress
    *) printf 'Other' ;;
  esac
}

# ---------------------------------------------------------------------------
# parse_and_bucket <subject_line>
# Parses one commit subject and appends to the appropriate section bucket.
# Silently skips blank/whitespace-only subjects.
# ---------------------------------------------------------------------------
parse_and_bucket() {
  local raw="$1"

  # Strip leading/trailing whitespace
  local subj
  subj="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$subj" ]] && return 0

  # Match conventional-commit prefix: type[(scope)][!]: description
  # Variable holds regex to satisfy shellcheck SC2221 for [[ =~ ]]
  local cc_re='^([a-zA-Z]+)(\([^)]*\))?(!)?: '
  local type scope breaking desc entry section

  if [[ "$subj" =~ $cc_re ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[2]}" # may be empty
    breaking=0
    [[ "${BASH_REMATCH[3]}" == "!" ]] && breaking=1

    # Extract description: everything after the matched prefix
    local prefix_len="${#BASH_REMATCH[0]}"
    desc="${subj:$prefix_len}"
    desc="$(printf '%s' "$desc" | sed 's/^[[:space:]]*//')"

    # Lowercase type — use tr for Bash 3.2 compat (no ${var,,})
    type="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"

    section="$(classify_type "$type" "$breaking")"
    [[ -z "$section" ]] && return 0 # silent type — suppress

    # Build entry text: bold scope if present; BREAKING prefix if applicable
    if [[ -n "$scope" ]]; then
      local scope_label="${scope:1:${#scope}-2}" # strip parens
      if [[ "$breaking" == "1" ]]; then
        entry="**BREAKING** **${scope_label}**: ${desc}"
      else
        entry="**${scope_label}**: ${desc}"
      fi
    else
      if [[ "$breaking" == "1" ]]; then
        entry="**BREAKING**: ${desc}"
      else
        entry="${desc}"
      fi
    fi
  else
    # Non-conventional commit — bucket under Other (never dropped)
    section="Other"
    entry="$subj"
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
  --file PATH        Read commit subjects from file (one per line) instead of git.
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

  # Collect commit subjects
  local subjects_raw=""

  if [[ -n "$input_file" ]]; then
    if [[ ! -r "$input_file" ]]; then
      printf >&2 'error: cannot read file: %s\n' "$input_file"
      exit 1
    fi
    subjects_raw="$(cat -- "$input_file")"
  else
    # Validate range — allow only chars safe in git revision specs
    if [[ ! "$range" =~ ^[a-zA-Z0-9_.^~/@{}-]+(\.\.[a-zA-Z0-9_.^~/@{}-]+)?$ ]]; then
      printf >&2 'error: git range contains unsafe characters: %s\n' "$range"
      exit 1
    fi
    if [[ -n "$repo_path" ]]; then
      subjects_raw="$(git -C "$repo_path" log "$range" --pretty=format:'%s' --)"
    else
      subjects_raw="$(git log "$range" --pretty=format:'%s' --)"
    fi
  fi

  # Parse and classify each subject line into section buckets
  while IFS= read -r subj; do
    parse_and_bucket "$subj"
  done <<< "$subjects_raw"

  render_sections "$version" "$date"
}

main "$@"
