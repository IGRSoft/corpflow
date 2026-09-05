#!/usr/bin/env bash
# desc-lint.sh — frontmatter description lint: grammar (G1–G5) + length (G6).
#
# Frontmatter descriptions of every agent, command, and skill are AMBIENT:
# Claude Code injects them into every session's startup context in every
# project with the plugin enabled. They are the routing text the host model
# selects on, so their shape is load-bearing, not cosmetic.
#
# The normative grammar lives in `agents/prompt-engineer.md § Description
# grammar` — this script is an implementation of that text, never a second
# definition of it. A rule that disagrees with that section is a bug here.
#
# Asset-class scoping (load-bearing): `commands/*.md` descriptions are menu
# labels for a human picking a slash command, not model-routing text, so they
# carry G6 alone. Paths in no asset class (ad-hoc files passed explicitly) are
# length-only for the same reason — the ambient set is exactly what the
# no-argument enumeration below reaches.
#
# Multi-line YAML scalars (`description: |` / `>`) hide overruns from
# single-line greps — this lint joins continuation lines before measuring.
#
# Usage:
#   desc-lint.sh                 # lint agents/*.md commands/*.md and every skills/**/SKILL.md
#   desc-lint.sh <file> [...]    # lint specific files
#   desc-lint.sh --self-test     # verify the parser and every G-rule against inline fixtures
#
# Exit codes: 0 = clean, 1 = at least one violation, 2 = usage/parser error.
#
# CI / repo-maintenance helper only — never read by agents at runtime.

set -euo pipefail

lint() {
  python3 - "$@" <<'PYEOF'
import os, re, sys

CAP = 250
DOCTRINE = "agents/prompt-engineer.md § Description grammar"

# G1's verb set is an enforced proxy for G4: "Use when …" is the shape that makes
# a trigger-first description easy to write, and unlike G4 it is decidable.
G1_OPENERS = re.compile(r'^(Use|Apply|Invoke|Run)\s')
G2_CONNECTIVES = re.compile(
    r'\b(when|before|after|during|while|if|for|as|on|upon|proactively)\b', re.I)
G2_WINDOW = 60
G3_MAX_SENTENCES = 2
G4_WORKFLOW = re.compile(r'\b(then|next|finally)\b|\bstep\s+\d|->|→', re.I)
# G5 anchors on word boundaries: `AI`, `API` and `SwiftUI` all carry a bare `I`,
# and every one of them is a routing term that must survive the lint.
G5_FIRST_PERSON_I = re.compile(r"(?<![\w'])I(?![\w])")
G5_FIRST_PERSON_WE = re.compile(r"(?<![\w'])(we|our)(?![\w'])", re.I)

INLINE_CODE = re.compile(r'`[^`]*`')
SENTENCE_END = re.compile(r'[.!?](?=\s|$)')


def asset_class(path):
    """agent | skill | command | other — decides which rules apply, per the
    asset-class scoping table in the doctrine section."""
    base = os.path.basename(path)
    parent = os.path.basename(os.path.dirname(os.path.abspath(path)))
    if base == 'SKILL.md':
        return 'skill'
    if parent == 'agents':
        return 'agent'
    if parent == 'commands':
        return 'command'
    return 'other'


def description(path):
    """Joined single-line description, or None when there is nothing to lint."""
    try:
        t = open(path, encoding='utf-8').read()
    except OSError as e:
        print(f"desc-lint: cannot read {path}: {e}", file=sys.stderr)
        return None
    m = re.match(r'^---\r?\n(.*?)\r?\n---', t, re.S)
    if not m:
        return None  # no frontmatter — nothing to lint
    out, cap = [], False
    for ln in m.group(1).split('\n'):
        if re.match(r'^description:', ln):
            cap = True
            v = ln.split(':', 1)[1].strip()
            if v and v not in ('|', '>', '|-', '>-'):
                out.append(v)
            continue
        if cap:
            if re.match(r'^\S', ln):
                break  # next top-level key
            out.append(ln.strip())
    if not cap:
        return None  # no description key — skipped, not failed
    return ' '.join(' '.join(out).split())


def sentence_count(d):
    # Inline code spans carry dots that are not sentence ends (`.context/`,
    # `publish-pl-issue.sh`), so they are masked before terminators are counted.
    masked = INLINE_CODE.sub(lambda m: '`' + '_' * (len(m.group(0)) - 2) + '`', d)
    n = len(SENTENCE_END.findall(masked))
    if masked and not SENTENCE_END.search(masked[-1:] + ' '):
        n += 1  # unterminated tail is still a sentence
    return n


def grammar_violations(d):
    v = []
    if not G1_OPENERS.match(d):
        v.append(("G1", "must open with Use/Apply/Invoke/Run"))
    if not G2_CONNECTIVES.search(d[:G2_WINDOW]):
        v.append(("G2", f"no trigger connective in the first {G2_WINDOW} chars"))
    n = sentence_count(d)
    if n > G3_MAX_SENTENCES:
        v.append(("G3", f"{n} sentences (max {G3_MAX_SENTENCES})"))
    m = G4_WORKFLOW.search(d)
    if m:
        v.append(("G4", f"workflow enumeration ({m.group(0)!r})"))
    m = G5_FIRST_PERSON_I.search(d) or G5_FIRST_PERSON_WE.search(d)
    if m:
        v.append(("G5", f"first person ({m.group(0)!r})"))
    return v


fail = 0
for path in sys.argv[1:]:
    d = description(path)
    if d is None:
        continue
    cls = asset_class(path)
    problems = []
    if cls in ('agent', 'skill'):
        problems += grammar_violations(d)
    n = len(d)
    if n > CAP:
        problems.append(("G6", f"{n} chars (cap {CAP}) — OVER"))
    if problems:
        fail = 1
        for rule, msg in problems:
            print(f"desc-lint: {path}: {msg} [{rule}] — see {DOCTRINE}")
    else:
        print(f"desc-lint: {path}: {n} chars ok")
sys.exit(fail)
PYEOF
}

case "${1:-}" in
  --self-test)
    # Sourced HERE, not at the top: the harness is test code the production path
    # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
    # `.` builtin is a special-builtin error that exits the shell immediately,
    # bypassing an `if ! . …` guard entirely.
    SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/desc-lint-selftest.sh"
    if [ -r "$SELFTEST_LIB_PATH" ]; then
      # shellcheck source=desc-lint-selftest.sh
      # shellcheck disable=SC1090
      . "$SELFTEST_LIB_PATH"
    else
      printf >&2 'desc-lint: self-test harness unreachable at %s — plugin install broken\n' \
        "$SELFTEST_LIB_PATH"
      exit 2
    fi
    self_test
    ;;
  "")
    cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    # `find` rather than a depth-fixed glob: asset_class() calls ANY basename
    # SKILL.md a skill, so a glob is a second, drift-prone definition of the
    # same set — a skill nested one level deeper would be silently ungraded,
    # which is indistinguishable from passing. `sort` because readdir order is
    # filesystem-dependent and the report should be stable.
    # agents/ and commands/ need no such walk: asset_class() keys them on the
    # immediate parent directory, so nothing below them is in either class.
    # shellcheck disable=SC2046
    lint $(ls agents/*.md commands/*.md 2>/dev/null) \
         $(find skills -name SKILL.md 2>/dev/null | sort) \
      | { grep -v " ok$" || true; }
    ;;
  *) lint "$@" ;;
esac
