# Relay Public GitHub Release Design

Date: 2026-07-25
Status: Product direction approved; written specification awaiting user review

## Summary

Relay is a standalone Wear OS remote for Codex tasks running on an Apple silicon
Mac. A native SwiftUI menu-bar application manages installation, pairing,
Tailscale Funnel, the local bridge, devices, updates, and diagnostics. The
existing TypeScript bridge remains the version-aware translator between the
watch and Codex app-server.

Version 1 is distributed only through GitHub Releases under Apache License 2.0.
The primary physical test device is the Samsung Galaxy Watch6. The supported
target is round watches running Wear OS 4 or later; devices not physically
verified by the project are community-supported until their results are added
to the compatibility matrix.

## Locked product decisions

- Distribution: GitHub Releases only; no Play Store release in version 1.
- Mac support: Apple silicon only.
- Mac experience: native SwiftUI menu-bar application.
- Bridge: retain the current TypeScript bridge and package it as a
  self-contained arm64 sidecar; users do not install Node.js or pnpm.
- Remote transport: free Tailscale account and Tailscale Funnel.
- Voice: built-in Wear OS text/voice input without an API key, plus optional
  hold-to-record transcription through the Mac using an OpenAI API key.
- Approvals: normal actions can be approved with one tap; dangerous or elevated
  actions require press-and-hold by default. A single-tap-everything mode exists
  only behind an explicit advanced warning.
- Watch support: Wear OS 4 or later on round screens, with Galaxy Watch6 as the
  first fully tested device.
- License: Apache License 2.0.
- Development and acceptance testing: physical watches only; no emulator or Wear
  OS system image is required.

## User outcome

A new user can:

1. Download one notarized Mac disk image from a GitHub Release.
2. Drag Relay to Applications and open it.
3. Follow a guided check for Codex and Tailscale.
4. Pair a Wear OS watch over Wireless ADB and install the signed APK.
5. Pair the Relay watch app to the Mac with a short-lived code.
6. Enable remote access through Tailscale Funnel.
7. View and control existing Codex tasks from Wi-Fi or LTE while the Mac is
   awake and Relay is running.

After the first setup, normal use does not require Android Studio, a terminal,
Node.js, pnpm, Gradle, or an Android phone.

## Non-goals for version 1

- Google Play Store distribution.
- Intel Mac, Windows, or Linux bridge applications.
- Android or iPhone companion applications.
- A Relay-hosted cloud account, database, push gateway, or telemetry service.
- Running Codex or an AI model directly on the watch.
- Scraping or automating the Codex desktop interface.
- Silently installing or updating the APK without Wireless ADB.
- Waking a sleeping Mac.
- Queuing approvals, commands, or new tasks while offline.
- File-content browsing or editing from the watch.

## System architecture

```text
Wear OS app
    │ HTTPS requests + resumable live events
    ▼
Tailscale Funnel public TLS origin
    │ reverse proxy to loopback only
    ▼
Relay bridge at 127.0.0.1:43117
    ├── Codex app-server adapter
    ├── optional OpenAI transcription
    ├── approved workspace browser
    └── SQLite event, device, and audit store
    ▲
    │ private local administration channel
Relay SwiftUI menu-bar app
```

The menu-bar app is the user-facing control plane. The bridge is the narrow
security and protocol boundary. Funnel is transport, not identity. Codex
remains the worker and source of truth.

### Native Mac application

The SwiftUI application:

- owns first-run setup, status, help, and recovery;
- starts and stops the bundled bridge;
- optionally starts at Mac login;
- discovers or downloads official Android Platform Tools after user consent;
- discovers a watch through ADB mDNS with a manual-address fallback;
- performs Wireless ADB pairing, connection, APK installation, and APK update;
- checks that Codex and Tailscale are available;
- enables and disables Funnel only after bridge security self-checks pass;
- creates pairing codes and manages paired devices;
- manages approved workspace roots;
- stores optional OpenAI credentials in macOS Keychain;
- checks the signed GitHub release feed for Mac and watch updates;
- shows redacted diagnostics and emergency controls.

