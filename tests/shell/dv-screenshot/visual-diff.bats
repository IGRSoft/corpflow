#!/usr/bin/env bats
# tests/shell/dv-screenshot/visual-diff.bats
# Target: skills/dv-screenshot-capture/scripts/visual-diff.sh
# Covers: pass/fail verdict either side of the threshold, the boundary itself,
#         diff-artifact retention policy (pd2: keep only on fail), magick failure
#         → exit 3, missing reference → deferred exit 0, missing candidate →
#         exit 3, magick absent → deferred exit 0, missing args → exit 2.
#
# The `magick` double is behavioural, not `exit 0`: it replays a configurable
# `compare -metric RMSE` line on stderr (`<abs> (<normalized>)`) and returns
# ImageMagick's own convention (0 identical / 1 differs / >=2 error), so the
# script's parse → percent → verdict → artifact chain is actually exercised. An
# `exit 0` shim made every verdict test vacuous: with no metric on stderr the
# parser fell back to NORMALIZED=0 and every comparison "passed".
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/visual-diff.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/images/wt-test"
  printf '%s' '{"version":2,"worktask_id":"wt-test","tasks":{}}' > "$WD/.context/state.json"
  export WORKSPACE_ROOT="$WD"
  REF="$WD/reference.png"
  CAND="$WD/candidate.png"
  printf 'ref' > "$REF"
  printf 'cand' > "$CAND"
  # Behavioural magick double: RMSE_NORM is the normalized (0..1) metric the
  # real `magick compare -metric RMSE` prints in parentheses on stderr.
  stub_cmd magick --body '
if [ "${1:-}" = "compare" ]; then
  printf "%s (%s)\n" "${RMSE_ABS:-3212.7}" "${RMSE_NORM:-0.0100}" >&2
  # Fourth positional after the metric flags is the diff output path.
  for a in "$@"; do :; done
  printf "diff-bytes" > "$a"
  exit "${MAGICK_RC:-1}"
fi
exit 0'
}

diff_pngs() { ls "$WD/.context/images/wt-test/"diff-*.png 2>/dev/null | wc -l | tr -d ' '; }

# --- verdict chain ----------------------------------------------------------

@test "below threshold -> verdict=pass, audit ok, no diff artifact kept" {
  # 0.0100 normalized = 1.0000% against an 8% threshold.
  run_script_env --cwd "$WD" --stub-path --env RMSE_NORM=0.0100 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --threshold 8.0 \
    --worktask-id wt-test --slug diff-test
  assert_success
  assert_output --partial "verdict=pass"
  assert_output --partial "value=1.0000%"
  assert_output --partial "diff_path="
  refute_output --partial "diff_path=.context/images"
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --result ok --meta verdict=pass --meta diff_path= \
    --jq '.metadata.value_percent == 1.0' 
  [ "$(diff_pngs)" -eq 0 ]
}

@test "above threshold -> verdict=fail_visual_diff, diff PNG written and recorded" {
  # 0.2500 normalized = 25.0000% against an 8% threshold.
  run_script_env --cwd "$WD" --stub-path --env RMSE_NORM=0.2500 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --threshold 8.0 \
    --worktask-id wt-test --slug diff-test
  assert_success
  assert_output --partial "verdict=fail_visual_diff"
  assert_output --partial "value=25.0000%"
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --result ok --meta verdict=fail_visual_diff \
    --jq '.metadata.value_percent == 25.0' 
  [ "$(diff_pngs)" -eq 1 ]
  # The recorded diff_path must be the artifact that actually exists on disk.
  local recorded
  recorded="$(jq -r 'select(.action=="visual_diff_run") | .metadata.diff_path' \
    "$WD/.context/logs/audit.jsonl" | tail -1)"
  [ -n "$recorded" ]
  [ -f "$recorded" ]
  [[ "$recorded" == "$WD/.context/images/wt-test/"* ]]
}

@test "value exactly at the threshold is a pass (boundary is inclusive)" {
  # 0.0800 normalized = 8.0000% against an 8.0% threshold.
  run_script_env --cwd "$WD" --stub-path --env RMSE_NORM=0.0800 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --threshold 8.0 \
    --worktask-id wt-test --slug diff-test
  assert_success
  assert_output --partial "verdict=pass"
  assert_output --partial "value=8.0000%"
  [ "$(diff_pngs)" -eq 0 ]
}

@test "threshold flag is honoured: same metric flips verdict when it tightens" {
  run_script_env --cwd "$WD" --stub-path --env RMSE_NORM=0.0500 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --threshold 2.0 \
    --worktask-id wt-test --slug diff-test
  assert_success
  assert_output --partial "verdict=fail_visual_diff"
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --meta verdict=fail_visual_diff --jq '.metadata.threshold_percent == 2.0' 
}

@test "identical images (magick exit 0) still report a verdict" {
  run_script_env --cwd "$WD" --stub-path \
    --env RMSE_NORM=0 --env RMSE_ABS=0 --env MAGICK_RC=0 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --worktask-id wt-test --slug diff-test
  assert_success
  assert_output --partial "verdict=pass"
  assert_output --partial "value=0.0000%"
}

