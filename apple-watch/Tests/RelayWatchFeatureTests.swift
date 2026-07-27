import Foundation
import Testing
@testable import RelayWatchCore

@Test
func disconnectMarksSnapshotsStaleAndEveryMutationFailsClosed() async throws {
    let service = WatchServiceFake()
    let feature = RelayWatchFeature(service: service, state: featureState(cacheIsStale: false))
    await feature.handle(.disconnected(.network))
    #expect(await feature.state.cacheIsStale)

    await #expect(throws: RelayUserError.offline) {
        try await feature.approve("approval-1", dangerousConfirmation: true)
    }
    await #expect(throws: RelayUserError.offline) {
        try await feature.answer("question-1", answers: ["channel": ["Beta"]])
    }
    await #expect(throws: RelayUserError.offline) {
        try await feature.sendText(taskID: "task-1", text: "Continue")
    }
    await #expect(throws: RelayUserError.offline) { try await feature.stop("task-1") }
    await #expect(throws: RelayUserError.offline) {
        try await feature.startTask(
            cwd: "/workspace",
            modelID: "gpt-5",
            effort: "high",
            prompt: "Build Relay"
        )
    }
    #expect(await service.mutationKeys.isEmpty)
}

@Test
func reconnectRefreshesInboxAndTasksBeforeActionsBecomeFresh() async {
    let service = WatchServiceFake()
    await service.setInbox(RelayInbox(approvals: [approvalFixture], questions: []))
    await service.setTasks([taskFixture])
    let feature = RelayWatchFeature(service: service)

    await feature.handle(.connected(reconnected: true))
    let state = await feature.state
    #expect(state.connection == .live)
    #expect(!state.cacheIsStale)
    #expect(state.inbox.approvals.map(\.id) == ["approval-1"])
    #expect(state.tasks.map(\.id) == ["task-1"])
}

@Test
func disconnectDuringReconnectRefreshCannotPublishFreshState() async {
    let service = WatchServiceFake(blockReads: true)
    let feature = RelayWatchFeature(service: service)
    let connecting = Task { await feature.handle(.connected(reconnected: true)) }
    #expect(await service.waitForInboxCount(1))

    await feature.handle(.disconnected(.network))
    await service.releaseReads()
    await connecting.value

    let state = await feature.state
    #expect(state.connection == .offline)
    #expect(state.cacheIsStale)
}

@Test
func duplicateTapRunsOnceRetryKeepsKeyAndNewActionGetsNewKey() async throws {
    let service = WatchServiceFake(blockFirstMutation: true)
    let counter = FeatureCounter()
    let feature = RelayWatchFeature(
        service: service,
        state: featureState(cacheIsStale: false),
        makeIdempotencyKey: { "feature-key-\(counter.next())" }
    )
    let first = Task { try await feature.approve("approval-1", dangerousConfirmation: true) }
    #expect(await service.waitForMutationCount(1))
    await #expect(throws: RelayUserError.duplicateAction) {
        try await feature.approve("approval-1", dangerousConfirmation: true)
    }
    await service.releaseMutation()
    try await first.value
    #expect(await service.mutationKeys.count == 1)

    await service.failNextMutation()
    await #expect(throws: WatchServiceFake.Failure.rejected) {
        try await feature.approve("approval-1", dangerousConfirmation: true)
    }
    try await feature.approve("approval-1", dangerousConfirmation: true)
    let keys = await service.mutationKeys
    #expect(keys[1] == keys[2])

    try await feature.approve("approval-1", dangerousConfirmation: true)
    let finalKeys = await service.mutationKeys
    #expect(finalKeys[3] != finalKeys[2])
}

@Test
func pushedApprovalRefreshesInboxAndTextRoutesByTaskStatus() async throws {
    let service = WatchServiceFake()
    var initial = featureState(cacheIsStale: false)
    initial.inbox = RelayInbox(approvals: [], questions: [])
    let feature = RelayWatchFeature(service: service, state: initial)
    await service.setInbox(RelayInbox(approvals: [approvalFixture], questions: []))
    await feature.handle(
        .event(RelayEvent(id: 1, type: "approval.updated", data: .null, createdAt: 1))
    )
    #expect((await feature.state).inbox.approvals.map(\.id) == ["approval-1"])

    try await feature.sendText(taskID: "task-1", text: "Steer now")
    #expect(await service.operations.contains("steer"))
    await service.setTaskDetail(idleTaskDetail)
    try await feature.loadTask("task-1")
    try await feature.sendText(taskID: "task-1", text: "Next instruction")
    #expect(await service.operations.contains("instruction"))
}

@Test
func newTaskRequiresAdvertisedFolderModelEffortAndPrompt() async throws {
    let service = WatchServiceFake()
    let feature = RelayWatchFeature(service: service, state: featureState(cacheIsStale: false))

    await #expect(throws: RelayUserError.invalidSelection) {
        try await feature.startTask(
            cwd: "/not-allowed", modelID: "gpt-5", effort: "high", prompt: "Build"
        )
    }
    await #expect(throws: RelayUserError.invalidSelection) {
        try await feature.startTask(
            cwd: "/workspace", modelID: "gpt-5", effort: "unknown", prompt: "Build"
        )
    }
    await #expect(throws: RelayUserError.emptyPrompt) {
        try await feature.startTask(
            cwd: "/workspace", modelID: "gpt-5", effort: "high", prompt: "   "
        )
    }
    #expect(await service.mutationKeys.isEmpty)

    try await feature.startTask(
        cwd: "/workspace", modelID: "gpt-5", effort: "high", prompt: "Build"
    )
    #expect(await service.operations.contains("start"))
}

