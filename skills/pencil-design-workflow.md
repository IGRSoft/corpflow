---
name: pencil-design-workflow
description: Design mockup generation workflow using Pencil MCP tools for the Designer agent. Use when generating design mockups, creating .pen files, or integrating design tokens.
---

# Pencil Design Workflow

Design mockup generation workflow using Pencil MCP tools for the Designer agent.

## When to Generate

**Generate mockups when:**
- Task triggers design detection (score >= 5)
- New UI screens or components are being created
- Existing UI is being redesigned or significantly modified

**Do NOT generate mockups for:**
- Backend-only tasks (APIs, databases, infrastructure)
- Minor copy or styling tweaks
- Tasks explicitly marked as "no UI"

## Prerequisites

### Loading Pencil Tools

All Pencil MCP tools are deferred and must be loaded before use:

```
ToolSearch({ query: "+pencil" })
```

This loads all `mcp__pencil__*` tools. Do this once at the start of any design session.

### Available Tools

| Tool | Purpose |
|------|---------|
| `get_editor_state` | Check current Pencil editor state and active file |
| `open_document` | Open existing or create new .pen file |
| `batch_design` | Insert, update, replace, copy, move, delete design elements (max 25 ops per call) |
| `batch_get` | Read element nodes by pattern or ID |
| `get_screenshot` | Visual validation — capture screenshot of a node |
| `snapshot_layout` | Structured layout export for developer handoff |
| `get_guidelines` | Design guidelines by topic (design-system, landing-page, table, code, tailwind) |
| `get_style_guide_tags` | List available style guide tag categories |
| `get_style_guide` | Retrieve style guide by tags or name for design inspiration |
| `get_variables` | Read design tokens/variables from .pen file |
| `set_variables` | Create/update design tokens in .pen file |
| `find_empty_space_on_canvas` | Find placement coordinates for new elements |
| `search_all_unique_properties` | Search element properties across node tree |
| `replace_all_matching_properties` | Batch property updates across node tree |

## Mockup Generation Workflow

### Step 1: Preparation

```typescript
// 1. Load Pencil tools (once per session)
ToolSearch({ query: "+pencil" })

// 2. Get design guidelines for the task type
mcp__pencil__get_guidelines({ topic: "design-system" })
// Available topics: design-system, landing-page, table, code, tailwind

// 3. Get style guide for design inspiration
mcp__pencil__get_style_guide_tags()
// Then pick 5-10 relevant tags:
mcp__pencil__get_style_guide({ tags: ["mobile", "clean", "minimal", ...] })
```

### Step 2: Create Document

```typescript
// Determine workspace-aware path
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const designsPath = workspacePath
  ? `${workspacePath}/.context/designs`
  : `.context/designs`;

// Create the .pen file
mcp__pencil__open_document({
  filePathOrTemplate: `${designsPath}/mockup-feature-screen.pen`
})
```

### Step 3: Build Design

Use `batch_design` with operation strings. Max 25 operations per call.

```typescript
// Create screen structure
mcp__pencil__batch_design({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  operations: `
screen=I(document, {type: "frame", name: "Login Screen", width: 375, height: 667, fill: "#FFFFFF", layout: "vertical"})
header=I(screen, {type: "frame", name: "Header", width: "fill_container", height: 88, layout: "horizontal", alignItems: "center", padding: 16})
title=I(header, {type: "text", content: "Login", fontSize: 20, fontWeight: "600", fill: "#333333"})
content=I(screen, {type: "frame", name: "Content", width: "fill_container", layout: "vertical", gap: 24, padding: 32})
`
})

// Add form elements in subsequent calls
mcp__pencil__batch_design({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  operations: `
emailLabel=I("content-id", {type: "text", content: "Email", fontSize: 14, fontWeight: "600", fill: "#333333"})
emailInput=I("content-id", {type: "frame", name: "Email Input", width: "fill_container", height: 48, cornerRadius: 8, fill: "#F5F5F5", stroke: "#CCCCCC"})
`
})
```

For complex designs, split into logical sections (structure first, then content, then details).

### Step 4: Visual Validation

