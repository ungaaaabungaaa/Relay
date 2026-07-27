import CryptoKit
import Foundation
import Testing
@testable import RelayWatchCore

private let testConfig = RelayCloudDeviceConfig(
    accountId: "account-1",
    hostId: "host-1",
    deviceId: "watch-1",
    credential: "device-secret",
    rootKey: Data(repeating: 9, count: 32),
    apiVersion: 1
)

@Test
func concurrentResponsesRouteByRequestIDAndPublishInterleavedEvent() async throws {
    let socket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [socket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))

    let tasksRequest = Task {
        try await fixture.client.request(RelayEndpoint<RelayPage<RelayTask>>.tasks())
    }
    let inboxRequest = Task {
        try await fixture.client.request(RelayEndpoint<RelayInbox>.inbox())
    }
    let first = try await socket.nextSentEnvelope()
    let second = try await socket.nextSentEnvelope()
    let requests = try [first, second].map { envelope in
        (envelope, try decodeInner(envelope, rootKey: testConfig.rootKey))
    }
    let tasksEnvelope = try #require(requests.first { requestPath($0.1) == "/v1/tasks" }?.0)
    let inboxEnvelope = try #require(requests.first { requestPath($0.1) == "/v1/inbox" }?.0)

    try await socket.push(
        hostEnvelope(
            sequence: 1,
            inner: [
                "kind": "response",
                "body": [
                    "requestId": inboxEnvelope.messageID,
                    "status": 200,
                    "headers": ["content-type": "application/json"],
                    "body": #"{"approvals":[],"questions":[]}"#,
                ],
            ]
        )
    )
    let relayEvent = RelayEvent(
        id: 7,
        type: "task.updated",
        data: .object(["taskId": .string("task-1")]),
        createdAt: 1_000
    )
    try await socket.push(
        hostEnvelope(
            sequence: 2,
            inner: [
                "kind": "event",
                "body": try jsonObject(relayEvent),
            ]
        )
    )
    try await socket.push(
        hostEnvelope(
            sequence: 3,
            inner: [
                "kind": "response",
                "body": [
                    "requestId": tasksEnvelope.messageID,
                    "status": 200,
                    "headers": ["content-type": "application/json"],
                    "body": #"{"data":[],"nextCursor":null}"#,
                ],
            ]
        )
    )

    #expect(try await inboxRequest.value == RelayInbox(approvals: [], questions: []))
    #expect(try await tasksRequest.value == RelayPage<RelayTask>(data: [], nextCursor: nil))
    #expect(await events.next() == .event(relayEvent))
    #expect(fixture.store.hostSequence == 3)
    await fixture.client.stop()
}

@Test
func replayStateSurvivesReconnectAndRejectsAnOldHostEnvelope() async throws {
    let firstSocket = ControlledRelaySocket()
    let secondSocket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [firstSocket, secondSocket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))

    let firstRequest = Task {
        try await fixture.client.request(RelayEndpoint<RelayInbox>.inbox())
    }
    let sent = try await firstSocket.nextSentEnvelope()
    try await firstSocket.push(
        hostResponse(sequence: 8, requestID: sent.messageID, body: #"{"approvals":[],"questions":[]}"#)
    )
    _ = try await firstRequest.value
    #expect(fixture.store.hostSequence == 8)

    await firstSocket.fail(RelaySocketError.network)
    #expect(await events.next() == .disconnected(.network))
    #expect(await events.next() == .connected(reconnected: true))
    let replayedRequest = Task {
        try await fixture.client.request(RelayEndpoint<RelayInbox>.inbox())
    }
    let replayedSent = try await secondSocket.nextSentEnvelope()
    try await secondSocket.push(
        hostResponse(sequence: 8, requestID: replayedSent.messageID, body: #"{"approvals":[],"questions":[]}"#)
    )
    await #expect(throws: RelayAPIError.invalidEnvelope) {
        try await replayedRequest.value
    }
    #expect(fixture.store.hostSequence == 8)
    await fixture.client.stop()
}

@Test
func disconnectFailsPendingMutationAndReconnectDoesNotReplayIt() async throws {
    let firstSocket = ControlledRelaySocket()
    let secondSocket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [firstSocket, secondSocket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))

    let mutation = Task {
        try await fixture.client.request(
            RelayEndpoint<RelayMutationAcknowledgement>.stop(
                taskID: "task-1",
                turnID: "turn-1"
            ),
            idempotencyKey: "stop-task-1-turn-1"
        )
    }
    _ = try await firstSocket.nextSentEnvelope()
    await firstSocket.fail(RelaySocketError.network)
    await #expect(throws: RelayAPIError.offline) {
        try await mutation.value
    }
    #expect(await events.next() == .disconnected(.network))
    #expect(await events.next() == .connected(reconnected: true))
    #expect(await secondSocket.sentCount == 0)
    await fixture.client.stop()
}

