#!/usr/bin/env bats
# skills/worktask/scripts/autonomy-preflight.sh — every human dependency an unattended
# run would hit, reported in one message before the seed, then recorded after it.
# No network and no host config: gh, git, npx, xcrun, xcodebuild, swift and plutil are
# stubs; settings, MCP config and plugin list are fixtures; HOME is a temp dir.
bats_require_minimum_version 1.5.0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/autonomy-preflight.sh"
SCAN="skills/worktask/scripts/preflight-issue-scan.sh"
SCRUB="skills/shared/scripts/path-scrub.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  WD="$(cd "$WD" && pwd -P)"
  BIN="$WD/bin"
  mkdir -p "$BIN" "$WD/proj" "$WD/cfg" "$WD/tmp" "$WD/home" "$WD/browsers"
  ln -s "$(command -v jq)" "$BIN/jq"

  cat > "$BIN/gh" << 'EOS'
#!/bin/sh
printf '%s\n' "gh $*" >> "${STUB_LOG:-/dev/null}"
case "$1" in
  auth) exit "${GH_AUTH_EXIT:-0}" ;;
  repo) printf '{"viewerPermission":"%s"}\n' "${GH_PERM:-WRITE}" ;;
  issue)
    if [ "$4" = "closed" ]; then echo '[]'; else cat "${ISSUES_JSON:?}"; fi ;;
esac
exit 0
EOS
  cat > "$WD/git-stub" << 'EOS'
#!/bin/sh
printf '%s\n' "git $*" >> "${STUB_LOG:-/dev/null}"
case "$1" in
  rev-parse) if [ "$2" = "--show-toplevel" ]; then pwd; else echo origin/main; fi ;;
  symbolic-ref) echo main ;;
  push) exit "${GIT_PUSH_EXIT:-0}" ;;
esac
exit 0
EOS
  printf '#!/bin/sh\nexit 0\n' > "$BIN/silicon"
  printf '#!/bin/sh\nexit 1\n' > "$BIN/npx"
  chmod +x "$BIN/gh" "$WD/git-stub" "$BIN/silicon" "$BIN/npx"

  printf '%s' '{"permissions":{"allow":["Bash(gh pr merge:*)","Bash(git reset --hard:*)"]}}' > "$WD/cfg/allow.json"
  printf '%s' '{"permissions":{"allow":["Bash(gh pr list:*)"]}}' > "$WD/cfg/no-merge.json"
  printf '%s' '{}' > "$WD/cfg/mcp.json"
  printf '%s' '{}' > "$WD/cfg/plugins.json"
  SETTINGS="$WD/cfg/allow.json"
  cd "$WD/proj"
}

# _pf [VAR=val ...] -- <script args>
_pf() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  run --separate-stderr env -u WORKSPACE_ROOT -u MILESTONE_MODE -u CLAUDE_CONFIG_DIR \
    -u ANDROID_HOME -u ANDROID_SDK_ROOT \
    PATH="$BIN:/usr/bin:/bin" HOME="$WD/home" TMPDIR="$WD/tmp" \
    GH_BIN="$BIN/gh" GIT_BIN="$WD/git-stub" CLAUDE_PROJECT_DIR="$WD/proj" \
    AUTONOMY_PREFLIGHT_SETTINGS="$SETTINGS" AUTONOMY_PREFLIGHT_TIMEOUT=5 \
    AUTONOMY_PREFLIGHT_MCP_CONFIGS="$WD/cfg/mcp.json" \
    AUTONOMY_PREFLIGHT_PLUGINS_FILE="$WD/cfg/plugins.json" \
    PLAYWRIGHT_BROWSERS_PATH="$WD/browsers" DEVELOPER_DIR="$WD/dev" \
    ${envs[@]+"${envs[@]}"} bash "$PLUGIN_ROOT/$SCRIPT" "$@"
}

_block() { printf '%s\n' "$output" | awk '/^preflight_failures=/ { on = 1 } /^result_json=/ { on = 0 } on'; }
_entries() { _block | grep -c '^  - \[' || true; }
_rj() { printf '%s\n' "$output" | sed -n 's/^result_json=//p' | tail -n 1; }

