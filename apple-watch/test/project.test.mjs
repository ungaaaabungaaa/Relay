import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
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
const pairingView = await readFile(
  new URL("../RelayWatch/RelayPairingViews.swift", import.meta.url),
  "utf8",
);
const homeView = await readFile(
  new URL("../RelayWatch/RelayWatchHomeView.swift", import.meta.url),
  "utf8",
);
const macAppURL = new URL("../../mac/Sources/RelayMac/RelayMacApp.swift", import.meta.url);
const macBrandURL = new URL("../../mac/Sources/RelayMac/RelayBrand.swift", import.meta.url);
const macComponentsURL = new URL("../../mac/Sources/RelayMac/Components.swift", import.meta.url);
const watchStyleURL = new URL("../RelayWatch/RelayWatchStyle.swift", import.meta.url);
const sourceCheckURL = new URL("../../scripts/check-watchos-source.sh", import.meta.url);
const watchAccentURL = new URL("../RelayWatch/Assets.xcassets/AccentColor.colorset/Contents.json", import.meta.url);
const macIconURL = new URL("../../mac/Resources/AppIconSource.png", import.meta.url);
const watchIconURL = new URL("../RelayWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png", import.meta.url);

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
    "RelayWatchNavigation.swift",
    "RelayNewTaskFlow.swift",
    "RelayWatchComponents.swift",
    "RelayPairingViews.swift",
    "RelayWatchHomeView.swift",
  ]);
  assert.ok(
    !targetSourceMembership(project).includes("RelayInboxViews.swift"),
    "RelayWatch target must not retain the deleted RelayInboxViews.swift",
  );
});

