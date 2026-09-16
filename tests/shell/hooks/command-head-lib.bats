#!/usr/bin/env bats
# Tests for hooks/lib/command-head-lib.sh: the bounds on what a committed audit row may
# keep of a shell command, and the assignment strip the test-execution gate shares.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="hooks/lib/command-head-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  WD="$(cd "$WD" && pwd -P)"
}

# ch <function> <command> [<match>]: the library's printed answer under `set -eu`, run
# from a directory with no git root so only CH_ROOT can rebase a path.
ch() {
  run env LIBF="${CH_LIB:-$PLUGIN_ROOT/$LIB}" FN="$1" CMD="$2" MATCH="${3:-}" \
    WORKSPACE_ROOT="${CH_ROOT:-}" \
    bash -c 'set -eu; cd "$0"; . "$LIBF"; "$FN" "$CMD" "$MATCH"' "$WD"
}

# chstate <command> [<match>]: head|targets,comma,joined|truncated|redaction.
chstate() {
  run env LIBF="${CH_LIB:-$PLUGIN_ROOT/$LIB}" CMD="$1" MATCH="${2:-}" \
    WORKSPACE_ROOT="${CH_ROOT:-}" \
    bash -c 'set -eu; cd "$0"; . "$LIBF"; audit_command_head "$CMD" "$MATCH" > /dev/null
      printf "%s|" "$AUDIT_COMMAND_HEAD"; printf "%s" "$AUDIT_TARGETS" | tr "\n" ","
      printf "|%s|%s" "$AUDIT_TARGETS_TRUNCATED" "$AUDIT_REDACTION"' "$WD"
}

# _isolated_lib <path-scrub body>: a copy of the library whose sibling path-scrub.sh
# holds that body, or is absent when the body is empty.
_isolated_lib() {
  mkdir -p "$WD/plug/hooks/lib"
  cp "$PLUGIN_ROOT/$LIB" "$WD/plug/hooks/lib/"
  rm -rf "$WD/plug/skills"
  if [ -n "$1" ]; then
    mkdir -p "$WD/plug/skills/shared/scripts"
    printf '%s\n' "$1" > "$WD/plug/skills/shared/scripts/path-scrub.sh"
  fi
  CH_LIB="$WD/plug/hooks/lib/command-head-lib.sh"
}

@test "load: executing the library directly is refused" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
}

@test "load: sourcing defines the three symbols and defers the path scrub" {
  run bash -c "set -eu; . '$PLUGIN_ROOT/$LIB'
    command -v strip_assignments audit_command_head audit_targets > /dev/null
    command -v corpflow_path_scrub > /dev/null && echo eager || echo lazy"
  assert_success
  assert_output lazy
}

@test "strip: leading assignments, quoted values and env wrappers are removed" {
  ch strip_assignments "API_KEY=sk-x FOO=\"a b\" env BAR='c d' pytest x"
  assert_success
  assert_output 'pytest x'
}

@test "bound: the head is the script basename plus at most three grammar tokens" {
  ch audit_command_head 'bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress --note hello' state-patch.sh
  assert_success
  assert_output 'state-patch.sh --task-status DV1 in_progress'
}

@test "bound: a token outside the flag, task-id and status grammar is redacted" {
  ch audit_command_head 'deploy prod-db --force hunter2 --x'
  assert_output 'deploy [redacted] --force [redacted]'
}

@test "segment: only the first line's segment that invokes the named script is read" {
  ch audit_command_head $'cd /tmp && API_TOKEN=zq1 bash /x/state-patch.sh --task-status QA0 done | tee y; echo ok\nstate-patch.sh --leak' state-patch.sh
  assert_output 'state-patch.sh --task-status QA0 [redacted]'
}

@test "segment: a separator inside quotes does not split" {
  ch audit_command_head 'run "x; y" --z'
  assert_output 'run [redacted] [redacted] --z'
}

@test "segment: no segment naming the script leaves only [redacted]" {
  ch audit_command_head 'echo x' state-patch.sh
  assert_output '[redacted]'
}

@test "mask: every secret shape redacts the whole token, ordinary tokens survive" {
  local tok long
  long="$(printf '%032d' 0 | tr 0 A)"
  for tok in API_KEY=abc db_password=x MY_TOKEN=t Bearer ghp_abc github_pat_abc sk-abc \
    xoxb-1 AKIAABCDEFGH https://u:p@host/x "$long" a/ghs_x; do
    run env LIBF="$PLUGIN_ROOT/$LIB" TOK="$tok" bash -c '. "$LIBF"; _ch_mask "$TOK"; printf %s "$_CH_TOK"'
    [ "$output" = "[redacted]" ] || fail "not masked: $tok"
  done
  for tok in --task-status in_progress DV1 skills/worktask/scripts/state-patch.sh \
    tests/shell/hooks/command-head-lib.bats; do
    run env LIBF="$PLUGIN_ROOT/$LIB" TOK="$tok" bash -c '. "$LIBF"; _ch_mask "$TOK"; printf %s "$_CH_TOK"'
    [ "$output" = "$tok" ] || fail "masked an ordinary token: $tok"
  done
}

