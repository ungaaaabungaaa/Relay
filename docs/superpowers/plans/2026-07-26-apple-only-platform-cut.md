# Apple-Only Platform Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Relay's Android and Wear OS product surfaces while keeping the macOS app, Apple Watch app, Relay Cloud, Mac bridge, and shared encrypted protocol.

**Architecture:** Apple Watch sends signed requests inside encrypted WebSocket envelopes through Relay Cloud to the outbound Mac tunnel and loopback bridge. GitHub releases carry the Mac DMG and source material; Apple distributes the independent watchOS app through TestFlight and the App Store.

**Tech Stack:** Swift 6, SwiftUI, watchOS 10+, macOS 14+, TypeScript, Node 24, pnpm 11, Cloudflare Worker/D1/Durable Objects, GitHub Actions, Sparkle 2, Xcode.

## Global Constraints

- Support Apple-silicon Macs running macOS 14 or newer.
- Support the independent Apple Watch app on watchOS 10 or newer.
- Keep `apple-watch/`, `mac/`, `apps/bridge/`, `apps/cloud/`, and shared packages.
- Keep Relay Cloud and the Mac bridge because the Apple Watch client uses both.
- Do not create an iPhone companion app.
- Do not add a data migration; the user confirmed that Relay has no users or production setup.
- Use signed release-manifest schema version 2 for Mac artifacts only.
- Distribute the Apple Watch app through TestFlight and the App Store, outside the GitHub DMG release.
- Describe unfinished Apple Watch destination actions and physical testing without beta-ready claims.
- Leave pnpm-owned optional cross-platform records in `pnpm-lock.yaml` intact.
- Do not rewrite Git history or delete any local SDK outside the repository.
- Push with a normal fast-forward update to `origin/main`; never force-push.

## File Responsibility Map

- `apple-watch/RelayWatch/RelayProtocol.swift` defines Apple Watch device metadata and the encrypted pairing/tunnel protocol.
- `apple-watch/Tests/WatchIdentityTests.swift` protects Apple Watch key encoding, pairing vectors, envelope authentication, and replay behavior.
- `apps/bridge/src/security/store.ts`, `pairing-session.ts`, and `apps/bridge/src/admin/admin-server.ts` define and validate the device metadata accepted by the Mac bridge.
- `release/release-manifest.schema.json`, `scripts/create-release-manifest.mjs`, and `scripts/verify-release.mjs` define the signed GitHub release contract.
- `mac/Sources/RelayCore/ReleaseClient.swift` verifies the same release contract inside the Mac app.
- `.github/workflows/quality.yml` verifies Node, Mac, bridge, and Apple Watch code.
- `.github/workflows/release.yml` signs, notarizes, verifies, and publishes Mac releases.
- `README.md`, `apple-watch/README.md`, and `docs/*.md` describe the active Apple-only product and its external release gates.

---

### Task 1: Make the shared device contract Apple Watch-only

**Files:**

- Modify: `apple-watch/RelayWatch/RelayProtocol.swift`
- Modify: `apple-watch/Tests/WatchIdentityTests.swift`
- Modify: `apps/bridge/src/security/store.ts`
- Modify: `apps/bridge/src/security/pairing-session.ts`
- Modify: `apps/bridge/src/admin/admin-server.ts`
- Modify fixtures: `apps/bridge/test/admin-server.test.ts`
- Modify fixtures: `apps/bridge/test/authentication.test.ts`
- Modify fixtures: `apps/bridge/test/bridge-cloud-runtime.test.ts`
- Modify fixtures: `apps/bridge/test/pairing.test.ts`
- Modify fixtures: `apps/bridge/test/pairing-session.test.ts`
- Modify fixtures: `apps/bridge/test/pairing-session-routes.test.ts`
- Modify fixtures: `apps/bridge/test/sqlite-pairing-store.test.ts`
- Modify fixtures: `apps/cloud/test/d1-auth-pairing.test.ts`
- Modify fixtures: `apps/cloud/test/d1-worker-flow.test.ts`
- Modify fixtures: `apps/cloud/test/service.test.ts`
- Modify fixtures: `mac/Tests/RelayCoreTests/AdminClientTests.swift`
- Modify fixtures: `mac/Tests/RelayCoreTests/RelayCloudCryptoTests.swift`
- Modify fixtures: `mac/Tests/RelayCoreTests/RelayCloudHostKeysTests.swift`
- Modify fixtures: `mac/Tests/RelayCoreTests/RelayCloudTunnelTests.swift`

**Interfaces:**

- Consumes: existing `RelayDeviceMetadata`, `DeviceMetadata`, `PairingSessionService`, and `relayOpenPairingPayload` interfaces.
- Produces: `DeviceMetadata` with `platform: "watch-os"` and `screenShape: "rounded-rect"`; Apple Watch pairing metadata accepted by the bridge; Apple-side coverage for the shared encrypted completion vector.

