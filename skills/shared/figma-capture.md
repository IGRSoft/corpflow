# Figma Design Capture

Read this when a Figma URL is detected in the task description or user input. It carries the full
capture mechanics; the `{{asset:<basename>}}` placeholder grammar, the canonical example, and the
Figma-URL trigger/regex stay inline in `agents/product-manager.md` (steady-path, no-Figma runs
never Read this doc).

When a Figma URL is provided in the task description or user input, capture design screenshots regardless of the keyword-based design detection score.

## Figma URL Detection

Scan the task description for URLs matching:

```
figma\.com/(?:file|design|proto)/([a-zA-Z0-9]+)/([^?]+)(\?node-id=([0-9-]+))?
```

- Group 1: `fileKey`, Group 4: `nodeId` (convert `-` to `:` for API calls)
- `(?:file|design|proto)` covers all three design-file path forms and is **non-capturing**, so group numbers are unchanged (Group 1 `fileKey`, Group 4 `nodeId`). Keep it in lockstep with the two trigger regexes in `agents/product-manager.md § Figma Design Capture`; if they drift, a `/file/` or `/proto/` URL surfaces in `design-preview` but never fires capture (no PNGs, no registry, QA design gate skipped).
- Do **not** add `/board/` or `/slides/`: `get_metadata` is design-file-only and rejects FigJam/Slides.
- Branch URLs: `figma.com/design/:fileKey/branch/:branchKey/...` → use `branchKey` as fileKey
- URLs without `node-id` are valid — capture the top-level frame

## State Input Contract

State is derived **only from explicit user input** — no heuristic sibling scanning.

- One URL, no annotation → `state: default`
- For non-default states, the user must list one URL per state using any of:
  - URL fragment: `https://figma.com/design/FOO/Login?node-id=42-7#state=error`
  - Query parameter: `https://figma.com/design/FOO/Login?node-id=42-7&state=error`
  - Inline annotation in the task description: `<url> [state: error]`
- Valid values: `default | error | empty | loading | hover | disabled | success`
- Unknown values are preserved as-is (tolerant); QA reports unusual states in `testing.md`

## Auth Probe

Before running the Capture Workflow, detect Figma URLs in the task description (case-insensitive substring match on `figma.com`) and attempt one MCP call on the first URL via `mcp__plugin_figma_figma__get_screenshot({ fileKey, nodeId })`. Classify the result:

- **Success**: proceed to Capture Workflow as normal.

### Auth failure

- **Auth failure** — error string matches (case-insensitive) any of `authenticate` / `OAuth` / `unauthorized` / `401`:
  1. Emit exactly one user-facing line: `Figma MCP not authenticated. Authorize at <OAUTH_URL_FROM_ERROR> and paste callback to continue, or reply 'skip' to proceed without screenshot.` (Use the OAuth URL from the error payload when present; otherwise omit the `<…>` placeholder and say `Authorize the Figma MCP server`.)
  2. Append `q1: Figma MCP auth pending; PM proceeded without screenshot capture (URLs: <comma-separated list>)` to `facts.open_questions[]` in `state.json` and mirror it into the plan's `handoff.open_questions` frontmatter.

#### Soft halt (step 3)

  3. Skip the Capture Workflow entirely; continue writing the plan (requirements, acceptance criteria, scope, stages) as if no Figma URL was present. This is a **soft halt** — the plan ships with the open question recorded; the user decides whether to authorize and re-run or proceed without screenshots.

### Non-auth failure and probe cost

- **Non-auth failure** (network, rate limit, bad node id, etc.): do not intercept. Fall through to the existing per-URL failure path documented at the end of `## Capture Workflow` (continue with remaining URLs, append a failure note to `.context/errors/product-manager.md`).

The probe call is **not** net-new traffic — it reorders the existing `get_screenshot` invocation from step 3b of the Capture Workflow earlier in the pipeline so that the auth-error class can be classified before any plan-file writes commit.

## Capture Workflow

Run **Auth Probe** first; on success, proceed with the steps below; on auth failure, skip these steps and continue plan authoring with the open question recorded.

The canonical screenshot directory is `.context/designs/` (see `skills/task-folder-organization/SKILL.md § Canonical Figma Asset Directory`). All persisted PNGs land there.

### Directory bootstrap

**Ensure the canonical dir exists first** — run `mkdir -p .context/designs` **once per turn** before any `curl` below. `curl -o` cannot create parent directories, so without this the first download would fail and frames could fall back to `.context/images/`. This step keeps this doc self-contained on a standalone Read: do **not** assume the `commands/worktask.md` Phase-1 init mkdir has already run.

### Container-aware capture

This workflow is **container-aware**: it classifies each referenced node via metadata first and, when the node is a container of multiple frames, captures the overview **and** each child frame individually. The PM persists every screenshot to disk in this same turn via `Bash(curl:*)` (see frontmatter note) — `get_screenshot` returns a short-lived URL that would expire before any post-approval step, so the PM must fetch it now. The PM never claims a file is saved that it has not verified on disk.

### Steps 1–2 — Parse and classify

For each Figma URL (state defaults to `default`):

