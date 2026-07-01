# tests/fixtures — index + write-access rules

`tests/fixtures/` is the **shared read surface** for all five DV tracks. Writes are
namespaced per track to prevent collisions.

## Write-access partition

| Subdirectory              | Owner | Contents |
|---------------------------|-------|----------|
| `tests/fixtures/worktask/` | DV0a  | `state.sample.json`, plan frontmatter samples, sanitiser-input fixtures, `{{asset:…}}` resolution fixtures for `publish-pl-issue.sh` |
| `tests/fixtures/skills/`   | DV0b  | Synthetic-secret fixtures for `scan-secrets.sh`, export samples, git-log samples, clean-input fixtures |
| `tests/fixtures/hooks/`    | DV0c  | Hook stdin JSON payloads, estimate inputs, TTT spec stub |
| `tests/fixtures/README.md` | DV0d  | THIS FILE (cross-cutting index; sole owner) |

No two tracks write the same fixture file. `tests/fixtures/` itself is read by all
tracks (a `.bats` file may reference another track's fixture by absolute path via
`$FIXTURES/<subdir>/<file>` — reads are unrestricted; writes are namespaced).

## audit-dedup.sh basename collision (BINDING on all tracks + QA AC-2)

Two source files share the basename `audit-dedup.sh`:

| # | Path | Track | Test file |
|---|------|-------|-----------|
| 1 | `hooks/audit-dedup.sh`                                 | DV0c | `tests/shell/hooks/audit-dedup.bats` |
| 2 | `skills/agent-coordination/references/audit-dedup.sh`  | DV0b | `tests/shell/skills/agent-coordination__audit-dedup.bats` |

The AC-2 residual-completeness gate strips the extension and greps `tests/ -R` for
the stem. A naive grep for `audit-dedup` would match BOTH files with a SINGLE test
file, falsely claiming both are covered.

**Locked mitigation:**
- DV0c's test file lives at `tests/shell/hooks/audit-dedup.bats` — safe because the
  `hooks/` directory prefix distinguishes it from the skill variant.
- DV0b's test file is `tests/shell/skills/agent-coordination__audit-dedup.bats` — the
  double-underscore path-derived prefix makes the skill variant uniquely identifiable.
- QA's AC-2 gate MUST match on **path-derived stems** (not raw basenames). The
  correctness check is: both `tests/shell/hooks/audit-dedup.bats` AND
  `tests/shell/skills/agent-coordination__audit-dedup.bats` must exist for the suite
  to be considered complete.

## Fixture hygiene rules (all tracks)

1. **No real secrets.** Fixtures that exercise `scan-secrets.sh` must use synthetic
   strings that RESEMBLE secret patterns (e.g. `AKIA_FAKE_KEY_1234567890AB`) but are
   not real credentials. SR reviews this at the SR stage.
2. **No generated-app source.** `benchmark/workdirs/` is gitignored (AC-9). Do not
   commit any generated TTT app tree under `tests/fixtures/`.
3. **Minimal, focused files.** Each fixture file covers exactly the scenario(s) that
   reference it. Avoid multi-purpose fixture blobs that make failures ambiguous.
4. **UTF-8, LF line endings.** Platform-neutral for CI-readiness.
