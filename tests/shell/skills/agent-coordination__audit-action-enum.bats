#!/usr/bin/env bats
# skills/agent-coordination/references/audit-actions.md is the registry of audit
# `action` values every audit.jsonl reader keys on. A script that writes an action
# the registry lacks leaves readers and reviewers with an undocumented value, so
# every literal action a shipped script writes must be listed.
#
# Covered write shapes: `--action <lit>` (corpflow_audit_row and
# corpflow_hook_audit_row), a jq/JSON `action: "<lit>"` object key, and the
# script-local wrappers whose first action-bearing argument is a literal.
# Actions built from variables and actions only described in prose are outside
# what a grep can prove; the registry still lists them.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

REGISTRY="$PLUGIN_ROOT/skills/agent-coordination/references/audit-actions.md"

# Registry values: the backticked names on each `actions:` line.
_enum_values() {
  grep '^actions: ' "$REGISTRY" | grep -oE '`[a-z_]+`' | tr -d '`'
}

# Shipped shell writers: hooks and skills, minus self-tests and fixtures.
_writer_files() {
  find "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/skills" -type f -name '*.sh' \
    ! -name '*selftest*' ! -path '*/fixtures/*' ! -path '*/tests/*'
}

_written_actions() {
  local f
  while IFS= read -r f; do
    grep -ohE -- '--action[ =]+"?[a-z_]+' "$f" | sed -E 's/--action[ =]+"?//'
    grep -ohE '(^|[^.a-z_])"?action"?: *"[a-z_]+"' "$f" | sed -E 's/.*"([a-z_]+)"$/\1/'
    grep -ohE '^[[:space:]]*(if !? *)?(audit|audit_fn|audit_av|_lock_audit) +"?[a-z_]+"?( |$)' "$f" \
      | sed -E 's/^[[:space:]]*(if !? *)?[a-z_]+ +"?([a-z_]+).*/\2/'
    grep -ohE 'write_audit_row +"?[^ ]+"? +"?[a-z_]+' "$f" | awk '{print $3}' | tr -d '"'
    grep -ohE 'append_row +[^ ]+ +[^ ]+ +[a-z_]+' "$f" | awk '{print $4}'
  done < <(_writer_files)
}

@test "enum: non-vacuity — the enum and the writer scan both yield values" {
  [ "$(_enum_values | grep -c .)" -ge 100 ] || fail "registry parsed to fewer than 100 values"
  [ "$(_written_actions | sort -u | grep -c .)" -ge 60 ] || fail "writer scan found fewer than 60 actions"
}

@test "enum: every literal action a shipped script writes is a member" {
  local enum missing="" a
  enum="$(_enum_values)"
  while IFS= read -r a; do
    grep -qxF "$a" <<< "$enum" || missing="$missing $a"
  done < <(_written_actions | sort -u)
  [ -z "$missing" ] || fail "written but missing from references/audit-actions.md:$missing"
}

@test "enum: no value is listed in two groups" {
  local dups
  dups="$(_enum_values | sort | uniq -d)"
  [ -z "$dups" ] || fail "duplicate enum values: $dups"
}