_no_context_anywhere() {
  local hit
  hit="$(find "$WD" "$@" -name .context -print 2> /dev/null | head -n 1)"
  [ -z "$hit" ] || fail "a .context/ appeared at $hit"
}

_ledger() {
  mkdir -p "$WD/ctx"
  printf '%s' '{"version":2,"worktask_id":"wt-pf","tasks":{},"metadata":{"base_ref":"develop"}}' > "$WD/ctx/state.json"
}

# An apple host whose only defect is one SDKSettings.plist that fails plutil -lint.
_apple_host() {
  local sdk="$WD/dev/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.0.sdk"
  mkdir -p "$sdk"
  printf 'not a plist' > "$sdk/SDKSettings.plist"
  cat > "$BIN/xcrun" << 'EOS'
#!/bin/sh
case "$1" in
  simctl) echo '-- iOS 18.0 --'; echo '    iPhone 16 (0A1B2C3D-0000-0000-0000-000000000000) (Shutdown)' ;;
  swift) echo 'Apple Swift version 6.0 (swiftlang-6.0.0.9.10)' ;;
esac
exit 0
EOS
  printf '#!/bin/sh\necho "Apple Swift version 6.0 (swiftlang-6.0.0.9.10)"\n' > "$BIN/swift"
  printf '#!/bin/sh\nexit 0\n' > "$BIN/xcodebuild"
  printf '#!/bin/sh\n[ "$1" = "-lint" ] && grep -q "<plist" "$2"\n' > "$BIN/plutil"
  chmod +x "$BIN/xcrun" "$BIN/swift" "$BIN/xcodebuild" "$BIN/plutil"
  printf '%s' '{"mcpServers":{"XcodeBuildMCP":{"command":"npx"}}}' > "$WD/cfg/mcp.json"
  printf '%s' '{"version":2,"plugins":{"apple-developer@apple-developer":[{}]}}' > "$WD/cfg/plugins.json"
}

# --- usage ------------------------------------------------------------------------

@test "AC-6: an unknown --accept-absent token exits 2 before any probe runs" {
  _pf STUB_LOG="$WD/stub.log" -- --auto plan --platform web --accept-absent bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ] || fail "stdout must be empty, got: $output"
  [ ! -s "$WD/stub.log" ] || fail "a probe ran: $(cat "$WD/stub.log")"
}

@test "usage: --auto and --platform are required, and --record refuses check flags" {
  _pf -- --platform web
  [ "$status" -eq 2 ]
  _pf -- --auto plan
  [ "$status" -eq 2 ]
  _pf -- --record "$WD/x" --context "$WD/ctx" --auto plan
  [ "$status" -eq 2 ]
}

@test "skip: --auto without plan or finalization, or a milestone run, probes nothing" {
  _pf STUB_LOG="$WD/stub.log" -- --auto decision --platform web
  assert_success
  assert_output --partial "reason=not_unattended"
  _pf STUB_LOG="$WD/stub.log" MILESTONE_MODE=1 -- --auto "[plan, finalization]" --platform web
  assert_success
  assert_output --partial "reason=milestone_mode"
  [ ! -s "$WD/stub.log" ]
}

# --- verdicts ---------------------------------------------------------------------

@test "pass: every grant and the renderer present yields one v1 pass record" {
  _pf -- --auto plan,finalization --platform backend
  assert_success
  refute_output --partial "preflight_failures="
  run jq -e '.version == 1 and .result == "pass" and .platforms == ["backend"]
    and (.checks | map(.id) | index("gh-pr-merge") != null)
    and .tools_absent == []' <<< "$(_rj)"
  assert_success
  _no_context_anywhere
}

@test "AC-1: clean git repo, READ permission, no merge rule -> exit 1 and no .context" {
  local repo
  repo="$(mk_git_fixture --file 'a.txt:hi' --commit 'init')"
  repo="$(cd "$repo" && pwd -P)"
  cd "$repo"
  SETTINGS="$WD/cfg/no-merge.json"
  _pf GIT_BIN=git GH_PERM=READ CLAUDE_PROJECT_DIR="$repo" -- --auto plan --platform backend
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^preflight_failures=')" -eq 1 ]
  _block | grep -q 'gh-pr-merge' || fail "merge grant missing from the block"
  _block | grep -q 'repository permission is READ' || fail "READ permission missing from the block"
  _block | grep -qF '"Bash(gh pr merge:*)"' || fail "the exact rule to add is not printed"
  [ ! -e "$repo/.context" ]
  _no_context_anywhere "$repo"
}

