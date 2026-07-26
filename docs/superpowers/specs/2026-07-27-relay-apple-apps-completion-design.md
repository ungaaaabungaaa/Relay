# Relay Apple Apps Completion Design

**Date:** 2026-07-27  
**Status:** Approved product direction; implementation contract

## Goal

Finish the visible Relay Mac app and native Apple Watch app to a
source-complete, locally testable prototype. Relay Cloud remains the opaque,
end-to-end encrypted transport between the watch and the Mac. The Mac bridge
continues to control Codex through `codex app-server` on the user's Mac.

## Product boundary

Relay ships as two visible Apple applications:

- a macOS 14+ menu-bar and dashboard app for Apple-silicon Macs;
- an independent watchOS 10+ Apple Watch app.

The repository retains Relay Cloud, the embedded Node bridge, and the shared
protocol packages. This work does not add Android, Wear OS, a Codex plugin, or
an iPhone companion experience.

Source completion does not include Apple signing credentials, notarization,
TestFlight processing, App Store approval, production Cloudflare or Resend
ownership, or physical-device evidence. The release checklist must keep those
items as external gates.

## Existing foundation

The Mac app already supervises the embedded bridge, stores credentials in
Keychain, signs users in through Relay Cloud, manages pairing and workspaces,
and exposes Emergency Stop and account deletion. The bridge already provides
authenticated routes for task reads, task creation and control, approvals,
questions, transcription, models, folders, and live events.

The Watch already creates device identities, completes six-character cloud
pairing, derives the envelope key, signs inner requests, encrypts tunnel
messages, and stores scoped credentials. Its destination screens still show
preview data and do not invoke the bridge actions.

## Architecture

```text
Relay Watch SwiftUI views
        |
RelayWatchModel and typed feature state
        |
RelayAPIClient response router and event stream
        |
signed request inside an AES-256-GCM envelope
        |
Relay Cloud Worker, D1, and Durable Object tunnel
        |
Relay Mac outbound WebSocket tunnel
        |
loopback Relay bridge and Codex adapter
        |
codex app-server
```

Relay Cloud routes ciphertext and account or device metadata. It must not gain
the ability to decrypt task content. The Watch and Mac retain their existing
root-key, signing, replay, workspace, idempotency, and approval boundaries.

## Watch application

### Typed state and responses

The Watch client will decode bridge responses into explicit Swift types for:

- paginated tasks and task detail;
- pending approvals and questions;
- models and model effort choices;
- workspace folders;
- Relay events and activity history;
- transcription results and mutation acknowledgements.

`RelayWatchModel` will own user-visible state, selected task and inbox item,
editable drafts, activity entries, loading state, mutation state, and errors.
Views will render model data. Preview fixtures may remain in SwiftUI previews,
but runtime screens may not use them.

### Response and event transport

`RelayAPIClient` will maintain one authenticated device WebSocket while the
app is active. A receive loop will decrypt each envelope, validate its replay
sequence, then route responses by request identifier or publish typed events.
Concurrent requests must not consume one another's responses.

The client will reconnect after recoverable network failures with capped
backoff. It will refresh the inbox and task snapshots after reconnection. The
model will mark cached data stale as soon as the connection drops. Mutations
remain disabled while state is stale or the Mac is unavailable, and Relay
must not queue them for later delivery.

An authenticated 401 or 403 response from the bridge or cloud will revoke the
local session. The Watch will close the socket and erase the cloud credential,
root key, signing identity, agreement identity, and replay counters.

### Pairing

The Watch will separate pairing into these steps:

1. submit the six-character code and device identity;
2. display the Mac fingerprint;
3. require the user to confirm that the Mac shows the same fingerprint;
4. poll while the Mac user reviews the Watch fingerprint;
5. store the scoped credential only after approval.

Cancel and expiry return to an unpaired state without leaving pairing material
or an active socket.

### Inbox, tasks, and actions

The Watch will support these real flows:

- list approvals and questions, then open one item;
- deny any approval and approve a normal-risk action;
- require a second confirmation for dangerous approvals;
- answer each question using only the options returned by Codex;
- list tasks, open task detail, inspect recent activity, and stop a running
  turn after confirmation;
- send an instruction to an idle task or steer its current turn;
- choose an allowed workspace, model, effort, and prompt before creating a
  task;
- refresh activity from snapshots and pushed events.

Each mutation will create one idempotency key and retain it for retries of the
same in-flight action. A new user action receives a new key. The UI will show
success or failure and prevent duplicate taps while a request is pending.

### Voice

The Watch will record up to 30 seconds of audio with an explicit start and stop
control. It will send ordered encrypted chunks through the existing voice
tunnel, receive the Mac transcription, and show an editable transcript. The
user must tap Send before Relay submits the text as an instruction or new-task
prompt. Cancel deletes the local audio and transcript.

