#!/usr/bin/env bats
# Guards the one prohibition `skills/cross-plugin-handoff/templates/CORPFLOW.md` states in its
# own header comment: a plugin-root CORPFLOW.md must never carry `## Routing` or `## Models` —
# both are reserved for the project-root kind (`templates/PROJECT-CORPFLOW.md`). Prose-only
# until now (architecture-0.md#ad6 implied a guard test already existed; none did —
# development-0-matrix-and-resolver.md#risks, DV0).
#
# Scope, decided here rather than guessed: the two kinds share one basename (`CORPFLOW.md`)
# once a template is copied into place, so filename alone cannot tell them apart — only
# LOCATION can, and this repository's own root is a documented exception to even that
# (planning-0.md#summary: a CORPFLOW.md at corpflow's own root would be the project-root kind
# despite sitting beside this repo's own `.claude-plugin/plugin.json`, the only plugin manifest
# in this tree). No real plugin-root CORPFLOW.md instance exists here today (asserted below via
# `git ls-files`, not assumed), so this suite checks the two TEMPLATES — each self-declares its
# kind in its own header comment, unambiguous by construction — rather than sweeping the tree
# with a "sibling of a plugin manifest" heuristic that would misclassify corpflow's own
# hypothetical root file. A vendored sibling plugin's own CORPFLOW.md is outside what this suite
# can see; that is a stated limit, not an oversight.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

PLUGIN_ROOT_TEMPLATE="skills/cross-plugin-handoff/templates/CORPFLOW.md"
PROJECT_ROOT_TEMPLATE="skills/cross-plugin-handoff/templates/PROJECT-CORPFLOW.md"

@test "the plugin-root template carries neither ## Routing nor ## Models" {
  run grep -E '^## (Routing|Models)$' "$PLUGIN_ROOT/$PLUGIN_ROOT_TEMPLATE"
  assert_failure
}

@test "the plugin-root template's own guard comment names both forbidden headings" {
  run grep -qF 'Never add a `## Routing` or `## Models` heading' "$PLUGIN_ROOT/$PLUGIN_ROOT_TEMPLATE"
  assert_success
}

@test "discrimination control: the project-root template legitimately carries both headings" {
  # If this test failed the same way as the plugin-root one above, the guard would be
  # indiscriminate — forbidding a heading the project-root kind is explicitly allowed.
  run grep -qE '^## Routing$' "$PLUGIN_ROOT/$PROJECT_ROOT_TEMPLATE"
  assert_success
  run grep -qE '^## Models$' "$PLUGIN_ROOT/$PROJECT_ROOT_TEMPLATE"
  assert_success
}

@test "no other file literally named CORPFLOW.md exists in this tree today" {
  # Documents the current absence rather than asserting a permanent rule. A legitimate
  # project-root CORPFLOW.md landing at this repo's own root tomorrow is NOT a violation of
  # anything this suite checks — it would need this list updated, which is cheaper than a
  # false-positive guard firing on a correct addition (see the file header).
  run bash -c "cd '$PLUGIN_ROOT' && git ls-files -- '*/CORPFLOW.md' 'CORPFLOW.md'"
  assert_success
  assert_output "$PLUGIN_ROOT_TEMPLATE"
}
