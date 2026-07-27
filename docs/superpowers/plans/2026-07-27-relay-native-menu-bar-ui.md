# Relay Native Menu-Bar UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Relay's dashboard window with a native, menu-only macOS app that keeps every existing Mac control reachable from the UFO menu-bar item.

**Architecture:** `RelayMacApp` owns only a `.menu`-style `MenuBarExtra`. `MenuContent` composes native SwiftUI menus and delegates system alerts, secure text entry, and folder selection to a small AppKit helper. Pure menu descriptors keep the hierarchy testable without rendering AppKit.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ServiceManagement, Sparkle, Swift Testing.

## Global Constraints

- Relay opens no dashboard, settings, or utility window.
- Use native `MenuBarExtra`, `Menu`, `Button`, `Toggle`, `Divider`, `Label`, keyboard shortcuts, SF Symbols, `NSAlert`, and `NSOpenPanel`.
- The UFO remains the 18-point menu-bar label.
- Preserve bridge, cloud, encryption, pairing, workspace, voice, and destructive-action behavior.
- Keep secrets out of menu labels, logs, and copied diagnostics.
- Preserve the user's Xcode scheme and workspace files.

---

### Task 1: Testable menu contract and window removal

**Files:**
- Modify: `mac/Tests/RelayMacTests/RelayNavigationTests.swift`
- Create: `mac/Sources/RelayMac/RelayMenuStructure.swift`
- Modify: `mac/Sources/RelayMac/RelayMacApp.swift`
- Delete after callers are removed: dashboard-only SwiftUI files that no longer belong to the target

**Interfaces:**
- Produces: `RelayMenuGroup`, `RelayMenuItem`, and `RelayMenuStructure.root`.
- Produces: an app scene containing only `MenuBarExtra`.

- [ ] **Step 1: Write failing menu hierarchy tests**

Replace the dashboard-section assertion with tests that require root groups for
status, actions, connection, maintenance, and lifecycle; require Apple Watch,
Workspaces, Relay Cloud, Voice and Transcription, Diagnostics, Updates, About,
Emergency Stop, and Quit; and reject `Open Dashboard`.

- [ ] **Step 2: Verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test --disable-sandbox --package-path mac \
  --scratch-path /private/tmp/relay-menu-task1-red \
  --filter RelayNavigationTests
```

Expected: failure because `RelayMenuStructure` does not exist and the current app
still exposes a dashboard window.

- [ ] **Step 3: Add the pure menu structure and remove the Window scene**

Define stable item identifiers and titles in `RelayMenuStructure.swift`. Remove
the `Window("Relay", id: "dashboard")` scene from `RelayMacApp` while retaining
the UFO `MenuBarExtra` and `.menu` style.

- [ ] **Step 4: Verify GREEN**

Run the focused test command and confirm the menu contract passes.

### Task 2: Native root menu and functional submenus

**Files:**
- Modify: `mac/Tests/RelayMacTests/RelayNavigationTests.swift`
- Create: `mac/Sources/RelayMac/RelayMenuDialogs.swift`
- Rewrite: `mac/Sources/RelayMac/MenuContent.swift`
- Modify only if required: `mac/Sources/RelayMac/RelayAppModel.swift`

**Interfaces:**
- Consumes: `RelayMenuStructure`, `RelayAppModel`, and `RelayUpdateController`.
- Produces: `RelayMenuDialogs.requestEmail()`, `requestOpenAIKey()`,
  `chooseWorkspace()`, `copyText(_:)`, and destructive confirmation helpers.

- [ ] **Step 1: Write failing behavior-contract tests**

Add tests for status wording, pairing expiry formatting, workspace display names,
safe diagnostic text, and destructive action labels. Each test calls pure helpers
used by `MenuContent`.

- [ ] **Step 2: Verify RED**

Run the focused `RelayMacTests` suite. Confirm failure on missing helper behavior.

- [ ] **Step 3: Compose the root menu**

Build these native groups in order:

```text
Relay status
Pending Actions >
Apple Watch >
Workspaces >
Relay Cloud >
Voice & Transcription >
Start Relay at Login
Diagnostics >
Check for Updates…
About Relay >
Emergency Stop…
Quit Relay    Command-Q
```

Use disabled `Text` rows for status and empty states. Do not create custom row
backgrounds or popover chrome.

- [ ] **Step 4: Wire Apple Watch and Workspaces**

Apple Watch supports creating a pairing session, copying the code, refreshing and
approving or denying requests, listing devices, and confirmed revocation.
Workspaces lists allowed roots, uses `NSOpenPanel` to add one, copies or reveals a
selected path, and confirms removal.

- [ ] **Step 5: Wire Relay Cloud, voice, diagnostics, and maintenance**

Use `NSAlert` text input for Relay Cloud email sign-in and secure input for the
OpenAI key. Keep sign-out, account deletion, Start at Login, refresh, update check,
About links, Emergency Stop, and Quit connected to the existing model methods.
Copy only the existing redacted diagnostic string plus non-secret state labels.

- [ ] **Step 6: Verify GREEN**

Run the focused suite, then all Mac tests. Confirm the executable links.

### Task 3: Remove dashboard-only code and document menu testing

**Files:**
- Delete: `mac/Sources/RelayMac/DashboardView.swift`
- Delete: `mac/Sources/RelayMac/Components.swift`
- Delete: `mac/Sources/RelayMac/SetupView.swift`
- Delete: `mac/Sources/RelayMac/WatchesView.swift`
- Delete: `mac/Sources/RelayMac/WorkspacesView.swift`
- Delete: `mac/Sources/RelayMac/RemoteAccessView.swift`
- Delete: `mac/Sources/RelayMac/VoiceView.swift`
- Delete: `mac/Sources/RelayMac/UpdatesView.swift`
- Delete: `mac/Sources/RelayMac/DiagnosticsView.swift`
- Delete: `mac/Sources/RelayMac/AboutView.swift`
- Modify: `docs/TODO.md`
- Modify: `docs/SETUP.md`

**Interfaces:**
- Consumes: the complete menu-only implementation.
- Produces: one menu-only application target with no dead dashboard sources.

- [ ] **Step 1: Prove dashboard files have no remaining callers**

Run `rg` for every dashboard type. Delete a file only after its type has no caller
outside that file.

- [ ] **Step 2: Update local test instructions**

Document launching `RelayMac`, locating the UFO beside other menu-bar items, and
checking every submenu without expecting a dashboard window.

- [ ] **Step 3: Run final verification**

Run all Mac tests, `swift build`, `git diff --check`, and a source scan that rejects
`Window("Relay"`, `openWindow`, and `Open Dashboard` from production Mac sources.

- [ ] **Step 4: Commit and launch**

Commit the menu-only app and documentation while excluding user Xcode files. Run
the built `RelayMac` executable so the user can test the UFO menu interactively.
