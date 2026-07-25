import Foundation

public enum TailscaleClientError: Error, Equatable, Sendable {
    case commandFailed
    case notSignedIn
    case bridgeSecurityCheckFailed
    case invalidStatus
    case loginURLMissing
    case loginTimedOut
}

public enum TailscaleCommandPlan {
    private static let cliEnvironment = ["TAILSCALE_BE_CLI": "1"]

    public static func status(tailscale: URL) -> CommandInvocation {
        CommandInvocation(
            executableURL: tailscale,
            arguments: ["status", "--json"],
            environment: cliEnvironment
        )
    }

    public static func loginURL(tailscale: URL) -> CommandInvocation {
        CommandInvocation(
            executableURL: tailscale,
            arguments: ["login", "--timeout=1s"],
            environment: cliEnvironment
        )
    }

    public static func enableFunnel(tailscale: URL) -> CommandInvocation {
        CommandInvocation(
            executableURL: tailscale,
            arguments: [
                "funnel",
                "--bg",
                "http://127.0.0.1:43117",
            ],
            environment: cliEnvironment
        )
    }

    public static func disableFunnel(tailscale: URL) -> CommandInvocation {
        CommandInvocation(
            executableURL: tailscale,
            arguments: ["funnel", "43117", "off"],
            environment: cliEnvironment
        )
    }

    public static func funnelStatus(tailscale: URL) -> CommandInvocation {
        CommandInvocation(
            executableURL: tailscale,
            arguments: ["funnel", "status", "--json"],
            environment: cliEnvironment
        )
    }
}

public struct TailscaleStatus: Equatable, Sendable {
    public var signedIn: Bool
    public var dnsName: String?
}

public struct EmergencyStopResult: Equatable, Sendable {
    public var funnelDisabled: Bool
    public var bridgeStopped: Bool

    public init(funnelDisabled: Bool, bridgeStopped: Bool) {
        self.funnelDisabled = funnelDisabled
        self.bridgeStopped = bridgeStopped
    }
}

public struct TailscaleClient: Sendable {
    public let executableURL: URL
    private let runner: any CommandRunning

    public init(
        executableURL: URL,
        runner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func status() async throws -> TailscaleStatus {
        let result = try await runner.run(
            TailscaleCommandPlan.status(tailscale: executableURL)
        )
        guard result.exitCode == 0 else {
            throw TailscaleClientError.commandFailed
        }
        struct StatusDocument: Decodable {
            struct SelfNode: Decodable {
                var dnsName: String?

                enum CodingKeys: String, CodingKey {
                    case dnsName = "DNSName"
                }
            }

            var backendState: String
            var selfNode: SelfNode?

            enum CodingKeys: String, CodingKey {
                case backendState = "BackendState"
                case selfNode = "Self"
            }
        }
        guard
            let document = try? JSONDecoder().decode(
                StatusDocument.self,
                from: Data(result.standardOutput.utf8)
            )
        else {
            throw TailscaleClientError.invalidStatus
        }
        return TailscaleStatus(
            signedIn: document.backendState == "Running",
            dnsName: document.selfNode?.dnsName?.trimmingCharacters(
                in: CharacterSet(charactersIn: ".")
            )
        )
    }

    public func login(
        openURL: @Sendable (URL) async -> Void,
        sleep: @Sendable () async throws -> Void = {
            try await Task.sleep(for: .seconds(2))
        },
        maximumPolls: Int = 60
    ) async throws -> TailscaleStatus {
        let result = try await runner.run(
            TailscaleCommandPlan.loginURL(tailscale: executableURL)
        )
        guard let loginURL = Self.officialLoginURL(
            in: result.standardOutput + "\n" + result.standardError
        ) else {
            throw TailscaleClientError.loginURLMissing
        }
        await openURL(loginURL)
        for poll in 0..<maximumPolls {
            try Task.checkCancellation()
            let current = try await status()
            if current.signedIn {
                return current
            }
            if poll + 1 < maximumPolls {
                try await sleep()
            }
        }
        throw TailscaleClientError.loginTimedOut
    }

    public func enableFunnel(
        securitySelfTest: @Sendable () async throws -> AdminSecuritySelfTest
    ) async throws -> URL {
        let current = try await status()
        guard current.signedIn, let dnsName = current.dnsName, !dnsName.isEmpty else {
            throw TailscaleClientError.notSignedIn
        }
        guard try await securitySelfTest().ok else {
            throw TailscaleClientError.bridgeSecurityCheckFailed
        }
        let result = try await runner.run(
            TailscaleCommandPlan.enableFunnel(tailscale: executableURL)
        )
        guard result.exitCode == 0 else {
            throw TailscaleClientError.commandFailed
        }
        guard let origin = URL(string: "https://\(dnsName)") else {
            throw TailscaleClientError.invalidStatus
        }
        return origin
    }

    public func disableFunnel() async throws {
        let result = try await runner.run(
            TailscaleCommandPlan.disableFunnel(tailscale: executableURL)
        )
        guard result.exitCode == 0 else {
            throw TailscaleClientError.commandFailed
        }
    }

    public func funnelEnabled() async throws -> Bool {
        let result = try await runner.run(
            TailscaleCommandPlan.funnelStatus(tailscale: executableURL)
        )
        guard
            result.exitCode == 0,
            let document = try? JSONSerialization.jsonObject(
                with: Data(result.standardOutput.utf8)
            )
        else {
            throw TailscaleClientError.invalidStatus
        }
        return Self.containsRelayPort(document)
    }

    public func emergencyStop(
        bridgeShutdown: @Sendable () async throws -> Void
    ) async -> EmergencyStopResult {
        let funnelDisabled: Bool
        do {
            try await disableFunnel()
            funnelDisabled = true
        } catch {
            funnelDisabled = false
        }
        let bridgeStopped: Bool
        do {
            try await bridgeShutdown()
            bridgeStopped = true
        } catch {
            bridgeStopped = false
        }
        return EmergencyStopResult(
            funnelDisabled: funnelDisabled,
            bridgeStopped: bridgeStopped
        )
    }

    private static func containsRelayPort(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.contains("43117")
        }
        if let number = value as? NSNumber {
            return number.intValue == 43_117
        }
        if let array = value as? [Any] {
            return array.contains(where: containsRelayPort)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.contains { key, value in
                key.contains("43117") || containsRelayPort(value)
            }
        }
        return false
    }

    private static func officialLoginURL(in output: String) -> URL? {
        output
            .split(whereSeparator: \.isWhitespace)
            .lazy
            .map {
                $0.trimmingCharacters(
                    in: CharacterSet(charactersIn: "<>()[]{}.,;\"'")
                )
            }
            .compactMap(URL.init(string:))
            .first {
                $0.scheme == "https" &&
                    $0.host?.lowercased() == "login.tailscale.com"
            }
    }
}