1. **Parse** `fileKey`, `nodeId`, and `state` from the URL.
2. **Classify the node** — call `mcp__plugin_figma_figma__get_metadata({ fileKey, nodeId })` FIRST. Inspect the returned node tree:
   - **Leaf** (a single screen — node type is a `frame`/`component`/`instance` with no child `frame`s, OR fewer than 2 direct `frame` children) → one target: the node itself. Preserve current single-screen behavior (no regression).

#### Container and ambiguous nodes

   - **Container** (parent type is `section`/`canvas`, OR a wide `frame` whose **direct** children are **≥ 2** `frame`s) → descend **one level only**. Targets = the container itself (captured as the **overview**) PLUS each direct child `frame` (id + name from metadata). **Cap** the child frames at the first **12** in document order; if more exist, capture the first 12 and append a note to `.context/errors/product-manager.md`: `R2 over-capture cap hit: container <nodeId> has <N> frames, captured first 12`.
   - Ambiguous nodes (a single `frame` that is itself a screen, a layout group with 0–1 `frame` children) → treat as **leaf** (R3).

### Step 3 — Capture each target

3. **For each target node** (overview first, then child frames):
   a. `mcp__plugin_figma_figma__get_design_context({ fileKey, nodeId })` — code hints + component info.
   b. `mcp__plugin_figma_figma__get_screenshot({ fileKey, nodeId })` — returns a short-lived image URL.

#### Persist in-turn (3c)

   c. **Persist in-turn**: compute `target_path = .context/designs/` + the basename from the filename grammar below — the directory is **always** `.context/designs/`, **NEVER** `.context/images/` (see Placement guard in `agents/product-manager.md`; `images/` is reserved for DV implementation screenshots and disables the QA design gate). Then download immediately. Always double-quote both arguments so the MCP-returned URL (an external value) cannot break out of the `curl` invocation — the `Bash(curl:*)` grant matches only commands that begin with `curl`, never a bare shell:
      ```bash
      # target_path MUST be under .context/designs/ — e.g. .context/designs/figma-models-review-page-default-2456-16736.png
      curl -sf -o ".context/designs/<basename>" "<image_url>"
      ```

#### Verify and record (3d–3e)

   d. **Verify** the file is a real non-zero PNG before recording success: `file "<target_path>"` reports a PNG **and** the byte size is > 0. On failure (curl non-zero, missing file, zero bytes, or not a PNG), append a note to `.context/errors/product-manager.md` (`figma persist failed: <nodeId> → <target_path> (<reason>)`), record an open question in `state.json facts.open_questions[]`, and **continue** — never block the worktask (non-blocking contract; mirrors the auth soft-halt philosophy).
   e. Record a row `{nodeId, name, state, image_url, target_path}` into `state.json facts.figma_assets[]` (only verified rows count toward registry success; failed rows are recorded with a `failed: true` flag for traceability).

### Step 4 — Filename grammar

4. **Filename grammar** (full path — the directory component is mandatory): `.context/designs/figma-[screen]-[state]-[node-id].png`
   - **Per-frame child**: `[screen]` = child frame name (lowercased, spaces → hyphens), `[node-id]` = child id (colons → dashes).
   - **Overview** (container image): `[screen]` = container name (lowercased, spaces → hyphens), `[node-id]` = container id (colons → dashes).
   - `[state]`: from the State Input Contract above; defaults to `default`. A container's child frames inherit the URL-level state unless the user annotated per-frame states.
   - **Non-ASCII separators**: Non-alphanumeric characters (dashes, slashes, en-dashes, em-dashes, and other special punctuation) collapse to a single hyphen; consecutive hyphens are squeezed to one.

### Steps 5–7 — Outputs and failure path

5. If multiple Figma URLs provided, repeat steps 1–4 for each.
6. **Summarize per-frame design context** in `<plan_file>` under **Figma Design References** — one bullet **per frame**: state, key badge/label text, and key build notes (shape/geometry, control deltas). The container gets one overview bullet.
7. Write `.context/designs/figma-registry.md` (see Registry Generation below) — one row per persisted frame plus an overview row.

If a Figma MCP call fails for one URL, continue with the remaining URLs, write the registry with successfully-captured rows, and append a failure note to `.context/errors/product-manager.md`.

## Registry Generation

After capturing all screenshots, write `.context/designs/figma-registry.md` using the following structure. Emit **one row per persisted frame** (each child frame gets its own row keyed on its own node id) plus **one Overview row** for the container image. A leaf (single-screen) URL produces exactly one row and **no** Overview row.

### Registry template — entries

```markdown
# Figma Design Registry

Produced by: PL stage (product-manager)
Consumed by: QA stage (qa-engineer)

## Entries

| ID | Screen | State | Device | Figma Node | Screenshot | Target File(s) | AC Ref |
|----|--------|-------|--------|------------|------------|----------------|--------|
| design-001 | skin-analysis-face-scan | overview | iPhone 15 | 255:2263 | figma-skin-analysis-face-scan-overview-255-2263.png | ScanView.swift | AC-1 |
| design-002 | scan-25   | default  | iPhone 15 | 255:2264 | figma-scan-25-default-255-2264.png    | ScanView.swift | AC-1, AC-2 |
<!-- repeat per child frame: design-003 (scan-hint/default/255:2265), design-004 (scan-100/success/255:2266), design-005 (analyzing/loading/255:2267) — same row shape -->
```

