#!/usr/bin/env bash
# @description junit-tally.sh — one count-bearing summary line from a JUnit XML results
#   directory, for runners whose console output carries no executed count (Gradle prints
#   `BUILD SUCCESSFUL in 4s`). A DV or QA stage captures the line to .context/logs/ and
#   quotes it as that runner's `summary_line`; handoff-harness.sh fails a gradle* or junit*
#   entry whose line does not carry its `count`.
#
# Usage:
#   junit-tally.sh <results-dir>
#
# Stdout, exactly one line on success:
#   JUnit XML tally: <N> tests executed, <F> failures, <E> errors, <S> skipped
# N is `tests` minus `skipped`: the count contract is cases that ran, and the JUnit
# `tests` attribute includes skipped cases.
#
# Counted, in every *.xml under <results-dir> (recursively; a symlinked <results-dir> is
# followed):
#   - a leaf <testsuite> (no child suites) by its tests/failures/errors/skipped attributes;
#   - a <testsuite> that holds child suites by its DIRECT <testcase> elements only, with
#     <failure>, <error> and <skipped> children as outcomes. Its attributes aggregate the
#     children, which are already counted, so reading them would count twice.
# A <testsuites> wrapper is never counted, for the same reason. Comments and CDATA sections
# are skipped in one left-to-right scan, whichever opens first, so captured output that
# prints XML or an unclosed `<!--` cannot add or hide suites. Tag ends are found outside
# quoted attribute values, so `name="a > b"` does not cut a tag short.
#
# Exit: 0 line printed · 1 no directory, no XML, no <testsuite>, or skipped exceeds tests
# (reason on stderr, stdout empty) · 2 usage error.
#
# Minimum shell: bash 3.2+ (macOS default), POSIX awk and find.
set -euo pipefail

usage() {
  echo "usage: junit-tally.sh <results-dir>" >&2
}

