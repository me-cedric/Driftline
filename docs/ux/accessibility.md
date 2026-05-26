# Accessibility

Planned and initial accessibility expectations:

- VoiceOver labels for connection and transfer status.
- Keyboard shortcuts for core workflows.
- High contrast compatibility through semantic colors.
- Reduced motion respect for future animations.
- Focusable toolbars, sidebar, browser tables, and inspector actions.
- Readable glass backgrounds.

## Implemented

- Toolbar controls include accessibility hints for refresh, upload, download, connect, and terminal actions.
- File browser rows expose file name and kind.
- Transfer controls describe cancel/retry behavior.
- Host trust confirmation includes an explicit accessibility hint.

## Remaining Audit

- Run VoiceOver manually across create server, host trust, transfer conflict, and view options flows.
- Add UI automation coverage for keyboard-only workflows.
- Verify high contrast with real screenshots before tagged releases.
