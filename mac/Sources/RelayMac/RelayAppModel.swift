import AppKit
import Foundation
import RelayCore
import ServiceManagement

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
    @Published var pairingSession: AdminPairingSession?
    @Published var pendingPairings: [AdminPendingPairing] = []
    @Published var hostFingerprint = "Loading…"
    @Published var pendingActionCount = 0
    @Published var updateAvailable = false
    @Published var lastError: String?
    @Published var diagnostic = "Relay is starting…"
    @Published var platformToolsReady = false
    @Published var adbWizardState: ADBWizardState = .idle
    @Published var tailscaleInstalled = false
    @Published var tailscaleSignedIn = false
    @Published var tailscaleLoginInProgress = false
    @Published var funnelOrigin: URL?
    @Published var temporaryPairingTransport = false
    @Published var watchInstalled = false
    @Published var emergencyStopResult: EmergencyStopResult?
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published var cloudSignedIn = false
    @Published var cloudConnected = false
    @Published var cloudLoginInProgress = false
    @Published var cloudPairingSession: RelayCloudPairingSession?

    private let secrets: KeychainStore
    private let adminClient: AdminClient
    private var supervisor: BridgeSupervisor?
    private var adbWizard: ADBWizard?
    private var tailscaleClient: TailscaleClient?
    private let discoveryAdvertiser = PairingDiscoveryAdvertiser()
    private let pairingTransportLease = TemporaryPairingTransportLease()
    let updateController = RelayUpdateController()
    private var tailscaleLoginTask: Task<Void, Never>?
    private let cloudClient = RelayCloudClient()
    private var cloudAccessToken: String?
    private var cloudLoginTask: Task<Void, Never>?

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

    var setupJourney: SetupJourney {
        SetupJourney(
            codexAndIntegrityReady: codexStatus.lowercased() == "ready",
            signedIn: cloudSignedIn,
            cloudConnected: cloudConnected,
            watchPaired: activeDeviceCount > 0,
            workspacesSelected: !workspaces.isEmpty,
            startAtLoginEnabled: startAtLogin
        )
    }

    func bootstrap() async {
        await detectLocalDependencies()
        do {
            hostFingerprint = try RelayHostIdentity.loadOrCreate(
                in: secrets
            ).fingerprint
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
            pendingPairings = try await adminClient.pendingPairings()
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

    func createSecurePairingSession() async {
        guard
            cloudConnected,
            let accessToken = cloudAccessToken,
            let hostID = try? secrets.value(for: .cloudHostID),
            !hostID.isEmpty
        else {
            lastError = "Connect Relay Cloud before starting watch pairing."
            return
        }
        do {
            let keys = try RelayCloudHostKeys.loadOrCreate(in: secrets)
            hostFingerprint = keys.fingerprint
            cloudPairingSession = try await cloudClient.createPairingSession(
                accessToken: accessToken,
                hostID: hostID,
                macFingerprint: keys.fingerprint
            )
            pendingPairings = []
            lastError = nil
            diagnostic = "Cloud pairing is open for five minutes."
        } catch {
            cloudPairingSession = nil
            lastError = "Relay could not start secure watch pairing."
        }
    }

    func refreshPendingPairings() async {
        do {
            pendingPairings = try await adminClient.pendingPairings()
            lastError = nil
        } catch {
            lastError = "Relay could not refresh pending watch approvals."
        }
    }

    func approvePairing(_ pairing: AdminPendingPairing) async {
        do {
            _ = try await adminClient.approvePairing(id: pairing.id)
            discoveryAdvertiser.stop()
            pairingSession = nil
            pendingPairings = []
            let closed = await closeTemporaryPairingTransport()
            await refresh()
            if !closed {
                reportTemporaryPairingCloseFailure()
            }
        } catch {
            lastError = "That pairing request expired. Start pairing again."
        }
    }

    func denyPairing(_ pairing: AdminPendingPairing) async {
        do {
            try await adminClient.denyPairing(id: pairing.id)
            discoveryAdvertiser.stop()
            pairingSession = nil
            pendingPairings = []
            let closed = await closeTemporaryPairingTransport()
            if closed {
                lastError = nil
            }
        } catch {
            lastError = "That pairing request is no longer available."
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
        temporaryPairingTransport = false
        await pairingTransportLease.promote()
        if let tailscaleClient {
            emergencyStopResult = await tailscaleClient.emergencyStop {
                try await self.adminClient.shutdown()
            }
        } else {
            let bridgeStopped = (try? await adminClient.shutdown()) != nil
            emergencyStopResult = EmergencyStopResult(
                funnelDisabled: true,
                bridgeStopped: bridgeStopped
            )
        }
        await supervisor?.emergencyStop()
        bridgeState = .emergencyStopped
        diagnostic = "Emergency Stop closed Relay watch access. Codex tasks were left running."
        updateSetupState(bridgeReady: false)
    }

    func installPlatformTools() async {
        do {
            let support = applicationSupportDirectory()
            let adb = try await PlatformToolsManager().install(
                installationRoot: support
            )
            platformToolsReady = true
            adbWizard = ADBWizard(client: ADBClient(executableURL: adb))
            adbWizardState = .idle
            lastError = nil
            diagnostic = "Official Platform Tools 37.0.0 passed SHA-256 verification."
        } catch {
            platformToolsReady = false
            lastError = "Platform Tools failed integrity verification or installation."
        }
    }

    func signInToTailscale() {
        guard let client = tailscaleClient else {
            lastError = "Install the official Tailscale Mac app first."
            return
        }
        tailscaleLoginTask?.cancel()
        tailscaleLoginInProgress = true
        lastError = nil
        tailscaleLoginTask = Task {
            do {
                let status = try await client.login { url in
                    await MainActor.run {
                        _ = NSWorkspace.shared.open(url)
                    }
                }
                tailscaleSignedIn = status.signedIn
                tailscaleLoginInProgress = false
                diagnostic = "Tailscale sign-in completed through the official browser flow."
                updateSetupState(bridgeReady: bridgeState == .running)
            } catch is CancellationError {
                tailscaleLoginInProgress = false
                lastError = "Tailscale sign-in was cancelled."
            } catch {
                tailscaleLoginInProgress = false
                lastError = "Tailscale sign-in did not finish within two minutes."
            }
        }
    }

    func signInToRelayCloud(email: String) {
        cloudLoginTask?.cancel()
        cloudLoginInProgress = true
        lastError = nil
        cloudLoginTask = Task {
            do {
                let session = try await cloudClient.startDeviceLogin(email: email)
                _ = NSWorkspace.shared.open(session.verificationURL)
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(600))
                while clock.now < deadline {
                    try Task.checkCancellation()
                    if let tokens = try await cloudClient.pollForToken(
                        sessionID: session.id,
                        pkceVerifier: session.pkceVerifier
                    ) {
                        try secrets.set(
                            tokens.refreshToken,
                            for: .cloudRefreshToken
                        )
                        let keys = try RelayCloudHostKeys.loadOrCreate(
                            in: secrets
                        )
                        if try secrets.value(for: .cloudHostID) == nil {
                            let host = try await cloudClient.registerHost(
                                accessToken: tokens.accessToken,
                                name: Host.current().localizedName ?? "Relay Mac",
                                signingPublicKey: keys.signingPublicKey,
                                agreementPublicKey: keys.agreementPublicKey
                            )
                            try secrets.set(host.id, for: .cloudHostID)
                            try secrets.set(
                                host.credential,
                                for: .cloudHostCredential
                            )
                        }
                        cloudAccessToken = tokens.accessToken
                        cloudSignedIn = true
                        cloudConnected = true
                        funnelEnabled = true
                        cloudLoginInProgress = false
                        diagnostic = "Relay Cloud is connected with end-to-end encryption."
                        updateSetupState(bridgeReady: bridgeState == .running)
                        return
                    }
                    try await Task.sleep(for: .seconds(2))
                }
                throw RelayCloudClientError.authenticationFailed
            } catch is CancellationError {
                cloudLoginInProgress = false
            } catch {
                cloudLoginInProgress = false
                cloudSignedIn = false
                cloudConnected = false
                lastError = "Relay Cloud sign-in did not complete."
            }
        }
    }

    func cancelRelayCloudLogin() {
        cloudLoginTask?.cancel()
        cloudLoginTask = nil
        cloudLoginInProgress = false
    }

    func signOutOfRelayCloud() async {
        if let refreshToken = try? secrets.value(for: .cloudRefreshToken) {
            try? await cloudClient.logout(refreshToken: refreshToken)
        }
        try? secrets.remove(.cloudRefreshToken)
        try? secrets.remove(.cloudHostCredential)
        cloudAccessToken = nil
        cloudSignedIn = false
        cloudConnected = false
        funnelEnabled = false
        updateSetupState(bridgeReady: bridgeState == .running)
    }

    func cancelTailscaleLogin() {
        tailscaleLoginTask?.cancel()
        tailscaleLoginTask = nil
    }

    func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            startAtLogin = SMAppService.mainApp.status == .enabled
            lastError = nil
        } catch {
            startAtLogin = SMAppService.mainApp.status == .enabled
            lastError = "macOS could not change Relay’s login-item setting."
        }
    }

    func discoverWatch() async {
        guard let adbWizard else {
            lastError = "Install or locate Android Platform Tools first."
            return
        }
        await adbWizard.discover()
        adbWizardState = await adbWizard.state
    }

    func pairWatch(
        pairingAddress: String,
        code: String,
        connectionAddress: String
    ) async {
        guard let adbWizard else {
            lastError = "Android Platform Tools are not ready."
            return
        }
        await adbWizard.pairAndConnect(
            pairingAddress: pairingAddress,
            code: code,
            connectionAddress: connectionAddress
        )
        adbWizardState = await adbWizard.state
        if case .failed(let message) = adbWizardState {
            lastError = message
        } else {
            lastError = nil
        }
    }

    func installWatchApp() async {
        guard let adbWizard else {
            lastError = "Connect the watch first."
            return
        }
        guard let apk = locateWatchAPK() else {
            lastError = "The bundled Relay watch APK could not be found."
            return
        }
        guard let metadata = bundledReleaseMetadata() else {
            lastError = "The bundled watch release metadata is missing or invalid."
            return
        }
        await adbWizard.install(
            apk: apk,
            packageID: "dev.ungaaaabungaaa.relay",
            expectedVersionCode: metadata.watchVersionCode,
            component: "dev.ungaaaabungaaa.relay/.MainActivity"
        )
        adbWizardState = await adbWizard.state
        if case .ready = adbWizardState {
            watchInstalled = true
            diagnostic = "Relay was installed and its version verified on the watch."
            lastError = nil
        } else if case .failed(let message) = adbWizardState {
            lastError = message
        }
        updateSetupState(bridgeReady: bridgeState == .running)
    }

    func enableRemoteAccess() async {
        guard let tailscaleClient else {
            lastError = "Install Tailscale, sign in, then run checks again."
            return
        }
        do {
            if temporaryPairingTransport {
                let preflight = try await adminClient.securitySelfTest()
                guard preflight.ok else {
                    throw TailscaleClientError.bridgeSecurityCheckFailed
                }
                await pairingTransportLease.promote()
            } else {
                funnelOrigin = try await tailscaleClient.enableFunnel {
                    try await self.adminClient.securitySelfTest()
                }
            }
            funnelEnabled = true
            temporaryPairingTransport = false
            lastError = nil
            diagnostic = "Funnel exposes only the authenticated watch port. Admin stays local."
        } catch {
            funnelEnabled = false
            lastError = "Remote access preflight failed. Relay left Funnel disabled."
        }
        updateSetupState(bridgeReady: bridgeState == .running)
    }

    func disableRemoteAccess() async {
        guard let tailscaleClient else {
            funnelEnabled = false
            return
        }
        if temporaryPairingTransport {
            let closed = await closeTemporaryPairingTransport()
            funnelEnabled = !closed
            if closed {
                lastError = nil
            }
            updateSetupState(bridgeReady: bridgeState == .running)
            return
        }
        do {
            try await tailscaleClient.disableFunnel()
            funnelEnabled = false
            funnelOrigin = nil
            temporaryPairingTransport = false
            lastError = nil
        } catch {
            lastError = "Relay could not confirm that Funnel was disabled."
        }
        updateSetupState(bridgeReady: bridgeState == .running)
    }

    func quit() async {
        cancelTailscaleLogin()
        discoveryAdvertiser.stop()
        await closeTemporaryPairingTransport()
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

    private func locateWatchAPK() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "relay-wear", withExtension: "apk"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("wear/build/outputs/apk/debug/wear-debug.apk"),
        ]
        return candidates
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    private func bundledReleaseMetadata() -> BundledReleaseMetadata? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "relay-release", withExtension: "json"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("release/bundled-metadata.json"),
        ]
        return candidates
            .compactMap { $0 }
            .first(where: { fileManager.fileExists(atPath: $0.path) })
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? BundledReleaseMetadata.decode($0) }
    }

    @discardableResult
    private func closeTemporaryPairingTransport() async -> Bool {
        await pairingTransportLease.finish()
        if temporaryPairingTransport {
            await expireTemporaryPairingTransport()
        }
        return !temporaryPairingTransport
    }

    private func expireTemporaryPairingTransport(
        expectedSessionID: String? = nil
    ) async {
        if let expectedSessionID, pairingSession?.id != expectedSessionID {
            return
        }
        guard temporaryPairingTransport, let tailscaleClient else {
            return
        }
        discoveryAdvertiser.stop()
        pairingSession = nil
        pendingPairings = []
        do {
            try await tailscaleClient.disableFunnel()
            temporaryPairingTransport = false
            funnelOrigin = nil
            diagnostic = "The temporary pairing endpoint closed."
        } catch {
            reportTemporaryPairingCloseFailure()
        }
    }

    private func reportTemporaryPairingCloseFailure() {
        diagnostic = "Temporary access may still be open. Use Emergency Stop and check Tailscale."
        lastError = "Relay could not confirm that temporary pairing access closed."
    }

    private func detectLocalDependencies() async {
        if let adb = locateADB() {
            platformToolsReady = true
            adbWizard = ADBWizard(client: ADBClient(executableURL: adb))
        }
        if let tailscale = locateTailscale() {
            tailscaleInstalled = true
            let client = TailscaleClient(executableURL: tailscale)
            tailscaleClient = client
            if let status = try? await client.status() {
                tailscaleSignedIn = status.signedIn
                funnelEnabled = (try? await client.funnelEnabled()) ?? false
                if funnelEnabled, let dnsName = status.dnsName {
                    funnelOrigin = URL(string: "https://\(dnsName)")
                }
            }
        }
        updateSetupState(bridgeReady: bridgeState == .running)
    }

    private func locateADB() -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let candidates: [URL?] = [
            environment["ANDROID_HOME"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("platform-tools/adb")
            },
            environment["ANDROID_SDK_ROOT"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("platform-tools/adb")
            },
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Android/sdk/platform-tools/adb"),
            applicationSupportDirectory().appendingPathComponent("platform-tools/adb"),
        ]
        return candidates
            .compactMap { $0 }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func locateTailscale() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
        ].map(URL.init(fileURLWithPath:))
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func makeSupervisor(
        executableURL: URL,
        token: String
    ) -> BridgeSupervisor {
        let fileManager = FileManager.default
        let support = applicationSupportDirectory()
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
            account: cloudSignedIn ? .ready : .missing,
            bridge: bridgeReady ? .ready : .missing,
            watchPaired: activeDeviceCount > 0,
            cloud: cloudConnected ? .ready : .missing
        )
    }

    private func applicationSupportDirectory() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Relay", isDirectory: true)
    }
}
