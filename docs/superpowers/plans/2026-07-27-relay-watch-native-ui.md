# Relay Watch Native UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Relay's manual Watch screen switch with a native, action-first watchOS interface that uses the approved Material grids, queue, adaptive reviews, progressive composition flows, and deliberate scrolling rules.

**Architecture:** A typed `RelayWatchRoute` drives one `NavigationStack`; connection state stays at the root. Small presentation helpers decide home composition, question progress, task summaries, new-task steps, and haptic behavior. Views use native SwiftUI controls and pass typed intent to `RelayWatchModel`, while existing transport, validation, encryption, and mutation services remain unchanged.

**Tech Stack:** Swift 6.1, SwiftUI, watchOS 10+, WatchKit haptics, Swift Testing, Xcode 26 watchOS SDK, SF Symbols.

## Global Constraints

- Keep `RelayCloud`, pairing, encryption, Codex action, workspace, offline, replay, idempotency, and voice protocol behavior unchanged.
- Use Apple SwiftUI components, system materials, system typography, and SF Symbols. Add no icon or UI dependency.
- System blue marks primary actions and selection; orange marks attention; red marks destructive actions.
- The 40 mm Apple Watch SE 2 is the primary no-scroll acceptance display. Also inspect 44 mm and 46 mm.
- Use adaptive vertical scrolling before clipping, truncating exact security text, or shrinking text.
- Cached offline content remains review-only. Mutations stay disabled and never queue.
- Preserve the user's modified `RelayWatch.xcscheme` and untracked Xcode workspace.
- Each task uses RED, GREEN, focused review, and its own commit.

---

## File structure

- `RelayWatchNavigation.swift`: typed routes and route-to-selection mapping.
- `RelayWatchComponents.swift`: Material tile, action dock, status strip, task/activity rows, adaptive container.
- `RelayWatchHomeView.swift`: pending queue, all-clear 2×2 grid, and offline state.
- `RelayPairingViews.swift`: pairing entry, fingerprint review, wait, and problem states.
- `RelayNewTaskFlow.swift`: three-step state and new-task screens.
- `RelayMoreViews.swift`: More grid, history, settings, identity, and about screens.
- Existing feature files keep the domain they already own: approvals, questions, tasks, compose, voice, model, and protocol types.

---

### Task 1: Native navigation and reusable presentation foundation

**Files:**
- Create: `apple-watch/RelayWatch/RelayWatchNavigation.swift`
- Create: `apple-watch/RelayWatch/RelayWatchComponents.swift`
- Modify: `apple-watch/RelayWatch/RelayProtocol.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchModel.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchRootView.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchStyle.swift`
- Modify: `apple-watch/Tests/RelayWatchContractTests.swift`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Produces: `enum RelayWatchRoute: Hashable`, `RelayWatchModel.path: [RelayWatchRoute]`, `navigate(to:)`, `popToRoot()`, `RelayAdaptiveContainer`, `RelayMaterialTile`, `RelayActionDock`, and `RelayStatusStrip`.
- Consumes: existing selection IDs, `RelayConnectionState`, `RelayWatchScreen` transitions, and every current destination view.

- [ ] **Step 1: Write failing navigation and component contracts**

Add tests that require typed routes and reject the old custom navigation boundary:

```swift
private func relayWatchSources() throws -> [String: String] {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourceDirectory = tests
        .deletingLastPathComponent()
        .appendingPathComponent("RelayWatch")
    return try Dictionary(uniqueKeysWithValues:
        FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    )
}

private func relayWatchSource(named name: String) throws -> String {
    try #require(relayWatchSources()[name])
}

@Test
func watchRoutesCarryOnlyStableDestinationIdentity() {
    #expect(RelayWatchRoute.approval("approval-1") != .approval("approval-2"))
    #expect(RelayWatchRoute.task("task-1") == .task("task-1"))
    #expect(RelayWatchRoute.newTask != .voice)
}

@Test
func watchSourcesUseNativeNavigationAndNoCustomBackButton() throws {
    let sources = try relayWatchSources()
    #expect(sources["RelayWatchRootView.swift"]?.contains("NavigationStack(path:") == true)
    #expect(sources["RelayWatchNavigation.swift"]?.contains("enum RelayWatchRoute") == true)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test --disable-sandbox --package-path apple-watch \
  --filter RelayWatchContractTests
```

