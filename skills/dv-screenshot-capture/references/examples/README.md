# Examples — dv-screenshot-capture

These three PNGs are the inaugural output of this skill, captured during the worktask that introduced it (issue #114, run 0). They serve a dual purpose: they prove the contract works end-to-end (the skill captured the diff that defines the skill itself), and they document the expected shape of a manifest entry so future DV stages have a concrete reference.

All three were produced by the `cli_fallback` adapter using `silicon` (Dracula theme), downscaled to ≤200 KB per AR ad7 size budget. Platform was `all` (plugin meta-work has no UI); the adapter selection is deterministic per the routing table in `../SKILL.md § Platform Routing`.

## Manifest

| # | Slug | Path | Bytes | Platform | Adapter | Caption |
|---|------|------|-------|----------|---------|---------|
| 01 | skill-scaffold | dv-01-skill-scaffold.png | 188676 | all | cli_fallback (silicon) | Head of the new `SKILL.md` — frontmatter + intro + trigger conditions |
| 02 | developer-prompt-delta | dv-02-developer-prompt-delta.png | 166538 | all | cli_fallback (silicon) | `agents/developer.md` diff — DV completion-gate insertion (AR § 6.1 verbatim) |
| 03 | files-changed | dv-03-files-changed.png | 155017 | all | cli_fallback (silicon) | `git status --short` of the workspace at DV completion |

## AC coverage (from planning-0.md)

| AC | Demonstrated by | Verdict |
|----|----------------|---------|
| AC-1 skill present | dv-01 | pass |
| AC-2 ≥1 screenshot artifact | dv-01..03 | pass |
| AC-4 QA-readable artifact | dv-01..03 (PNG, universally readable) | pass |
| AC-5 DR-citable artifact | dv-01..03 + this manifest | pass |
| AC-6 deterministic platform routing | adapter column above | pass |

## Reproducing

From a workspace with `silicon` installed (`brew install silicon`):

```bash
silicon <input-file> \
  --output <path>/dv-NN-<slug>.png \
  --language <lang> \
  --theme Dracula \
  --background "#1e1e2e" \
  --window-title "<descriptive title>" \
  --no-line-number

# Then downscale + recompress to stay under the 200 KB budget
sips -Z 1200 <path>/dv-NN-<slug>.png -s formatOptions 70 --out <path>/dv-NN-<slug>.png
```
