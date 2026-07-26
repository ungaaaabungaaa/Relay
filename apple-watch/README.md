# Relay for Apple Watch

This is the Phase 2 foundation for an independent watch-only SwiftUI app
targeting watchOS 10+. It does not require an iPhone companion and is not part
of the Wear-first public beta.

The source now contains:

- six-character Relay Cloud pairing and Mac/watch fingerprint comparison;
- separate Keychain-backed P-256 signing and agreement identities;
- ECDH/HKDF root-key derivation and authenticated AES-GCM tunnel envelopes;
- scoped cloud credentials, root keys, and replay sequences stored on-watch;
- canonical signed inner requests over an authenticated WSS device tunnel;
- offline stale-state behavior and local cache wipe on revocation;
- native routes for inbox, approvals, questions, tasks, activity,
  instructions, voice, new tasks, history, and settings.

The destination screens still use preview content. Before TestFlight they must
be wired to real response/event models, actions, reviewed voice capture, and
reconnect callbacks. Physical Wi-Fi/cellular transitions, battery, revocation,
and TestFlight updates are also unverified.

Run `../scripts/check-watchos-source.sh` for a watchOS 10+ compiler check, then
open `RelayWatch.xcodeproj` in Xcode. Set your Apple team and use a physical
Apple Watch for pairing, Wi-Fi/cellular transitions, approvals, voice, battery,
revocation, and TestFlight update tests.

The future app will require Relay Mac `1.0.0+` and API version `1`. Apple
distributes public watchOS apps through TestFlight and the App Store. A DMG
cannot install an Apple Watch app.
