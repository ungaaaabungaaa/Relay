import Foundation
import Testing
@testable import RelayWatchCore

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

@Test
func compactMaterialGridKeepsTwoRowsBelowOneHundredPoints() {
    #expect(RelayCompactLayout.materialTileMinimumHeight == 44)
    #expect(RelayCompactLayout.gridMinimumHeight(rows: 2) == 92)
    #expect(RelayCompactLayout.gridMinimumHeight(rows: 2) < 100)
}

@Test
func newTaskFlowAdvancesOnlyWithValidStepData() {
    var draft = RelayNewTaskDraft()
    let folders = [folderFixture(path: "/workspace")]
    #expect(!draft.canAdvance(from: .workspace, folders: folders, models: []))
    draft.cwd = "/workspace"
    #expect(draft.canAdvance(from: .workspace, folders: folders, models: []))
    #expect(draft.next(after: .workspace) == .model)
    #expect(draft.next(after: .model) == .prompt)
}

@Test
func newTaskDraftRejectsWorkspaceRemovedFromCurrentAllowedFolders() {
    var draft = RelayNewTaskDraft()
    draft.cwd = "/previously-allowed"

    #expect(!draft.canAdvance(
        from: .workspace,
        folders: [folderFixture(path: "/currently-allowed")],
        models: []
    ))
}

@Test
func newTaskDraftUsesAdvertisedDefaultModelAndEffort() {
    let models = [
        modelFixture(id: "fallback", defaultEffort: "medium", isDefault: false),
        modelFixture(id: "preferred", defaultEffort: "high", isDefault: true),
    ]
    var draft = RelayNewTaskDraft()

    draft.applyDefaults(folders: [folderFixture(path: "/workspace")], models: models)

    #expect(draft.cwd == "/workspace")
    #expect(draft.modelID == "preferred")
    #expect(draft.effort == "high")
    #expect(RelayNewTaskPresentation.finalActionTitle == "Start reviewed task")
}

@Test
func activeTaskSummaryUsesOnlyTheLatestActivity() {
    let detail = RelayTaskDetail(
        id: "task", title: "Build Watch UI", preview: "Working",
        cwd: "/Users/developer/Relay/watch-native-ui", updatedAt: 2, status: .running,
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
    #expect(summary.latestActivityStatus == "Running")
    #expect(summary.workspaceName == "watch-native-ui")
    #expect(summary.workspaceAccessibilityLabel == "Workspace /Users/developer/Relay/watch-native-ui")
    #expect(summary.canStop)
}

@Test
func taskRowsUseStateSpecificSymbolsAndShortTimeContext() {
    let symbols = [
        RelayTaskPresentation.row(taskFixture(id: "idle", status: .idle), nowSeconds: 121).systemImage,
        RelayTaskPresentation.row(taskFixture(id: "running", status: .running), nowSeconds: 121).systemImage,
        RelayTaskPresentation.row(taskFixture(id: "error", status: .error), nowSeconds: 121).systemImage,
        RelayTaskPresentation.row(taskFixture(id: "offline", status: .offline), nowSeconds: 121).systemImage,
    ]
    let running = RelayTaskPresentation.row(
        taskFixture(id: "running", status: .running),
        nowSeconds: 121
    )

    #expect(symbols == [
        "pause.circle", "play.circle.fill", "exclamationmark.triangle.fill", "wifi.slash",
    ])
    #expect(running.statusAndTime == "Running · 2m ago")
}

@Test
func instructionTargetFallsBackToTheRunningCurrentTask() {
    let idle = taskFixture(id: "idle", status: .idle)
    let running = taskFixture(id: "running", status: .running)

    let target = RelayTaskPresentation.instructionTask(
        routeTaskID: nil,
        selectedTaskID: nil,
        tasks: [idle, running]
    )

    #expect(target?.id == "running")
}

@Test
func instructionTargetRejectsAStaleSelectionWithoutRunningFallback() {
    let idle = taskFixture(id: "idle", status: .idle)

    let target = RelayTaskPresentation.instructionTask(
        routeTaskID: nil,
        selectedTaskID: "stale-task",
        tasks: [idle]
    )

    #expect(target == nil)
}

@Test
func explicitInstructionRouteRejectsAStaleTaskWithoutRunningFallback() {
    let running = taskFixture(id: "running", status: .running)

    let target = RelayTaskPresentation.instructionTask(
        routeTaskID: "stale-route",
        selectedTaskID: "running",
        tasks: [running]
    )

    #expect(target == nil)
}

