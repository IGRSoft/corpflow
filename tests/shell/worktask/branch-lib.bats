#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/branch-lib.sh.
# Structural tests (T1-T3) pin the residual risk: an unreachable library is
# the only failure mode this file may have (skills/shared/git-conventions.md
# § Branch Naming).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="skills/worktask/scripts/branch-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  cat > "$WD/.context/state.json" <<'EOF'
{"version":1,"worktask_id":"wt-demo","run_index":0,"platform":"systems",
 "plan_file":".context/planning-0.md","tasks":{},"facts":{},"handoffs":{},"metadata":{}}
EOF
}

mk_no_jq_path() {
  local dir="$WD/nobin" tool p
  mkdir -p "$dir"
  for tool in git grep sed tr cut date mkdir bash sh env printf true false cat; do
    p=$(command -v "$tool" 2> /dev/null) || continue
    ln -sf "$p" "$dir/$tool"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T1 — double-source, one process, no state.json, strict mode: rc 0, no output.
# ---------------------------------------------------------------------------
@test "T1: branch-lib.sh sources twice cleanly under set -euo pipefail" {
  cd "$WD"
  run bash -c "set -euo pipefail; IFS=\$'\n\t'; . '$PLUGIN_ROOT/$LIB'; . '$PLUGIN_ROOT/$LIB'"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# T2 — symbol inventory: all 10 required functions defined after one source.
# ---------------------------------------------------------------------------
@test "T2: all 14 required symbols are defined after sourcing" {
  cd "$WD"
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    for f in branch_type_regex branch_is_conventional resolve_goal derive_type \
             derive_ticket slug_body slug_budget slug_is_truncated derive_slug \
             target_branch_name meta_json audit_fn \
             fn_batch_scope resolve_base_ref; do
      type -t \"\$f\" > /dev/null 2>&1 || { printf 'MISSING: %s\n' \"\$f\"; exit 1; }
    done
    exit 0
  "
  assert_success
}

# ---------------------------------------------------------------------------
# T3 — grep-based dependency-free structural assertion.
# ---------------------------------------------------------------------------
@test "T3: branch-lib.sh sources nothing, sets no options, no readonly, no global IFS" {
  run bash -c "grep -Ec '^[[:space:]]*(\.|source)[[:space:]]' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
  run bash -c "grep -Ec '^[[:space:]]*(set|shopt|trap)[[:space:]]' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
  run bash -c "grep -c '^readonly' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
  run bash -c "grep -Ec '^[[:space:]]*IFS=' '$PLUGIN_ROOT/$LIB' || true"
  assert_output "0"
}

# ---------------------------------------------------------------------------
# derive_type / derive_slug / target_branch_name — pure unit tests.
# ---------------------------------------------------------------------------
@test "derive_type: unmatched goal falls back to feature (not feat)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Add login flow'"
  assert_success
  assert_output "feature"
}

@test "derive_type: fix keywords map to bugfix (not fix)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Fix crash on startup'"
  assert_success
  assert_output "bugfix"
}

@test "derive_type: revert keyword maps to revert" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Revert the last release'"
  assert_success
  assert_output "revert"
}

@test "derive_type: hotfix keyword maps to hotfix (not bugfix)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'Ship a hotfix for prod'"
  assert_success
  assert_output "hotfix"
}

@test "derive_type: hotfix wins even when the goal also contains crash/bug (case ordering)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_type 'hotfix for a bug causing a crash'"
  assert_success
  assert_output "hotfix"
}