@Test
func cancellingARequestRemovesItsContinuationWithoutStoppingTheRouter() async throws {
    let socket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [socket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))

    let cancelled = Task {
        try await fixture.client.request(RelayEndpoint<RelayInbox>.inbox())
    }
    _ = try await socket.nextSentEnvelope()
    cancelled.cancel()
    await #expect(throws: CancellationError.self) {
        try await cancelled.value
    }

    let healthy = Task {
        try await fixture.client.request(RelayEndpoint<RelayInbox>.inbox())
    }
    let healthyEnvelope = try await socket.nextSentEnvelope()
    try await socket.push(
        hostResponse(
            sequence: 1,
            requestID: healthyEnvelope.messageID,
            body: #"{"approvals":[],"questions":[]}"#
        )
    )
    #expect(try await healthy.value == RelayInbox(approvals: [], questions: []))
    await fixture.client.stop()
}

@Test
func reconnectBackoffCapsAtThirtySeconds() {
    let policy = RelayReconnectPolicy()
    #expect(policy.delay(forAttempt: 0) == .seconds(1))
    #expect(policy.delay(forAttempt: 1) == .seconds(2))
    #expect(policy.delay(forAttempt: 4) == .seconds(16))
    #expect(policy.delay(forAttempt: 5) == .seconds(30))
    #expect(policy.delay(forAttempt: 50) == .seconds(30))
}

@Test(arguments: [401, 403])
func handshakeAuthorizationFailureErasesEveryDeviceSecret(_ status: Int) async throws {
    let fixture = TransportFixture(connectErrors: [.handshakeRejected(status)])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()

    #expect(await events.next() == .revoked)
    #expect(fixture.store.load() == nil)
    #expect(fixture.store.outgoingSequence == 0)
    #expect(fixture.store.hostSequence == 0)
    #expect(fixture.identity.deleteCount == 1)
    #expect(fixture.agreementIdentity.deleteCount == 1)
    await fixture.client.stop()
}

@Test(arguments: [401, 403])
func innerAuthorizationFailureErasesEveryDeviceSecret(_ status: Int) async throws {
    let socket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [socket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))

    let request = Task {
        try await fixture.client.request(RelayEndpoint<RelayInbox>.inbox())
    }
    let sent = try await socket.nextSentEnvelope()
    try await socket.push(
        hostResponse(sequence: 1, requestID: sent.messageID, status: status, body: #"{"error":"revoked"}"#)
    )
    await #expect(throws: RelayAPIError.revoked) {
        try await request.value
    }
    #expect(await events.next() == .revoked)
    #expect(fixture.store.load() == nil)
    #expect(fixture.identity.deleteCount == 1)
    #expect(fixture.agreementIdentity.deleteCount == 1)
    await fixture.client.stop()
}

@Test
func voiceUsesBoundedOrderedChunksAndSignsTheFullRequest() async throws {
    let socket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [socket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))
    let audio = Data(repeating: 0x5A, count: 2 * 1024 * 1024)

    let transcription = Task {
        try await fixture.client.transcribe(
            audio: audio,
            durationMs: 30_000,
            contentType: "audio/mp4",
            idempotencyKey: "voice-request-0001"
        )
    }
    var frames: [RelayTunnelEnvelope] = []
    for _ in 0..<16 {
        frames.append(try await socket.nextSentEnvelope())
    }
    let first = try #require(frames.first)
    let second = try #require(frames.last)
    let firstInner = try decodeInner(first, rootKey: testConfig.rootKey)
    let secondInner = try decodeInner(second, rootKey: testConfig.rootKey)
    let firstBody = try #require(firstInner["body"] as? [String: Any])
    let secondBody = try #require(secondInner["body"] as? [String: Any])
    let firstHeaders = try #require(firstBody["headers"] as? [String: String])
    let secondHeaders = try #require(secondBody["headers"] as? [String: String])

    #expect(firstInner["kind"] as? String == "voice")
    #expect(firstBody["index"] as? Int == 0)
    #expect(secondBody["index"] as? Int == 15)
    #expect(firstBody["totalChunks"] as? Int == 16)
    #expect(secondBody["totalChunks"] as? Int == 16)
    #expect(Data(base64Encoded: try #require(firstBody["data"] as? String))?.count == 128 * 1024)
    #expect(Data(base64Encoded: try #require(secondBody["data"] as? String))?.count == 128 * 1024)
    #expect(second.sequence == first.sequence + 15)
    #expect(firstHeaders == secondHeaders)
    #expect(firstHeaders["idempotency-key"] == "voice-request-0001")
    #expect(firstHeaders["content-type"] == "audio/mp4")
    #expect(fixture.identity.lastCanonical == relayCanonicalRequest(
        deviceID: testConfig.deviceId,
        method: "POST",
        path: "/v1/transcribe?durationMs=30000",
        body: audio,
        timestamp: 1_000,
        nonce: "nonce-1"
    ))

    try await socket.push(
        hostResponse(sequence: 1, requestID: second.messageID, body: #"{"transcript":"Ship it"}"#)
    )
    #expect(try await transcription.value == RelayTranscription(transcript: "Ship it"))
    await fixture.client.stop()
}

