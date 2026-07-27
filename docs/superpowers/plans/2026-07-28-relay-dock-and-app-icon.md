# Relay Dock and App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Relay menu-bar-only while showing its approved UFO application icon in Applications, Launchpad, and the Dock while running.

**Architecture:** Preserve the existing SwiftUI `MenuBarExtra` scene and existing compiled `AppIcon.icns`. Change only the packaged application's macOS activation policy by setting `LSUIElement` to `false`, backed by a source-level release packaging contract test.

**Tech Stack:** zsh release packaging, macOS Info.plist, Node.js built-in test runner.

## Global Constraints

- Do not add a SwiftUI `Window`, dashboard, settings window, or popover.
- Do not change the existing menu hierarchy or controls.
- Preserve the approved white/silver UFO source icon.
- Preserve the user's Xcode scheme and workspace files.

---

### Task 1: Enable packaged Dock presence

**Files:**
- Modify: `release/test/permanent-identifiers.test.mjs`
- Modify: `scripts/package-mac-app.sh`

**Interfaces:**
- Consumes: the existing `AppIcon.icns` asset compilation and `CFBundleIconFile` declaration.
- Produces: a packaged `Relay.app` with `LSUIElement=false`, allowing macOS to show the app in the Dock while it runs.

- [x] **Step 1: Write the failing packaging policy test**

Add these assertions to `consumer builds use permanent Apple product identifiers`:

```javascript
assert.match(macPackaging, /CFBundleIconFile string AppIcon/);
assert.match(macPackaging, /LSUIElement bool false/);
assert.doesNotMatch(macPackaging, /LSUIElement bool true/);
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
node --test release/test/permanent-identifiers.test.mjs
```

Expected: FAIL because the current packaging script declares `LSUIElement bool true`.

- [x] **Step 3: Make the minimal packaging change**

In `scripts/package-mac-app.sh`, replace:

```zsh
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "${contents_path}/Info.plist"
```

with:

```zsh
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool false" "${contents_path}/Info.plist"
```

- [x] **Step 4: Verify GREEN and guard the menu-only UI**

Run:

```bash
node --test release/test/permanent-identifiers.test.mjs
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path mac --filter RelayNavigationTests
pnpm test
git diff --check
```

Expected: all tests pass, and `RelayNavigationTests` continues to reject window and dashboard code.

- [x] **Step 5: Build and inspect a local app bundle**

Package an unsigned local build into `/private/tmp/relay-dock-validation`, then inspect its plist and icon:

```bash
RELAY_VERSION=0.0.0-local RELAY_SIGN_IDENTITY=- RELAY_OUTPUT_DIR=/private/tmp/relay-dock-validation ./scripts/package-mac-app.sh
/usr/libexec/PlistBuddy -c "Print :LSUIElement" /private/tmp/relay-dock-validation/Relay.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" /private/tmp/relay-dock-validation/Relay.app/Contents/Info.plist
test -f /private/tmp/relay-dock-validation/Relay.app/Contents/Resources/AppIcon.icns
```

Expected: `false`, `AppIcon`, and a present compiled icon. The build remains menu-only; final Dock/Launchpad appearance is visually checked by launching the bundle.

- [x] **Step 6: Commit only scoped files**

```bash
git add release/test/permanent-identifiers.test.mjs scripts/package-mac-app.sh docs/superpowers/plans/2026-07-28-relay-dock-and-app-icon.md
git commit -m "feat(mac): show Relay in Dock while running"
```
