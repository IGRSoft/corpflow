# Claude Code Hardening

Read when the diff touches Claude Code configuration — permission rules, `settings*.json`, hooks,
sandbox settings, plugin or marketplace manifests, agent `tools` grants — or when the worktask runs
unattended (`/megatask`, `--auto=[finalization]`) or on a shared runner.

## Permission rules

Flag: bash bypass patterns, compound-command injection (`&&`/`||`), env-var prefix bypasses
(`FOO=bar cmd`), `/dev/tcp` redirects, unscoped wildcard allow rules (`Bash(*)`, `Read(*)`),
deny-rule precedence, subagent permission scope, LSP `which` fallback injection. Scoped wildcards
match correctly and are legitimate — don't flag `WebFetch(domain:*.example.com)` subdomain rules or
mid-pattern file rules like `Read(secrets-*/config.json)`.

### Rule syntax

- Single-segment `dir/**` allow rules and hook `if:` conditions are cwd-anchored — they match only `<cwd>/dir`; any-depth needs `**/dir/**`. `deny`/`ask` rules keep any-depth matching.
- `Write(path)`/`NotebookEdit(path)`/`Glob(path)` rules trigger a startup warning — those tools take no path predicate the way Edit/Read do; recommend `Edit(path)`/`Read(path)`.
- A `!`-prefixed deny or ask rule applies only within the settings source that wrote it; a bare `!` negation is ignored.

### Bash matching

- The file a Bash `tee` writes is checked against `Edit()` deny rules and the write-path check; a `Bash(tee:*)` allow rule does not cover destinations outside the working directories.
- Deny and ask rules on symlinked directories (`/etc`, `/tmp`, `/var` on macOS; `/bin` on Linux) apply by real path, and Bash honors deny rules written on the symlinked spelling.
- Bash analysis fail-closes on FD redirects, commands over 10k characters, zsh subscripts in `[[ ]]`, unsafe `help`/`man` forms, and arithmetic assignment to an integer variable (`OPTIND=1`, `RANDOM=2+2`). Extra ask prompts there are the detection working, not a regression.

## Settings scope

- Project `.claude/settings.json` and `.claude/settings.local.json` cannot start a session in bypass (`defaultMode: "bypassPermissions"` is ignored there; only user or managed settings or `--permission-mode` can), enable detailed beta tracing or raw API body logging, bypass an OTLP collector pinned by managed settings, or set `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`, or `TMPDIR`/`TMP`/`TEMP` through `env`.
- A managed MCP allowlist `${VAR}` resolves from the startup environment and managed-settings env, not the settings-file env; a settings-file variable does not expand there.
- `permissions.blockReadsOutsideWorkingDirectories` blocks file reads outside the working directories (auto mode asks once before the first); sandboxed git still sees the user's git config and a worktree-isolated subagent still sees its own checkout.

## Sandbox

| Setting | Effect |
|---------|--------|
| `sandbox.network.strictAllowlist` | Denies non-allowlisted hosts for sandboxed commands without prompting. Prefer for unattended batches — a prompt in an unattended run is an indefinite stall |
| `sandbox.filesystem.disabled` | Skips filesystem isolation but keeps network egress control. Narrow escape hatch: requires a documented justification, never set to silence a failing command |
| `--restricted` / `CLAUDE_CODE_RESTRICTED=1` | Removes the built-in tools that run commands or code plus `WebFetch` (unless named in `--tools`), keeps file tools inside the working directory, refuses `bypassPermissions`, and ignores user, project and local settings files. The strongest posture for untrusted or third-party plugin content; too restrictive for a normal worktask, since no stage could build or test |

## Plugin and marketplace paths

A plugin component path (command, agent, skill, hooks, other) that is a symlink, contains a
backslash, or points outside the plugin directory is refused as path traversal; fetched marketplace
entry paths get the same check. This repo is both a marketplace and the plugin it publishes, so every
`commands[]`, `agents[]` and `skills[]` entry in `.claude-plugin/marketplace.json` stays
`./`-relative — no `../`, absolute path, or external URL.