@Test
func voiceRejectsUnsafeLimitsBeforeSending() async throws {
    let socket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [socket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))

    await #expect(throws: RelayAPIError.voiceLimitExceeded) {
        try await fixture.client.transcribe(
            audio: Data(repeating: 1, count: 2 * 1024 * 1024 + 1),
            durationMs: 1_000,
            contentType: "audio/mp4",
            idempotencyKey: "voice-request-0001"
        )
    }
    await #expect(throws: RelayAPIError.voiceLimitExceeded) {
        try await fixture.client.transcribe(
            audio: Data([1]),
            durationMs: 30_001,
            contentType: "audio/mp4",
            idempotencyKey: "voice-request-0002"
        )
    }
    #expect(await socket.sentCount == 0)
    await fixture.client.stop()
}

@Test
func mutationRejectsMissingOrMalformedIdempotencyKeysBeforeSending() async throws {
    let socket = ControlledRelaySocket()
    let fixture = TransportFixture(sockets: [socket])
    let stream = await fixture.client.start()
    var events = stream.makeAsyncIterator()
    #expect(await events.next() == .connected(reconnected: false))
    let endpoint = try RelayEndpoint<RelayMutationAcknowledgement>.stop(
        taskID: "task-1",
        turnID: "turn-1"
    )

    await #expect(throws: RelayAPIError.idempotencyRequired) {
        try await fixture.client.request(endpoint)
    }
    await #expect(throws: RelayAPIError.idempotencyRequired) {
        try await fixture.client.request(
            endpoint,
            idempotencyKey: "contains spaces 123"
        )
    }
    #expect(await socket.sentCount == 0)
    await fixture.client.stop()
}

private final class FakeSigningIdentity: RelayWatchSigningIdentity, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDeleteCount = 0
    private var storedCanonical: Data?

    var deleteCount: Int { lock.withLock { storedDeleteCount } }
    var lastCanonical: Data? { lock.withLock { storedCanonical } }

    func publicKeyPEM() throws -> String { "test-signing-key" }
    func fingerprint() throws -> String { "test-fingerprint" }
    func sign(_ canonical: Data) throws -> String {
        lock.withLock { storedCanonical = canonical }
        return "test-signature"
    }
    func delete() { lock.withLock { storedDeleteCount += 1 } }
}

private final class FakeAgreementIdentity: RelayWatchAgreementIdentityProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDeleteCount = 0
    var deleteCount: Int { lock.withLock { storedDeleteCount } }

    func publicKeyBase64URL() throws -> String { "test-agreement-key" }
    func deriveRootKey(peerPublicKey: String, pairingSessionNonce: String) throws -> SymmetricKey {
        SymmetricKey(data: testConfig.rootKey)
    }
    func delete() { lock.withLock { storedDeleteCount += 1 } }
}

private final class MemoryCloudStore: RelayWatchCloudStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var config: RelayCloudDeviceConfig?
    private var outgoing: Int64 = 0
    private var incoming: Int64 = 0

    init(config: RelayCloudDeviceConfig?) { self.config = config }
    func load() -> RelayCloudDeviceConfig? { lock.withLock { config } }
    func save(_ config: RelayCloudDeviceConfig) throws {
        lock.withLock {
            self.config = config
            outgoing = 0
            incoming = 0
        }
    }
    var outgoingSequence: Int64 {
        get { lock.withLock { outgoing } }
        set { lock.withLock { outgoing = newValue } }
    }
    var hostSequence: Int64 {
        get { lock.withLock { incoming } }
        set { lock.withLock { incoming = newValue } }
    }
    func delete() {
        lock.withLock {
            config = nil
            outgoing = 0
            incoming = 0
        }
    }
}

