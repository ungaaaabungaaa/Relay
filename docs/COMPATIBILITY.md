# Relay compatibility

The signed manifest shipped with each GitHub Release is the final authority for
that release. This page explains the project baseline.

## Mac

| Item | Support |
| --- | --- |
| Processor | Apple silicon only: M1, M2, M3, M4, or newer arm64 Mac |
| macOS | macOS 14 or newer |
| Intel Mac | Not supported |
| Distribution | Notarized `Relay.dmg` from GitHub Releases |
| Codex | Existing Mac installation and signed-in desktop session |
| Tailscale | Required for remote watch access; free plan is sufficient |

The current development checkout has been exercised with Codex CLI `0.144.5`.
The intended first-release range is `0.144.x`, but the values in
`release-manifest.json` override this note. Relay hides an operation when the
installed Codex app-server does not advertise the needed capability.

## Watches

| Item | Support |
| --- | --- |
| Operating system | Wear OS 4 or newer |
| Android API | API 33 or newer |
| Shape | Round layouts are the primary design |
| Networking | Wi-Fi; LTE may work when the watch and plan permit normal HTTPS |
| Install method | Wireless ADB from the Relay Mac wizard |
| Phone requirement after setup | None for Relay itself |

Galaxy Watch6 is the required project release device. Its physical acceptance
run is still pending. Other Wear OS 4+ watches are supported by design but must
be labelled **community-tested** until a reproducible physical result is added
to this file.

| Device | Wear OS | Result | Tester |
| --- | --- | --- | --- |
| Samsung Galaxy Watch6 | 4+ | Release gate pending | Project |

## Feature requirements

- The Mac must be awake, online, and running Relay and Codex.
- Tailscale must be signed in, and Funnel must be enabled for remote networks.
- System keyboard/dictation requires no OpenAI key.
- Optional hold-to-record transcription requires an OpenAI API key stored in
  macOS Keychain.
- Relay does not support Android phones, Apple Watch, Intel Macs, or a
  cloud-hosted Mac replacement in version 1.

## How to contribute a watch result

Open a GitHub issue with the watch model, Wear OS version, install result,
round-screen and rotary result, Wi-Fi reconnect result, approval/deny result,
and one-hour battery observation. Do not attach pairing codes, Funnel URLs,
device public keys, account names, prompts, or command output.
