# Figma Design Capture

Read this when a Figma URL is detected in the task description or user input — the URL forces capture
regardless of the design-detection keyword score. The Figma-URL trigger, the `{{asset:<basename>}}`
placeholder grammar, and the canonical anchor example stay inline in
`skills/worktask/references/pl0-procedure.md`.

## Figma URL Detection

Scan the task description for URLs matching:

```
figma\.com/(?:file|design|proto)/([a-zA-Z0-9]+)/([^?]+)(\?node-id=([0-9-]+))?
```

- Group 1 `fileKey`, Group 4 `nodeId` (`-` → `:` for API calls); `(?:file|design|proto)` is **non-capturing** — all three design-file path forms keep the same group numbers.
- Must match the two trigger regexes in `skills/worktask/references/pl0-procedure.md § Figma Design Capture` — on drift, `/file/` and `/proto/` URLs reach `design-preview` but never fire capture (no PNGs, no registry, QA design gate skipped).
- Never add `/board/` or `/slides/` — `get_metadata` is design-file-only and rejects FigJam/Slides.
- Branch URL (`…/branch/:branchKey/…`) → `branchKey` is the fileKey. No `node-id` → capture the top-level frame.

## State Input Contract

State is derived **only from explicit user input** — no heuristic sibling scanning. One URL, no annotation → `state: default`; otherwise one URL per state via fragment (`…?node-id=42-7#state=error`), query parameter (`…&state=error`), or inline annotation (`<url> [state: error]`).

Valid values: `default | error | empty | loading | hover | disabled | success`. Unknown values are preserved as-is (tolerant); QA reports unusual states in `testing.md`.

## Auth Probe

Before the Capture Workflow, match `figma.com` (case-insensitive substring) in the task description and call `mcp__plugin_figma_figma__get_screenshot({ fileKey, nodeId })` once on the first URL. Not net-new traffic: step 3b reordered ahead of any plan-file write, so the auth-error class is classified first.

- **Success** → run the Capture Workflow as normal.
- **Non-auth failure** (network, rate limit, bad node id): do not intercept — use the per-URL failure path at the end of `## Capture Workflow`.

### Auth failure (soft halt)

Error string matches (case-insensitive) any of `authenticate` / `OAuth` / `unauthorized` / `401`:

1. Emit exactly one user-facing line: `Figma MCP not authenticated. Authorize at <OAUTH_URL_FROM_ERROR> and paste callback to continue, or reply 'skip' to proceed without screenshot.` (OAuth URL from the error payload; if absent, drop the placeholder and say `Authorize the Figma MCP server`.)
2. Append `q1: Figma MCP auth pending; PM proceeded without screenshot capture (URLs: <comma-separated list>)` to `state.json facts.open_questions[]`, mirrored into the plan's `handoff.open_questions` frontmatter.
3. **Soft halt**: skip the Capture Workflow entirely and write the plan as if no Figma URL were present — it ships with the open question, and the user decides whether to authorize and re-run.

## Capture Workflow

Run **Auth Probe** first; on auth failure skip these steps. All PNGs land in the canonical `.context/designs/` (see `skills/task-folder-organization/SKILL.md § Canonical Figma Asset Directory`).

Run `mkdir -p .context/designs` **once per turn** before any `curl`: `curl -o` cannot create parents, and frames must never fall back to `.context/images/`. Do not assume the `commands/worktask.md` Phase-1 init mkdir ran, and never claim a file is saved without verifying it on disk.

### Steps 1–2 — Parse and classify

Per Figma URL (state defaults to `default`): **parse** `fileKey`, `nodeId`, `state`; **classify the node** via `mcp__plugin_figma_figma__get_metadata({ fileKey, nodeId })` FIRST:

- **Leaf** — `frame`/`component`/`instance` with no child `frame`s, or fewer than 2 direct `frame` children → one target, the node itself (single-screen behavior unchanged).
- **Container** — type `section`/`canvas`, or a wide `frame` with **≥ 2** direct `frame` children → descend **one level only**: the container as the **overview**, plus each direct child `frame` (id + name from metadata).
- **Ambiguous** — lone screen `frame`, or a layout group with 0–1 `frame` children → treat as **leaf** (R3).

**Cap**: the first **12** child frames in document order; beyond that capture those 12 and append `R2 over-capture cap hit: container <nodeId> has <N> frames, captured first 12` to `.context/errors/product-manager.md`.

### Step 3 — Capture each target

For each target node (overview first, then child frames):

a. `mcp__plugin_figma_figma__get_design_context({ fileKey, nodeId })` — code hints + component info.
b. `mcp__plugin_figma_figma__get_screenshot({ fileKey, nodeId })` — returns a short-lived image URL.
c. **Persist in-turn** (the URL expires before any post-approval step): `target_path` = `.context/designs/` + the grammar basename — **always** `.context/designs/`, **NEVER** `.context/images/` (Placement guard in `skills/worktask/references/pl0-procedure.md`: `images/` is DV-only and disables the QA design gate). Download immediately, double-quoting both arguments — the MCP-returned URL is external input:

```bash
curl -sf -o ".context/designs/<basename>" "<image_url>"
```

#### Verify and record (3d–3e)