@test "magick error exit (>=2) -> exit 3 + audit reason=magick_invocation_failed" {
  run_script_env --cwd "$WD" --stub-path --env MAGICK_RC=2 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --worktask-id wt-test --slug diff-test
  [ "$status" -eq 3 ]
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --result error --meta reason=magick_invocation_failed --meta verdict=error
}

# --- degrade + argument paths ------------------------------------------------

@test "magick absent -> deferred exit 0 + audit reason=imagemagick_not_found" {
  # --hide rebuilds PATH from an allowlist farm without magick, so the result
  # does not depend on what the host happens to have in /usr/bin. The setup
  # double lives on $STUB_BIN, which --hide keeps ahead of the farm, so it has
  # to be removed for this one test.
  rm -f "$STUB_BIN/magick"
  run_script_env --cwd "$WD" --hide magick -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --worktask-id wt-test --slug diff-test
  assert_success
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --result deferred --meta reason=imagemagick_not_found --meta verdict=skipped
}

@test "reference not found -> deferred exit 0 + audit reason=reference_not_found" {
  run_script_env --cwd "$WD" --stub-path -- "$SCRIPT" \
    --reference "$WD/nonexistent-ref.png" --candidate "$CAND" \
    --worktask-id wt-test --slug diff-test
  assert_success
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --result deferred --meta reason=reference_not_found --meta verdict=skipped
  # Deferred before any comparison: magick must not have been invoked.
  [ "$(stub_log --count magick)" -eq 0 ]
}

@test "candidate not found -> exit 3 + audit reason=candidate_not_found" {
  run_script_env --cwd "$WD" --stub-path -- "$SCRIPT" \
    --reference "$REF" --candidate "$WD/nonexistent-cand.png" \
    --worktask-id wt-test --slug diff-test
  [ "$status" -eq 3 ]
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" \
    --result error --meta reason=candidate_not_found --meta verdict=error
  [ "$(stub_log --count magick)" -eq 0 ]
}

@test "missing required args -> exit 2 with usage on stderr, no audit row" {
  run_script_env --cwd "$WD" --stub-path --separate-stderr -- "$SCRIPT" \
    --worktask-id wt-test
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage: visual-diff.sh"* ]]
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" --absent
}


# DR0 P2-3. R6 moved this adapter's inline emitter into skills/shared/lib/audit-lib.sh
# and made the source block fail closed. Before that move "the emitter is missing" was
# not a reachable state; it is now, and on the capture adapters it takes down screenshot
# capture, which the DV screenshot gate blocks the pipeline on. These two arms declare
# that behaviour change and pin what an operator actually sees, which is NOT one code:
# the documented exit 2 is reached only when shared/lib exists but audit-lib.sh does
# not. When the directory itself is missing, the `cd ... && pwd -P` substitution fails
# first and errexit takes the script down with a bare exit 1 and no diagnostic.
@test "install: audit-lib.sh missing from an existing shared/lib -> exit 2, named diagnostic" {
  mkdir -p "$WD/inst/skills/dv-screenshot-capture/scripts" "$WD/inst/skills/shared/lib"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/inst/skills/dv-screenshot-capture/scripts/visual-diff.sh"
  cd "$WD"
  run --separate-stderr bash "$WD/inst/skills/dv-screenshot-capture/scripts/visual-diff.sh" \
    --worktask-id wt-test --reference "$REF" --candidate "$CAND"
  assert_failure 2
  [[ "$stderr" == *"plugin install broken"* ]]
  [[ "$stderr" == *"audit-lib.sh"* ]]
}

@test "install: an absent shared/lib degrades to a silent exit 1, not the documented 2" {
  # Pinned as observed, not as intended. The likelier partial-install shape gives an
  # operator no diagnostic at all; changing that is a follow-up, not this run.
  mkdir -p "$WD/lonely"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/lonely/visual-diff.sh"
  cd "$WD"
  run --separate-stderr bash "$WD/lonely/visual-diff.sh" \
    --worktask-id wt-test --reference "$REF" --candidate "$CAND"
  assert_failure 1
  [[ "$stderr" != *"plugin install broken"* ]]
}

# --- root resolution -----------------------------------------------------------

@test "root: an omitted --worktask-id is read from the ledger" {
  run_script_env --cwd "$WD" --stub-path --env RMSE_NORM=0.0100 -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --slug diff-test
  assert_success
  assert_audit_row visual_diff_run --file "$WD/.context/logs/audit.jsonl" --subject wt-test/diff-test
}

@test "root: a --worktask-id the ledger disagrees with exits 1 before any comparison" {
  run_script_env --cwd "$WD" --stub-path -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --worktask-id other --slug diff-test
  [ "$status" -eq 1 ]
  [ "$(stub_log --count magick)" -eq 0 ]
}

@test "root: no declared root exits 1 and creates no .context under cwd" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --stub-path --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --unset CONTEXT_DIR --env "GIT_CEILING_DIRECTORIES=$cwd" -- "$SCRIPT" \
    --reference "$REF" --candidate "$CAND" --worktask-id wt-test
  [ "$status" -eq 1 ]
  [ ! -e "$cwd/.context" ]
}
