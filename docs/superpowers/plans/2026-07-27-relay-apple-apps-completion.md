# Relay Apple Apps Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the visible Relay Mac app and native Apple Watch app as a source-complete, locally testable prototype while retaining Relay Cloud and the loopback Codex bridge.

**Architecture:** The Watch uses typed Swift state and one encrypted WebSocket receive loop for response routing and pushed events. Relay Cloud routes ciphertext and account or device metadata, while the Mac app owns the outbound tunnel, bridge lifecycle, pairing approval, workspace policy, and destructive controls. The bridge exposes a small Watch-safe API instead of raw Codex protocol payloads.

**Tech Stack:** Swift 6, SwiftUI, watchOS 10+, macOS 14+, AVFoundation, CryptoKit, Security, Sparkle 2.9.2, Node.js 24, TypeScript 5.9, Cloudflare Workers, Durable Objects, D1, Node test runner, Swift Testing.

## Global Constraints

- Keep only the Apple-silicon macOS app, independent watchOS 10+ app, Relay Cloud, embedded bridge, and shared protocols.
- Do not add Android, Wear OS, an iPhone companion experience, or a Codex plugin.
- Relay Cloud must remain unable to decrypt Codex task content or voice audio.
- Keep the bridge admin and Watch listeners on `127.0.0.1` or `::1`.
- Store Mac and Watch credentials in Keychain-backed stores; never log tokens, pairing codes, fingerprints, account identifiers, task text, repository paths, commands, or audio.
- Mutations require a live, fresh connection and a 16-to-128-character idempotency key. Relay must not queue mutations while offline.
- A retry of one logical mutation retains its idempotency key. A new user action receives a new key.
- Dangerous approvals require a second Watch confirmation and bridge-side validation.
- Debug builds may use one checked development cloud origin. Release builds must ignore or reject endpoint overrides and use production HTTPS/WSS.
- Signing, notarization, TestFlight, App Store review, production account ownership, and physical-device evidence remain external gates.
- Use test-driven development: run each new behavior test and observe the expected failure before production changes.

---

### Task 1: Stabilize the Watch-safe bridge contract

**Files:**
- Modify: `apps/bridge/src/domain.ts`
- Modify: `apps/bridge/src/codex/mappers.ts`
- Modify: `apps/bridge/src/codex/adapter.ts`
- Create: `apps/bridge/src/watch-request-validation.ts`
- Modify: `apps/bridge/src/server.ts`
- Modify: `apps/bridge/test/codex-adapter.test.ts`
- Modify: `apps/bridge/test/server.test.ts`

**Interfaces:**
- Consumes: Codex `thread/read`, pending approval/question objects, `WorkspacePolicy`, and existing `ActionExecutor` idempotency handling.
- Produces: normalized task detail/activity and fail-closed mutation validation consumed by the Watch DTOs in Task 3.

```ts
export type RelayActivityEntry = {
  id: string;
  turnId: string;
  kind: "user" | "assistant" | "command" | "file" | "tool" | "status";
  title: string;
  detail: string | null;
  status: "pending" | "running" | "succeeded" | "failed" | "unknown";
  occurredAt: number | null;
};

export type RelayTaskDetail = RelayTask & {
  activeTurnId: string | null;
  activity: RelayActivityEntry[];
};

export function validateApprovalDecision(
  approval: RelayApproval,
  body: unknown,
): { decision: "approve" | "deny" };

export function validateQuestionAnswers(
  question: RelayQuestion,
  body: unknown,
): Record<string, string[]>;

export function validateNewTaskInput(
  body: unknown,
  models: RelayModel[],
): { cwd: string; model: string; effort: string; prompt: string };
```

- [ ] **Step 1: Write failing mapper and validator tests**

Add literal fixtures proving that task detail returns at most the newest 50 safe activity entries, preserves the active turn identifier, rejects unknown question options, rejects unknown model/effort combinations, and requires `dangerousConfirmation: true` for dangerous approval.

