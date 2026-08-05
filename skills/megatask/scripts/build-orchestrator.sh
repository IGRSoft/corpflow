#!/usr/bin/env bash
# @description Build orchestrator.json v3.1 from pre-fetched issue JSON.
#
#   Input  : JSON array of issue objects via --file <path> or stdin:
#              [{ "issue": <int>, "body": "<text>", "labels": ["P0", ...],
#                 "title": "<text>" }, ...]
#
#   Output : orchestrator.json v3.1 written to --out <path> (default stdout).
#
#   Performs:
#     1. Edge extraction  -- "Depends on / Blocked by #N" and "Blocks: #N"
#        parsed as integers only; untrusted text never reaches a shell command.
#     2. Normalization    -- deduplicate edges, drop self-edges, classify external.
#     3. Cycle detection  -- Kahn's algorithm; exits 1 with clear error on cycle.
#     4. Level assignment -- topological wave (0 = no blockers).
#     5. Priority tiebreak -- P0 < P1 < P2 < P3 < unlabeled; FIFO by number.
#     6. parallel_tracks  -- min(count(ready issues), 5); single issue => 1.
#     7. Emits orchestrator.json v3.1 exactly per skills/megatask/references/schemas.md.
#
#   Usage:
#     bash build-orchestrator.sh --file issues.json [--out orchestrator.json]
#                                [--group milestone-1] [--milestone-num N]
#                                [--milestone-title "Sprint 1"] [--base-branch develop]
#     bash build-orchestrator.sh --self-test
#
# @arg --file         path   Pre-fetched issue JSON (array); use - for stdin.
# @arg --out          path   Destination for orchestrator.json (default: stdout).
# @arg --group        string Group token, e.g. milestone-1 or issues-abc (default: milestone-0).
# @arg --milestone-num int   Milestone number stored in .milestone.number (default: 0).
# @arg --milestone-title str Milestone title (default: "").
# @arg --base-branch  string Stored in .base_branch (default: master).
# @arg --self-test           Run built-in tests (no network, no side effects); exit non-zero on fail.
#
# @exitcode 0  Success.
# @exitcode 1  Cycle detected / bad input / missing dependency.
# @exitcode 2  jq not found.
#
# Minimum Bash: 4.0 (associative arrays). Tested on Bash 5.x and macOS.
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d (exit %d)\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ts() { date -u +%FT%TZ 2> /dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ'; }

require_jq() {
  command -v jq > /dev/null 2>&1 || {
    printf >&2 'build-orchestrator: jq is required but not found\n'
    exit 2
  }
}

die() {
  printf >&2 'build-orchestrator: %s\n' "$*"
  exit 1
}

# ---------------------------------------------------------------------------
# build_orchestrator <json_src>
# json_src = path to issue JSON array, or "-" for stdin.
# Writes orchestrator.json v3.1 to stdout.
# All DAG construction is done inside jq -- untrusted body text never reaches
# shell string interpolation or any command.
# ---------------------------------------------------------------------------
build_orchestrator() {
  local json_src="$1"

  if [[ "$json_src" == "-" ]]; then
    # Materialise stdin to a temp file so we can pass a path to jq safely.
    local tmp_input
    tmp_input=$(mktemp -t build-orch-input.XXXXXX)
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_input'" RETURN
    cat > "$tmp_input"
    json_src="$tmp_input"
  fi

  # Validate: must be a JSON array.
  jq -e 'type == "array"' -- "$json_src" > /dev/null 2>&1 \
    || die "input must be a JSON array of issue objects"

  # Pass all DAG construction into a single jq program.
  # Issue numbers are extracted with tonumber|floor and filtered to integers.
  # No shell word-splitting or interpolation of body text occurs.
  jq -c \
    --arg group "$OPT_GROUP" \
    --argjson ms_num "$OPT_MS_NUM" \
    --arg ms_title "$OPT_MS_TITLE" \
    --arg base_branch "$OPT_BASE_BRANCH" \
    --arg created_at "$(ts)" \
    '
    # -----------------------------------------------------------------------
    # 0. Normalise input: ensure each element has .issue (int), .body (str),
    #    .labels (array of strings), .title (str).
    # -----------------------------------------------------------------------
    def to_int: . // 0 | if type == "number" then floor else tonumber | floor end;
    def ensure_labels: if (.labels // [] | type) == "array"
      then [(.labels // [])[] | if type == "string" then . else .name // "" end]
      else [] end;

    # -----------------------------------------------------------------------
    # 1. Build index: issue_num -> {number, title, priority_score, labels}
    # -----------------------------------------------------------------------
    def priority_score(lbls):
      (lbls | map(
        if test("^(P0|priority:critical)$";"i") then 0
        elif test("^(P1|priority:high)$";"i")   then 1
        elif test("^(P2|priority:medium)$";"i") then 2
        elif test("^(P3|priority:low)$";"i")    then 3
        elif test("^(P4|priority:backlog)$";"i") then 4
        else 99 end
      ) | if length == 0 then 99 else min end);

    # Resolve issue number: accept .issue or .number key.
    def issue_num: (.issue // .number // 0) | to_int;

    map({
      number:   issue_num,
      title:    (.title // ""),
      labels:   ensure_labels,
      body:     (.body // ""),
      priority: priority_score(ensure_labels)
    }) | map(select(.number > 0)) as $issues |

    # -----------------------------------------------------------------------
    # 2. Extract edges from body text (integers only; no shell execution).
    #    "Depends on / Blocked by #N" -> blocked_by edge (N must finish before this)
    #    "Blocks: #N"                 -> blocks edge (this must finish before N)
    #
    #    Strategy: scan each keyword-to-EOL line, then collect all #NNN on it.
    #    Using scan(...line...) | scan(#NNN) avoids gsub+split which loses the
    #    $iss scope and breaks on real newlines embedded in JSON strings.
    # -----------------------------------------------------------------------
    ($issues | map(.number) | sort) as $issue_set |

    # Build raw edge list: {from: A, to: B} means "A must complete before B"
    ([ $issues[] | . as $iss |
      # "Depends on / Blocked by" lines: each #N means edge N -> $iss.number
      ([ $iss.body | scan("(?i)(?:depends[ -]on|blocked[ -]by)\\s*:?[^\n]*") |
           scan("#(\\d+)") | .[0] | tonumber | select(. > 0) |
           {from: ., to: $iss.number} ]) +
      # "Blocks" lines: each #N means edge $iss.number -> N
      # \b on both sides: an unanchored `blocks?` substring-matches the "Block" in
      # "Blocked by", which minted a reverse edge on top of the correct one and
      # turned acyclic graphs into false cycles. The `s?` is kept so the singular
      # "Block: #N" spelling still registers.
      ([ $iss.body | scan("(?i)\\bblocks?\\b\\s*:?[^\n]*") |
           scan("#(\\d+)") | .[0] | tonumber | select(. > 0) |
           {from: $iss.number, to: .} ])
    ] | flatten) as $raw_edges |

    # -----------------------------------------------------------------------
    # 3. Normalise: deduplicate, drop self-edges (warn), split internal/external
    # -----------------------------------------------------------------------
    ($raw_edges |
      map(select(.from != .to)) |
      unique_by([.from, .to])
    ) as $all_edges |

    ($all_edges | map(select((.from | IN($issue_set[])) and (.to | IN($issue_set[]))))) as $internal |
    ($all_edges | map(select((.from | IN($issue_set[]) | not) or (.to | IN($issue_set[]) | not)))) as $external_edges |

    # Self-edges (warned but not in output)
    ($raw_edges | map(select(.from == .to)) | map(.from)) as $self_edge_nums |

    # dependency_warnings: external + self-edges
    (
      ($external_edges | map({
        issue: .to,
        external_dependency: .from,
        note: ("#" + (.from|tostring) + " not in resolved set — not gating")
      })) +
      ($self_edge_nums | map({
        issue: .,
        note: "self-edge dropped"
      }))
    ) as $dep_warnings |

    # -----------------------------------------------------------------------
    # 4. Kahn cycle detection + topological sort (priority-respecting)
    # -----------------------------------------------------------------------
    # Build in-degree map and adjacency list from $internal edges.
    # We work in a functional style using reduce.
    (reduce $issues[] as $i ({};. + {($i.number|tostring): 0})) as $zero_indeg |

    (reduce $internal[] as $e (
      $zero_indeg;
      . + {($e.to|tostring): ((.[$e.to|tostring] // 0) + 1)}
    )) as $indeg_init |

    # adjacency list: from -> [to, ...]
    (reduce $internal[] as $e (
      {};
      . + {($e.from|tostring): ((.[$e.from|tostring] // []) + [$e.to])}
    )) as $adj |

    # Priority map: number -> {priority, number} for sorting
    (reduce $issues[] as $i ({}; . + {($i.number|tostring): {p: $i.priority, n: $i.number}})) as $pmap |

    # Kahn: reduce over N iterations (one per issue). Each step picks the
    # lowest-(priority,number) zero-indegree node, appends it to order, and
    # decrements successors. State = {order, indeg, done}.
    # "done" becomes true when no zero-indegree node remains (cycle) or all
    # N nodes have been ordered (success).
    ($issues | length) as $n_issues |
    (reduce range($n_issues) as $_ (
      {order: [], indeg: $indeg_init, done: false};
      if .done then .
      else
        # Zero-indegree candidates, sorted by (priority, number)
        (.indeg | to_entries | map(select(.value == 0)) | map(.key | tonumber)
          | sort_by([$pmap[(.|tostring)].p, $pmap[(.|tostring)].n])) as $candidates |
        if ($candidates | length) == 0 then
          # No zero-indegree node -- cycle; stop iteration
          .done = true
        else
          ($candidates[0]) as $node |
          {
            order: (.order + [$node]),
            done:  false,
            indeg: (
              (.indeg | del(.[$node|tostring])) as $d |
              reduce ($adj[$node|tostring] // [])[] as $s (
                $d;
                . + {($s|tostring): (.[$s|tostring] - 1)}
              )
            )
          }
        end
      end
    )) as $kahn_result |

    # Cycle detection: issues ordered < total => cycle among remaining nodes.
    (($kahn_result.order | length) < $n_issues) as $has_cycle |
    # Identify cycle participants: nodes still present in indeg after Kahn run.
    ([$kahn_result.indeg | to_entries[] | select(.value > 0) | .key | tonumber]) as $cycle_nodes |

    if $has_cycle then
      error("dependency cycle among issues: " + ($cycle_nodes | sort | map(tostring) | join(", ")))
    else
      # -----------------------------------------------------------------------
      # 5. Level assignment: level[n] = 0 if no blockers, else 1 + max(level[blocker])
      # -----------------------------------------------------------------------
      # blocked_by map: issue -> [blocker, ...]
      (reduce $internal[] as $e (
        {};
        . + {($e.to|tostring): ((.[$e.to|tostring] // []) + [$e.from])}
      )) as $blocked_by_map |

      # Assign levels in topo order
      (reduce $kahn_result.order[] as $n (
        {};
        . as $levels |
        ($blocked_by_map[$n|tostring] // []) as $blockers |
        (if ($blockers | length) == 0
         then 0
         else 1 + ($blockers | map($levels[(.|tostring)] // 0) | max)
         end) as $lv |
        $levels + {($n|tostring): $lv}
      )) as $levels |

      # blocks map: from -> [to, ...]
      (reduce $internal[] as $e (
        {};
        . + {($e.from|tostring): ((.[$e.from|tostring] // []) + [$e.to])}
      )) as $blocks_map |

      # External dependencies per issue:
      # External edge from=external, to=internal -> issue .to has external dep .from
      ($external_edges | map(select((.to | IN($issue_set[])))) |
        group_by(.to) |
        map({key: (.[0].to|tostring), value: map(.from)}) |
        from_entries
      ) as $ext_dep_map |

      # -----------------------------------------------------------------------
      # 6. parallel_tracks = min(ready_count, 5); single issue -> 1
      # -----------------------------------------------------------------------
      ($issues | length) as $total |
      ([$issues[] | select(($blocked_by_map[(.number|tostring)] // []) | length == 0)] | length) as $ready_count |
      (if $total <= 1 then 1
       elif $ready_count == 0 then 1
       elif $ready_count > 5 then 5
       else $ready_count
       end) as $parallel_tracks |

      # -----------------------------------------------------------------------
      # 7. Build issue records and initial tracks
      # -----------------------------------------------------------------------
      (reduce $issues[] as $iss (
        [];
        . + [
          {
            number:   $iss.number,
            title:    $iss.title,
            priority: (if $iss.priority == 0 then "P0"
                       elif $iss.priority == 1 then "P1"
                       elif $iss.priority == 2 then "P2"
                       elif $iss.priority == 3 then "P3"
                       elif $iss.priority == 4 then "P4"
                       elif $iss.priority == 99 then null
                       else null end),
            status:   (if (($blocked_by_map[$iss.number|tostring] // []) | length) == 0
                       then "ready" else "blocked" end),
            track:    null,
            level:    ($levels[$iss.number|tostring] // 0),
            blocked_by: ($blocked_by_map[$iss.number|tostring] // []),
            blocks:     ($blocks_map[$iss.number|tostring] // []),
            external_dependencies: ($ext_dep_map[$iss.number|tostring] // []),
            current_stage: null,
            branch: null,
            workspace: (".worktrees/" + $group + "/" + ($iss.number|tostring)),
            isolation: "worktree"
          }
        ]
      )) as $issue_records |

      # Initial tracks object: 1..parallel_tracks all available
      (reduce range(1; $parallel_tracks + 1) as $t (
        {};
        . + {($t|tostring): {issue_number: null, status: "available"}}
      )) as $tracks_init |

      # Progress counts
      {
        total:       ($issue_records | length),
        completed:   0,
        in_progress: 0,
        ready:       ($issue_records | map(select(.status == "ready")) | length),
        blocked:     ($issue_records | map(select(.status == "blocked")) | length),
        failed:      0
      } as $progress |

      # -----------------------------------------------------------------------
      # Final orchestrator.json v3.1
      # -----------------------------------------------------------------------
      {
        version:          "3.1",
        group:            $group,
        milestone:        {number: $ms_num, title: $ms_title},
        configuration:    {parallel_tracks: $parallel_tracks, isolation: "worktree"},
        base_branch:      $base_branch,
        created_at:       $created_at,
        topological_order: $kahn_result.order,
        dependency_warnings: $dep_warnings,
        issues:           $issue_records,
        tracks:           $tracks_init,
        progress:         $progress
      }
    end
    ' -- "$json_src"
}

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
  td=$(mktemp -d -t build-orch-selftest.XXXXXX)
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

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
OPT_FILE=""
OPT_OUT=""
OPT_GROUP="milestone-0"
OPT_MS_NUM=0
OPT_MS_TITLE=""
OPT_BASE_BRANCH="master"
SELF_TEST_MODE=0

usage() {
  cat >&2 << 'USAGE'
Usage: build-orchestrator.sh [OPTIONS]

Options:
  --file <path>            Input issue JSON array (use - for stdin)
  --out  <path>            Write orchestrator.json here (default: stdout)
  --group <str>            Group token, e.g. milestone-1 (default: milestone-0)
  --milestone-num <int>    Milestone number (default: 0)
  --milestone-title <str>  Milestone title (default: "")
  --base-branch <str>      Base branch name (default: master)
  --self-test              Run built-in tests; exit non-zero on failure
  -h, --help               Show this help
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      OPT_FILE="$2"
      shift 2
      ;;
    --file=*)
      OPT_FILE="${1#--file=}"
      shift
      ;;
    --out)
      OPT_OUT="$2"
      shift 2
      ;;
    --out=*)
      OPT_OUT="${1#--out=}"
      shift
      ;;
    --group)
      OPT_GROUP="$2"
      shift 2
      ;;
    --group=*)
      OPT_GROUP="${1#--group=}"
      shift
      ;;
    --milestone-num)
      OPT_MS_NUM="$2"
      shift 2
      ;;
    --milestone-num=*)
      OPT_MS_NUM="${1#--milestone-num=}"
      shift
      ;;
    --milestone-title)
      OPT_MS_TITLE="$2"
      shift 2
      ;;
    --milestone-title=*)
      OPT_MS_TITLE="${1#--milestone-title=}"
      shift
      ;;
    --base-branch)
      OPT_BASE_BRANCH="$2"
      shift 2
      ;;
    --base-branch=*)
      OPT_BASE_BRANCH="${1#--base-branch=}"
      shift
      ;;
    --self-test | self-test)
      SELF_TEST_MODE=1
      shift
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      printf >&2 'build-orchestrator: unknown option: %s\n' "$1"
      usage
      ;;
  esac
done

require_jq

# Export opts so subshell (self_test) can read them.
export OPT_GROUP OPT_MS_NUM OPT_MS_TITLE OPT_BASE_BRANCH

if [[ "$SELF_TEST_MODE" -eq 1 ]]; then
  self_test
  exit $?
fi

[[ -n "$OPT_FILE" ]] || die "--file <path> or - (stdin) is required"

# Validate milestone-num is an integer.
[[ "$OPT_MS_NUM" =~ ^[0-9]+$ ]] || die "--milestone-num must be a non-negative integer"

if [[ -n "$OPT_OUT" ]]; then
  # Atomic write: write to sibling tmp, then rename.
  out_dir="$(dirname -- "$OPT_OUT")"
  tmp_out=$(mktemp -t build-orch-out.XXXXXX -p "$out_dir" 2> /dev/null \
    || mktemp -t build-orch-out.XXXXXX)
  trap 'rm -f "$tmp_out"' EXIT
  build_orchestrator "$OPT_FILE" > "$tmp_out"
  mv -f -- "$tmp_out" "$OPT_OUT"
  trap - EXIT
else
  build_orchestrator "$OPT_FILE"
fi
