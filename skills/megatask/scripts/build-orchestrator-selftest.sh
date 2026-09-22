#!/usr/bin/env bash
# build-orchestrator-selftest.sh — the `--self-test` harness for build-orchestrator.sh.
#
# SOURCED, never executed: build-orchestrator.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every fixture passes.

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
self_test() {
  local failures=0
  local pass_count=0

  require_jq

  st_pass() {
    pass_count=$((pass_count + 1))
    printf 'PASS: %s\n' "$1"
  }
  st_fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1"
  }
  st_check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then st_pass "$desc"; else
      st_fail "$desc -- expected $(printf '%q' "$expected") got $(printf '%q' "$actual")"
    fi
  }

  local td
  td=$(mktemp -d "${TMPDIR:-/tmp}/build-orch-selftest.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$td'" EXIT

  # ------------------------------------------------------------------
  # Fixture A: Clean DAG (matches dependency-graph.md worked example)
  # Issues: #41 P0, #42 P1, #57 P1, #60 P2
  # Edges: 42 depends on 41; 57 depends on 41; 60 depends on 42 and 57
  # Expected topo order: [41, 42, 57, 60]
  # Expected levels: 41=0, 42=1, 57=1, 60=2
  # Expected parallel_tracks: 1 (only #41 is ready at init)
  # ------------------------------------------------------------------
  cat > "$td/clean.json" << 'EOF'
[
  {"issue": 41, "title": "Core theme system",     "labels": ["P0"],
   "body": "## Summary\nCore work.\n"},
  {"issue": 42, "title": "Add login flow",         "labels": ["P1"],
   "body": "## Dependencies\n- Depends on: #41\n"},
  {"issue": 57, "title": "Settings sidebar",       "labels": ["P1"],
   "body": "## Dependencies\n- Depends on: #41\n"},
  {"issue": 60, "title": "Settings integration",  "labels": ["P2"],
   "body": "## Dependencies\n- Depends on: #42, #57\n"}
]
EOF

  local out_a
  OPT_GROUP="milestone-1" OPT_MS_NUM=1 OPT_MS_TITLE="Sprint 1" OPT_BASE_BRANCH="develop" \
    out_a=$(build_orchestrator "$td/clean.json")

  st_check "clean: version" "3.1" "$(printf '%s' "$out_a" | jq -r '.version')"
  st_check "clean: group" "milestone-1" "$(printf '%s' "$out_a" | jq -r '.group')"
  st_check "clean: topo order" "[41,42,57,60]" "$(printf '%s' "$out_a" | jq -c '.topological_order')"
  st_check "clean: level #41" "0" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==41) | .level')"
  st_check "clean: level #42" "1" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==42) | .level')"
  st_check "clean: level #57" "1" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==57) | .level')"
  st_check "clean: level #60" "2" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==60) | .level')"
  st_check "clean: #41 status" "ready" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==41) | .status')"
  st_check "clean: #42 status" "blocked" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==42) | .status')"
  st_check "clean: #60 blocked_by" "[42,57]" "$(printf '%s' "$out_a" | jq -c '.issues[] | select(.number==60) | .blocked_by | sort')"
  st_check "clean: parallel_tracks" "1" "$(printf '%s' "$out_a" | jq -r '.configuration.parallel_tracks')"
  st_check "clean: progress.total" "4" "$(printf '%s' "$out_a" | jq -r '.progress.total')"
  st_check "clean: progress.ready" "1" "$(printf '%s' "$out_a" | jq -r '.progress.ready')"
  st_check "clean: progress.blocked" "3" "$(printf '%s' "$out_a" | jq -r '.progress.blocked')"
  st_check "clean: #41 priority" "P0" "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==41) | .priority')"
  st_check "clean: tracks count" "1" "$(printf '%s' "$out_a" | jq -r '.tracks | keys | length')"
  st_check "clean: #41 workspace" ".worktrees/milestone-1/41" \
    "$(printf '%s' "$out_a" | jq -r '.issues[] | select(.number==41) | .workspace')"

  # ------------------------------------------------------------------
  # Fixture B: Cycle (41 depends on 42; 42 depends on 41)
  # ------------------------------------------------------------------
  cat > "$td/cycle.json" << 'EOF'
[
  {"issue": 41, "title": "Issue A", "labels": ["P0"],
   "body": "## Dependencies\n- Depends on: #42\n"},
  {"issue": 42, "title": "Issue B", "labels": ["P1"],
   "body": "## Dependencies\n- Depends on: #41\n"}
]
EOF

  local cycle_err=0
  OPT_GROUP="milestone-0" OPT_MS_NUM=0 OPT_MS_TITLE="" OPT_BASE_BRANCH="master" \
    build_orchestrator "$td/cycle.json" > /dev/null 2> "$td/cycle_stderr.txt" || cycle_err=$?

  if [[ "$cycle_err" -ne 0 ]]; then
    st_pass "cycle: exits non-zero"
  else
    st_fail "cycle: should have exited non-zero"
  fi

  if grep -qi 'cycle' "$td/cycle_stderr.txt"; then
    st_pass "cycle: error mentions 'cycle'"
  else
    st_fail "cycle: error message missing 'cycle'"
    cat "$td/cycle_stderr.txt" >&2
  fi

  # ------------------------------------------------------------------
  # Fixture C: No-dependency set -- all issues ready; parallel_tracks = min(3,5)
  # ------------------------------------------------------------------
  cat > "$td/nodeps.json" << 'EOF'
