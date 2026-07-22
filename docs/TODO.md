# Relay Build Checklist

The order is deliberate: prove Codex task control before investing in the complete watch UI, and prove authentication before opening Funnel.

## Phase 0 — Developer setup

- [ ] Install Android Studio without emulator components.
- [ ] Install Android SDK Platform Tools.
- [ ] Pair the Galaxy Watch6 to `adb` over local Wi-Fi.
- [ ] Install and sign into Tailscale on the Mac.
- [ ] Initialize environment files from committed examples without adding secrets to Git.
- [ ] Confirm the Mac stays awake while a task is running.

## Phase 1 — Codex protocol spike

- [ ] Generate or inspect the installed Codex app-server schema.
- [ ] Connect a disposable localhost client to Codex app-server.
- [ ] List existing desktop tasks and confirm stable task identifiers.
- [ ] Subscribe to task/turn updates.
- [ ] Detect approval requests and questions.
- [ ] Approve and deny a harmless test command.
- [ ] Send a follow-up instruction to an existing task.
- [ ] Enumerate currently available models and reasoning efforts.
- [ ] Start a task with a selected working directory.
- [ ] Stop a running task.
- [ ] Document unsupported or version-sensitive operations behind a compatibility adapter.

**Exit gate:** do not build remote ingress until existing Codex desktop tasks can be observed and controlled locally.

## Phase 2 — Mac bridge foundation

- [ ] Create the TypeScript bridge package.
- [ ] Bind HTTP/WebSocket only to `127.0.0.1`.
- [ ] Implement health and version endpoints with no private metadata.
- [ ] Add the Codex compatibility adapter.
- [ ] Add resumable event streaming with monotonically increasing event IDs.
- [ ] Add a SQLite store for paired devices, nonces, task aliases, and audit events.
- [ ] Add structured logs with secret and prompt redaction.
- [ ] Add a macOS LaunchAgent definition and clean start/stop/status commands.

## Phase 3 — Pairing and security

- [ ] Generate six-character pairing codes that expire after five minutes.
- [ ] Exchange the code for a device-specific public-key credential.
- [ ] Store the watch private key in Android Keystore.
- [ ] Sign every request with method, path, body digest, timestamp, and nonce.
- [ ] Reject expired timestamps, replayed nonces, invalid signatures, and unknown devices.
- [ ] Add short-lived WebSocket session tokens.
- [ ] Rate-limit pairing, authentication failures, audio uploads, and actions.
- [ ] Add local pair/list/revoke commands.
- [ ] Record every approve, deny, stop, send, and new-task action in the audit log.
- [ ] Confirm that an unpaired client cannot infer task names, folder names, models, or status.

## Phase 4 — Bridge API

- [ ] Task list and task detail endpoints.
- [ ] Resumable live event stream.
- [ ] Approval and denial endpoint with idempotency keys.
- [ ] Question-answer endpoint.
- [ ] Follow-up/steer endpoint.
- [ ] Stop-task endpoint.
- [ ] Directory listing endpoint with pagination and macOS permission errors.
- [ ] Model and reasoning-effort capability endpoint.
- [ ] New-task endpoint.
- [ ] Approval-history endpoint.
- [ ] OpenAI speech-to-text endpoint with duration and size limits.
- [ ] Delete audio immediately after transcription; do not persist raw recordings.

## Phase 5 — Wear OS shell and design system

- [ ] Create a Kotlin, Compose for Wear OS application module.
- [ ] Set the minimum SDK based on the Watch6 OS baseline selected during project creation.
- [ ] Implement the circular safe-area layout primitives.
- [ ] Add the monochrome, icon-first design tokens.
- [ ] Use Material Symbols or original vector icons; do not use ambiguous Unicode icons in production.
- [ ] Add rotary input and swipe navigation.
- [ ] Add haptics for received approvals, success, denial, and connection loss.
- [ ] Add accessible content descriptions and minimum touch targets.
- [ ] Verify every screen on the physical watch in light, dark, ambient, and large-font conditions where applicable.

## Phase 6 — Watch screens

- [ ] Pairing.
- [ ] Offline/reconnecting.
- [ ] Action inbox.
- [ ] Approval detail.
- [ ] Codex question.
- [ ] Task list.
- [ ] Task detail.
- [ ] Voice recording.
- [ ] Transcript review.
- [ ] Folder browser.
- [ ] Model and reasoning-effort chooser.
- [ ] New-task review.
- [ ] Settings and unpair.
- [ ] Approval history.

## Phase 7 — Voice

- [ ] Request watch microphone permission just in time.
- [ ] Implement press-and-hold recording.
- [ ] Encode a small, speech-appropriate audio payload.
- [ ] Upload only to the authenticated Mac bridge.
- [ ] Transcribe on the Mac with OpenAI speech-to-text.
- [ ] Always show transcript review before sending.
- [ ] Support cancel and re-record.
- [ ] Handle silence, oversized recordings, timeouts, quota errors, and unavailable Wi-Fi.

## Phase 8 — Tailscale Funnel

- [ ] Verify the bridge is still localhost-only.
- [ ] Run the complete unauthenticated and replay-attack test suite locally.
- [ ] Enable Funnel for the bridge port.
- [ ] Test from a second Wi-Fi network.
- [ ] Confirm TLS certificate validation on the watch.
- [ ] Confirm rate limits and credential revocation through Funnel.
- [ ] Add one-command Funnel disable and emergency watch revocation instructions.

## Phase 9 — Physical-watch validation

- [ ] Install the debug build with `adb`; no emulator.
- [ ] Check all controls remain inside the circular safe zone.
- [ ] Test crown/rotary scrolling on all long lists.
- [ ] Test disconnect/reconnect while switching Wi-Fi.
- [ ] Test duplicate taps and delayed responses.
- [ ] Test approval arrival while the app is foregrounded and backgrounded.
- [ ] Test an actual safe Codex approval, question, steer, stop, folder switch, model selection, and new task.
- [ ] Check battery use during one hour of monitoring.
- [ ] Turn off wireless debugging after validation.

## Phase 10 — Packaging

- [ ] Produce a signed release APK for personal sideloading.
- [ ] Keep signing keys outside Git and backed up securely.
- [ ] Add bridge install/uninstall/update commands.
- [ ] Add watch update instructions using `adb install -r`.
- [ ] Add recovery steps for lost watch, leaked pairing credential, and Mac replacement.
- [ ] Tag the first working end-to-end release.

