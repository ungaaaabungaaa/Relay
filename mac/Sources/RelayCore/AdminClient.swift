import Foundation

public enum AdminClientError: Error, Equatable, Sendable {
    case missingToken
    case unauthorized
    case rejected(Int)
    case invalidResponse
}

public protocol AdminTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAdminTransport: AdminTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AdminClientError.invalidResponse
        }
        return (data, http)
    }
}

public struct AdminWatchEndpoint: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
}

public struct AdminStatus: Codable, Equatable, Sendable {
    public var bridge: String
    public var codex: String
    public var watch: AdminWatchEndpoint
    public var activeDevices: Int
}

public struct AdminSecurityChecks: Codable, Equatable, Sendable {
    public var adminLoopbackOnly: Bool
    public var watchLoopbackOnly: Bool
    public var strongAdminToken: Bool
}

public struct AdminSecuritySelfTest: Codable, Equatable, Sendable {
    public var ok: Bool
    public var checks: AdminSecurityChecks
}

public struct AdminPairingCode: Codable, Equatable, Sendable {
    public var code: String
    public var expiresAt: Int64
}

public struct AdminPairingSession: Codable, Equatable, Sendable {
    public var id: String
    public var discoveryToken: String
    public var code: String
    public var expiresAt: Int64
    public var macFingerprint: String
    public var origin: URL
}

private struct AdminPairingSessionRequest: Codable, Sendable {
    var origin: String
    var macName: String
    var macFingerprint: String
}

public struct AdminDevice: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var fingerprint: String
    public var createdAt: Int64
    public var revokedAt: Int64?
}

public struct AdminDeviceMetadata: Codable, Equatable, Sendable {
    public var platform: String
    public var manufacturer: String
    public var model: String
    public var osVersion: String
    public var appVersion: String
    public var screenShape: String

    public init(
        platform: String,
        manufacturer: String,
        model: String,
        osVersion: String,
        appVersion: String,
        screenShape: String
    ) {
        self.platform = platform
        self.manufacturer = manufacturer
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.screenShape = screenShape
    }
}

public struct AdminPendingPairing: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var fingerprint: String
    public var metadata: AdminDeviceMetadata
    public var expiresAt: Int64

    public init(
        id: String,
        name: String,
        fingerprint: String,
        metadata: AdminDeviceMetadata,
        expiresAt: Int64
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.metadata = metadata
        self.expiresAt = expiresAt
    }
}

public struct AdminCloudDeviceRegistration: Codable, Equatable, Sendable {
    public var accountId: String
    public var hostId: String
    public var deviceId: String
    public var name: String
    public var signingPublicKey: String
    public var rootKey: String
    public var metadata: AdminDeviceMetadata

    public init(
        accountId: String,
        hostId: String,
        deviceId: String,
        name: String,
        signingPublicKey: String,
        rootKey: String,
        metadata: AdminDeviceMetadata
    ) {
        self.accountId = accountId
        self.hostId = hostId
        self.deviceId = deviceId
        self.name = name
        self.signingPublicKey = signingPublicKey
        self.rootKey = rootKey
        self.metadata = metadata
    }
}

private struct AdminPendingPairings: Codable, Sendable {
    var pairings: [AdminPendingPairing]
}

private struct AdminApprovedPairing: Codable, Sendable {
    var device: AdminDevice
}

public struct AdminDevices: Codable, Equatable, Sendable {
    public var devices: [AdminDevice]
}

public struct AdminWorkspaceRoots: Codable, Equatable, Sendable {
    public var roots: [String]
}

public struct AdminVoiceStatus: Codable, Equatable, Sendable {
    public var configured: Bool
    public var provider: String?
}

private struct AdminOK: Codable, Sendable {
    var ok: Bool?
    var stopping: Bool?
}

private struct AdminCloudEvents: Codable, Sendable {
    var envelopes: [RelayTunnelEnvelope]
}

