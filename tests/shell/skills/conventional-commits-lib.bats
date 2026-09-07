#!/usr/bin/env bats
# Unit contracts for skills/release-engineering/scripts/conventional-commits-lib.sh
# — the parsing both changelog-from-git.sh and version-bump-from-git.sh route
# through. Those two have their own end-to-end suites; this file pins the shared
# functions directly, so a break is attributed to the library rather than showing
# up twice as a mystery in the consumers.
#
# Contracts (from the source's own header comments):
#   cc_parse takes the WHOLE message — `BREAKING CHANGE:` is a footer, not a subject.
#   Breaking detection is case-sensitive: prose must not be promoted to MAJOR.
#   Breaking beats type, so `fix!:` and `chore:` + footer both reach major.
#   A breaking commit is never routed to a silent section.
#   cc_bump_rank ranks an unknown token 0, so a typo cannot win an aggregation.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/release-engineering/scripts/conventional-commits-lib.sh"

setup() {
  # shellcheck disable=SC1090
  . "$PLUGIN_ROOT/$LIB"
}

@test "cc_parse: splits type, scope, and description from a conventional subject" {
  cc_parse "feat(worktask): add the depth cap"
  [ "$CC_CONVENTIONAL" = 1 ]
  [ "$CC_TYPE" = "feat" ]
  [ "$CC_SCOPE" = "worktask" ]
  [ "$CC_DESC" = "add the depth cap" ]
  [ "$CC_BREAKING" = 0 ]
}

@test "cc_parse: a non-conventional subject still yields a subject, not a parse failure" {
  cc_parse "tidied some things up"
  [ "$CC_CONVENTIONAL" = 0 ]
  [ "$CC_TYPE" = "" ]
  [ "$CC_SUBJECT" = "tidied some things up" ]
}

@test "cc_parse: a blank message returns 1" {
  run cc_parse ""
  [ "$status" -eq 1 ]
  run cc_parse "   "
  [ "$status" -eq 1 ]
}

@test "cc_parse: leading blank lines do not swallow the subject" {
  cc_parse "$(printf '\n\n  feat: real subject\n')"
  [ "$CC_SUBJECT" = "feat: real subject" ]
  [ "$CC_TYPE" = "feat" ]
}

@test "cc_parse: the header bang and the footer are both breaking" {
  cc_parse "fix!: drop the legacy flag"
  [ "$CC_BREAKING" = 1 ]
  cc_parse "$(printf 'chore: bump deps\n\nBREAKING CHANGE: minimum bash is now 4\n')"
  [ "$CC_BREAKING" = 1 ]
  cc_parse "$(printf 'chore: bump deps\n\nBREAKING-CHANGE: hyphenated spelling too\n')"
  [ "$CC_BREAKING" = 1 ]
}

@test "cc_parse: breaking detection is case-sensitive and footer-anchored" {
  # Loose matching would promote ordinary prose to a MAJOR release.
  cc_parse "$(printf 'feat: rework\n\nthis is a breaking change: for downstreams\n')"
  [ "$CC_BREAKING" = 0 ]
  cc_parse "$(printf 'feat: rework\n\nsee BREAKING CHANGE: below\n')"
  [ "$CC_BREAKING" = 0 ]
}

@test "cc_parse: a subject-only breaking footer is not read from the subject line" {
  # The footer lives in the body; a subject that merely contains the words is not one.
  cc_parse "BREAKING CHANGE: not a footer here"
  [ "$CC_BREAKING" = 0 ]
}

@test "cc_classify_section: maps types to Keep-a-Changelog sections" {
  [ "$(cc_classify_section feat 0)" = "Added" ]
  [ "$(cc_classify_section fix 0)" = "Fixed" ]
  [ "$(cc_classify_section refactor 0)" = "Changed" ]
  [ "$(cc_classify_section perf 0)" = "Changed" ]
  [ "$(cc_classify_section docs 0)" = "" ]
  [ "$(cc_classify_section chore 0)" = "" ]
}

@test "cc_classify_section: a breaking commit is never silent" {
  # Otherwise the release ships a MAJOR bump whose changelog says nothing about it.
  [ "$(cc_classify_section chore 1)" = "Changed" ]
  [ "$(cc_classify_section docs 1)" = "Changed" ]
}

@test "cc_classify_section: an unknown or empty type falls through to Other, never dropped" {
  [ "$(cc_classify_section wibble 0)" = "Other" ]
  [ "$(cc_classify_section '' 0)" = "Other" ]
}

@test "cc_bump_for: breaking outranks type" {
  [ "$(cc_bump_for feat 0)" = "minor" ]
  [ "$(cc_bump_for fix 0)" = "patch" ]
  [ "$(cc_bump_for chore 0)" = "none" ]
  [ "$(cc_bump_for fix 1)" = "major" ]
  [ "$(cc_bump_for chore 1)" = "major" ]
}

