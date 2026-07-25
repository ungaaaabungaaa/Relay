import { readFile } from "node:fs/promises";
import test from "node:test";
import assert from "node:assert/strict";

const project = await readFile(
  new URL("../RelayWatch.xcodeproj/project.pbxproj", import.meta.url),
  "utf8",
);

test("watchOS target declares local Bonjour discovery", () => {
  const declarations = project.match(
    /INFOPLIST_KEY_NSBonjourServices = "_relay-pair\._tcp";/g,
  ) ?? [];

  assert.equal(declarations.length, 2);
  assert.match(project, /INFOPLIST_KEY_NSLocalNetworkUsageDescription/);
});

test("watchOS target remains independent and watch-only", () => {
  const watchOnlyDeclarations = project.match(
    /INFOPLIST_KEY_WKWatchOnly = YES;/g,
  ) ?? [];

  assert.equal(watchOnlyDeclarations.length, 2);
  assert.match(project, /WATCHOS_DEPLOYMENT_TARGET = 10\.0;/);
});