@test "derive_type: every output is a member of BRANCH_TYPES (AR ruling-4 self-test)" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    is_member() {
      local needle=\"\$1\" t
      local IFS=\$'\n'
      for t in \$BRANCH_TYPES; do
        [ \"\$t\" = \"\$needle\" ] && return 0
      done
      return 1
    }
    for g in 'random goal' 'fix bug' 'ship a hotfix' 'refactor module' 'perf tuning' \
             'add docs' 'chore bump deps' 'ci pipeline' 'build packaging' \
             'test coverage' 'revert x'; do
      t=\$(derive_type \"\$g\")
      is_member \"\$t\" || { printf 'BAD (not in BRANCH_TYPES): %s -> %s\n' \"\$g\" \"\$t\"; exit 1; }
    done
    exit 0
  "
  assert_success
}

@test "derive_type: a typo'd arm output (e.g. 'perff') would be caught by the ∈ BRANCH_TYPES self-test" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    is_member() {
      local needle=\"\$1\" t
      local IFS=\$'\n'
      for t in \$BRANCH_TYPES; do
        [ \"\$t\" = \"\$needle\" ] && return 0
      done
      return 1
    }
    is_member 'perff' && exit 1
    exit 0
  "
  assert_success
}

# D4 — `fix` matched as a word, plus the defect vocabulary. Every string in the
# "verified today" column of the defect report is pinned here.
@test "derive_type: table-driven goal -> type mapping (D4)" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    rc=0
    while IFS='|' read -r goal want; do
      [ -n \"\$goal\" ] || continue
      got=\$(derive_type \"\$goal\")
      if [ \"\$got\" != \"\$want\" ]; then
        printf 'MISMATCH: %s -> %s (want %s)\n' \"\$goal\" \"\$got\" \"\$want\"
        rc=1
      fi
    done <<'TABLE'
Images blink on catalog open, investigate and fix|bugfix
Catalog images blink before rendering|bugfix
Product images flicker on open|bugfix
Investigate and fix|bugfix
Something is off, please fix.|bugfix
fix|bugfix
Fix crash on startup|bugfix
Rendering glitch in the grid|bugfix
Thumbnail cache is broken|bugfix
Scroll regression after the 2.1 release|bugfix
Totals are incorrect on export|bugfix
Wrong locale on first launch|bugfix
Upload fails on retry|bugfix
Sync failing intermittently|bugfix
Prefix handling in the fixture parser|feature
Add suffix support to filenames|feature
Ship a hotfix for prod|hotfix
hotfix for a bug causing a crash|hotfix
Revert the last release|revert
Add dark mode support|feature
Refactor the module boundaries|refactor
Optimise startup perf|perf
Document the public API|docs
Improve test coverage|test
Bump the dependency|chore
TABLE
    exit \$rc
  "
  assert_success
}

# ---------------------------------------------------------------------------
# derive_ticket — D2.
# ---------------------------------------------------------------------------
@test "derive_ticket: extracts the first issue key, lowercased" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_ticket 'OV-164 Product images blink'"
  assert_success
  assert_output "ov-164"
}

@test "derive_ticket: first key wins when the goal names several" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_ticket 'OV-161 blocks ABC-9 somehow'"
  assert_success
  assert_output "ov-161"
}

@test "derive_ticket: no key in the goal yields empty (ticket-less shape unchanged)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_ticket 'Add dark mode support'"
  assert_success
  assert_output ""
}

@test "derive_ticket: an already-lowercased token is not a key" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_ticket 'work on ov-164 today'"
  assert_success
  assert_output ""
}

@test "derive_ticket: a no-match run does not kill a set -euo pipefail caller" {
  run bash -c "set -euo pipefail; IFS=\$'\n\t'; . '$PLUGIN_ROOT/$LIB'
    t=\$(derive_ticket 'no key at all'); printf 'survived=%s' \"\$t\""
  assert_success
  assert_output "survived="
}

@test "derive_slug: kebab-cases, trims, and caps at 48 chars" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_slug 'Fix: crash on startup!!!'"
  assert_success
  assert_output "fix-crash-on-startup"
}

@test "derive_slug: multi-line goal collapses to a single-line slug (regression)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_slug \$'Fix PR composition\nand branch naming'"
  assert_success
  refute_output --partial $'\n'
  assert_output "fix-pr-composition-and-branch-naming"
}

