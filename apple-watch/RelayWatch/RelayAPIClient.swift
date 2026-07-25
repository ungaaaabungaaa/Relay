import Foundation

actor RelayAPIClient {
    private let identity: RelayWatchIdentity
    private let session: URLSession

    init(
        identity: RelayWatchIdentity,
        session: URLSession = .shared
    ) {
        self.identity = identity
        self.session = session
    }

    func discover(_ record: RelayPairingRecord) async throws -> RelayMacIdentity {
        try await decode(
            RelayMacIdentity.self,
            request: URLRequest(url: pairingURL(record))
        )
    }

    func submit(
        _ record: RelayPairingRecord,
        code: String,
        metadata: RelayDeviceMetadata
    ) async throws -> RelayPendingPairing {
        struct Submission: Encodable {
            let code: String
            let name: String
            let publicKey: String
            let metadata: RelayDeviceMetadata
        }
        let submission = Submission(
            code: code.uppercased(),
            name: "Apple Watch",
            publicKey: try identity.publicKeyPEM(),
            metadata: metadata
        )
        var request = URLRequest(url: pairingURL(record))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(submission)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await decode(RelayPendingPairing.self, request: request)
    }

    func poll(
        _ record: RelayPairingRecord,
        token: String
    ) async throws -> RelayPairingStatus {
        var components = URLComponents(
            url: pairingURL(record).appendingPathComponent("status"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "pollToken", value: token)]
        return try await decode(
            RelayPairingStatus.self,
            request: URLRequest(url: components.url!)
        )
    }

    func request(
        origin: URL,
        deviceID: String,
        path: String,
        method: String = "GET",
        body: Data = Data(),
        idempotencyKey: String? = nil
    ) async throws -> Data {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let nonce = UUID().uuidString
        let canonical = relayCanonicalRequest(
            deviceID: deviceID,
            method: method,
            path: path,
            body: body,
            timestamp: timestamp,
            nonce: nonce
        )
        var request = URLRequest(
            url: origin.appendingPathComponent(path.trimmingPrefix("/"))
        )
        request.httpMethod = method
        request.httpBody = body.isEmpty ? nil : body
        request.setValue(deviceID, forHTTPHeaderField: "x-relay-device")
        request.setValue(String(timestamp), forHTTPHeaderField: "x-relay-timestamp")
        request.setValue(nonce, forHTTPHeaderField: "x-relay-nonce")
        request.setValue(try identity.sign(canonical), forHTTPHeaderField: "x-relay-signature")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "idempotency-key")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw RelayAPIError.revoked
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RelayAPIError.rejected(http.statusCode)
        }
        return data
    }

    func webSocket(
        origin: URL,
        deviceID: String,
        lastEventID: Int64
    ) throws -> URLSessionWebSocketTask {
        let path = "/v1/events?after=\(lastEventID)"
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let nonce = UUID().uuidString
        let canonical = relayCanonicalRequest(
            deviceID: deviceID,
            method: "GET",
            path: path,
            body: Data(),
            timestamp: timestamp,
            nonce: nonce
        )
        var components = URLComponents(
            url: origin.appendingPathComponent("v1/events"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = "wss"
        components.queryItems = [
            URLQueryItem(name: "after", value: String(lastEventID)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(deviceID, forHTTPHeaderField: "x-relay-device")
        request.setValue(String(timestamp), forHTTPHeaderField: "x-relay-timestamp")
        request.setValue(nonce, forHTTPHeaderField: "x-relay-nonce")
        request.setValue(try identity.sign(canonical), forHTTPHeaderField: "x-relay-signature")
        return session.webSocketTask(with: request)
    }

    private func pairingURL(_ record: RelayPairingRecord) -> URL {
        record.origin
            .appendingPathComponent("v1")
            .appendingPathComponent("pairing-sessions")
            .appendingPathComponent(record.discoveryToken)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        request: URLRequest
    ) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw RelayAPIError.pairingUnavailable
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum RelayAPIError: Error {
    case pairingUnavailable
    case revoked
    case rejected(Int)
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
