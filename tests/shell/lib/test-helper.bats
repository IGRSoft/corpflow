#!/usr/bin/env bats
# Self-test for tests/lib/test_helper.bash — the 7 helpers every other .bats
# file in this suite compiles against. A silent regression here corrupts the
# evidence of every test that uses them, so the contract is pinned directly.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"

  # Probe: reports the child's view of env, cwd and PATH resolution.
  cat > "$WD/probe.sh" <<'EOF'
#!/usr/bin/env bash
printf 'cwd=%s\n' "$PWD"
printf 'FOO=%s\n' "${FOO-<unset>}"
printf 'BAR=%s\n' "${BAR-<unset>}"
if command -v jq > /dev/null 2>&1; then printf 'jq=present\n'; else printf 'jq=absent\n'; fi
printf 'stdin=%s\n' "$(cat)"
printf 'argv=%s\n' "$*"
printf 'to-stderr\n' >&2
exit 0
EOF
  chmod +x "$WD/probe.sh"
}

teardown() {
  _test_helper_cleanup
}

# ---------------------------------------------------------------------------
# Exposed paths
# ---------------------------------------------------------------------------
@test "H1: PLUGIN_ROOT and FIXTURES point at the real tree" {
  [ -f "$PLUGIN_ROOT/run-tests.sh" ]
  [ -d "$FIXTURES" ]
  [ "$FIXTURES" = "$PLUGIN_ROOT/tests/fixtures" ]
}

# ---------------------------------------------------------------------------
# run_script — the frozen primitive
# ---------------------------------------------------------------------------
@test "H2: run_script dispatches a PLUGIN_ROOT-relative .sh and sets status/output" {
  run_script run-tests.sh --bogus-flag
  [ "$status" -eq 64 ]
  assert_output --partial "unknown arg '--bogus-flag'"
}

# ---------------------------------------------------------------------------
# run_script_env — child-only environment mutation (AR D2)
# ---------------------------------------------------------------------------
@test "H3: --env sets a child variable and --unset removes an inherited one" {
  export BAR="inherited-value"
  run_script_env --env FOO=from-flag --unset BAR --cwd "$WD" ./probe.sh
  unset BAR
  assert_success
  assert_line 'FOO=from-flag'
  assert_line 'BAR=<unset>'
}

@test "H4: --cwd runs the child elsewhere without moving the caller" {
  caller_pwd_before="$PWD"
  run_script_env --cwd "$WD" ./probe.sh
  assert_success
  # The wrapper `cd`s to the given path, so the child keeps the logical form.
  assert_line "cwd=$WD"
  [ "$PWD" = "$caller_pwd_before" ]
}

@test "H5: --path replaces the child PATH without touching the caller's" {
  caller_path="$PATH"
  mkdir -p "$WD/onlybin"
  ln -sf "$(command -v bash)" "$WD/onlybin/bash"
  ln -sf "$(command -v cat)" "$WD/onlybin/cat"
  run_script_env --path "$WD/onlybin" --cwd "$WD" ./probe.sh
  assert_success
  assert_line 'jq=absent'
  assert_equal "$PATH" "$caller_path"
}

@test "H6: stdin defaults to /dev/null, --stdin-string and --stdin-file feed the child" {
  run_script_env --cwd "$WD" ./probe.sh
  assert_line 'stdin='

  run_script_env --cwd "$WD" --stdin-string 'payload-text' ./probe.sh
  assert_line 'stdin=payload-text'

  printf 'from-a-file' > "$WD/payload.txt"
  run_script_env --cwd "$WD" --stdin-file "$WD/payload.txt" ./probe.sh
  assert_line 'stdin=from-a-file'
}

@test "H7: --separate-stderr splits the two streams" {
  run_script_env --separate-stderr --cwd "$WD" ./probe.sh
  assert_success
  assert_equal "$stderr" 'to-stderr'
  refute_output --partial 'to-stderr'
}

@test "H8: target resolution covers PLUGIN_ROOT-relative, ./-relative and absolute" {
  run_script_env --cwd "$WD" ./probe.sh rel-form
  assert_line 'argv=rel-form'

  run_script_env "$WD/probe.sh" abs-form
  assert_line 'argv=abs-form'

  cp "$WD/probe.sh" "$PLUGIN_ROOT/tests/shell/lib/.probe-tmp.sh"
  run_script_env tests/shell/lib/.probe-tmp.sh root-form
  rm -f "$PLUGIN_ROOT/tests/shell/lib/.probe-tmp.sh"
  assert_line 'argv=root-form'
}