- [ ] **Step 1: Change the tests to the Apple Watch metadata contract and port the shared pairing vector**

Add these tests to `apple-watch/Tests/WatchIdentityTests.swift`:

```swift
@Test
func watchMetadataUsesWatchOSAndRoundedRectangle() throws {
    let data = try JSONEncoder().encode(
        RelayDeviceMetadata(
            model: "Apple Watch",
            osVersion: "10",
            appVersion: "0.2.0"
        )
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: String]
    )

    #expect(object["platform"] == "watch-os")
    #expect(object["manufacturer"] == "Apple")
    #expect(object["model"] == "Apple Watch")
    #expect(object["screenShape"] == "rounded-rect")
}

@Test
func pairingCompletionOpensTheSharedEncryptedFixture() throws {
    let payload = RelayCloudPairingPayloadEnvelope(
        version: 1,
        nonce: "BwcHBwcHBwcHBwcH",
        ciphertext: "Ipns_AseincDozOvrOAShV5XcyT0IcNnsqx5_4ACyn1hheZdO2yVENqvqHewusDboJLNJrXksCO4QF2L4ULZIrO0xtPQeZir4ejLnlNgyks06MUKP96sllHjC0kg-fTFUR69DnmQGHBd2uOniuIBj7C4Tu6AvsVnfqTYcO6xXJx855wfqzOAhKkTq1GUsQywQ5spui_x5IOsMHC3maU24urmS2n5eMw"
    )
    let credential = try relayOpenPairingPayload(
        payload,
        requestID: "request-1",
        hostID: "host-1",
        rootKey: SymmetricKey(data: Data(repeating: 9, count: 32))
    )

    #expect(credential.deviceId == "watch-1")
    #expect(credential.credential == "watch-secret")
}
```

Change the `metadata` fixture at the top of `apps/bridge/test/pairing-session.test.ts` to:

```ts
const metadata = {
  platform: "watch-os",
  manufacturer: "Apple",
  model: "Apple Watch",
  osVersion: "10",
  appVersion: "0.2.0",
  screenShape: "rounded-rect",
} as const;
```

- [ ] **Step 2: Run the changed tests and confirm the old contract rejects them**

Run:

```bash
swift test --package-path apple-watch
node --test apps/bridge/test/pairing-session.test.ts
```

Expected: the Swift metadata test reports `round` instead of `rounded-rect`, and the bridge pairing test rejects the new shape or fails the current TypeScript shape contract. The encrypted fixture test must pass, proving the vector works before deleting its Kotlin copy.

- [ ] **Step 3: Implement the Apple Watch metadata contract**

Change `RelayDeviceMetadata.screenShape` in `apple-watch/RelayWatch/RelayProtocol.swift`:

```swift
struct RelayDeviceMetadata: Encodable, Sendable {
    let platform = "watch-os"
    let manufacturer = "Apple"
    let model: String
    let osVersion: String
    let appVersion: String
    let screenShape = "rounded-rect"
}
```

Change `DeviceMetadata` in `apps/bridge/src/security/store.ts`:

```ts
export type DeviceMetadata = {
  platform: "watch-os";
  manufacturer: string;
  model: string;
  osVersion: string;
  appVersion: string;
  screenShape: "rounded-rect";
};
```

Change both validators to require the same exact values:

```ts
metadata.platform === "watch-os" &&
metadata.screenShape === "rounded-rect"
```

Use the Apple fixture values from Step 1 in every listed bridge, cloud, and Mac test. Keep generic IDs such as `watch-1`. Rename the authentication test to `accepts CryptoKit-compatible P-256 signatures` without changing its cryptographic assertion.

- [ ] **Step 4: Run the device, cloud, and Swift test groups**

Run:

```bash
node --test \
  apps/bridge/test/admin-server.test.ts \
  apps/bridge/test/authentication.test.ts \
  apps/bridge/test/bridge-cloud-runtime.test.ts \
  apps/bridge/test/pairing.test.ts \
  apps/bridge/test/pairing-session.test.ts \
  apps/bridge/test/pairing-session-routes.test.ts \
  apps/bridge/test/sqlite-pairing-store.test.ts \
  apps/cloud/test/d1-auth-pairing.test.ts \
  apps/cloud/test/d1-worker-flow.test.ts \
  apps/cloud/test/service.test.ts
swift test --package-path apple-watch
swift test --package-path mac
pnpm typecheck
```

Expected: every command exits 0. Apple and bridge tests agree on `watch-os` and `rounded-rect`; shared fixtures contain Apple device metadata.

- [ ] **Step 5: Commit the device contract**

```bash
git add apple-watch apps/bridge apps/cloud/test mac/Tests
git commit -m "refactor: make device pairing Apple Watch-only"
```

