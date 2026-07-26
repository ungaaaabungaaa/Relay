# Relay compatibility

## Mac

| Item | Support |
| --- | --- |
| Processor | Apple silicon only: M1 or newer arm64 Mac |
| macOS | macOS 14 or newer |
| Intel Mac | Not supported |
| Distribution | Notarized `Relay.dmg` from GitHub Releases |
| Codex | Existing signed-in Mac installation |
| Network | Outbound HTTPS/WSS to `api.relayforcodex.com` |

The signed release manifest is the final authority for supported Codex and
protocol versions.

## Wear OS

| Item | Support |
| --- | --- |
| Operating system | Wear OS 3 or newer |
| Android API | API 30 or newer |
| Shapes | Round and square |
| Input | Rotary and touch-only fallback |
| Network | Wi-Fi and normal LTE data |
| Distribution | Google Play Wear OS closed-test track, then production |
| Phone after setup | Not required by Relay |

Relay for Wear OS does not claim support for Android phones, Apple Watch,
Garmin, Huawei/HarmonyOS, or Amazfit/Zepp devices. Apple Watch is a separate
watchOS 10+ Phase 2 app distributed through TestFlight and the App Store.

The beta release gate requires a Galaxy Watch6 plus two additional physical
Wear OS watches across at least two OEMs, including one Wear OS 3 device and two
screen-size classes. Untested models remain community-supported.

## Product requirements

- The Mac must be awake, online, and running Relay and Codex.
- Relay Cloud routes ciphertext and does not run Codex.
- System keyboard/dictation requires no OpenAI key.
- Optional reviewed voice transcription requires an OpenAI key in Mac
  Keychain.
- There is no Tailscale, phone companion, emulator, or cloud-hosted Mac
  requirement.
