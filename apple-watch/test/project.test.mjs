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
const relaySocket = await readFile(
  new URL("../RelayWatch/RelaySocket.swift", import.meta.url),
  "utf8",
);
const rootView = await readFile(
  new URL("../RelayWatch/RelayWatchRootView.swift", import.meta.url),
  "utf8",
);

function expectTargetSources(names, contents = project) {
  const sourceMembership = targetSourceMembership(contents);
  for (const name of names) {
    assert.ok(
      sourceMembership.includes(name),
      `RelayWatch target must include ${name}`,
    );
  }
}

function targetSourceMembership(contents) {
  const target = contents.match(
    /E00000000000000000000001 \/\* RelayWatch \*\/ = \{\s*isa = PBXNativeTarget;([\s\S]*?)\n\t\t\};/,
  );
  assert.ok(target, "RelayWatch target must exist");
  const sourcePhaseID = target[1].match(
    /\b([A-F0-9]{24}) \/\* Sources \*\//,
  )?.[1];
  assert.ok(sourcePhaseID, "RelayWatch target must reference a Sources build phase");

  const sourcePhase = contents.match(
    new RegExp(
      `${sourcePhaseID} /\\* Sources \\*/ = \\{\\s*isa = PBXSourcesBuildPhase;[\\s\\S]*?files = \\(\\n([\\s\\S]*?)\\n\\t\\t\\t\\);`,
    ),
  );
  assert.ok(sourcePhase, "RelayWatch Sources build phase must exist");

  return [...sourcePhase[1].matchAll(/^\s*([A-F0-9]{24}) \/\* .+ in Sources \*\/,?$/gm)]
    .map((match) => match[1])
    .map((buildFileID) => {
      const buildFile = contents.match(
        new RegExp(
          `${buildFileID} /\\* ([^*]+) in Sources \\*/ = \\{isa = PBXBuildFile;`,
        ),
      );
      assert.ok(buildFile, `Sources build file ${buildFileID} must exist`);
      return buildFile[1];
    });
}

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
  assert.match(relaySocket, /task\.send\(\.string\(/);
  assert.doesNotMatch(relaySocket, /task\.send\(\s*\.data\(/);
  assert.match(apiClient, /private var pending: \[String: PendingRequest\]/);
  assert.match(apiClient, /private var outboundQueue: \[OutboundBatch\]/);
});

test("Watch runtime contract sources belong to the app target", () => {
  expectTargetSources([
    "RelayEndpoint.swift",
    "RelayEnvironment.swift",
    "RelayReconnectPolicy.swift",
    "RelayPairingState.swift",
    "RelaySocket.swift",
    "RelayWatchFeature.swift",
    "RelayWatchService.swift",
    "RelayWatchTypes.swift",
  ]);
});

test("Watch destinations use bridge data instead of preview fixtures", async () => {
  const viewSources = await Promise.all([
    "RelayWatchRootView.swift",
    "RelayInboxViews.swift",
    "RelayApprovalView.swift",
    "RelayQuestionView.swift",
    "RelayTaskViews.swift",
    "RelayComposeViews.swift",
  ].map((name) => readFile(new URL(`../RelayWatch/${name}`, import.meta.url), "utf8")));
  const runtimeUI = viewSources.join("\n");

  assert.doesNotMatch(runtimeUI, /git push origin main/);
  assert.doesNotMatch(runtimeUI, /Which release channel should Relay use\?/);
  assert.doesNotMatch(runtimeUI, /Relay launch readiness/);
  assert.match(runtimeUI, /approval\.command/);
  assert.match(runtimeUI, /item\.options/);
  assert.match(runtimeUI, /model\.tasks/);
  assert.match(runtimeUI, /accessibilityHint\(/);
  assert.doesNotMatch(rootView, /RelayWatchDestinationView/);
});

test("Watch destination view sources belong to the app target", () => {
  expectTargetSources([
    "RelayInboxViews.swift",
    "RelayApprovalView.swift",
    "RelayQuestionView.swift",
    "RelayTaskViews.swift",
    "RelayComposeViews.swift",
  ]);
});

test("Watch runtime contract sources must be connected to the Sources build phase", () => {
  const missingEndpointMembership = project.replace(
    "\n\t\t\t\tA00000000000000000000009 /* RelayEndpoint.swift in Sources */,",
    "",
  );

  assert.throws(() => {
    expectTargetSources(["RelayEndpoint.swift"], missingEndpointMembership);
  }, /RelayWatch target must include RelayEndpoint.swift/);
});