Quitting Relay deliberately stops the bridge and disables Relay-managed Funnel
ingress. A login item relaunches the menu application when enabled.

### Bundled bridge sidecar

The current TypeScript bridge becomes a signed, self-contained arm64 executable
inside the Mac application bundle. The exact packaging tool is an implementation
choice, but the release must not require a separate JavaScript runtime.

The bridge:

- listens for watch traffic only on `127.0.0.1`;
- exposes no private metadata from public health responses;
- authenticates devices and rejects replayed requests before reading task data;
- translates a stable Relay API into version-sensitive Codex calls;
- maintains a bounded resumable event stream;
- transcribes optional audio and immediately deletes it;
- applies workspace and approval policy;
- records redacted audit events.

Administrative operations such as pairing-code creation, device revocation, and
workspace-policy changes use a Mac-user-only local channel. The channel is not
exposed through Funnel.

### Codex adapter

Every Codex operation goes through one adapter with a tested stable interface:

- list and read tasks;
- read activity and status;
- answer supported approval types;
- answer Codex questions;
- send or steer instructions;
- interrupt or stop a task;
- list models and reasoning efforts;
- start a task in an approved workspace;
- report capabilities and compatibility failures.

Relay does not invent support for a missing Codex capability. It disables the
affected control and explains the installed-version mismatch.

### Wear OS application

The watch app is a standalone Kotlin and Compose for Wear OS application. It
owns rendering, local navigation, a minimal stale cache, cryptographic request
signing, microphone capture, and network reconnection. It stores no Codex
credential, OpenAI key, Mac password, repository content, or audio history.

The release declares Wear OS 4 / Android 13 (API 33) as its minimum supported
platform and the watch hardware feature as required.

The UI uses shallow navigation, circular safe areas, rotary scrolling, haptics,
large touch targets, vector icons, and text wherever safety or meaning would be
ambiguous.

## Mac application screens

### First-run setup

A single checklist shows:

1. Relay application integrity.
2. Codex installed and reachable.
3. Tailscale installed and signed in.
4. Bridge security self-test passed.
5. Watch installed.
6. Watch paired to Relay.
7. Remote access enabled.

Each failed row has one primary fix action and a plain-language explanation.
Relay may open an official download page but does not silently install Codex or
Tailscale.

### Watch installation wizard

The wizard:

1. Verifies or downloads Platform Tools.
2. Shows exact watch Developer Options and Wireless Debugging steps.
3. Searches for pairing services through ADB mDNS.
4. Falls back to manual IP, pairing port, connection port, and pairing code.
5. Connects to the watch and displays the verified device model.
6. Installs or updates the release APK with `adb install -r`.
7. Opens Relay on the watch.
8. Recommends turning Wireless Debugging off after installation.

The wizard never asks the user to install an emulator or Android Studio.

### Menu status

The compact menu shows:

- bridge running or stopped;
- Codex connected or unavailable;
- remote access enabled or disabled;
- connected watch count;
- active and waiting task counts;
- pending approval count;
- update availability;
- Open Dashboard, Emergency Stop, and Quit.

### Dashboard

The dashboard contains Setup, Watches, Remote Access, Workspaces, Voice,
Updates, Diagnostics, and About sections. It is a normal SwiftUI window opened
from the menu bar, not a web interface.

### Emergency stop

One Mac action:

1. disables Funnel;
2. stops accepting watch sessions;
3. leaves Codex tasks untouched;
4. shows whether each step succeeded.

Device revocation is a separate deliberate action so a temporary network
shutdown does not force re-pairing.

## Watch screen map

### Connection and onboarding

1. Welcome
2. Relay pairing-code entry
3. Mac identity confirmation
4. Connecting
5. Offline or Mac asleep
6. Revoked device
7. Compatibility or update required

### Daily control

8. Home
9. Action inbox
10. Approval detail
11. Codex question
12. Task list
13. Task detail and activity timeline
14. Send instruction
15. Built-in text and voice input
16. Hold-to-record voice
17. Transcript review
18. Task controls

### New task