@test "AC-3: merge grant, Playwright and SDK lint land in exactly one block" {
  _apple_host
  SETTINGS="$WD/cfg/no-merge.json"
  _pf -- --auto plan --platform web,apple
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^preflight_failures=')" -eq 1 ]
  [ "$(_entries)" -eq 3 ] || fail "want 3 entries, got: $(_block)"
  _block | grep -q '\] gh-pr-merge:' || fail "merge grant not named"
  _block | grep -q '\] playwright:' || fail "playwright not named"
  _block | grep -q '\] apple-sdk-settings:.*iPhoneOS18.0.sdk' || fail "lint failure not named"
  _block | grep -qF -- '--accept-absent playwright' || fail "the opt-out is not offered"
  run jq -e '.result == "fail"
    and .tools_absent == [{"tool":"playwright","platform":"web","accepted":false}]' <<< "$(_rj)"
  assert_success
  _no_context_anywhere
}

@test "AC-3: --accept-absent playwright drops it from the block and the exit stays 1" {
  _apple_host
  SETTINGS="$WD/cfg/no-merge.json"
  _pf -- --auto plan --platform web,apple --accept-absent playwright
  [ "$status" -eq 1 ]
  [ "$(_entries)" -eq 2 ] || fail "want 2 entries, got: $(_block)"
  _block | grep -q '\] gh-pr-merge:'
  _block | grep -q '\] apple-sdk-settings:'
  if _block | grep -qi playwright; then fail "playwright still named: $(_block)"; fi
  refute_output --partial "accepted_absent="
}

@test "AC-6: accepted absent Playwright passes and --record stores exactly that entry" {
  _ledger
  _pf -- --auto plan --platform web --accept-absent playwright
  assert_success
  assert_line "accepted_absent=playwright"
  local buf="$WD/tmp/corpflow-preflight.ac6"
  printf '%s\n' "$output" > "$buf"

  run bash "$PLUGIN_ROOT/$SCRIPT" --record "$buf" --context "$WD/ctx"
  assert_success
  run jq -e '.metadata.preflight.version == 1 and (.metadata.preflight.tools_absent | type == "array")
    and .metadata.base_ref == "develop"' "$WD/ctx/state.json"
  assert_success
  run jq -c '.metadata.preflight.tools_absent' "$WD/ctx/state.json"
  assert_output '[{"tool":"playwright","platform":"web","accepted":true}]'
  run jq -se 'map(select(.action == "autonomy_preflight")) | length == 1
    and (.[0].metadata.result == "pass")' "$WD/ctx/logs/audit.jsonl"
  assert_success
  [ ! -e "$buf" ] || fail "--record left its own buffer behind"
}

@test "AC-6: without the flag the same host fails, and --record refuses to write it" {
  _ledger
  _pf -- --auto plan --platform web
  [ "$status" -eq 1 ]
  _block | grep -q '\] playwright:'
  printf '%s\n' "$output" > "$WD/tmp/corpflow-preflight.fail"
  cp "$WD/ctx/state.json" "$WD/before.json"
  run bash "$PLUGIN_ROOT/$SCRIPT" --record "$WD/tmp/corpflow-preflight.fail" --context "$WD/ctx"
  [ "$status" -eq 1 ]
  cmp -s "$WD/ctx/state.json" "$WD/before.json" || fail "a failing preflight reached the ledger"
  [ ! -e "$WD/ctx/logs/audit.jsonl" ]
}

# --- renderer binaries --------------------------------------------------------------

# Removes the silicon stub; skips when the fixed PATH tail still holds a real renderer.
_no_renderer() {
  local t
  rm -f "$BIN/silicon"
  for t in silicon magick convert; do
    if PATH="/usr/bin:/bin" command -v "$t" > /dev/null 2>&1; then
      skip "host has $t on /usr/bin:/bin"
    fi
  done
}