public struct AdminClient: Sendable {
    private let baseURL: URL
    private let token: @Sendable () throws -> String
    private let transport: any AdminTransport

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:43118")!,
        token: @escaping @Sendable () throws -> String,
        transport: any AdminTransport = URLSessionAdminTransport()
    ) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    public func status() async throws -> AdminStatus {
        try await request(["v1", "status"])
    }

    public func securitySelfTest() async throws -> AdminSecuritySelfTest {
        try await request(["v1", "security", "self-test"], method: "POST")
    }

    public func pairingCode() async throws -> AdminPairingCode {
        try await request(["v1", "pairing-code"], method: "POST")
    }

    public func createPairingSession(
        origin: URL,
        macName: String,
        macFingerprint: String
    ) async throws -> AdminPairingSession {
        let body = try JSONEncoder().encode(
            AdminPairingSessionRequest(
                origin: origin.absoluteString,
                macName: macName,
                macFingerprint: macFingerprint
            )
        )
        return try await request(
            ["v1", "pairing-sessions"],
            method: "POST",
            body: body
        )
    }

    public func devices() async throws -> [AdminDevice] {
        try await request(["v1", "devices"], as: AdminDevices.self).devices
    }

    public func pendingPairings() async throws -> [AdminPendingPairing] {
        try await request(
            ["v1", "pairing-sessions", "pending"],
            as: AdminPendingPairings.self
        ).pairings
    }

    public func approvePairing(id: String) async throws -> AdminDevice {
        try await request(
            ["v1", "pairing-sessions", id, "approve"],
            method: "POST",
            as: AdminApprovedPairing.self
        ).device
    }

    public func denyPairing(id: String) async throws {
        let _: AdminOK = try await request(
            ["v1", "pairing-sessions", id, "deny"],
            method: "POST"
        )
    }

    public func registerCloudDevice(
        _ registration: AdminCloudDeviceRegistration
    ) async throws {
        let _: AdminOK = try await request(
            ["v1", "cloud", "devices"],
            method: "POST",
            body: try JSONEncoder().encode(registration)
        )
    }

    public func processCloudEnvelope(
        _ envelope: RelayTunnelEnvelope
    ) async throws {
        let _: AdminOK = try await request(
            ["v1", "cloud", "envelopes"],
            method: "POST",
            body: try JSONEncoder().encode(envelope)
        )
    }

    public func cloudEvents() async throws -> [RelayTunnelEnvelope] {
        try await request(
            ["v1", "cloud", "events"],
            as: AdminCloudEvents.self
        ).envelopes
    }

    public func revoke(deviceID: String) async throws {
        let _: AdminOK = try await request(
            ["v1", "devices", deviceID, "revoke"],
            method: "POST"
        )
    }

    public func workspaces() async throws -> [String] {
        try await request(
            ["v1", "workspaces"],
            as: AdminWorkspaceRoots.self
        ).roots
    }

    public func replaceWorkspaces(_ roots: [String]) async throws -> [String] {
        let body = try JSONEncoder().encode(AdminWorkspaceRoots(roots: roots))
        return try await request(
            ["v1", "workspaces"],
            method: "PUT",
            body: body,
            as: AdminWorkspaceRoots.self
        ).roots
    }

    public func voiceStatus() async throws -> AdminVoiceStatus {
        try await request(["v1", "voice"])
    }

    public func shutdown() async throws {
        let _: AdminOK = try await request(["v1", "shutdown"], method: "POST")
    }

    private func request<Response: Decodable & Sendable>(
        _ path: [String],
        method: String = "GET",
        body: Data? = nil,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        let token = try token()
        guard !token.isEmpty else {
            throw AdminClientError.missingToken
        }
        let url = path.reduce(baseURL) {
            $0.appendingPathComponent($1)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 401 {
            throw AdminClientError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AdminClientError.rejected(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw AdminClientError.invalidResponse
        }
    }
}
