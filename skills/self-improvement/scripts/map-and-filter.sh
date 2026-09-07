#!/usr/bin/env bash
# @file        map-and-filter.sh
# @description Step 4 of the self-improvement pipeline.
#              Reads a change table (path\tlines_added\tlines_removed) and applies
#              the 17-rule path-pattern->target mapping from target-mapping.md,
#              then filters against the used-in-context set produced by
#              build-context-set.sh.
#
#              Emits one TSV row per KEPT change:
#                <path>\t<rule_num>\t<target>\t<lines_added>\t<lines_removed>
#
#              Discarded rows are logged to LOG_OUT under
#              "## Out-of-Context Discards".
#
# @usage       map-and-filter.sh [options]
#
# @arg --changes=<file>     TSV produced by detect-user-changes.sh
#                           (default: read from stdin)
# @arg --context-set=<file> File listing in-context paths (one per line),
#                           produced by build-context-set.sh (required unless
#                           --self-test)
# @arg --dv-agent=<path>    Resolved DV agent path for rules 5,13,16
#                           e.g. "agents/developer.md"  (optional;
#                           defaults to "agents/developer.md")
# @arg --self-test          Run internal test suite; exit 0/non-zero
#
# @env LOG_OUT              Path to the run-log file (append only).
#                           Required unless --self-test.
#
# @exitcode 0  success (zero or more kept rows)
# @exitcode 1  usage/environment error
# @exitcode 2  self-test failure
#
# @requires    bash >=3.2  (portable; no associative arrays used)
# @min_shell   bash 3.2 (macOS system bash compatible)
#
# Platform: Linux + macOS (Darwin). No GNU-only flags used.
# NOTE: uses grep for in-context lookup to avoid bash 4.0+ associative arrays.

set -Eeuo pipefail
IFS=$'\n\t'

trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  printf >&2 'usage: %s [--changes=<file>] --context-set=<file> [--dv-agent=<path>] [--self-test]\n' \
    "${BASH_SOURCE[0]}"
  exit 1
}

# log_discard <path> <reason>
log_discard() {
  if [ -n "${LOG_OUT:-}" ]; then
    # Use %s for the leading dash to avoid bash 3.2 printf treating '-' as a flag.
    printf '%s DISCARD %s  reason: %s\n' "-" "$1" "$2" >> "$LOG_OUT"
  fi
}

# in_context_set <target> <context_set_file>
# Returns 0 if target is in the set, 1 otherwise.
# Uses grep -Fxq for exact whole-line match; portable on bash 3.2 + macOS.
in_context_set() {
  local target="$1"
  local set_file="$2"
  grep -Fxq -- "$target" "$set_file" 2> /dev/null
}