```ts
it("requires explicit dangerous approval confirmation", () => {
  assert.throws(
    () => validateApprovalDecision(dangerousApproval, { decision: "approve" }),
    /confirmation required/,
  );
  assert.deepEqual(
    validateApprovalDecision(dangerousApproval, {
      decision: "approve",
      dangerousConfirmation: true,
    }),
    { decision: "approve" },
  );
});
```

- [ ] **Step 2: Run the focused tests and confirm the new assertions fail**

Run:

```bash
node --test apps/bridge/test/codex-adapter.test.ts apps/bridge/test/server.test.ts
```

Expected: failures name missing `mapThreadDetail` or validation exports and show that current routes accept unsafe bodies.

- [ ] **Step 3: Implement normalized task detail and request validation**

Map user/assistant text, commands without aggregated output, file changes, and tool/status entries. Use turn timestamps when present and `null` otherwise. Return stable mutation acknowledgements:

```ts
{ ok: true }
{ taskId: string }
{ turnId: string }
```

Validate body shapes before invoking Codex. Load `/v1/models` choices before accepting new-task model and effort. Keep workspace validation in `WorkspacePolicy`.

- [ ] **Step 4: Run focused tests, then the bridge suite**

Run:

```bash
node --test apps/bridge/test/codex-adapter.test.ts apps/bridge/test/server.test.ts
pnpm test
```

Expected: all tests pass and invalid bodies never increment fake Codex call counts.

- [ ] **Step 5: Commit the bridge contract**

```bash
git add apps/bridge/src/domain.ts apps/bridge/src/codex/mappers.ts apps/bridge/src/codex/adapter.ts apps/bridge/src/watch-request-validation.ts apps/bridge/src/server.ts apps/bridge/test/codex-adapter.test.ts apps/bridge/test/server.test.ts
git commit -m "feat: stabilize Watch bridge contract"
```

---

### Task 2: Build the deterministic encrypted Apple-client harness

**Files:**
- Create: `apps/bridge/test/support/fake-codex-adapter.ts`
- Create: `apps/bridge/test/support/watch-transport-fixture.ts`
- Create: `apps/bridge/test/apple-client-integration.test.ts`
- Modify: `apps/bridge/src/cloud/bridge-cloud-runtime.ts`
- Modify: `apps/bridge/src/cloud/cloud-tunnel-adapter.ts`
- Modify: `apps/bridge/test/bridge-cloud-runtime.test.ts`
- Modify: `apps/bridge/test/cloud-tunnel-adapter.test.ts`

**Interfaces:**
- Consumes: Task 1 bridge contract, `createRequestHandler`, `BridgeCloudRuntime`, `CloudTunnelAdapter`, `EventHub`, and `packages/cloud-protocol`.
- Produces: a reusable ciphertext-only Watch fixture and explicit runtime cleanup seams used for end-to-end verification.

```ts
export class WatchTransportFixture {
  static create(input: WatchFixtureInput): Promise<WatchTransportFixture>;
  request(input: WatchRequestInput): Promise<{ status: number; body: unknown }>;
  sendVoice(input: WatchVoiceInput): Promise<{ status: number; body: unknown }>;
  drainEvents(): Promise<RelayEvent[]>;
  disconnect(): void;
  reconnect(): void;
  revoke(): void;
}
```

- [ ] **Step 1: Write the failing encrypted journey tests**

Cover task/inbox/model/folder snapshots, every mutation exactly once, an event interleaved with a response, disconnect without queued mutation, reconnect snapshot refresh, revocation, Emergency Stop, replay rejection, conflicting idempotency reuse, and ordered voice chunks.

```ts
it("does not queue a disconnected mutation", async () => {
  const fixture = await WatchTransportFixture.create(testInput);
  fixture.disconnect();
  await assert.rejects(
    fixture.request({
      method: "POST",
      path: "/v1/tasks/task-1/stop",
      body: { turnId: "turn-1" },
      idempotencyKey: "stop-task-1-turn-1",
    }),
    /offline/,
  );
  assert.equal(fakeCodex.calls.length, 0);
});
```

