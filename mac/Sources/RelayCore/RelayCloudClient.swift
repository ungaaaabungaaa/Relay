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

    private func request(path: String, method: String, body: Data) -> URLRequest {
        var request = URLRequest(
            url: URL(string: path, relativeTo: apiOrigin)!.absoluteURL
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("no-store", forHTTPHeaderField: "cache-control")
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
