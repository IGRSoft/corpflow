# Shared shell libraries — conventions

Three libraries live here. Each is a `source`-only file — never execute it directly, and
never treat it as an entry point.

| Library | Symbols | Mirrored into `hooks/lib/`? |
|---|---|---|
| `corpflow-base.sh` | `corpflow_script_dir`, `corpflow_plugin_root` | **Yes, byte-identical** — see below |
| `audit-lib.sh` | `corpflow_audit_row` | No — the hook tree has its own single appender, `hooks/lib/model-switch-lib.sh`'s `corpflow_audit_row`; a second same-purpose symbol there would recreate the duplication this file exists to remove |
| `state-read-lib.sh` | `corpflow_state_str`, `corpflow_worktask_id`, `corpflow_run_index` | No — `.context/state.json` is only reachable once a plugin root and workspace are already resolved, which is a skills-tree concern |

## `corpflow-base.sh` is mirrored, not shared

`skills/shared/lib/corpflow-base.sh` and `hooks/lib/corpflow-base.sh` are **byte-identical**
copies, pinned by a parity test (`tests/shell/skills/corpflow-base.bats`). This is
deliberate, not an oversight: a hook cannot reach `skills/shared/lib/` without first
resolving a plugin root — the very thing this library supplies — so the boundary is
mirrored across rather than crossed, matching the existing `hooks/model-switch-lib.sh`
precedent. **Edit one copy, edit both, in the same commit**, or the parity test fails.

## The source-block idiom

Every caller sources a library with a guard block, and the guard's failure mode differs by
tree:

**Skills tree — fail closed (`exit 2`).** A missing library under `skills/` is a broken
install, not a runtime condition a script should degrade around:

```bash
_AUDIT_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 '<script>: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"
```

Six adapters under `skills/dv-screenshot-capture/scripts/` plus worktask consumers
(`attach-visual-evidence.sh`, `adhoc-visual-evidence.sh`, `attachments-preseed.sh`,
`publish-pl-issue.sh`) follow this exact shape for `audit-lib.sh` and/or
`state-read-lib.sh`.

**Hooks tree — stricter still.** A hook gate runs on every tool call in a live session, so
its fail-closed exit code (`exit 1`) is load-bearing: a hook that silently no-ops on a
broken install would let the exact class of defect the gate exists to catch through
unnoticed. Where a hook's own contract is instead to *degrade* (e.g.
`hooks/anchor-preflight.sh`, whose job is advisory linting, not a hard block), the source
block drops `-e` around the source, probes for the resulting symbol, and falls back to a
no-op rather than aborting the host tool call:

```bash
_LIB="$(dirname -- "$0")/lib/corpflow-base.sh"
_cf_opts=$-
set +e
# shellcheck source=hooks/lib/corpflow-base.sh
[ -f "$_LIB" ] && . "$_LIB"
case "$_cf_opts" in *e*) set -e ;; esac
if command -v corpflow_plugin_root > /dev/null 2>&1; then
  PLUGIN_ROOT="$(corpflow_plugin_root)" || PLUGIN_ROOT=""
fi
```

Do not conflate the two: **a script that must fail closed uses the skills-tree shape; a
script whose own contract is to degrade uses the probe-and-fall-back shape** — picking the
wrong one either turns a broken install into silent success, or turns an advisory check
into an unwanted hard block. `sw-DV5-3` (open, non-blocking) asks whether the six
fail-closed adapters should share one exit code and diagnostic instead of each choosing its
own; left as-is for this run, since narrowing it touches ten call sites on the eve of a
full-suite QA pass for no behavior change.

## Anti-execution and include guards

Every library opens with two guards, in this order:

```bash
# Anti-execution guard — MUST be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 '<lib>.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_<NAME>_LIB:-}" ] && return 0
_CORPFLOW_<NAME>_LIB=1
```

The anti-execution guard catches `bash lib.sh` / `./lib.sh` misuse before anything else
runs. The include guard makes a script that is sourced twice in one process (a caller that
sources it, then sources a helper that sources it again) a no-op re-source rather than a
redefinition — bash re-defining a function is harmless, but a library that also does
top-level work (none of these three do, by design) would otherwise run that work twice.

## Libraries must not use `readonly`

None of the three libraries declares a `readonly` variable, and new libraries must not
either. `bats` sources a library **twice per process** — once for the suite file itself and
again inside each `run` helper's subshell setup — and a second `readonly NAME=...`
assignment on an already-`readonly` name is `rc 1`. Under a caller running with `set -e`,
that `rc 1` is fatal and kills the test, not just the assignment. Every library instead
relies on the include guard above to make re-sourcing idempotent, and treats "immutable
after first source" as a convention enforced by review, not by the shell.
