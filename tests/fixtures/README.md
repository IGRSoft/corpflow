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

## Basename collisions (BINDING on all tracks + QA AC-2)

When two source files share a basename, their test files MUST be distinguishable by
**path-derived stem**, not raw basename: the AC-2 residual-completeness gate strips the
extension and greps `tests/ -R` for the stem, so a naive basename match would claim a
single test file covers both sources.

**Locked mitigation:** name the test file after the path, using a double-underscore
prefix for non-`hooks/` variants (e.g. `agent-coordination__audit-dedup.bats` for
`skills/agent-coordination/scripts/audit-dedup.sh`). QA's AC-2 gate MUST match on
path-derived stems.

## Fixture hygiene rules (all tracks)

1. **No real secrets.** Fixtures that exercise `scan-secrets.sh` must use synthetic
   strings that RESEMBLE secret patterns (e.g. `AKIA_FAKE_KEY_1234567890AB`) but are
   not real credentials. SR reviews this at the SR stage.
2. **No generated-app source.** `benchmark/workdirs/` is gitignored (AC-9). Do not
   commit any generated TTT app tree under `tests/fixtures/`.
3. **Minimal, focused files.** Each fixture file covers exactly the scenario(s) that
   reference it. Avoid multi-purpose fixture blobs that make failures ambiguous.
4. **UTF-8, LF line endings.** Platform-neutral for CI-readiness.
