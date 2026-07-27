import Foundation
import Testing
@testable import RelayWatchCore

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
