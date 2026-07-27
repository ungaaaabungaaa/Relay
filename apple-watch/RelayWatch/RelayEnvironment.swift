import Foundation

struct RelayEnvironment: Equatable, Sendable {
    enum Name: String, Equatable, Sendable {
        case production, staging, localDevelopment
    }

    let name: Name
    let httpOrigin: URL
    let webSocketOrigin: URL

    static let productionHTTPOrigin = URL(string: "https://api.relayforcodex.com")!
    static let stagingHTTPOrigin = URL(string: "https://staging-api.relayforcodex.com")!

    static func resolve(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool
    ) throws -> Self {
        guard let override = processEnvironment["RELAY_CLOUD_ORIGIN"], !override.isEmpty else {
            return compiled(.production)
        }
        guard isDebugBuild else { throw RelayEnvironmentError.releaseOverrideForbidden }
        guard let origin = URL(string: override), isSafeOrigin(origin) else {
            throw RelayEnvironmentError.invalidDevelopmentOrigin
        }

        if origin == stagingHTTPOrigin {
            return compiled(.staging)
        }
        guard isLoopback(origin.host) else {
            throw RelayEnvironmentError.invalidDevelopmentOrigin
        }
        return RelayEnvironment(
            name: .localDevelopment,
            httpOrigin: origin,
            webSocketOrigin: try relayWebSocketOrigin(for: origin)
        )
    }

    private static func compiled(_ name: Name) -> Self {
        let httpOrigin = name == .staging ? stagingHTTPOrigin : productionHTTPOrigin
        return RelayEnvironment(
            name: name,
            httpOrigin: httpOrigin,
            webSocketOrigin: URL(string: name == .staging
                ? "wss://staging-api.relayforcodex.com"
                : "wss://api.relayforcodex.com")!
        )
    }
}

enum RelayEnvironmentError: Error, Equatable, Sendable {
    case releaseOverrideForbidden
    case invalidDevelopmentOrigin
}

private func isSafeOrigin(_ origin: URL) -> Bool {
    guard
        origin.user == nil,
        origin.password == nil,
        origin.query == nil,
        origin.fragment == nil,
        origin.path.isEmpty || origin.path == "/",
        let scheme = origin.scheme?.lowercased(),
        let host = origin.host,
        !host.isEmpty
    else {
        return false
    }
    if scheme == "https" { return true }
    return scheme == "http" && isLoopback(host)
}

private func isLoopback(_ host: String?) -> Bool {
    guard let host else { return false }
    return host.lowercased() == "localhost" || host == "127.0.0.1" || host == "::1"
}

private func relayWebSocketOrigin(for httpOrigin: URL) throws -> URL {
    guard var components = URLComponents(url: httpOrigin, resolvingAgainstBaseURL: false) else {
        throw RelayEnvironmentError.invalidDevelopmentOrigin
    }
    components.scheme = httpOrigin.scheme?.lowercased() == "https" ? "wss" : "ws"
    guard let origin = components.url else {
        throw RelayEnvironmentError.invalidDevelopmentOrigin
    }
    return origin
}
