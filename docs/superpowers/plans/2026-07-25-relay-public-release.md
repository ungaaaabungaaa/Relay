# Relay Public Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current Relay bridge and Wear OS MVP into an installable,
security-hardened Apple silicon Mac menu-bar app and standalone Wear OS 4+
remote distributed through GitHub Releases.

**Architecture:** The Kotlin Wear OS app uses signed HTTPS requests and a
resumable WebSocket to a localhost-only TypeScript bridge exposed through
Tailscale Funnel. A native SwiftUI menu-bar app supervises the bundled bridge,
stores secrets in Keychain, installs the signed APK over Wireless ADB, manages
workspaces and devices, and controls Funnel.

**Tech Stack:** Node.js 24, TypeScript with erasable syntax, Node test runner,
SQLite, WebSocket, Kotlin 2, Jetpack Compose for Wear OS, OkHttp, WorkManager,
Swift 6, SwiftUI, Foundation, Security, Node SEA, Gradle, GitHub Actions,
Tailscale CLI, Android Platform Tools.

## Global Constraints

- GitHub Releases only; do not add Play Store publishing in version 1.
- Support Apple silicon Macs only.
- Support round Wear OS 4 / Android 13 (API 33) or later watches.
- Use the physical Samsung Galaxy Watch6 as the primary release gate.
- Do not install or require an emulator or Wear OS system image.
- Keep the watch API bound to `127.0.0.1:43117`.
- Keep the local administration API bound to `127.0.0.1:43118`; never route it
  through Funnel.
- Store no Codex credential, OpenAI key, Mac password, repository content, or
  audio history on the watch.
- Keep the optional OpenAI key in macOS Keychain.
- Delete uploaded audio on every success and failure path.
- Do not queue approvals, instructions, stops, or new tasks while offline.
- Use one-tap approval only for normal risk. Dangerous, destructive, elevated,
  incomplete, or unknown risk requires a 1.5-second hold by default.
- Default folder browsing to user-approved roots. The advanced all-readable
  mode must remain off until explicitly enabled on the Mac.
- Keep remote ingress disabled until authentication, replay, workspace, and
  generic-unauthorized tests pass.
- Use Apache License 2.0 and preserve third-party notices.
- Write a failing test and observe the expected failure before every production
  behavior change.

---

## File structure

### Bridge

- `apps/bridge/src/security/approval-risk.ts` — deterministic fail-closed risk
  classification.
- `apps/bridge/src/workspaces/workspace-policy.ts` — canonical approved-root
  browsing and traversal rejection.
- `apps/bridge/src/actions/action-executor.ts` — idempotent, audited
  state-changing operations.
- `apps/bridge/src/events/event-hub.ts` — bounded sequence and resume state.
- `apps/bridge/src/events/websocket-server.ts` — authenticated live event
  upgrade and replay.
- `apps/bridge/src/transcription/openai-transcriber.ts` — injected
  speech-to-text provider.
- `apps/bridge/src/admin/admin-server.ts` — loopback-only token-authenticated
  Mac control API.
- `apps/bridge/src/server.ts` — watch HTTP route composition only.

### Wear OS

- `wear/.../domain/` — immutable screen, task, approval, question, new-task,
  settings, and connection state.
- `wear/.../data/RelayApi.kt` — signed request/response transport.
- `wear/.../data/RelaySocket.kt` — resumable WebSocket client.
- `wear/.../audio/VoiceRecorder.kt` — duration-limited temporary audio.
- `wear/.../background/LiveMonitoringService.kt` — user-started foreground
  live session.
- `wear/.../background/RelayRefreshWorker.kt` — battery-aware stale refresh.
- `wear/.../ui/components/` — reusable circular-safe controls.
- `wear/.../ui/screens/` — one focused file per flow.

### Mac

- `mac/Package.swift` — Swift package for the native executable and tests.
- `mac/Sources/RelayCore/` — process, ADB, Tailscale, Keychain, update, and
  setup state machines.
- `mac/Sources/RelayMac/` — SwiftUI menu, dashboard, setup, device, workspace,
  voice, update, diagnostic, and about views.
- `scripts/build-bridge-sea.mjs` — self-contained arm64 bridge sidecar.
- `scripts/package-mac-app.sh` — deterministic `.app` and DMG assembly.

