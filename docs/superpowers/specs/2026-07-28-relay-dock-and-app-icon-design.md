# Relay Dock and App Icon Design

**Date:** 2026-07-28
**Status:** Approved

## Goal

Make Relay easy to find as a normal installed Mac application without adding a
dashboard, settings window, popover, or other secondary interface.

## Approved behavior

- Relay remains strictly menu-bar-only for its interface.
- The existing UFO opens the existing native macOS menu.
- Relay uses the approved white/silver UFO as its installed application icon in
  Applications and Launchpad.
- The same application icon remains visible in the Dock while Relay is running.
- Clicking the Dock icon does not open a window; the menu-bar UFO remains the
  only entry point to Relay controls.
- Closing system dialogs returns the user to the menu-bar app and does not quit
  Relay. Quit Relay remains the explicit way to stop the app.

## Implementation boundary

The packaged Mac application must run as a regular foreground application so
macOS supplies its Dock presence. The package continues to compile and declare
the existing `AppIcon.icns`. Only the app-agent policy changes; no SwiftUI
window scene or dashboard source is added.

This does not change the bridge, Relay Cloud, encryption, Apple Watch pairing,
Codex control, workspaces, voice, updates, or safety behavior.

## Acceptance criteria

- A packaged `Relay.app` shows the white/silver UFO in Applications and
  Launchpad.
- Launching `Relay.app` shows the UFO in both the macOS menu bar and Dock.
- Relay opens no normal window on launch or when its Dock icon is clicked.
- The existing menu and all its controls remain unchanged.
- Quit Relay removes both running icons.
- Packaging tests reject a background-agent-only `LSUIElement=true` build.
