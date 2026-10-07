# DR reference — rarely needed sections of `agents/technical-lead.md`

Read a section only when its trigger in `agents/technical-lead.md` fires; the agent body names each one.
Kept out of the agent body because every DR turn pays for the body's tokens.

## Landed-set check

Trigger: a rework round that adds scope (`agents/technical-lead.md § Scope-addition re-entry
checklist`). The query itself stays in the agent body, under § No untracked files outside the
landed set.

### Tree resolution

`<DV tree>` is the row's `metadata.workspace_path` (as the ledger holds it), else the
orchestrator's `git rev-parse --show-toplevel` (`agents/technical-lead.md § Reading the DV tasks`).
No resolvable tree: pass `--arg root ""` (empty set, never a union). An empty set is normal.

### Edge cases

Subtract from untracked paths only: a landed path that shows staged or modified means the consumer
edited a read-only file, so it stays a gap. FN commits tracked modifications only, so untracked
guard or test files ship as silent omissions while the suite stays green.
