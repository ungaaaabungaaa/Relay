# Relay

Relay lets an Apple Watch review and control Codex tasks running on an
Apple-silicon Mac. Relay Cloud routes end-to-end encrypted envelopes between
the approved watch and Mac; it cannot decrypt task content.

## Current checkpoint

The repository contains six-character cloud pairing, fingerprint comparison,
Keychain identities, and an encrypted Apple Watch request tunnel. The Mac app,
loopback bridge, and Relay Cloud provide the supporting account, workspace,
device, and ciphertext-routing controls.

Apple Watch destination screens still use preview content. Real destination
actions, pushed events, reviewed voice, reconnect behavior, signed watchOS
archives, TestFlight processing, App Store review, and physical-device evidence
remain release gates. The repository does not provide a live TestFlight or App
Store build.

## What is implemented

### Apple Watch

- independent watchOS 10+ app with no companion iPhone target;
- six-character Relay Cloud pairing with Mac and watch fingerprint comparison;
- separate P-256 signing and key-agreement identities backed by Keychain and
  Apple security APIs;
- ECDH/HKDF root-key derivation and AES-256-GCM tunnel envelopes;
- scoped cloud credentials, replay sequences, and canonical signed requests;
- offline, incompatible, and revoked states with local credential removal;
- native route shells for inbox, approvals, questions, tasks, instructions,
  voice, new tasks, history, and settings.

The route shells do not yet complete destination actions against Codex.

### Mac

- native SwiftUI menu-bar app for Apple-silicon Macs on macOS 14+;
- embedded arm64 bridge with a loopback-bound admin API and Codex adapter;
- passwordless invite login, PKCE, rotating refresh tokens, and Keychain
  storage;
- outbound Relay Cloud tunnel and encrypted pairing approval;
- approved-workspace containment, watch revocation, Emergency Stop, account
  deletion, and redacted diagnostics;
- Sparkle update support and a Developer ID packaging workflow for a notarized
  Mac disk image.

Signing credentials and notarization results remain external release gates.

### Relay Cloud

- Cloudflare Worker API, D1 data store, and a hibernating Durable Object tunnel
  router;
- accounts restricted to invited users, with single-use email links;
- encrypted email storage plus hashed lookup, refresh, host, and watch values;
- ciphertext routing with no content decryption and with account and host
  isolation;
- live revocation, Emergency Stop credential rotation, and no offline action
  queue;
- seven-day operational-metadata retention, no product analytics, and no
  plaintext Codex-content logging.

## Architecture

```text
Apple Watch
  -> signed request inside an AES-256-GCM envelope
  -> Relay Cloud ciphertext tunnel
  -> Relay Mac outbound tunnel
  -> loopback Relay bridge
  -> Codex app-server on the Mac
```

The Mac must stay awake, online, and running Relay and Codex. Relay Cloud does
not run Codex or store Codex credentials.

## Start here

- User and developer setup: [docs/SETUP.md](docs/SETUP.md)
- Compatibility: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)
- Security model: [docs/SECURITY.md](docs/SECURITY.md)
- Physical Apple Watch test: [docs/PHYSICAL-APPLE-WATCH-TEST.md](docs/PHYSICAL-APPLE-WATCH-TEST.md)
- Release gates: [docs/TODO.md](docs/TODO.md)
- Maintainer release guide: [docs/RELEASE.md](docs/RELEASE.md)
- Relay Cloud operations: [docs/CLOUD-OPERATIONS.md](docs/CLOUD-OPERATIONS.md)
- Apple Watch source status: [apple-watch/README.md](apple-watch/README.md)

## Developer quick start

Install the JavaScript dependencies and verify the shared code:

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm build:bridge-sea
```

Build and run the Mac Swift package:

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcrun swift test --package-path mac
xcrun swift run --package-path mac RelayMac
```

Check the Apple Watch Swift package and target source:

```bash
xcrun swift test --package-path apple-watch
scripts/check-watchos-source.sh
```

Run an unsigned generic watchOS build:

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

Source checks and unsigned builds do not replace a signed install on a
physical Apple Watch.

## License

Relay uses the [Apache License 2.0](LICENSE). Read [NOTICE](NOTICE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and dependency
licenses.
