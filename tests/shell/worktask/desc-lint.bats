#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/desc-lint.sh.
# Contracts (from header + body):
#   - explicit-file mode: within cap => "N chars ok", exit 0
#   - over cap (multi-line block scalar joined) => "OVER", exit 1
#   - no-frontmatter file => skipped (no output line), exit 0
#   - --self-test => "ALL PASS", exit 0
#   - agents/skills: G1–G5 grammar enforced, violation names the file and rule
#   - commands/*.md: cap only, grammar exempt
#   - default mode enumerates every skills/**/SKILL.md, at any depth
#   - G6 counts characters, not bytes
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/desc-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  printf -- '---\nname: a\ndescription: short and sweet\nmodel: sonnet\n---\nbody\n' > "$WD/ok.md"
  printf -- '# plain markdown, no frontmatter\n' > "$WD/plain.md"
  # build an over-cap multi-line block scalar (>250 chars joined)
  local long; long=$(printf 'x%.0s' $(seq 1 130))
  printf -- '---\nname: b\ndescription: |\n  %s\n  %s\nmodel: sonnet\n---\nbody\n' "$long" "$long" > "$WD/over.md"
}

@test "happy: a within-cap description passes (exit 0, 'ok')" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/ok.md"
  assert_success
  assert_output --partial "chars ok"
}

@test "edge: no-frontmatter file is skipped (exit 0, no lint line)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/plain.md"
  assert_success
  refute_output --partial "chars"
}

@test "failure: an over-cap multi-line description fails (exit 1, 'OVER')" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/over.md"
  assert_failure 1
  assert_output --partial "OVER"
  assert_output --partial "cap 250"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

# --- cap boundary ------------------------------------------------------------
# The cap is an inclusive <=250: 250 passes, 251 does not. Asserting only a
# far-over case (260+) left the comparison operator itself untested — a `>=`
# slip would have gone unnoticed.

_desc_file() {
  # _desc_file <path> <n> — frontmatter whose joined description is exactly n chars.
  local path="$1" n="$2" body
  body="$(printf 'x%.0s' $(seq 1 "$n"))"
  printf -- '---\nname: a\ndescription: %s\nmodel: sonnet\n---\nbody\n' "$body" > "$path"
}

@test "boundary: 249 chars is within cap (exit 0)" {
  _desc_file "$WD/b249.md" 249
  run_script_env -- "$SCRIPT" "$WD/b249.md"
  assert_success
  assert_output --partial "b249.md: 249 chars ok"
}

@test "boundary: exactly 250 chars is within cap (inclusive, exit 0)" {
  _desc_file "$WD/b250.md" 250
  run_script_env -- "$SCRIPT" "$WD/b250.md"
  assert_success
  assert_output --partial "b250.md: 250 chars ok"
}

@test "boundary: 251 chars is over cap (exit 1)" {
  _desc_file "$WD/b251.md" 251
  run_script_env -- "$SCRIPT" "$WD/b251.md"
  assert_failure 1
  assert_output --partial "251 chars (cap 250) — OVER"
}

@test "boundary: one over-cap file among many fails the whole run" {
  _desc_file "$WD/b250.md" 250
  _desc_file "$WD/b251.md" 251
  run_script_env -- "$SCRIPT" "$WD/ok.md" "$WD/b250.md" "$WD/b251.md"
  assert_failure 1
  assert_output --partial "b251.md: 251 chars"
  # The within-cap files are still reported, not short-circuited away.
  assert_output --partial "b250.md: 250 chars ok"
}

@test "boundary: the cap counts characters, not bytes (multibyte)" {
  # G6 is a character cap. A byte-counting implementation scores this 256 and
  # rejects it; py3's len(str) scores 250 and accepts. Unasserted, the unit of
  # measure is free to drift the next time the reader is rewritten.
  local body
  body="$(printf 'x%.0s' $(seq 1 247))———"
  printf -- '---\nname: a\ndescription: %s\nmodel: sonnet\n---\nbody\n' \
    "$body" > "$WD/em250.md"
  [ "$(printf '%s' "$body" | wc -c | tr -d ' ')" -gt 250 ]
  run_script_env -- "$SCRIPT" "$WD/em250.md"
  assert_success
  assert_output --partial "em250.md: 250 chars ok"
}

