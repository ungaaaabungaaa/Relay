import AppKit
import Foundation
import RelayCore
import ServiceManagement

@MainActor
final class RelayAppModel: ObservableObject {
    @Published var setupState = SetupState.checking
    @Published var bridgeState: BridgeSupervisorState = .stopped
    @Published var codexStatus = "Checking"
    @Published var devices: [AdminDevice] = []
    @Published var workspaces: [String] = []
    @Published var voiceConfigured = false
    @Published var pendingPairings: [AdminPendingPairing] = []
    @Published var hostFingerprint = "Loading…"
    @Published var pendingActionCount = 0
    @Published var updateAvailable = false
    @Published var lastError: String?
    @Published var diagnostic = "Relay is starting…"
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published var cloudSignedIn = false
    @Published var cloudConnected = false
    @Published var cloudLoginInProgress = false
    @Published var cloudPairingSession: RelayCloudPairingSession?

    private let secrets: KeychainStore
    private let adminClient: AdminClient
    private var supervisor: BridgeSupervisor?
    let updateController = RelayUpdateController()
    private let cloudClient = RelayCloudClient()
    private let cloudTunnel = RelayCloudHostTunnel()
    private var cloudAccessToken: String?
    private var cloudLoginTask: Task<Void, Never>?
    private var cloudTunnelTask: Task<Void, Never>?
    private var cloudPairingRequests: [String: RelayCloudPairingRequest] = [:]

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
            await restoreRelayCloudSession()
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
            pendingPairings = cloudPendingPairings
            workspaces = try await adminClient.workspaces()
            voiceConfigured = try await adminClient.voiceStatus().configured
            bridgeState = selfTest.ok ? .running : .failed
            codexStatus = status.codex.capitalized
            diagnostic = selfTest.ok
                ? "Local security self-test passed. Admin and watch ports are loopback-only."
                : "Local security self-test failed. Relay Cloud actions remain disabled."
            lastError = nil
            updateSetupState(bridgeReady: selfTest.ok)
        } catch {
            bridgeState = .failed
            codexStatus = "Unavailable"
            lastError = "The local bridge is not responding."
            updateSetupState(bridgeReady: false)
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
        pendingPairings = cloudPendingPairings
        lastError = nil
    }

    func approvePairing(_ pairing: AdminPendingPairing) async {
        guard let cloudRequest = cloudPairingRequests[pairing.id] else {
            lastError = "That pairing request is no longer available."
            return
        }
        await approveCloudPairing(cloudRequest)
    }

    func denyPairing(_ pairing: AdminPendingPairing) async {
        guard cloudPairingRequests[pairing.id] != nil else {
            lastError = "That pairing request is no longer available."
            return
        }
        await denyCloudPairing(pairing.id)
    }

    func revoke(_ device: AdminDevice) async {
        do {
            if
                try RelayCloudDeviceVault.devices(in: secrets).contains(
                    where: { $0.deviceId == device.id }
                ),
                let accessToken = cloudAccessToken
            {
                try await cloudClient.revokeDevice(
                    accessToken: accessToken,
                    deviceID: device.id
                )
                try RelayCloudDeviceVault.remove(
                    deviceID: device.id,
                    from: secrets
                )
            }
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
        cloudTunnelTask?.cancel()
        cloudTunnelTask = nil
        await cloudTunnel.disconnect()
        if let accessToken = cloudAccessToken,
           let stopped = try? await cloudClient.emergencyStop(
               accessToken: accessToken
           ) {
            try? secrets.set(
                stopped.hostCredential,
                for: .cloudHostCredential
            )
        }
        try? RelayCloudDeviceVault.removeAll(from: secrets)
        _ = try? await adminClient.shutdown()
        await supervisor?.emergencyStop()
        bridgeState = .emergencyStopped
        cloudConnected = false
        diagnostic = "Emergency Stop closed Relay watch access. Codex tasks were left running."
        updateSetupState(bridgeReady: false)
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
                        cloudLoginInProgress = false
                        startCloudTunnel()
                        diagnostic = "Relay Cloud sign-in completed. Connecting the encrypted tunnel…"
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
        cloudTunnelTask?.cancel()
        cloudTunnelTask = nil
        await cloudTunnel.disconnect()
        if let refreshToken = try? secrets.value(for: .cloudRefreshToken) {
            try? await cloudClient.logout(refreshToken: refreshToken)
        }
        try? secrets.remove(.cloudRefreshToken)
        cloudAccessToken = nil
        cloudSignedIn = false
        cloudConnected = false
        updateSetupState(bridgeReady: bridgeState == .running)
    }

    func deleteRelayAccount() async {
        guard let accessToken = cloudAccessToken else {
            lastError = "Sign in before deleting this Relay account."
            return
        }
        do {
            try await cloudClient.deleteAccount(accessToken: accessToken)
            cloudTunnelTask?.cancel()
            cloudTunnelTask = nil
            await cloudTunnel.disconnect()
            _ = try? await adminClient.shutdown()
            await supervisor?.emergencyStop()
            for secret in [
                RelaySecret.cloudRefreshToken,
                .cloudHostID,
                .cloudHostCredential,
                .cloudRootKeys,
                .cloudSigningPrivateKey,
                .cloudAgreementPrivateKey,
            ] {
                try? secrets.remove(secret)
            }
            cloudAccessToken = nil
            cloudSignedIn = false
            cloudConnected = false
            cloudPairingSession = nil
            cloudPairingRequests = [:]
            pendingPairings = []
            bridgeState = .emergencyStopped
            diagnostic = "The Relay account and every paired watch were deleted."
            lastError = nil
            updateSetupState(bridgeReady: false)
        } catch {
            lastError = "Relay could not confirm account deletion. Try again while online."
        }
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

    func quit() async {
        cloudTunnelTask?.cancel()
        await cloudTunnel.disconnect()
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

    private var cloudPendingPairings: [AdminPendingPairing] {
        cloudPairingRequests.values
            .sorted { $0.expiresAt < $1.expiresAt }
            .map {
                AdminPendingPairing(
                    id: $0.id,
                    name: $0.metadata.model.isEmpty
                        ? "Relay Watch"
                        : $0.metadata.model,
                    fingerprint: $0.fingerprint,
                    metadata: AdminDeviceMetadata(
                        platform: $0.metadata.platform,
                        manufacturer: $0.metadata.manufacturer,
                        model: $0.metadata.model,
                        osVersion: $0.metadata.osVersion,
                        appVersion: $0.metadata.appVersion,
                        screenShape: $0.metadata.screenShape
                    ),
                    expiresAt: $0.expiresAt
                )
            }
    }

    private func restoreRelayCloudSession() async {
        guard
            let refreshToken = try? secrets.value(for: .cloudRefreshToken),
            let hostID = try? secrets.value(for: .cloudHostID),
            let hostCredential = try? secrets.value(for: .cloudHostCredential),
            !refreshToken.isEmpty,
            !hostID.isEmpty,
            !hostCredential.isEmpty
        else {
            return
        }
        do {
            let tokens = try await cloudClient.refresh(
                refreshToken: refreshToken
            )
            try secrets.set(tokens.refreshToken, for: .cloudRefreshToken)
            cloudAccessToken = tokens.accessToken
            cloudSignedIn = true
            for registration in try RelayCloudDeviceVault.devices(in: secrets) {
                try await adminClient.registerCloudDevice(registration)
            }
            startCloudTunnel()
        } catch {
            try? secrets.remove(.cloudRefreshToken)
            cloudSignedIn = false
            cloudConnected = false
            lastError = "Relay Cloud needs you to sign in again."
        }
    }

    private func startCloudTunnel() {
        cloudTunnelTask?.cancel()
        guard
            let hostID = try? secrets.value(for: .cloudHostID),
            let credential = try? secrets.value(for: .cloudHostCredential),
            !hostID.isEmpty,
            !credential.isEmpty
        else {
            cloudConnected = false
            return
        }
        cloudTunnelTask = Task {
            var retrySeconds = 1
            while !Task.isCancelled {
                do {
                    let events = await cloudTunnel.events(
                        hostID: hostID,
                        credential: credential
                    )
                    let eventPump = Task { @MainActor in
                        while !Task.isCancelled {
                            do {
                                for envelope in try await adminClient.cloudEvents() {
                                    try await cloudTunnel.send(envelope)
                                }
                            } catch is CancellationError {
                                break
                            } catch {
                                try? await Task.sleep(for: .seconds(1))
                                continue
                            }
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                    }
                    defer { eventPump.cancel() }
                    for try await event in events {
                        try Task.checkCancellation()
                        switch event {
                        case .connected:
                            cloudConnected = true
                            retrySeconds = 1
                            diagnostic = "Relay Cloud is connected with end-to-end encryption."
                        case .pairingRequest(let request):
                            cloudPairingRequests[request.id] = request
                            pendingPairings = cloudPendingPairings
                            diagnostic = "A watch is waiting for fingerprint approval."
                        case .envelope(let envelope):
                            try await adminClient.processCloudEnvelope(envelope)
                        }
                    }
                } catch is CancellationError {
                    break
                } catch {
                    cloudConnected = false
                }
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(retrySeconds))
                retrySeconds = min(retrySeconds * 2, 30)
            }
            cloudConnected = false
        }
    }

    private func approveCloudPairing(
        _ request: RelayCloudPairingRequest
    ) async {
        guard
            let accessToken = cloudAccessToken,
            let session = cloudPairingSession,
            let hostID = try? secrets.value(for: .cloudHostID)
        else {
            lastError = "Start a new cloud pairing session."
            return
        }
        do {
            let prepared = try RelayCloudPairingMaterial.prepare(
                accountID: session.accountId,
                hostID: hostID,
                request: request,
                sessionNonce: session.sessionNonce,
                hostKeys: RelayCloudHostKeys.loadOrCreate(in: secrets)
            )
            let approved = try await cloudClient.approvePairing(
                accessToken: accessToken,
                pairingToken: session.token,
                requestID: request.id,
                deviceID: prepared.device.id,
                credentialHash: prepared.credentialHash,
                approvedPayload: prepared.payload
            )
            guard approved.id == prepared.device.id else {
                throw RelayCloudPairingMaterialError.invalidApproval
            }
            let registration = prepared.registration
            try RelayCloudDeviceVault.upsert(registration, in: secrets)
            try await adminClient.registerCloudDevice(registration)
            cloudPairingRequests.removeValue(forKey: request.id)
            cloudPairingSession = nil
            pendingPairings = cloudPendingPairings
            await refresh()
            diagnostic = "The watch is paired and its encrypted tunnel is active."
            lastError = nil
        } catch {
            lastError = "That cloud pairing request expired. Start pairing again."
        }
    }

    private func denyCloudPairing(_ requestID: String) async {
        guard
            let accessToken = cloudAccessToken,
            let session = cloudPairingSession
        else {
            lastError = "Start a new cloud pairing session."
            return
        }
        do {
            try await cloudClient.denyPairing(
                accessToken: accessToken,
                pairingToken: session.token,
                requestID: requestID
            )
            cloudPairingRequests.removeValue(forKey: requestID)
            cloudPairingSession = nil
            pendingPairings = cloudPendingPairings
            lastError = nil
        } catch {
            lastError = "That cloud pairing request is no longer available."
        }
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