Relay will stop recording when the app becomes inactive, the connection drops,
or the duration limit expires. It will delete temporary audio after success,
cancel, or failure. The UI will disclose that the configured transcription
provider processes the recording on the Mac.

### Accessibility and feedback

Controls will use explicit accessibility labels and hints where an icon or
short Watch label lacks context. Destructive and approval actions will expose
their consequence. Relay will use Watch haptics for success, failure, and
dangerous-confirmation prompts. Layouts must support system text sizing and
avoid fixed-height text containers.

## Mac application

The Mac app will keep its current visible menu-bar and dashboard experience.
This completion pass will add:

- observable cloud tunnel phases and the most recent safe failure reason;
- capped reconnect with status changes reflected without a manual refresh;
- recovery of pending pairing requests after a tunnel replacement where the
  cloud API supports retrieval;
- confirmation dialogs for Emergency Stop and account deletion;
- accurate update states: unknown, checking, current, available, and failed;
- development endpoint configuration that both HTTP and WebSocket clients use;
- diagnostics that identify production, staging, or local development without
  printing hosts, tokens, account identifiers, or task content.

The app will continue to store secrets in Keychain and bind its admin and Watch
bridge listeners to loopback addresses. Debug endpoint configuration may come
from a checked build setting or process environment. Release builds must accept
only the production HTTPS and WSS origins compiled into the app.

## Development and local testing

The repository will provide a secret-free development path with two layers.

### Deterministic automated integration

Tests will run a real bridge request handler, Relay encryption adapters, and a
fake Codex adapter in process. A Watch transport fixture will exercise pairing
material, snapshots, each mutation, pushed events, disconnect and reconnect,
revocation, Emergency Stop behavior, and voice chunk assembly. Tests will use
temporary stores and disposable keys.

### Interactive Apple testing

Debug builds will accept a development Relay Cloud origin. The Mac app and
Watch target must use the same environment. A Watch simulator can use a local
reachable endpoint when the required Xcode runtime exists. A physical Watch
requires a TLS endpoint reachable from the device, so developers must use a
staging Worker or an approved secure tunnel to a local Worker.

The local testing checklist will contain exact commands for JavaScript tests,
type checks, bridge packaging and smoke tests, Mac Swift tests and launch,
Watch Swift tests and source checks, the unsigned generic Watch build, and the
interactive product journey. It will separate code checks from signed-device
and production release evidence.

## Error handling

The Watch and Mac will show short user-facing errors while retaining structured,
redacted diagnostic categories. Relay must distinguish authentication or
revocation, incompatibility, offline transport, stale state, rejected actions,
and server failures.

Relay will fail closed for approvals, destructive controls, workspace access,
invalid response shapes, replayed envelopes, missing idempotency keys, and
version incompatibility. Network recovery may refresh reads. It may not replay
a mutation unless the retry uses the same idempotency key for the same action.

## Test strategy

Implementation will use test-driven development for state reducers, response
routing, request creation, reconnect policy, revocation, mutation guards,
pairing confirmation, and voice lifecycle. Each test will assert observable
behavior against real types. Network, Keychain, audio hardware, and Codex
process boundaries may use narrow injected adapters.

The final verification run will include:

```bash
pnpm test
pnpm typecheck
pnpm build:bridge-sea
pnpm smoke:bridge-sea
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apple-watch/RelayWatch.xcodeproj \
  -scheme RelayWatch \
  -configuration Debug \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /private/tmp/relay-watch-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The report will record any missing local Xcode runtime, signing identity,
physical device, cloud credential, or external account as an unverified gate.
It will not reinterpret those gates as passing.

## Documentation outcome

`README.md`, `docs/SETUP.md`, `apple-watch/README.md`, and `docs/TODO.md` will
describe the implemented runtime instead of preview destinations. The TODO
list will use four sections: automated local checks, interactive local or
staging checks, Apple distribution and physical-device checks, and ownership
or security review gates.

## Acceptance criteria

The source-complete milestone requires all of the following:

- runtime Watch screens render decoded bridge data and invoke real routes;
- the Watch handles responses and pushed events on one encrypted connection;
- stale or offline state blocks mutations without an offline queue;
- pairing requires fingerprint confirmation on both devices;
- voice supports record, transcribe, edit, send, and cancel;
- revocation removes credentials and prevents further access;
- the Mac exposes actionable tunnel, pairing, update, and destructive-action
  states;
- debug builds can target a non-production environment;
- automated tests cover the Apple-client state and encrypted integration path;
- documentation gives the developer exact local checks and labels external
  evidence as pending.