# D3 — the exact goal that produced `…-blinking-before-r` before the fix.
@test "derive_slug: truncation drops the trailing partial word, never cuts mid-word" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    derive_slug 'Product list images are blinking before rendering on the catalog screen'"
  assert_success
  assert_output "product-list-images-are-blinking-before"
  refute_output --partial "-renderin"
}

@test "derive_slug: output is always a whole-word prefix of the untruncated kebab (D3)" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    rc=0
    while IFS= read -r goal; do
      [ -n \"\$goal\" ] || continue
      full=\$(printf '%s' \"\$goal\" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*\$//')
      got=\$(derive_slug \"\$goal\")
      case \"\$full\" in
        \"\$got\") ;;
        \"\$got\"-*) ;;
        *) printf 'NOT A WHOLE-WORD PREFIX: %s -> %s\n' \"\$goal\" \"\$got\"; rc=1 ;;
      esac
      case \"\$got\" in
        *-) printf 'TRAILING SEPARATOR: %s\n' \"\$got\"; rc=1 ;;
      esac
    done <<'TABLE'
Product list images are blinking before rendering on the catalog screen
aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll mmm nnn ooo
aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk
Fix the reconstruction scan flow so it stops dropping frames midway
short goal
TABLE
    exit \$rc
  "
  assert_success
}

@test "derive_slug: a single word longer than the budget survives whole (never empty)" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    derive_slug 'supercalifragilisticexpialidociousnessfactorial tail'"
  assert_success
  assert_output "supercalifragilisticexpialidociousnessfactorial"
}

@test "derive_slug: ticket prefix is budgeted inside the 48-char cap" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    k=ov-164
    s=\$(derive_slug 'OV-164 Product list images are blinking before rendering on catalog' \"\$k\")
    printf '%s-%s|%s' \"\$k\" \"\$s\" \"\${#k}\"
    c=\"\$k-\$s\"
    [ \"\${#c}\" -le 48 ] || { printf ' OVER-BUDGET(%s)' \"\${#c}\"; exit 1; }
  "
  assert_success
  assert_output --partial "ov-164-product-list-images-are-blinking-before|"
}

@test "derive_slug: a long issue key cannot starve the slug to nothing" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    derive_slug 'VERYLONGPROJECTKEY-123456789 reconstruction scan flow drops frames' \
      'verylongprojectkey-123456789'"
  assert_success
  refute_output ""
  refute_output --regexp -- '-$'
}

@test "derive_slug: the ticket is stripped from the slug body — no duplicate key" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_slug 'OV-156 reconstruction scan flow' 'ov-156'"
  assert_success
  assert_output "reconstruction-scan-flow"
}

@test "derive_slug: adjacent repeats of the key are all stripped" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; derive_slug 'OV-1 OV-1 scan flow OV-1' 'ov-1'"
  assert_success
  assert_output "scan-flow"
}

@test "target_branch_name: composes <type>/<slug>" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; target_branch_name feature add-login-flow"
  assert_success
  assert_output "feature/add-login-flow"
}

@test "target_branch_name: composes <type>/<ticket>-<slug> when a ticket is supplied" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; target_branch_name bugfix reconstruction-scan-flow ov-156"
  assert_success
  assert_output "bugfix/ov-156-reconstruction-scan-flow"
}

@test "target_branch_name: an empty ticket argument yields the ticket-less shape" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; target_branch_name feature add-login-flow ''"
  assert_success
  assert_output "feature/add-login-flow"
}

@test "target_branch_name: empty slug returns 1, no output" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; target_branch_name feature ''"
  assert_failure
  assert_output ""
}

# ---------------------------------------------------------------------------
# slug_is_truncated — AC-4 (8 assertions). The budget is 48; a ticket and its
# separator are spent inside it.
# ---------------------------------------------------------------------------

# Bodies pinned by construction, not by eye: 5x8 chars + "abc" + 5 separators = 48.
BODY_48="a2345678 b2345678 c2345678 d2345678 e2345678 abc"
BODY_49="a2345678 b2345678 c2345678 d2345678 e2345678 abcd"