@test "H9: --hide makes command -v genuinely fail for the hidden tool only" {
  run_script_env --hide jq --cwd "$WD" ./probe.sh
  assert_success
  assert_line 'jq=absent'

  # Control arm: without --hide the same probe resolves jq, so the line above is
  # attributable to the farm and not to a broken probe.
  run_script_env --cwd "$WD" ./probe.sh
  assert_line 'jq=present'
}

@test "H10: --hide never leaks into the test shell's own PATH" {
  run_script_env --hide jq --cwd "$WD" ./probe.sh
  assert_line 'jq=absent'
  # The assertion machinery below would break if the farm had escaped.
  command -v jq > /dev/null
  printf '{"a":1}' | jq -e '.a == 1' > /dev/null
}

@test "H11: --source calls a function out of a repo-relative library" {
  run_script_env --source skills/worktask/scripts/branch-lib.sh derive_slug 'Fix The Thing'
  assert_success
  assert_output 'fix-the-thing'
}

# ---------------------------------------------------------------------------
# stub_cmd / stub_log — the recording double behind the offline proofs
# ---------------------------------------------------------------------------
@test "H12: stub_cmd records argv per call and stub_log reports count and argv" {
  stub_cmd faketool --exit 3 --stdout 'stub-said-this' --stderr 'stub-warned'
  run_script_env --stub-path --cwd "$WD" --separate-stderr /bin/sh -c \
    'faketool one "two three"; faketool second-call; exit 0'
  assert_success
  assert_output --partial 'stub-said-this'

  assert_equal "$(stub_log --count faketool)" '2'
  assert_equal "$(stub_log --argv faketool --call 1)" 'one
two three'
  assert_equal "$(stub_log --argv faketool --call 2)" 'second-call'
}

@test "H13: stub_log for a never-called stub is empty, and never clobbers \$output" {
  stub_cmd nevercalled
  run_script_env --stub-path --cwd "$WD" ./probe.sh sentinel-argv
  assert_line 'argv=sentinel-argv'

  assert_equal "$(stub_log nevercalled)" ''
  assert_equal "$(stub_log --count nevercalled)" '0'
  # $output must survive the stub_log calls above — this is what makes the
  # offline proofs assertable in the same test as the exit-code assertion.
  assert_line 'argv=sentinel-argv'
}

@test "H14: stub_cmd --body runs custom shell and --record-stdin captures input" {
  stub_cmd writer --body 'out="${@: -1}"; printf "written" > "$out"; exit 0'
  stub_cmd drain --record-stdin --exit 0
  run_script_env --stub-path --cwd "$WD" /bin/sh -c \
    'writer ignored "$0/made.txt"; printf "piped-in" | drain; exit 0' "$WD"
  assert_success
  assert_equal "$(cat "$WD/made.txt")" 'written'
  assert_equal "$(stub_log --count drain)" '1'
}

# ---------------------------------------------------------------------------
# mock_gh
# ---------------------------------------------------------------------------
@test "H15: mock_gh routes on an argv prefix and falls through to the default" {
  mock_gh --route 'issue create=0:https://github.com/o/r/issues/7' \
          --default-exit 1 --default-stdout 'unrouted'
  run_script_env --stub-path --cwd "$WD" /bin/sh -c \
    'gh issue create --title T; echo "rc=$?"; gh pr list; echo "rc=$?"'
  assert_line 'https://github.com/o/r/issues/7'
  assert_line --index 1 'rc=0'
  assert_line 'unrouted'
  assert_line --index 3 'rc=1'
  [[ "$(stub_log gh)" == *"issue create --title T"* ]]
}

# ---------------------------------------------------------------------------
# mk_state_fixture
# ---------------------------------------------------------------------------
@test "H16: mk_state_fixture writes the canonical shape and omits facts.goal" {
  mk_state_fixture "$WD/.context/state.json" > /dev/null
  run jq -e '.version == 1 and .worktask_id == "wt-test" and .run_index == 0
             and (.facts | has("goal") | not)' "$WD/.context/state.json"
  assert_success
}