# --- default (no-argument) mode ----------------------------------------------

@test "default mode: this repo's own agents/commands/skills are all within cap" {
  # No-argument mode cds to the repo root and lints agents/*.md, commands/*.md
  # and every skills/**/SKILL.md, filtering the ok lines so only violations print.
  # These descriptions are ambient context in every session, so an over-cap one
  # is a real defect. Nothing in the suite exercised this mode before; when it
  # was added it immediately failed on skills/cross-plugin-handoff/SKILL.md.
  run_script_env --cwd "$PLUGIN_ROOT" -- "$SCRIPT"
  assert_success
  assert_output ""
}

@test "default mode: an over-cap file in the default set is found and named" {
  # Falsification arm for the test above, whose clean tree prints nothing: this
  # proves no-argument mode really walks agents/ and reports what it finds.
  # Grammar-compliant prefix so the only rule this fixture breaks is the cap.
  local repo body
  body="Use when linting. $(printf 'x%.0s' $(seq 1 233))"
  repo="$(mk_git_fixture \
    --file "agents/bad.md:---\nname: bad\ndescription: ${body}\n---\nbody\n" \
    --file 'agents/good.md:---\nname: good\ndescription: Use when linting. Fine.\n---\nbody\n')"
  run_script_env --cwd "$repo" -- "$SCRIPT"
  assert_failure 1
  assert_output --partial "agents/bad.md: 251 chars (cap 250) — OVER"
  refute_output --partial "agents/good.md"
}

# --- description grammar (G1–G5) ---------------------------------------------
# The grammar is normative in `agents/prompt-engineer.md § Description grammar`;
# these cases pin the linter to that text, not the other way round. Scoping is
# load-bearing: agents and skills carry G1–G5, `commands/*.md` carry the cap
# alone, so a case for each class is what keeps the exemption from drifting.

_asset() {
  # _asset <relpath-under-WD> <description>
  local path="$WD/$1"
  mkdir -p "$(dirname "$path")"
  printf -- '---\nname: a\ndescription: %s\n---\nbody\n' "$2" > "$path"
}

@test "grammar: a trigger-first agent description passes (exit 0)" {
  _asset agents/good.md 'Use when auditing prompt assets. Grammar, routing terms, and cap enforcement.'
  run_script_env -- "$SCRIPT" "$WD/agents/good.md"
  assert_success
  assert_output --partial "chars ok"
}

@test "grammar: a capability-first agent description fails, naming the file (G1)" {
  _asset agents/bad.md 'Elite specialist for prompt architecture and model selection.'
  run_script_env -- "$SCRIPT" "$WD/agents/bad.md"
  assert_failure 1
  assert_output --partial "agents/bad.md"
  assert_output --partial "[G1]"
  assert_output --partial "must open with Use/Apply/Invoke/Run"
}

@test "grammar: the failure message points at the doctrine section (AD-1)" {
  _asset agents/bad.md 'Elite specialist for prompt architecture and model selection.'
  run_script_env -- "$SCRIPT" "$WD/agents/bad.md"
  assert_failure 1
  assert_output --partial "agents/prompt-engineer.md § Description grammar"
}

@test "grammar: a trigger clause outside the first 60 chars fails (G2)" {
  _asset agents/late.md 'Use to review every prompt asset in the plugin catalogue; applies when routing is unclear.'
  run_script_env -- "$SCRIPT" "$WD/agents/late.md"
  assert_failure 1
  assert_output --partial "[G2]"
}

@test "grammar: a third sentence fails (G3)" {
  _asset agents/three.md 'Use when auditing assets. Grammar and routing terms. A third sentence lands here.'
  run_script_env -- "$SCRIPT" "$WD/agents/three.md"
  assert_failure 1
  assert_output --partial "[G3]"
  assert_output --partial "3 sentences"
}

@test "grammar: dots inside inline code are not sentence ends (G3 false-positive guard)" {
  _asset agents/code.md 'Use when a repeat run finds `.context/state.json` and `publish-pl-issue.sh`. Ledger notes.'
  run_script_env -- "$SCRIPT" "$WD/agents/code.md"
  assert_success
}

