# Apple-Only Platform Design

**Status:** Approved on 2026-07-26

## Decision

Relay will support two client platforms:

- the Relay Mac app on Apple-silicon Macs running macOS 14 or newer;
- the independent Relay Apple Watch app on watchOS 10 or newer.

Relay Cloud, the Mac bridge, and the shared protocols remain because the Apple
Watch app uses them for pairing, encrypted transport, device revocation, and
Codex actions. The current tree will contain no Android or Wear OS client,
toolchain, build, release, store, preview, or support material.

Git history will continue to contain the deleted Android work. Rewriting remote
history and deleting a developer's local Android SDK fall outside this change.

## Current State and Accepted Trade-off

The Apple Watch target already implements six-character cloud pairing,
Keychain-backed identities, ECDH/HKDF key derivation, authenticated AES-GCM
envelopes, signed requests, replay tracking, and offline/revoked states.

Several Apple Watch destination screens still show preview data. Real
approvals, questions, instructions, task controls, voice, pushed events, and
reconnect behavior need more implementation and physical testing. Removing
Wear OS now removes Relay's more complete watch client before Apple Watch
reaches feature parity. The project accepts that trade-off because no users,
store release, or production setup depend on the Android client. Documentation
must describe the Apple Watch limitations without calling the product beta-ready.
Do not add an Android-device data migration. The user confirmed that Relay has
no users or production setup.

## Resulting Architecture

```text
Apple Watch app
  -> signed request in an encrypted WebSocket envelope
  -> Relay Cloud ciphertext router
  -> outbound Relay Mac tunnel
  -> loopback Relay bridge
  -> Codex and approved Mac workspaces
```

The cloud and bridge use platform-neutral types. Product clients,
builds, tests, copy, and distribution support only macOS and watchOS. Device
metadata may retain a generic `platform` field, but active fixtures use
`watch-os` and Apple device metadata. The Apple Watch client reports its screen
as `rounded-rect`, replacing the inherited round-Wear value. The platform label
does not serve as an authentication boundary.

## Removal Boundary

Delete:

- `wear/` and all Kotlin, Compose, Android resources, and Wear tests;
- root Gradle files, the Gradle wrapper, Android ignore entries, and Android
  dependency inventory;
- Android jobs and toolchain setup in GitHub Actions;
- APK scanning, APK signing, Android keystore inputs, Wear version fields, and
  APK release artifacts;
- the Wear browser preview, Kotlin-backed gallery generator, and generated Wear
  screen boards;
- Play Store listing and reviewer instructions;
- the Galaxy Watch physical-test guide and Android-era implementation
  specs/plans;
- this transition spec and its implementation plan after the work finishes, so
  Git history holds the decision record without leaving Android guidance in the
  final tree.

Keep and update:

- `apple-watch/`, `mac/`, `apps/bridge/`, `apps/cloud/`, and shared packages;
- cloud deployment and invite workflows;
- Mac DMG, notarization, signed-manifest, and Sparkle update infrastructure;
- generic device, pairing, workspace, approval, voice, and tunnel APIs.

Change Android-specific sample devices and test names in shared code to Apple
Watch fixtures. Move the crypto vector that protects cross-language pairing
behavior into the Apple Watch test suite before deleting its Wear copy.

## Release Contract

Maintainers will change the signed GitHub release manifest to schema version 2
and describe the Mac release alone. The schema will require the notarized arm64
`Relay.dmg`, source archive, license files, compatibility document, checksums,
and signature. The Mac release client and its tests will reject the old
Android-shaped schema.

Remove `watchVersionCode` from bundled Mac metadata. Remove Java, Android SDK,
keystore, `apksigner`, APK build, APK upload, and Wear version inputs from the
release workflow.

Apple will distribute the watchOS app through TestFlight and the App Store.
The GitHub DMG cannot install or update an Apple Watch app. App Store Connect
signing and upload remain an external release gate until the project configures
an Apple Developer account and distribution credentials.

## Product Copy and Documentation

Replace Google Play, Wear OS, ADB, and Android language in the Mac app with
Apple Watch, TestFlight, App Store, and Xcode language. Setup, Watches, Updates,
Voice, About, compatibility, security, release, support, privacy, terms, and
the cloud-hosted policy pages must agree.

Add an Apple Watch physical-test guide, App Store listing, and App Store
reviewer guide. Delete the old Wear screenshots because they do not prove Apple
Watch behavior.

The README and Apple Watch guide will state that pairing and encrypted tunnel
work exist in source while destination actions, signed TestFlight distribution,
and physical-device behavior remain unverified.

## Verification

The Apple-only quality gate will run:

```bash
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm --filter @relay/cloud build
pnpm build:bridge-sea
pnpm smoke:bridge-sea
swift test --package-path mac
swift build --package-path mac --configuration release --arch arm64
swift test --package-path apple-watch
scripts/check-watchos-source.sh
xcodebuild -project apple-watch/RelayWatch.xcodeproj \
  -scheme RelayWatch \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
git diff --check
```

After removing the transition spec and plan, the final audit will search tracked
source, configuration, UI copy, documentation, and CI for Android, Wear OS,
Galaxy Watch, Gradle, APK, ADB, Kotlin, and Google Play references. Optional
esbuild and Rollup package names in `pnpm-lock.yaml` may contain `android`; pnpm
owns those cross-platform lockfile records, and they do not provide Android
product support.

Missing signing identities, App Store Connect setup, a physical Apple Watch, or
a local Xcode runtime will remain external verification gates. The final report
will separate those gates from commands that pass in the repository.

## Out of Scope

This removal does not finish the Apple Watch destination actions, create an
iPhone companion, deploy Relay Cloud, publish a Mac release, upload a TestFlight
build, configure production accounts, or rewrite Git history. Those tasks need
their own implementation and release work.

## Acceptance Criteria

- The current Git tree contains no Android or Wear OS implementation, build,
  release, preview, store, or active documentation surface.
- Mac, Apple Watch, bridge, cloud, and shared protocol code remain.
- Mac UI and active docs describe an Apple-only product and disclose unfinished
  Apple Watch behavior.
- CI and release workflows request no Android toolchain, secret, version, or
  artifact.
- The release manifest and Mac updater validate a Mac-only schema.
- Shared behavioral and cryptographic tests retain Apple-critical coverage.
- The final verified changes are committed and pushed to `origin/main`.
