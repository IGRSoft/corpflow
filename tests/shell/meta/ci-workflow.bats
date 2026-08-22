#!/usr/bin/env bats
# tests/shell/meta/ci-workflow.bats
# Target: .github/workflows/test.yml
#
# A workflow cannot be executed offline, so its *content* is the invariant under
# test: the permission surface, the action pinning, and the four lint invocation
# modes. Each of these fails silently in the direction of a weaker gate — a
# dropped `2>&1` empties the skipped-phase summary, a bare cache-lint exits 2 for
# a usage error rather than a finding, and a widened `permissions:` block is
# invisible until it is abused.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

WORKFLOW=".github/workflows/test.yml"

setup() {
  WF="$PLUGIN_ROOT/$WORKFLOW"
  [ -f "$WF" ] || fail "missing workflow: $WORKFLOW"
}

@test "the workflow exists and declares both required jobs" {
  run grep -Eq '^jobs:' "$WF"
  assert_success
  grep -Eq '^  test:' "$WF" || fail "no 'test' job"
  grep -Eq '^  lint:' "$WF" || fail "no 'lint' job"
}

@test "permissions are declared read-only at the top level" {
  # A workflow with no `permissions:` block inherits the repository default,
  # which may be read-write; absence is the failure, not just a wrong value.
  run grep -Eq '^permissions:' "$WF"
  assert_success
  run grep -Eq '^  contents: read$' "$WF"
  assert_success
  # No job may widen it back.
  run grep -Eq 'contents: (write|read-all)|permissions: write-all' "$WF"
  assert_failure
}

@test "the workflow references no repository secret" {
  run grep -n 'secrets\.' "$WF"
  assert_failure
}

@test "every third-party action is pinned to a major version" {
  local line
  while IFS= read -r line; do
    [[ "$line" =~ @v[0-9]+ ]] || fail "unpinned action: $line"
  done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$WF")
  # Non-vacuity: at least one `uses:` must exist for the loop to mean anything.
  run grep -cE '^[[:space:]]*-?[[:space:]]*uses:' "$WF"
  assert_success
  [ "$output" -ge 1 ]
}

@test "actions/checkout is the only third-party action" {
  local uses
  uses="$(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$WF" \
    | sed -E 's#.*uses:[[:space:]]*##; s#@.*##' | sort -u)"
  [ "$uses" = "actions/checkout" ] || fail "unexpected actions: $uses"
}

@test "the test job runs the deterministic entry point with selection disabled" {
  # Selection is never the required check: a scoped run can be green while the
  # full suite is red.
  run grep -Eq 'CORPFLOW_TEST_SELECT: "0"' "$WF"
  assert_success
  run grep -Eq '\./run-tests\.sh' "$WF"
  assert_success
}

@test "the piped suite step declares shell: bash, so pipefail applies" {
  # The implicit default shell on Linux is `bash -e {0}`; -o pipefail is added ONLY
  # when `shell: bash` is written out. Without it the step exits with tee's status —
  # always 0 — and a red suite reports green, which is the whole gate.
  #
  # The match must be a real YAML key, anchored and terminated: prose mentioning
  # `shell: bash` (this file's own comments do) would otherwise satisfy it, and the
  # window must close at the next step or the following step's key answers for it.
  local found
  found="$(awk '
    /^[[:space:]]*-[[:space:]]+name:/ { inblock = ($0 ~ /full deterministic suite/) }
    inblock && /^[[:space:]]*shell:[[:space:]]*bash[[:space:]]*$/ { print "yes" }' "$WF")"
  [ "$found" = "yes" ] || fail "the suite step must declare 'shell: bash' or the pipeline status is lost"
}

@test "every piped run: step declares shell: bash" {
  # Generalises the assertion above: any future `|` in a run: body inherits the same
  # trap, so the check is on the shape, not on one known step.
  local bad
  bad="$(awk '
    /^[[:space:]]*-[[:space:]]/                            { step = $0; shell = 0; inrun = 0 }
    /^[[:space:]]*shell:[[:space:]]*bash[[:space:]]*$/     { shell = 1 }
    /^[[:space:]]*run:/                                    { inrun = 1 }
    # `run: |` is the YAML block indicator, not a shell pipe.
    inrun && /\|/ && $0 !~ /run:[[:space:]]*\|[[:space:]]*$/ {
      if (!shell) { print step; shell = 1 }
    }' "$WF")"
  [ -z "$bad" ] || fail "piped run: step(s) without shell: bash:$bad"
}

@test "the suite step merges stderr into the tee'd log" {
  # run-tests.sh prints SKIPPED PHASES to stderr. Without 2>&1 the summary step
  # below produces an empty block that reads as 'everything ran'.
  run grep -Eq '\./run-tests\.sh 2>&1 \| tee run-tests\.log' "$WF"
  assert_success
}

@test "the skipped-phase summary reads the log and never emits an empty block" {
  run grep -q 'SKIPPED PHASES:' "$WF"
  assert_success
  run grep -q 'GITHUB_STEP_SUMMARY' "$WF"
  assert_success
  # The `grep . || echo` fallback is what turns "no output" into a visible line
  # rather than a blank block that reads as "everything ran".
  grep -qF "awk '/SKIPPED PHASES:/{f=1} f' run-tests.log | grep ." "$WF" \
    || fail "the summary must filter the awk output through grep ."
  grep -qF "|| echo 'none" "$WF" || fail "missing empty-summary fallback"
}

@test "all four lint scripts are invoked, each in its exact mode" {
  # A lint runs against its real subject where this repo holds one, and against
  # its built-in fixtures where it does not. cache-lint and pr-body-lint exit 2
  # when invoked bare, so a bare call would fail the job for a usage error.
  grep -Eq 'bash skills/worktask/scripts/desc-lint\.sh[[:space:]]*$' "$WF" \
    || fail "desc-lint must run bare (repo subject)"
  grep -Eq 'bash skills/worktask/scripts/section-lint\.sh[[:space:]]*$' "$WF" \
    || fail "section-lint must run bare (repo subject)"
  grep -Eq 'bash skills/worktask/scripts/cache-lint\.sh --self-test[[:space:]]*$' "$WF" \
    || fail "cache-lint must run --self-test"
  grep -Eq 'bash skills/worktask/scripts/pr-body-lint\.sh --self-test[[:space:]]*$' "$WF" \
    || fail "pr-body-lint must run --self-test"
}

@test "the lint steps all report on a single run" {
  # Without if: always() the first red lint hides the other three, turning one
  # run into four sequential fix-push cycles.
  local always
  always="$(grep -c 'if: always()' "$WF")"
  [ "$always" -ge 4 ] || fail "expected >=4 'if: always()' steps, found $always"
}

@test "the section-length lint is blocking, never advisory" {
  run grep -q 'continue-on-error' "$WF"
  assert_failure
}

@test "concurrency cancels superseded PR runs only" {
  run grep -q 'cancel-in-progress' "$WF"
  assert_success
  run grep -Eq "cancel-in-progress: \\\$\{\{ github.event_name == 'pull_request' \}\}" "$WF"
  assert_success
}

@test "bootstrap is never invoked — it hard-exits without a Swift toolchain" {
  run grep -q 'make bootstrap' "$WF"
  assert_failure
}