# ---------------------------------------------------------------------------
# Mapping engine — apply the 17 rules from target-mapping.md
# Returns via stdout: "<rule_num>\t<target>"  or  "17\tDISCARD"
#
# $1 = changed file path
# $2 = dv_agent path (e.g. "agents/developer.md")
# ---------------------------------------------------------------------------
map_path() {
  local p="$1"
  local dv_agent="$2"

  # Rule 1 — direct edit to a prompt file
  # agents/*.md  |  commands/*.md  |  skills/<any depth>/SKILL.md
  case "$p" in
    agents/*.md | commands/*.md)
      printf '1\t%s\n' "$p"
      return 0
      ;;
  esac
  # Catch skills/<name>/SKILL.md (one level deep).
  case "$p" in
    skills/*/SKILL.md)
      printf '1\t%s\n' "$p"
      return 0
      ;;
  esac
  # Catch skills/<plugin>/<name>/SKILL.md (two levels deep).
  # Separate case statement avoids SC2221/SC2222 false-positive for | alternatives.
  case "$p" in
    skills/*/*/SKILL.md)
      printf '1\t%s\n' "$p"
      return 0
      ;;
  esac
  # Source 4 of build-context-set.sh enters hooks and helpers into the context set under
  # exactly these shapes, so the in-context join needs a rule emitting them as a target.
  # Test-shaped names fall through to rule 15, which owns them.
  case "$p" in
    *_test.sh | *.bats) ;;
    hooks/*.sh | scripts/*.sh | skills/*/scripts/*.sh)
      printf '1\t%s\n' "$p"
      return 0
      ;;
  esac

  # Rule 2 — planning artifact
  case "$p" in
    .context/planning-*.md)
      printf '2\tagents/product-manager.md\n'
      return 0
      ;;
  esac

  # Rule 3 — architecture artifact
  case "$p" in
    .context/architecture-*.md)
      printf '3\tagents/software-architector.md\n'
      return 0
      ;;
  esac

  # Rule 4 — coordination artifact
  case "$p" in
    .context/coordination-*.md)
      printf '4\tagents/team-lead.md\n'
      return 0
      ;;
  esac

  # Rule 5 — development artifact (platform-aware DV agent)
  case "$p" in
    .context/development-*.md)
      printf '5\t%s\n' "$dv_agent"
      return 0
      ;;
  esac

  # Rule 6 — developer-review artifact
  case "$p" in
    .context/developer-review-*.md)
      printf '6\tagents/technical-lead.md\n'
      return 0
      ;;
  esac

  # Rule 7 — security-review artifact
  case "$p" in
    .context/security-review-*.md)
      printf '7\tagents/security-reviewer.md\n'
      return 0
      ;;
  esac

  # Rule 8 — testing artifact
  case "$p" in
    .context/testing-*.md)
      printf '8\tagents/qa-engineer.md\n'
      return 0
      ;;
  esac

  # Rule 9 — documentation artifact
  case "$p" in
    .context/documentation-*.md)
      printf '9\tagents/technical-writer.md\n'
      return 0
      ;;
  esac

  # Rule 10 — release artifact
  case "$p" in
    .context/release-*.md)
      printf '10\tagents/release-engineer.md\n'
      return 0
      ;;
  esac

  # Rule 11 — complete-summary artifact
  case "$p" in
    .context/complete-summary-*.md)
      printf '11\tagents/project-manager.md\n'
      return 0
      ;;
  esac

  # Rule 12 — retrospective artifact (ST self-signal)
  case "$p" in
    .context/retrospective-*.md)
      printf '12\tagents/stakeholder.md\n'
      return 0
      ;;
  esac

  # Rule 13 — source code
  case "$p" in
    src/* | app/* | lib/* | Sources/*)
      printf '13\t%s\n' "$dv_agent"
      return 0
      ;;
  esac

  # Rule 14 — docs / root markdown
  # README.md and docs/** map to technical-writer.
  # Root-level *.md (no slash) also maps here.
  case "$p" in
    README.md)
      printf '14\tagents/technical-writer.md\n'
      return 0
      ;;
    docs/*)
      printf '14\tagents/technical-writer.md\n'
      return 0
      ;;
  esac
  # Root-level *.md that is not already matched by rule 1 (agents/commands/skills)
  case "$p" in
    *.md)
      case "$p" in
        */*)
          # Nested .md not matched by earlier rules -> fall through to rule 17
          ;;
        *)
          printf '14\tagents/technical-writer.md\n'
          return 0
          ;;
      esac
      ;;
  esac

  # Rule 15 — tests
  # Naming conventions are per-ecosystem, so the patterns have to be too: a
  # Kotlin, TS, Go or Rust test file matched none of these and fell through to
  # rule 17 DISCARD, dropping the QA signal it should have produced.
  case "$p" in
    tests/* | spec/* | test/*)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
    *Tests.swift | *Test.swift)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
    *_test.py | test_*.py)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
    *Test.kt | *Tests.kt | *Spec.kt | *Test.java | *Tests.java)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
    *.test.ts | *.test.tsx | *.test.js | *.test.jsx)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
    *.spec.ts | *.spec.tsx | *.spec.js | *.spec.jsx)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
    *_test.go | *_test.rs | *_test.sh | *.bats)
      printf '15\tagents/qa-engineer.md\n'
      return 0
      ;;
  esac

  # Rule 16 — config; special-case plugin.json
  # Manifests and lockfiles across the stacks we build for; Package.swift was
  # the only one named, so a gradle/go/cargo build change read as unclassified.
  case "$p" in
    plugin.json)
      printf '16\tagents/workflow-engineer.md\n'
      return 0
      ;;
    *.json | *.toml | *.yml | *.yaml | *.ini | *.cfg | *.properties)
      printf '16\t%s\n' "$dv_agent"
      return 0
      ;;
    Makefile | CMakeLists.txt | *.cmake | Dockerfile)
      printf '16\t%s\n' "$dv_agent"
      return 0
      ;;
    Package.swift | Package.resolved | Podfile | *.podspec)
      printf '16\t%s\n' "$dv_agent"
      return 0
      ;;
    *.gradle | *.gradle.kts)
      printf '16\t%s\n' "$dv_agent"
      return 0
      ;;
    go.mod | go.sum | Cargo.lock | pom.xml | Gemfile | Gemfile.lock)
      printf '16\t%s\n' "$dv_agent"
      return 0
      ;;
    setup.py | requirements.txt | requirements-*.txt)
      printf '16\t%s\n' "$dv_agent"
      return 0
      ;;
  esac

  # Rule 17 — no match
  printf '17\tDISCARD\n'
}

# ---------------------------------------------------------------------------
# Edge-case pre-filter (applied BEFORE rule mapping)
# Returns 0 to signal "discard immediately", 1 to continue.
#
# $1 = changed file path
# ---------------------------------------------------------------------------
should_discard_early() {
  local p="$1"

  # .context/logs and .context/errors are ephemeral
  case "$p" in
    .context/logs/* | .context/errors/*)
      return 0
      ;;
  esac

  # self-improvement files — avoid recursion
  case "$p" in
    skills/self-improvement/*)
      return 0
      ;;
  esac

  return 1
}

# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

run_main() {
  local changes_file=""
  local context_set_file=""
  local dv_agent="agents/developer.md"

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --changes=*) changes_file="${1#*=}" ;;
      --context-set=*) context_set_file="${1#*=}" ;;
      --dv-agent=*) dv_agent="${1#*=}" ;;
      --self-test)
        _source_selftest
        run_self_test
        exit $?
        ;;
      -h | --help) usage ;;
      *) usage ;;
    esac
    shift
  done

  if [ -z "$context_set_file" ]; then
    printf >&2 'error: --context-set=<file> is required\n'
    usage
  fi

  if [ ! -f "$context_set_file" ]; then
    printf >&2 'error: context-set file not found: %s\n' "$context_set_file"
    exit 1
  fi

  : "${LOG_OUT:?LOG_OUT env var required (path to run-log file)}"

  # Write discard section header to log (append)
  printf '\n## Out-of-Context Discards\n' >> "$LOG_OUT"

  # Process each row from the changes table (stdin or file)
  local input
  if [ -n "$changes_file" ]; then
    input="$changes_file"
  else
    # Read stdin to temp file so we can iterate
    local tmp_in
    tmp_in="$(mktemp)"
    trap 'rm -f "$tmp_in"' EXIT
    cat > "$tmp_in"
    input="$tmp_in"
  fi

  local path added removed mapping rule_num target
  while IFS=$'\t' read -r path added removed || [ -n "$path" ]; do
    [ -z "$path" ] && continue

    # Edge-case pre-filter
    if should_discard_early "$path"; then
      log_discard "$path" "early-filter (logs/errors/self-improvement)"
      continue
    fi

    # Apply mapping rules
    mapping="$(map_path "$path" "$dv_agent")"
    rule_num="${mapping%%	*}"
    target="${mapping#*	}"

    if [ "$target" = "DISCARD" ]; then
      log_discard "$path" "rule-17-no-match"
      continue
    fi

    # In-context filter
    if ! in_context_set "$target" "$context_set_file"; then
      log_discard "$path" "out-of-context-target:$target"
      continue
    fi

    # Emit kept row: path, rule, target, added, removed
    printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$rule_num" "$target" "$added" "$removed"

  done < "$input"
}

# Loads the harness ON the --self-test path only, never at the top: it is test
# code the production path never runs. `[ -r ]` first, not a bare `.` — sourcing
# a missing file with the `.` builtin is a special-builtin error that exits the
# shell immediately, bypassing an `if ! . …` guard entirely. Defined once because
# two dispatch arms reach it; both fail closed.
_source_selftest() {
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/map-and-filter-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=map-and-filter-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'map-and-filter: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

# If --self-test is anywhere in argv, handle it before LOG_OUT check.
for _arg in "$@"; do
  if [ "$_arg" = "--self-test" ]; then
    _source_selftest
    run_self_test
    exit $?
  fi
done

run_main "$@"