@test "AC-4/1: a long goal with no ticket is truncated" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    slug_is_truncated 'Product list images are blinking before rendering on the catalog screen' ''"
  assert_success
}

@test "AC-4/2: a short goal with no ticket is not truncated" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; slug_is_truncated 'Add login flow' ''"
  assert_failure 1
}

@test "AC-4/3: a goal exactly at the budget boundary is not truncated" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    b=\$(slug_body '$BODY_48' '')
    [ \"\${#b}\" -eq 48 ] || { printf 'BODY LEN %s, want 48\n' \"\${#b}\"; exit 2; }
    slug_is_truncated '$BODY_48' ''"
  assert_failure 1
}

@test "AC-4/4: a goal one character over the budget is truncated" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    b=\$(slug_body '$BODY_49' '')
    [ \"\${#b}\" -eq 49 ] || { printf 'BODY LEN %s, want 49\n' \"\${#b}\"; exit 2; }
    slug_is_truncated '$BODY_49' ''"
  assert_success
}

@test "AC-4/5: ticket present, body inside the reduced budget — not truncated" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    [ \"\$(slug_budget ov-164)\" = 41 ] || { printf 'BUDGET %s, want 41\n' \"\$(slug_budget ov-164)\"; exit 2; }
    slug_is_truncated 'OV-164 aaaaaaaa bbbbbbbb cccccccc dddddddd eeeee' 'ov-164'"
  assert_failure 1
}

@test "AC-4/6: ticket present, body over the reduced budget — truncated" {
  # Identical to AC-4/5 plus one character: the ticket segment is what makes it overflow.
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    slug_is_truncated 'OV-164 aaaaaaaa bbbbbbbb cccccccc dddddddd eeeeee' 'ov-164'"
  assert_success
}

@test "AC-4/7: one word longer than the budget — truncated, slug still non-empty" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    slug_is_truncated 'supercalifragilisticexpialidociousnessfactorial tail' ''"
  assert_success
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    derive_slug 'supercalifragilisticexpialidociousnessfactorial tail' ''"
  assert_success
  assert_output "supercalifragilisticexpialidociousnessfactorial"
}

# The defect this predicate exists to avoid: `slug=$(derive_slug …)` runs in a subshell,
# so a flag assigned inside the derivation can never reach the caller.
@test "AC-4/8: the answer is identical called directly and through command substitution" {
  run bash -c "
    . '$PLUGIN_ROOT/$LIB'
    rc=0
    while IFS= read -r goal; do
      [ -n \"\$goal\" ] || continue
      direct=0; slug_is_truncated \"\$goal\" '' || direct=1
      sub=\$( slug_is_truncated \"\$goal\" '' && printf 0 || printf 1 )
      s=\$(derive_slug \"\$goal\" '')
      [ -n \"\$s\" ] || { printf 'EMPTY SLUG: %s\n' \"\$goal\"; rc=1; }
      [ \"\$direct\" = \"\$sub\" ] || { printf 'DISAGREE (%s vs %s): %s\n' \"\$direct\" \"\$sub\" \"\$goal\"; rc=1; }
    done <<'TABLE'
Product list images are blinking before rendering on the catalog screen
Add login flow
$BODY_48
$BODY_49
supercalifragilisticexpialidociousnessfactorial tail
TABLE
    exit \$rc
  "
  assert_success
}

@test "slug_budget: no ticket is 48; a ticket spends its own length plus a separator" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; slug_budget ''"
  assert_output "48"
  run bash -c ". '$PLUGIN_ROOT/$LIB'; slug_budget 'ov-156'"
  assert_output "41"
  # Floored at 1: a zero-length slug would make target_branch_name refuse outright.
  run bash -c ". '$PLUGIN_ROOT/$LIB'; slug_budget 'verylongprojectkey-123456789012345678901234567890'"
  assert_output "1"
}

@test "slug_body: uncapped, ticket-stripped, never a trailing separator" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; slug_body 'OV-156 reconstruction scan flow!!!' 'ov-156'"
  assert_success
  assert_output "reconstruction-scan-flow"
  run bash -c ". '$PLUGIN_ROOT/$LIB'
    b=\$(slug_body 'Product list images are blinking before rendering on the catalog screen' '')
    printf '%s' \"\${#b}\""
  assert_output "71"
}

# ---------------------------------------------------------------------------
# branch_is_conventional — AC-4 / AC-5.
# ---------------------------------------------------------------------------
@test "AC-4: milestone-helpers batch output is accepted by branch_is_conventional" {
  b=$(bash "$PLUGIN_ROOT/skills/shared/milestone-helpers/scripts/milestone-helpers.sh" \
    branch-name 42 "Add login flow")
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional '$b'"
  assert_success
}

@test "AC-5 (binding): feature/lyon is recognised as conventional" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'feature/lyon'"
  assert_success
}

@test "branch_is_conventional: a non-conventional name returns 1" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'wt-abc123'"
  assert_failure 1
}

@test "branch_is_conventional: already-conventional short form (feat) is accepted" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'feat/221-thing'"
  assert_success
}

