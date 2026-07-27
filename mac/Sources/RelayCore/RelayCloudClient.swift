import CryptoKit
import Foundation
import Security

public struct RelayCloudLoginSession: Equatable, Sendable {
    public var id: String
    public var verificationURL: URL
    public var expiresAt: Int64
    public var pkceVerifier: String
}

public struct RelayCloudTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var accessExpiresAt: Int64
    public var refreshToken: String
    public var refreshExpiresAt: Int64
}

public struct RelayCloudHost: Codable, Equatable, Sendable {
    public var id: String
    public var credential: String
}

public struct RelayCloudPairingSession: Codable, Equatable, Sendable {
    public var token: String
    public var code: String
    public var accountId: String
    public var expiresAt: Int64
    public var sessionNonce: String
    public var macFingerprint: String
}

public struct RelayCloudApprovedDevice: Codable, Equatable, Sendable {
    public var id: String
    public var hostId: String
    public var sessionNonce: String
}

public struct RelayCloudEmergencyStop: Codable, Equatable, Sendable {
    public var hostId: String
    public var hostCredential: String
    public var revokedDeviceCount: Int
}

public enum RelayCloudClientError: Error, Equatable, Sendable {
    case invalidResponse
    case authenticationFailed
}

private struct RelayCloudPairingApprovalRequest: Encodable, Sendable {
    var requestId: String
    var deviceId: String
    var credentialHash: String
    var approvedPayload: RelayCloudPairingPayloadEnvelope
}

private struct RelayCloudRecoveredPairingRequests: Decodable, Sendable {
    struct Request: Decodable, Sendable {
        var requestId: String
        var signingPublicKey: String
        var agreementPublicKey: String
        var metadata: RelayCloudDeviceMetadata
        var expiresAt: Int64
    }
    var requests: [Request]
}

