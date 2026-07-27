import CryptoKit
import Foundation

struct RelayCloudPreparedPairing: Sendable {
    let pending: RelayCloudPendingPairing
    let rootKey: SymmetricKey
}

enum RelayCloudPairingResult: Sendable {
    case pending
    case denied
    case approved(RelayCloudDeviceConfig)
}

struct RelayTunnelHTTPResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
}

enum RelayFailureCategory: Equatable, Sendable {
    case offline
    case network
    case invalidEnvelope
    case stopped
}

enum RelayTransportEvent: Sendable, Equatable {
    case connected(reconnected: Bool)
    case disconnected(RelayFailureCategory)
    case event(RelayEvent)
    case revoked
    case incompatible
}

actor RelayAPIClient {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct Lifecycle {
        let id: Int
        let task: Task<Void, Never>
    }

    private struct ActiveConnection {
        let id: Int
        let lifecycleID: Int
        let socket: any RelaySocket
        let config: RelayCloudDeviceConfig
    }

    private struct OutboundFrame {
        let plaintext: Data
        let requestID: String
        let timestamp: Int64
    }

    private struct OutboundBatch {
        let requestID: String
        let connection: ActiveConnection
        let frames: [OutboundFrame]
    }

    private struct Sender {
        let connectionID: Int
        let task: Task<Void, Never>
    }

    private let identity: any RelayWatchSigningIdentity
    private let agreementIdentity: any RelayWatchAgreementIdentityProtocol
    private var deviceStore: any RelayWatchCloudStoring
    private let session: URLSession
    private let socketFactory: any RelaySocketFactory
    private let environment: RelayEnvironment
    private let reconnectPolicy: RelayReconnectPolicy
    private let now: @Sendable () -> Int64
    private let makeNonce: @Sendable () -> String
    private let makeIdentifier: @Sendable () -> String
    private let randomBytes: @Sendable (Int) -> Data
    private let sleep: Sleep

    private var lifecycle: Lifecycle?
    private var lifecycleGeneration = 0
    private var connectionGeneration = 0
    private var activeConnection: ActiveConnection?
    private var sender: Sender?
    private var sendingRequestID: String?
    private var outboundQueue: [OutboundBatch] = []
    private var pending: [String: CheckedContinuation<RelayTunnelHTTPResponse, Error>] = [:]
    private var eventContinuation: AsyncStream<RelayTransportEvent>.Continuation?
    private var desiredRunning = false
    private var erasingSession = false
    private var connected = false
    private var hasConnected = false

    init(
        identity: any RelayWatchSigningIdentity,
        agreementIdentity: any RelayWatchAgreementIdentityProtocol,
        deviceStore: any RelayWatchCloudStoring,
        session: URLSession = .shared,
        socketFactory: (any RelaySocketFactory)? = nil,
        environment: RelayEnvironment = RelayEnvironment(
            name: .production,
            httpOrigin: RelayEnvironment.productionHTTPOrigin,
            webSocketOrigin: URL(string: "wss://api.relayforcodex.com")!
        ),
        reconnectPolicy: RelayReconnectPolicy = RelayReconnectPolicy(),
        now: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        makeNonce: @escaping @Sendable () -> String = { UUID().uuidString },
        makeIdentifier: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        },
        randomBytes: @escaping @Sendable (Int) -> Data = { count in
            Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
        },
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.identity = identity
        self.agreementIdentity = agreementIdentity
        self.deviceStore = deviceStore
        self.session = session
        self.socketFactory = socketFactory ?? URLSessionRelaySocketFactory(session: session)
        self.environment = environment
        self.reconnectPolicy = reconnectPolicy
        self.now = now
        self.makeNonce = makeNonce
        self.makeIdentifier = makeIdentifier
        self.randomBytes = randomBytes
        self.sleep = sleep
    }

    func submit(
        code: String,
        metadata: RelayDeviceMetadata
    ) async throws -> RelayCloudPreparedPairing {
        struct Submission: Encodable {
            let fingerprint: String
            let signingPublicKey: String
            let agreementPublicKey: String
            let metadata: RelayDeviceMetadata
        }
        guard code.range(of: #"^[A-Z0-9]{6}$"#, options: .regularExpression) != nil else {
            throw RelayAPIError.pairingUnavailable
        }
        let body = try JSONEncoder().encode(
            Submission(
                fingerprint: try identity.fingerprint(),
                signingPublicKey: try identity.publicKeyPEM(),
                agreementPublicKey: try agreementIdentity.publicKeyBase64URL(),
                metadata: metadata
            )
        )
        var request = URLRequest(
            url: environment.httpOrigin
                .appendingPathComponent("cloud/v1/pairing-sessions")
                .appendingPathComponent(code)
                .appendingPathComponent("requests")
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let pending = try await decode(RelayCloudPendingPairing.self, request: request)
        let rootKey = try agreementIdentity.deriveRootKey(
            peerPublicKey: pending.macAgreementPublicKey,
            pairingSessionNonce: pending.sessionNonce
        )
        return RelayCloudPreparedPairing(pending: pending, rootKey: rootKey)
    }

    func poll(_ prepared: RelayCloudPreparedPairing) async throws -> RelayCloudPairingResult {
        var request = URLRequest(
            url: environment.httpOrigin
                .appendingPathComponent("cloud/v1/pairing-requests")
                .appendingPathComponent(prepared.pending.id)
        )
        request.setValue(
            "Pairing \(prepared.pending.pollToken)",
            forHTTPHeaderField: "authorization"
        )
        let response = try await decode(RelayCloudPairingStatus.self, request: request)
        switch response.status {
        case "pending":
            return .pending
        case "denied":
            return .denied
        case "approved":
            guard let payload = response.payload else {
                throw RelayAPIError.pairingUnavailable
            }
            let credential = try relayOpenPairingPayload(
                payload,
                requestID: prepared.pending.id,
                hostID: prepared.pending.hostId,
                rootKey: prepared.rootKey
            )
            guard
                credential.accountId == prepared.pending.accountId,
                credential.hostId == prepared.pending.hostId,
                credential.apiVersion == 1,
                credential.minimumApiVersion <= 1,
                credential.maximumApiVersion >= 1
            else {
                throw RelayAPIError.incompatible
            }
            let config = RelayCloudDeviceConfig(
                accountId: credential.accountId,
                hostId: credential.hostId,
                deviceId: credential.deviceId,
                credential: credential.credential,
                rootKey: prepared.rootKey.withUnsafeBytes { Data($0) },
                apiVersion: credential.apiVersion
            )
            try deviceStore.save(config)
            return .approved(config)
        default:
            throw RelayAPIError.pairingUnavailable
        }
    }

    func start() -> AsyncStream<RelayTransportEvent> {
        eventContinuation?.finish()
        let (stream, continuation) = AsyncStream<RelayTransportEvent>.makeStream()
        eventContinuation = continuation
        guard !erasingSession else { return stream }
        desiredRunning = true
        launchLifecycleIfNeeded()
        return stream
    }

    func stop() async {
        desiredRunning = false
        let stoppingLifecycle = lifecycle
        let stoppingConnection = activeConnection
        stoppingLifecycle?.task.cancel()
        invalidateConnection(stoppingConnection)
        await stoppingConnection?.socket.close()
        failAllPending(with: RelayAPIError.offline)
        await stoppingLifecycle?.task.value
        if !desiredRunning {
            eventContinuation?.yield(.disconnected(.stopped))
            eventContinuation?.finish()
            eventContinuation = nil
        }
    }

    func close() async {
        await stop()
    }

    func request<Response: Decodable & Sendable>(
        _ endpoint: RelayEndpoint<Response>,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        if endpoint.isMutation {
            try validateIdempotencyKey(idempotencyKey)
        } else if let idempotencyKey {
            try validateIdempotencyKey(idempotencyKey)
        }
        let response = try await sendRequest(
            path: endpoint.path,
            method: endpoint.method,
            body: endpoint.body,
            idempotencyKey: idempotencyKey
        )
        guard (200..<300).contains(response.status) else {
            throw RelayAPIError.httpStatus(response.status)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: response.body)
        } catch {
            throw RelayAPIError.invalidResponse
        }
    }

    // Retained until Task 5 migrates the visible model to typed snapshots.
    func request(
        path: String,
        method: String = "GET",
        body: Data = Data(),
        idempotencyKey: String? = nil
    ) async throws -> RelayTunnelHTTPResponse {
        if method.uppercased() != "GET" && method.uppercased() != "HEAD" {
            try validateIdempotencyKey(idempotencyKey)
        }
        return try await sendRequest(
            path: path,
            method: method,
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func transcribe(
        audio: Data,
        durationMs: Int,
        contentType: String,
        idempotencyKey: String
    ) async throws -> RelayTranscription {
        guard
            !audio.isEmpty,
            audio.count <= relayVoiceMaximumBytes,
            (1...relayVoiceMaximumDurationMs).contains(durationMs),
            !contentType.isEmpty,
            contentType.count <= 128,
            !contentType.contains("\n"),
            !contentType.contains("\r")
        else {
            throw RelayAPIError.voiceLimitExceeded
        }
        try validateIdempotencyKey(idempotencyKey)
        guard let config = deviceStore.load(), connected, activeConnection != nil else {
            throw RelayAPIError.offline
        }

        let path = try RelayEndpoint<RelayTranscription>
            .transcription(durationMs: durationMs).path
        let timestamp = now()
        let requestNonce = makeNonce()
        var headers = try signedHeaders(
            config: config,
            method: "POST",
            path: path,
            body: audio,
            timestamp: timestamp,
            requestNonce: requestNonce,
            idempotencyKey: idempotencyKey
        )
        headers["content-type"] = contentType

        let chunkSize = relayVoiceChunkBytes
        let chunks = stride(from: 0, to: audio.count, by: chunkSize).map { offset in
            audio.subdata(in: offset..<min(offset + chunkSize, audio.count))
        }
        guard !chunks.isEmpty, chunks.count <= relayVoiceMaximumChunks else {
            throw RelayAPIError.voiceLimitExceeded
        }
        let transferID = makeIdentifier()
        var frames: [OutboundFrame] = []
        var finalRequestID = ""
        for (index, chunk) in chunks.enumerated() {
            let requestID = makeIdentifier()
            finalRequestID = requestID
            let recordedAtMs = chunks.count == 1
                ? durationMs
                : (index * durationMs) / (chunks.count - 1)
            let inner: [String: Any] = [
                "kind": "voice",
                "body": [
                    "transferId": transferID,
                    "index": index,
                    "totalChunks": chunks.count,
                    "recordedAtMs": recordedAtMs,
                    "durationMs": durationMs,
                    "method": "POST",
                    "path": path,
                    "headers": headers,
                    "data": chunk.base64EncodedString(),
                ],
            ]
            frames.append(
                OutboundFrame(
                    plaintext: try JSONSerialization.data(withJSONObject: inner),
                    requestID: requestID,
                    timestamp: timestamp
                )
            )
        }
        let response = try await awaitResponse(
            requestID: finalRequestID,
            frames: frames
        )
        guard (200..<300).contains(response.status) else {
            throw RelayAPIError.httpStatus(response.status)
        }
        do {
            return try JSONDecoder().decode(RelayTranscription.self, from: response.body)
        } catch {
            throw RelayAPIError.invalidResponse
        }
    }

    func eraseSession() async {
        erasingSession = true
        desiredRunning = false
        let stoppingLifecycle = lifecycle
        let stoppingConnection = activeConnection
        stoppingLifecycle?.task.cancel()
        invalidateConnection(stoppingConnection)
        await stoppingConnection?.socket.close()
        failAllPending(with: RelayAPIError.revoked)
        await stoppingLifecycle?.task.value
        eraseDeviceMaterial()
        erasingSession = false
    }

    private func eraseDeviceMaterial() {
        deviceStore.delete()
        agreementIdentity.delete()
        identity.delete()
        hasConnected = false
    }

    private func launchLifecycleIfNeeded() {
        guard desiredRunning, lifecycle == nil else { return }
        lifecycleGeneration += 1
        let lifecycleID = lifecycleGeneration
        let task = Task { await self.runConnectionLoop(lifecycleID: lifecycleID) }
        lifecycle = Lifecycle(id: lifecycleID, task: task)
    }

    private func runConnectionLoop(lifecycleID: Int) async {
        defer { lifecycleFinished(lifecycleID) }
        var reconnectAttempt = 0
        while ownsLifecycle(lifecycleID) && desiredRunning && !Task.isCancelled {
            guard let config = deviceStore.load() else {
                desiredRunning = false
                break
            }
            do {
                let activeSocket = try await socketFactory.connect(
                    socketRequest(config: config)
                )
                guard
                    ownsLifecycle(lifecycleID),
                    desiredRunning,
                    !Task.isCancelled
                else {
                    await activeSocket.close()
                    break
                }
                connectionGeneration += 1
                let connection = ActiveConnection(
                    id: connectionGeneration,
                    lifecycleID: lifecycleID,
                    socket: activeSocket,
                    config: config
                )
                activeConnection = connection
                connected = true
                let reconnected = hasConnected
                hasConnected = true
                reconnectAttempt = 0
                eventContinuation?.yield(.connected(reconnected: reconnected))
                try await receiveMessages(connection)
                throw RelaySocketError.closed
            } catch {
                let authFailure = isAuthorizationFailure(error)
                let incompatible = error as? RelayAPIError == .incompatible
                let failedConnection = activeConnection.flatMap {
                    $0.lifecycleID == lifecycleID ? $0 : nil
                }
                invalidateConnection(failedConnection)
                await failedConnection?.socket.close()

                if authFailure {
                    desiredRunning = false
                    failAllPending(with: RelayAPIError.revoked)
                    eraseDeviceMaterial()
                    eventContinuation?.yield(.revoked)
                    eventContinuation?.finish()
                    eventContinuation = nil
                    break
                }
                if incompatible {
                    failAllPending(with: RelayAPIError.incompatible)
                    eventContinuation?.yield(.incompatible)
                    desiredRunning = false
                    break
                }
                guard
                    ownsLifecycle(lifecycleID),
                    desiredRunning,
                    !Task.isCancelled
                else { break }
                let mapped = requestFailure(for: error)
                failAllPending(with: mapped)
                eventContinuation?.yield(.disconnected(failureCategory(for: error)))
                do {
                    try await sleep(reconnectPolicy.delay(forAttempt: reconnectAttempt))
                } catch {
                    return
                }
                reconnectAttempt += 1
            }
        }
    }

    private func receiveMessages(_ connection: ActiveConnection) async throws {
        while
            ownsConnection(connection.id),
            desiredRunning,
            !Task.isCancelled
        {
            let data = try await connection.socket.receive()
            guard ownsConnection(connection.id) else { throw RelaySocketError.closed }
            try processIncoming(data, config: connection.config)
        }
    }

    private func ownsLifecycle(_ id: Int) -> Bool {
        lifecycle?.id == id
    }

    private func ownsConnection(_ id: Int) -> Bool {
        activeConnection?.id == id
    }

    private func lifecycleFinished(_ id: Int) {
        guard lifecycle?.id == id else { return }
        lifecycle = nil
        launchLifecycleIfNeeded()
    }

    private func invalidateConnection(_ connection: ActiveConnection?) {
        guard let connection else { return }
        if activeConnection?.id == connection.id {
            activeConnection = nil
            connected = false
        }
        outboundQueue.removeAll { $0.connection.id == connection.id }
        if sender?.connectionID == connection.id {
            sender?.task.cancel()
            sender = nil
            sendingRequestID = nil
        }
    }

    private func processIncoming(
        _ data: Data,
        config: RelayCloudDeviceConfig
    ) throws {
        if let control = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           control["type"] as? String == "host_offline" {
            throw RelayAPIError.offline
        }
        let envelope: RelayTunnelEnvelope
        do {
            envelope = try JSONDecoder().decode(RelayTunnelEnvelope.self, from: data)
        } catch {
            throw RelayAPIError.invalidEnvelope
        }
        guard
            envelope.accountID == config.accountId,
            envelope.hostID == config.hostId,
            envelope.senderID == config.hostId,
            envelope.recipientID == config.deviceId,
            abs(now() - envelope.sentAt) <= 5 * 60_000
        else {
            throw RelayAPIError.invalidEnvelope
        }
        do {
            var replay = RelayCloudReplayWindow(
                highestSequences: [config.hostId: deviceStore.hostSequence]
            )
            try replay.accept(senderID: config.hostId, sequence: envelope.sequence)
            let plaintext = try relayDecrypt(
                envelope,
                rootKey: SymmetricKey(data: config.rootKey)
            )
            deviceStore.hostSequence = envelope.sequence
            try routeInner(plaintext)
        } catch let error as RelayAPIError {
            throw error
        } catch {
            throw RelayAPIError.invalidEnvelope
        }
    }

    private func routeInner(_ plaintext: Data) throws {
        guard
            let inner = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
            let kind = inner["kind"] as? String,
            let body = inner["body"]
        else {
            throw RelayAPIError.invalidEnvelope
        }
        switch kind {
        case "response":
            guard
                let response = body as? [String: Any],
                let requestID = response["requestId"] as? String,
                let status = response["status"] as? Int,
                let responseBody = response["body"] as? String
            else {
                throw RelayAPIError.invalidEnvelope
            }
            if status == 401 || status == 403 {
                completePending(requestID, with: .failure(RelayAPIError.revoked))
                throw RelayAPIError.revoked
            }
            completePending(
                requestID,
                with: .success(
                    RelayTunnelHTTPResponse(
                        status: status,
                        headers: response["headers"] as? [String: String] ?? [:],
                        body: Data(responseBody.utf8)
                    )
                )
            )
        case "event":
            do {
                let eventData = try JSONSerialization.data(withJSONObject: body)
                let event = try JSONDecoder().decode(RelayEvent.self, from: eventData)
                eventContinuation?.yield(.event(event))
            } catch {
                throw RelayAPIError.invalidEnvelope
            }
        case "control":
            guard let control = body as? [String: Any] else {
                throw RelayAPIError.invalidEnvelope
            }
            if let status = control["status"] as? Int, status == 401 || status == 403 {
                throw RelayAPIError.revoked
            }
            switch control["type"] as? String {
            case "revoked": throw RelayAPIError.revoked
            case "incompatible": throw RelayAPIError.incompatible
            case "host_offline": throw RelayAPIError.offline
            default: throw RelayAPIError.invalidEnvelope
            }
        default:
            throw RelayAPIError.invalidEnvelope
        }
    }

    private func sendRequest(
        path: String,
        method: String,
        body: Data,
        idempotencyKey: String?
    ) async throws -> RelayTunnelHTTPResponse {
        guard path.hasPrefix("/v1/"), !path.hasPrefix("//") else {
            throw RelayAPIError.invalidResponse
        }
        guard let config = deviceStore.load(), connected, activeConnection != nil else {
            throw RelayAPIError.offline
        }
        let timestamp = now()
        let requestNonce = makeNonce()
        let headers = try signedHeaders(
            config: config,
            method: method,
            path: path,
            body: body,
            timestamp: timestamp,
            requestNonce: requestNonce,
            idempotencyKey: idempotencyKey
        )
        let requestID = makeIdentifier()
        let inner: [String: Any] = [
            "kind": "request",
            "body": [
                "method": method.uppercased(),
                "path": path,
                "headers": headers,
                "body": String(decoding: body, as: UTF8.self),
            ],
        ]
        let frame = OutboundFrame(
            plaintext: try JSONSerialization.data(withJSONObject: inner),
            requestID: requestID,
            timestamp: timestamp
        )
        return try await awaitResponse(requestID: requestID, frames: [frame])
    }

    private func signedHeaders(
        config: RelayCloudDeviceConfig,
        method: String,
        path: String,
        body: Data,
        timestamp: Int64,
        requestNonce: String,
        idempotencyKey: String?
    ) throws -> [String: String] {
        let canonical = relayCanonicalRequest(
            deviceID: config.deviceId,
            method: method,
            path: path,
            body: body,
            timestamp: timestamp,
            nonce: requestNonce
        )
        var headers = [
            "x-relay-device": config.deviceId,
            "x-relay-timestamp": String(timestamp),
            "x-relay-nonce": requestNonce,
            "x-relay-signature": try identity.sign(canonical),
            "content-type": "application/json; charset=utf-8",
        ]
        if let idempotencyKey {
            headers["idempotency-key"] = idempotencyKey
        }
        return headers
    }

    private func encryptedFrame(
        _ frame: OutboundFrame,
        config: RelayCloudDeviceConfig
    ) throws -> Data {
        let nextSequence = deviceStore.outgoingSequence + 1
        let envelope = try relayEncrypt(
            frame.plaintext,
            routing: RelayTunnelRouting(
                messageID: frame.requestID,
                accountID: config.accountId,
                hostID: config.hostId,
                senderID: config.deviceId,
                recipientID: config.hostId,
                sentAt: frame.timestamp,
                sequence: nextSequence
            ),
            rootKey: SymmetricKey(data: config.rootKey),
            nonce: randomBytes(12)
        )
        deviceStore.outgoingSequence = nextSequence
        return try JSONEncoder().encode(envelope)
    }

    private func awaitResponse(
        requestID: String,
        frames: [OutboundFrame]
    ) async throws -> RelayTunnelHTTPResponse {
        guard let connection = activeConnection, connected else {
            throw RelayAPIError.offline
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[requestID] = continuation
                outboundQueue.append(
                    OutboundBatch(
                        requestID: requestID,
                        connection: connection,
                        frames: frames
                    )
                )
                launchSenderIfNeeded(for: connection)
            }
        } onCancel: {
            Task { await self.cancelPending(requestID) }
        }
    }

    private func cancelPending(_ requestID: String) async {
        outboundQueue.removeAll { $0.requestID == requestID }
        completePending(requestID, with: .failure(CancellationError()))
        if sendingRequestID == requestID, let connection = activeConnection {
            invalidateConnection(connection)
            await connection.socket.close()
        }
    }

    private func launchSenderIfNeeded(for connection: ActiveConnection) {
        guard sender == nil, ownsConnection(connection.id) else { return }
        let task = Task { await self.runSender(connectionID: connection.id) }
        sender = Sender(connectionID: connection.id, task: task)
    }

    private func runSender(connectionID: Int) async {
        while
            ownsConnection(connectionID),
            !Task.isCancelled,
            let batch = nextBatch(for: connectionID)
        {
            sendingRequestID = batch.requestID
            do {
                for frame in batch.frames {
                    guard
                        ownsConnection(connectionID),
                        pending[batch.requestID] != nil,
                        !Task.isCancelled
                    else { break }
                    let data = try encryptedFrame(frame, config: batch.connection.config)
                    try await batch.connection.socket.send(data)
                }
            } catch {
                completePending(
                    batch.requestID,
                    with: .failure(requestFailure(for: error))
                )
                invalidateConnection(batch.connection)
                await batch.connection.socket.close()
            }
            if sendingRequestID == batch.requestID {
                sendingRequestID = nil
            }
        }
        senderFinished(connectionID)
    }

    private func nextBatch(for connectionID: Int) -> OutboundBatch? {
        while !outboundQueue.isEmpty {
            let batch = outboundQueue.removeFirst()
            guard
                batch.connection.id == connectionID,
                pending[batch.requestID] != nil
            else { continue }
            return batch
        }
        return nil
    }

    private func senderFinished(_ connectionID: Int) {
        guard sender?.connectionID == connectionID else { return }
        sender = nil
        sendingRequestID = nil
        if let connection = activeConnection, !outboundQueue.isEmpty {
            launchSenderIfNeeded(for: connection)
        }
    }

    private func completePending(
        _ requestID: String,
        with result: Result<RelayTunnelHTTPResponse, Error>
    ) {
        guard let continuation = pending.removeValue(forKey: requestID) else { return }
        continuation.resume(with: result)
    }

    private func failAllPending(with error: Error) {
        outboundQueue.removeAll()
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func validateIdempotencyKey(_ key: String?) throws {
        guard
            let key,
            key.range(
                of: #"^[A-Za-z0-9._:-]{16,128}$"#,
                options: .regularExpression
            ) != nil
        else {
            throw RelayAPIError.idempotencyRequired
        }
    }

    private func socketRequest(config: RelayCloudDeviceConfig) -> URLRequest {
        var request = URLRequest(
            url: environment.webSocketOrigin
                .appendingPathComponent("cloud/v1/connect/device")
        )
        request.setValue("Bearer \(config.credential)", forHTTPHeaderField: "authorization")
        request.setValue(config.deviceId, forHTTPHeaderField: "x-relay-device-id")
        request.setValue("no-store", forHTTPHeaderField: "cache-control")
        return request
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        request: URLRequest
    ) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RelayAPIError.pairingUnavailable
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            await eraseSession()
            throw RelayAPIError.revoked
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RelayAPIError.pairingUnavailable
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func isAuthorizationFailure(_ error: Error) -> Bool {
        if error as? RelayAPIError == .revoked { return true }
        if case let RelaySocketError.handshakeRejected(status) = error {
            return status == 401 || status == 403
        }
        return false
    }

    private func requestFailure(for error: Error) -> RelayAPIError {
        if let relayError = error as? RelayAPIError {
            return relayError == .invalidEnvelope ? .invalidEnvelope : .offline
        }
        if error is RelayCloudCryptoError { return .invalidEnvelope }
        return .offline
    }

    private func failureCategory(for error: Error) -> RelayFailureCategory {
        if error as? RelayAPIError == .invalidEnvelope || error is RelayCloudCryptoError {
            return .invalidEnvelope
        }
        if error as? RelayAPIError == .offline { return .offline }
        return .network
    }
}

enum RelayAPIError: Error, Equatable, Sendable {
    case pairingUnavailable
    case incompatible
    case invalidEnvelope
    case invalidResponse
    case offline
    case revoked
    case httpStatus(Int)
    case idempotencyRequired
    case voiceLimitExceeded
}
