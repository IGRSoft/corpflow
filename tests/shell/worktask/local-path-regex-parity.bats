#!/usr/bin/env bats
# The absolute-host-path prefix rule is a BLOCKING strip in publish-pl-issue-lib.sh
# sanitise_body and a read-back finding in pr-body-lint.sh. Two literals, one
# contract: a prefix added to only one of them makes the lint and the sanitiser
# disagree about the same body, which is the failure this pins.
# No network, no gh, no git push.
bats_require_minimum_version 1.5.0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SANITISER="skills/worktask/scripts/publish-pl-issue-lib.sh"
LINT="skills/worktask/scripts/pr-body-lint.sh"

# Both files carry the rule as a single awk ERE literal; extract the alternation
# body so incidental spacing around the predicate cannot mask a real divergence.
extract_alternation() {
  grep -oE '\\/\(Users\|[A-Za-z|]+\)\\/' "$1" | head -1
}

@test "parity: the mount-prefix alternation is identical in both guards" {
  a="$(extract_alternation "$PLUGIN_ROOT/$SANITISER")"
  b="$(extract_alternation "$PLUGIN_ROOT/$LINT")"
  [ -n "$a" ] || fail "no prefix alternation found in $SANITISER"
  [ -n "$b" ] || fail "no prefix alternation found in $LINT"
  [ "$a" = "$b" ] || fail "prefix alternation drifted: $SANITISER=$a  $LINT=$b"
}

@test "parity: exactly one copy of the alternation lives in each guard" {
  [ "$(grep -cE '\\/\(Users\|[A-Za-z|]+\)\\/' "$PLUGIN_ROOT/$SANITISER")" -eq 1 ]
  [ "$(grep -cE '\\/\(Users\|[A-Za-z|]+\)\\/' "$PLUGIN_ROOT/$LINT")" -eq 1 ]
}

@test "parity: the drive-letter rule is present in both guards" {
  grep -qE '\[A-Za-z\]:\\\\' "$PLUGIN_ROOT/$SANITISER"
  grep -qE '\[A-Za-z\]:\\\\' "$PLUGIN_ROOT/$LINT"
}

@test "parity: the mount prefixes the guards claim are the ones they strip" {
  local p
  for p in Users home tmp var opt etc root Volumes mnt media private srv; do
    printf 'Ref /%s/w/x.md here\n' "$p" > "$BATS_TEST_TMPDIR/one.md"
    run bash -c "PUBLISH_LIB_ONLY=1 . '$PLUGIN_ROOT/$SANITISER' --parity >/dev/null 2>&1; sanitise_body < '$BATS_TEST_TMPDIR/one.md'"
    [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ] || fail "sanitiser kept /$p/"
  done
}