19. Workspace list
20. Folder browser within an approved workspace
21. Model selector
22. Reasoning-effort selector
23. Permission profile selector
24. Prompt input
25. New-task review and confirmation

### Management

26. Approval history
27. Settings
28. About, license, versions, and update state

The top-level Home, Inbox, Tasks, and New Task destinations remain reachable
without navigation deeper than two meaningful levels. Long detail flows use a
linear step sequence with an obvious back or cancel action.

## Watch behavior

### Home

Home prioritizes what needs attention:

1. pending approval or question;
2. currently running task;
3. recent tasks;
4. connection status and last refresh.

Empty states explain whether there is simply no work or Relay cannot reach the
Mac. Stale content is visibly labelled and cannot perform an action.

### Task detail

Task detail presents a concise, watch-sized activity timeline rather than raw
terminal output. Events include Codex messages, tool activity, approval state,
questions, failures, and completion. Exact commands and consequences remain
available in the approval view.

The screen exposes only actions currently supported by the adapter. Interrupt,
stop, retry, or archive do not appear when Codex does not offer them.

### Approvals

Every approval has an immutable Relay action ID and shows:

- operation type and risk label;
- exact command or file operation;
- working directory;
- declared network, filesystem, or privilege consequence;
- task name;
- request age and expiry state.

Risk classification uses Codex-provided policy and permission metadata when it
is available. The bridge then applies deterministic local rules for destructive
commands, privilege escalation, broad filesystem writes, and network-policy
changes. Unknown or incomplete cases fail into the dangerous class rather than
the normal class.

Default confirmation policy:

- deny: one tap;
- normal approval: one tap;
- dangerous, destructive, or elevated approval: press and hold for 1.5 seconds;
- moving the finger away or losing screen focus cancels the hold;
- expired approvals cannot be submitted.

Advanced “single tap all approvals” requires a warning on both Mac and watch.
The setting is device-specific, auditable, and can be reset from the Mac.

### Questions

Codex questions support:

- one or more supplied choices;
- short keyboard or voice input;
- a review step before submitting free text;
- explicit timeout or already-answered states.

### Voice

Mode one uses the system Wear OS input flow. It requires no Relay API key and
returns editable text to the instruction screen.

Mode two is optional:

1. user presses and holds to record;
2. the watch shows elapsed time and a hard duration limit;
3. releasing uploads the recording through the authenticated bridge;
4. the Mac transcribes using the Keychain-held OpenAI key;
5. the bridge deletes audio in all success and failure paths;
6. the watch shows the transcript;
7. the user edits, sends, cancels, or records again.

No transcript is automatically sent to Codex.

### Folders and workspaces

The bridge defaults to user-approved workspace roots selected in the Mac app.
The watch can browse directories only below those roots and cannot read file
contents. Symlink and canonical-path checks prevent traversal outside a root.

An advanced “all readable folders” mode is available with a clear warning. It
still cannot bypass macOS privacy permissions.

### Models and permissions

Models and reasoning efforts come from the currently installed Codex adapter.
Relay does not ship a hard-coded model list. New-task permission profiles are
named, explained presets mapped to current Codex capabilities; unsafe or
unsupported combinations are not offered.

## Connectivity and background behavior

The foreground app opens an authenticated resumable WebSocket. Events carry
monotonically increasing IDs. Reconnection resumes after the last received ID
within a bounded retention window; otherwise the watch requests a new snapshot.

Wear OS may defer background networking to preserve battery. Relay therefore
does not promise an invisible permanent socket.

Version 1 provides:

- real-time events whenever the application is open;
- an optional user-started Live Monitoring session with a foreground service,
  ongoing activity, and visible watch indicator;
- an automatic four-hour maximum for a Live Monitoring session;
- a low-battery cutoff;
- battery-aware periodic refresh through WorkManager when Live Monitoring is
  off;
- no Relay-operated Firebase or cloud push service.

The ongoing activity opens the inbox or active task. The settings screen shows
the expected battery trade-off before Live Monitoring starts.

## Data and persistence

### Mac

SQLite stores:

- paired device public keys and labels;
- device revocation and approval policy;
- consumed nonces within the replay window;
- idempotency results;
- bounded event sequence and resume data;
- redacted audit events;
- user-facing task aliases;
- workspace root bookmarks and policy metadata.

The database does not duplicate repository files, Codex conversation history,
raw command output, prompts, or audio.

Secrets such as the optional OpenAI key are stored in macOS Keychain, never in
SQLite, logs, release artifacts, or the watch.

### Watch

The watch stores:

- a non-exportable signing key in Android Keystore;
- device ID and Relay origin;
- last event sequence;
- connection preferences;
- minimal task summaries needed for stale offline rendering.

Unpairing deletes the local credential and cache.

## Security

### Pairing

1. The Mac app asks the bridge for a six-character code valid for five minutes.
2. The watch creates a non-exportable signing key.
3. The watch submits the code and public key.
4. The Mac displays the watch model and key fingerprint for confirmation.
5. The bridge stores the public key and returns the device identity and Funnel
   origin.

Pairing attempts have strict per-origin and global limits. No private task data
is returned during pairing.

### Authenticated requests

Each request includes device ID, timestamp, nonce, body digest, and a signature
over the canonical method and path. The bridge rejects an unknown device, stale
timestamp, reused nonce, invalid signature, invalid body digest, or revoked
device before loading private data.

Every state-changing action includes an idempotency key. Repeated taps return the
original result instead of executing twice.

### Public ingress

Funnel forwards only to the loopback bridge. Funnel identity headers are not
trusted as watch authentication. Unauthenticated responses reveal no task,
model, workspace, device, or Mac identity metadata.

The Mac app cannot enable Funnel until local tests confirm loopback binding,
authentication, replay rejection, and generic unauthorized responses.

### Logging

Logs redact credentials, prompts, command output, authorization headers, audio,
and file contents. Audit records keep only the device, action type, target,
decision, timestamp, risk class, and success or failure result.

## Error handling

| Failure | User-visible behavior | Safety behavior |
| --- | --- | --- |
| Mac asleep or offline | Stale badge and last-seen time | No action is queued |
| Tailscale or Funnel stopped | Remote access unavailable | Bridge remains loopback-only |
| Codex unavailable | Setup or reconnect instruction | Controls are disabled |
| Protocol mismatch | Exact compatibility message | Unsupported action is hidden |
| WebSocket lost | Backoff, resume, then snapshot | No duplicate event delivery |
| Duplicate action | Original result shown | Idempotency prevents repetition |
| Approval expired | Expired state and refresh | Decision is not retried |
| Watch revoked | Re-pair screen | Cached private data is deleted |
| Workspace denied | Folder-specific explanation | No privacy bypass attempt |
| Transcription failed | Retry or use system input | Audio is deleted |
| Update required | Read-only compatibility screen | Unsafe old protocol is blocked |
| Low watch battery | Live Monitoring stops | Periodic refresh remains |
| ADB setup failed | Exact failed step and copyable help | No shell command is guessed |

## Installation and update design

### GitHub Release assets

Each public release contains:

- notarized Apple silicon `Relay.dmg`;
- signed Wear OS `relay-wear.apk`;
- checksums and signed update metadata;
- source archive;
- Apache 2.0 license and third-party notices;
- release notes, supported Codex range, and compatibility matrix.

The DMG bundles the bridge sidecar and the matching APK. The Mac application and
all nested executable code are signed consistently before notarization.

### Mac updates

The application checks signed GitHub release metadata and offers an update. It
never installs a downgrade or an artifact with an invalid signature. A failed
update keeps the previous working application.

### Watch updates

Because version 1 is GitHub-only, watch installation and update require Wireless
ADB on the same local network. The Mac wizard reconnects, runs
`adb install -r`, verifies the installed package version, and preserves watch
pairing data when the Android signature is unchanged.

Relay does not claim background or silent APK updates.

### Release prerequisites

A public easy-install release requires:

- Apple Developer ID signing and successful notarization;
- a protected and backed-up Android signing key;
- protected update-signing material;
- release automation that never exposes credentials;
- a clean source tag matching every distributed artifact.

## Testing strategy

### Automated bridge tests

