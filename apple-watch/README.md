# Relay for Apple Watch

This Phase 2 target is an independent watch-only SwiftUI app for watchOS 10+.
It does not require an iPhone companion.

The project contains:

- Bonjour discovery for `_relay-pair._tcp`;
- HTTPS session pairing and Mac/watch fingerprint comparison;
- a non-exportable Secure Enclave P-256 signing identity;
- canonical signed requests and a signed WebSocket handshake;
- offline stale-state behavior and local cache wipe on revocation;
- native routes for inbox, approvals, questions, tasks, activity,
  instructions, voice, new tasks, history, and settings.

Run `../scripts/check-watchos-source.sh` for a watchOS 10+ compiler check, then
open `RelayWatch.xcodeproj` in Xcode. Set your Apple team and use a physical
Apple Watch for pairing, Wi-Fi/cellular transitions, approvals, voice, battery,
revocation, and TestFlight update tests.

The app requires Relay Mac `1.0.0+` and API version `1`. Apple distributes the
public app through TestFlight and the App Store. A DMG cannot install an Apple
Watch app.
