#!/usr/bin/env bats
# Asserted contracts for skills/worktask/scripts/pr-body-lint.sh:
#   - exit 0 on a clean body, and on findings while warn-only (the default)
#   - exit 1 on findings under --strict / CORPFLOW_PR_BODY_STRICT=1
#   - exit 2 on usage errors (unknown flag, --body missing or nonexistent)
#   - P1 fires on a BACKTICK-WRAPPED local path — the shape that defeated the
#     sanitiser's own anchors and reached a published PR
#   - P2 fires when a Visual evidence section carries no inline image
#   - findings go to stderr; the summary line goes to stdout
#   - the lint self-disables under batch/incident routing
# No network, no gh, no git push.
bats_require_minimum_version 1.5.0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/pr-body-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  CLEAN="$WD/clean.md"
  cat > "$CLEAN" << 'EOF'
## Motivation
Because it was broken.

## Changes
- fixed the thing

## Test plan
- ran the suite

Closes #12
EOF
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

@test "failure: unknown argument exits 2 (usage)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
}

# A usage error printing help on stdout reads as ordinary output to a caller running
# this under the house `; true` / pipe convention — the exit-2 diagnostic on stderr
# never gets reconciled with it.
@test "contract: a usage ERROR writes nothing to stdout" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
  [ -z "$output" ]
  [[ "$stderr" == *"unknown argument: --bogus"* ]]
  [[ "$stderr" == *"pr-body-lint.sh"* ]]
}

@test "contract: an explicit --help still writes to stdout" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --help
  assert_failure 2
  [[ "$output" == *"pr-body-lint.sh"* ]]
}

@test "failure: --body missing exits 2 (usage)" {
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 2
}

@test "failure: --body pointing at a nonexistent file exits 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$WD/does-not-exist.md"
  assert_failure 2
}

@test "happy: a clean body reports clean and exits 0" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_success
  assert_output --partial "pr-body-lint: clean"
}

@test "P1: a backtick-wrapped .context/ path is caught (the shipped defect)" {
  printf 'Manifest: `.context/images/x/screenshots.md`\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_success
  assert_output --partial "warn: P1"
  assert_output --partial ".context/images/x/screenshots.md"
}

@test "P1: a backtick-wrapped absolute host path is caught" {
  printf 'See `/Users/me/private/notes.md` for detail.\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_output --partial "warn: P1"
}

@test "P2: a Visual evidence section with no inline image is caught" {
  printf '\n## Visual evidence\n\nScreenshots persisted on disk.\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_output --partial "warn: P2"
}

@test "P2: a Visual evidence section WITH an https image stays clean" {
  printf '\n## Visual evidence\n\n![dv-01 shot](https://github.com/user-attachments/assets/a1)\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_success
  assert_output --partial "pr-body-lint: clean"
  refute_output --partial "warn: P2"
}

@test "P3: a relative image reference is caught" {
  printf '![shot](images/local.png)\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_output --partial "warn: P3"
}

@test "P4: a body missing the Test plan heading is caught" {
  printf '## Motivation\nx\n\n## Changes\n- y\n\nCloses #1\n' > "$WD/b.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$WD/b.md"
  assert_output --partial "warn: P4"
  assert_output --partial "Test plan"
}

@test "P4: a body with no Closes trailer is caught" {
  printf '## Motivation\nx\n\n## Changes\n- y\n\n## Test plan\n- z\n' > "$WD/b.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$WD/b.md"
  assert_output --partial "Closes #<N>"
}

@test "P5: an AI-attribution footer is caught" {
  printf 'Co-Authored-By: Claude <noreply@anthropic.com>\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_output --partial "warn: P5"
}

@test "edge: --strict promotes findings to a blocking exit 1" {
  printf 'Manifest: `.context/images/x/screenshots.md`\n' >> "$CLEAN"
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN" --strict
  assert_failure 1
  assert_output --partial "BLOCKED"
}

@test "edge: CORPFLOW_PR_BODY_STRICT=1 is equivalent to --strict" {
  printf 'Manifest: `.context/images/x/screenshots.md`\n' >> "$CLEAN"
  run env CORPFLOW_PR_BODY_STRICT=1 bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_failure 1
}

@test "edge: --strict on a clean body still exits 0" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN" --strict
  assert_success
}

@test "contract: findings go to stderr, the summary to stdout" {
  printf 'Manifest: `.context/images/x/screenshots.md`\n' >> "$CLEAN"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --body "$CLEAN"
  assert_success
  assert_output --partial "warn-only"
  refute_output --partial "warn: P1"
  [[ "$stderr" == *"warn: P1"* ]]
}

@test "edge: batch routing self-disables the lint (MILESTONE_MODE)" {
  mkdir -p "$WD/.context"
  printf '{"version":1,"worktask_id":"w","run_index":0,"metadata":{"milestone":1},"tasks":{},"facts":{}}\n' \
    > "$WD/.context/state.json"
  printf 'Manifest: `.context/images/x/screenshots.md`\n' >> "$CLEAN"
  run env MILESTONE_MODE=1 bash "$PLUGIN_ROOT/$SCRIPT" \
    --body "$CLEAN" --state "$WD/.context/state.json" --context "$WD/.context" --strict
  assert_success
  assert_output --partial "skipped"
}

@test "regression: the exact OV-161 body flags BOTH the leak and the missing images" {
  cat > "$WD/ov161.md" << 'EOF'
## Motivation
Rework the results UI.

## Changes
- extracted the report body

## Test plan
- ran the UI suite

## Visual evidence

Screenshots persisted on disk; inline hosting unavailable — see manifest.

Manifest: `.context/images/ov-161-skin-analysis-results-ui/screenshots.md`

Closes #161
EOF
  run bash "$PLUGIN_ROOT/$SCRIPT" --body "$WD/ov161.md"
  assert_success
  assert_output --partial "warn: P1"
  assert_output --partial "warn: P2"
  assert_output --partial "2 finding(s)"
}
