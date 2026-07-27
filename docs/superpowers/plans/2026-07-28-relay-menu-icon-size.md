# Relay Menu Icon Size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Increase only the adaptive Relay menu-bar UFO from 18 by 18 points to 24 by 24 points.

**Architecture:** Keep the supplied SVG, template-image behavior, square status item, menu hierarchy, Dock icon, and application icon unchanged. Update the AppKit presentation size and its source-level contract, then rebuild and visually compare the installed app.

**Tech Stack:** Swift 6, AppKit, Node test runner, zsh packaging, LaunchServices.

## Global Constraints

- Preserve the supplied SVG paths and adaptive template coloring.
- Do not modify the Dock or application icon.
- Preserve the menu-only, zero-window application behavior.
- Do not stage the user's Xcode scheme or workspace changes.

---

### Task 1: Enlarge and verify the menu-bar UFO

**Files:**
- Modify: `apple-watch/test/project.test.mjs`
- Modify: `mac/Sources/RelayMac/RelayStatusItemController.swift`

**Interfaces:**
- Consumes: `RelayMenuBarIcon.svg` through `Bundle.main`.
- Produces: `NSImage.size = NSSize(width: 24, height: 24)`.

- [x] **Step 1: Update the source contract to require 24 points**

Change the final Mac icon assertion to:

```javascript
assert.match(statusController, /image\.size = NSSize\(width: 24, height: 24\)/);
```

- [x] **Step 2: Run the focused test and verify it fails**

Run: `node --test apple-watch/test/project.test.mjs`

Expected: the menu icon assertion fails because production still uses 18 points.

- [x] **Step 3: Update the AppKit presentation size**

Change only the controller assignment to:

```swift
image.size = NSSize(width: 24, height: 24)
```

- [x] **Step 4: Run automated verification**

Run:

```bash
node --test apple-watch/test/project.test.mjs
xcrun swift test --disable-sandbox --package-path mac
pnpm test
git diff --check
```

Expected: 17 project tests, 60 Mac tests, and 191 repository tests pass.

- [x] **Step 5: Package, install, and visually inspect**

Package version `0.0.0`, replace `/Applications/Relay.app`, register it with LaunchServices, launch it, and capture the menu bar. Confirm the UFO has similar visual weight to adjacent icons and Relay still owns zero windows.

- [x] **Step 6: Commit and push**

Stage only this plan, the source contract, and the AppKit controller. Commit with `fix(mac): enlarge Relay menu icon`, then push the current branch to `origin`.