### Release

- `.github/workflows/quality.yml` — bridge and Wear tests and builds.
- `.github/workflows/release.yml` — signed, notarized tagged release.
- `release/release-manifest.schema.json` — signed update metadata contract.
- `docs/COMPATIBILITY.md` — project-tested and community-tested devices.
- `docs/RELEASE.md` — signing, notarization, recovery, and release procedure.

---

### Task 1: Fail-closed approval risk contract

**Files:**

- Create: `apps/bridge/src/security/approval-risk.ts`
- Create: `apps/bridge/test/approval-risk.test.ts`
- Modify: `apps/bridge/src/domain.ts`
- Modify: `apps/bridge/src/codex/mappers.ts`
- Modify: `apps/bridge/test/codex-adapter.test.ts`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/domain/ApprovalPolicy.kt`
- Create: `wear/src/test/java/dev/ungaaaabungaaa/relay/domain/ApprovalPolicyTest.kt`
- Modify: `wear/src/main/java/dev/ungaaaabungaaa/relay/domain/Models.kt`
- Modify: `wear/src/main/java/dev/ungaaaabungaaa/relay/data/RelayApi.kt`

**Interfaces:**

- Produces:
  `classifyApprovalRisk(input: ApprovalRiskInput): ApprovalRiskResult`.
- Produces: `ApprovalRisk = "normal" | "dangerous"` plus `riskReasons`.
- Produces: Kotlin `ApprovalRisk` and `RelayApproval.requiresHold()`.
- Consumes: mapped Codex approval kind, exact command, reason, and working
  directory.

- [x] **Step 1: Write the failing bridge risk tests**

```ts
it("marks destructive, privileged, remote-write, and incomplete approvals dangerous", () => {
  for (const command of ["rm -rf build", "sudo make install", "git push origin main"]) {
    assert.equal(classifyApprovalRisk({ kind: "command", command, reason: null }).risk, "dangerous");
  }
  assert.equal(
    classifyApprovalRisk({ kind: "command", command: null, reason: null }).risk,
    "dangerous",
  );
});

it("keeps read-only and test commands normal", () => {
  for (const command of ["git status --short", "pnpm test", "ls -la"]) {
    assert.equal(classifyApprovalRisk({ kind: "command", command, reason: null }).risk, "normal");
  }
});
```

- [x] **Step 2: Run the bridge test and observe the missing-module failure**

Run:

```bash
node --test apps/bridge/test/approval-risk.test.ts
```

Expected: FAIL because `approval-risk.ts` does not exist.

- [x] **Step 3: Implement the minimal deterministic classifier**

```ts
export type ApprovalRiskInput = {
  kind: "command" | "file" | "permission";
  command: string | null;
  reason: string | null;
};

export type ApprovalRiskResult = {
  risk: "normal" | "dangerous";
  riskReasons: string[];
};

export function classifyApprovalRisk(input: ApprovalRiskInput): ApprovalRiskResult {
  const text = `${input.command ?? ""}\n${input.reason ?? ""}`.trim();
  const reasons: string[] = [];
  if (input.kind !== "command") reasons.push(`${input.kind} approval`);
  if (!text) reasons.push("incomplete approval details");
  if (/\b(sudo|doas|su)\b/i.test(text)) reasons.push("privilege escalation");
  if (/\b(rm|rmdir|dd|mkfs|diskutil)\b/i.test(text)) reasons.push("destructive filesystem operation");
  if (/\bgit\s+push\b|\b(npm|pnpm)\s+publish\b/i.test(text)) reasons.push("remote write");
  if (/[|;]|&&|\|\||>>?|<</.test(text)) reasons.push("compound shell operation");
  return reasons.length
    ? { risk: "dangerous", riskReasons: reasons }
    : { risk: "normal", riskReasons: [] };
}
```

- [x] **Step 4: Add risk metadata to mapped approvals and mapper assertions**

`RelayApproval` gains:

```ts
risk: "normal" | "dangerous";
riskReasons: string[];
```

`mapApproval` calls `classifyApprovalRisk` once and spreads the result into the
returned object.

- [x] **Step 5: Run bridge tests**

Run:

```bash
pnpm test
pnpm typecheck
```

Expected: all Node tests pass and the TypeScript check exits zero.

- [x] **Step 6: Write the failing Kotlin policy test**

```kotlin
@Test
fun dangerousApprovalRequiresHold() {
    assertTrue(sampleApproval(ApprovalRisk.Dangerous).requiresHold())
    assertFalse(sampleApproval(ApprovalRisk.Normal).requiresHold())
}
```

Run:

```bash
env JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ANDROID_HOME='/Users/syedabdulmuqeeth/Library/Android/sdk' \
  ./gradlew :wear:testDebugUnitTest --tests '*ApprovalPolicyTest'
