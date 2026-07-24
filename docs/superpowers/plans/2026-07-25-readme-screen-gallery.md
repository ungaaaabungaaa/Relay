# README Screen Gallery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a readable preview of every native Relay watch screen directly in the GitHub README.

**Architecture:** Keep one data-driven screen catalog in a Node.js generator. The generator validates that its catalog exactly matches the Wear OS `Screen` enum, then writes four lightweight SVG boards grouped by product flow. The README embeds those boards and links to the interactive HTML preview.

**Tech Stack:** Node.js ESM, built-in `node:test`, generated SVG, GitHub-flavored Markdown, Kotlin enum as the native screen inventory.

## Global Constraints

- Cover all 28 native Wear OS screens.
- Preserve the approved near-black, circular, icon-led Watch6 visual direction.
- Keep commands, folder names, model names, and approval consequences readable.
- Add no runtime or image-generation dependency.
- Keep the existing interactive HTML preview available.

---

### Task 1: Guard the native-to-documentation screen contract

**Files:**
- Create: `preview/test/readme-screen-gallery.test.mjs`
- Modify: `package.json`
- Test: `preview/test/readme-screen-gallery.test.mjs`

**Interfaces:**
- Consumes: `generateReadmeScreenGallery({ repoRoot, outputDir })`.
- Produces: a test that compares generated `data-screen` markers with the native Kotlin enum and checks four non-empty boards.

- [ ] **Step 1: Write the failing test**

```js
test("generates one preview for every native Wear OS screen", async () => {
  const outputDir = await mkdtemp(join(tmpdir(), "relay-screen-gallery-"));
  const result = await generateReadmeScreenGallery({ repoRoot, outputDir });
  assert.equal(result.screenCount, 28);
  assert.equal(result.files.length, 4);
});
```

- [ ] **Step 2: Run the focused test to verify RED**

Run: `node --test preview/test/readme-screen-gallery.test.mjs`

Expected: FAIL because `scripts/generate-readme-screen-gallery.mjs` does not exist.

### Task 2: Generate the four SVG screen boards

**Files:**
- Create: `scripts/generate-readme-screen-gallery.mjs`
- Create: `docs/assets/screens-connection.svg`
- Create: `docs/assets/screens-daily-control.svg`
- Create: `docs/assets/screens-new-task.svg`
- Create: `docs/assets/screens-management.svg`

**Interfaces:**
- Produces: `generateReadmeScreenGallery({ repoRoot, outputDir }) -> Promise<{ screenCount: number, files: string[] }>`
- Produces: an exported `SCREEN_GROUPS` catalog with exact native enum names.

- [ ] **Step 1: Implement the catalog validator and SVG renderer**

The generator reads `wear/src/main/java/dev/ungaaaabungaaa/relay/domain/RelayState.kt`, extracts `enum class Screen`, rejects missing, extra, or duplicate catalog entries, and renders each screen inside a circular Watch6 frame.

- [ ] **Step 2: Generate the checked-in boards**

Run: `node scripts/generate-readme-screen-gallery.mjs`

Expected: four SVG files and `Generated 28 Relay screen previews across 4 boards.`

- [ ] **Step 3: Run the focused test to verify GREEN**

Run: `node --test preview/test/readme-screen-gallery.test.mjs`

Expected: 1 test, 1 pass, 0 failures.

### Task 3: Embed and verify the gallery

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the four generated SVG boards.
- Produces: a visible README gallery with descriptive alt text and the existing interactive-preview link.

- [ ] **Step 1: Add a 28-screen gallery section to the README**

Place it after “See the UI now,” group the images by connection, daily control, new task, and management, and explain that the native Compose implementation remains the source of truth.

- [ ] **Step 2: Run repository verification**

Run: `pnpm test`

Expected: all Node tests pass, including the gallery contract.

Run: `pnpm typecheck`

Expected: exit 0.

- [ ] **Step 3: Visually inspect the generated boards**

Serve the repository locally, open each SVG in the browser, and confirm that labels, circular safe areas, and critical approval text are readable with no clipping.

- [ ] **Step 4: Commit and push**

```bash
git add README.md package.json scripts/generate-readme-screen-gallery.mjs preview/test/readme-screen-gallery.test.mjs docs/assets/screens-*.svg docs/superpowers/plans/2026-07-25-readme-screen-gallery.md
git commit -m "docs: add complete Relay screen gallery"
git push origin feat/relay-mvp
```