private actor ControlledRelaySocket: RelaySocket {
    private var sent: [Data] = []
    private var sentWaiters: [CheckedContinuation<Data, Never>] = []
    private var incoming: [Result<Data, Error>] = []
    private var receiveWaiters: [CheckedContinuation<Data, Error>] = []
    private(set) var closed = false

    var sentCount: Int { sent.count }

    func send(_ data: Data) async throws {
        guard !closed else { throw RelaySocketError.network }
        if sentWaiters.isEmpty {
            sent.append(data)
        } else {
            sentWaiters.removeFirst().resume(returning: data)
        }
    }

    func receive() async throws -> Data {
        if !incoming.isEmpty { return try incoming.removeFirst().get() }
        return try await withCheckedThrowingContinuation { receiveWaiters.append($0) }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        let waiters = receiveWaiters
        receiveWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: RelaySocketError.closed) }
    }

    func nextSentEnvelope() async throws -> RelayTunnelEnvelope {
        let data: Data
        if !sent.isEmpty {
            data = sent.removeFirst()
        } else {
            data = await withCheckedContinuation { sentWaiters.append($0) }
        }
        return try JSONDecoder().decode(RelayTunnelEnvelope.self, from: data)
    }

    func push(_ envelope: RelayTunnelEnvelope) async throws {
        let data = try JSONEncoder().encode(envelope)
        if receiveWaiters.isEmpty {
            incoming.append(.success(data))
        } else {
            receiveWaiters.removeFirst().resume(returning: data)
        }
    }

    func fail(_ error: Error) {
        if receiveWaiters.isEmpty {
            incoming.append(.failure(error))
        } else {
            receiveWaiters.removeFirst().resume(throwing: error)
        }
    }
}

private actor ControlledSocketFactory: RelaySocketFactory {
    private var results: [Result<any RelaySocket, Error>]

    init(sockets: [ControlledRelaySocket] = [], errors: [RelaySocketError] = []) {
        results = sockets.map { .success($0 as any RelaySocket) }
            + errors.map { .failure($0) }
    }

    func connect(_ request: URLRequest) async throws -> any RelaySocket {
        guard !results.isEmpty else { throw RelaySocketError.network }
        return try results.removeFirst().get()
    }
}

private final class TransportFixture: @unchecked Sendable {
    let identity = FakeSigningIdentity()
    let agreementIdentity = FakeAgreementIdentity()
    let store = MemoryCloudStore(config: testConfig)
    let client: RelayAPIClient

    init(
        sockets: [ControlledRelaySocket] = [],
        connectErrors: [RelaySocketError] = []
    ) {
        let factory = ControlledSocketFactory(sockets: sockets, errors: connectErrors)
        let nonceCount = LockedCounter()
        let identifierCount = LockedCounter()
        client = RelayAPIClient(
            identity: identity,
            agreementIdentity: agreementIdentity,
            deviceStore: store,
            socketFactory: factory,
            environment: RelayEnvironment(
                name: .localDevelopment,
                httpOrigin: URL(string: "http://127.0.0.1:8787")!,
                webSocketOrigin: URL(string: "ws://127.0.0.1:8787")!
            ),
            now: { 1_000 },
            makeNonce: {
                "nonce-\(nonceCount.next())"
            },
            makeIdentifier: {
                "identifier-\(identifierCount.next())"
            },
            randomBytes: { Data(repeating: 0xA5, count: $0) },
            sleep: { _ in }
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private func hostResponse(
    sequence: Int64,
    requestID: String,
    status: Int = 200,
    body: String
) throws -> RelayTunnelEnvelope {
    try hostEnvelope(
        sequence: sequence,
        inner: [
            "kind": "response",
            "body": [
                "requestId": requestID,
                "status": status,
                "headers": ["content-type": "application/json"],
                "body": body,
            ],
        ]
    )
}

private func hostEnvelope(
    sequence: Int64,
    inner: [String: Any]
) throws -> RelayTunnelEnvelope {
    try relayEncrypt(
        JSONSerialization.data(withJSONObject: inner),
        routing: RelayTunnelRouting(
            messageID: "host-message-\(sequence)",
            accountID: testConfig.accountId,
            hostID: testConfig.hostId,
            senderID: testConfig.hostId,
            recipientID: testConfig.deviceId,
            sentAt: 1_000,
            sequence: sequence
        ),
        rootKey: SymmetricKey(data: testConfig.rootKey),
        nonce: Data(repeating: UInt8(sequence % 255), count: 12)
    )
}

private func decodeInner(
    _ envelope: RelayTunnelEnvelope,
    rootKey: Data
) throws -> [String: Any] {
    let plaintext = try relayDecrypt(envelope, rootKey: SymmetricKey(data: rootKey))
    return try #require(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
}

private func requestPath(_ inner: [String: Any]) -> String? {
    (inner["body"] as? [String: Any])?["path"] as? String
}

private func jsonObject<Value: Encodable>(_ value: Value) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}