---

### Task 2: Delete the Android client, toolchain, preview, and quality job

**Files:**

- Delete directory: `wear/`
- Delete: `build.gradle.kts`
- Delete: `settings.gradle.kts`
- Delete: `gradle.properties`
- Delete directory: `gradle/`
- Delete: `gradlew`
- Delete: `gradlew.bat`
- Delete directory: `preview/`
- Delete: `scripts/generate-readme-screen-gallery.mjs`
- Delete: `scripts/scan-apk-secrets.mjs`
- Delete: `docs/assets/screens-connection.svg`
- Delete: `docs/assets/screens-daily-control.svg`
- Delete: `docs/assets/screens-new-task.svg`
- Delete: `docs/assets/screens-management.svg`
- Modify: `.gitignore`
- Modify: `package.json`
- Modify: `scripts/check-types.mjs`
- Modify: `.github/workflows/quality.yml`
- Modify and test: `release/test/permanent-identifiers.test.mjs`

**Interfaces:**

- Consumes: Apple Watch bundle ID `com.relayforcodex.watch`, Mac bundle ID `com.relayforcodex.mac`, and existing Node/Swift quality commands.
- Produces: an Apple-only source tree and quality workflow with no Java, Gradle, SDK, APK, preview, or Wear job.

- [ ] **Step 1: Retarget the permanent-identifier test and make deletion observable**

Replace `release/test/permanent-identifiers.test.mjs` with:

```js
import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

test("consumer builds use permanent Apple product identifiers", async () => {
  const [watchProject, macPackaging] = await Promise.all([
    readFile(
      new URL("../../apple-watch/RelayWatch.xcodeproj/project.pbxproj", import.meta.url),
      "utf8",
    ),
    readFile(new URL("../../scripts/package-mac-app.sh", import.meta.url), "utf8"),
  ]);

  assert.match(watchProject, /PRODUCT_BUNDLE_IDENTIFIER = com\.relayforcodex\.watch;/);
  assert.match(watchProject, /WATCHOS_DEPLOYMENT_TARGET = 10\.0;/);
  assert.match(macPackaging, /com\.relayforcodex\.mac/);
  assert.doesNotMatch(macPackaging, /NSBonjourServices/);
  assert.doesNotMatch(macPackaging, /NSLocalNetworkUsageDescription/);

  for (const path of ["../../wear", "../../gradle", "../../gradlew", "../../preview"]) {
    await assert.rejects(access(new URL(path, import.meta.url)), { code: "ENOENT" });
  }
});
```

- [ ] **Step 2: Run the identifier test and confirm the old paths make it fail**

Run: `node --test release/test/permanent-identifiers.test.mjs`

Expected: FAIL because one of `wear`, `gradle`, `gradlew`, or `preview` still exists.

- [ ] **Step 3: Delete the Android and preview paths with `apply_patch`**

Delete every path listed in this task. Do not delete `apple-watch/`, `mac/`, `apps/bridge/`, `apps/cloud/`, `packages/cloud-protocol/`, or `packages/codex-protocol/`.

Remove these ignore patterns from `.gitignore`:

```gitignore
.gradle/
local.properties
*.jks
*.keystore
```

Keep `**/build/` and `**/.build/` because Swift and Xcode use them.

- [ ] **Step 4: Remove deleted scripts from the Node and type-check configuration**

Make the `package.json` scripts block contain:

```json
"scripts": {
  "generate:codex": "node scripts/generate-codex-protocol.mjs",
  "build:bridge-sea": "node scripts/build-bridge-sea.mjs",
  "smoke:bridge-sea": "node scripts/smoke-bridge-sea.mjs",
  "test": "node --test packages/*/test/*.test.ts apps/*/test/*.test.ts release/test/*.test.mjs apple-watch/test/*.test.mjs",
  "test:protocol": "node --test packages/codex-protocol/test/*.test.ts",
  "test:release": "node --test release/test/*.test.mjs",
  "typecheck": "node scripts/check-types.mjs"
}
```

Remove `".gradle"` from the directory exclusion list in `scripts/check-types.mjs`.

- [ ] **Step 5: Make the quality workflow Apple-only**

Delete the entire `wear` job from `.github/workflows/quality.yml`. Rename the `apple-silicon` job display name to `Apple platforms`. Replace the Apple Watch step with:

```yaml
- name: Test and build Apple Watch
  run: |
    swift test --package-path apple-watch
    scripts/check-watchos-source.sh
    xcodebuild \
      -project apple-watch/RelayWatch.xcodeproj \
      -scheme RelayWatch \
      -configuration Release \
      -destination 'generic/platform=watchOS' \
      -derivedDataPath "${RUNNER_TEMP}/relay-watch-derived-data" \
      CODE_SIGNING_ALLOWED=NO \
      build
```

