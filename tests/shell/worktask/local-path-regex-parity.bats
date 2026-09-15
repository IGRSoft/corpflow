#!/usr/bin/env bats
# The absolute-host-path pattern is a BLOCKING line rule in publish-pl-issue-lib.sh
# sanitise_body and a read-back finding in pr-body-lint.sh. Both read it from one
# definition in skills/shared/scripts/path-scrub.sh. A second literal anywhere lets
# the sanitiser and the lint disagree about the same body, which is what this pins.
# No network, no gh, no git push.
bats_require_minimum_version 1.5.0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRUB="skills/shared/scripts/path-scrub.sh"
SANITISER="skills/worktask/scripts/publish-pl-issue-lib.sh"
LINT="skills/worktask/scripts/pr-body-lint.sh"
PREFLIGHT_CMDS="skills/worktask/scripts/fn-preflight-cmds.sh"

# The alternation body of the shared ERE, one prefix per line, read by sourcing the
# definition rather than by grepping it, so this follows whatever the file exports.
_prefixes() {
  bash -c '. "$1"; printf "%s\n" "$CORPFLOW_HOST_PATH_ERE"' _ "$PLUGIN_ROOT/$SCRUB" \
    | sed -E 's#^/\((.*)\)/$#\1#' | tr '|' '\n'
}

@test "single definition: only path-scrub.sh carries the mount alternation" {
  cd "$PLUGIN_ROOT"
  run grep -rlE '\(Users\|home\|tmp\|var\|opt\|etc\|root\|Volumes\|mnt\|media\|private\|srv\)' \
    skills hooks --include='*.sh'
  assert_output "$SCRUB"
  # A reordered or partial copy is still a second definition.
  run grep -rlE '\(Users\|[A-Za-z|]+\)' skills hooks --include='*.sh'
  assert_output "$SCRUB"
}

@test "single definition: only path-scrub.sh carries the drive-letter rule" {
  cd "$PLUGIN_ROOT"
  run grep -rlE '\[A-Za-z\]:\\\\' skills hooks --include='*.sh'
  assert_output "$SCRUB"
}

# Static half only: the path is assembled differently in each file, so this checks
# that each names it. The fail-closed cases below prove the lib and the lint load it.
@test "consumers: the sanitiser, the lint and the PR bridge name path-scrub.sh" {
  local f
  for f in "$SANITISER" "$LINT" "$PREFLIGHT_CMDS"; do
    grep -qF 'shared/scripts' "$PLUGIN_ROOT/$f" || fail "$f does not resolve skills/shared/scripts"
    grep -qF 'path-scrub.sh' "$PLUGIN_ROOT/$f" || fail "$f does not name path-scrub.sh"
  done
}

@test "consumers: the sanitiser and the lint read both EREs through ENVIRON, never awk -v" {
  local f
  for f in "$SANITISER" "$LINT"; do
    grep -qF 'ENVIRON["CORPFLOW_HOST_PATH_ERE"]' "$PLUGIN_ROOT/$f" || fail "$f: host ERE not read via ENVIRON"
    grep -qF 'ENVIRON["CORPFLOW_DRIVE_PATH_ERE"]' "$PLUGIN_ROOT/$f" || fail "$f: drive ERE not read via ENVIRON"
    if grep -nE -- '-v[[:space:]]*[A-Za-z_]+=[^ ]*CORPFLOW_(HOST|DRIVE)_PATH_ERE' "$PLUGIN_ROOT/$f"; then
      fail "$f passes a path ERE through awk -v"
    fi
  done
}

@test "parity: the pattern still claims every mount convention" {
  local p got
  got="$(_prefixes)"
  for p in Users home tmp var opt etc root Volumes mnt media private srv; do
    printf '%s\n' "$got" | grep -qx "$p" || fail "CORPFLOW_HOST_PATH_ERE lost /$p/"
  done
}

@test "parity: every claimed prefix is stripped by the sanitiser, bare or glued" {
  local p
  for p in $(_prefixes); do
    printf 'Ref /%s/w/x.md here\n' "$p" > "$BATS_TEST_TMPDIR/one.md"
    run bash -c "PUBLISH_LIB_ONLY=1 . '$PLUGIN_ROOT/$SANITISER' --parity >/dev/null 2>&1; sanitise_body < '$BATS_TEST_TMPDIR/one.md'"
    [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ] || fail "sanitiser kept /$p/"

    printf 'Ref (/%s/w/x.md) here\n' "$p" > "$BATS_TEST_TMPDIR/glued.md"
    run bash -c "PUBLISH_LIB_ONLY=1 . '$PLUGIN_ROOT/$SANITISER' --parity >/dev/null 2>&1; sanitise_body < '$BATS_TEST_TMPDIR/glued.md'"
    assert_output 'Ref ([local-path]) here'
  done
}

@test "parity: every claimed prefix is a P1 finding for the lint" {
  local p
  for p in $(_prefixes); do
    printf 'Ref `/%s/w/x.md`\n' "$p" > "$BATS_TEST_TMPDIR/lint.md"
    run --separate-stderr bash "$PLUGIN_ROOT/$LINT" --body "$BATS_TEST_TMPDIR/lint.md" \
      --state "$BATS_TEST_TMPDIR/no-state.json"
    [[ "$stderr" == *"warn: P1"* ]] || fail "lint missed /$p/: $stderr"
  done
}

@test "fail closed: the sanitiser library stops when path-scrub.sh is missing" {
  local tree="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree/skills/worktask/scripts"
  cp "$PLUGIN_ROOT/$SANITISER" "$tree/$SANITISER"
  run bash -c "PUBLISH_LIB_ONLY=1 . '$tree/$SANITISER'; echo reached"
  assert_failure 1
  assert_output --partial "path-scrub.sh unreachable"
  refute_output --partial "reached"
}

@test "fail closed: the lint exits 3 when path-scrub.sh is missing" {
  local tree="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$tree/skills/worktask/scripts"
  cp "$PLUGIN_ROOT/$LINT" "$PLUGIN_ROOT/skills/worktask/scripts/branch-lib.sh" "$tree/skills/worktask/scripts/"
  printf 'clean\n' > "$BATS_TEST_TMPDIR/body.md"
  run bash "$tree/$LINT" --body "$BATS_TEST_TMPDIR/body.md"
  assert_failure 3
  assert_output --partial "path-scrub.sh unreachable"
}
