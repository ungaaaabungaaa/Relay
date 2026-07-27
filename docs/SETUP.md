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
   14 or newer. Find the white UFO beside the other menu-bar items; no
   dashboard window is expected.
2. Open **Diagnostics → Refresh** and confirm the bridge and Codex status.
3. Open **Relay Cloud → Sign In…** and complete the invite/PKCE link in the
   browser when credentials are available.
4. Only after both bridge and Relay Cloud are ready, open **Apple Watch → Start
   Secure Pairing** to create the six-character code. The command remains
   disabled until those prerequisites are met.
5. Install Relay for Codex on the Apple Watch from the TestFlight or App Store
   link supplied with the invite. On the Watch, enter the code in **Pair with
   Mac**, tap **Find Mac**, compare fingerprints, then tap **Fingerprints
   match**.
6. Approve the watch fingerprint on the Mac, then select the Mac workspace
   roots that the watch may use.
7. Keep the Mac awake, online, and running Relay and Codex. Once paired, the
   Watch home shows either **Needs you** (up to two pending actions) or **All
   clear** with **Tasks**, **New task**, **Voice**, and **More**. **More**
   contains **Voice**, **Refresh**, **History**, and **Settings**.

The current source implements pairing, live destinations, pushed-event refresh,
reviewed voice, reconnect refresh, and stale mutation blocking. These paths
still require interactive staging and physical-device evidence.

## Offline, revocation, and deletion

Relay must block mutations when the Mac or watch is offline and must not queue
an action for later execution.

- Revoke one Apple Watch from **Apple Watch → paired device → Revoke…** if the
  device is lost.
- Use **Emergency Stop** to revoke watch access, rotate the Mac host
  credential, disconnect tunnels, and stop the bridge. Codex tasks stay on the
  Mac.
- Use **Delete Relay Account** to remove cloud account and device metadata and
  clear Relay Cloud credentials from the Mac. Relay does not delete Codex tasks
  or repositories.

For local native-menu testing, Relay is menu-bar only: expect the UFO beside
the other menu-bar items, not a dashboard window. Exercise every root item and
submenu plus every confirmation dialog before recording the result.

## Developer setup

Install Xcode with the watchOS 10 or newer SDK. Use a physical Apple Watch for
signed installation and runtime testing.

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm build:bridge-sea

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcrun swift test --disable-sandbox --package-path mac
xcrun swift build --disable-sandbox --package-path mac
xcrun swift run --package-path mac RelayMac
xcrun swift test --disable-sandbox --package-path apple-watch
scripts/check-watchos-source.sh
```

For an unsigned compiler check:

```bash
xcodebuild \
  -project apple-watch/RelayWatch.xcodeproj \
  -scheme RelayWatch \
  -configuration Debug \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /private/tmp/relay-watch-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For a device run, open `apple-watch/RelayWatch.xcodeproj` in Xcode, select the
Apple developer team, choose the paired physical Apple Watch, and run the app.
Record results in
[PHYSICAL-APPLE-WATCH-TEST.md](PHYSICAL-APPLE-WATCH-TEST.md).

### Debug cloud origin

`RELAY_CLOUD_ORIGIN` is a debug-build-only override shared by the Mac HTTP and
WebSocket clients and the Watch environment. It accepts the TLS staging origin
or plaintext loopback such as `http://127.0.0.1:8787`. Invalid values fail
closed; release builds reject every override instead of falling back silently.

Loopback is suitable only when the client runs on the same Mac. A physical
Apple Watch cannot reach the Mac through `localhost`, and plaintext remote
origins are rejected. Physical testing therefore needs a reachable TLS staging
deployment and its matching `wss://` tunnel.

## Cloud maintainer setup

Relay Cloud needs organization-owned Cloudflare and Resend accounts, D1
identifiers, Worker secrets, DNS, a verified sending domain, and protected
GitHub environments. Follow [CLOUD-OPERATIONS.md](CLOUD-OPERATIONS.md) and
[RELEASE.md](RELEASE.md). Keep credentials and sign-in links out of source,
logs, issues, and diagnostic archives.