d. **Verify** before recording success: `file "<target_path>"` reports a PNG **and** byte size > 0. On failure (curl non-zero, missing file, zero bytes, not a PNG) append `figma persist failed: <nodeId> → <target_path> (<reason>)` to `.context/errors/product-manager.md`, record an open question in `state.json facts.open_questions[]`, and **continue** — persist failures never block the worktask.
e. Record `{nodeId, name, state, image_url, target_path}` into `state.json facts.figma_assets[]`; only verified rows count toward registry success, failed rows carry `failed: true`.

### Step 4 — Filename grammar

`.context/designs/figma-[screen]-[state]-[node-id].png` — the directory component is mandatory.

- `[screen]`/`[node-id]`: child frame name + child id; the **Overview** (container image) uses the container name + id. Names lowercase, spaces → hyphens; ids colons → dashes.
- `[state]`: per the State Input Contract, default `default`; child frames inherit the URL-level state unless annotated per-frame.
- Non-alphanumeric characters (dashes, slashes, en/em-dashes, other punctuation) collapse to one hyphen; consecutive hyphens squeeze to one.

### Steps 5–7 — Outputs and failure path

5. Repeat steps 1–4 per Figma URL.
6. **Summarize per-frame design context** in `<plan_file>` under **Figma Design References**: one bullet per frame (state, badge/label text, build notes — shape/geometry, control deltas) plus one overview bullet.
7. Write `.context/designs/figma-registry.md` (see Registry Generation).

A per-URL MCP failure never stops the run — continue with the remaining URLs, write the registry with the captured rows, append a failure note to `.context/errors/product-manager.md`.

## Registry Generation

Write `.context/designs/figma-registry.md` after all captures. **Per-frame rule (REQ-B)**: a container yields N+1 rows — one Overview row (container node id, `State: overview`) plus one row per persisted child frame, keyed on **its own** node id with its own name and state; a leaf (single-screen) URL yields exactly one row and **no** Overview row. QA's Design Comparison compares each row's persisted file individually (`agents/qa-engineer.md § Design Comparison (Visual QA)`).

### Registry template

```markdown
# Figma Design Registry

Produced by: PL stage (product-manager)
Consumed by: QA stage (qa-engineer)

## Entries

| ID | Screen | State | Device | Figma Node | Screenshot | Target File(s) | AC Ref |
|----|--------|-------|--------|------------|------------|----------------|--------|
| design-001 | skin-analysis-face-scan | overview | iPhone 15 | 255:2263 | figma-skin-analysis-face-scan-overview-255-2263.png | ScanView.swift | AC-1 |
| design-002 | scan-25 | default | iPhone 15 | 255:2264 | figma-scan-25-default-255-2264.png | ScanView.swift | AC-1, AC-2 |
```

Then `## Source URLs` (one `- design-NNN: <url> (container|child frame)` bullet per row) and `## Capture Metadata` (`Captured at:` ISO-8601, `Captured by: corpflow:product-manager (PL0)`, `Figma file version:` from `get_metadata`, else `unknown`).

### Column semantics

Column order is authoritative — QA parsers rely on it. `Screen`, `State`, and `Screenshot` follow the filename grammar (`Screenshot` = basename only; the Overview row uses the container name and literal state `overview`). `Figma Node` is the API-format id (colons). `ID` is a sequential `design-NNN`; `Device` comes from task context ("iPhone 15", "Desktop 1440", "iPad"); `Target File(s)` and `AC Ref` come from `<plan_file> § Scope` (comma-separated) and `§ Acceptance Criteria`.

Defaults when unknown: `Screen` → node-id, `State` → `default`, `Device` → `unspecified`, `Target File(s)` → `?`, `AC Ref` → blank.

Reference the registry from `<plan_file> § Figma Design References`:

> See `.context/designs/figma-registry.md` for the full node → screenshot → target mapping.

## Post-Capture Plan Update (REQ-D)

After persistence and the registry write — **in this same PL turn**, the PM being Bash-capable and having verified the files on disk — rewrite the plan's `## design-preview` anchor with the **Asset-placeholder grammar** from `skills/worktask/references/pl0-procedure.md`, so DV implements and QA verifies against the discrete per-frame files.

### Anchor update steps

1. Keep the captured Figma source URL line(s) at the top of the anchor, verbatim.
2. Per **persisted** file (verified non-zero PNG): a `{{asset:<basename>}}` token line (basename only, no path) **immediately followed** by a `- <description>` bullet — state mapping plus build notes (shape/geometry, badge/label text, control deltas versus the other states). The Overview gets its own token + bullet, marked as the container reference, not a per-state target.
3. Failed/skipped frames (`failed: true` in `state.json facts.figma_assets[]`) get a plain bullet naming their open question — no `{{asset:...}}` token (nothing verified to host), never a satisfied target.

The registry rows, not one combined screenshot, are QA's authoritative per-state targets.

### Publish-helper boundary

The PM writes **only** tokens and descriptions, never hosted URLs or `![...]()` image markdown. Post-approval and post-sanitisation, `publish-pl-issue.sh` resolves each `{{asset:<basename>}}` into a hosted `![<basename>](<url>)` line, with a non-blocking fallback chain (raw.githubusercontent.com → gist → URL-only note); asset commits stay deferred until after human approval (AC-9). Persistence and the plan update both happen inside the PL turn while the screenshot URLs are valid — no orchestrator re-entry.

## Coexistence with Pencil Mockups

A Figma URL always captures + writes the registry; a design keyword score >= 5 without a Figma URL invokes Designer for Pencil mockups instead (existing behavior, no registry). When both fire, do both — the Figma screenshots are the authoritative design reference.
