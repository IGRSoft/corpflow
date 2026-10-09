#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/junit-tally.sh.
# Contracts (from header):
#   - <results-dir> with JUnit XML => exactly one line on stdout, exit 0:
#     "JUnit XML tally: <tests - skipped> tests executed, <F> failures, <E> errors, <S> skipped"
#   - only leaf <testsuite> elements count; a <testsuites> wrapper or a parent suite does not
#   - comments and CDATA never add suites
#   - missing dir / no XML / no <testsuite> => stdout empty, reason on stderr, exit 1
#   - wrong argument count => usage on stderr, exit 2
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
bats_require_minimum_version 1.5.0

SCRIPT="skills/worktask/scripts/junit-tally.sh"

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "tally: two suites in nested dirs print the exact line, N = tests minus skipped" {
  bash "$PLUGIN_ROOT/$SCRIPT" "$FIXTURES/worktask/junit-tally" > "$WD/out"
  cmp "$FIXTURES/worktask/junit-tally.expected" "$WD/out"
}

@test "testsuites: an aggregate wrapper is not counted twice" {
  mkdir -p "$WD/r"
  cat > "$WD/r/results.xml" << 'XML'
<?xml version="1.0"?>
<testsuites tests="8" failures="1" errors="1" skipped="1">
  <testsuite name="a" tests="5" failures="1" errors="0" skipped="1"><testcase name="x"/></testsuite>
  <testsuite name="b" tests="3" failures="0" errors="1" skipped="0"/>
</testsuites>
XML
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_success
  assert_output 'JUnit XML tally: 7 tests executed, 1 failures, 1 errors, 1 skipped'
}

@test "testsuites: a parent suite holding child suites counts only the children" {
  mkdir -p "$WD/r"
  cat > "$WD/r/nested.xml" << 'XML'
<testsuite name="parent" tests="4" failures="0" errors="0" skipped="0">
  <testsuite
      name="child1" tests="1" failures="0" errors="0" skipped="0">
    <testcase name="c1"/>
  </testsuite>
  <testsuite name="child2" tests="3" failures="0" errors="0" skipped="0"/>
</testsuite>
XML
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_success
  assert_output 'JUnit XML tally: 4 tests executed, 0 failures, 0 errors, 0 skipped'
}

@test "testsuites: a parent suite with child suites and direct testcases counts both, once" {
  mkdir -p "$WD/r"
  cat > "$WD/r/mixed.xml" << 'XML'
<testsuite name="parent" tests="4" failures="1" errors="0" skipped="1">
  <testcase name="d1"><failure message="x"/></testcase>
  <testcase name="d2">
    <skipped/>
  </testcase>
  <testsuite name="child" tests="2" failures="0" errors="0" skipped="0">
    <testcase name="c1"/><testcase name="c2"/>
  </testsuite>
</testsuite>
XML
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_success
  assert_output 'JUnit XML tally: 3 tests executed, 1 failures, 0 errors, 1 skipped'
}

@test "cdata: an unclosed <!-- inside CDATA does not hide the next suite" {
  mkdir -p "$WD/r"
  cat > "$WD/r/multi.xml" << 'XML'
<testsuites>
  <testsuite name="a" tests="2" failures="0" errors="0" skipped="0">
    <system-out><![CDATA[<html><!-- unclosed comment in captured output]]></system-out>
  </testsuite>
  <testsuite name="b" tests="3" failures="0" errors="0" skipped="0"/>
</testsuites>
XML
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_success
  assert_output 'JUnit XML tally: 5 tests executed, 0 failures, 0 errors, 0 skipped'
}

@test "quotes: a > inside an attribute value does not cut the tag short" {
  mkdir -p "$WD/r"
  printf '%s\n' "<testsuite name=\"a > b\" tests=\"3\" failures=\"1\" errors=\"0\" skipped='0'/>" > "$WD/r/q.xml"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_success
  assert_output 'JUnit XML tally: 3 tests executed, 1 failures, 0 errors, 0 skipped'
}

@test "symlink: a symlinked results directory is followed" {
  ln -s "$FIXTURES/worktask/junit-tally" "$WD/linked"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/linked"
  assert_success
  assert_output 'JUnit XML tally: 7 tests executed, 1 failures, 1 errors, 1 skipped'
}

@test "size: a 100k-line system-out finishes in bounded time" {
  # The bound is generous so a slow CI host does not flake, yet a scan that is quadratic
  # in file size runs far past it on this file in BWK awk.
  mkdir -p "$WD/r"
  awk 'BEGIN {
    print "<testsuite name=\"big\" tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\">"
    print "<testcase name=\"t\"/><system-out><![CDATA["
    for (i = 0; i < 100000; i++) print "log line " i " with <tags> & noise, padding padding"
    print "]]></system-out></testsuite>"
  }' > "$WD/r/big.xml"
  local start=$SECONDS
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_success
  assert_output 'JUnit XML tally: 1 tests executed, 0 failures, 0 errors, 0 skipped'
  [ $((SECONDS - start)) -le 10 ] || fail "took $((SECONDS - start)) s on a 100k-line file"
}

@test "empty: a directory with no XML prints nothing on stdout and fails with a reason" {
  mkdir -p "$WD/empty"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/empty"
  assert_failure 1
  assert_output ''
  [[ "$stderr" == *"no *.xml file under"* ]] || fail "stderr: $stderr"
}

@test "empty: XML with no <testsuite> element fails rather than printing a zero tally" {
  mkdir -p "$WD/r"
  printf '<?xml version="1.0"?>\n<testsuites/>\n' > "$WD/r/x.xml"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/r"
  assert_failure 1
  assert_output ''
  [[ "$stderr" == *"no <testsuite> element"* ]] || fail "stderr: $stderr"
}

@test "missing: a path that does not exist prints nothing on stdout and fails with a reason" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" "$WD/nope"
  assert_failure 1
  assert_output ''
  [[ "$stderr" == *"no such directory"* ]] || fail "stderr: $stderr"
}

@test "usage: no argument exits 2" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 2
  assert_output ''
  [[ "$stderr" == *"usage: junit-tally.sh"* ]] || fail "stderr: $stderr"
}
