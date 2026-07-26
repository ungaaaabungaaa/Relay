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

actor RelayAPIClient {
    private let identity: RelayWatchIdentity
    private let agreementIdentity: RelayWatchAgreementIdentity
    private let deviceStore: RelayWatchCloudStore
    private let session: URLSession
    private let apiOrigin: URL
    private var socket: URLSessionWebSocketTask?

    init(
        identity: RelayWatchIdentity,
        agreementIdentity: RelayWatchAgreementIdentity,
        deviceStore: RelayWatchCloudStore,
        session: URLSession = .shared,
        apiOrigin: URL = relayCloudAPIOrigin
    ) {
        self.identity = identity
        self.agreementIdentity = agreementIdentity
        self.deviceStore = deviceStore
        self.session = session
        self.apiOrigin = apiOrigin
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
            url: apiOrigin
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
            url: apiOrigin
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

    func request(
        path: String,
        method: String = "GET",
        body: Data = Data(),
        idempotencyKey: String? = nil
    ) async throws -> RelayTunnelHTTPResponse {
        guard path.hasPrefix("/v1/"), let config = deviceStore.load() else {
            throw RelayAPIError.pairingUnavailable
        }
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let requestNonce = UUID().uuidString
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
        let requestID = UUID().uuidString.lowercased()
        let inner: [String: Any] = [
            "kind": "request",
            "body": [
                "method": method.uppercased(),
                "path": path,
                "headers": headers,
                "body": String(decoding: body, as: UTF8.self),
            ],
        ]
        let plaintext = try JSONSerialization.data(withJSONObject: inner)
        let nextSequence = deviceStore.outgoingSequence + 1
        let envelope = try relayEncrypt(
            plaintext,
            routing: RelayTunnelRouting(
                messageID: requestID,
                accountID: config.accountId,
                hostID: config.hostId,
                senderID: config.deviceId,
                recipientID: config.hostId,
                sentAt: timestamp,
                sequence: nextSequence
            ),
            rootKey: SymmetricKey(data: config.rootKey),
            nonce: randomData(count: 12)
        )
        deviceStore.outgoingSequence = nextSequence
        do {
            let activeSocket = socketFor(config)
            try await activeSocket.send(
                .string(
                    String(
                        decoding: try JSONEncoder().encode(envelope),
                        as: UTF8.self
                    )
                )
            )
            return try await receiveResponse(
                requestID: requestID,
                config: config,
                socket: activeSocket
            )
        } catch {
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            if let closeCode = (error as? URLError)?.code,
               closeCode == .userAuthenticationRequired {
                throw RelayAPIError.revoked
            }
            throw error
        }
    }

    func close() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func socketFor(_ config: RelayCloudDeviceConfig) -> URLSessionWebSocketTask {
        if let socket { return socket }
        var components = URLComponents(
            url: apiOrigin.appendingPathComponent("cloud/v1/connect/device"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = "wss"
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(config.credential)", forHTTPHeaderField: "authorization")
        request.setValue(config.deviceId, forHTTPHeaderField: "x-relay-device-id")
        request.setValue("no-store", forHTTPHeaderField: "cache-control")
        let created = session.webSocketTask(with: request)
        socket = created
        created.resume()
        return created
    }

    private func receiveResponse(
        requestID: String,
        config: RelayCloudDeviceConfig,
        socket: URLSessionWebSocketTask
    ) async throws -> RelayTunnelHTTPResponse {
        while true {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case let .data(value): data = value
            case let .string(value): data = Data(value.utf8)
            @unknown default: throw RelayAPIError.invalidEnvelope
            }
            if let control = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               control["type"] as? String == "host_offline" {
                throw RelayAPIError.offline
            }
            let envelope = try JSONDecoder().decode(RelayTunnelEnvelope.self, from: data)
            guard
                envelope.accountID == config.accountId,
                envelope.hostID == config.hostId,
                envelope.senderID == config.hostId,
                envelope.recipientID == config.deviceId,
                abs(Int64(Date().timeIntervalSince1970 * 1_000) - envelope.sentAt)
                    <= 5 * 60_000
            else {
                throw RelayAPIError.invalidEnvelope
            }
            let plaintext = try relayDecrypt(
                envelope,
                rootKey: SymmetricKey(data: config.rootKey)
            )
            var replay = RelayCloudReplayWindow(
                highestSequences: [config.hostId: deviceStore.hostSequence]
            )
            try replay.accept(senderID: config.hostId, sequence: envelope.sequence)
            deviceStore.hostSequence = envelope.sequence
            guard
                let inner = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
                inner["kind"] as? String == "response",
                let response = inner["body"] as? [String: Any],
                response["requestId"] as? String == requestID,
                let status = response["status"] as? Int,
                let body = response["body"] as? String
            else {
                // Valid live events may arrive before the requested response.
                continue
            }
            return RelayTunnelHTTPResponse(
                status: status,
                headers: response["headers"] as? [String: String] ?? [:],
                body: Data(body.utf8)
            )
        }
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
            throw RelayAPIError.revoked
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RelayAPIError.pairingUnavailable
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }
}

enum RelayAPIError: Error {
    case pairingUnavailable
    case incompatible
    case invalidEnvelope
    case offline
    case revoked
}