Expected: compilation fails because `RelayWatchRoute` and native navigation do not exist.

- [ ] **Step 3: Add the typed route and model navigation API**

Create this route surface and replace `screen` mutations with typed navigation:

```swift
enum RelayWatchRoute: Hashable {
    case approval(String)
    case question(String)
    case tasks
    case task(String)
    case activity(String)
    case instruction(String?)
    case newTask
    case voice
    case more
    case history
    case settings
    case identity
    case about
}

@Published var path: [RelayWatchRoute] = []

func navigate(to route: RelayWatchRoute) {
    switch route {
    case let .approval(id): selectedApprovalID = id
    case let .question(id): selectedQuestionID = id
    case let .task(id), let .activity(id): selectedTaskID = id
    case let .instruction(id): if let id { selectedTaskID = id }
    default: break
    }
    path.append(route)
}

func popToRoot() { path.removeAll() }
```

Use `NavigationStack(path: $model.path)` and `navigationDestination(for:)` in the live/offline root. Pairing and problem connection states remain outside the stack. Keep a temporary `show(_:)` adapter from `RelayWatchScreen` to typed routes while later tasks migrate each destination. Remove the adapter, `RelayWatchScreen`, and `RelayBackButton` in Task 5 after the final call site moves to native stack dismissal.

- [ ] **Step 4: Add reusable native components**

Implement focused components with these signatures:

```swift
struct RelayAdaptiveContainer<Compact: View, Scrolling: View>: View
struct RelayMaterialTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void
}
struct RelayActionDock: View {
    let primaryTitle: String
    let secondaryTitle: String
    let primary: () -> Void
    let secondary: () -> Void
}
struct RelayStatusStrip: View {
    let connection: RelayConnectionState
    let cacheIsStale: Bool
    let error: String?
}
```

`RelayAdaptiveContainer` places the complete compact view first in `ViewThatFits(in: .vertical)` and a vertical `ScrollView` second. Components use `Button`, `.buttonStyle(.plain)`, `.background(.thinMaterial)`, system corner shapes, SF Symbols, and literal accessibility labels.

- [ ] **Step 5: Run focused and full Watch tests, source check, and commit**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path apple-watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh
git diff --check
```

Commit:

```bash
git add apple-watch/RelayWatch/RelayWatchNavigation.swift \
  apple-watch/RelayWatch/RelayWatchComponents.swift \
  apple-watch/RelayWatch/RelayProtocol.swift \
  apple-watch/RelayWatch/RelayWatchModel.swift \
  apple-watch/RelayWatch/RelayWatchRootView.swift \
  apple-watch/RelayWatch/RelayWatchStyle.swift \
  apple-watch/Tests/RelayWatchContractTests.swift scripts/check-watchos-source.sh
git commit -m "refactor(watch): adopt native navigation"
```

---

### Task 2: Pairing and action-first home

**Files:**
- Create: `apple-watch/RelayWatch/RelayPairingViews.swift`
- Create: `apple-watch/RelayWatch/RelayWatchHomeView.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchRootView.swift`
- Delete: `apple-watch/RelayWatch/RelayInboxViews.swift`
- Modify: `apple-watch/Tests/RelayWatchContractTests.swift`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Consumes: Task 1 routes, components, model pairing state, inbox, tasks, live/offline flags, and refresh.
- Produces: `RelayPairingFlowView`, `RelayWatchHomeView`, `RelayHomeItem`, and `RelayHomePresentation.items(approvals:questions:limit:)`.

- [ ] **Step 1: Write failing home-composition and pairing source tests**

```swift
@Test
func actionFirstHomeCapsTheVisibleQueueAtTwo() {
    let items = RelayHomePresentation.items(
        approvals: [approvalFixture("a1"), approvalFixture("a2")],
        questions: [questionFixture("q1")],
        limit: 2
    )
    #expect(items.map(\.id) == ["a1", "a2"])
    #expect(RelayHomePresentation.remainingCount(total: 3, visible: items.count) == 1)
}

