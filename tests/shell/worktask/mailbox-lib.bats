#!/usr/bin/env bats
# mailbox-lib.sh — the one definition of the durable cross-session mailbox, sourced by
# mailbox.sh, mailbox-reply.sh and blocked-on-dispatch.sh.
#
# The load-bearing block is the pair of gates every caller leans on: mb_valid_ask_id, which
# runs before any ask_id reaches a path join, and mb_dir, which refuses a symlinked, foreign
# or non-directory level rather than handing back a partial mailbox a later write follows.
# mb_write_nc's first-writer-wins contract is the third: two sessions answering one ask must
# not both land.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/mailbox-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  MBDIR="$WD/mailbox"
}

# _lib <snippet> — runs the snippet with the library sourced under the callers' strict mode,
# always against the test seam mailbox so no case can reach a real one.
_lib() {
  run --separate-stderr env MAILBOX_DIR="$MBDIR" MAILBOX_NOW="${NOW:-1789646700}" \
    bash -c "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; $1" < /dev/null
}

@test "executing the library directly is refused; it is source-only" {
  run bash "$PLUGIN_ROOT/$LIB"
  [ "$status" -eq 2 ]
  [[ "$output" == *"source it, do not execute it directly"* ]]
}

# --- mb_valid_ask_id: the gate before any path join ---------------------------

@test "mb_valid_ask_id: the documented grammar passes" {
  _lib 'mb_valid_ask_id "ask-20260917t090000z-aaaaaaaaaaaa"'
  [ "$status" -eq 0 ]
}

@test "mb_valid_ask_id: traversal, empty, wrong length and uppercase hex are refused" {
  local id
  for id in '../../etc/passwd' '' 'ask-20260917t090000z-AAAAAAAAAAAA' \
    'ask-20260917t090000z-aaaaaaaaaaa' 'ask-20260917t090000z-aaaaaaaaaaaaa' \
    'ask-2026091t090000z-aaaaaaaaaaaa' 'ask-20260917t090000z-aaaaaaaaaaaa/x'; do
    _lib "mb_valid_ask_id '$id'"
    [ "$status" -ne 0 ] || fail "accepted a bad ask_id: [$id]"
  done
}

@test "mb_valid_ask_id: an embedded newline does not slip past the anchors" {
  # A line-anchored match would accept this and hand a two-line value to a path join.
  _lib 'mb_valid_ask_id "ask-20260917t090000z-aaaaaaaaaaaa
../../etc/passwd"'
  [ "$status" -ne 0 ]
}

# --- mb_now: the test seam ----------------------------------------------------

@test "mb_now: a numeric MAILBOX_NOW is the clock; junk falls back to the host" {
  NOW=1789646700 _lib 'mb_now'
  [ "$output" = "1789646700" ]

  run --separate-stderr env MAILBOX_DIR="$MBDIR" MAILBOX_NOW="not-a-number" \
    bash -c "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; mb_now" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]] || fail "non-numeric seam did not fall back to an epoch: $output"
  [ "$output" != "not-a-number" ]
}

# --- mb_dir: refuses a partial or foreign mailbox -----------------------------

@test "mb_dir: creates the three levels 0700 and prints the root" {
  _lib 'mb_dir'
  [ "$status" -eq 0 ]
  [ "$output" = "$MBDIR" ]
  local d mode
  for d in "$MBDIR" "$MBDIR/requests" "$MBDIR/replies"; do
    [ -d "$d" ] || fail "missing level: $d"
    mode="$(stat -f '%Lp' "$d" 2> /dev/null || stat -c '%a' "$d")"
    [ "$mode" = "700" ] || fail "$d is $mode, want 700"
  done
}

@test "mb_dir: a relative MAILBOX_DIR is refused rather than resolved against cwd" {
  run --separate-stderr env MAILBOX_DIR="relative/mailbox" \
    bash -c "set -euo pipefail; . '$PLUGIN_ROOT/$LIB'; mb_dir" < /dev/null
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "mb_dir: a symlinked level is refused, at the root and at a subdirectory" {
  mkdir -p "$WD/elsewhere"
  ln -s "$WD/elsewhere" "$MBDIR"
  _lib 'mb_dir'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ -z "$(find "$WD/elsewhere" -mindepth 1 2> /dev/null)" ] || fail "wrote through the symlink"

  rm -f "$MBDIR"
  mkdir -p "$MBDIR" "$WD/other"
  chmod 700 "$MBDIR"
  ln -s "$WD/other" "$MBDIR/requests"
  _lib 'mb_dir'
  [ "$status" -eq 1 ]
}