```

Expected: FAIL because `ApprovalRisk` and `requiresHold` do not exist.

- [x] **Step 7: Add the Kotlin enum, parser, and hold policy**

```kotlin
enum class ApprovalRisk { Normal, Dangerous }

fun RelayApproval.requiresHold(): Boolean = risk == ApprovalRisk.Dangerous
```

The JSON parser maps only the exact string `normal` to `Normal`; missing or
unknown strings map to `Dangerous`.

- [x] **Step 8: Verify and commit**

Run:

```bash
pnpm test
pnpm typecheck
env JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ANDROID_HOME='/Users/syedabdulmuqeeth/Library/Android/sdk' \
  ./gradlew :wear:testDebugUnitTest :wear:lintDebug :wear:assembleDebug
```

Commit:

```bash
git add apps/bridge wear
git commit -m "feat: classify Relay approval risk safely"
```

---

### Task 2: Approved workspace boundary

**Files:**

- Create: `apps/bridge/src/workspaces/workspace-policy.ts`
- Create: `apps/bridge/test/workspace-policy.test.ts`
- Modify: `apps/bridge/src/server.ts`
- Modify: `apps/bridge/test/server.test.ts`
- Modify: `apps/bridge/src/cli.ts`

**Interfaces:**

- Produces:
  `WorkspacePolicy.list(requestedPath?: string): Promise<WorkspaceListing>`.
- Produces:
  `WorkspacePolicy.assertAllowed(path: string): Promise<string>`.
- Consumes: canonical root paths loaded by the admin configuration.

- [x] **Step 1: Write failing tests using temporary real directories**

```ts
it("lists an approved root and rejects a sibling path and escaping symlink", async () => {
  const policy = new WorkspacePolicy([approvedRoot]);
  assert.equal((await policy.list()).roots[0]?.path, await realpath(approvedRoot));
  await assert.rejects(() => policy.list(siblingRoot), /workspace not allowed/);
  await assert.rejects(() => policy.list(path.join(approvedRoot, "escape")), /workspace not allowed/);
});
```

- [x] **Step 2: Run and observe the missing class**

Run:

```bash
node --test apps/bridge/test/workspace-policy.test.ts
```

Expected: FAIL because `WorkspacePolicy` is missing.

- [x] **Step 3: Implement canonical root validation**

Resolve roots and requested paths with `realpath`, require an exact root match or
the root plus the platform path separator, filter hidden directories, and
return at most 100 sorted directory entries. A symlink is allowed only when its
resolved target remains within an approved root.

- [x] **Step 4: Inject policy into the bridge handler**

Replace direct `readdir(resolve(...))` access with
`options.workspacePolicy.list(url.searchParams.get("path") ?? undefined)`.
Starting a task calls `assertAllowed(String(body.cwd))` before the adapter.

- [x] **Step 5: Add server tests**

Authenticated `/v1/folders` must return roots when no path is supplied, reject
an unapproved path with `403`, and reject a new task outside a root before
calling the fake adapter.

- [x] **Step 6: Verify and commit**

Run `pnpm test && pnpm typecheck`.

Commit:

```bash
git add apps/bridge
git commit -m "feat: restrict Relay to approved workspaces"
```

---

### Task 3: Idempotent audited state changes

**Files:**

- Create: `apps/bridge/src/actions/action-executor.ts`
- Create: `apps/bridge/test/action-executor.test.ts`
- Modify: `apps/bridge/src/security/store.ts`
- Modify: `apps/bridge/src/store/sqlite-store.ts`
- Modify: `apps/bridge/src/server.ts`
- Modify: `apps/bridge/test/server.test.ts`

**Interfaces:**

- Produces:
  `ActionExecutor.run<T>(context: ActionContext, operation: () => Promise<T> | T)`.
- Consumes: `deviceId`, required `Idempotency-Key`, action type, target ID.
- Produces: the original serialized result for repeated keys.

- [x] **Step 1: Write a failing duplicate-action test**

```ts
it("executes a repeated approval only once and returns the first result", async () => {
  let executions = 0;
  const first = await executor.run(context, () => ({ count: ++executions }));
  const second = await executor.run(context, () => ({ count: ++executions }));
  assert.deepEqual(second, first);
  assert.equal(executions, 1);
});
```

- [x] **Step 2: Run it and observe the missing executor**

Run `node --test apps/bridge/test/action-executor.test.ts`.

- [x] **Step 3: Add transactional idempotency storage**

Add an `action_results` SQLite table keyed by `(device_id, idempotency_key)`.
Persist `action`, `target`, `status`, `response_json`, and timestamps. Insert the
claim before the operation and finalize it in the same serialized executor.

- [x] **Step 4: Require idempotency keys on all mutating watch routes**

Approval, question, instruction, steer, stop, and start-task requests without a
valid 16–128 character `Idempotency-Key` return `400`. Repeated requests return
the first response and do not call Codex again.

- [x] **Step 5: Audit success and failure without payload content**

Audit only device, action type, target, risk class where applicable, and result.
Never store prompt text, command output, answers, or request bodies.

- [x] **Step 6: Verify and commit**

Run `pnpm test && pnpm typecheck`.

Commit:

```bash
git add apps/bridge
git commit -m "feat: make Relay actions idempotent and auditable"
```

---

### Task 4: Resumable authenticated live events

**Files:**

- Modify: `apps/bridge/src/events/event-hub.ts`
- Create: `apps/bridge/src/events/websocket-server.ts`
- Create: `apps/bridge/test/websocket-server.test.ts`
- Modify: `apps/bridge/src/server.ts`
- Modify: `apps/bridge/package.json`
- Modify: `package.json`
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Produces:
  `EventHub.resumeAfter(id: number): { events: RelayEvent[]; snapshotRequired: boolean }`.
- Produces: authenticated `GET /v1/events?after=<sequence>` WebSocket upgrade.
- Consumes the same signed request headers as HTTP.

- [x] **Step 1: Add failing retention-gap tests**

```ts
it("requires a snapshot when the requested sequence is older than retention", () => {
  const hub = new EventHub(2);
  hub.publish("one", {});
  hub.publish("two", {});
  hub.publish("three", {});
  assert.equal(hub.resumeAfter(0).snapshotRequired, true);
  assert.deepEqual(hub.resumeAfter(1).events.map((event) => event.id), [2, 3]);
});
```

- [x] **Step 2: Implement bounded resume metadata**

Track the earliest retained event and return `snapshotRequired` only when the
client asks before that boundary.

- [x] **Step 3: Add `ws` and write failing upgrade tests**

The test connects with a valid signed upgrade, receives replayed events, then
receives a newly published event. Missing, stale, replayed, or revoked
credentials must close before private event data is sent.

- [x] **Step 4: Implement WebSocket upgrade composition**

Attach `WebSocketServer({ noServer: true })` to `createRelayServer`. Validate
the signed path including `?after=` before calling `handleUpgrade`. Send either
`snapshot.required` or retained events, then subscribe until close.

- [x] **Step 5: Verify and commit**

Run `pnpm install --frozen-lockfile`, `pnpm test`, and `pnpm typecheck`.

Commit:

```bash
git add package.json pnpm-lock.yaml apps/bridge
git commit -m "feat: stream resumable Relay events"
```

---

### Task 5: Wear live client and connection state

**Files:**

- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/data/RelaySocket.kt`
- Create: `wear/src/test/java/dev/ungaaaabungaaa/relay/data/EventResumeTest.kt`
- Modify: `wear/src/main/java/dev/ungaaaabungaaa/relay/data/RelayPreferences.kt`
- Modify: `wear/src/main/java/dev/ungaaaabungaaa/relay/domain/RelayState.kt`
- Modify: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/RelayViewModel.kt`

**Interfaces:**

- Produces: `RelaySocket.start(after: Long)` and `RelaySocket.close()`.
- Emits typed `RelayLiveEvent` values and `SnapshotRequired`.
- Persists the last processed sequence only after state accepts an event.

- [x] **Step 1: Write failing sequence tests**

```kotlin
@Test
fun ignoresDuplicateEventsAndRequestsSnapshotAcrossRetentionGap() {
    val state = applyEvents(initialState, listOf(event(4), event(4), event(5)))
    assertEquals(5, state.lastEventId)
    assertEquals(2, state.appliedEventCount)
}
```

- [x] **Step 2: Observe the missing event reducer failure**

Run the single test with the Android Studio JDK and existing SDK.

- [x] **Step 3: Implement event models and reducer**

Deduplicate sequence IDs, map approval/question/task events, and transition to a
fresh snapshot request on `snapshot.required`.

- [x] **Step 4: Implement signed OkHttp WebSocket**

Build the canonical signed GET path with the persisted sequence, reconnect with
capped exponential backoff, and stop reconnecting after revocation or an
update-required response.

- [x] **Step 5: Remove three-second foreground polling**

Use the socket while connected and retain an explicit authenticated snapshot
refresh for launch, resume-gap, and manual retry.

- [x] **Step 6: Verify and commit**

Run Wear unit tests, lint, and debug assembly.

Commit:

```bash
git add wear
git commit -m "feat: receive live Relay events on Wear OS"
```

---

### Task 6: Complete circular watch product

**Files:**

- Split: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/RelayApp.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/theme/RelayTheme.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/components/RelayComponents.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/components/HoldToConfirm.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/screens/OnboardingScreens.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/screens/HomeScreen.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/screens/InboxScreens.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/screens/TaskScreens.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/screens/NewTaskScreens.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/ui/screens/ManagementScreens.kt`
- Create: `wear/src/test/java/dev/ungaaaabungaaa/relay/ui/NavigationPolicyTest.kt`
- Create: `wear/src/androidTest/java/dev/ungaaaabungaaa/relay/ui/RelayNavigationTest.kt`