private func featureState(cacheIsStale: Bool) -> RelayWatchFeatureState {
    RelayWatchFeatureState(
        connection: .live,
        cacheIsStale: cacheIsStale,
        inbox: RelayInbox(approvals: [approvalFixture], questions: [questionFixture]),
        tasks: [taskFixture],
        taskDetails: ["task-1": runningTaskDetail],
        models: [modelFixture],
        folders: [folderFixture]
    )
}

private let taskFixture = RelayTask(
    id: "task-1", title: "Relay", preview: "Working", cwd: "/workspace",
    updatedAt: 1, status: .running
)
private let runningTaskDetail = RelayTaskDetail(
    id: "task-1", title: "Relay", preview: "Working", cwd: "/workspace",
    updatedAt: 1, status: .running, activeTurnId: "turn-1", activity: []
)
private let idleTaskDetail = RelayTaskDetail(
    id: "task-1", title: "Relay", preview: "Ready", cwd: "/workspace",
    updatedAt: 2, status: .idle, activeTurnId: nil, activity: []
)
private let approvalFixture = RelayApproval(
    id: "approval-1", threadId: "task-1", turnId: "turn-1", itemId: "item-1",
    kind: .command, risk: .dangerous, riskReasons: ["remote write"],
    command: "git push", cwd: "/workspace", reason: nil, startedAtMs: 1
)
private let questionFixture = RelayQuestion(
    id: "question-1", threadId: "task-1", turnId: "turn-1", itemId: "item-2",
    questions: [
        RelayQuestion.Item(
            id: "channel", header: "Release", question: "Choose",
            options: [RelayQuestion.Item.Option(label: "Beta", description: "Preview")]
        ),
    ]
)
private let modelFixture = RelayModel(
    id: "gpt-5", name: "GPT-5", description: "Model", efforts: ["high"],
    defaultEffort: "high", isDefault: true
)
private let folderFixture = RelayFolder(name: "workspace", path: "/workspace", kind: .root)

private actor WatchServiceFake: RelayWatchServicing {
    enum Failure: Error { case rejected }
    private var inboxValue = RelayInbox(approvals: [approvalFixture], questions: [questionFixture])
    private var taskValues = [taskFixture]
    private var detailValue = runningTaskDetail
    private var blockMutation: Bool
    private var blockReads: Bool
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    private var inboxCallCount = 0
    private var shouldFail = false
    private(set) var mutationKeys: [String] = []
    private(set) var operations: [String] = []

    init(blockFirstMutation: Bool = false, blockReads: Bool = false) {
        blockMutation = blockFirstMutation
        self.blockReads = blockReads
    }
    func setInbox(_ inbox: RelayInbox) { inboxValue = inbox }
    func setTasks(_ tasks: [RelayTask]) { taskValues = tasks }
    func setTaskDetail(_ detail: RelayTaskDetail) { detailValue = detail }
    func failNextMutation() { shouldFail = true }
    func inbox() async throws -> RelayInbox {
        inboxCallCount += 1
        if blockReads { await withCheckedContinuation { readWaiters.append($0) } }
        return inboxValue
    }
    func tasks() async throws -> RelayPage<RelayTask> { .init(data: taskValues, nextCursor: nil) }
    func task(id: String) async throws -> RelayTaskDetail { detailValue }
    func models() async throws -> RelayPage<RelayModel> { .init(data: [modelFixture], nextCursor: nil) }
    func folders(path: String?) async throws -> RelayFolderListing {
        .init(path: path, entries: [folderFixture])
    }

    func approve(
        id: String, decision: RelayApprovalDecision.Decision,
        dangerousConfirmation: Bool, idempotencyKey: String
    ) async throws {
        try await mutation("approval", key: idempotencyKey)
    }
    func answer(id: String, answers: [String: [String]], idempotencyKey: String) async throws {
        try await mutation("question", key: idempotencyKey)
    }
    func startTask(_ input: RelayNewTaskInput, idempotencyKey: String) async throws -> String {
        try await mutation("start", key: idempotencyKey)
        return "created"
    }
    func instruction(taskID: String, text: String, idempotencyKey: String) async throws {
        try await mutation("instruction", key: idempotencyKey)
    }
    func steer(taskID: String, turnID: String, text: String, idempotencyKey: String) async throws {
        try await mutation("steer", key: idempotencyKey)
    }
    func stop(taskID: String, turnID: String, idempotencyKey: String) async throws {
        try await mutation("stop", key: idempotencyKey)
    }

    func waitForMutationCount(_ count: Int) async -> Bool {
        for _ in 0..<10_000 {
            if mutationKeys.count >= count { return true }
            await Task.yield()
        }
        return mutationKeys.count >= count
    }
    func releaseMutation() {
        blockMutation = false
        let waiters = mutationWaiters
        mutationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForInboxCount(_ count: Int) async -> Bool {
        for _ in 0..<10_000 {
            if inboxCallCount >= count { return true }
            await Task.yield()
        }
        return inboxCallCount >= count
    }
    func releaseReads() {
        blockReads = false
        let waiters = readWaiters
        readWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func mutation(_ operation: String, key: String) async throws {
        mutationKeys.append(key)
        operations.append(operation)
        if blockMutation {
            await withCheckedContinuation { mutationWaiters.append($0) }
        }
        if shouldFail {
            shouldFail = false
            throw Failure.rejected
        }
    }
}

private final class FeatureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}
