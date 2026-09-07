#!/usr/bin/env bash
# section-lint.sh — markdown section-length lint (≤1000 chars per leaf section).
#
# Long sections bury the imperative rules agents must follow and defeat
# skim-reading during stage handoffs. A section is a heading line (#..######
# at column 0, outside fenced code blocks) plus its body up to the next
# heading of ANY level (leaf semantics — an H2's own text stops at its first
# H3). count = len(heading) + 1 + Σ(len(body_line) + 1). Fenced blocks
# (``` and ~~~, marker- and length-aware, ≤3 leading spaces) COUNT toward
# the cap; heading-lookalikes inside fences are ignored. YAML frontmatter
# and any pre-heading preamble are exempt (no heading owns them).
#
# Usage:
#   section-lint.sh                 # lint agents/*.md commands/*.md skills/**/*.md
#                                   # (excludes skills/**/references/fixtures/**,
#                                   #  skills/*/tests/** — test vectors, not prompts)
#   section-lint.sh <file> [...]    # lint specific files
#   section-lint.sh --self-test     # verify the parser against inline fixtures
#
# Exit codes: 0 = all within cap, 1 = at least one over cap, 2 = usage/parser error.
#
# CI / repo-maintenance helper only — never read by agents at runtime.

set -euo pipefail

lint() {
  python3 - "$@" <<'PYEOF'
import re, sys

CAP = 1000
FENCE_RE = re.compile(r'^ {0,3}(`{3,}|~{3,})')
HEAD_RE = re.compile(r'^#{1,6} ')

def sections(text):
    """Yield (lineno, heading, char_count) leaf sections of a markdown text."""
    lines = text.splitlines()
    start = 0
    if lines and lines[0].rstrip('\r') == '---':          # skip YAML frontmatter
        for j in range(1, len(lines)):
            if lines[j].rstrip('\r') == '---':
                start = j + 1
                break
    fence_char, fence_len = None, 0
    cur = None                                            # [lineno, heading, count]
    for n in range(start, len(lines)):
        ln = lines[n]
        m = FENCE_RE.match(ln)
        if m:
            marker, mlen = m.group(1)[0], len(m.group(1))
            if fence_char is None:
                fence_char, fence_len = marker, mlen      # open
            elif marker == fence_char and mlen >= fence_len \
                    and ln[m.end():].strip() == '':
                fence_char = None                         # close (bare fence only)
            # opposite marker / shorter run / info-string close = content
        elif fence_char is None and HEAD_RE.match(ln):
            if cur:
                yield tuple(cur)
            cur = [n + 1, ln, len(ln) + 1]
            continue
        if cur:
            cur[2] += len(ln) + 1
    if cur:
        yield tuple(cur)

repo_mode = sys.argv[1] == '--repo'
paths = sys.argv[2:] if repo_mode else sys.argv[1:]
fail, viol, nfiles = 0, 0, 0
for path in paths:
    try:
        text = open(path, encoding='utf-8').read()
    except OSError as e:
        print(f"section-lint: cannot read {path}: {e}", file=sys.stderr)
        sys.exit(2)
    nfiles += 1
    over, total = [], 0
    for lineno, heading, count in sections(text):
        total += 1
        if count > CAP:
            over.append((lineno, heading, count))
    for lineno, heading, count in over:
        print(f"section-lint: {path}:{lineno}: {count} chars (cap {CAP}) — OVER :: {heading.strip()}")
    if over:
        fail, viol = 1, viol + len(over)
    elif not repo_mode:
        print(f"section-lint: {path}: {total} sections, all ≤ cap ok")
if repo_mode:
    print(f"section-lint: {nfiles} files, {viol} sections over cap")
sys.exit(fail)
PYEOF
}

repo_files() {
  git ls-files -- 'agents/*.md' 'commands/*.md' 'skills/*.md' 'skills/**/*.md' \
    | sort -u \
    | grep -Ev '^skills/([^/]+/)*references/fixtures/|^skills/[^/]+/tests/' || true
}

case "${1:-}" in
  --self-test)
    # Sourced HERE, not at the top: the harness is test code the production path
    # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
    # `.` builtin is a special-builtin error that exits the shell immediately,
    # bypassing an `if ! . …` guard entirely.
    SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/section-lint-selftest.sh"
    if [ -r "$SELFTEST_LIB_PATH" ]; then
      # shellcheck source=section-lint-selftest.sh
      # shellcheck disable=SC1090
      . "$SELFTEST_LIB_PATH"
    else
      printf >&2 'section-lint: self-test harness unreachable at %s — plugin install broken\n' \
        "$SELFTEST_LIB_PATH"
      exit 2
    fi
    self_test
    ;;
  "")
    cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    # shellcheck disable=SC2046
    lint --repo $(repo_files)
    ;;
  *) lint "$@" ;;
esac
