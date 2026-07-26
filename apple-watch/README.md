# Relay for Apple Watch

Relay for Apple Watch is the project's independent watchOS 10+ client. It pairs
directly with Relay Cloud and a Relay Mac; Relay has no separate iPhone
companion target in this repository.

The source now contains:

- six-character Relay Cloud pairing and Mac/watch fingerprint comparison;
- separate Keychain-backed P-256 signing and agreement identities;
- ECDH/HKDF root-key derivation and authenticated AES-GCM tunnel envelopes;
- scoped cloud credentials, root keys, and replay sequences stored on-watch;
- canonical signed inner requests over an authenticated WSS device tunnel;
- offline stale-state behavior and local cache wipe on revocation;
- native routes for inbox, approvals, questions, tasks, activity,
  instructions, voice, new tasks, history, and settings.

The destination screens still use preview content. Developers must connect them
to response and event models, actions, reviewed voice capture, and reconnect
callbacks. The team has not verified physical Wi-Fi or cellular transitions,
battery behavior, revocation, signing, or TestFlight updates.

Run `../scripts/check-watchos-source.sh` for a watchOS 10+ compiler check, then
open `RelayWatch.xcodeproj` in Xcode. Set your Apple team and signing assets,
then use a physical Apple Watch for pairing, Wi-Fi or cellular transitions,
approvals, voice, battery, revocation, and TestFlight update tests.

The watch client requires Relay Mac `1.0.0+` and API version `1`. Apple
distributes watchOS apps through TestFlight and the App Store. This repository
does not include a signed TestFlight or App Store build. A DMG cannot install an
Apple Watch app.