@Test
func allClearHomeUsesTheApprovedFourActions() {
    #expect(RelayHomePresentation.clearActions.map(\.title) == [
        "Tasks", "New task", "Voice", "More",
    ])
}

private func approvalFixture(_ id: String) -> RelayApproval {
    RelayApproval(
        id: id, threadId: "task", turnId: "turn", itemId: "item-\(id)",
        kind: .command, risk: .normal, riskReasons: [], command: "pnpm test",
        cwd: "/workspace", reason: nil, startedAtMs: 1
    )
}

private func questionFixture(_ id: String) -> RelayQuestion {
    RelayQuestion(
        id: id, threadId: "task", turnId: "turn", itemId: "item-\(id)",
        questions: [
            .init(
                id: "choice", header: "Release", question: "Choose",
                options: [.init(label: "Beta", description: "Private testing")]
            ),
        ]
    )
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run the Watch contract filter. Expected: `RelayHomePresentation` does not exist.

- [ ] **Step 3: Split pairing into its own flow**

Move code entry, submitting, fingerprint review, approval wait, paired progress, revoked, and incompatible presentations out of `RelayWatchRootView`. Keep exact model methods and state transitions. Use a compact fixed layout first and `RelayAdaptiveContainer` for fingerprint and problem copy. Before deleting `RelayInboxViews.swift`, move its temporary `RelayBackButton` compatibility type into `RelayWatchComponents.swift`; Tasks 3 through 5 remove its remaining call sites.

The code-entry view must contain exactly one `TextField`, **Find Mac**, the Watch fingerprint, and inline error text. It uppercases through the existing model and keeps the six-character validation.

- [ ] **Step 4: Build the action-first home**

Use up to two pending `NavigationLink` rows. Show the remaining count and the fixed **Tasks / More** dock. When the queue is empty, render a `Grid` of four `RelayMaterialTile` buttons. Offline renders `RelayStatusStrip`, openable cached review rows, disabled mutation controls inside their destinations, and **Try again**.

Keep refresh, task loading, and selected identifiers in the model. Delete the legacy three-section inbox and custom Back view.

- [ ] **Step 5: Run Watch tests/source check and commit**

Use the Task 1 verification commands, then commit:

```bash
git add apple-watch/RelayWatch/RelayPairingViews.swift \
  apple-watch/RelayWatch/RelayWatchHomeView.swift \
  apple-watch/RelayWatch/RelayWatchRootView.swift \
  apple-watch/RelayWatch/RelayInboxViews.swift \
  apple-watch/Tests/RelayWatchContractTests.swift scripts/check-watchos-source.sh
git commit -m "feat(watch): add action-first home"
```

---

### Task 3: Adaptive approvals and one-question flow

**Files:**
- Modify: `apple-watch/RelayWatch/RelayApprovalView.swift`
- Modify: `apple-watch/RelayWatch/RelayQuestionView.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchComponents.swift`
- Modify: `apple-watch/Tests/RelayWatchContractTests.swift`

**Interfaces:**
- Consumes: `RelayAdaptiveContainer`, model action guards, selected approval/question, existing mutation APIs, and WatchKit haptics.
- Produces: `RelayQuestionProgress`, one-question navigation state, and adaptive approval/question content.

- [ ] **Step 1: Write failing question-progress and security-presentation tests**

```swift
@Test
func questionProgressRequiresEveryAnswerBeforeSend() throws {
    let progress = RelayQuestionProgress(questionCount: 2)
    #expect(progress.title(at: 0) == "Question 1 of 2")
    #expect(progress.actionTitle(at: 0) == "Next question")
    #expect(progress.actionTitle(at: 1) == "Send answer")
    #expect(!progress.canSubmit(answeredQuestionIDs: ["one"], requiredIDs: ["one", "two"]))
}

@Test
func approvalSourceKeepsExactContentAndBothConfirmations() throws {
    let source = try relayWatchSource(named: "RelayApprovalView.swift")
    #expect(source.contains("RelayAdaptiveContainer"))
    #expect(source.contains("confirmNormal"))
    #expect(source.contains("confirmDangerous"))
    #expect(!source.contains("lineLimit"))
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Expected: `RelayQuestionProgress` is missing and approval does not use the adaptive container.

- [ ] **Step 3: Implement adaptive approval review**

Render kind/risk, exact command or reason, cwd/target, and every consequence in a shared content builder. Place Deny and Approve in a two-button row only when both labels fit; the scrolling fallback uses full-width buttons. Keep `actionsEnabled`, `mutationPending`, dangerous haptic, normal confirmation, and dangerous confirmation unchanged.

- [ ] **Step 4: Implement one question at a time**

Add `@State private var questionIndex = 0` and retain the answer dictionary. Render only the current item and its full-width option rows. **Next question** advances after a selection. **Send answer** calls `validatedAnswers` through the existing model path only when every required ID has an answer. Use the adaptive container for long copy.

- [ ] **Step 5: Run Watch tests and commit**

Run the full Watch suite and source check, then:

```bash
git add apple-watch/RelayWatch/RelayApprovalView.swift \
  apple-watch/RelayWatch/RelayQuestionView.swift \
  apple-watch/RelayWatch/RelayWatchComponents.swift \
  apple-watch/Tests/RelayWatchContractTests.swift
git commit -m "feat(watch): streamline reviews"
```

---

### Task 4: Task summary, activity, instruction, and progressive new task

**Files:**
- Create: `apple-watch/RelayWatch/RelayNewTaskFlow.swift`
- Modify: `apple-watch/RelayWatch/RelayTaskViews.swift`
- Modify: `apple-watch/RelayWatch/RelayComposeViews.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchModel.swift`
- Modify: `apple-watch/Tests/RelayWatchContractTests.swift`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Consumes: routes, task data, model/folder options, existing start/instruction/stop mutations, and stale guards.
- Produces: `RelayNewTaskStep`, `RelayNewTaskDraft`, `RelayTaskSummaryView`, `RelayTaskActivityView`, and the three-step creation flow.

- [ ] **Step 1: Write failing task-summary and new-task state tests**

```swift
@Test
func newTaskFlowAdvancesOnlyWithValidStepData() {
    var draft = RelayNewTaskDraft()
    #expect(!draft.canAdvance(from: .workspace, models: []))
    draft.cwd = "/workspace"
    #expect(draft.canAdvance(from: .workspace, models: []))
    #expect(draft.next(after: .workspace) == .model)
    #expect(draft.next(after: .model) == .prompt)
}

@Test
func activeTaskSummaryUsesOnlyTheLatestActivity() {
    let detail = RelayTaskDetail(
        id: "task", title: "Build Watch UI", preview: "Working",
        cwd: "/workspace", updatedAt: 2, status: .running,
        activeTurnId: "turn",
        activity: [
            RelayActivity(
                id: "one", turnId: "turn", kind: .status,
                title: "First activity", detail: nil, status: .succeeded,
                occurredAt: 1
            ),
            RelayActivity(
                id: "two", turnId: "turn", kind: .status,
                title: "Second activity", detail: nil, status: .running,
                occurredAt: 2
            ),
        ]
    )
    let summary = RelayTaskPresentation.summary(detail)
    #expect(summary.latestActivityTitle == "Second activity")
    #expect(summary.canStop)
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Expected: new flow and summary helpers are undefined.

- [ ] **Step 3: Separate task summary from full activity**

Tasks remain a compact `List`. A task link loads details and opens `RelayTaskSummaryView`, which shows state, title, workspace display name, latest activity, **Instruct**, conditional **Stop**, and **View full activity** without scrolling at normal sizes. The activity destination remains a native list of all real items. Stop keeps its confirmation.

- [ ] **Step 4: Rebuild instruction and new task composition**

Instruction uses the selected task, native text input, and **Send**. Remove manual Back rows.

Define:

```swift
enum RelayNewTaskStep: Int, CaseIterable { case workspace, model, prompt }

struct RelayNewTaskDraft: Equatable {
    var cwd = ""
    var modelID = ""
    var effort = ""
    var prompt = ""
}
```

Workspace, model/effort, and prompt/review each render as one route-local step. The final screen shows all selected display values and calls the existing `startTask` method. Default selection uses current `RelayModel.isDefault` and `defaultEffort` behavior.

- [ ] **Step 5: Run Watch tests/source check and commit**

```bash
git add apple-watch/RelayWatch/RelayNewTaskFlow.swift \
  apple-watch/RelayWatch/RelayTaskViews.swift \
  apple-watch/RelayWatch/RelayComposeViews.swift \
  apple-watch/RelayWatch/RelayWatchModel.swift \
  apple-watch/Tests/RelayWatchContractTests.swift scripts/check-watchos-source.sh
git commit -m "feat(watch): simplify task control"
```

---

### Task 5: Voice, More, history, settings, and haptic preference

**Files:**
- Create: `apple-watch/RelayWatch/RelayMoreViews.swift`
- Create: `apple-watch/RelayWatch/RelayHaptics.swift`
- Modify: `apple-watch/RelayWatch/RelayVoiceView.swift`
- Modify: `apple-watch/RelayWatch/RelayTaskViews.swift`
- Modify: `apple-watch/RelayWatch/RelayComposeViews.swift`
- Modify: `apple-watch/RelayWatch/RelayWatchModel.swift`
- Modify: `apple-watch/Tests/RelayWatchContractTests.swift`
- Modify: `apple-watch/Tests/RelayVoiceLifecycleTests.swift`
- Modify: `scripts/check-watchos-source.sh`

**Interfaces:**
- Consumes: existing voice controller phases, mutation history, identity, local erase, routes, and Material tile.
- Produces: `RelayMoreView`, `RelaySettingsView`, `RelayIdentityView`, `RelayAboutView`, and `RelayHapticPreference`.

- [ ] **Step 1: Write failing haptic and More-grid contracts**

```swift
@Test
func hapticPreferenceDefaultsOnAndPersistsOff() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let preference = RelayHapticPreference(defaults: defaults)
    #expect(preference.isEnabled)
    preference.isEnabled = false
    #expect(!RelayHapticPreference(defaults: defaults).isEnabled)
}

@Test
func moreGridUsesTheApprovedActions() {
    #expect(RelayMorePresentation.actions.map(\.title) == [
        "Voice", "Refresh", "History", "Settings",
    ])
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Expected: haptic and More presentation types are missing.

- [ ] **Step 3: Rebuild voice around focused phases**

Keep the controller state machine unchanged. Replace the list with phase-specific compact views: destination, idle, recording, transcribing, review, and sending. Recording shows elapsed/limit text plus Stop & Transcribe and Erase. Review uses `RelayAdaptiveContainer` around the editable transcript. Every destructive path still calls controller cleanup.

- [ ] **Step 4: Add More and Watch-local settings**

Use the 2×2 grid for Voice, Refresh, History, and Settings. History remains a scrollable list. Settings uses a binding to `RelayHapticPreference`, links to identity/about, and confirms **Forget this Watch**. Identity shows only the Watch fingerprint. About reads `CFBundleShortVersionString`.

Route all success, failure, and dangerous-warning haptics through:

```swift
struct RelayHapticPreference {
    static let key = "relay.watch.haptics.enabled"
    var isEnabled: Bool { get nonmutating set }
}

@MainActor
func playRelayHaptic(_ type: WKHapticType) {
    guard hapticPreference.isEnabled else { return }
WKInterfaceDevice.current().play(type)
}
```

After voice, history, settings, and every earlier screen use native stack dismissal or typed routes, delete the temporary `show(_:)` adapter, `RelayWatchScreen`, and `RelayBackButton`.

- [ ] **Step 5: Run Watch tests/source check and commit**

```bash
git add apple-watch/RelayWatch/RelayMoreViews.swift \
  apple-watch/RelayWatch/RelayHaptics.swift \
  apple-watch/RelayWatch/RelayVoiceView.swift \
  apple-watch/RelayWatch/RelayTaskViews.swift \
  apple-watch/RelayWatch/RelayComposeViews.swift \
  apple-watch/RelayWatch/RelayWatchModel.swift \
  apple-watch/Tests/RelayWatchContractTests.swift \
  apple-watch/Tests/RelayVoiceLifecycleTests.swift scripts/check-watchos-source.sh
git commit -m "feat(watch): complete native utility flows"
```

---

### Task 6: Display verification, docs, Mac regression check, and delivery

**Files:**
- Modify: `docs/TODO.md`
- Modify: `docs/SETUP.md`
- Modify: `docs/PHYSICAL-APPLE-WATCH-TEST.md`
- Modify: `docs/COMPATIBILITY.md` only if a real simulator or device result supplies a truthful entry.

**Interfaces:**
- Consumes: complete Watch UI, source checker, Xcode project, existing bridge artifact, and native Mac menu app.
- Produces: verified commits, pushed `main`, and local Mac/Watch test instructions.

- [ ] **Step 1: Add release-contract source assertions**

Extend Watch contracts to reject legacy manual navigation and external icon/UI dependencies:

```swift
let allSources = try relayWatchSources().values.joined(separator: "\n")
#expect(!allSources.contains("RelayWatchScreen"))
#expect(!allSources.contains("RelayBackButton"))
#expect(allSources.contains("NavigationStack(path:"))
#expect(allSources.contains("Image(systemName:"))
```

Update the source-check script with every new Swift file so both supported watchOS architectures typecheck.

- [ ] **Step 2: Run complete automated verification**

```bash
pnpm --filter @relay/bridge test
pnpm typecheck
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path apple-watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-watchos-source.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --package-path mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --disable-sandbox --package-path mac
git diff --check
```

If loopback tests fail with `listen EPERM` in the sandbox, rerun the exact test command with approved unsandboxed execution and record both results.

- [ ] **Step 3: Build generic watchOS and installed simulator destinations**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apple-watch/RelayWatch.xcodeproj -scheme RelayWatch \
  -configuration Debug -destination 'generic/platform=watchOS' \
  -derivedDataPath /private/tmp/relay-watch-native-generic \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apple-watch/RelayWatch.xcodeproj -scheme RelayWatch \
  -showdestinations
```

Resolve installed 40 mm, 44 mm, and 46 mm simulator destinations from `-showdestinations`. Build each available size with a separate `/private/tmp/relay-watch-native-<size>` derived-data path and `CODE_SIGNING_ALLOWED=NO`. Record unavailable sizes as external gates rather than inventing evidence.

- [ ] **Step 4: Inspect the UI and update test docs truthfully**

Launch the 40 mm simulator when available. Check pairing, clear home, pending queue, approval, question, task summary, instruction, new-task steps, voice, More, offline, largest practical Dynamic Type, and VoiceOver order. Record only observed results. Update TODO/SETUP/physical-device instructions with the final navigation labels and keep physical-device gates pending.

- [ ] **Step 5: Commit documentation, push, and launch Mac for user testing**

```bash
git add docs/TODO.md docs/SETUP.md docs/PHYSICAL-APPLE-WATCH-TEST.md
git commit -m "docs: add native Watch test flow"
git status --short
git push origin main
```

Build and launch the Mac menu app from the reviewed source with the repository root as its working directory so it locates `dist/relay-bridge-arm64`. Give the user this first test path:

1. Find the white UFO in the menu bar.
2. Open **Diagnostics → Refresh**.
3. Confirm bridge and Codex status.
4. Open **Relay Cloud** and sign in when credentials are available.
5. Open **Apple Watch → Start Secure Pairing** only after bridge and cloud show ready.

Do not stage or overwrite the user's Xcode scheme or workspace files.