- [ ] **Step 6: Verify the source-tree cut**

Run:

```bash
node --test release/test/permanent-identifiers.test.mjs
pnpm test
pnpm typecheck
git diff --check
```

Expected: all commands exit 0. The Node suite no longer tries to load `preview/test`, and the identifier test confirms that Android source/build roots are absent.

- [ ] **Step 7: Commit the source and toolchain deletion**

```bash
git add -A
git commit -m "refactor: remove Android client and toolchain"
```

---

### Task 3: Convert releases and Mac update verification to schema version 2

**Files:**

- Modify and test: `release/test/release-verifier.test.mjs`
- Modify: `release/release-manifest.schema.json`
- Modify: `release/bundled-metadata.json`
- Modify: `scripts/create-release-manifest.mjs`
- Modify: `scripts/verify-release.mjs`
- Modify: `scripts/package-mac-app.sh`
- Modify: `mac/Sources/RelayCore/BundledReleaseMetadata.swift`
- Modify: `mac/Sources/RelayCore/ReleaseClient.swift`
- Modify and test: `mac/Tests/RelayCoreTests/ReleaseClientTests.swift`
- Modify: `.github/workflows/release.yml`
- Modify: `docs/RELEASE.md` in Task 5, not in this task.

**Interfaces:**

- Consumes: `ReleaseMac`, `CodexCompatibility`, `ReleaseArtifact`, Ed25519 manifest signatures, Sparkle, and the notarized `Relay.dmg`.
- Produces: `ReleaseManifestPayload` schema version 2 with `mac`, `codex`, and `artifacts`; bundled metadata containing `version` and `apiVersion`; a Mac-only release workflow.

- [ ] **Step 1: Rewrite Node release fixtures for the Mac-only schema**

Use this payload shape in `release/test/release-verifier.test.mjs`:

```js
const payload = {
  schemaVersion: 2,
  tag: TAG,
  version: VERSION,
  license: "Apache-2.0",
  mac: {
    version: VERSION,
    artifact: "Relay.dmg",
    architecture: "arm64",
  },
  codex: {
    minimumVersion: "0.144.0",
    maximumVersion: "0.144.x",
  },
  artifacts,
};
```

Use exactly these fixture files:

```js
const files = new Map([
  ["Relay.dmg", "arm64 mac image"],
  [`Relay-${VERSION}.tar.gz`, "source archive"],
  ["LICENSE", "Apache License Version 2.0"],
  ["NOTICE", "Relay notices"],
  ["THIRD_PARTY_NOTICES.md", "Third-party notices"],
  ["COMPATIBILITY.md", "Compatibility matrix"],
]);
```

Delete assertions and mutation tests tied to a watch package. Add a test that signs `schemaVersion: 1` and expects `verifyRelease` to reject it with `unsupported release schema version`.

- [ ] **Step 2: Rewrite Swift release fixtures before changing production types**

Change bundled metadata tests to decode:

```swift
let data = Data(#"{"version":"0.2.0-beta.1","apiVersion":1}"#.utf8)
let metadata = try BundledReleaseMetadata.decode(data)
#expect(metadata.version == "0.2.0-beta.1")
#expect(metadata.apiVersion == 1)
```

Construct `ReleaseManifestPayload` with:

```swift
let payload = ReleaseManifestPayload(
    schemaVersion: 2,
    tag: "v1.1.0",
    version: "1.1.0",
    license: "Apache-2.0",
    mac: ReleaseMac(
        version: "1.1.0",
        artifact: "Relay.dmg",
        architecture: "arm64"
    ),
    codex: CodexCompatibility(
        minimumVersion: "0.144.0",
        maximumVersion: "0.144.x"
    ),
    artifacts: [
        ReleaseArtifact(
            name: "Relay.dmg",
            version: "1.1.0",
            architecture: "arm64",
            sha256: String(repeating: "a", count: 64),
            signed: true
        )
    ]
)
```

Delete every `ReleaseWatch`, `watchVersionCode`, watch artifact, and minimum operating-system argument from the Swift tests.

Add an explicit schema rejection after the valid payload assertion:

```swift
var legacyPayload = payload
legacyPayload.schemaVersion = 1
let legacySignature = try signingKey.signature(
    for: ReleaseClient.signingData(for: legacyPayload)
)
let legacyManifest = SignedReleaseManifest(
    payload: legacyPayload,
    signature: legacySignature.base64EncodedString()
)
#expect(throws: ReleaseClientError.invalidManifest) {
    try client.verifyManifest(
        JSONEncoder().encode(legacyManifest),
        currentVersion: "1.0.0"
    )
}
```

- [ ] **Step 3: Run the rewritten release tests and confirm production code still has the old contract**

Run:

```bash
pnpm test:release
swift test --package-path mac
```