@test "grammar: workflow enumeration fails (G4)" {
  _asset agents/flow.md 'Use when auditing assets, then scoring them. Grammar and routing terms.'
  run_script_env -- "$SCRIPT" "$WD/agents/flow.md"
  assert_failure 1
  assert_output --partial "[G4]"
}

@test "grammar: first-person pronouns fail (G5)" {
  _asset agents/me.md 'Use when auditing assets. I score each description and our team reviews it.'
  run_script_env -- "$SCRIPT" "$WD/agents/me.md"
  assert_failure 1
  assert_output --partial "[G5]"
}

@test "grammar: G5 does not fire on AI, API or SwiftUI (word-boundary anchor)" {
  # A raw `I ` substring match would flag six shipped descriptions on routing
  # terms that predate the grammar; the pronoun rule must anchor on words.
  _asset agents/terms.md 'Use when documenting AI, API, or SwiftUI surfaces. Reference docs for routing terms.'
  run_script_env -- "$SCRIPT" "$WD/agents/terms.md"
  assert_success
  assert_output --partial "chars ok"
}

@test "scoping: a capability-first command description still passes (G1–G5 exempt)" {
  _asset commands/menu.md 'Comprehensive audit of agents, commands, and prompts for quality and consistency.'
  run_script_env -- "$SCRIPT" "$WD/commands/menu.md"
  assert_success
  assert_output --partial "chars ok"
}

@test "scoping: a command description still fails the cap (G6 applies)" {
  _asset commands/long.md "$(printf 'x%.0s' $(seq 1 251))"
  run_script_env -- "$SCRIPT" "$WD/commands/long.md"
  assert_failure 1
  assert_output --partial "[G6]"
}

@test "edge: frontmatter without a description key is skipped, not failed" {
  mkdir -p "$WD/agents"
  printf -- '---\nname: a\nmodel: sonnet\n---\nbody\n' > "$WD/agents/nodesc.md"
  run_script_env -- "$SCRIPT" "$WD/agents/nodesc.md"
  assert_success
  refute_output --partial "chars"
}

# --- asset enumeration --------------------------------------------------------
# `asset_class()` calls any basename SKILL.md a skill at any depth, so default
# mode walks `skills/` with find rather than a depth-fixed glob. These cases pin
# the two definitions together: a skill deeper than the old glob reached must
# still be graded, or it is silently unchecked.

@test "glob: default mode reaches a nested skills/*/*/SKILL.md" {
  # The narrow `skills/*/SKILL.md` glob silently skipped every nested skill —
  # an unchecked asset is indistinguishable from a passing one.
  local repo
  repo="$(mk_git_fixture \
    --file 'skills/shared/nested/SKILL.md:---\nname: nested\ndescription: Capability-first nested skill, no trigger clause.\n---\nbody\n' \
    --file 'skills/flat/SKILL.md:---\nname: flat\ndescription: Use when flat. Fine.\n---\nbody\n')"
  run_script_env --cwd "$repo" -- "$SCRIPT"
  assert_failure 1
  assert_output --partial "skills/shared/nested/SKILL.md"
  assert_output --partial "[G1]"
  refute_output --partial "skills/flat/SKILL.md"
}

@test "glob: a compliant nested skill is enumerated and passes" {
  local repo
  repo="$(mk_git_fixture \
    --file 'skills/shared/nested/SKILL.md:---\nname: nested\ndescription: Use when initializing milestone workspaces. Helper patterns.\n---\nbody\n')"
  run_script_env --cwd "$repo" -- "$SCRIPT"
  assert_success
  assert_output ""
}

@test "enumeration: default mode reaches a skill deeper than any fixed glob" {
  # `skills/*/*/SKILL.md` stopped at depth 3; asset_class() never did. This
  # fixture sits at depth 5 and must still be graded.
  local repo
  repo="$(mk_git_fixture \
    --file 'skills/a/b/c/SKILL.md:---\nname: deep\ndescription: Capability-first deep skill, no trigger clause.\n---\nbody\n' \
    --file 'skills/flat/SKILL.md:---\nname: flat\ndescription: Use when flat. Fine.\n---\nbody\n')"
  run_script_env --cwd "$repo" -- "$SCRIPT"
  assert_failure 1
  assert_output --partial "skills/a/b/c/SKILL.md"
  assert_output --partial "[G1]"
  refute_output --partial "skills/flat/SKILL.md"
}