[
  {"issue": 10, "title": "Alpha", "labels": ["P1"], "body": ""},
  {"issue": 11, "title": "Beta",  "labels": ["P2"], "body": ""},
  {"issue": 12, "title": "Gamma", "labels": [],     "body": ""}
]
EOF

  local out_c
  OPT_GROUP="issues-xyz" OPT_MS_NUM=0 OPT_MS_TITLE="" OPT_BASE_BRANCH="master" \
    out_c=$(build_orchestrator "$td/nodeps.json")

  st_check "nodeps: parallel_tracks" "3" "$(printf '%s' "$out_c" | jq -r '.configuration.parallel_tracks')"
  st_check "nodeps: all ready" "3" "$(printf '%s' "$out_c" | jq -r '.progress.ready')"
  st_check "nodeps: tracks count" "3" "$(printf '%s' "$out_c" | jq -r '.tracks | keys | length')"

  # ------------------------------------------------------------------
  # Fixture D: Single issue -- parallel_tracks must be 1
  # ------------------------------------------------------------------
  cat > "$td/single.json" << 'EOF'
[{"issue": 5, "title": "Solo", "labels": ["P0"], "body": ""}]
EOF

  local out_d
  OPT_GROUP="issues-solo" OPT_MS_NUM=0 OPT_MS_TITLE="" OPT_BASE_BRANCH="master" \
    out_d=$(build_orchestrator "$td/single.json")

  st_check "single: parallel_tracks" "1" "$(printf '%s' "$out_d" | jq -r '.configuration.parallel_tracks')"

  # ------------------------------------------------------------------
  # Fixture E: External dependency warning (#99 not in set)
  # ------------------------------------------------------------------
  cat > "$td/external.json" << 'EOF'
[
  {"issue": 20, "title": "Internal", "labels": ["P1"],
   "body": "## Dependencies\n- Depends on: #99\n"}
]
EOF

  local out_e
  OPT_GROUP="milestone-2" OPT_MS_NUM=2 OPT_MS_TITLE="T2" OPT_BASE_BRANCH="master" \
    out_e=$(build_orchestrator "$td/external.json")

  st_check "external: issue ready (external dep not gating)" "ready" \
    "$(printf '%s' "$out_e" | jq -r '.issues[] | select(.number==20) | .status')"
  st_check "external: dep_warning present" "1" \
    "$(printf '%s' "$out_e" | jq -r '.dependency_warnings | length')"

  # ------------------------------------------------------------------
  # Fixture F: Blocks: keyword (reverse direction)
  # Issue 30 says "Blocks: #31" => 31 is blocked by 30
  # ------------------------------------------------------------------
  cat > "$td/blocks.json" << 'EOF'
[
  {"issue": 30, "title": "Lib", "labels": ["P0"],
   "body": "## Dependencies\n- Blocks: #31\n"},
  {"issue": 31, "title": "App", "labels": ["P1"], "body": ""}
]
EOF

  local out_f
  OPT_GROUP="milestone-3" OPT_MS_NUM=3 OPT_MS_TITLE="T3" OPT_BASE_BRANCH="master" \
    out_f=$(build_orchestrator "$td/blocks.json")

  st_check "blocks: #31 blocked by #30" "[30]" \
    "$(printf '%s' "$out_f" | jq -c '.issues[] | select(.number==31) | .blocked_by')"
  st_check "blocks: #30 is ready" "ready" \
    "$(printf '%s' "$out_f" | jq -r '.issues[] | select(.number==30) | .status')"

  # ------------------------------------------------------------------
  # Fixture G: max 5 parallel_tracks even with 7 ready issues
  # ------------------------------------------------------------------
  cat > "$td/many.json" << 'EOF'
[
  {"issue":1,"title":"I1","labels":["P0"],"body":""},
  {"issue":2,"title":"I2","labels":["P1"],"body":""},
  {"issue":3,"title":"I3","labels":["P2"],"body":""},
  {"issue":4,"title":"I4","labels":[],"body":""},
  {"issue":5,"title":"I5","labels":[],"body":""},
  {"issue":6,"title":"I6","labels":[],"body":""},
  {"issue":7,"title":"I7","labels":[],"body":""}
]
EOF

  local out_g
  # Read by build_orchestrator in the caller (build-orchestrator.sh); shellcheck
  # cannot follow across the source boundary since the harness moved out.
  # shellcheck disable=SC2034
  OPT_GROUP="milestone-4" OPT_MS_NUM=4 OPT_MS_TITLE="" OPT_BASE_BRANCH="master" \
    out_g=$(build_orchestrator "$td/many.json")

  st_check "many: parallel_tracks capped at 5" "5" \
    "$(printf '%s' "$out_g" | jq -r '.configuration.parallel_tracks')"

  # ------------------------------------------------------------------
  trap - EXIT
  rm -rf "$td"

  if [[ "$failures" -eq 0 ]]; then
    printf 'build-orchestrator: self-test OK (%d checks passed)\n' "$pass_count"
    return 0
  else
    printf 'build-orchestrator: self-test FAILED (%d/%d checks failed)\n' "$failures" "$((failures + pass_count))"
    return 1
  fi
}