- [ ] **Step 2: Run the new test and confirm the fixture/runtime seams are absent**

Run:

```bash
node --test apps/bridge/test/apple-client-integration.test.ts
```

Expected: failure reports missing support modules or missing runtime cleanup methods.

- [ ] **Step 3: Implement disposable identities, ciphertext routing, and cleanup**

Generate P-256 signing/agreement keys per fixture, derive one AES root key per device, use the real canonical signature and envelope functions, and store sequences in temporary stores. Add `close()` and `removeDevice(deviceId)` only where production lifecycle ownership requires them. `close()` must clear partial voice transfers, pending encrypted events, root keys, registrations, and adapters.

- [ ] **Step 4: Run focused encryption tests and typecheck**

Run:

```bash
node --test apps/bridge/test/apple-client-integration.test.ts apps/bridge/test/cloud-tunnel-adapter.test.ts apps/bridge/test/bridge-cloud-runtime.test.ts
pnpm typecheck
```

Expected: tests pass without hanging sockets or temporary audio state.

- [ ] **Step 5: Commit the integration harness**

```bash
git add apps/bridge/src/cloud apps/bridge/test/support apps/bridge/test/apple-client-integration.test.ts apps/bridge/test/bridge-cloud-runtime.test.ts apps/bridge/test/cloud-tunnel-adapter.test.ts
git commit -m "test: cover encrypted Apple client journey"
```

---

### Task 3: Add Watch DTOs, endpoints, and debug environment selection

**Files:**
- Create: `apple-watch/RelayWatch/RelayWatchTypes.swift`
- Create: `apple-watch/RelayWatch/RelayEndpoint.swift`
- Create: `apple-watch/RelayWatch/RelayEnvironment.swift`
- Modify: `apple-watch/Package.swift`
- Modify: `apple-watch/RelayWatch.xcodeproj/project.pbxproj`
- Modify: `scripts/check-watchos-source.sh`
- Create: `apple-watch/Tests/RelayWatchContractTests.swift`
- Modify: `apple-watch/test/project.test.mjs`

**Interfaces:**
- Consumes: Task 1 JSON contract.
- Produces: `Codable`, `Equatable`, `Sendable` Watch types and typed endpoints consumed by Tasks 4 through 7.

```swift
struct RelayPage<Element: Codable & Sendable>: Codable, Sendable {
    let data: [Element]
    let nextCursor: String?
}

struct RelayEndpoint<Response: Decodable & Sendable>: Sendable {
    let method: String
    let path: String
    let body: Data
    let isMutation: Bool
}

struct RelayEnvironment: Equatable, Sendable {
    enum Name: String, Sendable { case production, staging, localDevelopment }
    let name: Name
    let httpOrigin: URL
    let webSocketOrigin: URL
}
```

- [ ] **Step 1: Write failing decoding, endpoint, and environment tests**

Use literal bridge JSON. Assert malformed approval risks fail decoding, question answers can only reference decoded options, mutation endpoints mark `isMutation`, and one debug origin derives matched HTTP/WebSocket origins.

```swift
@Test func releaseConfigurationRejectsDevelopmentOverride() throws {
    #expect(throws: RelayEnvironmentError.releaseOverrideForbidden) {
        try RelayEnvironment.resolve(
            processEnvironment: ["RELAY_CLOUD_ORIGIN": "http://127.0.0.1:8787"],
            isDebugBuild: false
        )
    }
}
```

