# Relay AppKit Status Item Design

**Date:** 2026-07-28
**Status:** Approved

## Goal

Keep Relay strictly menu-bar-only while reliably showing the supplied UFO in
the menu bar, the approved application icon in the Dock, and the installed app
in Applications, Launchpad, and Spotlight search.

## Menu-bar shell

Replace only the SwiftUI `MenuBarExtra` scene with an AppKit `NSStatusItem`.
The application continues to expose no dashboard, settings window, popover, or
other normal window.

The status item uses the user-supplied UFO SVG. Every fixed color is converted
to a solid template mask. `NSImage.isTemplate` remains enabled so macOS renders
the UFO white in dark appearances and black in light appearances. The status
image renders at 24 by 24 points so the wide UFO has similar visual weight to
neighboring system items without modifying or stretching its paths. The status
button accessibility title is `Relay`.

## Native menu

Build a standard `NSMenu` from the existing `RelayAppModel`. Preserve the
current hierarchy, copy, disabled states, keyboard shortcut, confirmations, and
actions for status, pending actions, Apple Watch, workspaces, Relay Cloud,
voice, login, diagnostics, updates, About, Emergency Stop, and Quit.

Rebuild dynamic menu state immediately before opening the menu. Action targets
remain retained for the lifetime of each built menu. No bridge, cloud,
encryption, pairing, workspace, voice, update, or safety contract changes.

## Installation and discovery

The release package includes the application icon and the menu-bar SVG. Local
validation installs the finished `Relay.app` at `/Applications/Relay.app`, then
registers that exact bundle with LaunchServices. Spotlight and Launchpad must
discover the installed bundle; temporary builds under `/private/tmp` are not
treated as installed applications.

## Acceptance criteria

- The supplied UFO is visibly present in the macOS menu bar.
- The UFO renders at 24 by 24 points and visually matches neighboring items.
- The UFO adapts automatically between dark and light menu-bar appearances.
- Selecting the UFO opens the existing native Relay menu.
- Relay owns zero normal windows.
- Relay remains visible in the Dock while running.
- `/Applications/Relay.app` exists and carries the approved application icon.
- LaunchServices recognizes `com.relayforcodex.mac` at the Applications path.
- Existing functional and security tests pass.
