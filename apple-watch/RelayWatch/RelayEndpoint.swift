import Foundation

struct RelayEndpoint<Response: Decodable & Sendable>: Sendable {
    let method: String
    let path: String
    let body: Data
    let isMutation: Bool

    init(method: String, path: String, body: Data = Data(), isMutation: Bool) {
        self.method = method
        self.path = path
        self.body = body
        self.isMutation = isMutation
    }
}

enum RelayEndpointError: Error, Equatable, Sendable {
    case invalidIdentifier
}

extension RelayEndpoint where Response == RelayPage<RelayTask> {
    static func tasks(cursor: String? = nil) -> Self {
        guard let cursor, !cursor.isEmpty else {
            return Self(method: "GET", path: "/v1/tasks", isMutation: false)
        }
        var components = URLComponents()
        components.path = "/v1/tasks"
        components.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        return Self(method: "GET", path: components.string ?? "/v1/tasks", isMutation: false)
    }
}

extension RelayEndpoint where Response == RelayTaskDetail {
    static func task(id: String) throws -> Self {
        Self(method: "GET", path: "/v1/tasks/\(try pathSegment(id))", isMutation: false)
    }
}

extension RelayEndpoint where Response == RelayInbox {
    static func inbox() -> Self {
        Self(method: "GET", path: "/v1/inbox", isMutation: false)
    }
}

extension RelayEndpoint where Response == RelayPage<RelayModel> {
    static func models() -> Self {
        Self(method: "GET", path: "/v1/models", isMutation: false)
    }
}

extension RelayEndpoint where Response == RelayFolderListing {
    static func folders(path: String? = nil) -> Self {
        guard let path, !path.isEmpty else {
            return Self(method: "GET", path: "/v1/folders", isMutation: false)
        }
        var components = URLComponents()
        components.path = "/v1/folders"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return Self(method: "GET", path: components.string ?? "/v1/folders", isMutation: false)
    }
}

extension RelayEndpoint where Response == RelayMutationAcknowledgement {
    static func approve(
        approvalID: String,
        decision: RelayApprovalDecision.Decision,
        dangerousConfirmation: Bool
    ) throws -> Self {
        try Self(
            method: "POST",
            path: "/v1/approvals/\(pathSegment(approvalID))",
            body: JSONEncoder().encode(
                RelayApprovalDecision(
                    decision: decision,
                    dangerousConfirmation: dangerousConfirmation ? true : nil
                )
            ),
            isMutation: true
        )
    }

    static func answer(questionID: String, answers: [String: [String]]) throws -> Self {
        try Self(
            method: "POST",
            path: "/v1/questions/\(pathSegment(questionID))",
            body: JSONEncoder().encode(RelayQuestionAnswers(answers: answers)),
            isMutation: true
        )
    }

    static func stop(taskID: String, turnID: String) throws -> Self {
        try Self(
            method: "POST",
            path: "/v1/tasks/\(pathSegment(taskID))/stop",
            body: JSONEncoder().encode(RelayStopInput(turnId: turnID)),
            isMutation: true
        )
    }
}

extension RelayEndpoint where Response == RelayTaskMutationAcknowledgement {
    static func startTask(_ input: RelayNewTaskInput) throws -> Self {
        Self(
            method: "POST",
            path: "/v1/tasks",
            body: try JSONEncoder().encode(input),
            isMutation: true
        )
    }
}

extension RelayEndpoint where Response == RelayTurnMutationAcknowledgement {
    static func instruction(taskID: String, text: String) throws -> Self {
        try Self(
            method: "POST",
            path: "/v1/tasks/\(pathSegment(taskID))/instructions",
            body: JSONEncoder().encode(RelayInstructionInput(text: text)),
            isMutation: true
        )
    }

    static func steer(taskID: String, turnID: String, text: String) throws -> Self {
        try Self(
            method: "POST",
            path: "/v1/tasks/\(pathSegment(taskID))/steer",
            body: JSONEncoder().encode(RelaySteerInput(turnId: turnID, text: text)),
            isMutation: true
        )
    }
}

extension RelayEndpoint where Response == RelayTranscription {
    static func transcription(durationMs: Int) throws -> Self {
        guard durationMs > 0 else { throw RelayEndpointError.invalidIdentifier }
        var components = URLComponents()
        components.path = "/v1/transcribe"
        components.queryItems = [URLQueryItem(name: "durationMs", value: String(durationMs))]
        return Self(method: "POST", path: components.string ?? "/v1/transcribe", isMutation: true)
    }
}

private func pathSegment(_ value: String) throws -> String {
    guard
        !value.isEmpty,
        !value.contains("/"),
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else {
        throw RelayEndpointError.invalidIdentifier
    }
    return encoded
}