- [ ] **Step 2: Run the Watch contract tests and observe missing-type failures**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch --filter RelayWatchContractTests
node --test apple-watch/test/project.test.mjs
```

Expected: Swift cannot find the new contract types and the project contract lacks the new sources.

- [ ] **Step 3: Implement types and fail-closed endpoint selection**

Add task summary/detail, activity, inbox, approval, question, model, folder, event, transcription, and mutation acknowledgement types. `RelayEnvironment.resolve` must reject credentials, query strings, fragments, and non-root paths; it may accept plaintext only for loopback debug origins. Release builds use compiled production origins.

- [ ] **Step 4: Add each source to SwiftPM, Xcode, and the source-check script**

Use unique PBX object IDs and include all new non-UI types in `RelayWatchCore`. Extend `project.test.mjs` to parse the project and verify source membership instead of matching an exact source line.

- [ ] **Step 5: Run focused tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch --filter RelayWatchContractTests
node --test apple-watch/test/project.test.mjs
git add apple-watch scripts/check-watchos-source.sh
git commit -m "feat: define Watch runtime contract"
```

---

### Task 4: Replace per-request socket reads with one response and event router

**Files:**
- Create: `apple-watch/RelayWatch/RelaySocket.swift`
- Create: `apple-watch/RelayWatch/RelayReconnectPolicy.swift`
- Modify: `apple-watch/RelayWatch/RelayAPIClient.swift`
- Modify: `apple-watch/RelayWatch/RelayProtocol.swift`
- Modify: `apple-watch/RelayWatch/WatchIdentity.swift`
- Create: `apple-watch/Tests/RelayAPIClientTests.swift`
- Modify: `apple-watch/Package.swift`
- Modify: `apple-watch/RelayWatch.xcodeproj/project.pbxproj`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Consumes: Task 3 endpoints, environment, envelope types, signing identity, and cloud device store.
- Produces: one actor-owned receive loop and event stream consumed by Task 5.

```swift
protocol RelaySocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

protocol RelaySocketFactory: Sendable {
    func connect(_ request: URLRequest) async throws -> any RelaySocket
}

enum RelayTransportEvent: Sendable, Equatable {
    case connected(reconnected: Bool)
    case disconnected(RelayFailureCategory)
    case event(RelayEvent)
    case revoked
    case incompatible
}

actor RelayAPIClient {
    func start() -> AsyncStream<RelayTransportEvent>
    func stop() async
    func request<Response: Decodable & Sendable>(
        _ endpoint: RelayEndpoint<Response>,
        idempotencyKey: String? = nil
    ) async throws -> Response
    func transcribe(
        audio: Data,
        durationMs: Int,
        contentType: String,
        idempotencyKey: String
    ) async throws -> RelayTranscription
    func eraseSession() async
}
```

- [ ] **Step 1: Write failing concurrency, event, replay, and revocation tests**

Use a fake `RelaySocket` with controlled incoming envelopes. Prove two concurrent requests receive their own response, an event between them reaches the stream, replay survives reconnect, disconnect fails pending mutation without replay, backoff caps at 30 seconds, and inner/handshake 401 or 403 erases all device material.

- [ ] **Step 2: Run the API client tests and observe current cross-consumption**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch --filter RelayAPIClientTests
```

Expected: current API lacks socket injection, concurrent routing, or event publication.

- [ ] **Step 3: Implement one receive task and request continuations**

Maintain pending request continuations keyed by request ID inside the actor. Persist the host replay sequence before resuming a response or yielding an event. Close the socket and fail all pending continuations on disconnect. Reconnect reads snapshots later through Task 5; it never replays a mutation.

```swift
private var pending: [String: CheckedContinuation<RelayTunnelHTTPResponse, Error>] = [:]
private var receiveTask: Task<Void, Never>?
```

- [ ] **Step 4: Implement voice chunk encryption through the same sequence owner**

Limit audio to 2 MiB, 30 seconds, at most 16 chunks, and 128 KiB per chunk. Sign the canonical full transcription request before splitting it. Every chunk receives the next actor-serialized outgoing sequence.

- [ ] **Step 5: Run Watch core tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch
git add apple-watch scripts/check-watchos-source.sh
git commit -m "feat: add Watch response and event router"
```

---

### Task 5: Implement confirmed pairing and Watch feature state

