import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repoRoot = dirname(dirname(dirname(fileURLToPath(import.meta.url))));

test("interactive preview exposes the secure pairing and shape controls", async () => {
  const [html, script] = await Promise.all([
    readFile(join(repoRoot, "preview", "index.html"), "utf8"),
    readFile(join(repoRoot, "preview", "app.js"), "utf8"),
  ]);
  const screens = Array.from(
    html.matchAll(/data-screen="([^"]+)"/g),
    (match) => match[1],
  );

  assert.deepEqual(screens, [
    "pairing",
    "home",
    "approval",
    "task",
    "voice",
    "new-task",
    "offline",
  ]);
  assert.match(html, /data-shape="round" aria-pressed="true"/);
  assert.match(html, /data-shape="square" aria-pressed="false"/);
  assert.match(script, /showWatchScreen\("pairing"\)/);
  assert.match(script, /SCREEN \$\{screen\.index\} \/ 07/);
});

test("Mac preview presents all nine resumable setup steps", async () => {
  const script = await readFile(join(repoRoot, "preview", "app.js"), "utf8");
  const setupPanel = script.match(
    /setup:\s*\{[\s\S]*?rows:\s*\[([\s\S]*?)\n\s*\],\n\s*action:/,
  )?.[1];

  assert.ok(setupPanel, "setup dashboard panel should be discoverable");
  assert.equal(Array.from(setupPanel.matchAll(/\["\d{2}"/g)).length, 9);
});

test("README embeds every generated Wear OS screen board", async () => {
  const readme = await readFile(join(repoRoot, "README.md"), "utf8");

  for (const filename of [
    "screens-connection.svg",
    "screens-daily-control.svg",
    "screens-new-task.svg",
    "screens-management.svg",
  ]) {
    assert.match(readme, new RegExp(`docs/assets/${filename}`));
  }
});