@test "mb_dir: a level that is a regular file is refused, not clobbered" {
  mkdir -p "$MBDIR"
  chmod 700 "$MBDIR"
  printf 'not a dir\n' > "$MBDIR/replies"
  _lib 'mb_dir'
  [ "$status" -eq 1 ]
  [ "$(cat "$MBDIR/replies")" = "not a dir" ]
}

# --- mb_write_nc: first writer wins ------------------------------------------

@test "mb_write_nc: writes 0600 and reports rc 1 for a second writer, leaving the first intact" {
  mkdir -p "$MBDIR/replies"
  chmod 700 "$MBDIR/replies"
  _lib 'mb_write_nc "$MAILBOX_DIR/replies" "ask-20260917t090000z-aaaaaaaaaaaa" "{\"n\":1}"'
  [ "$status" -eq 0 ]
  local f="$MBDIR/replies/ask-20260917t090000z-aaaaaaaaaaaa.json"
  [ -f "$f" ]
  local mode
  mode="$(stat -f '%Lp' "$f" 2> /dev/null || stat -c '%a' "$f")"
  [ "$mode" = "600" ]

  _lib 'mb_write_nc "$MAILBOX_DIR/replies" "ask-20260917t090000z-aaaaaaaaaaaa" "{\"n\":2}"'
  [ "$status" -eq 1 ]
  grep -qF '"n":1' "$f" || fail "the second writer overwrote the first"
}

@test "mb_write_nc: a symlinked target is refused as rc 2 and the link target is untouched" {
  mkdir -p "$MBDIR/replies"
  chmod 700 "$MBDIR/replies"
  printf 'original\n' > "$WD/victim"
  ln -s "$WD/victim" "$MBDIR/replies/ask-20260917t090000z-aaaaaaaaaaaa.json"
  _lib 'mb_write_nc "$MAILBOX_DIR/replies" "ask-20260917t090000z-aaaaaaaaaaaa" "{\"n\":1}"'
  [ "$status" -eq 2 ]
  [ "$(cat "$WD/victim")" = "original" ]
}

@test "mb_write_nc: a failed write leaves no temp file behind" {
  mkdir -p "$MBDIR/replies"
  chmod 700 "$MBDIR/replies"
  _lib 'mb_write_nc "$MAILBOX_DIR/replies" "ask-20260917t090000z-aaaaaaaaaaaa" "{\"n\":1}"'
  [ "$status" -eq 0 ]
  _lib 'mb_write_nc "$MAILBOX_DIR/replies" "ask-20260917t090000z-aaaaaaaaaaaa" "{\"n\":2}"'
  [ "$status" -eq 1 ]
  [ -z "$(find "$MBDIR/replies" -name '.ask-*' 2> /dev/null)" ] || fail "temp file left behind"
}

# --- mb_create_request / mb_read_request --------------------------------------

@test "mb_create_request: mints a grammar-valid id, writes the request and defaults the deadline" {
  _lib 'mb_create_request DR0 peer "which base?" ""'
  [ "$status" -eq 0 ]
  local id
  id="$(printf '%s' "$output" | jq -r '.ask_id')"
  _lib "mb_valid_ask_id '$id'"
  [ "$status" -eq 0 ]
  [ -f "$MBDIR/requests/$id.json" ]
  # Default deadline is 1800s past MAILBOX_NOW.
  run jq -r '.deadline' "$MBDIR/requests/$id.json"
  [ "$output" = "$(jq -rn '(1789646700 + 1800) | todate')" ]
}

@test "mb_create_request: an unparseable deadline is rc 3, kept apart from unavailability" {
  _lib 'mb_create_request DR0 peer "q" "not-a-date"'
  [ "$status" -eq 3 ]
  [ -z "$(find "$MBDIR/requests" -name 'ask-*.json' 2> /dev/null)" ]
}

@test "mb_read_request: round-trips what mb_create_request wrote; an unknown id fails" {
  _lib 'mb_create_request DR0 peer "which base?" ""'
  [ "$status" -eq 0 ]
  local id
  id="$(printf '%s' "$output" | jq -r '.ask_id')"

  _lib "mb_read_request '$id' | jq -r '.question'"
  [ "$status" -eq 0 ]
  [ "$output" = "which base?" ]

  _lib 'mb_read_request "ask-20260917t090000z-ffffffffffff"'
  [ "$status" -ne 0 ]
}

@test "mb_read_request: a traversal-shaped id is refused before the path join" {
  _lib 'mb_read_request "../../etc/passwd"'
  [ "$status" -ne 0 ]
}
