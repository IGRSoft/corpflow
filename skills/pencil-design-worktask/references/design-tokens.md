# Design Tokens & Naming Conventions

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

When documenting mockups, use this format in the plan file (`<plan_file>` — `.context/planning-N.md`; e.g. `planning-0.md`):

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