@test "renderer: absent binaries fail with one entry each and offer --accept-absent renderer" {
  _no_renderer
  _pf -- --auto plan --platform systems
  [ "$status" -eq 1 ]
  [ "$(_entries)" -eq 1 ] || fail "want 1 entry, got: $(_block)"
  _block | grep -q '\] renderer: no silicon, magick or convert on PATH$'
  _block | grep -qF -- '--accept-absent renderer'
  run jq -ce '.tools_absent' <<< "$(_rj)"
  assert_output '[{"tool":"silicon","platform":"systems","accepted":false},{"tool":"magick","platform":"systems","accepted":false},{"tool":"convert","platform":"systems","accepted":false}]'
}

@test "AC-6: --accept-absent renderer passes and --record stores one entry per binary" {
  _no_renderer
  _ledger
  _pf -- --auto plan --platform backend --accept-absent renderer
  assert_success
  assert_line "accepted_absent=silicon,magick,convert"
  printf '%s\n' "$output" > "$WD/tmp/corpflow-preflight.r6"
  run bash "$PLUGIN_ROOT/$SCRIPT" --record "$WD/tmp/corpflow-preflight.r6" --context "$WD/ctx"
  assert_success
  run jq -e '.metadata.preflight.tools_absent == [
    {"tool":"silicon","platform":"backend","accepted":true},
    {"tool":"magick","platform":"backend","accepted":true},
    {"tool":"convert","platform":"backend","accepted":true}]' "$WD/ctx/state.json"
  assert_success
}

@test "renderer: binary names accept one at a time, and a partial list still fails" {
  _no_renderer
  _pf -- --auto plan --platform backend --accept-absent silicon
  [ "$status" -eq 1 ]
  _block | grep -q '\] renderer: .*not accepted: magick,convert'
  _pf -- --auto plan --platform backend --accept-absent silicon,magick,convert
  assert_success
  run jq -e '.tools_absent | map(.tool) == ["silicon","magick","convert"] and all(.accepted)' <<< "$(_rj)"
  assert_success
}

# --- permission rules -------------------------------------------------------------

@test "rules: prefix, space-star, broader prefixes and bare Bash satisfy the merge grant" {
  local rule
  for rule in 'Bash(gh pr merge:*)' 'Bash(gh pr merge *)' 'Bash(gh pr:*)' 'Bash(gh:*)' 'Bash(gh *)' 'Bash'; do
    printf '{"permissions":{"allow":[%s]}}' "$(jq -Rn --arg r "$rule" '$r')" > "$WD/cfg/rule.json"
    SETTINGS="$WD/cfg/rule.json"
    _pf -- --auto plan --platform backend
    [ "$status" -eq 0 ] || fail "rule $rule did not satisfy the merge grant: $output"
  done
}

@test "rules: an exact rule without arguments and an unrelated prefix do not count" {
  local rule
  for rule in 'Bash(gh pr merge)' 'Bash(gh pr list:*)' 'Bash(ghx:*)'; do
    printf '{"permissions":{"allow":[%s]}}' "$(jq -Rn --arg r "$rule" '$r')" > "$WD/cfg/rule.json"
    SETTINGS="$WD/cfg/rule.json"
    _pf -- --auto plan --platform backend
    [ "$status" -eq 1 ] || fail "rule $rule wrongly satisfied the merge grant"
    _block | grep -q '\] gh-pr-merge:'
  done
}

@test "rules: a deny rule fails git-push even though the dry-run probe succeeds" {
  printf '%s' '{"permissions":{"allow":["Bash(gh pr merge:*)"],"deny":["Bash(git push:*)"]}}' > "$WD/cfg/deny.json"
  SETTINGS="$WD/cfg/deny.json"
  _pf -- --auto finalization --platform backend
  [ "$status" -eq 1 ]
  [ "$(_entries)" -eq 1 ]
  _block | grep -q '\] git-push: deny rule "Bash(git push:\*)"'
  _block | grep -q 'fix: remove the deny rule'
}