Expected: compilation or assertion failures reference schema version 1, `ReleaseWatch`, `watchVersionCode`, or the removed watch artifact.

- [ ] **Step 4: Implement release schema version 2 in Node**

In `scripts/create-release-manifest.mjs`, remove `watchVersionCode` and create only six artifacts: `Relay.dmg`, the source archive, `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, and `COMPATIBILITY.md`. Return `schemaVersion: 2` with `mac`, `codex`, and `artifacts`.

In `scripts/verify-release.mjs`:

- remove `spawnSync`, `verifyApkSignature`, and signature-tool verification;
- require `payload.schemaVersion === 2`, with a dedicated `unsupported release schema version` error;
- require the same six artifacts and their existing architecture/signature properties;
- retain tag, license, Codex range, digest, signature, downgrade, and arm64 checks.

In `release/release-manifest.schema.json`, remove the `watch` definition/property, set `schemaVersion` to 2, set `artifacts.minItems` to 6, and remove `universal` from the architecture enum.

- [ ] **Step 5: Implement release schema version 2 in Swift and Mac packaging**

Make `BundledReleaseMetadata` contain:

```swift
public struct BundledReleaseMetadata: Codable, Equatable, Sendable {
    public var version: String
    public var apiVersion: Int

    public static func decode(_ data: Data) throws -> BundledReleaseMetadata {
        guard
            let metadata = try? JSONDecoder().decode(Self.self, from: data),
            !metadata.version.isEmpty,
            metadata.apiVersion == 1
        else {
            throw BundledReleaseMetadataError.invalid
        }
        return metadata
    }
}
```

Delete `ReleaseWatch` and the `watch` property/initializer argument from `ReleaseManifestPayload`. Require schema version 2 and a signed arm64 `Relay.dmg` in `ReleaseClient.verifyManifest` while retaining all signature, digest, version, and rollback checks.

Write bundled metadata in `scripts/package-mac-app.sh` with:

```zsh
printf '{"version":"%s","apiVersion":1}\n' \
  "${relay_version}" \
  > "${resources_path}/relay-release.json"
```

Set `release/bundled-metadata.json` to:

```json
{
  "version": "0.2.0-beta.1",
  "apiVersion": 1
}
```

- [ ] **Step 6: Make the release workflow Mac-only and keep Apple Watch as a source/build gate**

Remove from `.github/workflows/release.yml`:

- all watch version and keystore environment inputs;
- Java and SDK setup;
- keystore import/export and cleanup;
- Gradle tests and package assembly;
- signature scanning and watch artifact checksum/upload;
- the `--watch-version-code` and package-signature verifier arguments.

Change the toolchain step to install pnpm only. Add the same unsigned generic watchOS `xcodebuild` command from Task 2 to `Run all automated release gates`. Keep Apple certificate import, bridge build/smoke test, DMG packaging, notarization, manifest signing, checksums, Sparkle feeds, GitHub Release upload, and Pages deployment.

- [ ] **Step 7: Verify both release implementations**

Run:

```bash
pnpm test:release
swift test --package-path mac
pnpm typecheck
git diff --check
```

Expected: every command exits 0. Node and Swift accept signed schema version 2 manifests, reject version 1, and require no watch package or watch version field.

- [ ] **Step 8: Commit the release migration**

```bash
git add release scripts/create-release-manifest.mjs scripts/verify-release.mjs scripts/package-mac-app.sh mac/Sources/RelayCore mac/Tests/RelayCoreTests/ReleaseClientTests.swift .github/workflows/release.yml
git commit -m "refactor: make releases Apple-only"
```

---

### Task 4: Align the Mac app and Apple Watch guide with the supported platforms

**Files:**

- Modify and test: `mac/Tests/RelayCoreTests/SetupJourneyTests.swift`
- Modify: `mac/Sources/RelayCore/SetupState.swift`
- Modify: `mac/Sources/RelayMac/AboutView.swift`
- Modify: `mac/Sources/RelayMac/SetupView.swift`
- Modify: `mac/Sources/RelayMac/UpdatesView.swift`
- Modify: `mac/Sources/RelayMac/VoiceView.swift`
- Modify: `mac/Sources/RelayMac/WatchesView.swift`
- Modify: `apple-watch/README.md`

**Interfaces:**

- Consumes: the existing six-step `SetupJourney`, independent watchOS bundle, Relay Cloud pairing code, Sparkle, and App Store distribution boundary.
- Produces: Mac product copy that points users to Apple Watch and an Apple Watch guide that treats watchOS as the sole watch client.

- [ ] **Step 1: Add a failing setup-copy assertion**

Add to `mac/Tests/RelayCoreTests/SetupJourneyTests.swift`:

```swift
@Test
func watchPairingStepUsesAppleDistribution() throws {
    let step = try #require(
        SetupJourney.complete.steps.first(where: { $0.id == .watchPairing })
    )

    #expect(step.detail.contains("Apple Watch"))
    #expect(step.detail.contains("TestFlight or the App Store"))
}
```

- [ ] **Step 2: Run the setup test and confirm the current store copy fails**

Run: `swift test --package-path mac`

Expected: FAIL because the current detail names the old store.

- [ ] **Step 3: Replace Mac copy with the exact Apple-only messages**

Use these messages:

| File | Replacement copy |
| --- | --- |
| `SetupState.swift` | `Install Relay on your Apple Watch from TestFlight or the App Store, enter the code, and compare fingerprints.` |
| `SetupView.swift` | `Install Relay on your Apple Watch, open Watches, and enter the six-character code.` |
| `AboutView.swift` | `Built for Apple Watch` and `Relay Cloud routes only encrypted task data` |
| `WatchesView.swift` | `Install Relay on Apple Watch` and `Use TestFlight during development and the App Store after release. Relay needs no VPN or port forwarding.` |
| `UpdatesView.swift` | `Sparkle updates the Mac app. TestFlight or the App Store updates the Apple Watch app.` and `Apple silicon · watchOS 10+` |
| `UpdatesView.swift` rollback panel | `A failed or older Mac download never replaces the working app. Apple manages signed Apple Watch updates.` |
| `VoiceView.swift` | `Apple Watch text input needs no key. Custom hold-to-record uses an OpenAI key stored only in macOS Keychain.` |

Do not claim an App Store release exists. Keep TestFlight and signed distribution described as external gates.

- [ ] **Step 4: Promote the Apple Watch README from a later phase to the only watch app**

Start `apple-watch/README.md` with:

```markdown
# Relay for Apple Watch