@test "cc_bump_rank: unknown tokens rank 0 so a typo cannot win an aggregation" {
  [ "$(cc_bump_rank major)" = "3" ]
  [ "$(cc_bump_rank minor)" = "2" ]
  [ "$(cc_bump_rank patch)" = "1" ]
  [ "$(cc_bump_rank none)" = "0" ]
  [ "$(cc_bump_rank MAJOR)" = "0" ]
  [ "$(cc_bump_rank '')" = "0" ]
}

@test "cc_bump_max: highest severity wins in either argument order" {
  [ "$(cc_bump_max patch minor)" = "minor" ]
  [ "$(cc_bump_max minor patch)" = "minor" ]
  [ "$(cc_bump_max none major)" = "major" ]
  [ "$(cc_bump_max patch patch)" = "patch" ]
}

@test "cc_collect_records: a NUL-free file is read one record per line" {
  printf 'feat: one\nfix: two\n' > "$BATS_TEST_TMPDIR/subjects.txt"
  # Redirected to a file, not captured through $output: command substitution
  # discards NUL bytes, which are the very thing under test here.
  cc_collect_records "" "" "$BATS_TEST_TMPDIR/subjects.txt" > "$BATS_TEST_TMPDIR/out.bin"
  [ "$(LC_ALL=C tr -dc '\000' < "$BATS_TEST_TMPDIR/out.bin" | wc -c | tr -d ' ')" = "2" ]
}

@test "cc_collect_records: a NUL-separated file passes through whole, footers intact" {
  printf 'feat: one\n\nBREAKING CHANGE: x\0fix: two\0' > "$BATS_TEST_TMPDIR/records.bin"
  run cc_collect_records "" "" "$BATS_TEST_TMPDIR/records.bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BREAKING CHANGE: x"* ]]
}

@test "cc_collect_records: an unreadable file is an error, not an empty range" {
  run cc_collect_records "" "" "$BATS_TEST_TMPDIR/nope.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read file"* ]]
}

@test "cc_collect_records: a range with shell metacharacters is refused before git runs" {
  run cc_collect_records 'v1..v2; rm -rf /' "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe characters"* ]]
}

# --- the mandatory `#<issue>` prefix (git-conventions.md § Commit Message Format) -------------
#
# Every subject this project produces carries one. Before these cases the library was tested
# only against inputs the project does not emit, so a prefixed `feat` scoring `none` — and a
# prefixed `feat!` never reaching major — went unseen through eight releases.

@test "cc_parse: an issue-prefixed subject is conventional, prefix excluded from the fields" {
  cc_parse "#356 feat(worktask): Add a ledger operation"
  [ "$CC_CONVENTIONAL" = 1 ]
  [ "$CC_TYPE" = "feat" ]
  [ "$CC_SCOPE" = "worktask" ]
  [ "$CC_DESC" = "Add a ledger operation" ]
  [ "$CC_SUBJECT" = "#356 feat(worktask): Add a ledger operation" ]
}

@test "cc_parse: a non-numeric issue key is accepted (git-conventions allows #PROJ-123)" {
  cc_parse "#OV-164 fix: Stop the blink"
  [ "$CC_CONVENTIONAL" = 1 ]
  [ "$CC_TYPE" = "fix" ]
  [ "$CC_DESC" = "Stop the blink" ]
}

@test "cc_parse: a prefixed breaking bang still reaches major" {
  cc_parse "#360 feat(api)!: Remove the v1 endpoint"
  [ "$CC_BREAKING" = 1 ]
  [ "$CC_TYPE" = "feat" ]
  [ "$(cc_bump_for "$CC_TYPE" "$CC_BREAKING")" = "major" ]
}

@test "cc_parse: a prefixed silent type is still classified silent" {
  cc_parse "#359 docs(evals): Quote the captured pair"
  [ "$CC_CONVENTIONAL" = 1 ]
  [ "$CC_TYPE" = "docs" ]
  [ "$(cc_classify_section "$CC_TYPE" "$CC_BREAKING")" = "" ]
}

@test "cc_parse: a bare # token is not an issue prefix" {
  # `#comment: x` must stay non-conventional — the prefix only matches when a space
  # separates it from the type, so `comment` can never be read as an issue key.
  cc_parse "#comment: not a commit type"
  [ "$CC_CONVENTIONAL" = 0 ]
  [ "$CC_TYPE" = "" ]
}

@test "cc_parse: an unprefixed subject is unchanged by the optional group" {
  cc_parse "fix(evals): Scope the label store"
  [ "$CC_CONVENTIONAL" = 1 ]
  [ "$CC_TYPE" = "fix" ]
  [ "$CC_SCOPE" = "evals" ]
  [ "$CC_DESC" = "Scope the label store" ]
}