**Files:**
- Create: `apple-watch/RelayWatch/RelayPairingState.swift`
- Create: `apple-watch/RelayWatch/RelayWatchFeature.swift`
- Create: `apple-watch/RelayWatch/RelayWatchService.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchModel.swift`
- Create: `apple-watch/Tests/RelayPairingStateTests.swift`
- Create: `apple-watch/Tests/RelayWatchFeatureTests.swift`
- Modify: `apple-watch/Package.swift`
- Modify: `apple-watch/RelayWatch.xcodeproj/project.pbxproj`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Consumes: Tasks 3 and 4 typed endpoints and transport events.
- Produces: testable pairing and feature state used by runtime views.

```swift
enum RelayPairingPhase: Equatable, Sendable {
    case codeEntry
    case submitting
    case confirmMac(name: String, fingerprint: String, expiresAt: Int64)
    case awaitingMacApproval(watchFingerprint: String)
    case failed(RelayFailureCategory)
}

struct RelayMutationAttempt: Equatable, Sendable {
    enum Status: Equatable, Sendable { case pending, failed, succeeded }
    let action: RelayMutation
    let idempotencyKey: String
    var status: Status
}
```

- [ ] **Step 1: Write failing pairing state tests**

Prove polling does not begin before Watch-side fingerprint confirmation, credentials save only after both confirmations, cancel/expiry/denial clear prepared material, and host/API mismatches fail closed.

- [ ] **Step 2: Write failing feature state tests**

Prove disconnect marks snapshots stale before reconnect, stale state rejects each mutation, reconnect refreshes inbox/tasks before enabling actions, duplicate taps create one call, retry keeps its idempotency key, a new action gets a new key, and pushed approval events update the inbox.

```swift
@Test func staleStateRejectsApproval() async {
    var feature = RelayWatchFeature(state: .fixture(cacheIsStale: true))
    await #expect(throws: RelayUserError.offline) {
        try await feature.approve("approval-1", dangerousConfirmation: false)
    }
    #expect(service.mutations.isEmpty)
}
```

- [ ] **Step 3: Run tests and observe the state machine is absent**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch --filter RelayPairingStateTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch --filter RelayWatchFeatureTests
```

- [ ] **Step 4: Implement the service, reducer-like feature state, and model bindings**

Keep transport/service work outside SwiftUI views. Route idle-task text through instructions and running-task text through steer with `activeTurnId`. Require an allowed folder returned by the bridge, advertised model/effort, and non-empty prompt for a new task. Refresh affected snapshots after success.

- [ ] **Step 5: Run tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch
git add apple-watch scripts/check-watchos-source.sh
git commit -m "feat: implement Watch pairing and feature state"
```

---

### Task 6: Replace preview destinations with real Watch controls

**Files:**
- Create: `apple-watch/RelayWatch/RelayInboxViews.swift`
- Create: `apple-watch/RelayWatch/RelayApprovalView.swift`
- Create: `apple-watch/RelayWatch/RelayQuestionView.swift`
- Create: `apple-watch/RelayWatch/RelayTaskViews.swift`
- Create: `apple-watch/RelayWatch/RelayComposeViews.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchRootView.swift`
- Modify: `apple-watch/test/project.test.mjs`
- Modify: `apple-watch/RelayWatch.xcodeproj/project.pbxproj`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Consumes: Task 5 `RelayWatchModel` published state and action methods.
- Produces: runtime inbox, approval, question, task, activity, instruction, new-task, history, and settings UI.

- [ ] **Step 1: Write failing source/project contract tests**

Parse runtime Swift sources and reject the existing preview strings such as `git push origin main`, `Which release channel should Relay use?`, and `Relay launch readiness`. Assert every new view belongs to the Xcode target and each destructive/approval control has an accessibility consequence.

- [ ] **Step 2: Run project tests and observe preview fixture failures**

```bash
node --test apple-watch/test/project.test.mjs
```

- [ ] **Step 3: Implement live inbox, approval, and question views**

