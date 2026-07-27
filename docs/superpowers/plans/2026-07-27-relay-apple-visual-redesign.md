# Relay Apple Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved white/silver UFO identity and native graphite Apple design language to Relay's Mac app, menu-bar item, and Apple Watch app.

**Architecture:** Keep all product state and transport behavior unchanged. Add small platform-specific presentation primitives for the UFO glyph and semantic styling, replace the two app icon sources, then compose those primitives through the existing SwiftUI views.

**Tech Stack:** Swift 6, SwiftUI, AppKit, watchOS 10+, macOS 14+, Xcode asset catalogs, Node source-contract tests.

## Global Constraints

- The app icon is a white and brushed-silver UFO on graphite black.
- The menu bar and in-app glyph use a simplified monochrome UFO.
- System blue is the only brand interaction color; mint and green branding are removed.
- Existing Relay state, pairing, encryption, cloud, and Codex behavior must not change.
- Preserve the user's modified Xcode scheme and untracked workspace state.

---

### Task 1: Brand contract and reusable glyphs

**Files:**
- Modify: `apple-watch/test/project.test.mjs`
- Create: `mac/Sources/RelayMac/RelayBrand.swift`
- Create: `apple-watch/RelayWatch/RelayWatchStyle.swift`
- Modify: `mac/Sources/RelayMac/Components.swift`

**Interfaces:**
- Produces: `RelayUFOGlyph`, `RelayBrandMark`, `RelayPalette`, and `RelayWatchStyle`.
- Consumes: SwiftUI semantic foreground and background styles.

- [ ] **Step 1: Write failing brand source checks**

Add assertions that both style files exist, the Mac app uses a custom UFO menu
label, the Watch root uses `RelayWatchMark`, and Watch production sources contain
no `.mint` styling.

- [ ] **Step 2: Run the checks and confirm RED**

Run: `node --test apple-watch/test/project.test.mjs`

Expected: failure because the new brand primitives and menu label do not exist.

- [ ] **Step 3: Implement the minimal reusable glyphs and palette**

Create a SwiftUI UFO from simple capsule, ellipse, and glow shapes. Keep the Mac
glyph template-safe and expose a larger `RelayBrandMark` for headers. Replace the
mint RGB accent in `RelayPalette` with `Color.accentColor` and use semantic system
materials for panels.

- [ ] **Step 4: Run the checks and confirm GREEN**

Run: `node --test apple-watch/test/project.test.mjs`

Expected: all project contract tests pass.

### Task 2: Production app icon sources

**Files:**
- Modify: `mac/Resources/AppIconSource.png`
- Modify: `apple-watch/RelayWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- Verify: both `Contents.json` files

**Interfaces:**
- Consumes: approved generated UFO artwork.
- Produces: valid 1024-by-1024 RGB app-icon sources for packaging and Xcode.

- [ ] **Step 1: Record current asset dimensions and catalog filenames**

Run: `sips -g pixelWidth -g pixelHeight <each icon>` and inspect each
`Contents.json` filename entry.

- [ ] **Step 2: Install the approved artwork at 1024 square**

Use `sips` for a deterministic RGB 1024-by-1024 copy. Do not alter the generated
source retained by Codex.

- [ ] **Step 3: Verify both catalogs**

Run the dimension check again and `xcrun actool` indirectly through the Mac and
Watch builds.

### Task 3: Native macOS shell and menu bar

**Files:**
- Modify: `mac/Sources/RelayMac/RelayMacApp.swift`
- Modify: `mac/Sources/RelayMac/DashboardView.swift`
- Modify: `mac/Sources/RelayMac/MenuContent.swift`
- Modify: `mac/Sources/RelayMac/SetupView.swift`
- Modify: `mac/Sources/RelayMac/AboutView.swift`

**Interfaces:**
- Consumes: `RelayUFOGlyph`, `RelayBrandMark`, and semantic `RelayPalette`.
- Produces: UFO menu-bar identity and native graphite dashboard shell.

- [ ] **Step 1: Wire the custom menu-bar label**

Use the `MenuBarExtra` label closure with `RelayUFOGlyph`, an accessibility label
of `Relay`, and keep existing menu commands unchanged.

- [ ] **Step 2: Simplify the dashboard shell**

Remove the decorative detail gradient. Add the UFO beside the Relay sidebar title,
use system background/material, and show bridge health as one compact labeled row.

- [ ] **Step 3: Normalize headers and setup states**

Use native title/body hierarchy, system-blue primary actions, neutral ready checks,
and semantic warning/destructive colors. Retain every existing action and binding.

- [ ] **Step 4: Compile and run Mac tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac --scratch-path /private/tmp/relay-mac-visual-tests`

Expected: all RelayCore and RelayMac tests pass.

### Task 4: Native Apple Watch presentation

**Files:**
- Modify: `apple-watch/RelayWatch/RelayWatchRootView.swift`
- Modify: `apple-watch/RelayWatch/RelayInboxViews.swift`
- Modify: `apple-watch/RelayWatch/RelayTaskViews.swift`
- Modify: `apple-watch/RelayWatch/RelayVoiceView.swift`
- Modify only as required: remaining destination views that expose old accent styling

**Interfaces:**
- Consumes: `RelayWatchMark` and `RelayWatchStyle`.
- Produces: UFO-led pairing, neutral task surfaces, and system-blue actions.

- [ ] **Step 1: Redesign the pairing entry screen**

Place the monochrome UFO above `Pair with Mac`, shorten the instruction, keep the
six-character input and fingerprint, and use a system-blue primary action.

- [ ] **Step 2: Normalize paired destinations**

Replace mint status symbols with semantic blue or primary styling, retain orange
and red only for warning or destructive states, and preserve all navigation and
mutation guards.

- [ ] **Step 3: Run Watch source and Swift tests**

Run:

```bash
node --test apple-watch/test/project.test.mjs
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test \
  --package-path apple-watch --scratch-path /private/tmp/relay-watch-visual-tests
```

Expected: all contract and Watch tests pass.

### Task 5: Build, visual QA, and documentation

**Files:**
- Modify: `docs/TODO.md`
- Modify: `apple-watch/README.md` only if screenshots or visual wording are stale

**Interfaces:**
- Consumes: completed Mac and Watch presentation.
- Produces: build evidence and an explicit local visual test checklist.

- [ ] **Step 1: Build the exact Watch simulator destination**

Run the installed Apple Watch simulator build using a fresh derived-data directory.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Build and launch the Mac app from source**

Run the Mac build/test command, then launch `RelayMac` for menu-bar and dashboard
inspection. Confirm the UFO remains visible in light and dark menu bars.

- [ ] **Step 3: Update the solo private-beta checklist**

Add explicit checks for the app icons, Mac menu-bar UFO, dashboard layout, Watch
pairing layout, Dynamic Type, VoiceOver labels, and small-display clipping.

- [ ] **Step 4: Run the final verification matrix**

Run Mac tests, Watch tests, project checks, and both builds from clean temporary
scratch paths. Record external signing and physical-watch gates honestly.

- [ ] **Step 5: Review, commit, and push**

Inspect the diff while excluding the user's Xcode scheme/workspace changes, create
focused commits, and push `main` only after verification succeeds.