@test "rules: an ask rule is a prompt nobody answers, so it fails the grant" {
  printf '%s' '{"permissions":{"allow":["Bash(gh pr merge:*)"],"ask":["Bash(gh pr merge:*)"]}}' > "$WD/cfg/ask.json"
  SETTINGS="$WD/cfg/ask.json"
  _pf -- --auto plan --platform backend
  [ "$status" -eq 1 ]
  _block | grep -q '\] gh-pr-merge: ask rule'
}

@test "rules: bypassPermissions covers merge and reset, and managed disable revokes it" {
  printf '%s' '{"permissions":{"defaultMode":"bypassPermissions"}}' > "$WD/cfg/bypass.json"
  printf '%s' '{"permissions":{"disableBypassPermissionsMode":"disable"}}' > "$WD/cfg/managed.json"
  SETTINGS="$WD/cfg/bypass.json"
  _pf -- --auto plan --platform backend --harness
  assert_success
  SETTINGS="$WD/cfg/bypass.json:$WD/cfg/managed.json"
  _pf -- --auto plan --platform backend --harness
  [ "$status" -eq 1 ]
  _block | grep -q '\] gh-pr-merge:'
  _block | grep -q '\] git-reset-hard:'
  _block | grep -qF '"Bash(git reset --hard:*)"'
}

@test "rules: a linked worktree reads only its own project settings, never the main checkout's" {
  local main wt realgit
  main="$(mk_git_fixture --file 'a.txt:hi' --commit 'init')"
  main="$(cd "$main" && pwd -P)"
  wt="$WD/wt"
  git -C "$main" worktree add -q -b wt "$wt" 2> /dev/null || fail "git worktree add failed"
  mkdir -p "$main/.claude" "$wt/.claude"
  printf '%s' '{"permissions":{"allow":["Bash(gh pr merge:*)","Bash(git reset --hard:*)"]}}' \
    > "$main/.claude/settings.local.json"
  # _pf points DEVELOPER_DIR at a fixture, which breaks the macOS /usr/bin/git shim,
  # so the real binary from git's exec path goes first on PATH for the resolver too.
  realgit="$(git --exec-path)/git"
  [ -x "$realgit" ] || realgit="$(command -v git)"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$realgit" > "$BIN/git"
  chmod +x "$BIN/git"
  cd "$wt"

  _pf CLAUDE_PROJECT_DIR= AUTONOMY_PREFLIGHT_SETTINGS= GIT_BIN="$BIN/git" \
    -- --auto plan --platform backend
  [ "$status" -eq 1 ]
  if _block | grep -q 'not inside a git repository'; then fail "fixture not seen as a checkout: $output"; fi
  _block | grep -q '\] gh-pr-merge:' || fail "a main-checkout grant satisfied the worktree check: $output"

  cp "$main/.claude/settings.local.json" "$wt/.claude/settings.local.json"
  _pf CLAUDE_PROJECT_DIR= AUTONOMY_PREFLIGHT_SETTINGS= GIT_BIN="$BIN/git" \
    -- --auto plan --platform backend
  if _block | grep -q '\] gh-pr-merge:'; then fail "the worktree's own grant was not read: $output"; fi
}

@test "probes: a failed push and a missing gh login both surface in the same block" {
  _pf GIT_PUSH_EXIT=128 GH_AUTH_EXIT=1 -- --auto plan --platform backend
  [ "$status" -eq 1 ]
  [ "$(_entries)" -eq 2 ]
  _block | grep -q '\] git-push: git push --dry-run to origin failed'
  _block | grep -q 'fix: authenticate the GitHub CLI: gh auth login'
}

# --- record: candidates -----------------------------------------------------------

