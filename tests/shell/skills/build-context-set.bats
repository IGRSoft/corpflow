#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/build-context-set.sh
# Contracts (from source):
#   Reads agent names from (a) TASK_LIST_JSON, (b) CONTEXT_DIR/*.md, (c) git log.
#   Normalizes company-workflow:<name> and bare <name> to agents/<name>.md.
#   CROSS_PLUGIN:* refs are silently dropped.
#   Only emits paths that EXIST on disk; output is sorted + deduplicated.
#   No --self-test flag in this script; tests drive it via env vars.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/build-context-set.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  # Create minimal agent files that normalize_path checks actually exist.
  mkdir -p "$WD/agents"
  touch "$WD/agents/developer.md"
  touch "$WD/agents/qa-engineer.md"
  touch "$WD/agents/product-manager.md"
}

# --- happy path: TASK_LIST_JSON source ------------------------------------
@test "happy: extracts completed-task agents from TASK_LIST_JSON" {
  cat > "$WD/tasks.json" <<'JSON'
[
  {"status":"completed","metadata":{"agent":"company-workflow:developer"}},
  {"status":"in_progress","metadata":{"agent":"company-workflow:qa-engineer"}},
  {"status":"completed","metadata":{"agent":"company-workflow:product-manager"}}
]
JSON
  # Run from WD so relative path checks hit our stub agent files.
  TASK_LIST_JSON="$WD/tasks.json" CONTEXT_DIR="$WD/.ctx_none" \
    run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # developer and product-manager were completed; qa-engineer was in_progress.
  assert_line "agents/developer.md"
  assert_line "agents/product-manager.md"
  refute_line "agents/qa-engineer.md"
}

# --- edge: CONTEXT_DIR source ----------------------------------------------
@test "KNOWN BUG (BSD sed): CONTEXT_DIR 'agent:' extraction mangled on macOS (build-context-set.sh:59)" {
  # build-context-set.sh strips the metadata key with GNU-only '\s':
  #   sed -E 's/^\s*agent:\s*//; ...'
  # On BSD/macOS sed, '\s' is the LITERAL char 's' (not whitespace), so the space after
  # 'agent:' is not removed. The value becomes " product-manager" and normalize emits
  # "agents/ product-manager.md" (note the embedded space) which does not exist; the
  # `[ -f "$path" ]` test then fails and the path is simply never emitted.
  # Portability bug — REPORTED, not fixed (plan scope). The script exits 0 either way
  # (a read-helper must not fail the caller); the observable difference is the output:
  # GNU sed emits the path, BSD sed emits nothing.
  mkdir -p "$WD/ctx"
  cat > "$WD/ctx/planning-0.md" <<'MD'
---
agent: company-workflow:product-manager
---
# Planning
MD
  TASK_LIST_JSON="" CONTEXT_DIR="$WD/ctx" \
    run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # Use *_output --partial (operates on the $output string) rather than *_line, which
  # errors with "lines: parameter null" when the script produces no stdout (BSD path).
  case "$output" in
    *"agents/company-workflow:product-manager.md"*)
      # Neither sed dialect should ever emit the un-stripped qualified basename.
      false ;;
    *"agents/product-manager.md"*)
      : ;;                                              # GNU sed: bug not triggered
    *)
      refute_output --partial "product-manager" ;;      # BSD/macOS sed: name mangled, nothing emitted
  esac
}

@test "edge: cross-plugin refs (e.g. apple-developer:ios-developer) are dropped" {
  cat > "$WD/tasks.json" <<'JSON'
[
  {"status":"completed","metadata":{"agent":"apple-developer:ios-developer"}},
  {"status":"completed","metadata":{"agent":"company-workflow:developer"}}
]
JSON
  TASK_LIST_JSON="$WD/tasks.json" CONTEXT_DIR="$WD/.ctx_none" \
    run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # Cross-plugin ref must not appear; local developer.md must.
  refute_output --partial "apple-developer"
  assert_line "agents/developer.md"
}

@test "edge: non-existent agent files are dropped (only disk-resident paths emitted)" {
  cat > "$WD/tasks.json" <<'JSON'
[
  {"status":"completed","metadata":{"agent":"company-workflow:nonexistent-ghost-agent"}},
  {"status":"completed","metadata":{"agent":"company-workflow:developer"}}
]
JSON
  TASK_LIST_JSON="$WD/tasks.json" CONTEXT_DIR="$WD/.ctx_none" \
    run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  refute_output --partial "nonexistent-ghost-agent"
  assert_line "agents/developer.md"
}

# --- failure: empty inputs produce empty output (exit 0 is correct) -------
@test "failure: empty task list and empty context dir produce no output (exit 0)" {
  printf '[]\n' > "$WD/empty.json"
  mkdir -p "$WD/ctx_empty"
  TASK_LIST_JSON="$WD/empty.json" CONTEXT_DIR="$WD/ctx_empty" \
    run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output ""
}
