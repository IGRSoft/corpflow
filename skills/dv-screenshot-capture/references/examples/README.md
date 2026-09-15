# Examples — dv-screenshot-capture

These three PNGs are the inaugural output of this skill, captured during the worktask that introduced it (issue #114, run 0): they prove the contract end-to-end (the skill captured the diff that defines the skill itself) and document the expected shape of a manifest entry for future DV stages.

All three came from the `cli_fallback` adapter via `silicon` (Dracula theme), downscaled to ≤200 KB per the AR ad7 size budget. Platform was `all` (plugin meta-work has no UI); adapter selection is deterministic per `../../SKILL.md § Adapters`.

## Manifest

This table is the **canonical 9-column shape** — what `attach-visual-evidence.sh
--validate-manifest` asserts, and the file its failure diagnostic points a DV agent at.

| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |
|---|------|------|-------|----------|---------|---------|----------|------------|
| 01 | skill-scaffold | dv-DV0-01-skill-scaffold.png | 188676 | all | cli_fallback (silicon) | Head of the new `SKILL.md` — frontmatter + intro + trigger conditions | 2026-06-28T17:16:04Z | — |
| 02 | developer-prompt-delta | dv-DV0-02-developer-prompt-delta.png | 166538 | all | cli_fallback (silicon) | `agents/developer.md` diff — DV completion-gate insertion (AR § 6.1 verbatim) | 2026-06-28T17:16:04Z | — |
| 03 | files-changed | dv-DV0-03-files-changed.png | 155017 | all | cli_fallback (silicon) | `git status --short` of the workspace at DV completion | 2026-06-28T17:16:04Z | — |

### Column notes

The rows follow the per-task grammar for task `DV0`, as they would appear in `screenshots-DV0.md`:
each Path is `dv-DV0-NN-<slug>.png` with `NN` equal to `#`, naming a PNG beside this file.

Copy the column set and the two-digit `#` exactly: a one-digit index or a dropped trailing column
parses as zero capture rows, and the run then ships with its evidence silently missing.

`Captured` is an ISO-8601 UTC timestamp; `Design Ref` is the `figma-registry.md` row `ID` this
capture maps to, or `—` when there is no registry or no unique match (plugin meta-work has
neither). Full template and row grammar, including the `tool_missing` row:
`../../SKILL.md § Row grammar` and `§ tool_missing row`.

## AC coverage (from planning-0.md)

A list, not a second table, deliberately: `--validate-manifest` reads *every* pipe table in the
file it is pointed at, so a companion table here would be judged against the capture-row grammar
and reported as a schema violation.

- AC-1 skill present — dv-DV0-01 — pass
- AC-2 ≥1 screenshot artifact — dv-DV0-01..03 — pass
- AC-4 QA-readable artifact — dv-DV0-01..03 (PNG, universally readable) — pass
- AC-5 DR-citable artifact — dv-DV0-01..03 + the manifest above — pass
- AC-6 deterministic platform routing — Adapter column above — pass

## Reproducing

From a workspace with `silicon` installed (`brew install silicon`):

```bash
silicon <input-file> \
  --output <path>/dv-<TASK_ID>-NN-<slug>.png \
  --language <lang> \
  --theme Dracula \
  --background "#1e1e2e" \
  --window-title "<descriptive title>" \
  --no-line-number

# Then downscale + recompress to stay under the 200 KB budget
sips -Z 1200 <path>/dv-<TASK_ID>-NN-<slug>.png -s formatOptions 70 --out <path>/dv-<TASK_ID>-NN-<slug>.png
```