@test "H17: mk_state_fixture applies trailing jq filters in order" {
  mk_state_fixture "$WD/.context/state.json" \
    '.worktask_id="wt-fix"' \
    '.tasks.PL0={status:"completed",verdict:"ok"}' \
    '.facts.goal="build a thing"' > /dev/null
  run jq -r '[.worktask_id, .tasks.PL0.status, .facts.goal] | @tsv' "$WD/.context/state.json"
  assert_success
  assert_output "$(printf 'wt-fix\tcompleted\tbuild a thing')"
}

# ---------------------------------------------------------------------------
# mk_git_fixture
# ---------------------------------------------------------------------------
@test "H18: mk_git_fixture is byte-deterministic across two runs" {
  a="$(mk_git_fixture --branch main --file 'src/a.sh:#!/usr/bin/env bash\necho hi\n' --commit 'init')"
  b="$(mk_git_fixture --branch main --file 'src/a.sh:#!/usr/bin/env bash\necho hi\n' --commit 'init')"
  sha_a="$(git -C "$a" rev-parse HEAD)"
  sha_b="$(git -C "$b" rev-parse HEAD)"
  assert_equal "$sha_a" "$sha_b"
}

@test "H19: mk_git_fixture --commit then --modify leaves an unstaged working-tree diff" {
  repo="$(mk_git_fixture --branch main \
    --file 'src/a.sh:#!/usr/bin/env bash\necho hi\n' --commit 'init' \
    --modify 'src/a.sh:#!/usr/bin/env bash\n# why: the retry window is 2s\necho hi\n')"
  run git -C "$repo" diff --name-only HEAD
  assert_output 'src/a.sh'
  run git -C "$repo" rev-parse --abbrev-ref HEAD
  assert_output 'main'
}

# ---------------------------------------------------------------------------
# assert_audit_row
# ---------------------------------------------------------------------------
@test "H20: assert_audit_row matches action/result/meta and honours --count/--absent" {
  cat > "$WD/.context/logs/audit.jsonl" <<'EOF'
{"ts":"2020-01-01T00:00:00Z","actor":"hook:x","action":"comment_density_block","subject":"a","result":"blocked","metadata":{"worst_pct":62}}
{"ts":"2020-01-01T00:00:01Z","actor":"hook:x","action":"comment_density_pass","subject":"a","result":"ok","metadata":{"worst_pct":12}}
EOF
  assert_audit_row comment_density_block --file "$WD/.context/logs/audit.jsonl" \
    --result blocked --meta worst_pct=62 --count 1
  assert_audit_row state_repair --file "$WD/.context/logs/audit.jsonl" --absent
}

@test "H21: assert_audit_row leaves \$output/\$status intact for later assertions" {
  cat > "$WD/.context/logs/audit.jsonl" <<'EOF'
{"ts":"2020-01-01T00:00:00Z","actor":"hook:x","action":"probe_ran","subject":"a","result":"ok","metadata":{}}
EOF
  run_script_env --cwd "$WD" ./probe.sh survivor
  assert_line 'argv=survivor'
  saved_status="$status"

  assert_audit_row probe_ran --file "$WD/.context/logs/audit.jsonl" --result ok

  # AR-4: an implementation that used `run` internally would blow both of these.
  assert_line 'argv=survivor'
  assert_equal "$status" "$saved_status"
}

@test "H22: AUDIT_LOG/WD defaulting resolves the log without an explicit --file" {
  cat > "$WD/.context/logs/audit.jsonl" <<'EOF'
{"ts":"2020-01-01T00:00:00Z","actor":"hook:x","action":"defaulted","subject":"a","result":"ok","metadata":{}}
EOF
  assert_audit_row defaulted --result ok
}

# ---------------------------------------------------------------------------
# mk_tmpworkdir
# ---------------------------------------------------------------------------
@test "H23: mk_tmpworkdir returns a fresh writable dir under BATS_TMPDIR" {
  d1="$(mk_tmpworkdir)"
  d2="$(mk_tmpworkdir)"
  [ -d "$d1" ] && [ -d "$d2" ]
  [ "$d1" != "$d2" ]
  printf 'x' > "$d1/f"
  [ -f "$d1/f" ]
  case "$d1" in
    "${BATS_TMPDIR%/}"/*) ;;
    *) fail "mk_tmpworkdir escaped BATS_TMPDIR: $d1" ;;
  esac
}