if [[ $# -ne 1 || "$1" == -h || "$1" == --help ]]; then
  usage
  exit 2
fi
dir="$1"

if [[ ! -d "$dir" ]]; then
  echo "junit-tally: no such directory: $dir" >&2
  exit 1
fi

files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find -H "$dir" -type f -name '*.xml' -print0)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "junit-tally: no *.xml file under $dir — point it at the test results directory (Gradle: build/test-results/test)" >&2
  exit 1
fi

# Streams each line once: split on `<`, so every piece after the first starts an element,
# a comment or a CDATA section. No buffer grows across lines, because joining a whole file
# into one string is quadratic in BWK awk (the macOS default) on a multi-MB <system-out>.
# `<` cannot occur inside an attribute value or inside `-->`/`]]>`, so a piece boundary
# never splits a tag end or a section closer.
totals=$(awk -v q="'" '
  function add(t, f, e, s) { T += t; F += f; E += e; S += s; suites++ }
  # Quote-aware tag end; tq carries an open quote across a tag that spans lines.
  function tag_end(s,   i, c, n) {
    n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (tq != "") { if (c == tq) tq = "" }
      else if (c == "\"" || c == q) tq = c
      else if (c == ">") return i
    }
    return 0
  }
  # Consumes name="value" pairs left to right, so a name inside a value never matches.
  function read_attrs(s,   re, pair, name, val, k) {
    for (k in A) delete A[k]
    re = "[A-Za-z_:][-A-Za-z0-9_:.]*[ \t]*=[ \t]*(\"[^\"]*\"|" q "[^" q "]*" q ")"
    while (match(s, re)) {
      pair = substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
      name = pair; sub(/[ \t]*=.*/, "", name)
      val = pair; sub(/^[^=]*=[ \t]*/, "", val)
      val = substr(val, 2, length(val) - 2)
      A[name] = (val ~ /^[0-9]+$/) ? val + 0 : 0
    }
  }
  function open_suite(text, selfclose) {
    if (d > 0) kid[d] = 1
    read_attrs(text)
    if (selfclose) { add(A["tests"], A["failures"], A["errors"], A["skipped"]); return }
    d++
    ot[d] = A["tests"]; of[d] = A["failures"]; oe[d] = A["errors"]; os[d] = A["skipped"]
    kid[d] = 0; dt[d] = 0; df[d] = 0; de[d] = 0; ds[d] = 0
  }
  function close_suite() {
    if (d == 0) return
    if (kid[d]) add(dt[d], df[d], de[d], ds[d])
    else add(ot[d], of[d], oe[d], os[d])
    d--
  }
  function open_case(selfclose) {
    if (d > 0) dt[d]++
    if (!selfclose) { incase = 1; cf = 0; ce = 0; cs = 0 }
  }
  function close_case() {
    if (incase && d > 0) { df[d] += cf; de[d] += ce; ds[d] += cs }
    incase = 0
  }
  function finish_tag(text,   sc) {
    sc = (text ~ /\/[ \t]*$/)
    if (kind == "suite") open_suite(text, sc)
    else open_case(sc)
    kind = ""; tagbuf = ""; tq = ""
  }
  # A tag body (text after the element name) that may end on this piece or a later line.
  function feed_tag(s,   k) {
    k = tag_end(s)
    if (k) { finish_tag(tagbuf " " substr(s, 1, k - 1)); mode = "text" }
    else tagbuf = tagbuf " " s
  }
  # Leaves the section when its closer is on this piece; the rest of the piece is text.
  function feed_section(s, closer) {
    if (index(s, closer)) mode = "text"
  }
  function end_file() {
    if (mode == "tag") finish_tag(tagbuf)
    close_case()
    # A file cut off mid-write still reports its open suites; attributes and direct
    # cases were written before the cut.
    while (d > 0) close_suite()
    mode = "text"
  }
  BEGIN { mode = "text" }
  FNR == 1 && NR > 1 { end_file() }
  {
    gsub(/\r/, " ")
    n = split($0, P, "<")
    for (i = 1; i <= n; i++) {
      s = P[i]
      if (mode == "comment") { feed_section(s, "-->"); continue }
      if (mode == "cdata") { feed_section(s, "]]>"); continue }
      if (mode == "tag") {
        if (i == 1) { feed_tag(s); continue }
        finish_tag(tagbuf); mode = "text"
      }
      if (i == 1) continue
      if (substr(s, 1, 3) == "!--") { mode = "comment"; feed_section(substr(s, 4), "-->") }
      else if (substr(s, 1, 8) == "![CDATA[") { mode = "cdata"; feed_section(substr(s, 9), "]]>") }
      else if (s ~ /^testsuite([ \t\/>]|$)/) { kind = "suite"; tagbuf = ""; mode = "tag"; feed_tag(substr(s, 10)) }
      else if (s ~ /^testcase([ \t\/>]|$)/) { kind = "case"; tagbuf = ""; mode = "tag"; feed_tag(substr(s, 9)) }
      else if (s ~ /^\/testsuite([ \t>]|$)/) { close_case(); close_suite() }
      else if (s ~ /^\/testcase([ \t>]|$)/) close_case()
      else if (incase && s ~ /^failure([ \t\/>]|$)/) cf = 1
      else if (incase && s ~ /^error([ \t\/>]|$)/) ce = 1
      else if (incase && s ~ /^skipped([ \t\/>]|$)/) cs = 1
    }
  }
  END { end_file(); printf "%d %d %d %d %d\n", suites, T, F, E, S }
' "${files[@]}")

read -r suites tests failures errors skipped <<< "$totals"

if [[ "$suites" -eq 0 ]]; then
  echo "junit-tally: no <testsuite> element in the ${#files[@]} *.xml file(s) under $dir" >&2
  exit 1
fi
if [[ "$skipped" -gt "$tests" ]]; then
  echo "junit-tally: skipped ($skipped) exceeds tests ($tests) under $dir — the results are malformed" >&2
  exit 1
fi

printf 'JUnit XML tally: %d tests executed, %d failures, %d errors, %d skipped\n' \
  "$((tests - skipped))" "$failures" "$errors" "$skipped"