Display exact bridge-provided command, cwd, reason, risk reasons, and consequence. Deny remains available. Normal approval uses one confirmation; dangerous approval opens a second confirmation and warning haptic. Question buttons come only from the decoded options.

- [ ] **Step 4: Implement tasks, activity, instruction, stop, and new-task views**

Use paginated model data, confirm stop against the active turn, and construct folder/model/effort choices from bridge responses. Disable every mutation when stale or pending. Show short redacted errors and success/failure haptics.

- [ ] **Step 5: Run source, Swift, and watchOS checks, then commit**

```bash
node --test apple-watch/test/project.test.mjs
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh
git add apple-watch scripts/check-watchos-source.sh
git commit -m "feat: connect Watch destination controls"
```

---

### Task 7: Implement reviewed Watch voice capture

**Files:**
- Create: `apple-watch/RelayWatch/RelayAudioRecorder.swift`
- Create: `apple-watch/RelayWatch/RelayVoiceView.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchModel.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchApp.swift`
- Modify: `apple-watch/RelayWatch.xcodeproj/project.pbxproj`
- Modify: `apple-watch/Package.swift`
- Modify: `scripts/check-watchos-source.sh`
- Create: `apple-watch/Tests/RelayVoiceLifecycleTests.swift`

**Interfaces:**
- Consumes: Task 4 transcription and Task 5 instruction/new-task actions.
- Produces: explicit record, stop, transcribe, edit, send, and cancel lifecycle.

```swift
struct RelayRecording: Sendable {
    let fileURL: URL
    let durationMs: Int
    let contentType: String
}

@MainActor
protocol RelayAudioRecording: AnyObject {
    func start() async throws
    func stop() async throws -> RelayRecording
    func cancel() async
}

enum RelayVoiceTarget: Equatable, Sendable {
    case instruction(taskID: String, turnID: String?)
    case newTaskPrompt
}
```

- [ ] **Step 1: Write failing voice lifecycle tests with a temporary file recorder**

Prove recording stops at 30 seconds and app inactivity, connection loss deletes audio, cancel deletes audio/transcript, transcription failures delete audio, transcript remains editable until explicit Send, and target selection uses instruction/steer or new-task draft.

- [ ] **Step 2: Run the voice tests and observe missing recorder/state failures**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch --filter RelayVoiceLifecycleTests
```

- [ ] **Step 3: Implement AVFoundation recording and deterministic cleanup**

Use explicit Start and Stop controls. Store audio only in a temporary URL, enforce 30 seconds and 2 MiB, and delete the file after success, cancel, timeout, failure, app inactivity, or disconnect. Do not persist transcript text.

- [ ] **Step 4: Implement transcript review and provider disclosure**

Display an editable transcript. Require Send before Codex receives text. Show that the Mac-configured transcription provider processes audio. Use success/failure haptics after final acknowledgements.

- [ ] **Step 5: Run Watch verification and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apple-watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh
git add apple-watch scripts/check-watchos-source.sh
git commit -m "feat: add reviewed Watch voice flow"
```

---

### Task 8: Add Mac cloud configuration and pending-pair recovery

**Files:**
- Create: `mac/Sources/RelayCore/RelayCloudEndpoints.swift`
- Modify: `mac/Sources/RelayCore/RelayCloudClient.swift`
- Modify: `mac/Sources/RelayCore/RelayCloudTunnel.swift`
- Modify: `mac/Sources/RelayMac/RelayAppModel.swift`
- Modify: `mac/Sources/RelayMac/DiagnosticsView.swift`
- Create: `mac/Tests/RelayCoreTests/RelayCloudEndpointsTests.swift`
- Modify: `apps/cloud/src/worker.ts`
- Modify: `apps/cloud/src/d1-gateway.ts`
- Modify: `apps/cloud/src/d1-repository.ts`
- Modify: `apps/cloud/test/d1-repository.test.ts`
- Modify: `apps/cloud/test/d1-worker-flow.test.ts`
- Modify: `apps/cloud/test/worker.test.ts`
- Modify: `mac/Tests/RelayCoreTests/RelayCloudClientTests.swift`

