# Relay for Apple Watch

Relay is an independent watchOS 10+ client with no iPhone companion target. It
pairs through Relay Cloud with Relay on an Apple-silicon Mac.

The source implements:

- six-character pairing with explicit Mac and Watch fingerprint comparison;
- separate P-256 signing and agreement identities plus ECDH/HKDF and AES-GCM;
- one encrypted WebSocket response/event router with replay and reconnect safety;
- live inbox, approval, question, task, activity, instruction, new-task,
  history, settings, revocation, and offline/stale views;
- bridge-provided folder/model/effort selection, validated answers, dangerous
  approval confirmation, and idempotent mutation retry;
- explicit microphone recording, 30-second/2 MiB bounds, Mac-configured
  transcription, editable transcript review, explicit Send, and deterministic
  audio cleanup.

Run the package tests and architecture source check:

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcrun swift test --disable-sandbox --package-path apple-watch
../scripts/check-watchos-source.sh
```

Then open `RelayWatch.xcodeproj`, choose the organization-owned team and a
paired physical Watch, and follow `../docs/PHYSICAL-APPLE-WATCH-TEST.md`.
Compiler checks do not prove microphone permission, Wi-Fi/cellular transitions,
battery, accessibility, signing, TestFlight, App Store review, or update
preservation.

The Watch requires Relay Mac `1.0.0+` and API version `1`. Apple distributes the
Watch app through TestFlight and the App Store; a Mac disk image cannot install
it. This repository does not contain or claim a signed public build.
