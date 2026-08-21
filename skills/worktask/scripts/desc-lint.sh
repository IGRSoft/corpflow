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

self_test() {
  td=$(mktemp -d -t desc-lint-XXXXXX)
  trap 'rm -rf "$td"' EXIT
  mkdir -p "$td/agents" "$td/commands" "$td/skills/nested/deep"

  # length parser
  printf -- '---\nname: a\ndescription: short and sweet\nmodel: sonnet\n---\nbody\n' > "$td/ok.md"
  long=$(printf 'x%.0s' {1..130})
  printf -- '---\nname: b\ndescription: |\n  %s\n  %s\nmodel: sonnet\n---\nbody\n' "$long" "$long" > "$td/over.md"
  printf -- '# plain markdown\n' > "$td/plain.md"
  # a frontmatter with no description key at all is skipped, never failed
  printf -- '---\nname: c\nmodel: sonnet\n---\nbody\n' > "$td/nodesc.md"

  # grammar fixtures (agent/skill classes)
  printf -- '---\nname: g\ndescription: Use when reviewing prompt assets. Grammar, routing terms, and cap enforcement.\n---\nbody\n' > "$td/agents/trigger-first.md"
  printf -- '---\nname: g\ndescription: Elite specialist for prompt architecture and model selection.\n---\nbody\n' > "$td/agents/capability-first.md"
  printf -- '---\nname: g\ndescription: Use to review every prompt asset in the plugin catalogue; applies when routing is unclear.\n---\nbody\n' > "$td/agents/no-connective.md"
  printf -- '---\nname: g\ndescription: Use when auditing. First it scores, then it reports. A third sentence lands here.\n---\nbody\n' > "$td/agents/workflow.md"
  printf -- '---\nname: g\ndescription: Use when auditing assets. I will score each description and our team reviews it.\n---\nbody\n' > "$td/agents/first-person.md"
  # G5 must not fire on AI / API / SwiftUI — the word-boundary regression guard
  printf -- '---\nname: g\ndescription: Use when documenting AI, API, or SwiftUI surfaces. Reference docs for routing terms.\n---\nbody\n' > "$td/agents/bare-i-terms.md"
  # commands are exempt from G1-G5 and carry G6 alone
  printf -- '---\nname: g\ndescription: Comprehensive audit of every prompt asset in the plugin.\n---\nbody\n' > "$td/commands/menu-label.md"
  printf -- '---\nname: g\ndescription: Capability-first nested skill, no trigger clause anywhere.\n---\nbody\n' > "$td/skills/nested/deep/SKILL.md"

  pass_files="$td/ok.md $td/plain.md $td/nodesc.md $td/agents/trigger-first.md $td/agents/bare-i-terms.md $td/commands/menu-label.md"
  # shellcheck disable=SC2086
  if ! lint $pass_files >/dev/null; then
    echo "desc-lint self-test: FAIL (compliant fixture flagged)" >&2; exit 2
  fi
  for f in over:G6 agents/capability-first:G1 agents/no-connective:G2 \
           agents/workflow:G3 agents/first-person:G5 skills/nested/deep/SKILL:G1; do
    path="$td/${f%%:*}.md"; rule="${f##*:}"
    if out=$(lint "$path"); then
      echo "desc-lint self-test: FAIL ($rule fixture passed)" >&2; exit 2
    fi
    case "$out" in
      *"[$rule]"*) ;;
      *) echo "desc-lint self-test: FAIL ($rule not reported for $path)" >&2; exit 2 ;;
    esac
    case "$out" in
      *"$path"*) ;;
      *) echo "desc-lint self-test: FAIL (message does not name $path)" >&2; exit 2 ;;
    esac
  done
  # G4 is reported alongside G3 on the workflow fixture; assert it explicitly.
  if out=$(lint "$td/agents/workflow.md"); then :; fi
  case "$out" in
    *"[G4]"*) ;;
    *) echo "desc-lint self-test: FAIL (G4 not reported)" >&2; exit 2 ;;
  esac
  echo "desc-lint self-test: ALL PASS"
}

case "${1:-}" in
  --self-test) self_test ;;
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
