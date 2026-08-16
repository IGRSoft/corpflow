#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/build-context-set.sh
# Contracts (from source):
#   Reads agent names from (a) LEDGER_JSON, (b) CONTEXT_DIR/*.md `agent:`
#   trailers, (c) `git log $BASELINE_SHA..HEAD` `Agent:` trailers.
#   Normalizes corpflow:<name> to agents/<name>.md (also probing the
#   commands/ and skills/ spellings). CROSS_PLUGIN:* refs are dropped.
#   Only emits paths that EXIST on disk, relative to the CWD; output is sorted
#   and deduplicated. No --self-test flag; the tests drive it via env vars.
#
# Every case runs with --cwd on a scratch tree that owns its own agents/, so the
# expected output is an exact, fixture-determined file list rather than whatever
# the real repo happens to contain.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/build-context-set.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/agents"
  : > "$WD/agents/developer.md"
  : > "$WD/agents/qa-engineer.md"
  : > "$WD/agents/product-manager.md"
}

# Trailer keys are stripped with POSIX bracket classes, so every source below
# asserts one exact output on every sed/grep dialect. The earlier `\s` spelling
# was GNU-only and silently dropped the spaced form on BSD/macOS; these tests
# are what would go red if it came back.
# --- source 1: LEDGER_JSON ------------------------------------------------

@test "source 1: only completed-task agents are emitted, sorted and deduped" {
  cat > "$WD/tasks.json" <<'JSON'
{"version":2,"tasks":{
  "DV0":{"status":"completed","metadata":{"agent":"corpflow:developer"}},
  "QA0":{"status":"in_progress","metadata":{"agent":"corpflow:qa-engineer"}},
  "PL0":{"status":"completed","metadata":{"agent":"corpflow:product-manager"}},
  "DV1":{"status":"completed","metadata":{"agent":"corpflow:developer"}}
}}
JSON
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/tasks.json" --env "CONTEXT_DIR=$WD/.ctx_none" \
    -- "$SCRIPT"
  assert_success
  assert_output "agents/developer.md
agents/product-manager.md"
}

@test "source 1: cross-plugin refs are dropped, local ones kept" {
  cat > "$WD/tasks.json" <<'JSON'
{"version":2,"tasks":{
  "DV0":{"status":"completed","metadata":{"agent":"apple-developer:ios-developer"}},
  "DV1":{"status":"completed","metadata":{"agent":"corpflow:developer"}}
}}
JSON
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/tasks.json" --env "CONTEXT_DIR=$WD/.ctx_none" \
    -- "$SCRIPT"
  assert_success
  assert_output "agents/developer.md"
}

@test "source 1: names with no file on disk are dropped" {
  cat > "$WD/tasks.json" <<'JSON'
{"version":2,"tasks":{
  "DV0":{"status":"completed","metadata":{"agent":"corpflow:nonexistent-ghost-agent"}},
  "DV1":{"status":"completed","metadata":{"agent":"corpflow:developer"}}
}}
JSON
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/tasks.json" --env "CONTEXT_DIR=$WD/.ctx_none" \
    -- "$SCRIPT"
  assert_success
  assert_output "agents/developer.md"
}

@test "source 1: embedded_commands entries resolve to commands/<name>.md" {
  mkdir -p "$WD/commands"
  : > "$WD/commands/worktask.md"
  cat > "$WD/tasks.json" <<'JSON'
{"version":2,"tasks":{
  "DV0":{"status":"completed","metadata":{"agent":"corpflow:developer","embedded_commands":"corpflow:worktask"}}
}}
JSON
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/tasks.json" --env "CONTEXT_DIR=$WD/.ctx_none" \
    -- "$SCRIPT"
  assert_success
  # Each qualified ref probes agents/, commands/ and skills/; only the
  # spellings that exist on disk survive the filter.
  assert_output "agents/developer.md
commands/worktask.md"
}

# --- source 2: CONTEXT_DIR trailers ------------------------------------------

@test "source 2: CONTEXT_DIR 'agent:' trailer resolves on every sed dialect" {
  mkdir -p "$WD/ctx"
  cat > "$WD/ctx/planning-0.md" <<'MD'
---
agent: corpflow:product-manager
---
# Planning
MD
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=" --env "CONTEXT_DIR=$WD/ctx" -- "$SCRIPT"
  assert_success
  assert_output "agents/product-manager.md"
}

