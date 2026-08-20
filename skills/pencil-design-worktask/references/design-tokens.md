# Design Tokens & Naming Conventions

## Design Tokens via Pencil Variables

Use Pencil's variable system instead of hardcoded values, and always read the existing tokens before writing new ones:

```typescript
mcp__pencil__get_variables({ filePath })

mcp__pencil__set_variables({
  filePath,
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

**Pattern**: `mockup-[feature]-[screen]-[variant].pen` — e.g. `mockup-login-screen.pen` (default login), `mockup-login-screen-error.pen` (validation errors, when kept as a separate file), `mockup-profile-edit-form.pen`, `mockup-dashboard-empty-state.pen`.

A single .pen file holding multiple states as frames uses the base name with no variant suffix.

## Storage

Save to `.context/designs/` with workspace-aware path resolution — the `designsPath` / `filePath` snippet lives in `../SKILL.md § Step 2: Create Document` and every later call reuses `filePath`.

## Reference Format in Documentation

Document mockups in the plan file (`<plan_file>` — `.context/planning-N.md`; e.g. `planning-0.md`) in this format:

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
