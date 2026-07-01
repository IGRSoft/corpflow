# Live dispatch stage prompts (DV0e)

One `<stage>.txt` per pipeline stage (PL, AR, TL, DV, DR, SR, QA, DC, FN, ST). Each
file is fed verbatim on stdin to:

```
claude agents run --cwd <workdir> --model <m> --effort <e> \
  --permission-mode default --output-format json -- <agent> < prompts/<stage>.txt
```

The benchmark workload is a **real runnable Python Tic-Tac-Toe app** (CLI + optional
curses TUI, stdlib `unittest`, no third-party deps — Python 3.14). The live A/B
measures the FULL worktask pipeline authoring that app end-to-end, with REAL
tokens/cost summed per stage and budget-capped.

These prompts are deterministic, stdlib-only, and contain NO secrets. They are only
ever read on an opt-in `--live` run (never `make benchmark` / `make test`).
