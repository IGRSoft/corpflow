#!/usr/bin/env bats
# control-byte-lib.sh — the control-byte predicate shared by the anchor preflight hook, the
# handoff harness gate and control-byte-lint.sh.
#
# Every raw byte below is generated at test time from a printf octal escape, so no fixture
# in the repository carries the bytes this library exists to reject.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/control-byte-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
}

# scan <file> [label] — cb_scan_file under the strict options every consumer sets; the rc
# is printed as the last line so a hit and its lines are asserted together.
scan() {
  run bash -c 'set -euo pipefail; . "$1"; rc=0; cb_scan_file "$2" "$3" || rc=$?; printf "rc=%s\n" "$rc"' \
    _ "$PLUGIN_ROOT/$LIB" "$1" "${2:-$1}"
}

lintable() {
  run bash -c '. "$1"; cb_is_lintable "$2"' _ "$PLUGIN_ROOT/$LIB" "$1"
}

# --- byte class --------------------------------------------------------------

@test "tab, LF, CR, DEL and multibyte UTF-8 are not flagged" {
  printf 'a\tb\r\nc\177d \303\251 \342\202\254\n' > "$WD/ok.md"
  scan "$WD/ok.md"
  assert_success
  assert_output "rc=0"
}

@test "a literal escape written as text is not flagged" {
  printf '%s\n' 'nul \0 hex \x00 caret ^@ octal \000 inline `\0`' > "$WD/literal.md"
  scan "$WD/literal.md"
  assert_output "rc=0"
}

@test "ESC is flagged at its exact 0-based offset" {
  printf 'ab\033c\n' > "$WD/esc.md"
  scan "$WD/esc.md" esc.md
  assert_output "esc.md:2:0x1B
rc=1"
}

@test "form feed is flagged" {
  printf 'x\014\n' > "$WD/ff.md"
  scan "$WD/ff.md" ff.md
  assert_output "ff.md:1:0x0C
rc=1"
}

@test "NUL is flagged" {
  printf 'raw \000 byte\n' > "$WD/nul.md"
  scan "$WD/nul.md" nul.md
  assert_output "nul.md:4:0x00
rc=1"
}

@test "offsets stay exact past repeated identical od lines" {
  # 48 identical bytes are three identical 16-byte od lines; without od -v they collapse.
  { for _ in $(seq 1 48); do printf 'a'; done; printf '\033\n'; } > "$WD/runs.md"
  scan "$WD/runs.md" runs.md
  assert_output "runs.md:48:0x1B
rc=1"
}

@test "the class is 0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F and nothing in 0x20-0x7F" {
  local i
  for i in $(seq 0 127); do printf "\\$(printf '%03o' "$i")"; done > "$WD/all.txt"
  scan "$WD/all.txt" all
  assert_equal "${#lines[@]}" 21
  assert_line --index 8 "all:8:0x08"
  assert_line --index 9 "all:11:0x0B"
  assert_line --index 10 "all:12:0x0C"
  assert_line --index 11 "all:14:0x0E"
  assert_line --index 20 "rc=1"
  refute_output --partial ":9:0x09"
  refute_output --partial ":10:0x0A"
  refute_output --partial ":13:0x0D"
  # The tail of the class, past the print cap of the combined file.
  for i in $(seq 23 34); do printf "\\$(printf '%03o' "$i")"; done > "$WD/tail.txt"
  scan "$WD/tail.txt" tail
  assert_line --index 8 "tail:8:0x1F"
  assert_line --index 9 "rc=1"
}

@test "hits print at most 20 lines and the rc survives pipefail" {
  { for _ in $(seq 1 30); do printf '\001'; done; } > "$WD/many.txt"
  scan "$WD/many.txt" many
  assert_equal "${#lines[@]}" 21
  assert_line --index 19 "many:19:0x01"
  assert_line --index 20 "rc=1"
}

@test "a label with backslashes is printed verbatim" {
  printf '\001' > "$WD/lab.md"
  scan "$WD/lab.md" 'dir\tname\0.md'
  assert_line --index 0 'dir\tname\0.md:0:0x01'
}

@test "an empty file is clean" {
  : > "$WD/empty.md"
  scan "$WD/empty.md"
  assert_output "rc=0"
}

# --- rc 2 --------------------------------------------------------------------

@test "a directory, a missing path and an unreadable file are rc 2" {
  mkdir "$WD/dir.md"
  scan "$WD/dir.md"
  assert_output "rc=2"
  scan "$WD/missing.md"
  assert_output "rc=2"
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file"
  printf 'x\n' > "$WD/locked.md"
  chmod 000 "$WD/locked.md"
  scan "$WD/locked.md"
  chmod 600 "$WD/locked.md"
  assert_output "rc=2"
}

# --- extension allowlist ------------------------------------------------------

@test "an upper-case text extension is lintable" {
  lintable "docs/README.MD"
  assert_success
  lintable ".env"
  assert_success
}

@test "a binary extension, an extension-less name and vendored paths are skipped" {
  lintable "img/logo.png"
  assert_failure
  lintable "Makefile"
  assert_failure
  lintable "tests/vendor/bats-core/x.bats"
  assert_failure
  lintable "/abs/repo/tests/vendor/x.md"
  assert_failure
}

# --- library authoring rules -------------------------------------------------

@test "executing the library directly is refused" {
  run bash "$PLUGIN_ROOT/$LIB"
  assert_failure 2
  assert_output --partial "source it, do not execute it directly"
}

@test "a double source is a no-op" {
  run bash -c '. "$1"; CB_TEXT_EXTS=md; . "$1"; printf "%s" "$CB_TEXT_EXTS"' _ "$PLUGIN_ROOT/$LIB"
  assert_success
  assert_output "md"
}

@test "sourcing sets no shell options" {
  run bash -c 'before=$-; . "$1"; [ "$before" = "$-" ] && printf same' _ "$PLUGIN_ROOT/$LIB"
  assert_output "same"
}
