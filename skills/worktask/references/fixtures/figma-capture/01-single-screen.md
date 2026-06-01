# Fixture 01 — Single-screen (leaf) node

Exercises the no-regression leaf path: a Figma URL pointing at one screen. The PM
captures exactly one screenshot, persists exactly one PNG, writes one registry row,
and emits no Overview row.

Primary ACs: **AC-2** (single screen → exactly one PNG), **AC-3** (persisted file is
a verified non-zero PNG), **AC-6** (PM is Bash-capable and never claims a file it did
not verify).

## Input

Task description contains:

```
https://www.figma.com/design/FOO/Login?node-id=42-1
```

(One URL, no state annotation → `state: default`.)

## Node classification (`get_metadata`)

```
node 42:1  type=FRAME  name="Login"
  children: [ TEXT, INPUT, INPUT, BUTTON ]   # zero direct FRAME children
```

→ **Leaf** (fewer than 2 direct `frame` children). One target: node `42:1` itself.

## Expected persisted files (`.context/designs/`)

Exactly **1** PNG, verified non-zero:

```
figma-login-default-42-1.png
```

No Overview file (leaf has no container).

## Expected registry rows (`figma-registry.md`)

Exactly **1** Entries row, no `overview` row:

| ID | Screen | State | Figma Node | Screenshot |
|----|--------|-------|------------|------------|
| design-001 | login | default | 42:1 | figma-login-default-42-1.png |

## Expected design-preview (`<plan_file> § design-preview`)

The original URL line PLUS one persisted-file line:

- `figma-login-default-42-1.png` — state `default` — build notes (form fields, primary button).

## Non-blocking contract

If `curl` or the PNG verification fails, the row is recorded with `failed: true` in
`state.json facts.figma_assets[]`, a note is appended to
`.context/errors/product-manager.md`, an open question is recorded, and the plan
still ships. The worktask never blocks on a persist failure.

## Assertions (QA)

- [ ] Exactly 1 PNG persisted; filename matches the grammar.
- [ ] Exactly 1 registry row; **no** `overview` row.
- [ ] No false "saved" claim — every recorded success corresponds to a verified PNG.
- [ ] design-preview lists the one persisted file with its state.