Relay for Apple Watch is the project's independent watchOS 10+ client. It pairs
directly with Relay Cloud and a Relay Mac; Relay has no separate iPhone
companion target in this repository.
```

Keep the implemented pairing/encryption inventory. Keep the unfinished screen,
event, voice, physical-device, signing, and TestFlight limitations. Remove phase
numbering and any comparison with a prior watch platform.

- [ ] **Step 5: Verify Mac behavior and scan shipped UI copy**

Run:

```bash
swift test --package-path mac
swift build --package-path mac --configuration release --arch arm64
swift test --package-path apple-watch
rg -n -i 'google play|wear[ -]?os|galaxy watch|watch6|\badb\b|\bapk\b' mac apple-watch
```

Expected: all Swift commands exit 0 and `rg` returns no matches.

- [ ] **Step 6: Commit the product-copy migration**

```bash
git add mac apple-watch/README.md
git commit -m "docs: make Apple Watch the sole watch client"
```

---

### Task 5: Replace active documentation and store material

**Files:**

- Rewrite: `README.md`
- Rewrite: `docs/SETUP.md`
- Rewrite: `docs/COMPATIBILITY.md`
- Delete: `docs/PHYSICAL-WATCH-TEST.md`
- Create: `docs/PHYSICAL-APPLE-WATCH-TEST.md`
- Rewrite: `docs/SECURITY.md`
- Rewrite: `docs/RELEASE.md`
- Rewrite: `docs/TODO.md`
- Keep: `docs/CLOUD-OPERATIONS.md`
- Delete: `docs/assets/relay-watch-flow.svg`
- Delete: `docs/store/PLAY-STORE-LISTING.md`
- Delete: `docs/store/REVIEWER-INSTRUCTIONS.md`
- Create: `docs/store/APP-STORE-LISTING.md`
- Create: `docs/store/APP-STORE-REVIEWER-INSTRUCTIONS.md`
- Update: `docs/store/PRIVACY-POLICY.md`
- Update: `docs/store/SUPPORT.md`
- Update: `docs/store/TERMS.md`
- Rewrite: `NOTICE`
- Rewrite: `THIRD_PARTY_NOTICES.md`
- Delete: `docs/superpowers/specs/2026-07-22-relay-design.md`
- Delete: `docs/superpowers/specs/2026-07-25-relay-public-release-design.md`
- Delete: `docs/superpowers/plans/2026-07-24-relay-mvp.md`
- Delete: `docs/superpowers/plans/2026-07-25-readme-screen-gallery.md`
- Delete: `docs/superpowers/plans/2026-07-25-relay-public-release.md`
- Keep until Task 6: `docs/superpowers/specs/2026-07-26-apple-only-platform-design.md`
- Keep until Task 6: `docs/superpowers/plans/2026-07-26-apple-only-platform-cut.md`

**Interfaces:**

- Consumes: implemented Mac/cloud/watch pairing facts, watchOS limitations, Mac schema version 2 release flow, and external Apple signing/TestFlight gates.
- Produces: one consistent Apple-only setup, compatibility, security, release, test, legal, and store story.

- [ ] **Step 1: Rewrite the README around the Apple Watch data path**

Use this opening:

```markdown
# Relay

