import { readFile } from "node:fs/promises";
import test from "node:test";
import assert from "node:assert/strict";

const project = await readFile(
  new URL("../RelayWatch.xcodeproj/project.pbxproj", import.meta.url),
  "utf8",
);
const apiClient = await readFile(
  new URL("../RelayWatch/RelayAPIClient.swift", import.meta.url),
  "utf8",
);

test("watchOS target uses Relay Cloud without Bonjour permissions", () => {
  assert.doesNotMatch(project, /NSBonjourServices|_relay-pair\._tcp/);
  assert.doesNotMatch(project, /NSLocalNetworkUsageDescription/);
  assert.doesNotMatch(project, /RelayPairingDiscovery\.swift/);
  assert.equal(
    project.match(/PRODUCT_BUNDLE_IDENTIFIER = com\.relayforcodex\.watch;/g)
      ?.length,
    2,
  );
});

test("watchOS target remains independent and watch-only", () => {
  const watchOnlyDeclarations = project.match(
    /INFOPLIST_KEY_WKWatchOnly = YES;/g,
  ) ?? [];

  assert.equal(watchOnlyDeclarations.length, 2);
  assert.match(project, /WATCHOS_DEPLOYMENT_TARGET = 10\.0;/);
});

test("Apple Watch sends Cloud envelopes as supported WebSocket text frames", () => {
  assert.match(apiClient, /activeSocket\.send\([\s\S]*?\.string\(/);
  assert.doesNotMatch(apiClient, /activeSocket\.send\(\s*\.data\(/);
});
