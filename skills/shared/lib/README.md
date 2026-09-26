# Shared shell libraries — conventions

Three `source`-only libraries. None is an entry point; executing one exits 2.

| Library | Symbols | Mirrored into `hooks/lib/`? |
|---|---|---|
| `corpflow-base.sh` | `corpflow_script_dir`, `corpflow_plugin_root` | Yes, byte-identical — see below |
| `audit-lib.sh` | `corpflow_audit_row` | No — the hook tree has its own appender, `hooks/model-switch-lib.sh`'s `corpflow_hook_audit_row`. The two take incompatible flags and both ignore unknown ones, so they are named apart |
| `state-read-lib.sh` | `corpflow_state_str`, `corpflow_worktask_id`, `corpflow_run_index`, `corpflow_context_dir` | No — `.context/state.json` is only reachable once a plugin root and workspace are resolved, which is a skills-tree concern |

## `corpflow-base.sh` is mirrored, not shared

`skills/shared/lib/corpflow-base.sh` and `hooks/lib/corpflow-base.sh` are byte-identical,
pinned by `tests/shell/skills/corpflow-base.bats`. A hook cannot reach `skills/shared/lib/`
without first resolving a plugin root, which is what this library supplies. Edit both copies
in the same commit.

## The source-block idiom

Every caller sources a library through a guard block. Pick the shape by the caller's own
contract: the wrong one either turns a broken install into silent success or turns an
advisory check into a hard block.

### Fail closed — skills tree, and hook gates

A missing library under `skills/` is a broken install, not a condition to degrade around:

```bash
_AUDIT_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 '<script>: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"
```

A hook gate fails closed the same way with `exit 1`, because a gate that no-ops on a broken
install lets through the defect it exists to catch.

### Degrade — advisory hooks

A hook whose contract is to degrade (`hooks/anchor-preflight.sh`, advisory linting) drops
`-e` around the source, probes for the symbol, and falls back to a no-op:

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

## Anti-execution and include guards

Every library opens with two guards, in this order:

```bash
# Anti-execution guard — must be the first statement.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 '<lib>.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

# Include guard: a double source is a no-op rather than a re-definition.
[ -n "${_CORPFLOW_<NAME>_LIB:-}" ] && return 0
_CORPFLOW_<NAME>_LIB=1
```

The anti-execution guard refuses `bash lib.sh` before anything else runs. The include guard
makes a second source in one process a no-op; that matters only for a library with
top-level work, which none of these has.

## No `readonly`

Libraries declare no `readonly` variable. `bats` sources a library twice per process, and a
second `readonly NAME=...` on the same name is `rc 1`, fatal under `set -e`. The include
guard keeps re-sourcing idempotent instead.