- Codex mapping fixtures and compatibility errors.
- Pairing expiry and attempt limits.
- Valid and invalid signatures.
- Timestamp skew and nonce replay.
- Device revocation.
- Idempotent approvals, questions, instructions, stop, and new task.
- Workspace canonicalization, symlinks, pagination, and permission denial.
- Event ordering, retention, resume, and snapshot fallback.
- Transcription size, duration, deletion, timeout, and provider errors.
- Redacted logs and generic unauthenticated responses.

### Automated watch tests

- Reducer and state transition tests.
- Request canonicalization against shared fixtures.
- Pairing and revocation state.
- Reconnect and event resume.
- Approval confirmation policy.
- Navigation for every screen and empty/error state.
- Accessibility labels and minimum touch targets where testable.

### Mac application tests

- First-run state machine.
- Bridge process lifecycle and crash recovery.
- Codex and Tailscale detection.
- Platform Tools verification.
- ADB discovery, manual fallback, install, update, and error parsing.
- Device and workspace administration through the private local channel.
- Funnel preflight, enable, disable, and emergency stop.
- Keychain reads and writes without value logging.
- Release signature and update rollback.

### Physical device matrix

Galaxy Watch6 is the release gate. It must pass:

- install and upgrade from the Mac wizard;
- round-screen safe areas and rotary navigation;
- default and large text;
- Wi-Fi and, when available, LTE;
- foreground real-time events;
- background Live Monitoring and periodic refresh;
- connection switching, Mac sleep, and bridge restart;
- approval, deny, question, instruction, voice, stop, and new task;
- lost-watch revocation;
- one-hour battery observation in normal mode and Live Monitoring;
- accessibility and haptic behavior.

Other Wear OS 4+ round watches enter the matrix only with a documented physical
result. The release page distinguishes project-tested from community-tested.

## Release acceptance criteria

Version 1 is ready when:

1. A clean Apple silicon Mac can install the notarized DMG without development
   toolchains.
2. The first-run wizard reaches a healthy state using plain-language steps.
3. A reset Galaxy Watch6 can be installed and paired using only the Mac wizard.
4. The watch can discover an existing Codex task through Funnel.
5. The watch can handle one normal and one dangerous approval with the correct
   confirmation policy.
6. Questions, instructions, both voice modes, steering, stopping, and new-task
   creation work end to end.
7. Workspace boundaries, replay rejection, revocation, and generic
   unauthenticated responses pass adversarial tests.
8. Live Monitoring behavior and its battery cost are visible and documented.
9. Mac and APK update paths are proven without losing pairing state.
10. The release tag, source, checksums, DMG, APK, license, and notes agree.

## Implementation decomposition

The public release is built as five independently verifiable verticals:

1. **Security and live transport** — complete authentication, event resume,
   workspace boundaries, risk policy, and optional Live Monitoring.
2. **Complete watch product** — implement all watch flows, both voice modes, and
   physical Watch6 validation.
3. **Native Mac control plane** — SwiftUI menu app, bundled bridge lifecycle,
   Keychain, setup, devices, workspaces, and diagnostics.
4. **One-click installation and remote access** — Platform Tools, Wireless ADB,
   APK installation, Tailscale preflight, Funnel, and recovery.
5. **Release engineering** — signing, notarization, updates, license,
   compatibility matrix, GitHub automation, and release acceptance.

Each vertical has automated tests and a manual gate. Remote ingress remains
disabled until the security vertical passes. Public release remains blocked
until the physical Galaxy Watch6 and clean-Mac installation gates pass.

## Repository transition

The existing MVP remains the starting point:

- retain and harden the TypeScript bridge and Codex adapter;
- refactor the current monolithic watch UI into screen-focused components;
- replace HTTP polling with the designed resumable live path while preserving a
  safe refresh fallback;
- revise the old single-tap-all and unrestricted-folder defaults;
- add the SwiftUI Mac application as a new workspace;
- replace LaunchAgent-first setup with menu-app lifecycle management;
- update README, setup, security, physical-test, and release documentation to
  match this specification.

No unrelated refactor is part of the release.
