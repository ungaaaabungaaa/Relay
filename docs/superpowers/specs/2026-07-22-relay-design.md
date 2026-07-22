# Relay Design Specification

Date: 2026-07-22  
Status: Approved interaction design; implementation pending

## Goal

Build a small, native Wear OS application for a Wi-Fi Samsung Galaxy Watch6 that remotely monitors and controls Codex tasks already running in the Codex desktop application on a MacBook. It must work on any usable Wi-Fi network while the Mac is awake and online. Development and validation use only the physical watch; no emulator is required.

## Scope

The MVP supports:

1. Live task monitoring and concise recent activity.
2. One-tap approve or deny for every Codex approval class.
3. Answers to Codex questions.
4. Voice instructions recorded on the watch, transcribed through OpenAI on the Mac, reviewed on the watch, and sent to a task.
5. Browsing all Mac folders accessible to the bridge process.
6. Selecting a currently available model and reasoning effort.
7. Creating, steering, and stopping tasks.
8. Pairing, reconnection, settings, revocation, and approval history.

The MVP does not include an Android or iPhone companion, an Android emulator, a hosted application database, multi-user accounts, Play Store distribution, or offline action queueing.

## Architecture

The Galaxy Watch6 connects over HTTPS and WebSocket to a Tailscale Funnel address. Funnel terminates public TLS and proxies to a Mac bridge bound only to `127.0.0.1`. The bridge authenticates the paired watch, translates its narrow API into Codex app-server operations, calls OpenAI speech-to-text, performs on-demand directory browsing, and writes a local audit log.

Tailscale's supported Android documentation does not establish a Wear OS client. The design therefore does not depend on sideloading Tailscale onto the watch. Funnel is transport, not identity: the endpoint is publicly reachable and all authorization is enforced by the bridge.

The Codex app-server surface is experimental in the installed Codex CLI. All protocol calls live behind a version-aware adapter. A local protocol spike is the first implementation gate; unsupported capabilities must be reported rather than emulated through desktop UI automation.

## Components

### Wear OS app

A Kotlin and Jetpack Compose for Wear OS application. It owns presentation, microphone capture, pairing keys, request signing, reconnection, and a minimal stale cache. It contains no OpenAI or Codex secret.

### Mac bridge

A TypeScript service managed by a macOS LaunchAgent. It owns pairing, authentication, replay protection, rate limits, task/event translation, folder enumeration, transcription, audit logging, and Funnel-facing HTTP/WebSocket endpoints. It listens on localhost only.

### Codex adapter

A focused module around the local Codex app-server protocol. It maps version-sensitive protocol messages into stable Relay concepts: task, activity, approval, question, capability, model, effort, and action result.

### Local store

SQLite stores paired-device public keys, revocation state, used nonces, audit events, resumable event sequence numbers, and user-facing task aliases. It does not duplicate repositories, prompts, raw audio, or Codex conversation history.

## Data flows

### Pairing

The Mac bridge emits a six-character code valid for five minutes. The watch creates a non-exportable signing key and exchanges the code plus public key for a device identity and Funnel origin. The bridge stores only the public key. Pairing attempts are rate-limited.

### Monitoring

The watch opens a short-lived authenticated WebSocket session. Bridge events have monotonically increasing IDs. After interruption, the watch reconnects with its last received ID and obtains missed events within a bounded retention window; otherwise it requests a fresh snapshot.

### Approval

The bridge maps a Codex approval to an immutable action ID and shows its exact command or operation, working directory, risk label, and declared effects. Approve and deny requests include idempotency keys. Per the user's explicit choice, both are single-tap and no additional PIN challenge is added.

### Voice

The user presses and holds to record, then releases. The watch uploads a size- and duration-limited recording to the authenticated bridge. The bridge calls OpenAI speech-to-text and deletes the audio immediately after completion or failure. The watch always displays the transcript before the user sends it.

### Folders and new tasks

Directory listings are fetched on demand and paginated. The bridge returns names, paths, and entry types but not file contents. macOS permission errors are explicit. Model and reasoning choices come from current Codex capabilities rather than a hard-coded list. A final review screen shows folder, model, effort, and prompt before task creation.

## Visual design

The approved direction is a Next.js/Vercel-inspired native Compose system: near-black circular surfaces, white primary controls, fine gray dividers, compact pill actions, code-forward typography, and sparse semantic color. It is an original Wear OS implementation, not a web theme or React dependency.

The interface is icon-first. Text remains for commands, task names, folder names, model names, questions, transcripts, errors, and risk consequences where icons alone would be ambiguous or unsafe. Production uses consistent vector icons with accessibility labels, not Unicode glyphs.

Every screen uses a circular inner safe zone sized for the Galaxy Watch6. Primary actions remain fully inside that zone. Longer lists use rotary scrolling and a subtle position indicator.

Approved screens:

1. Pairing
2. Offline/reconnecting
3. Action inbox
4. Approval detail
5. Codex question
6. Task list
7. Task detail
8. Voice recording
9. Transcript review
10. Folder browser
11. Model and reasoning selector
12. New-task review
13. Settings
14. Approval history

## Failure handling

- Offline watch or Mac: show stale/offline state and do not queue approvals or commands.
- WebSocket loss: reconnect with exponential backoff and resume from the last event ID.
- Duplicate tap: idempotency key returns the original result.
- Expired approval: show that Codex no longer accepts the decision and refresh the task.
- Codex protocol mismatch: disable the affected operation and show an upgrade/compatibility error.
- Transcription failure: preserve no server audio, show a retry/re-record choice, and never send partial text automatically.
- macOS permission denial: identify the inaccessible folder without attempting to bypass system privacy controls.
- Mac sleep: show offline; waking the Mac remotely is outside the MVP.

## Security

The watch has full approval authority and folder visibility matching the bridge process. This power is intentional. The bridge requires per-device public-key authentication, signed requests, timestamp and nonce replay protection, short WebSocket sessions, idempotency, rate limits, redacted logs, and auditable actions. Unauthenticated responses expose no task or folder metadata.

Full requirements and emergency procedures are in `docs/SECURITY.md`.

## Validation

All UI and end-to-end checks run on the physical Galaxy Watch6 over wireless ADB. Unit tests cover bridge policy, signatures, replay rejection, idempotency, adapter mapping, and reducers. Integration tests use a fake Codex adapter and fake transcription provider. A gated local smoke test exercises the installed Codex app-server with harmless commands. Remote tests occur only after authentication tests pass and Funnel is enabled.

Acceptance requires a real end-to-end demonstration of task discovery, approval, question response, voice transcript review, steering, stop, folder selection, model selection, new-task creation, reconnect, credential revocation, and an unauthenticated access rejection.

## Implementation boundaries

- Do not automate Codex desktop clicks or scrape its UI.
- Do not embed OpenAI or Codex credentials in the APK.
- Do not expose the bridge directly on LAN or public interfaces.
- Do not enable Funnel before authentication and replay tests pass.
- Do not store raw recordings.
- Do not install or require an Android emulator.
- Do not promise a Codex operation until the protocol spike proves it against the installed version.

