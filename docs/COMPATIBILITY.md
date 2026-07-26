# Relay compatibility

## Mac

| Item | Support |
| --- | --- |
| Processor | Apple silicon, arm64 |
| Operating system | macOS 14 or newer |
| Codex | Installed, signed in, and running on the same Mac |
| Network | Outbound HTTPS/WSS to Relay Cloud |
| Distribution | Developer ID signed and notarized Mac disk image after release gates pass |
| Runtime | Mac stays awake and online while the Apple Watch uses Relay |

Intel Macs are outside the release contract. The signed schema version 2
manifest records the supported Codex version range for each Mac release.

## Apple Watch

| Item | Support |
| --- | --- |
| Operating system | watchOS 10 or newer |
| App structure | independent watch app |
| Network | Wi-Fi or cellular where supported |
| Distribution | TestFlight during testing; App Store after release |
| Mac requirement | Relay Mac 1.0.0+ and API version 1 |
| Physical model coverage | Pending physical-device results |

The repository contains one watchOS target and no companion iPhone target.
Apple Watch model, case-size, network-transition, accessibility, update, and
battery coverage stays pending until maintainers record physical evidence in
[PHYSICAL-APPLE-WATCH-TEST.md](PHYSICAL-APPLE-WATCH-TEST.md).

## Product constraints

- Relay Cloud routes ciphertext and does not run Codex.
- The Mac must run Relay, Codex, and the loopback bridge.
- An offline or stale Apple Watch must block mutations.
- Optional recorded voice requires transcript review before Relay sends text to
  Codex.
- App Store and TestFlight availability remain external distribution gates.