**Interfaces:**
- Consumes: current Mac cloud HTTP/WebSocket clients and D1 pairing records.
- Produces: one fail-closed endpoint source and authenticated recovery for pending requests in the active pairing session.

```swift
public struct RelayCloudEndpoints: Equatable, Sendable {
    public let apiOrigin: URL
    public let hostWebSocketURL: URL
    public let environment: RelayCloudEnvironmentName
    public static func resolve(
        processEnvironment: [String: String],
        isDebugBuild: Bool
    ) throws -> RelayCloudEndpoints
}
```

Cloud route:

```text
GET /cloud/v1/pairing-sessions/:token/requests
Authorization: Bearer <Mac access token>
200 {"requests":[...]}
```

- [ ] **Step 1: Write failing Mac endpoint tests**

Assert one debug origin derives HTTP/WebSocket endpoints, plaintext works only on loopback, invalid overrides fail instead of falling back to production, release overrides fail, and diagnostics expose only the environment name.

- [ ] **Step 2: Write failing cloud recovery tests**

Assert the query returns only pending, unexpired requests for the authenticated account, host, and unconsumed session. Denied, approved, expired, consumed, cross-account, and cross-host requests return nothing or authorization failure.

- [ ] **Step 3: Run focused tests and observe missing endpoint/route failures**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac --filter RelayCloudEndpoints
node --test apps/cloud/test/d1-repository.test.ts apps/cloud/test/d1-worker-flow.test.ts apps/cloud/test/worker.test.ts
```

- [ ] **Step 4: Implement shared endpoint resolution and D1 recovery route**

Reuse the existing POST path for Watch submission and add authenticated GET for Mac recovery. Return public keys, metadata, request ID, and expiry; never return the code, polling token, credential, or root key. The Mac derives and validates the displayed fingerprint from recovered public keys.

- [ ] **Step 5: Run Mac/cloud suites and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac
node --test apps/cloud/test/d1-repository.test.ts apps/cloud/test/d1-worker-flow.test.ts apps/cloud/test/worker.test.ts
git add mac apps/cloud
git commit -m "feat: recover Mac cloud pairing state"
```

---

### Task 9: Make Mac tunnel, destructive controls, and updates truthful

**Files:**
- Create: `mac/Sources/RelayCore/RelayCloudTunnelState.swift`
- Modify: `mac/Sources/RelayCore/RelayCloudTunnel.swift`
- Modify: `mac/Sources/RelayMac/RelayAppModel.swift`
- Modify: `mac/Sources/RelayMac/RemoteAccessView.swift`
- Modify: `mac/Sources/RelayMac/WatchesView.swift`
- Modify: `mac/Sources/RelayMac/MenuContent.swift`
- Modify: `mac/Sources/RelayMac/DiagnosticsView.swift`
- Create: `mac/Sources/RelayMac/DestructiveRelayAction.swift`
- Modify: `mac/Sources/RelayMac/RelayUpdateController.swift`
- Modify: `mac/Sources/RelayMac/UpdatesView.swift`
- Create: `mac/Tests/RelayCoreTests/RelayCloudTunnelStateTests.swift`
- Create: `mac/Tests/RelayMacTests/RelayCloudRecoveryTests.swift`
- Create: `mac/Tests/RelayMacTests/DestructiveRelayActionTests.swift`
- Create: `mac/Tests/RelayMacTests/RelayUpdateControllerTests.swift`

**Interfaces:**
- Consumes: Task 8 endpoints and pending-request read method.
- Produces: observable handshake/retry state, safe destructive confirmation, and Sparkle-backed update state.