public struct RelayCloudClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let apiOrigin: URL
    private let transport: Transport

    public init(
        apiOrigin: URL = URL(string: "https://api.relayforcodex.com")!,
        transport: @escaping Transport = RelayCloudClient.liveTransport
    ) {
        self.apiOrigin = apiOrigin
        self.transport = transport
    }

    public init(
        endpoints: RelayCloudEndpoints,
        transport: @escaping Transport = RelayCloudClient.liveTransport
    ) {
        self.init(apiOrigin: endpoints.apiOrigin, transport: transport)
    }

    public func startDeviceLogin(email: String) async throws -> RelayCloudLoginSession {
        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "pkceChallenge": challenge,
            "pkceMethod": "S256",
        ])
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/auth/device-sessions",
                method: "POST",
                body: body
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        struct Response: Decodable {
            var id: String
            var verificationURL: URL
            var expiresAt: Int64
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return RelayCloudLoginSession(
            id: decoded.id,
            verificationURL: decoded.verificationURL,
            expiresAt: decoded.expiresAt,
            pkceVerifier: verifier
        )
    }

    public func pollForToken(
        sessionID: String,
        pkceVerifier: String
    ) async throws -> RelayCloudTokens? {
        let body = try JSONSerialization.data(withJSONObject: [
            "pkceVerifier": pkceVerifier,
        ])
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/auth/device-sessions/\(sessionID)/token",
                method: "POST",
                body: body
            )
        )
        if response.statusCode == 202 {
            return nil
        }
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(RelayCloudTokens.self, from: data)
    }

    public func refresh(refreshToken: String) async throws -> RelayCloudTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "refreshToken": refreshToken,
        ])
        let (data, response) = try await transport(
            request(path: "/cloud/v1/auth/refresh", method: "POST", body: body)
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(RelayCloudTokens.self, from: data)
    }

    public func logout(refreshToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "refreshToken": refreshToken,
        ])
        let (_, response) = try await transport(
            request(path: "/cloud/v1/auth/logout", method: "POST", body: body)
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
    }

    public func registerHost(
        accessToken: String,
        name: String,
        signingPublicKey: String,
        agreementPublicKey: String
    ) async throws -> RelayCloudHost {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "signingPublicKey": signingPublicKey,
            "agreementPublicKey": agreementPublicKey,
        ])
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/hosts",
                method: "POST",
                body: body,
                accessToken: accessToken
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(RelayCloudHost.self, from: data)
    }

    public func createPairingSession(
        accessToken: String,
        hostID: String,
        macFingerprint: String
    ) async throws -> RelayCloudPairingSession {
        let body = try JSONSerialization.data(withJSONObject: [
            "macFingerprint": macFingerprint,
        ])
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/hosts/\(hostID)/pairing-sessions",
                method: "POST",
                body: body,
                accessToken: accessToken
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(
            RelayCloudPairingSession.self,
            from: data
        )
    }

    public func pendingPairingRequests(
        accessToken: String,
        pairingToken: String
    ) async throws -> [RelayCloudPairingRequest] {
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/pairing-sessions/\(pairingToken)/requests",
                method: "GET",
                accessToken: accessToken
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(
            RelayCloudRecoveredPairingRequests.self,
            from: data
        ).requests.map { recovered in
            guard Self.validAgreementKey(recovered.agreementPublicKey) else {
                throw RelayCloudClientError.invalidResponse
            }
            return RelayCloudPairingRequest(
                id: recovered.requestId,
                fingerprint: try Self.watchFingerprint(
                    signingPublicKey: recovered.signingPublicKey
                ),
                signingPublicKey: recovered.signingPublicKey,
                agreementPublicKey: recovered.agreementPublicKey,
                expiresAt: recovered.expiresAt,
                metadata: recovered.metadata
            )
        }
    }

    public func approvePairing(
        accessToken: String,
        pairingToken: String,
        requestID: String,
        deviceID: String,
        credentialHash: String,
        approvedPayload: RelayCloudPairingPayloadEnvelope
    ) async throws -> RelayCloudApprovedDevice {
        let body = try JSONEncoder().encode(
            RelayCloudPairingApprovalRequest(
                requestId: requestID,
                deviceId: deviceID,
                credentialHash: credentialHash,
                approvedPayload: approvedPayload
            )
        )
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/pairing-sessions/\(pairingToken)/approve",
                method: "POST",
                body: body,
                accessToken: accessToken
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(
            RelayCloudApprovedDevice.self,
            from: data
        )
    }

    public func denyPairing(
        accessToken: String,
        pairingToken: String,
        requestID: String
    ) async throws {
        try await okRequest(
            path: "/cloud/v1/pairing-sessions/\(pairingToken)/deny",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: [
                "requestId": requestID,
            ]),
            accessToken: accessToken
        )
    }

    public func revokeDevice(
        accessToken: String,
        deviceID: String
    ) async throws {
        try await okRequest(
            path: "/cloud/v1/devices/\(deviceID)/revoke",
            method: "POST",
            body: Data("{}".utf8),
            accessToken: accessToken
        )
    }

    public func emergencyStop(
        accessToken: String
    ) async throws -> RelayCloudEmergencyStop {
        let (data, response) = try await transport(
            request(
                path: "/cloud/v1/emergency-stop",
                method: "POST",
                body: Data("{}".utf8),
                accessToken: accessToken
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
        return try JSONDecoder().decode(
            RelayCloudEmergencyStop.self,
            from: data
        )
    }

    public func deleteAccount(accessToken: String) async throws {
        try await okRequest(
            path: "/cloud/v1/account",
            method: "DELETE",
            body: Data("{}".utf8),
            accessToken: accessToken
        )
    }

    private func okRequest(
        path: String,
        method: String,
        body: Data = Data(),
        accessToken: String
    ) async throws {
        let (_, response) = try await transport(
            request(
                path: path,
                method: method,
                body: body,
                accessToken: accessToken
            )
        )
        guard response.statusCode == 200 else {
            throw RelayCloudClientError.authenticationFailed
        }
    }

    private static func watchFingerprint(signingPublicKey: String) throws -> String {
        let lines = signingPublicKey.split(separator: "\n").map(String.init)
        guard
            lines.first == "-----BEGIN PUBLIC KEY-----",
            lines.last == "-----END PUBLIC KEY-----",
            let decoded = Data(base64Encoded: lines.dropFirst().dropLast().joined()),
            !decoded.isEmpty
        else { throw RelayCloudClientError.invalidResponse }
        let digest = SHA256.hash(data: Data(signingPublicKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return stride(from: 0, to: 32, by: 4).map { offset in
            let start = digest.index(digest.startIndex, offsetBy: offset)
            let end = digest.index(start, offsetBy: 4)
            return String(digest[start..<end])
        }.joined(separator: ":")
    }

    private static func validAgreementKey(_ value: String) -> Bool {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return false }
        return (try? P256.KeyAgreement.PublicKey(x963Representation: data)) != nil
    }

    private func request(
        path: String,
        method: String,
        body: Data = Data(),
        accessToken: String? = nil
    ) -> URLRequest {
        var request = URLRequest(
            url: URL(string: path, relativeTo: apiOrigin)!.absoluteURL
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("no-store", forHTTPHeaderField: "cache-control")
        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "authorization"
            )
        }
        return request
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func liveTransport(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RelayCloudClientError.invalidResponse
        }
        return (data, response)
    }
}