### Registry template — notes, sources, metadata

```markdown
<!-- …continued: figma-registry.md template -->
The first row is the container **Overview** (State column = `overview`); rows 002–005 are the four child frames, each with its own Figma Node id and per-frame screenshot. A single-screen URL collapses to one leaf row with no Overview.

## Source URLs

- design-001: https://figma.com/design/FOO/FaceScan?node-id=255-2263 (container)
- design-002: https://figma.com/design/FOO/FaceScan?node-id=255-2264 (child frame)

## Capture Metadata

- Captured at: <ISO-8601 timestamp>
- Captured by: igrsoft:product-manager (PL0)
- Figma file version: <from get_metadata if available, else `unknown`>
```

### Column semantics

Order is authoritative — QA parsers rely on it:

| Column | Source | Default if unknown |
|--------|--------|--------------------|
| `ID` | Sequential `design-NNN` within the task (one per persisted frame + one for the overview) | — |
| `Screen` | Per-frame: child frame name (lowercased, spaces → hyphens). Overview: container name. | node-id if metadata missing |
| `State` | Per State Input Contract above; the Overview row uses the literal `overview` | `default` |
| `Device` | Task context (e.g. "iPhone 15", "Desktop 1440", "iPad") | `unspecified` |
| `Figma Node` | Node ID in API format (colons) — **the frame's own id**, not the container's, for child rows | — |
| `Screenshot` | Filename only, relative to `.context/designs/` | — |
| `Target File(s)` | Implementation files from `<plan_file> § Scope`, comma-separated | `?` |
| `AC Ref` | Acceptance criterion IDs from `<plan_file> § Acceptance Criteria` | blank |

### Per-frame rule and plan reference

**Per-frame rule (REQ-B)**: a container yields N+1 rows — one Overview row (container node id, `State: overview`) plus one row per persisted child frame (each with its own node id, name, and state). A leaf yields exactly one row and no Overview. QA's Design Comparison compares each row's persisted file individually (see `agents/qa-engineer.md § Per-Frame Comparison`).

Reference the registry from `<plan_file> § Figma Design References`:

> See `.context/designs/figma-registry.md` for the full node → screenshot → target mapping.

## Post-Capture Plan Update (REQ-D)

After persistence and registry write — **in this same PL turn**, since the PM is now Bash-capable and has already verified the files on disk — update the plan's `## design-preview` anchor so DV implements and QA verifies against the discrete per-frame files. Use the **Asset-placeholder grammar** in `agents/product-manager.md` (token + description bullet, no raw paths):

### Anchor update steps

1. Keep the captured Figma source URL line(s) at the top of the anchor, verbatim.
2. For each **persisted** per-frame file (verified non-zero PNG), emit a `{{asset:<basename>}}` token line (basename only — no `.context/` path) **immediately followed** by a `- <description>` bullet giving its state mapping and **per-frame build notes**: shape/geometry, badge/label text, and control deltas versus the other states.
3. Emit the Overview file as its own `{{asset:<basename>}}` token + bullet, noting in the bullet that it is the container reference (not a per-state target).

#### QA targeting and failed frames (steps 4–5)

4. Point QA's visual-check at the **discrete frame files** rather than a single combined screenshot — the registry rows are the authoritative per-state targets.
5. Failed/skipped frames (recorded in `state.json facts.figma_assets[]` with `failed: true`) are listed with their open-question reference in a plain bullet (no `{{asset:...}}` token, since there is no verified file to host), never as a satisfied target.

### Publish-helper boundary

The PM writes **only** the tokens and descriptions — it does **not** compute hosted URLs or emit `![...]()` image markdown. The publish helper (`publish-pl-issue.sh`, post-approval) resolves each `{{asset:<basename>}}` to a hosted `![<basename>](<url>)` line **after** sanitisation, with a non-blocking fallback chain (raw.githubusercontent.com → gist → URL-only note). This keeps the PM tool surface narrow and defers asset commits to after human approval (AC-9).

### Example anchor body

Example anchor body the PM writes:

```markdown
## design-preview

https://www.figma.com/design/FOO/FaceScan?node-id=255-2263

{{asset:figma-scan-25-default-255-2264.png}}
- state `default` — 25% progress ring, hint text hidden.
{{asset:figma-analyzing-default-255-2267.png}}
- state `default` — spinner, "Analyzing…" label.
```

No separate orchestrator re-entry is needed: persistence and this plan update both happen inside the PL turn while the screenshot URLs are still valid.

## Coexistence with Pencil Mockups

| Condition | Action |
|-----------|--------|
| Figma URL present | Capture Figma screenshots (always) + write registry |
| Design keyword score >= 5, no Figma URL | Invoke Designer for Pencil mockups (existing behavior); no registry |
| Both Figma URL AND score >= 5 | Capture Figma screenshots + write registry AND invoke Designer; Figma screenshots are the authoritative design reference |
