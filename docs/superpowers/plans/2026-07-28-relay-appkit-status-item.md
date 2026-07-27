# Relay AppKit Status Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the supplied adaptive UFO through AppKit, retain Relay's complete native menu, and install a searchable Mac application.

**Architecture:** A SwiftUI `App` supplies lifecycle only through `NSApplicationDelegateAdaptor`; `RelayStatusItemController` owns one `NSStatusItem` and rebuilds its standard `NSMenu` from `RelayAppModel` before presentation. The package copies the supplied SVG into the main bundle, where AppKit loads it as a template image.

**Tech Stack:** Swift 6, AppKit, SwiftUI lifecycle, Combine, zsh packaging, LaunchServices, Node and Swift Testing.

## Global Constraints

- Relay owns no normal window.
- The supplied UFO uses no fixed color at runtime; `NSImage.isTemplate` controls light/dark rendering.
- Preserve all existing menu actions and confirmations.
- Preserve bridge, cloud, encryption, pairing, workspace, voice, update, and safety behavior.
- Preserve the user's Watch scheme and workspace files.

---

### Task 1: AppKit status-item lifecycle

**Files:**
- Modify: `apple-watch/test/project.test.mjs`
- Modify: `mac/Sources/RelayMac/RelayMacApp.swift`
- Create: `mac/Sources/RelayMac/RelayAppDelegate.swift`
- Create: `mac/Sources/RelayMac/RelayStatusItemController.swift`

**Interfaces:**
- Produces: `RelayAppDelegate.applicationDidFinishLaunching(_:)`.
- Produces: `RelayStatusItemController.init(model:)` and one retained `NSStatusItem`.

- [ ] **Step 1: Write failing shell tests**

Require `NSApplicationDelegateAdaptor`, reject `MenuBarExtra`, require
`NSStatusBar.system.statusItem`, `NSImage.isTemplate = true`, and the `Relay`
accessibility title.

- [ ] **Step 2: Verify RED**

Run the focused `project.test.mjs` Mac status-item tests and confirm failure on
the missing AppKit shell.

- [ ] **Step 3: Add lifecycle and status image**

Use this lifecycle shape:

```swift
@main
struct RelayMacApp: App {
    @NSApplicationDelegateAdaptor(RelayAppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
```

The delegate creates one `RelayAppModel` and retains one
`RelayStatusItemController`. The controller loads `RelayMenuBarIcon.svg` from
`Bundle.main`, marks the image as a template, sizes it to 24 points, and assigns
it to the status button with accessibility title `Relay`.

- [ ] **Step 4: Compile and verify GREEN**

Run the focused Node tests and `xcrun swift build --package-path mac`.

### Task 2: Preserve the complete native menu

**Files:**
- Modify: `mac/Sources/RelayMac/RelayStatusItemController.swift`
- Modify: `mac/Tests/RelayMacTests/RelayNavigationTests.swift`

**Interfaces:**
- Consumes: `RelayAppModel`, `RelayMenuPresentation`, `RelayMenuDialogs`, and `RelayUpdateController`.
- Produces: `menuWillOpen(_:)`, `rebuildMenu()`, and retained closure-backed action targets.

- [ ] **Step 1: Add a failing menu parity test**

Require the AppKit controller to use `RelayMenuStructure.root` and verify that
the existing root contract still contains Status, Pending Actions, Apple Watch,
Workspaces, Relay Cloud, Voice and Transcription, Start at Login, Diagnostics,
Updates, About, Emergency Stop, and Quit.

- [ ] **Step 2: Verify RED**

Run `RelayNavigationTests` and confirm failure because the controller does not
yet build the menu contract.

- [ ] **Step 3: Build standard NSMenu groups**

Implement disabled status items, separators, submenus, checkmarks, Command-Q,
and the exact actions currently present in `MenuContent.swift`. Use a retained
`RelayMenuActionTarget` per actionable item:

```swift
@MainActor
final class RelayMenuActionTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func perform() { handler() }
}
```

Rebuild the menu in `menuWillOpen(_:)` so model state and disabled states are
fresh. Keep every destructive confirmation in `RelayMenuDialogs`.

- [ ] **Step 4: Verify menu parity**

Run focused Mac tests, all Mac tests, and compile the executable.

### Task 3: Package, install, and verify discovery

**Files:**
- Modify: `scripts/package-mac-app.sh`
- Modify: `release/test/permanent-identifiers.test.mjs`
- Create: `mac/Resources/RelayMenuBarIcon.svg`
- Modify: `docs/SETUP.md`

**Interfaces:**
- Produces: `Relay.app/Contents/Resources/RelayMenuBarIcon.svg`.
- Produces: `/Applications/Relay.app` registered as `com.relayforcodex.mac` during local validation.

- [ ] **Step 1: Write failing packaging assertions**

Require the packaging script to copy `mac/Resources/RelayMenuBarIcon.svg` into
the application resources and require the SVG source to contain no supplied
hex color.

- [ ] **Step 2: Verify RED**

Run `node --test release/test/permanent-identifiers.test.mjs` and confirm the
resource-copy contract is missing.

- [ ] **Step 3: Add the adaptive SVG resource**

Store the supplied paths with `stroke="black"` and `fill="black"` only. Copy
the file into the app's Resources directory before signing. Document that only
installed bundles appear reliably in Spotlight and Launchpad.

- [ ] **Step 4: Package and inspect**

Build an unsigned local app, verify the SVG exists, verify `LSUIElement=false`,
verify code signing, and launch it. Capture the screen and confirm the UFO is
visibly present, clicking it opens the menu, the Dock contains Relay, and Relay
owns zero windows.

- [ ] **Step 5: Run complete verification**

Run `pnpm test`, all Mac tests, `git diff --check`, and the package build.

- [ ] **Step 6: Commit and install**

Commit only scoped files. After confirming the target, install the validated
bundle at `/Applications/Relay.app`, register it with LaunchServices, launch it,
and verify LaunchServices resolves `com.relayforcodex.mac` to that path.
