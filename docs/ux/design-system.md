# Design System

Driftline should feel like a quiet professional macOS tool: glassy but readable, dense but calm.

## Tokens

- Accent teal: connection and active transfer.
- Glacier blue: selected remote state.
- Warm amber: warnings and pending trust.
- System red: destructive or failed states.
- Use semantic system foreground and material backgrounds.

## Components

- `ConnectionStatusPill`
- `TransferStatusBadge`
- `InspectorSection`
- `EmptyStateView`
- Future: `GlassPanel`, `GlassSidebar`, `FileListRow`, `ToolbarButton`, `BookmarkRow`, `StatsCard`

## Rules

- Prefer native sidebars, tables, inspectors, toolbars, sheets, and menus.
- Use material backgrounds with restraint.
- Keep text readable in light, dark, and high contrast modes.
- Keep cards to true grouped content, not whole page sections.
- Use SF Symbols for toolbar and row icons.
