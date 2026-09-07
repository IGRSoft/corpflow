#!/usr/bin/env bash
# map-and-filter-selftest.sh — the `--self-test` harness for map-and-filter.sh.
#
# SOURCED, never executed: map-and-filter.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_test`, returning 0 when every fixture passes.

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
    # `$0`, not BASH_SOURCE: this file is sourced, so BASH_SOURCE[0] is the
    # harness — re-invoking it would run a file with no entry point and every
    # case would compare against empty output. `$0` is still map-and-filter.sh.
    actual="$(bash "$0" \
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