**Interfaces:**

- Produces every watch state listed in the public-release spec.
- Consumes only `RelayState` and callback functions; composables contain no
  protocol, persistence, or credential logic.

- [x] **Step 1: Write failing pure navigation tests**

Assert Home → Inbox → Approval, Home → Task → Instruction, and New Task →
Workspace → Folder → Model → Effort → Permissions → Review.

- [x] **Step 2: Add the final screen enum and immutable draft state**

Represent onboarding, connection failures, daily control, new-task steps,
history, settings, and about explicitly. Do not use a generic screen for
production states.

- [x] **Step 3: Write and test the hold controller**

`HoldController` reaches confirmation only after 1,500 milliseconds of
continuous press. Cancel, pointer exit, lifecycle loss, and early release reset
progress without invoking approval.

- [x] **Step 4: Split reusable components and focused screens**

Use `TransformingLazyColumn` or the current Wear Compose rotary list primitive,
round-screen safe padding, minimum touch targets, vector icons, content
descriptions, and text for commands, paths, models, and consequences.

- [x] **Step 5: Wire all loading, empty, stale, failure, and expired states**

Stale states render cached summaries but expose no mutating callbacks.

- [x] **Step 6: Verify without an emulator**

Run unit tests, lint, and APK assembly. Record connected Android tests as a
physical-device gate until the Watch6 is paired.