@Test
func cachedTaskSummaryRemainsReviewableWithoutDetail() {
    let summary = RelayTaskPresentation.summary(taskFixture(id: "cached", status: .offline))

    #expect(summary.statusTitle == "Offline")
    #expect(summary.workspaceName == "workspace")
    #expect(summary.latestActivityTitle == "Cached preview")
    #expect(summary.latestActivityStatus == "Offline")
    #expect(summary.workspaceAccessibilityLabel == "Workspace /workspace")
    #expect(!summary.canStop)
    #expect(!summary.canViewActivity)
}

private func taskFixture(id: String, status: RelayTask.Status) -> RelayTask {
    RelayTask(
        id: id,
        title: "Task \(id)",
        preview: "Cached preview",
        cwd: "/workspace",
        updatedAt: 1,
        status: status
    )
}

private func folderFixture(path: String) -> RelayFolder {
    RelayFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path, kind: .root)
}

private func modelFixture(
    id: String,
    defaultEffort: String,
    isDefault: Bool
) -> RelayModel {
    RelayModel(
        id: id,
        name: id.capitalized,
        description: "Model",
        efforts: ["medium", "high"],
        defaultEffort: defaultEffort,
        isDefault: isDefault
    )
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

@Test
func watchSourcesUseNativeNavigationAndNoCustomBackButton() throws {
    let sources = try relayWatchSources()
    let allSources = sources.values.joined(separator: "\n")
    #expect(!allSources.contains("RelayWatchScreen"))
    #expect(!allSources.contains("RelayBackButton"))
    #expect(allSources.contains("NavigationStack(path:"))
    #expect(allSources.contains("Image(systemName:"))
    #expect(sources["RelayWatchNavigation.swift"]?.contains("enum RelayWatchRoute") == true)
    #expect(sources["RelayWatchModel.swift"]?.contains("func show(") == false)
}

@Test
func utilityViewsRouteFeedbackAndIdentityThroughTheNativeWatchContracts() throws {
    let haptics = try relayWatchSource(named: "RelayHaptics.swift")
    let model = try relayWatchSource(named: "RelayWatchModel.swift")
    let approval = try relayWatchSource(named: "RelayApprovalView.swift")
    let components = try relayWatchSource(named: "RelayWatchComponents.swift")
    let more = try relayWatchSource(named: "RelayMoreViews.swift")
    let root = try relayWatchSource(named: "RelayWatchRootView.swift")

    #expect(haptics.contains("static let key = \"relay.watch.haptics.enabled\""))
    #expect(haptics.contains("guard hapticPreference.isEnabled else { return }"))
    #expect(model.contains("playRelayHaptic(.failure)"))
    #expect(model.contains("playRelayHaptic(.success)"))
    #expect(approval.contains("playRelayHaptic(.notification)"))
    #expect(components.contains("RelayCompactLayout.materialTileMinimumHeight"))
    #expect(components.contains("RelayStatusPresentation.make"))
    #expect(components.contains(".fixedSize(horizontal: false, vertical: true)"))
    #expect(!components.contains(".lineLimit(1)"))
    #expect(more.contains("RelayAdaptiveContainer"))
    #expect(more.contains("RelayCompactLayout.materialGridSpacing"))
    #expect(try relayWatchSource(named: "RelayPairingViews.swift").contains(
        "private var codeEntry: some View {\n        RelayAdaptiveContainer"
    ))
    #expect(more.contains("struct RelayIdentityView"))
    #expect(more.contains("CFBundleShortVersionString"))
    #expect(root.contains("case .more: RelayMoreView(model: model)"))
}

@Test
func terminalConnectionTransitionsClearTheNavigationPath() throws {
    let model = try relayWatchSource(named: "RelayWatchModel.swift")

    #expect(model.contains("case .approved:\n                        popToRoot()"))
    #expect(model.contains("catch RelayAPIError.incompatible {\n                popToRoot()"))
    #expect(model.contains("func revokeLocally() {\n        pairingTask?.cancel()\n        transportTask?.cancel()\n        popToRoot()"))
    #expect(model.contains("func pairAgain() {\n        popToRoot()"))
}

