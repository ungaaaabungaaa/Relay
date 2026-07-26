# Relay for Apple Watch

This is a Phase 2 prototype for an independent watch-only SwiftUI app targeting
watchOS 10+. It does not require an iPhone companion, but it is **not part of
the Wear-first public beta and is not currently compatible with Relay Cloud**.

The legacy prototype contains:

- Bonjour discovery for `_relay-pair._tcp`;
- HTTPS session pairing and Mac/watch fingerprint comparison;
- a non-exportable Secure Enclave P-256 signing identity;
- canonical signed requests and a signed WebSocket handshake;
- offline stale-state behavior and local cache wipe on revocation;
- native routes for inbox, approvals, questions, tasks, activity,
  instructions, voice, new tasks, history, and settings.

Those paths target the earlier same-Wi-Fi/Bonjour transport. Before TestFlight,
they must be replaced with the current cloud pairing, P-256 agreement identity,
AES-GCM tunnel, persistent sequence/replay state, revoked/offline behavior, and
real screen data used by the Wear OS client. Bonjour must not be described as a
production Relay Cloud pairing path.

Run `../scripts/check-watchos-source.sh` for a watchOS 10+ compiler check, then
open `RelayWatch.xcodeproj` in Xcode. Set your Apple team and use a physical
Apple Watch for pairing, Wi-Fi/cellular transitions, approvals, voice, battery,
revocation, and TestFlight update tests.

The future app will require Relay Mac `1.0.0+` and API version `1`. Apple
distributes public watchOS apps through TestFlight and the App Store. A DMG
cannot install an Apple Watch app.
