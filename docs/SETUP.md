# Set up Relay

## Requirements

- an Apple-silicon Mac running macOS 14 or newer;
- Codex installed, signed in, and able to run a task on that Mac;
- a Relay invite;
- an Apple Watch running watchOS 10 or newer;
- network access for the Mac and Apple Watch;
- an awake, online Mac running Relay and Codex during watch use.

Relay Cloud carries encrypted envelopes between the approved Apple Watch and
Mac. It does not run Codex and cannot decrypt task content.

## User flow

The release owner will supply the Mac build and Apple Watch build through the
invite. Apple distributes test builds through TestFlight and release builds
through the App Store. This repository does not claim that either distribution
channel is live.

1. Install the supplied Relay Mac build on an Apple-silicon Mac running macOS
   14 or newer.
2. Open Relay and confirm that it finds the local Codex installation and starts
   the loopback bridge.
3. Enter the invited email address. Open the single-use link in the browser to
   finish the PKCE login.
4. Install Relay for Codex on the Apple Watch from the TestFlight or App Store
   link supplied with the invite.
5. In Relay for Mac, open **Watches** and create a six-character pairing code.
6. Enter the code on the Apple Watch.
7. Compare the Mac fingerprint on both devices. Confirm it on the watch, then
   approve the watch fingerprint on the Mac.
8. Select the Mac workspace roots that the watch may use.
9. Keep the Mac awake, online, and running Relay and Codex.

The current source supports pairing and the encrypted request tunnel. Apple
Watch destination actions, pushed events, reviewed voice, and reconnect
behavior still require implementation and physical evidence.

## Offline, revocation, and deletion

Relay must block mutations when the Mac or watch is offline and must not queue
an action for later execution.

- Revoke one Apple Watch from **Watches** if the device is lost.
- Use **Emergency Stop** to revoke watch access, rotate the Mac host
  credential, disconnect tunnels, and stop the bridge. Codex tasks stay on the
  Mac.
- Use **Delete Relay Account** to remove cloud account and device metadata and
  clear Relay Cloud credentials from the Mac. Relay does not delete Codex tasks
  or repositories.

## Developer setup

Install Xcode with the watchOS 10 or newer SDK. Use a physical Apple Watch for
signed installation and runtime testing.

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm build:bridge-sea

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcrun swift test --package-path mac
xcrun swift run --package-path mac RelayMac
xcrun swift test --package-path apple-watch
scripts/check-watchos-source.sh
```

For an unsigned compiler check:

```bash
xcodebuild \
  -project apple-watch/RelayWatch.xcodeproj \
  -scheme RelayWatch \
  -configuration Debug \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/relay-watch-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For a device run, open `apple-watch/RelayWatch.xcodeproj` in Xcode, select the
Apple developer team, choose the paired physical Apple Watch, and run the app.
Record results in
[PHYSICAL-APPLE-WATCH-TEST.md](PHYSICAL-APPLE-WATCH-TEST.md).

## Cloud maintainer setup

Relay Cloud needs organization-owned Cloudflare and Resend accounts, D1
identifiers, Worker secrets, DNS, a verified sending domain, and protected
GitHub environments. Follow [CLOUD-OPERATIONS.md](CLOUD-OPERATIONS.md) and
[RELEASE.md](RELEASE.md). Keep credentials and sign-in links out of source,
logs, issues, and diagnostic archives.