- [x] **Step 7: Commit**

```bash
git add wear
git commit -m "feat: complete Relay watch flows"
```

---

### Task 7: Both voice input modes

**Files:**

- Create: `apps/bridge/src/transcription/transcriber.ts`
- Create: `apps/bridge/src/transcription/openai-transcriber.ts`
- Create: `apps/bridge/test/transcription.test.ts`
- Modify: `apps/bridge/src/server.ts`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/audio/VoiceRecorder.kt`
- Create: `wear/src/test/java/dev/ungaaaabungaaa/relay/audio/VoiceRecorderPolicyTest.kt`
- Modify: voice and transcript watch screens.

**Interfaces:**

- Produces: `Transcriber.transcribe(filePath: string): Promise<string>`.
- Produces: authenticated `POST /v1/transcribe` with 30-second and 2 MiB limits.
- Produces: `VoiceRecorder.start()`, `VoiceRecorder.stop()`, and
  `VoiceRecorder.cancel()`.

- [x] **Step 1: Write failing deletion and limit tests**

Use an injected fake transcriber and temporary file. Assert deletion after
success, provider failure, invalid media, oversized input, and timeout.

- [x] **Step 2: Implement the injected route and provider**

Use native `fetch` with a multipart request to the configured OpenAI
transcription endpoint. Return only the transcript; do not log response bodies.

- [x] **Step 3: Write failing watch duration-policy tests**

Assert recording stops at 30 seconds, cancellation deletes the local file, and
upload success or failure deletes it.

- [x] **Step 4: Implement just-in-time microphone flow**

Request microphone permission only when custom recording starts. System Wear OS
text input remains available without an OpenAI key.

- [x] **Step 5: Require transcript review**

The only transitions from transcription are Review, Re-record, or Cancel.
Sending requires an explicit action from Review.

- [x] **Step 6: Verify and commit**

Run all bridge and Wear verification.

Commit:

```bash
git add apps/bridge wear
git commit -m "feat: add reviewed voice instructions"
```

---

### Task 8: Battery-visible Live Monitoring

**Files:**

- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/background/LiveMonitoringService.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/background/LiveMonitoringPolicy.kt`
- Create: `wear/src/main/java/dev/ungaaaabungaaa/relay/background/RelayRefreshWorker.kt`
- Create: `wear/src/test/java/dev/ungaaaabungaaa/relay/background/LiveMonitoringPolicyTest.kt`
- Modify: `wear/src/main/AndroidManifest.xml`
- Modify: `wear/build.gradle.kts`
- Modify: `gradle/libs.versions.toml`