Relay lets an Apple Watch review and control Codex tasks running on an
Apple-silicon Mac. Relay Cloud routes end-to-end encrypted envelopes between
the approved watch and Mac; it cannot decrypt task content.
```

The README must contain these sections and facts:

- `Current checkpoint`: pairing, Keychain identities, encrypted request tunnel, and unfinished destination actions/physical distribution.
- `What is implemented`: separate Apple Watch, Mac, and Relay Cloud subsections.
- `Architecture`: Apple Watch to Relay Cloud to Mac tunnel to loopback bridge to Codex.
- `Start here`: links to setup, compatibility, security, Apple Watch physical test, release gates, maintainer release guide, cloud operations, and `apple-watch/README.md`.
- `Developer quick start`: pnpm, bridge, Mac Swift, Apple Watch Swift, source check, and unsigned generic `xcodebuild` commands only.
- `License`: Apache 2.0, notice, and third-party notices.

Delete the browser-preview section, generated screen gallery, and all unsupported setup claims.

- [ ] **Step 2: Rewrite setup, compatibility, and physical testing**

`docs/SETUP.md` must require an Apple-silicon Mac on macOS 14+, Codex, a Relay invite, an Apple Watch on watchOS 10+, and an awake/online Mac. The user flow must name TestFlight or App Store distribution without claiming either is live. The developer flow must use Xcode and a physical Apple Watch.

`docs/COMPATIBILITY.md` must contain Mac and Apple Watch tables. Use `watchOS 10 or newer`, `independent watch app`, `Wi-Fi or cellular where supported`, and `TestFlight during testing; App Store after release`. Mark physical model coverage pending.

Create `docs/PHYSICAL-APPLE-WATCH-TEST.md` with a pending evidence table for:

- Xcode install and signed TestFlight install;
- code pairing and fingerprint comparison;
- Wi-Fi/cellular transition and Mac sleep recovery;
- approvals, questions, instructions, tasks, voice, and revocation;
- stale/offline mutation blocking;
- accessibility, battery, update preservation, and Emergency Stop.

State that source checks and unsigned builds do not prove behavior on a physical watch.

- [ ] **Step 3: Rewrite security, release, and launch-gate documents**

`docs/SECURITY.md` must describe Keychain-backed P-256 signing/agreement material, ECDH/HKDF, AES-256-GCM, replay protection, workspace containment, reviewed voice, revocation, and the Mac-only signed release manifest. Do not claim hardware key storage beyond what `WatchIdentity.swift` implements.

`docs/RELEASE.md` must split distribution into:

1. GitHub/Sparkle: arm64 Mac DMG, source archive, signed schema version 2 manifest, checksums, notarization, and appcasts.
2. App Store Connect: separately signed watchOS archive, TestFlight processing, review, and App Store release.

List only Apple, Sparkle, and release-manifest secrets used by the updated workflow. State that the current GitHub workflow validates watchOS source/build but does not upload a watch archive.

`docs/TODO.md` must mark the source/toolchain cut complete after implementation and keep these gates open: real Apple Watch actions, pushed events, reviewed voice, reconnect behavior, signed archive, TestFlight processing, App Store review, physical-device matrix, battery, clean-Mac notarized install, external security review, and production account ownership.

- [ ] **Step 4: Replace store and legal material**

Create `docs/store/APP-STORE-LISTING.md` with:

- app name `Relay for Codex`;
- bundle ID `com.relayforcodex.watch`;
- category `Productivity`;
- watchOS 10+ and Relay Mac requirements;
- short description `Review and steer Codex from Apple Watch.`;
- an implementation-accurate privacy summary;
- an asset checklist that requires screenshots from a physical Apple Watch after real destination actions work.

Create `docs/store/APP-STORE-REVIEWER-INSTRUCTIONS.md` with a Mac install, invite login, TestFlight watch install, pairing, temporary workspace, safe task, offline/revocation, Emergency Stop, and account-deletion review path. Mark reviewer credentials and private links as App Store Connect-only secrets.

Update privacy, support, and terms copy to say `Apple Watch` where the client identity matters and `App Store build` where distribution matters. Keep the seven-day operational-metadata retention, E2EE boundary, no analytics, reviewed voice, revocation, and deletion descriptions unchanged.

- [ ] **Step 5: Rewrite notices and delete obsolete historical material**

Make `NOTICE` list Codex, Apple, macOS, watchOS, and Sparkle as third-party names or trademarks. Remove names tied to deleted platforms and transport experiments.

Make `THIRD_PARTY_NOTICES.md` derive its inventory from `pnpm-lock.yaml` and `mac/Package.resolved`. Keep `ws`, Sparkle, TypeScript, esbuild, postject, Vitest/Vite/Rollup, Node type definitions, and the existing small support-package summary. Remove the deleted mobile-toolchain dependency table.

Delete every asset, old spec, and old plan listed in this task. Keep the approved 2026-07-26 transition spec and plan until final verification.

- [ ] **Step 6: Verify active documentation and policy consistency**

Run:

```bash
node --test apps/cloud/test/worker.test.ts
pnpm test
rg -n -i \
  -g '!pnpm-lock.yaml' \
  -g '!docs/superpowers/specs/2026-07-26-apple-only-platform-design.md' \
  -g '!docs/superpowers/plans/2026-07-26-apple-only-platform-cut.md' \
  'android|(^|[^a-z])wear([^a-z]|$)|galaxy watch|watch6|gradle|\.apk\b|\badb\b|kotlin|google play|play store' \
  .
