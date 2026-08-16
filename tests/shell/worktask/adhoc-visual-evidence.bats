#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/adhoc-visual-evidence.sh.
# Contracts (from header):
#   - --emit pr prints a "## Visual evidence" block, or NOTHING; exit 0 always
#   - skip-by-default: no path-class hit / no git / no base ref => empty stdout
#   - a .context/state.json carrying a worktask_id is refused (FN owns attachment)
#   - failure is never blocking: no operational path exits non-zero
#   - the manifest it writes satisfies attach-visual-evidence.sh --validate-manifest
#   - --detect emits {"visual_surface":bool,"files":N,"reason":"..."}
#   - the path-class vocabulary has ONE owner: detect-ui-change.sh --path-classes
#   - --self-test => "fail=0", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/adhoc-visual-evidence.sh"
DETECTOR="skills/worktask/scripts/detect-ui-change.sh"
ATTACHER="skills/worktask/scripts/attach-visual-evidence.sh"

# A repo shaped like a real PR: base commit on master, work on a feature branch.
mk_pr_repo() { # $1=path-to-add
  local d; d="$(mk_tmpworkdir)"
  git -C "$d" init -q -b master
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  printf 'a\n' > "$d/README.md"
  git -C "$d" add -A && git -C "$d" commit -qm base
  git -C "$d" checkout -q -b feature
  mkdir -p "$d/$(dirname "$1")"
  printf 'x\n' > "$d/$1"
  git -C "$d" add -A && git -C "$d" commit -qm work
  printf '%s' "$d"
}

@test "happy: a UI-touching diff emits a Visual evidence block" {
  local d; d="$(mk_pr_repo Views/app.css)"
  run env WORKSPACE_ROOT="$d" BASE_REF=master ASSET_HOST_MODE=none DRY_RUN=1 \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_line --index 0 "## Visual evidence"
}

@test "happy: a docs-only diff emits nothing and audits no_ui_surface" {
  local d; d="$(mk_pr_repo docs/guide.md)"
  run env WORKSPACE_ROOT="$d" BASE_REF=master bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
  run jq -e 'select(.action=="adhoc_visual_evidence") | .metadata.reason' \
    "$d/.context/logs/audit.jsonl"
  assert_output '"no_ui_surface"'
}

@test "edge: a worktask tree is refused so FN stays the only attacher" {
  local d; d="$(mk_pr_repo Views/app.css)"
  mkdir -p "$d/.context"
  printf '{"version":1,"worktask_id":"wid-real","run_index":0}' > "$d/.context/state.json"
  run env WORKSPACE_ROOT="$d" BASE_REF=master bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
  run jq -e 'select(.action=="adhoc_visual_evidence") | .metadata.reason' \
    "$d/.context/logs/audit.jsonl"
  assert_output '"worktask_path"'
}

@test "edge: ADHOC_SKIP=1 suppresses a run the heuristic gets wrong" {
  local d; d="$(mk_pr_repo Views/app.css)"
  run env WORKSPACE_ROOT="$d" BASE_REF=master ADHOC_SKIP=1 \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
}

@test "edge: the emitted manifest satisfies the attacher's own schema check" {
  local d; d="$(mk_pr_repo Views/app.css)"
  run env WORKSPACE_ROOT="$d" BASE_REF=master ASSET_HOST_MODE=none DRY_RUN=1 \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  local mf; mf="$(find "$d/.context/images" -name screenshots.md | head -1)"
  [ -n "$mf" ]
  run bash "$PLUGIN_ROOT/$ATTACHER" --validate-manifest "$mf"
  assert_success
}

@test "edge: rerunning replays the first emission instead of stacking captures" {
  local d; d="$(mk_pr_repo Views/app.css)"
  run env WORKSPACE_ROOT="$d" BASE_REF=master ASSET_HOST_MODE=none DRY_RUN=1 \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  local first="$output"
  run env WORKSPACE_ROOT="$d" BASE_REF=master ASSET_HOST_MODE=none DRY_RUN=1 \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output "$first"
  run bash -c "find '$d/.context/images' -type f -name 'dv-*' | wc -l | tr -d ' '"
  assert_output "1"
}

@test "failure: outside a git repo --emit is silent and still exits 0" {
  local d; d="$(mk_tmpworkdir)"
  run env WORKSPACE_ROOT="$d" bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
}

@test "failure: an unresolvable base ref never blocks the PR" {
  local d; d="$(mk_pr_repo Views/app.css)"
  git -C "$d" branch -D master >/dev/null 2>&1 || true
  run env WORKSPACE_ROOT="$d" BASE_REF=no-such-ref bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
}

@test "happy: --detect reports the visual surface as JSON" {
  local d; d="$(mk_pr_repo Views/app.css)"
  run env WORKSPACE_ROOT="$d" BASE_REF=master bash "$PLUGIN_ROOT/$SCRIPT" --detect
  assert_success
  local json="$output"
  run jq -r '.visual_surface' <<<"$json"
  assert_output "true"
  run jq -r '.files' <<<"$json"
  assert_output "1"
}

@test "edge: the path-class vocabulary is read from detect-ui-change, not copied" {
  run bash "$PLUGIN_ROOT/$DETECTOR" --path-classes
  assert_success
  refute_output ""
  # A literal second copy of the regex in the ad-hoc script would let the two
  # detectors disagree about what counts as UI.
  run grep -cF "$output" "$PLUGIN_ROOT/$SCRIPT"
  assert_output "0"
}

@test "failure: a bad mode is a caller error (exit 1), not a silent skip" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --emit issue
  assert_failure
}

@test "self-test: built-in fixtures pass" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}