@test "AC-4: the Step 2a buffer becomes one scrubbed preflight_issue_candidates row" {
  _ledger
  mkdir -p "$WD/scanbin"
  printf '#!/bin/sh\n[ "$1" = remote ] && echo git@github.com:o/r.git\nexit 0\n' > "$WD/scanbin/git"
  chmod +x "$WD/scanbin/git"
  printf '%s' '[{"number":42,"title":"Duplicate GitHub issues opened by overlapping worktasks under /Users/alice/private/repo","url":"https://github.com/o/r/issues/42"}]' \
    > "$WD/issues.json"

  local scan="$WD/tmp/corpflow-issue-scan.ac4"
  env -u CORPFLOW_NONINTERACTIVE -u MILESTONE_MODE -u WORKSPACE_ROOT \
    PATH="$WD/scanbin:$BIN:/usr/bin:/bin" GH_BIN="$BIN/gh" ISSUES_JSON="$WD/issues.json" \
    bash "$PLUGIN_ROOT/$SCAN" --goal "Stop duplicate GitHub issues from open worktasks" \
    --context "$WD/proj/.context" < /dev/null > "$scan" 2> /dev/null
  grep -qx 'result=shown' "$scan" || fail "scan did not show the paraphrase: $(cat "$scan")"
  if grep -q '/Users/alice' "$scan"; then fail "scan leaked the host path"; fi

  _pf -- --auto plan --platform backend
  assert_success
  printf '%s\n' "$output" > "$WD/tmp/corpflow-preflight.ac4"
  run bash "$PLUGIN_ROOT/$SCRIPT" --record "$WD/tmp/corpflow-preflight.ac4" --context "$WD/ctx" --candidates "$scan"
  assert_success
  assert_line "recorded=preflight_issue_candidates"

  run jq -sc 'map(select(.action == "preflight_issue_candidates"))' "$WD/ctx/logs/audit.jsonl"
  run jq -e 'length == 1 and .[0].metadata.result == "shown"
    and (.[0].metadata.candidates[0] | keys == ["number","score","title","url"])
    and (.[0].metadata.candidates[0].title | contains("[local-path]"))' <<< "$output"
  assert_success
  if grep -q '/Users/alice' "$WD/ctx/logs/audit.jsonl"; then fail "the audit row kept the host path"; fi
  [ ! -e "$scan" ] || fail "--record left the scan buffer behind"
  _no_context_anywhere "$WD/proj"
}

@test "record: a hand-edited candidates buffer is scrubbed again before it is recorded" {
  _ledger
  _pf -- --auto plan --platform backend
  printf '%s\n' "$output" > "$WD/tmp/corpflow-preflight.re"
  printf '%s\n' 'result=shown' 'candidates=1' \
    'candidate={"number":7,"url":"https://github.com/o/r/issues/7","title":"see /home/bob/work/x","state":"open","score":3}' \
    > "$WD/tmp/cands.txt"
  run bash "$PLUGIN_ROOT/$SCRIPT" --record "$WD/tmp/corpflow-preflight.re" --context "$WD/ctx" --candidates "$WD/tmp/cands.txt"
  assert_success
  if grep -q '/home/bob' "$WD/ctx/logs/audit.jsonl"; then fail "raw host path recorded"; fi
  grep -q '\[local-path\]' "$WD/ctx/logs/audit.jsonl"
  [ -e "$WD/tmp/cands.txt" ] || fail "a buffer without the owned prefix must never be deleted"
}

@test "record: no state.json in the context means nothing is written or created" {
  mkdir -p "$WD/bare"
  _pf -- --auto plan --platform backend
  printf '%s\n' "$output" > "$WD/tmp/corpflow-preflight.bare"
  run bash "$PLUGIN_ROOT/$SCRIPT" --record "$WD/tmp/corpflow-preflight.bare" --context "$WD/bare"
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "$WD/bare")" ] || fail "record wrote into a context with no ledger"
  [ -e "$WD/tmp/corpflow-preflight.bare" ]
}

@test "contract: the scan and the record both reach $SCRUB" {
  grep -qF 'shared/scripts/path-scrub.sh' "$PLUGIN_ROOT/$SCAN"
  grep -qF 'shared/scripts/path-scrub.sh' "$PLUGIN_ROOT/$SCRIPT"
}

@test "contract: --self-test passes" {
  run env -u MILESTONE_MODE -u WORKSPACE_ROOT TMPDIR="$WD/tmp" bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "0 failed"
}

@test "contract: --self-test passes when invoked by relative path from the repo root" {
  run env -u MILESTONE_MODE -u WORKSPACE_ROOT TMPDIR="$WD/tmp" \
    bash -c 'cd "$1" && bash "$2" --self-test' _ "$PLUGIN_ROOT" "$SCRIPT"
  assert_success
  assert_output --partial "0 failed"
}
