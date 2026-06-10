# Approval Gate Hook — installation & rollout

Read when installing or troubleshooting gate-enforcement hooks (from `skills/worktask/SKILL.md § Approval Gate Hook` stub). The approval gates (PL0 and FN) are honor-system — the orchestrator is expected to `STOP IMMEDIATELY` and wait for the user. `PreToolUse` hooks can enforce each gate programmatically. Each hook scopes its grep by `subject` so that PL0 approval does not satisfy the FN predicate (and vice versa).

## Advisory Rollout (Phase 1)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "if": "test -f .context/logs/audit.jsonl && ! grep -q 'approval_received.*\"subject\":\"PL0\"' .context/logs/audit.jsonl",
        "command": ".claude/hooks/approval-gate.sh",
        "mode": "warn"
      },
      {
        "matcher": "Bash",
        "if": "test -f .context/logs/audit.jsonl && grep -q 'fn_gate_waiting.*\"subject\":\"FN0\"' .context/logs/audit.jsonl && ! grep -q 'approval_received.*\"subject\":\"FN0\"' .context/logs/audit.jsonl && ! grep -q 'fn_gate_bypass.*\"subject\":\"FN0\"' .context/logs/audit.jsonl",
        "command": ".claude/hooks/approval-gate.sh",
        "mode": "warn"
      }
    ]
  }
}
```

The second stanza only fires once `fn_gate_waiting` has been written (so it is dormant before FN is reached) and clears once either `approval_received` or `fn_gate_bypass` is written for `FN0`. The `Bash` matcher covers FN's commit/push/PR calls without blocking earlier stages' write/edit activity.

## Blocking Rollout (Phase 2, after observation)

Change `mode: "warn"` to `mode: "deny"`. The hook returns `defer` with guidance: "Worktask awaiting user approval after PL0. Reply 'approve', 'proceed', 'go', 'yes', or 'continue' to unblock."

## Interaction with `--auto-continue` bypass

The orchestrator-side bypass behavior (PL0 `{approved: "auto", fn_gate: "bypass"}` + `approval_received` / `fn_gate_bypass` audit lines) is operative regardless of hooks and lives in `skills/worktask/SKILL.md § Approval Gate Hook`. Hook-side consequence: those audit lines make both `if` predicates evaluate false, so bypassed runs proceed without hook interference.

## Safety Valve

If the hook misfires (blocks legitimate post-approval work), the user can always remove the hook stanza from `settings.json` and retry. No persistent state is stored in the hook itself — the Task System metadata + audit log remain authoritative.