```typescript
// Always validate visually after building
mcp__pencil__get_screenshot({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  nodeId: "screen-node-id"
})

// Analyze the screenshot for correctness
// If adjustments needed, use batch_design with Update operations:
mcp__pencil__batch_design({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  operations: `U("node-id", {padding: 24, gap: 16})`
})

// Re-validate
mcp__pencil__get_screenshot({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  nodeId: "screen-node-id"
})
```

### Step 5: Handoff Preparation

```typescript
// Capture layout structure for developers
mcp__pencil__snapshot_layout({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  maxDepth: 3
})

// Read specific component details if needed
mcp__pencil__batch_get({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  patterns: [{ type: "frame" }],
  readDepth: 2
})
```

## Design Tokens via Pencil Variables

Instead of hardcoded color values, use Pencil's variable system.

### Reading Existing Tokens

Always check for existing tokens first:
```typescript
mcp__pencil__get_variables({
  filePath: `${designsPath}/mockup-feature-screen.pen`
})
```

### Setting Up Project Tokens

```typescript
mcp__pencil__set_variables({
  filePath: `${designsPath}/mockup-feature-screen.pen`,
  variables: {
    "color-background": { type: "color", value: "#FFFFFF" },
    "color-surface": { type: "color", value: "#F5F5F5" },
    "color-text-primary": { type: "color", value: "#333333" },
    "color-text-secondary": { type: "color", value: "#666666" },
    "color-border": { type: "color", value: "#CCCCCC" },
    "color-accent": { type: "color", value: "#4A90E2" },
    "color-error": { type: "color", value: "#D32F2F" },
    "color-success": { type: "color", value: "#388E3C" }
  }
})
```

## Multiple States in One Document

Multiple UI states can be represented as separate frames within a single .pen file:

```typescript
// Default state
defaultScreen=I(document, {type: "frame", name: "Login - Default", width: 375, height: 667, ...})

// Error state (positioned to the right)
errorScreen=I(document, {type: "frame", name: "Login - Error", width: 375, height: 667, ...})
// Or use find_empty_space_on_canvas to position:
mcp__pencil__find_empty_space_on_canvas({
  filePath: filePath,
  width: 375, height: 667, padding: 100, direction: "right"
})
```

## Naming Convention

**Pattern**: `mockup-[feature]-[screen]-[variant].pen`

Examples:
- `mockup-login-screen.pen` -- Default login
- `mockup-login-screen-error.pen` -- Login with validation errors (if separate file)
- `mockup-profile-edit-form.pen` -- Profile editing
- `mockup-dashboard-empty-state.pen` -- Dashboard with no data

When a single .pen file contains multiple states as frames, use the base name without variant suffix.

## Storage

Save to `.context/designs/` with workspace-aware path resolution:

```typescript
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const designsPath = workspacePath
  ? `${workspacePath}/.context/designs`
  : `.context/designs`;

mcp__pencil__open_document({
  filePathOrTemplate: `${designsPath}/mockup-feature-screen.pen`
})
```

## Reference Format in Documentation

When documenting mockups, use this format in planning.md:

```markdown
## Visual Mockups

Generated Pencil mockups (see `.context/designs/`):

- **`mockup-login-screen.pen`** -- Default login with email/password fields (frames: Default, Error, Loading)
- **`mockup-registration-flow.pen`** -- Registration steps

### Design Specifications

(Reference: `mockup-login-screen.pen`)

**Layout** (from `snapshot_layout()`):
- Screen frame: 375x667, vertical layout
- Header: 88pt height, horizontal layout
- Form: vertical layout, 24pt gap, 32pt padding
- Input fields: fill-width, 48pt height, 8pt corner radius
- Primary button: fill-width, 48pt height, 32pt below last input

**States Included:**
1. Default (empty fields)
2. Error (validation failed)
3. Loading (authentication in progress)
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

If Pencil MCP tools fail to load or calls error (e.g., Pencil.app not running):
1. Document the design specifications in text form only
2. Include detailed layout descriptions and measurements
3. Note in documentation that visual mockups were not generated
4. Report the issue so it can be resolved for future tasks

## Related

- `agents/designer.md` - Designer agent definition
- `skills/task-folder-organization.md` - `.context/designs/` directory structure and context folder organization
