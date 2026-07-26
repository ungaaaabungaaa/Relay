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
    public var expiresAt: Int64
    public var sessionNonce: String
    public var macFingerprint: String
}

public struct RelayCloudApprovedDevice: Codable, Equatable, Sendable {
    public var id: String
    public var hostId: String
    public var credential: String
    public var sessionNonce: String
}

public enum RelayCloudClientError: Error, Equatable, Sendable {
    case invalidResponse
    case authenticationFailed
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

    public func approvePairing(
        accessToken: String,
        pairingToken: String,
        requestID: String
    ) async throws -> RelayCloudApprovedDevice {
        let body = try JSONSerialization.data(withJSONObject: [
            "requestId": requestID,
        ])
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
        body: Data,
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

    private func request(
        path: String,
        method: String,
        body: Data,
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