git diff --check
```

Expected: Node tests exit 0, `rg` returns no matches outside the two transition documents and pnpm lockfile, and `git diff --check` exits 0.

- [ ] **Step 7: Commit the Apple-only documentation**

```bash
git add -A
git commit -m "docs: rewrite Relay for the Apple ecosystem"
```

---

### Task 6: Remove transition records, run final verification, and push

**Files:**

- Delete: `docs/superpowers/specs/2026-07-26-apple-only-platform-design.md`
- Delete: `docs/superpowers/plans/2026-07-26-apple-only-platform-cut.md`
- Modify only if verification finds a concrete remaining Apple-only defect: files named by the failing command.

**Interfaces:**

- Consumes: the Apple-only tree produced by Tasks 1 through 5.
- Produces: a clean `main` branch, a normal push to `origin/main`, and an evidence-backed report of repository checks and external Apple gates.

- [ ] **Step 1: Delete the transition spec and implementation plan with `apply_patch`**

Delete both files listed in this task. Git history retains their approved content through commits `6d479e8` and the plan checkpoint commit.

Stage those deletions before the tracked-file audit:

```bash
git add -A docs/superpowers
```

- [ ] **Step 2: Run the zero-Android tracked-file audit**

Run:

```bash
git grep -n -i -E \
  'android|(^|[^a-z])wear([^a-z]|$)|galaxy watch|watch6|gradle|\.apk([^a-z]|$)|(^|[^a-z])adb([^a-z]|$)|kotlin|google play|play store' \
  -- ':!pnpm-lock.yaml'
rg --files -g '!node_modules/**' -g '!.git/**' | \
  rg -i '(^|/)(wear|gradle)(/|$)|gradlew|android|play-store|physical-watch'
```

Expected: both searches exit 1 with no output, which means no tracked content
or working-tree path matches. Confirm that the current tree contains no old
preview, screen board, or store path.

- [ ] **Step 3: Run the complete Node and cloud verification**

Run:

```bash
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm --filter @relay/cloud build
pnpm build:bridge-sea
pnpm smoke:bridge-sea
```

Expected: every command exits 0. If the sandbox blocks loopback binding or package cache access, rerun the same command with the required approval and report the exact external gate instead of changing product code.

- [ ] **Step 4: Run the complete Apple verification**

Run:

```bash
swift test --package-path mac
swift build --package-path mac --configuration release --arch arm64
swift test --package-path apple-watch
scripts/check-watchos-source.sh
xcodebuild \
  -project apple-watch/RelayWatch.xcodeproj \
  -scheme RelayWatch \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/relay-watch-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: repository-controlled tests and builds exit 0 when the required local Xcode/watchOS runtime exists. Signing, TestFlight processing, App Store review, and physical-device behavior remain external gates and must not be reported as verified.

- [ ] **Step 5: Check the final diff and commit the cleanup**

Run:

```bash
git diff --check
git status --short
git diff --stat origin/main
```

Review every remaining path against the acceptance criteria. Then run:

```bash
git add -A
git diff --cached --check
git commit -m "chore: finalize Apple-only Relay repository"
```

- [ ] **Step 6: Verify the remote base and push without force**

Run:

```bash
git ls-remote --heads origin main
git rev-parse HEAD
git push origin main
git ls-remote --heads origin main
git status --short --branch
```

Before pushing, confirm the first remote SHA still equals the original `origin/main` base or a commit already contained in local `main`. If someone moved `origin/main`, stop and reconcile without force. After pushing, confirm the remote SHA equals local `HEAD` and the worktree is clean.

- [ ] **Step 7: Inspect the pushed quality run**

Run:

```bash
gh run list --branch main --limit 5 --json databaseId,name,status,conclusion,headSha,url
```

Find the `Quality` run for the pushed `HEAD`. If it is queued or running, wait for that run. Report its final conclusion and URL. Do not claim App Store, TestFlight, notarization, cloud deployment, or physical Apple Watch success from the quality workflow.