**Interfaces:**

- Produces a user-started foreground service and Wear ongoing activity.
- Stops after four hours, on explicit stop, revocation, or the configured
  low-battery threshold.
- Produces battery-aware WorkManager refresh when live mode is off.

- [x] **Step 1: Write failing pure policy tests**

Assert the session stops at exactly four hours, below 15% battery when not
charging, and immediately on revocation.

- [x] **Step 2: Implement policy and service lifecycle**

The foreground notification and ongoing activity must be visible whenever the
service keeps the socket open. Tapping it opens Inbox or the active task.

- [x] **Step 3: Add periodic WorkManager refresh**

Require network connectivity. Refresh only summaries, approvals, and questions;
never execute an action from background work.

- [x] **Step 4: Add settings disclosures**

Before activation, show the four-hour maximum and expected battery cost.

- [x] **Step 5: Verify and commit**

Run Wear unit tests, lint, and assembly.

Commit:

```bash
git add wear gradle
git commit -m "feat: add visible Relay live monitoring"
```

---

### Task 9: Bridge admin API and self-contained sidecar

**Files:**

- Create: `apps/bridge/src/admin/admin-server.ts`
- Create: `apps/bridge/test/admin-server.test.ts`
- Modify: `apps/bridge/src/cli.ts`
- Create: `scripts/build-bridge-sea.mjs`
- Modify: `package.json`
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Produces local token-authenticated admin operations: status, security
  self-test, pairing code, devices, revoke, workspaces, voice status, and
  shutdown.
- Produces `dist/relay-bridge-arm64` with no external Node.js dependency.

- [x] **Step 1: Write failing admin authentication tests**

Requests on the admin port without the 256-bit bearer token return a generic
`401`. The admin server refuses any non-loopback bind address.

- [x] **Step 2: Implement focused admin routes**

No route accepts arbitrary shell commands. Return structured status only and
never return a stored secret value.

- [x] **Step 3: Add Node SEA build dependencies and script**

Bundle the TypeScript entry to one CommonJS file, generate a SEA blob, copy the
current arm64 Node executable, remove its existing signature, inject the blob,
and apply an ad-hoc signature for local verification. Release signing replaces
the ad-hoc signature later.

- [x] **Step 4: Smoke-test the binary**