test("Watch destinations use bridge data instead of preview fixtures", async () => {
  const viewSources = await Promise.all([
    "RelayWatchRootView.swift",
    "RelayPairingViews.swift",
    "RelayWatchHomeView.swift",
    "RelayApprovalView.swift",
    "RelayQuestionView.swift",
    "RelayTaskViews.swift",
    "RelayComposeViews.swift",
    "RelayNewTaskFlow.swift",
    "RelayVoiceView.swift",
  ].map((name) => readFile(new URL(`../RelayWatch/${name}`, import.meta.url), "utf8")));
  const runtimeUI = viewSources.join("\n");

  assert.doesNotMatch(runtimeUI, /git push origin main/);
  assert.doesNotMatch(runtimeUI, /Which release channel should Relay use\?/);
  assert.doesNotMatch(runtimeUI, /Relay launch readiness/);
  assert.match(runtimeUI, /approval\.command/);
  assert.match(runtimeUI, /item\.options/);
  assert.match(runtimeUI, /model\.tasks/);
  assert.match(runtimeUI, /accessibilityHint\(/);
  assert.match(homeView, /RelayStatusStrip/);
  assert.match(homeView, /NavigationLink\(value:/);
  assert.match(pairingView, /TextField\("6-character code"/);
  assert.doesNotMatch(rootView, /RelayWatchDestinationView/);
});

test("Watch destination view sources belong to the app target", () => {
  expectTargetSources([
    "RelayPairingViews.swift",
    "RelayWatchHomeView.swift",
    "RelayApprovalView.swift",
    "RelayQuestionView.swift",
    "RelayTaskViews.swift",
    "RelayComposeViews.swift",
    "RelayVoiceLifecycle.swift",
    "RelayAudioRecorder.swift",
    "RelayVoiceView.swift",
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

test("Task 1 brand primitives define semantic Apple styling", async () => {
  const [macBrand, watchStyle] = await Promise.all([
    readFile(macBrandURL, "utf8"),
    readFile(watchStyleURL, "utf8"),
  ]);

  assert.match(macBrand, /struct RelayUFOGlyph: View/);
  assert.match(macBrand, /struct RelayBrandMark: View/);
  assert.match(macBrand, /\.accessibilityLabel\("Relay"\)/);
  assert.match(macBrand, /\.foregroundStyle\(\.primary\)/);
  assert.match(macBrand, /\.fill\(\.primary\)/);
  assert.match(watchStyle, /struct RelayWatchMark: View/);
  assert.match(watchStyle, /enum RelayWatchStyle/);
  assert.match(watchStyle, /static let accent = Color\.blue/);
  assert.doesNotMatch(watchStyle, /Color\.accentColor/);
  assert.doesNotMatch(watchStyle, /\.mint/);
});

test("Task 3 wires the custom UFO label into the Mac menu bar", async () => {
  const macApp = await readFile(macAppURL, "utf8");
  assert.match(macApp, /MenuBarExtra\s*\{[\s\S]*?\}\s*label:\s*\{[\s\S]*?RelayUFOGlyph\(size: 18\)/);
  assert.match(macApp, /RelayUFOGlyph\(size: 18\)[\s\S]*?\.accessibilityLabel\("Relay"\)/);
  assert.doesNotMatch(macApp, /systemImage:\s*model\.menuBarSymbol/);
});

test("Task 1 uses RelayWatchMark in the pairing flow", () => {
  assert.match(pairingView, /RelayWatchMark/);
  assert.match(rootView, /\.tint\(RelayWatchStyle\.accent\)/);
});

test("Task 4 removes mint styling from Watch production sources", async () => {
  const sources = await Promise.all([
    "RelayWatchRootView.swift",
    "RelayPairingViews.swift",
    "RelayWatchHomeView.swift",
    "RelayApprovalView.swift",
    "RelayQuestionView.swift",
    "RelayTaskViews.swift",
    "RelayComposeViews.swift",
    "RelayVoiceView.swift",
  ].map((name) => readFile(new URL(`../RelayWatch/${name}`, import.meta.url), "utf8")));

  assert.doesNotMatch(sources.join("\n"), /\.mint/);
});

test("Task 4 compiles RelayWatchStyle in the Watch target", () => {
  expectTargetSources(["RelayWatchStyle.swift"]);
});

test("final Watch source check includes the presentation style", async () => {
  const sourceCheck = await readFile(sourceCheckURL, "utf8");

  assert.match(sourceCheck, /RelayWatchStyle\.swift/);
});

test("final Apple visual styles use system blue and semantic surfaces", async () => {
  const [components, accentAsset] = await Promise.all([
    readFile(macComponentsURL, "utf8"),
    readFile(watchAccentURL, "utf8"),
  ]);

  assert.match(components, /static let accent = Color\.blue/);
  assert.doesNotMatch(components, /Color\.accentColor/);
  assert.doesNotMatch(components, /eyebrow\.uppercased\(\)/);
  assert.doesNotMatch(components, /\.white\.opacity/);
  assert.match(components, /Color\(nsColor: \.separatorColor\)/);
  assert.match(components, /Color\(nsColor: \.controlBackgroundColor\)/);
  assert.match(accentAsset, /"red" : "0\.000"/);
  assert.match(accentAsset, /"green" : "0\.478"/);
  assert.match(accentAsset, /"blue" : "1\.000"/);
});

test("final Mac menu glyph is dimensioned for its 18-point slot", async () => {
  const [macApp, macBrand] = await Promise.all([
    readFile(macAppURL, "utf8"),
    readFile(macBrandURL, "utf8"),
  ]);

  assert.match(macBrand, /var size: CGFloat/);
  assert.match(macBrand, /\.frame\(width: size, height: size\)/);
  assert.match(macApp, /RelayUFOGlyph\(size: 18\)/);
});

test("final Mac and Watch app icon sources are identical", async () => {
  const [macIcon, watchIcon] = await Promise.all([
    readFile(macIconURL),
    readFile(watchIconURL),
  ]);

  const digest = (icon) => createHash("sha256").update(icon).digest("hex");

  assert.equal(digest(macIcon), digest(watchIcon));
});