```swift
public enum RelayCloudTunnelPhase: Equatable, Sendable {
    case signedOut
    case connecting(attempt: Int)
    case connected
    case retrying(attempt: Int, delaySeconds: Int)
    case stopped
}

enum RelayUpdateState: Equatable {
    case unknown
    case checking
    case current
    case available(version: String)
    case failed(RelayUpdateFailure)
}
```

- [ ] **Step 1: Write failing tunnel and recovery tests**

Prove the tunnel reports connected only after WebSocket open, classifies 401/403 and 426 without raw errors, retries recoverable failures at `1, 2, 4, 8, 16, 30, 30` seconds, resets after open, publishes state without manual refresh, and reloads active pending pairing requests after connection.

- [ ] **Step 2: Write failing destructive and update-state tests**

Assert menu and dashboard actions open confirmation before model methods. Confirmation copy must name watch revocation or permanent cloud deletion and say local Codex tasks/repositories remain. Assert update state moves from unknown to checking and maps Sparkle callbacks to current, available version, or redacted failure.

- [ ] **Step 3: Run the focused Mac tests and observe failures**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac --filter RelayCloudTunnel
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac --filter DestructiveRelayAction
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac --filter RelayUpdateController
```

- [ ] **Step 4: Implement delegated WebSocket open events, state publication, and recovery**

Use a retained `URLSession` and `URLSessionWebSocketDelegate`. Stop automatic retries for authentication or incompatibility; keep capped retry for offline/server failures. After each successful open, recover the active pairing session, merge by request ID, and drop expired requests. Disable pairing decisions unless tunnel and bridge self-test are healthy.

- [ ] **Step 5: Add confirmation dialogs and Sparkle delegate state**

Both menu and dashboard destructive actions must set a pending enum before invocation. Pass `RelayUpdateController` as Sparkle updater delegate; never show raw errors or feed URLs. Treat user cancellation as unknown/current rather than corrupted.

- [ ] **Step 6: Run the Mac suite and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path mac
git add mac
git commit -m "feat: finish Mac control-plane states"
```

---

### Task 10: Update the local testing checklist and Apple-only documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/SETUP.md`
- Modify: `docs/TODO.md`
- Modify: `docs/SECURITY.md`
- Modify: `docs/CLOUD-OPERATIONS.md`
- Modify: `apple-watch/README.md`

**Interfaces:**
- Consumes: verified behavior and commands from Tasks 1 through 9.
- Produces: accurate source-complete docs and a four-part test/release checklist.

- [ ] **Step 1: Rewrite the checklist structure**

Use these exact headings in `docs/TODO.md`:

```markdown
## Automated local checks
## Interactive local or staging checks
## Apple distribution and physical-device checks
## Ownership or security review gates
```

Put exact commands and observable results under the first section. Keep physical Watch, signing, notarization, TestFlight, App Store, external security review, production incident drill, legal approval, and account ownership unchecked.

- [ ] **Step 2: Update runtime and setup docs**

Remove claims that Watch destination screens use preview content. Document `RELAY_CLOUD_ORIGIN` as debug-only, plaintext loopback as local-only, and reachable TLS staging as required for a physical Watch. Explain pairing recovery, tunnel status, dangerous confirmation, voice review, stale mutation blocking, and external evidence gates.

- [ ] **Step 3: Run the complete fresh verification matrix**

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
git diff --check
```

Expected: commands pass unless the local Xcode installation lacks the required watchOS runtime. Record that runtime error as an external local-toolchain gate rather than changing source claims.

- [ ] **Step 4: Audit Apple-only language and external gates**

```bash
rg -n -i "android|wear os|galaxy|adb|emulator" README.md docs apple-watch mac apps packages scripts .github
rg -n "preview content|destination screens still" README.md docs apple-watch
```

Expected: both searches produce no stale runtime/product claims. Historical design documents under `docs/superpowers` may describe the decision context but must not instruct Android setup.

- [ ] **Step 5: Commit documentation and test evidence**

```bash
git add README.md docs apple-watch/README.md
git commit -m "docs: add Apple apps local test checklist"
```