Start it with temporary data and ports, call both health endpoints, assert the
watch endpoint contains no private metadata, then terminate cleanly.

- [x] **Step 5: Verify and commit**

Run bridge tests, typecheck, SEA build, and smoke test.

Commit:

```bash
git add apps/bridge scripts package.json pnpm-lock.yaml
git commit -m "feat: package the Relay bridge sidecar"
```

---

### Task 10: Native SwiftUI menu-bar control plane

**Prerequisite:** Install full Xcode and select its developer directory. The
current machine has Command Line Tools and Swift but not the full Xcode SDK
toolchain required to build, sign, and notarize the SwiftUI application.

**Files:**

- Create: `mac/Package.swift`
- Create: `mac/Sources/RelayCore/SetupState.swift`
- Create: `mac/Sources/RelayCore/BridgeSupervisor.swift`
- Create: `mac/Sources/RelayCore/AdminClient.swift`
- Create: `mac/Sources/RelayCore/KeychainStore.swift`
- Create: `mac/Sources/RelayCore/CommandRunner.swift`
- Create: `mac/Tests/RelayCoreTests/SetupStateTests.swift`
- Create: `mac/Tests/RelayCoreTests/BridgeSupervisorTests.swift`
- Create: `mac/Tests/RelayCoreTests/KeychainStoreTests.swift`
- Create: `mac/Sources/RelayMac/RelayMacApp.swift`
- Create: `mac/Sources/RelayMac/MenuContent.swift`
- Create: `mac/Sources/RelayMac/DashboardView.swift`
- Create focused views for Setup, Watches, Remote Access, Workspaces, Voice,
  Updates, Diagnostics, and About.

**Interfaces:**

- Produces an Apple silicon SwiftUI `MenuBarExtra` application.
- Consumes the token-authenticated loopback admin API.
- Stores admin and OpenAI secrets through `KeychainStore`.

- [ ] **Step 1: Write failing Swift setup-state tests**

```swift
@Test func setupIsReadyOnlyWhenEveryRequiredCheckPasses() {
    let state = SetupState(
        codex: .ready, tailscale: .ready, bridge: .ready,
        watchInstalled: true, watchPaired: true, remoteAccess: .ready
    )
    #expect(state.isReady)
}
```

- [ ] **Step 2: Implement RelayCore with injected process and Keychain ports**

Production code uses `Process` and Security.framework. Tests use in-memory
implementations through protocols; production source has no test-only methods.

- [ ] **Step 3: Test bridge lifecycle**

Assert one sidecar instance, clean stop, bounded restart after a crash, redacted
error output, and no automatic restart after Emergency Stop.

- [ ] **Step 4: Build the MenuBarExtra and dashboard**

The menu shows bridge, Codex, Funnel, watch, pending-action, update, dashboard,
emergency stop, and quit states. The dashboard implements every Mac screen in
the public-release spec.

