import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

const repoRoot = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const generatorUrl = pathToFileURL(
  join(repoRoot, "scripts", "generate-readme-screen-gallery.mjs"),
).href;

function nativeScreenNames(kotlinSource) {
  const enumBody = kotlinSource.match(
    /enum\s+class\s+Screen\s*\{([\s\S]*?)\n\}/,
  )?.[1];

  assert.ok(enumBody, "the native Screen enum should remain discoverable");

  return enumBody
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

test("generates one preview for every native Wear OS screen", async () => {
  let galleryModule;
  try {
    galleryModule = await import(generatorUrl);
  } catch (error) {
    assert.fail(`the README gallery generator should be importable: ${error}`);
  }

  const outputDir = await mkdtemp(join(tmpdir(), "relay-screen-gallery-"));

  try {
    const result = await galleryModule.generateReadmeScreenGallery({
      repoRoot,
      outputDir,
    });
    const kotlinSource = await readFile(
      join(
        repoRoot,
        "wear",
        "src",
        "main",
        "java",
        "dev",
        "ungaaaabungaaa",
        "relay",
        "domain",
        "RelayState.kt",
      ),
      "utf8",
    );
    const expectedScreens = nativeScreenNames(kotlinSource).sort();
    const renderedScreens = [];

    assert.equal(result.screenCount, 28);
    assert.equal(result.files.length, 4);

    for (const filename of result.files) {
      const svg = await readFile(join(outputDir, filename), "utf8");
      assert.match(svg, /^<svg[^>]+role="img"/);
      renderedScreens.push(
        ...Array.from(
          svg.matchAll(/data-screen="([^"]+)"/g),
          (match) => match[1],
        ),
      );
    }

    assert.deepEqual(renderedScreens.sort(), expectedScreens);
    assert.equal(new Set(renderedScreens).size, renderedScreens.length);
  } finally {
    await rm(outputDir, { recursive: true, force: true });
  }
});
