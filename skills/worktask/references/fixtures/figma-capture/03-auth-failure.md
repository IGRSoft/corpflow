# Fixture 03 — Figma auth failure (soft halt)

Exercises the unchanged auth-failure soft-halt behavior (`agents/product-manager.md`
§ Auth Probe). When the Figma MCP is not authenticated, the PM emits one user-facing
authorize line, records an open question, skips the Capture Workflow entirely, and
still writes the plan. No capture is attempted; no PNG is persisted.

Primary AC: **AC-8** (auth-failure soft-halt preserved unchanged). This fixture must
pass **without** any change to the Auth Probe block — it pins the regression boundary.

## Input

Task description contains:

```
https://www.figma.com/design/FOO/FaceScan?node-id=255-2263
```

## Auth Probe result

The first `mcp__plugin_figma_figma__get_screenshot({ fileKey, nodeId })` call returns an
error whose string matches (case-insensitive) one of `authenticate` / `OAuth` /
`unauthorized` / `401`. Example:

```
Error: 401 Unauthorized — authenticate via OAuth at https://figma.com/oauth/authorize?...
```

→ classified as **Auth failure**.

## Expected behavior

1. Emit exactly one user-facing line:
   `Figma MCP not authenticated. Authorize at <OAUTH_URL_FROM_ERROR> and paste callback to continue, or reply 'skip' to proceed without screenshot.`
2. Append to `state.json facts.open_questions[]` and mirror into the plan's
   `handoff.open_questions` frontmatter:
   `q1: Figma MCP auth pending; PM proceeded without screenshot capture (URLs: https://www.figma.com/design/FOO/FaceScan?node-id=255-2263)`
3. **Skip the Capture Workflow entirely.** No `get_metadata`, no per-frame descent,
   no `curl`, no persistence.
4. Continue writing the plan (requirements, acceptance criteria, scope, stages) as if
   no Figma URL were present.

## Expected persisted files (`.context/designs/`)

**0** Figma PNGs. No `figma-*.png`, no `figma-registry.md` capture rows.

## Expected design-preview (`<plan_file> § design-preview`)

The URL is still surfaced under `## design-preview` (the URL-capture anchor is
independent of the Auth Probe), but **no persisted-file lines** are added — capture
did not run.

## Assertions (QA)

- [ ] Zero Figma PNGs persisted; no per-frame rows generated.
- [ ] Exactly one authorize line emitted to the user.
- [ ] Open question recorded in both `state.json` and the plan frontmatter.
- [ ] Plan still written with all required anchors (soft halt, not a hard stop).
- [ ] No `curl` was invoked — persistence path is never entered on auth failure.