- [ ] **Step 5: Verify and commit**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path mac
```

Commit:

```bash
git add mac
git commit -m "feat: add Relay Mac menu-bar app"
```

---

### Task 11: Wireless ADB, Tailscale, and updates

**Files:**

- Create: `mac/Sources/RelayCore/PlatformToolsManager.swift`
- Create: `mac/Sources/RelayCore/ADBClient.swift`
- Create: `mac/Sources/RelayCore/TailscaleClient.swift`
- Create: `mac/Sources/RelayCore/ReleaseClient.swift`
- Create corresponding RelayCore tests.
- Modify the Setup, Remote Access, Watches, and Updates SwiftUI views.

**Interfaces:**

- Produces official Platform Tools download and pinned-digest verification.
- Produces mDNS discovery plus manual pairing fallback.
- Produces APK install/update with installed-version verification.
- Produces Funnel preflight, enable, status, disable, and Emergency Stop.
- Produces signed GitHub update-manifest parsing and downgrade rejection.

- [ ] **Step 1: Write failing command-plan tests**

Assert exact argument arrays for `adb pair`, `adb connect`, `adb install -r`,
`tailscale status --json`, `tailscale funnel --bg 43117`, and
`tailscale funnel 43117 off`. Never build shell command strings.

- [ ] **Step 2: Implement Platform Tools integrity**

Download only the official configured HTTPS artifact. Verify the pinned SHA-256
before extracting to Relay Application Support. Reject redirects to unapproved
hosts and delete a failed download.

- [ ] **Step 3: Implement ADB wizard state**

Discover `_adb-tls-pairing._tcp` and `_adb-tls-connect._tcp`, permit manual
address entry, verify the connected device reports the watch hardware feature,
install the bundled APK, and verify package version.

- [ ] **Step 4: Implement Tailscale preflight**

Require a signed-in status and successful bridge security self-test before
Funnel enable. Always target port 43117. Emergency Stop attempts Funnel disable
and bridge remote-session shutdown independently and reports both results.

- [ ] **Step 5: Implement signed release checks**

Verify update metadata and artifact digest, reject lower versions, and preserve
the previous Mac app or APK after failure.

- [ ] **Step 6: Verify and commit**

Run Swift tests and build with full Xcode.

Commit:

```bash
git add mac
git commit -m "feat: automate Relay watch and Funnel setup"
```

---

### Task 12: Signing, quality automation, documentation, and release gate

**Files:**

- Create: `LICENSE`
- Create: `NOTICE`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `.github/workflows/quality.yml`
- Create: `.github/workflows/release.yml`
- Create: `release/release-manifest.schema.json`
- Create: `scripts/package-mac-app.sh`
- Create: `scripts/verify-release.mjs`
- Create: `docs/COMPATIBILITY.md`
- Create: `docs/RELEASE.md`
- Modify: `README.md`
- Modify: `docs/SETUP.md`
- Modify: `docs/SECURITY.md`
- Modify: `docs/PHYSICAL-WATCH-TEST.md`
- Modify: `docs/TODO.md`

**Interfaces:**

- Produces notarized `Relay.dmg`, signed `relay-wear.apk`, checksums, signed
  manifest, source archive, license, notices, release notes, and compatibility
  matrix from one clean tag.

- [ ] **Step 1: Write failing release-manifest verifier tests**

Assert matching tag, Mac version, watch version, Codex compatibility range,
artifact names, digests, architectures, and signatures. Reject a changed byte,
wrong tag, Intel artifact, unsigned APK, or missing license.

- [ ] **Step 2: Add Apache 2.0 and notices**

Add the unmodified Apache License 2.0 text, project copyright notice, and
third-party license inventory generated from locked dependencies.

- [ ] **Step 3: Add quality workflow**

Run Node tests/typecheck, Wear unit tests/lint/assembly, Swift tests/build, APK
secret scan, bridge sidecar smoke test, and release-manifest tests. Upload
artifacts only from successful jobs.

- [ ] **Step 4: Add release workflow**

Trigger only on `v*` tags. Import signing material from protected secrets, build
and sign nested Mac executables, notarize and staple the app and DMG, sign the
APK with the protected Android key, generate checksums and signed metadata,
verify all outputs, then create the GitHub Release.

- [ ] **Step 5: Perform clean-Mac and physical-Watch6 acceptance**

Use the exact ten acceptance criteria from
`docs/superpowers/specs/2026-07-25-relay-public-release-design.md`. Record
command outputs, device/OS versions, battery observations, and remaining
community-tested devices without storing secrets.

- [ ] **Step 6: Verify and commit**

Run the complete local quality command and `scripts/verify-release.mjs` against
unsigned local fixtures; keep signing/notarization as the credentialed release
job gate.

Commit:

```bash
git add LICENSE NOTICE THIRD_PARTY_NOTICES.md .github release scripts docs README.md
git commit -m "chore: prepare Relay GitHub release"
```

---

## Checkpoint and execution order

1. Push this plan.
2. Complete Tasks 1–3 before enabling any remote ingress.
3. Complete Tasks 4–8 before claiming the watch product is feature-complete.
4. Complete Task 9 before bundling the bridge into the Mac app.
5. Install full Xcode before Tasks 10–12; do not download Xcode automatically.
6. Pair the physical Galaxy Watch6 before closing Tasks 6, 8, 11, or 12.
7. Push every verified task commit to `origin/feat/relay-mvp`.
8. Open a pull request only after the full automated suite, clean-Mac install,
   physical-Watch6 acceptance, and release-artifact verification pass.
