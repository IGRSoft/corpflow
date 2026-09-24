---
name: plugin-root-resolution
---

# Plugin-Root Resolution (provider-agnostic)

**Definition**: the directory containing `.claude-plugin/plugin.json` for the corpflow
plugin. Known layouts: the Claude Code cache
`~/.claude/plugins/cache/igrsoft/corpflow/<version>/` (version-keyed, so never hardcode
it); a plain git clone, where it is the repository root; or wherever another harness
installed the plugin directory.

## Why `CLAUDE_PLUGIN_ROOT` alone is not enough

`CLAUDE_PLUGIN_ROOT` is Claude Code-only, with two behaviors:

1. Claude Code textually substitutes the exact bare token (dollar-brace form) when it loads
   skill, command or agent content and when it parses hook `command:` strings in
   `plugin.json` / agent frontmatter.
2. It is exported as an environment variable to hook (and MCP/LSP server) subprocesses
   only, not to the model's Bash tool environment.

So the token is literal and dead whenever a subagent `Read`s a plugin file from disk, a
snippet is pasted into another prompt, or a non-Claude-Code harness consumes these skills.
Every convention below works in all three states: substituted, expanded-to-empty, and
literal prose.

## Resolution ladder

1. **`$CLAUDE_PLUGIN_ROOT` when set in the executing shell** — hook subprocesses and tests
   that export it. An explicitly set value always wins (tests rely on this override).
2. **Skill base directory, minus `/skills/<name>`** — every agent-skills harness announces
   "Base directory for this skill: `<path>`" on load; for a corpflow skill the root is two
   levels up.
3. **Read-path derivation** — from the absolute path of a file you `Read`, walk up to the
   nearest ancestor containing `.claude-plugin/plugin.json`.
4. **Claude Code cache, last resort** (CC installs only):
   `ls -d ~/.claude/plugins/cache/igrsoft/corpflow/*/ 2>/dev/null | sort -V | tail -1`
   — may be stale if an older version is pinned.

Validate every candidate: `[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]`.

## Canonical executable-snippet shape (markdown)

Fenced snippets that call ungranted bundled helpers use this preamble, keeping their
existing `-f` guard and audit-deferral bodies. A script the file's frontmatter grants takes
§ Granted-script invocation shape instead:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # Claude Code substitutes this token when loading this file
# Empty? Substitute <plugin-root>: the dir containing .claude-plugin/plugin.json —
# two levels above this skill's base directory (see skills/shared/plugin-root-resolution.md).
[ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
HELPER="$PLUGIN_ROOT/skills/<skill>/scripts/<helper>.sh"
```

Under Claude Code the first line is substituted and the fallback is dead code. Elsewhere
the variable expands to empty, the `-d` test fails, and the executor substitutes
`<plugin-root>` via the ladder. A placeholder pasted verbatim fails the `-f` guard: graceful
deferral, not a hard error.

## Granted-script invocation shape

### Grant

A frontmatter grant for a bundled script names the interpreter, the unquoted token and the
script path, and ends in space-star. A `.py` script takes `python3` in place of `bash`:

```
Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh *)
```

#### Matching and scoped grants

- A quoted token never matches: rules match the command text, and the invocation is unquoted.
- A `$PLUGIN_ROOT` rule never matches: the variable is not in the Bash tool environment.
- Substitution in agent `tools:` is not explicitly documented (skill content, agent content
  and skill `allowed-tools` are). A grant that does not match denies the call, and the stage
  takes the permission-denied park path (`skills/worktask/SKILL.md § Step 6.5a4`).
- A fixed literal argument prefix may sit before the space-star to scope the grant to one
  subcommand, e.g. `Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/land-artifacts.sh --consumer *)`.
  The prefix is literal (letters, digits, `_ . , = / -` and single spaces; no `*`, `$`,
  quotes or other shell metacharacters). Never collapse it to the bare script form, which
  would widen the grant.

### Invocation

In a file whose frontmatter grants a script, every runnable mention of it (a fenced or
backticked command, or a `Run …` / `invoke …` instruction) is the grant prefix, byte for
byte, followed by the arguments:

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh --stage DR --prev DV
```

#### Forbidden, legal and exempt mentions

- Forbidden, because none can match the grant: a relative `bash skills/…` path; a bare
  `state-patch.sh --…`; `bash "$PLUGIN_ROOT/…"`; indirection through `$HELPER` or `$SCAN`; a
  quoted token; an env-prefixed command (`X=1 bash …`); an interpreter-less `skills/…/x.sh`.
- Legal: a capture such as
  `out=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh --stage DR --prev DV)`.
  Allow matching inside `$(…)` is not documented, so a capture may still prompt.
- A descriptive mention that is not an instruction to run
  ("`handoff-harness.sh check_sweep_ledger` fails when …") stays as written.
- A snippet keeps its control flow but drops the `-f` guard: `bash` exits 127 when the
  script is absent, and that exit is the deferral signal.

### On-disk references

A file read from disk is never substituted, so it carries the same literal text. The reader
replaces the token with the absolute plugin root its own loaded body shows. It does not
shell-expand the token (absent from the Bash tool environment) or fall back to a relative
path (which resolves against the working repo, not the installed plugin).

## Author rules

### Markdown token form

Markdown may contain the token only in its exact bare dollar-brace form, not the shell
default-value (colon-dash) form inside the braces: that form forfeits load-time
substitution and risks mangled output from partial matchers.

### Composed paths

A composed path (the token, a slash, then segments) breaks when the token is not
substituted, so it is legal only where arm H or arm S holds. Each occurrence is judged on
its own; every other composition, such as a `references/` doc path, is illegal.

- **Arm H — hook commands.** The path is `hooks/<name>.sh` in Claude Code-native config: the `hooks` block of `.claude-plugin/plugin.json`, `hooks:` entries in skill frontmatter, and verbatim documentation of those entries (`skills/worktask/references/handoff-protocol.md`).
- **Arm S — granted scripts.** The path is `skills/<skill>/scripts/<name>.sh` or `.py` with no `..`, and the token either follows `Bash(bash ` / `Bash(python3 ` with ` *)` right after the path, or follows `bash ` / `python3 ` at line start or after a backtick, a space, `(` or `$(` (not after `"`). The interpreter fits the extension: `bash` with `.sh`, `python3` with `.py`.

### Enforcement

`tests/shell/skills/plugin-root-refs.bats` enforces both arms and zero colon-dash forms in
`*.md`. It sources `skills/shared/scripts/grant-lint.sh` for the arm S path rule, so that
rule is defined once. `grant-lint.sh` also checks frontmatter grants and, with
`--invocations`, runnable body mentions of granted scripts.

### Prose, scripts, tests

- **Prose instructions** write helper paths plugin-root-relative (e.g.
  `hooks/megatask-monitor.sh`) followed by: "(plugin root: `${CLAUDE_PLUGIN_ROOT}` if
  available, else resolve per `skills/shared/plugin-root-resolution.md`)".
- **Shell scripts** (executed, never load-substituted) source
  `skills/shared/lib/corpflow-base.sh` and call `corpflow_plugin_root` (env first, then a
  self-location walk validated against the `.claude-plugin/plugin.json` marker) instead of
  reimplementing it. `hooks/lib/corpflow-base.sh` is a byte-identical mirror, checked by
  `tests/shell/skills/corpflow-base.bats`.
- **Tests** may set or unset the env var to exercise the override and fallback contracts
  (`tests/shell/worktask/hook-install.bats`, `tests/shell/dv-screenshot/apple-canvas.bats`,
  `tests/shell/hooks/anchor-preflight.bats`).
