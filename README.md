# Relay

Relay lets you talk to and control Codex tasks from a Wear OS watch while Codex
continues running on your Mac.

In plain English:

1. Codex does the real work on your Mac.
2. A small Relay bridge on the same Mac turns safe Codex actions into a watch
   interface.
3. Tailscale carries the encrypted connection when the watch is away from the
   Mac.
4. The watch signs every request, so knowing the public address is not enough
   to control Codex.

Relay has no hosted cloud service and no subscription. Version 1 is planned for
GitHub Releases only under Apache License 2.0.

> **Checkpoint status:** the applications and automated release pipeline are
> implemented on `feat/relay-mvp`, but there is no public easy-install release
> yet. A notarized DMG must not be published until the physical Galaxy Watch6
> and clean-Mac release gates pass.

## See the UI now

The browser preview is a clickable design model of the real native screens:

```bash
cd preview
python3 -m http.server 4173
```

Open [http://127.0.0.1:4173](http://127.0.0.1:4173). You can click Home,
Approval, Task, Voice, New task, Offline, and every Mac dashboard section. The
preview uses no account and sends no data. It is not the Wear OS application.

## All 28 watch screens

These boards show the complete native screen map, not just the six clickable
demo states. They follow the circular Galaxy Watch6 safe area and keep risky
commands, folders, models, and consequences readable. The native Compose
implementation is the source of truth; a repository test checks that every
`Screen` enum entry appears here exactly once.

### 01 — Connection and onboarding

![Relay connection and onboarding screens: welcome, pairing code, Mac identity, connecting, offline, revoked, and update required](docs/assets/screens-connection.svg)

### 02 — Daily control

![Relay daily-control screens: home, inbox, approval, question, tasks, task detail, instruction, system input, voice record, transcript review, and task controls](docs/assets/screens-daily-control.svg)

### 03 — New task

![Relay new-task screens: workspaces, folders, models, reasoning effort, permissions, prompt, and review](docs/assets/screens-new-task.svg)

### 04 — Management

![Relay management screens: approval history, settings, and about](docs/assets/screens-management.svg)

Maintainers can rebuild these lightweight SVG boards without adding a graphics
dependency:

```bash
pnpm generate:readme-screens
```

## What is implemented

### Watch

- native Kotlin and Compose for Wear OS application;
- onboarding, pairing, offline, revoked, and compatibility states;
- Home, inbox, approvals, questions, tasks, activity timeline, steering, and
  stop controls;
- system keyboard/dictation and optional reviewed voice transcription;
- approved workspace browsing, model, reasoning effort, permission profile,
  and new-task review;
- visible Live Monitoring with a four-hour limit and low-battery cutoff;
- periodic battery-aware refresh when Live Monitoring is off;
- circular layouts, rotary navigation, haptics, accessibility labels, and safe
  dangerous-action hold confirmation.

### Mac

- native SwiftUI menu-bar application and dashboard;
- self-contained arm64 bridge sidecar;
- Keychain-backed local admin token and optional OpenAI key;
- watch install wizard using verified Android Platform Tools;
- Tailscale sign-in checks, Funnel preflight, enable/disable, and Emergency
  Stop;
- paired-watch revocation, approved workspaces, redacted diagnostics, and
  signed-update verification.

### Bridge and security

- localhost-only watch and admin listeners;
- short-lived pairing codes and per-watch public-key credentials;
- signed requests, timestamp checks, nonce replay rejection, and revocation;
- idempotent state changes and redacted local audit records;
- resumable WebSocket events with snapshot fallback;
- deterministic approval-risk policy and canonical workspace boundaries;
- optional OpenAI transcription with size/duration limits and temporary audio
  deletion.

## The architecture

```text
Wear OS watch
  └─ signed HTTPS / resumable WebSocket
       └─ Tailscale Funnel (transport only)
            └─ Relay bridge on 127.0.0.1
                 ├─ Codex app-server
                 ├─ approved Mac folders
                 └─ optional OpenAI transcription
```

Codex credentials, the OpenAI key, Mac password, repository contents, and raw
audio do not live on the watch. The Mac remains the source of truth and must be
awake for Relay to work.

## Start here

- New user: [docs/SETUP.md](docs/SETUP.md)
- Physical Watch6 test: [docs/PHYSICAL-WATCH-TEST.md](docs/PHYSICAL-WATCH-TEST.md)
- Supported hardware: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)
- Security boundaries: [docs/SECURITY.md](docs/SECURITY.md)
- Remaining gates: [docs/TODO.md](docs/TODO.md)
- Maintainer release process: [docs/RELEASE.md](docs/RELEASE.md)

No emulator or Wear OS system image is required or used. Development and
release acceptance use a physical watch.

## Developer quick start

Use Android Studio's bundled Java and the already-installed SDK:

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck

export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew :wear:testDebugUnitTest :wear:lintDebug :wear:assembleDebug

pnpm build:bridge-sea
swift test --package-path mac
swift run --package-path mac RelayMac
```

Then follow the Wireless ADB steps in
[docs/PHYSICAL-WATCH-TEST.md](docs/PHYSICAL-WATCH-TEST.md). Turn Wireless
Debugging off when testing is finished.

## License

Relay is licensed under [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