@test "scrub: targets under the workspace rebase and host paths collapse" {
  CH_ROOT="$WD" ch audit_targets "cat $WD/src/a.sh /Users/alice/secret/x ./rel/y"
  assert_success
  assert_output "$(printf 'src/a.sh\n[local-path]\n./rel/y')"
}

@test "cap: at most five targets, and truncation is flagged" {
  chstate 'cp a/1 a/2 a/3 a/4 a/5 a/6 a/7'
  assert_output 'cp [redacted] [redacted] [redacted]|a/1,a/2,a/3,a/4,a/5|1|'
}

@test "cap: a head is cut to 120 chars and a target to 160" {
  local p t head rest
  p="$(printf 'a-%.0s' $(seq 1 100))"
  t="x/$(printf 'b-%.0s' $(seq 1 20))/$(printf 'c-%.0s' $(seq 1 20))"
  t="$t/$(printf 'd-%.0s' $(seq 1 20))/$(printf 'e-%.0s' $(seq 1 20))"
  chstate "$p $t"
  head="${output%%|*}"
  rest="${output#*|}"
  [ "${#head}" -eq 120 ] || fail "head is ${#head} chars"
  rest="${rest%%|*}"
  rest="${rest%,}"
  [ "${#rest}" -eq 160 ] || fail "target is ${#rest} chars"
}

@test "order: a secret straddling the target cap is masked before the cut" {
  local t
  t="$(printf 'c-%.0s' $(seq 1 26))/$(printf 'd-%.0s' $(seq 1 26))"
  t="$t/$(printf 'e-%.0s' $(seq 1 26))/ghp_zz"
  chstate "cat $t"
  assert_output 'cat [redacted]|[redacted]|0|'
}

@test "order: an assignment is stripped before anything is kept" {
  chstate 'API_TOKEN=zqCANARY bash state-patch.sh --task-status DV1 done --note zqCANARY' state-patch.sh
  assert_output 'state-patch.sh --task-status DV1 [redacted]||0|'
}

@test "bound: a path-shaped credential is redacted, ordinary repo paths are not" {
  local tok
  # The head's token grammar never reaches a target, and a credential with slashes in it is
  # itself path-shaped, so targets carry their own structural bound.
  for tok in 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' \
    'hooks.slack.com/services/T000/B000/XXXXXXXXXXXXXXXXXXXXXXXX' \
    'user-sup3rs3cret/host/path'; do
    ch audit_targets "cat $tok"
    [ "$output" = '[redacted]' ] || fail "published a credential-shaped target: $output"
  done
  for tok in skills/worktask/scripts/state-patch.sh tests/shell/hooks/command-head-lib.bats \
    .context/development-0.md src/App/Sources/Foo.swift dist/base64url/md5sum.txt; do
    ch audit_targets "cat $tok"
    [ "$output" = "$tok" ] || fail "redacted an ordinary path: $tok -> $output"
  done
}

@test "scrub: a target still absolute afterwards becomes [local-path], never the host path" {
  # The roots outside CORPFLOW_HOST_PATH_ERE the scrub cannot know. The self-test asserts this
  # invariant; the emit loop is what enforces it.
  ch audit_targets 'cat /data/u1/secrets/prod.env /usr/local/acme/licence.key'
  assert_output "$(printf '[local-path]\n[local-path]')"
}

@test "unavailable: a missing path scrub publishes [redacted] and no targets" {
  _isolated_lib ""
  chstate 'bash /Users/alice/state-patch.sh --task-status DV1 done' state-patch.sh
  assert_output '[redacted]||0|scrub_unavailable'
}

@test "unavailable: no function, no patterns, a failing or a line-dropping scrub all publish nothing" {
  local body
  local bodies=(
    'CORPFLOW_HOST_PATH_ERE=x; CORPFLOW_DRIVE_PATH_ERE=y'
    'corpflow_path_scrub() { cat; }'
    'CORPFLOW_HOST_PATH_ERE=x; CORPFLOW_DRIVE_PATH_ERE=y; corpflow_path_scrub() { cat; return 3; }'
    'CORPFLOW_HOST_PATH_ERE=x; CORPFLOW_DRIVE_PATH_ERE=y; corpflow_path_scrub() { head -n 1; }'
  )
  for body in "${bodies[@]}"; do
    _isolated_lib "$body"
    chstate 'cat /Users/alice/x a/b'
    [ "$output" = '[redacted]||0|scrub_unavailable' ] || fail "published '$output' with scrub body: $body"
  done
  _isolated_lib 'CORPFLOW_HOST_PATH_ERE=x; CORPFLOW_DRIVE_PATH_ERE=y; corpflow_path_scrub() { cat; }'
  chstate 'cat a/b'
  assert_output 'cat [redacted]|a/b|0|'
}
