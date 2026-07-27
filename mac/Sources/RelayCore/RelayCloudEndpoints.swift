import Foundation

public enum RelayCloudEnvironmentName: String, Equatable, Sendable {
    case production
    case staging
    case localDevelopment = "local-development"
}

public enum RelayCloudEndpointError: Error, Equatable, Sendable {
    case releaseOverrideForbidden
    case invalidDevelopmentOrigin
}

public struct RelayCloudEndpoints: Equatable, Sendable {
    public let apiOrigin: URL
    public let hostWebSocketURL: URL
    public let environment: RelayCloudEnvironmentName

    public static func resolve(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool
    ) throws -> RelayCloudEndpoints {
        guard let value = processEnvironment["RELAY_CLOUD_ORIGIN"], !value.isEmpty else {
            return try endpoints(
                origin: URL(string: "https://api.relayforcodex.com")!,
                environment: .production
            )
        }
        guard isDebugBuild else { throw RelayCloudEndpointError.releaseOverrideForbidden }
        guard let origin = URL(string: value), safe(origin) else {
            throw RelayCloudEndpointError.invalidDevelopmentOrigin
        }
        if origin == URL(string: "https://staging-api.relayforcodex.com")! {
            return try endpoints(origin: origin, environment: .staging)
        }
        guard loopback(origin.host) else {
            throw RelayCloudEndpointError.invalidDevelopmentOrigin
        }
        return try endpoints(origin: origin, environment: .localDevelopment)
    }

    private static func endpoints(
        origin: URL,
        environment: RelayCloudEnvironmentName
    ) throws -> RelayCloudEndpoints {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw RelayCloudEndpointError.invalidDevelopmentOrigin
        }
        components.scheme = origin.scheme?.lowercased() == "https" ? "wss" : "ws"
        components.path = "/cloud/v1/connect/host"
        guard let webSocket = components.url else {
            throw RelayCloudEndpointError.invalidDevelopmentOrigin
        }
        return RelayCloudEndpoints(
            apiOrigin: origin,
            hostWebSocketURL: webSocket,
            environment: environment
        )
    }

    private static func safe(_ origin: URL) -> Bool {
        guard
            origin.user == nil,
            origin.password == nil,
            origin.query == nil,
            origin.fragment == nil,
            origin.path.isEmpty || origin.path == "/",
            let scheme = origin.scheme?.lowercased(),
            let host = origin.host,
            !host.isEmpty
        else { return false }
        return scheme == "https" || (scheme == "http" && loopback(host))
    }

    private static func loopback(_ host: String?) -> Bool {
        guard let host else { return false }
        return host.lowercased() == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
