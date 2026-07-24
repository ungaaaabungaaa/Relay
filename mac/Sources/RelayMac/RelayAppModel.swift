import Foundation
import RelayCore

@MainActor
final class RelayAppModel: ObservableObject {
    @Published var setupState = SetupState.checking
    @Published var bridgeState: BridgeSupervisorState = .stopped
    @Published var codexStatus = "Checking"
    @Published var funnelEnabled = false
    @Published var devices: [AdminDevice] = []
    @Published var workspaces: [String] = []
    @Published var voiceConfigured = false
    @Published var pairingCode: AdminPairingCode?
    @Published var pendingActionCount = 0
    @Published var updateAvailable = false
    @Published var lastError: String?
    @Published var diagnostic = "Relay is starting…"

    private let secrets: KeychainStore
    private let adminClient: AdminClient
    private var supervisor: BridgeSupervisor?

    init() {
        let secrets = KeychainStore()
        self.secrets = secrets
        self.adminClient = AdminClient {
            try secrets.value(for: .adminToken) ?? ""
        }
        Task {
            await bootstrap()
        }
    }

    var menuBarSymbol: String {
        bridgeState == .running
            ? "applewatch.radiowaves.left.and.right"
            : "applewatch.slash"
    }

    var activeDeviceCount: Int {
        devices.filter { $0.revokedAt == nil }.count
    }

    func bootstrap() async {
        do {
            let token = try ensureAdminToken()
            guard let executableURL = locateBridgeExecutable() else {
                bridgeState = .failed
                diagnostic = "The bundled bridge could not be found."
                updateSetupState(bridgeReady: false)
                return
            }
            supervisor = makeSupervisor(executableURL: executableURL, token: token)
            try await supervisor?.start()
            bridgeState = .running
            try? await Task.sleep(for: .milliseconds(250))
            await refresh()
        } catch {
            bridgeState = .failed
            lastError = "Relay could not start its local bridge."
            diagnostic = "Bridge startup failed. No secret values were logged."
            updateSetupState(bridgeReady: false)
        }
    }

    func refresh() async {
        do {
            let status = try await adminClient.status()
            let selfTest = try await adminClient.securitySelfTest()
            devices = try await adminClient.devices()
            workspaces = try await adminClient.workspaces()
            voiceConfigured = try await adminClient.voiceStatus().configured
            bridgeState = selfTest.ok ? .running : .failed
            codexStatus = status.codex.capitalized
            diagnostic = selfTest.ok
                ? "Local security self-test passed. Admin and watch ports are loopback-only."
                : "Local security self-test failed. Remote access remains disabled."
            lastError = nil
            updateSetupState(bridgeReady: selfTest.ok)
        } catch {
            bridgeState = .failed
            codexStatus = "Unavailable"
            lastError = "The local bridge is not responding."
            updateSetupState(bridgeReady: false)
        }
    }

    func createPairingCode() async {
        do {
            pairingCode = try await adminClient.pairingCode()
            lastError = nil
        } catch {
            lastError = "Relay could not create a pairing code."
        }
    }

    func revoke(_ device: AdminDevice) async {
        do {
            try await adminClient.revoke(deviceID: device.id)
            await refresh()
        } catch {
            lastError = "Relay could not revoke that watch."
        }
    }

    func replaceWorkspaces(_ roots: [String]) async {
        do {
            workspaces = try await adminClient.replaceWorkspaces(roots)
            lastError = nil
        } catch {
            lastError = "That folder could not be added to Relay."
        }
    }

    func saveOpenAIKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try secrets.remove(.openAIAPIKey)
            } else {
                try secrets.set(trimmed, for: .openAIAPIKey)
            }
            voiceConfigured = !trimmed.isEmpty
            lastError = nil
            diagnostic = "Voice configuration was saved in macOS Keychain."
        } catch {
            lastError = "Relay could not save the voice key in Keychain."
        }
    }

    func emergencyStop() async {
        funnelEnabled = false
        try? await adminClient.shutdown()
        await supervisor?.emergencyStop()
        bridgeState = .emergencyStopped
        diagnostic = "Emergency Stop closed Relay watch access. Codex tasks were left running."
        updateSetupState(bridgeReady: false)
    }

    func quit() async {
        try? await adminClient.shutdown()
        await supervisor?.stop()
    }

    func updateSupervisorSnapshot() async {
        guard let snapshot = await supervisor?.snapshot() else {
            return
        }
        bridgeState = snapshot.state
        if !snapshot.lastDiagnostic.isEmpty {
            diagnostic = snapshot.lastDiagnostic
        }
    }

    private func ensureAdminToken() throws -> String {
        if let existing = try secrets.value(for: .adminToken), !existing.isEmpty {
            return existing
        }
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let token = Data(bytes).base64EncodedString()
        try secrets.set(token, for: .adminToken)
        return token
    }

    private func locateBridgeExecutable() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            ProcessInfo.processInfo.environment["RELAY_BRIDGE_PATH"].map {
                URL(fileURLWithPath: $0)
            },
            Bundle.main.url(forResource: "relay-bridge-arm64", withExtension: nil),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("dist/relay-bridge-arm64"),
        ]
        return candidates
            .compactMap { $0 }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func makeSupervisor(
        executableURL: URL,
        token: String
    ) -> BridgeSupervisor {
        let fileManager = FileManager.default
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Relay", isDirectory: true)
        try? fileManager.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )
        var environment = [
            "CODEWATCH_ADMIN_TOKEN": token,
            "CODEWATCH_DATA_DIR": support.path,
            "CODEWATCH_BIND_HOST": "127.0.0.1",
            "CODEWATCH_ADMIN_HOST": "127.0.0.1",
            "CODEWATCH_PORT": "43117",
            "CODEWATCH_ADMIN_PORT": "43118",
        ]
        var sensitive = [token]
        if let openAIKey = try? secrets.value(for: .openAIAPIKey) {
            environment["OPENAI_API_KEY"] = openAIKey
            sensitive.append(openAIKey)
        }
        return BridgeSupervisor(
            launcher: ProcessBridgeLauncher(),
            configuration: BridgeLaunchConfiguration(
                executableURL: executableURL,
                environment: environment,
                sensitiveValues: sensitive
            )
        )
    }

    private func updateSetupState(bridgeReady: Bool) {
        setupState = SetupState(
            codex: codexStatus.lowercased() == "ready" ? .ready : .missing,
            tailscale: .missing,
            bridge: bridgeReady ? .ready : .missing,
            watchInstalled: !devices.isEmpty,
            watchPaired: activeDeviceCount > 0,
            remoteAccess: funnelEnabled ? .ready : .missing
        )
    }
}
