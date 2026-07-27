# Relay Borderless App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the glossy outer-border shine from the shared Relay Mac and Watch application icon while preserving the UFO artwork.

**Architecture:** Replace both identical 1024 by 1024 sRGB PNG sources with the approved matte-edge edit. Leave the adaptive menu-bar SVG and all application behavior unchanged.

**Tech Stack:** PNG assets, Asset Catalog, `sips`, Node test runner, macOS `actool` packaging.

## Global Constraints

- Preserve the UFO, beam, black background, rounded-square silhouette, position, and scale.
- Remove only the bright application-tile perimeter highlight.
- Keep the Mac and Watch icon sources byte-identical, 1024 by 1024, and opaque.
- Do not stage the user's Xcode scheme or workspace changes.

---

### Task 1: Replace and verify the shared application icon

**Files:**
- Modify: `mac/Resources/AppIconSource.png`
- Modify: `apple-watch/RelayWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- Modify: `apple-watch/test/project.test.mjs`

**Interfaces:**
- Produces: byte-identical 1024 by 1024 PNG sources for Mac packaging and the Watch asset catalog.

- [x] **Step 1: Create a matte-edge edit from the approved icon**

Remove the glossy silver perimeter without changing the central UFO artwork.

- [x] **Step 2: Replace both shared source images**

Write the normalized 1024 by 1024 sRGB output to both icon source paths.

- [x] **Step 3: Strengthen the shared-icon contract**

Assert both files are byte-identical PNGs with a width and height of 1024.

- [x] **Step 4: Run automated verification**

Run the focused project tests, complete Mac tests, and full repository tests.

- [x] **Step 5: Package and visually inspect**

Rebuild and install `/Applications/Relay.app`, then confirm the real app icon has a matte outer edge and Relay still owns zero normal windows.

- [x] **Step 6: Commit and push**

Stage only the spec, plan, two PNG sources, and icon contract test. Commit with `fix(brand): remove app icon border shine` and push `main` to `origin`.