@Test
func routeDestinationsUseTheirStableIdentityInsteadOfMutableSelection() throws {
    let root = try relayWatchSource(named: "RelayWatchRootView.swift")
    let approval = try relayWatchSource(named: "RelayApprovalView.swift")
    let question = try relayWatchSource(named: "RelayQuestionView.swift")
    let task = try relayWatchSource(named: "RelayTaskViews.swift")

    #expect(root.contains("case let .approval(id): RelayApprovalView(model: model, approvalID: id)"))
    #expect(root.contains("case let .question(id): RelayQuestionView(model: model, questionID: id)"))
    #expect(root.contains("case let .task(id): RelayTaskSummaryView(model: model, taskID: id)"))
    #expect(root.contains("case let .activity(id): RelayTaskActivityView(model: model, taskID: id)"))
    #expect(approval.contains("model.inbox.approvals.first { $0.id == approvalID }"))
    #expect(question.contains("model.inbox.questions.first { $0.id == questionID }"))
    #expect(task.contains("model.taskDetails[taskID]"))
}

@Test
func taskSourcesKeepSummaryControlsSeparateFromTheActivityList() throws {
    let task = try relayWatchSource(named: "RelayTaskViews.swift")
    let compose = try relayWatchSource(named: "RelayComposeViews.swift")

    #expect(task.contains("NavigationLink(value: RelayWatchRoute.task(task.id))"))
    #expect(task.contains("struct RelayTaskSummaryView"))
    #expect(task.contains("Button(\"Instruct\")"))
    #expect(task.contains("Button(\"View full activity\")"))
    #expect(task.contains("struct RelayTaskActivityView"))
    #expect(task.contains("Image(systemName: row.systemImage)"))
    #expect(task.contains("Text(row.statusAndTime)"))
    #expect(task.contains(".accessibilityLabel(summary.workspaceAccessibilityLabel)"))
    #expect(task.contains("Text(summary.latestActivityStatus)"))
    #expect(compose.contains("@State private var step = RelayNewTaskStep.workspace"))
    #expect(compose.contains("Button(\"Send\")"))
    #expect(compose.contains("Section(\"1 of 3 · Workspace\")"))
    #expect(compose.contains("Section(\"2 of 3 · Model\")"))
    #expect(compose.contains("Section(\"3 of 3 · Review\")"))
    #expect(compose.contains("Button(RelayNewTaskPresentation.finalActionTitle)"))
    #expect(compose.contains("folders: model.folders"))
}

@Test
func decodesBridgeTaskAndRejectsUnknownApprovalRisk() throws {
    let task = try JSONDecoder().decode(
        RelayTask.self,
        from: Data(#"{"id":"task-1","title":"Build Relay","preview":"Ship the Apple client","cwd":"/workspace","updatedAt":1000,"status":"running"}"#.utf8)
    )
    #expect(task.id == "task-1")
    #expect(task.status == .running)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            RelayApproval.self,
            from: Data(#"{"id":"approval-1","threadId":"task-1","turnId":"turn-1","itemId":"item-1","kind":"command","risk":"critical","riskReasons":[],"command":"pnpm test","cwd":"/workspace","reason":null,"startedAtMs":1000}"#.utf8)
        )
    }
}

@Test
func questionAnswersRejectOptionsNotAdvertisedByTheBridge() throws {
    let question = try JSONDecoder().decode(
        RelayQuestion.self,
        from: Data(#"{"id":"question-1","threadId":"task-1","turnId":"turn-1","itemId":"item-1","questions":[{"id":"channel","header":"Release","question":"Choose a channel","options":[{"label":"Beta","description":"Preview"},{"label":"Stable","description":"General availability"}]}]}"#.utf8)
    )

    #expect(try question.validatedAnswers(["channel": ["Beta"]]) == ["channel": ["Beta"]])
    #expect(throws: RelayQuestionAnswerError.invalidOption) {
        try question.validatedAnswers(["channel": ["Nightly"]])
    }
}

@Test
func questionProgressRequiresEveryAnswerBeforeSend() throws {
    let progress = RelayQuestionProgress(questionCount: 2)

    #expect(progress.title(at: 0) == "Question 1 of 2")
    #expect(progress.actionTitle(at: 0) == "Next question")
    #expect(progress.actionTitle(at: 1) == "Send answer")
    #expect(!progress.canSubmit(answeredQuestionIDs: ["one"], requiredIDs: ["one", "two"]))
}

