import Foundation

enum RelayUserError: Error, Equatable, Sendable {
    case offline
    case duplicateAction
    case dangerousConfirmationRequired
    case invalidSelection
    case emptyPrompt
    case taskUnavailable
}

enum RelayMutation: Equatable, Sendable {
    case approval(id: String, decision: RelayApprovalDecision.Decision, dangerous: Bool)
    case question(id: String, answers: [String: [String]])
    case newTask(RelayNewTaskInput)
    case instruction(taskID: String, text: String)
    case steer(taskID: String, turnID: String, text: String)
    case stop(taskID: String, turnID: String)
}

struct RelayMutationAttempt: Equatable, Sendable {
    enum Status: Equatable, Sendable { case pending, failed, succeeded }
    let action: RelayMutation
    let idempotencyKey: String
    var status: Status
}

struct RelayWatchFeatureState: Equatable, Sendable {
    var connection: RelayConnectionState = .offline
    var cacheIsStale = true
    var inbox = RelayInbox(approvals: [], questions: [])
    var tasks: [RelayTask] = []
    var taskDetails: [String: RelayTaskDetail] = [:]
    var models: [RelayModel] = []
    var folders: [RelayFolder] = []
    var attempts: [RelayMutationAttempt] = []
}

actor RelayWatchFeature {
    private let service: any RelayWatchServicing
    private let makeIdempotencyKey: @Sendable () -> String
    private(set) var state: RelayWatchFeatureState
    private var transportRevision = 0

    init(
        service: any RelayWatchServicing,
        state: RelayWatchFeatureState = RelayWatchFeatureState(),
        makeIdempotencyKey: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.service = service
        self.state = state
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    func handle(_ event: RelayTransportEvent) async {
        switch event {
        case .connected:
            transportRevision += 1
            let revision = transportRevision
            state.connection = .live
            state.cacheIsStale = true
            try? await refresh(expectedRevision: revision)
        case .disconnected:
            transportRevision += 1
            markOffline()
        case let .event(event):
            await apply(event)
        case .revoked:
            transportRevision += 1
            state.connection = .revoked
            state.cacheIsStale = true
        case .incompatible:
            transportRevision += 1
            state.connection = .incompatible
            state.cacheIsStale = true
        }
    }

    func refresh() async throws {
        try await refresh(expectedRevision: transportRevision)
    }

    private func refresh(expectedRevision: Int) async throws {
        state.cacheIsStale = true
        do {
            let inbox = try await service.inbox()
            let tasks = try await service.tasks()
            guard
                transportRevision == expectedRevision,
                state.connection == .live
            else {
                throw RelayUserError.offline
            }
            state.inbox = inbox
            state.tasks = tasks.data
            state.taskDetails = [:]
            state.connection = .live
            state.cacheIsStale = false
        } catch {
            if transportRevision == expectedRevision { markOffline() }
            throw error
        }
    }

    func loadTask(_ id: String) async throws {
        state.taskDetails[id] = try await service.task(id: id)
    }

    func loadCreationOptions(path: String? = nil) async throws {
        state.models = try await service.models().data
        state.folders = try await service.folders(path: path).entries
    }

    func approve(_ id: String, dangerousConfirmation: Bool) async throws {
        try requireFresh()
        guard let approval = state.inbox.approvals.first(where: { $0.id == id }) else {
            throw RelayUserError.invalidSelection
        }
        if approval.risk == .dangerous && !dangerousConfirmation {
            throw RelayUserError.dangerousConfirmationRequired
        }
        let action = RelayMutation.approval(
            id: id,
            decision: .approve,
            dangerous: dangerousConfirmation
        )
        try await perform(action) { key in
            try await self.service.approve(
                id: id,
                decision: .approve,
                dangerousConfirmation: dangerousConfirmation,
                idempotencyKey: key
            )
            try await self.refreshInbox()
        }
    }

    func deny(_ id: String) async throws {
        try requireFresh()
        guard state.inbox.approvals.contains(where: { $0.id == id }) else {
            throw RelayUserError.invalidSelection
        }
        let action = RelayMutation.approval(id: id, decision: .deny, dangerous: false)
        try await perform(action) { key in
            try await self.service.approve(
                id: id,
                decision: .deny,
                dangerousConfirmation: false,
                idempotencyKey: key
            )
            try await self.refreshInbox()
        }
    }

    func answer(_ id: String, answers: [String: [String]]) async throws {
        try requireFresh()
        guard let question = state.inbox.questions.first(where: { $0.id == id }) else {
            throw RelayUserError.invalidSelection
        }
        let validated = try question.validatedAnswers(answers)
        let action = RelayMutation.question(id: id, answers: validated)
        try await perform(action) { key in
            try await self.service.answer(id: id, answers: validated, idempotencyKey: key)
            try await self.refreshInbox()
        }
    }

    func sendText(taskID: String, text: String) async throws {
        try requireFresh()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RelayUserError.emptyPrompt }
        let detail = try await detail(for: taskID)
        if detail.status == .running, let turnID = detail.activeTurnId {
            let action = RelayMutation.steer(taskID: taskID, turnID: turnID, text: trimmed)
            try await perform(action) { key in
                try await self.service.steer(
                    taskID: taskID,
                    turnID: turnID,
                    text: trimmed,
                    idempotencyKey: key
                )
                try await self.refreshTask(taskID)
            }
        } else {
            let action = RelayMutation.instruction(taskID: taskID, text: trimmed)
            try await perform(action) { key in
                try await self.service.instruction(
                    taskID: taskID,
                    text: trimmed,
                    idempotencyKey: key
                )
                try await self.refreshTask(taskID)
            }
        }
    }

    func stop(_ taskID: String) async throws {
        try requireFresh()
        let detail = try await detail(for: taskID)
        guard let turnID = detail.activeTurnId else { throw RelayUserError.taskUnavailable }
        let action = RelayMutation.stop(taskID: taskID, turnID: turnID)
        try await perform(action) { key in
            try await self.service.stop(taskID: taskID, turnID: turnID, idempotencyKey: key)
            try await self.refreshTask(taskID)
        }
    }

    func startTask(cwd: String, modelID: String, effort: String, prompt: String) async throws {
        try requireFresh()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RelayUserError.emptyPrompt }
        guard state.folders.contains(where: { $0.path == cwd }) else {
            throw RelayUserError.invalidSelection
        }
        guard
            let model = state.models.first(where: { $0.id == modelID }),
            model.efforts.contains(effort)
        else {
            throw RelayUserError.invalidSelection
        }
        let input = RelayNewTaskInput(cwd: cwd, model: modelID, effort: effort, prompt: trimmed)
        try await perform(.newTask(input)) { key in
            _ = try await self.service.startTask(input, idempotencyKey: key)
            try await self.refreshTasks()
        }
    }

    private func perform(
        _ action: RelayMutation,
        operation: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        try requireFresh()
        let existingIndex = state.attempts.lastIndex { $0.action == action }
        if let existingIndex, state.attempts[existingIndex].status == .pending {
            throw RelayUserError.duplicateAction
        }
        let key: String
        if let existingIndex, state.attempts[existingIndex].status == .failed {
            key = state.attempts[existingIndex].idempotencyKey
            state.attempts[existingIndex].status = .pending
        } else {
            key = makeIdempotencyKey()
            state.attempts.append(
                RelayMutationAttempt(action: action, idempotencyKey: key, status: .pending)
            )
        }
        let index = state.attempts.lastIndex { $0.action == action && $0.idempotencyKey == key }!
        do {
            try await operation(key)
            state.attempts[index].status = .succeeded
        } catch {
            state.attempts[index].status = .failed
            throw error
        }
    }

    private func requireFresh() throws {
        guard state.connection == .live, !state.cacheIsStale else {
            throw RelayUserError.offline
        }
    }

    private func detail(for id: String) async throws -> RelayTaskDetail {
        if let detail = state.taskDetails[id] { return detail }
        let detail = try await service.task(id: id)
        state.taskDetails[id] = detail
        return detail
    }

    private func refreshInbox() async throws {
        state.inbox = try await service.inbox()
    }

    private func refreshTasks() async throws {
        state.tasks = try await service.tasks().data
    }

    private func refreshTask(_ id: String) async throws {
        state.taskDetails[id] = try await service.task(id: id)
        try await refreshTasks()
    }

    private func apply(_ event: RelayEvent) async {
        if event.type.contains("approval") || event.type.contains("question") || event.type.contains("inbox") {
            try? await refreshInbox()
        }
        if event.type.contains("task") {
            try? await refreshTasks()
        }
    }

    private func markOffline() {
        state.connection = .offline
        state.cacheIsStale = true
    }
}
