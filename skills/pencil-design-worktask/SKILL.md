---
name: pencil-design-worktask
description: Use when generating design mockups, creating .pen files, or integrating design tokens. Design mockup generation worktask using Pencil MCP tools for the Designer agent.
keep-coding-instructions: true
paths:
  - "**/*.pen"
related:
  - agents/designer.md
  - skills/task-folder-organization/SKILL.md
---

# Pencil Design Worktask

Design mockup generation worktask using Pencil MCP tools for the Designer agent.

Token setup, naming conventions, and doc-reference format: `${CLAUDE_SKILL_DIR}/references/design-tokens.md`

## When to Generate

**Generate** when the task triggers design detection (score >= 5), creates new UI screens or components, or redesigns existing UI significantly.

**Do NOT generate** for backend-only tasks (APIs, databases, infrastructure), minor copy or styling tweaks, or tasks explicitly marked "no UI".

## Prerequisites

### Loading Pencil Tools

Every `mcp__pencil__*` tool is deferred — load them once at the start of a design session:

```
ToolSearch({ query: "+pencil" })
```

### Available Tools

#### Document, element, and validation tools

| Tool | Purpose |
|------|---------|
| `get_editor_state` | Check current Pencil editor state and active file |
| `open_document` | Open existing or create new .pen file |
| `batch_design` | Insert, update, replace, copy, move, delete design elements (max 25 ops per call) |
| `batch_get` | Read element nodes by pattern or ID |
| `get_screenshot` | Visual validation — capture screenshot of a node |
| `snapshot_layout` | Structured layout export for developer handoff |

#### Guideline, token, and search tools

| Tool | Purpose |
|------|---------|
| `get_guidelines` | Design guidelines by topic (design-system, landing-page, table, code, tailwind) |
| `get_style_guide_tags` | List available style guide tag categories |
| `get_style_guide` | Retrieve style guide by tags or name for design inspiration |
| `get_variables` | Read design tokens/variables from .pen file |
| `set_variables` | Create/update design tokens in .pen file |
| `find_empty_space_on_canvas` | Find placement coordinates for new elements |
| `search_all_unique_properties` | Search element properties across node tree |
| `replace_all_matching_properties` | Batch property updates across node tree |

## Mockup Generation Worktask

### Step 1: Preparation

```typescript
ToolSearch({ query: "+pencil" })                                   // once per session

// Guidelines for the task type — topics: design-system, landing-page, table, code, tailwind
mcp__pencil__get_guidelines({ topic: "design-system" })

// Style guide for inspiration: list tags, then pick 5-10 relevant ones
mcp__pencil__get_style_guide_tags()
mcp__pencil__get_style_guide({ tags: ["mobile", "clean", "minimal", ...] })
```

### Step 2: Create Document

```typescript
// Workspace-aware path — worktrees keep their designs beside their own .context/
const task = state.tasks[currentTaskId];
const workspacePath = task.metadata?.workspace_path;
const designsPath = workspacePath ? `${workspacePath}/.context/designs` : `.context/designs`;
const filePath = `${designsPath}/mockup-feature-screen.pen`;

mcp__pencil__open_document({ filePathOrTemplate: filePath })
```

### Step 3: Build Design

`batch_design` takes operation strings, max 25 operations per call. For complex designs split into logical sections — structure first, then content, then details.

```typescript
mcp__pencil__batch_design({
  filePath,
  operations: `
screen=I(document, {type: "frame", name: "Login Screen", width: 375, height: 667, fill: "#FFFFFF", layout: "vertical"})
header=I(screen, {type: "frame", name: "Header", width: "fill_container", height: 88, layout: "horizontal", alignItems: "center", padding: 16})
title=I(header, {type: "text", content: "Login", fontSize: 20, fontWeight: "600", fill: "#333333"})
content=I(screen, {type: "frame", name: "Content", width: "fill_container", layout: "vertical", gap: 24, padding: 32})
`
})
```

Later calls address already-created nodes by id, same operation syntax: `emailInput=I("content-id", {type: "frame", name: "Email Input", width: "fill_container", height: 48, cornerRadius: 8, fill: "#F5F5F5", stroke: "#CCCCCC"})`.

### Step 4: Visual Validation

Always validate visually after building: screenshot, analyze, adjust with `U(...)` update operations, re-screenshot.

```typescript
mcp__pencil__get_screenshot({ filePath, nodeId: "screen-node-id" })
mcp__pencil__batch_design({ filePath, operations: `U("node-id", {padding: 24, gap: 16})` })
mcp__pencil__get_screenshot({ filePath, nodeId: "screen-node-id" })
```

### Step 5: Handoff Preparation

```typescript
// Layout structure for developers
mcp__pencil__snapshot_layout({ filePath, maxDepth: 3 })

// Specific component details, if needed
mcp__pencil__batch_get({ filePath, patterns: [{ type: "frame" }], readDepth: 2 })
```

## Multiple States in One Document

Represent multiple UI states as separate frames in a single .pen file, positioning each with `find_empty_space_on_canvas`:

```typescript
defaultScreen=I(document, {type: "frame", name: "Login - Default", width: 375, height: 667, ...})
errorScreen=I(document, {type: "frame", name: "Login - Error", width: 375, height: 667, ...})

mcp__pencil__find_empty_space_on_canvas({ filePath, width: 375, height: 667, padding: 100, direction: "right" })
```

## Quality Checklist

Before completing design work:

- [ ] All critical screens have .pen mockups
- [ ] Key states represented (default, error, empty, loading) as frames
- [ ] Design tokens used via Pencil variables (not hardcoded values)
- [ ] File names follow naming convention
- [ ] Mockups saved to correct path (workspace-aware `.context/designs/`)
- [ ] Visual validation done via `get_screenshot()`
- [ ] Layout snapshot captured via `snapshot_layout()` for developer handoff
- [ ] All mockups referenced in design documentation with descriptions
- [ ] Style guide consulted for design consistency

## Fallback: Pencil Unavailable

If Pencil MCP tools fail to load or calls error (e.g. Pencil.app not running): document the design in text only — detailed layout descriptions and measurements — note in the documentation that visual mockups were not generated, and report the issue so it can be fixed for future tasks.
