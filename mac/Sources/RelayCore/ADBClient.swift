import Foundation

public enum ADBClientError: Error, Equatable, Sendable {
    case invalidAddress
    case commandFailed(String)
    case notAWearOSDevice
    case installedVersionMismatch
}

public enum ADBCommandPlan {
    public static func pair(
        adb: URL,
        address: String,
        code: String
    ) -> CommandInvocation {
        CommandInvocation(
            executableURL: adb,
            arguments: ["pair", address, code]
        )
    }

    public static func connect(adb: URL, address: String) -> CommandInvocation {
        CommandInvocation(
            executableURL: adb,
            arguments: ["connect", address]
        )
    }

    public static func install(
        adb: URL,
        serial: String,
        apk: URL
    ) -> CommandInvocation {
        CommandInvocation(
            executableURL: adb,
            arguments: ["-s", serial, "install", "-r", apk.path]
        )
    }

    public static func discover(adb: URL) -> CommandInvocation {
        CommandInvocation(executableURL: adb, arguments: ["mdns", "services"])
    }

    public static func features(adb: URL, serial: String) -> CommandInvocation {
        CommandInvocation(
            executableURL: adb,
            arguments: ["-s", serial, "shell", "pm", "list", "features"]
        )
    }

    public static func packageInfo(
        adb: URL,
        serial: String,
        packageID: String
    ) -> CommandInvocation {
        CommandInvocation(
            executableURL: adb,
            arguments: [
                "-s", serial, "shell", "dumpsys", "package", packageID,
            ]
        )
    }

    public static func launch(
        adb: URL,
        serial: String,
        component: String
    ) -> CommandInvocation {
        CommandInvocation(
            executableURL: adb,
            arguments: [
                "-s", serial, "shell", "am", "start", "-n", component,
            ]
        )
    }
}

public struct ADBMDNSServices: Equatable, Sendable {
    public var pairing: [String]
    public var connection: [String]
}

public struct ADBClient: Sendable {
    public let executableURL: URL
    private let runner: any CommandRunning

    public init(
        executableURL: URL,
        runner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public func discover() async throws -> ADBMDNSServices {
        let result = try await runner.run(ADBCommandPlan.discover(adb: executableURL))
        guard result.exitCode == 0 else {
            throw ADBClientError.commandFailed("Wireless discovery failed")
        }
        return Self.parseMDNSServices(result.standardOutput)
    }

    public func pair(address: String, code: String) async throws {
        guard Self.isValidAddress(address), code.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            throw ADBClientError.invalidAddress
        }
        let result = try await runner.run(
            ADBCommandPlan.pair(
                adb: executableURL,
                address: address,
                code: code
            )
        )
        guard result.exitCode == 0 else {
            throw ADBClientError.commandFailed("Watch pairing failed")
        }
    }

    public func connect(address: String) async throws -> String {
        guard Self.isValidAddress(address) else {
            throw ADBClientError.invalidAddress
        }
        let result = try await runner.run(
            ADBCommandPlan.connect(adb: executableURL, address: address)
        )
        guard result.exitCode == 0 else {
            throw ADBClientError.commandFailed("Watch connection failed")
        }
        return address
    }

    public func verifyWearOS(serial: String) async throws {
        let result = try await runner.run(
            ADBCommandPlan.features(adb: executableURL, serial: serial)
        )
        guard
            result.exitCode == 0,
            result.standardOutput.contains("feature:android.hardware.type.watch")
        else {
            throw ADBClientError.notAWearOSDevice
        }
    }

    public func install(
        apk: URL,
        serial: String,
        packageID: String,
        expectedVersionCode: Int
    ) async throws {
        let installed = try await runner.run(
            ADBCommandPlan.install(adb: executableURL, serial: serial, apk: apk)
        )
        guard installed.exitCode == 0 else {
            throw ADBClientError.commandFailed("Relay installation failed")
        }
        let info = try await runner.run(
            ADBCommandPlan.packageInfo(
                adb: executableURL,
                serial: serial,
                packageID: packageID
            )
        )
        guard
            info.exitCode == 0,
            Self.versionCode(from: info.standardOutput) == expectedVersionCode
        else {
            throw ADBClientError.installedVersionMismatch
        }
    }

    public func launch(serial: String, component: String) async throws {
        let result = try await runner.run(
            ADBCommandPlan.launch(
                adb: executableURL,
                serial: serial,
                component: component
            )
        )
        guard result.exitCode == 0 else {
            throw ADBClientError.commandFailed("Relay could not open on the watch")
        }
    }

    public static func parseMDNSServices(_ output: String) -> ADBMDNSServices {
        var pairing = Set<String>()
        var connection = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let address = fields.last(where: { $0.contains(":") }) else {
                continue
            }
            if fields.contains(where: { $0.contains("_adb-tls-pairing._tcp") }) {
                pairing.insert(address)
            }
            if fields.contains(where: { $0.contains("_adb-tls-connect._tcp") }) {
                connection.insert(address)
            }
        }
        return ADBMDNSServices(
            pairing: pairing.sorted(),
            connection: connection.sorted()
        )
    }

    public static func versionCode(from packageInfo: String) -> Int? {
        guard
            let range = packageInfo.range(
                of: #"versionCode=(\d+)"#,
                options: .regularExpression
            )
        else {
            return nil
        }
        let match = String(packageInfo[range])
        return Int(match.dropFirst("versionCode=".count))
    }

    private static func isValidAddress(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9._-]+:\d{1,5}$"#,
            options: .regularExpression
        ) != nil
    }
}

public enum ADBWizardState: Equatable, Sendable {
    case idle
    case discovering
    case manualEntry
    case readyToPair(ADBMDNSServices)
    case pairing
    case connecting
    case verifyingWatch
    case installing
    case verifyingInstall
    case ready(serial: String)
    case failed(String)
}

public actor ADBWizard {
    private let client: ADBClient
    private(set) public var state: ADBWizardState = .idle
    private var serial: String?

    public init(client: ADBClient) {
        self.client = client
    }

    public func discover() async {
        state = .discovering
        do {
            let services = try await client.discover()
            state = services.pairing.isEmpty && services.connection.isEmpty
                ? .manualEntry
                : .readyToPair(services)
        } catch {
            state = .manualEntry
        }
    }

    public func pairAndConnect(
        pairingAddress: String,
        code: String,
        connectionAddress: String
    ) async {
        do {
            state = .pairing
            try await client.pair(address: pairingAddress, code: code)
            state = .connecting
            let connected = try await client.connect(address: connectionAddress)
            state = .verifyingWatch
            try await client.verifyWearOS(serial: connected)
            serial = connected
            state = .ready(serial: connected)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    public func install(
        apk: URL,
        packageID: String,
        expectedVersionCode: Int,
        component: String
    ) async {
        guard let serial else {
            state = .failed("Connect a Wear OS watch first.")
            return
        }
        do {
            state = .installing
            try await client.install(
                apk: apk,
                serial: serial,
                packageID: packageID,
                expectedVersionCode: expectedVersionCode
            )
            state = .verifyingInstall
            try await client.launch(serial: serial, component: component)
            state = .ready(serial: serial)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case ADBClientError.invalidAddress:
            "Check the watch IP address and port."
        case ADBClientError.notAWearOSDevice:
            "The connected device is not a Wear OS watch."
        case ADBClientError.installedVersionMismatch:
            "Relay installed, but its version could not be verified."
        default:
            "Wireless watch setup failed. Reopen Wireless debugging and try again."
        }
    }
}
