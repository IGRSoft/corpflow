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

# ---------------------------------------------------------------------------
# Self-test suite (--self-test; no network, no external deps)
# ---------------------------------------------------------------------------

run_self_test() {
  local pass=0
  local fail=0

  # Minimal log sink. Use a global-scope name so the EXIT trap can reach it
  # even after this function returns (bash local vars leave scope on return).
  _SELF_TEST_LOG="$(mktemp)"
  trap 'rm -f "${_SELF_TEST_LOG:-}"' EXIT
  export LOG_OUT="$_SELF_TEST_LOG"

  # Helper: build a context-set file and a changes TSV, then run the pipeline.
  # $1 = context set content (newline-delimited)
  # $2 = changes TSV content (path\tadded\tremoved rows)
  # $3 = expected stdout (exact string match)
  # $4 = test label
  # $5 = (optional) --dv-agent value
  _run_test() {
    local ctx_content="$1"
    local changes_content="$2"
    local expected="$3"
    local label="$4"
    local dv_agent_arg="${5:-agents/developer.md}"

    local ctx_file chg_file
    ctx_file="$(mktemp)"
    chg_file="$(mktemp)"
    printf '%s\n' "$ctx_content" > "$ctx_file"
    printf '%s' "$changes_content" > "$chg_file"

    # Reset log
    : > "$_SELF_TEST_LOG"

    local actual
    # Use 'set +e' around the call; child exits 0 on success, 1 on env error.
    # LOG_OUT is already exported to the environment.
    set +e
    actual="$(bash "${BASH_SOURCE[0]}" \
      --changes="$chg_file" \
      --context-set="$ctx_file" \
      --dv-agent="$dv_agent_arg" \
      2> /dev/null)"
    local child_exit=$?
    set -e

    rm -f "$ctx_file" "$chg_file"

    if [ $child_exit -ne 0 ]; then
      printf 'FAIL: %s  (child exit %d)\n' "$label" "$child_exit"
      fail=$((fail + 1))
      return 0
    fi

    if [ "$actual" = "$expected" ]; then
      printf 'PASS: %s\n' "$label"
      pass=$((pass + 1))
    else
      printf 'FAIL: %s\n' "$label"
      printf '  expected: [%s]\n' "$expected"
      printf '  actual:   [%s]\n' "$actual"
      fail=$((fail + 1))
    fi
  }

  # T1 — Rule 1: direct edit to agents/*.md, in context
  _run_test \
    "agents/developer.md" \
    "agents/developer.md	5	2" \
    "agents/developer.md	1	agents/developer.md	5	2" \
    "rule-1 agent direct edit (in context)"

  # T2 — Rule 1: out of context -> discarded (no output)
  _run_test \
    "agents/qa-engineer.md" \
    "agents/developer.md	3	1" \
    "" \
    "rule-1 agent direct edit (out of context)"

  # T3 — Rule 2: planning artifact
  _run_test \
    "agents/product-manager.md" \
    ".context/planning-0.md	10	0" \
    ".context/planning-0.md	2	agents/product-manager.md	10	0" \
    "rule-2 planning artifact"

  # T4 — Rule 5: development artifact, custom DV agent
  _run_test \
    "plugins/apple-developer/agents/ios-developer.md" \
    ".context/development-1.md	8	3" \
    ".context/development-1.md	5	plugins/apple-developer/agents/ios-developer.md	8	3" \
    "rule-5 development artifact custom dv-agent" \
    "plugins/apple-developer/agents/ios-developer.md"

  # T5 — Rule 13: source code, in context
  _run_test \
    "agents/developer.md" \
    "src/main.c	20	5" \
    "src/main.c	13	agents/developer.md	20	5" \
    "rule-13 source code"

  # T6 — Rule 17: unknown file -> discarded
  _run_test \
    "agents/developer.md" \
    "some/unknown/path.xyz	1	1" \
    "" \
    "rule-17 no match discarded"

  # T7 — Early filter: .context/logs/* -> discarded regardless of context set
  _run_test \
    "agents/developer.md" \
    ".context/logs/run.log	2	0" \
    "" \
    "early-filter logs discarded"

  # T8 — Early filter: self-improvement files -> discarded
  _run_test \
    "skills/self-improvement/SKILL.md" \
    "skills/self-improvement/SKILL.md	4	1" \
    "" \
    "early-filter self-improvement discarded"

  # T9 — Rule 16: plugin.json -> workflow-engineer
  _run_test \
    "agents/workflow-engineer.md" \
    "plugin.json	3	0" \
    "plugin.json	16	agents/workflow-engineer.md	3	0" \
    "rule-16 plugin.json to workflow-engineer"

  # T10 — Rule 15: tests/* in context via qa-engineer
  _run_test \
    "agents/qa-engineer.md" \
    "tests/foo_test.py	7	2" \
    "tests/foo_test.py	15	agents/qa-engineer.md	7	2" \
    "rule-15 test file"

  # T10b — Rule 15: Kotlin test file outside tests/. Before the ecosystem
  # broadening this fell through to rule 17 DISCARD and produced no row.
  _run_test \
    "agents/qa-engineer.md" \
    "feature/profile/ProfileViewModelTest.kt	9	1" \
    "feature/profile/ProfileViewModelTest.kt	15	agents/qa-engineer.md	9	1" \
    "rule-15 kotlin test file"

  # T10c — Rule 15: Go test file beside its source.
  _run_test \
    "agents/qa-engineer.md" \
    "internal/server/handler_test.go	5	3" \
    "internal/server/handler_test.go	15	agents/qa-engineer.md	5	3" \
    "rule-15 go test file"

  # T10d — Rule 16: Gradle build script reaches the DV agent, not DISCARD.
  _run_test \
    "agents/developer.md" \
    "build.gradle.kts	6	2" \
    "build.gradle.kts	16	agents/developer.md	6	2" \
    "rule-16 gradle build script"

  # T11 — Multiple rows: one kept, one discarded
  _run_test \
    "agents/developer.md" \
    "src/app.go	4	1
agents/qa-engineer.md	2	0" \
    "src/app.go	13	agents/developer.md	4	1" \
    "multiple rows mixed keep-discard"

  # T12 — Rule 8: testing artifact
  _run_test \
    "agents/qa-engineer.md" \
    ".context/testing-2.md	6	1" \
    ".context/testing-2.md	8	agents/qa-engineer.md	6	1" \
    "rule-8 testing artifact"

  printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

# If --self-test is anywhere in argv, handle it before LOG_OUT check.
for _arg in "$@"; do
  if [ "$_arg" = "--self-test" ]; then
    run_self_test
    exit $?
  fi
done

run_main "$@"