@Test
func questionActionHintDistinguishesLocalAdvanceFromFinalSubmission() {
    let progress = RelayQuestionProgress(questionCount: 2)

    #expect(progress.actionHint(at: 0) == "Advances locally without sending an answer")
    #expect(progress.actionHint(at: 1) == "Sends only the selected Mac-provided answers to Codex")
}

@Test
func offlineStatusKeepsLiteralStateAndExposesTheFullErrorSeparately() {
    let presentation = RelayStatusPresentation.make(
        connection: .offline,
        cacheIsStale: true,
        error: "The Mac could not refresh because the encrypted session expired."
    )

    #expect(presentation.title == "Mac offline · cached data")
    #expect(presentation.systemImage == "wifi.slash")
    #expect(presentation.detail == "The Mac could not refresh because the encrypted session expired.")
    #expect(presentation.isAttention)
}

@Test
func approvalSourceRendersReviewDataAndDangerousSafeguards() throws {
    let source = try relayWatchSource(named: "RelayApprovalView.swift")

    #expect(source.contains("RelayAdaptiveContainer"))
    #expect(source.contains("Risk: \\(approval.risk.rawValue.capitalized)"))
    #expect(source.contains(".foregroundStyle(approval.risk == .dangerous ? .orange : .primary)"))
    #expect(!source.contains(".foregroundStyle(.red)"))
    #expect(source.contains("Text(\"Command\")"))
    #expect(source.contains("Text(command)"))
    #expect(source.contains("Text(\"Reason\")"))
    #expect(source.contains("Text(reason)"))
    #expect(source.contains("Text(\"Working directory\")"))
    #expect(source.contains("Label(cwd, systemImage: \"folder\")"))
    #expect(source.contains("ForEach(consequences(for: approval), id: \\.self)"))
    #expect(source.contains("playRelayHaptic(.notification)"))
    #expect(source.contains("confirmNormal"))
    #expect(source.contains("confirmDangerous"))
    #expect(source.contains("Button(\"Deny\", role: .destructive)"))
    #expect(source.contains("Button(\"Approve dangerous action\", role: .destructive)"))
    #expect(!source.contains("lineLimit"))
}

@Test
func mutationEndpointsAreMarkedAndEncodeTheirLiteralBody() throws {
    let endpoint = try RelayEndpoint<RelayMutationAcknowledgement>.approve(
        approvalID: "approval-1",
        decision: .approve,
        dangerousConfirmation: true
    )

    #expect(endpoint.method == "POST")
    #expect(endpoint.path == "/v1/approvals/approval-1")
    #expect(endpoint.isMutation)
    #expect(
        try JSONDecoder().decode(
            RelayApprovalDecision.self,
            from: endpoint.body
        ) == RelayApprovalDecision(
            decision: .approve,
            dangerousConfirmation: true
        )
    )
    #expect(!RelayEndpoint<RelayPage<RelayTask>>.tasks().isMutation)
}

@Test
func debugOriginDerivesMatchedHTTPAndWebSocketOrigins() throws {
    let environment = try RelayEnvironment.resolve(
        processEnvironment: ["RELAY_CLOUD_ORIGIN": "http://127.0.0.1:8787"],
        isDebugBuild: true
    )

    #expect(environment.name == .localDevelopment)
    #expect(environment.httpOrigin.absoluteString == "http://127.0.0.1:8787")
    #expect(environment.webSocketOrigin.absoluteString == "ws://127.0.0.1:8787")
}

@Test
func releaseConfigurationRejectsDevelopmentOverride() throws {
    #expect(throws: RelayEnvironmentError.releaseOverrideForbidden) {
        try RelayEnvironment.resolve(
            processEnvironment: ["RELAY_CLOUD_ORIGIN": "http://127.0.0.1:8787"],
            isDebugBuild: false
        )
    }
}

@Test(arguments: [
    "https://user@example.com",
    "https://api.example.com?mode=staging",
    "https://api.example.com/#fragment",
    "https://api.example.com/relay",
    "http://api.example.com",
])
func debugOriginRejectsUnsafeOrInvalidOrigins(_ origin: String) {
    #expect(throws: RelayEnvironmentError.self) {
        try RelayEnvironment.resolve(
            processEnvironment: ["RELAY_CLOUD_ORIGIN": origin],
            isDebugBuild: true
        )
    }
}
