import Foundation

protocol RelayPairingServicing: Sendable {
    func submit(
        code: String,
        metadata: RelayDeviceMetadata
    ) async throws -> RelayCloudPreparedPairing
    func poll(_ prepared: RelayCloudPreparedPairing) async throws -> RelayCloudPairingResult
}

extension RelayAPIClient: RelayPairingServicing {}

protocol RelayWatchServicing: Sendable {
    func inbox() async throws -> RelayInbox
    func tasks() async throws -> RelayPage<RelayTask>
    func task(id: String) async throws -> RelayTaskDetail
    func models() async throws -> RelayPage<RelayModel>
    func folders(path: String?) async throws -> RelayFolderListing
    func approve(
        id: String,
        decision: RelayApprovalDecision.Decision,
        dangerousConfirmation: Bool,
        idempotencyKey: String
    ) async throws
    func answer(
        id: String,
        answers: [String: [String]],
        idempotencyKey: String
    ) async throws
    func startTask(_ input: RelayNewTaskInput, idempotencyKey: String) async throws -> String
    func instruction(taskID: String, text: String, idempotencyKey: String) async throws
    func steer(taskID: String, turnID: String, text: String, idempotencyKey: String) async throws
    func stop(taskID: String, turnID: String, idempotencyKey: String) async throws
}

struct RelayWatchService: RelayWatchServicing, Sendable {
    let api: RelayAPIClient

    func inbox() async throws -> RelayInbox {
        try await api.request(.inbox())
    }

    func tasks() async throws -> RelayPage<RelayTask> {
        try await api.request(.tasks())
    }

    func task(id: String) async throws -> RelayTaskDetail {
        try await api.request(.task(id: id))
    }

    func models() async throws -> RelayPage<RelayModel> {
        try await api.request(.models())
    }

    func folders(path: String?) async throws -> RelayFolderListing {
        try await api.request(.folders(path: path))
    }

    func approve(
        id: String,
        decision: RelayApprovalDecision.Decision,
        dangerousConfirmation: Bool,
        idempotencyKey: String
    ) async throws {
        let endpoint = try RelayEndpoint<RelayMutationAcknowledgement>.approve(
            approvalID: id,
            decision: decision,
            dangerousConfirmation: dangerousConfirmation
        )
        _ = try await api.request(endpoint, idempotencyKey: idempotencyKey)
    }

    func answer(
        id: String,
        answers: [String: [String]],
        idempotencyKey: String
    ) async throws {
        let endpoint = try RelayEndpoint<RelayMutationAcknowledgement>.answer(
            questionID: id,
            answers: answers
        )
        _ = try await api.request(endpoint, idempotencyKey: idempotencyKey)
    }

    func startTask(_ input: RelayNewTaskInput, idempotencyKey: String) async throws -> String {
        try await api.request(.startTask(input), idempotencyKey: idempotencyKey).taskId
    }

    func instruction(taskID: String, text: String, idempotencyKey: String) async throws {
        let endpoint = try RelayEndpoint<RelayTurnMutationAcknowledgement>.instruction(
            taskID: taskID,
            text: text
        )
        _ = try await api.request(endpoint, idempotencyKey: idempotencyKey)
    }

    func steer(taskID: String, turnID: String, text: String, idempotencyKey: String) async throws {
        let endpoint = try RelayEndpoint<RelayTurnMutationAcknowledgement>.steer(
            taskID: taskID,
            turnID: turnID,
            text: text
        )
        _ = try await api.request(endpoint, idempotencyKey: idempotencyKey)
    }

    func stop(taskID: String, turnID: String, idempotencyKey: String) async throws {
        let endpoint = try RelayEndpoint<RelayMutationAcknowledgement>.stop(
            taskID: taskID,
            turnID: turnID
        )
        _ = try await api.request(endpoint, idempotencyKey: idempotencyKey)
    }
}