@test "branch_is_conventional: fix/ is removed cleanly — a fix/ branch is rejected" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'fix/crash-on-startup'"
  assert_failure 1
}

# D2 — both grammar shapes are conventional. An existing ticketed branch must never
# become non-conventional and get churned.
@test "branch_is_conventional: the ticketed shape is accepted" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'bugfix/ov-156-reconstruction-scan-flow'"
  assert_success
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'feature/ov-161-add-dark-mode'"
  assert_success
}

@test "branch_is_conventional: the ticket-less shape is still accepted" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'feature/add-dark-mode'"
  assert_success
}

@test "branch_is_conventional: rejects fix/x and a bare no-type-prefix name" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'fix/x'"
  assert_failure 1
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'no-type-prefix'"
  assert_failure 1
}

@test "branch_is_conventional: bugfix/ and hotfix/ are accepted" {
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'bugfix/crash-on-startup'"
  assert_success
  run bash -c ". '$PLUGIN_ROOT/$LIB'; branch_is_conventional 'hotfix/crash-on-startup'"
  assert_success
}

# ---------------------------------------------------------------------------
# resolve_goal — ranked fallbacks (sign-offs 4/5/6).
# ---------------------------------------------------------------------------
@test "resolve_goal: explicit argument wins over the ledger" {
  cd "$WD"
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal 'explicit goal'"
  assert_success
  assert_output "explicit goal"
}

@test "resolve_goal: empty explicit argument ranks past to facts.goal (shell -z semantics)" {
  cd "$WD"
  jq '.facts.goal = "Ledger goal here"' .context/state.json > s && mv s .context/state.json
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal ''"
  assert_success
  assert_output "Ledger goal here"
}

@test "resolve_goal: empty goal AND empty facts.goal falls back to worktask_id" {
  cd "$WD"
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal ''"
  assert_success
  assert_output "wt-demo"
}

@test "resolve_goal: jq-less run cannot read the ledger — refuses down to empty" {
  cd "$WD"
  jq '.facts.goal = "Ledger goal here"' .context/state.json > s && mv s .context/state.json
  local nobin
  nobin=$(mk_no_jq_path)
  run env PATH="$nobin" bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; resolve_goal ''"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# fn_batch_scope — parity migration (F14 intent).
# ---------------------------------------------------------------------------
@test "fn_batch_scope: MILESTONE_MODE=1 self-disables" {
  cd "$WD"
  run env MILESTONE_MODE=1 bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; fn_batch_scope && printf '%s' \"\$SCOPE_REASON\""
  assert_success
  assert_output "milestone_mode_env"
}

@test "fn_batch_scope: no batch/incident signal returns 1" {
  cd "$WD"
  run bash -c "STATE_PATH=.context/state.json; . '$PLUGIN_ROOT/$LIB'; fn_batch_scope"
  assert_failure 1
}