@test "source 2: an INDENTED 'agent:' trailer resolves too" {
  mkdir -p "$WD/ctx"
  # The leading-space arm of the same POSIX-class fix: `^[[:space:]]*` has to
  # hold at both ends of the key, not only after the colon.
  : > "$WD/agents/software-architector.md"
  cat > "$WD/ctx/architecture-0.md" <<'MD'
metadata:
    agent: corpflow:software-architector
MD
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=" --env "CONTEXT_DIR=$WD/ctx" -- "$SCRIPT"
  assert_success
  assert_output "agents/software-architector.md"
}

@test "source 2: a trailer value with no leading space resolves on every sed" {
  mkdir -p "$WD/ctx"
  printf 'agent:corpflow:qa-engineer\n' > "$WD/ctx/development-0.md"
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=" --env "CONTEXT_DIR=$WD/ctx" -- "$SCRIPT"
  assert_success
  assert_output "agents/qa-engineer.md"
}

# --- source 3: git log Agent: trailers ---------------------------------------

@test "source 3: BASELINE_SHA..HEAD trailers are read and the range is honoured" {
  local repo base
  repo="$(mk_git_fixture \
    --file 'agents/qa-engineer.md:x\n' \
    --commit "$(printf 'chore: before baseline\n\nAgent:corpflow:qa-engineer')" \
    --file 'agents/developer.md:x\n' \
    --commit "$(printf 'feat: after baseline\n\nAgent:corpflow:developer')")"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  run_script_env --cwd "$repo" \
    --env "LEDGER_JSON=" --env "CONTEXT_DIR=$repo/.ctx_none" \
    --env "BASELINE_SHA=$base" -- "$SCRIPT"
  assert_success
  # qa-engineer's trailer is on the baseline commit itself, outside the range.
  assert_output "agents/developer.md"
}

@test "source 3: conventional 'Agent: <name>' trailer resolves on every sed dialect" {
  local repo base
  repo="$(mk_git_fixture \
    --file 'agents/developer.md:x\n' \
    --commit 'chore: base' \
    --file 'note.txt:x\n' \
    --commit "$(printf 'feat: work\n\nAgent: corpflow:developer')")"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  run_script_env --cwd "$repo" \
    --env "LEDGER_JSON=" --env "CONTEXT_DIR=$repo/.ctx_none" \
    --env "BASELINE_SHA=$base" -- "$SCRIPT"
  assert_success
  assert_output "agents/developer.md"
}

# --- local plugin naming -----------------------------------------------------

# The whole pipeline is gated on this set being non-empty: a ref classified as
# cross-plugin is dropped, and an empty set makes map-and-filter discard every
# change, so Step 5b never writes a label. These two cases are what would go red
# if the accepted-prefix list narrowed back to a single hard-coded name.
@test "legacy igrsoft: refs resolve to local files" {
  cat > "$WD/tasks.json" <<'JSON'
{"version":2,"tasks":{
  "DV0":{"status":"completed","metadata":{"agent":"igrsoft:developer"}}
}}
JSON
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/tasks.json" --env "CONTEXT_DIR=$WD/.ctx_none" \
    -- "$SCRIPT"
  assert_success
  assert_output "agents/developer.md"
}

@test "the manifest's own plugin name is accepted as local" {
  mkdir -p "$WD/.claude-plugin"
  printf '{"name":"renamed-plugin","version":"9.0.0"}\n' > "$WD/.claude-plugin/plugin.json"
  cat > "$WD/tasks.json" <<'JSON'
{"version":2,"tasks":{
  "DV0":{"status":"completed","metadata":{"agent":"renamed-plugin:developer"}},
  "QA0":{"status":"completed","metadata":{"agent":"apple-developer:qa-engineer"}}
}}
JSON
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/tasks.json" --env "CONTEXT_DIR=$WD/.ctx_none" \
    -- "$SCRIPT"
  assert_success
  assert_output "agents/developer.md"
}

# --- empty inputs ------------------------------------------------------------

@test "empty task list and empty context dir produce no output (exit 0)" {
  printf '[]\n' > "$WD/empty.json"
  mkdir -p "$WD/ctx_empty"
  run_script_env --cwd "$WD" \
    --env "LEDGER_JSON=$WD/empty.json" --env "CONTEXT_DIR=$WD/ctx_empty" \
    -- "$SCRIPT"
  assert_success
  assert_output ""
}
