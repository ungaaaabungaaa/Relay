import Combine
import Foundation
import WatchKit

@MainActor
final class RelayWatchModel: ObservableObject {
    @Published var connection: RelayConnectionState = .unpaired
    @Published var screen: RelayWatchScreen = .onboarding
    @Published var pairingCode = ""
    @Published var pairingPhase: RelayPairingPhase = .codeEntry
    @Published var discoveredMac: RelayMacIdentity?
    @Published var error: String?
    @Published var inbox = RelayInbox(approvals: [], questions: [])
    @Published var tasks: [RelayTask] = []
    @Published var taskDetails: [String: RelayTaskDetail] = [:]
    @Published var models: [RelayModel] = []
    @Published var folders: [RelayFolder] = []
    @Published var mutationAttempts: [RelayMutationAttempt] = []
    @Published var cacheIsStale = true
    @Published var selectedApprovalID: String?
    @Published var selectedQuestionID: String?
    @Published var selectedTaskID: String?

    private let identity = RelayWatchIdentity()
    private let agreementIdentity = RelayWatchAgreementIdentity()
    private let deviceStore = RelayWatchCloudStore()
    private lazy var api = RelayAPIClient(
        identity: identity,
        agreementIdentity: agreementIdentity,
        deviceStore: deviceStore
    )
    private lazy var pairing = RelayPairingState(service: api)
    private lazy var feature = RelayWatchFeature(service: RelayWatchService(api: api))
    private var pairingTask: Task<Void, Never>?
    private var transportTask: Task<Void, Never>?

    init() {
        if deviceStore.load() != nil {
            connection = .offline
            screen = .inbox
            Task { try? await startRemoteSession() }
        }
    }

    var cachedTaskCount: Int { tasks.count }
    var cachedInboxCount: Int { inbox.approvals.count + inbox.questions.count }
    var watchFingerprint: String { (try? identity.fingerprint()) ?? "Unavailable" }
    var actionsEnabled: Bool { connection == .live && !cacheIsStale }
    var mutationPending: Bool { mutationAttempts.contains { $0.status == .pending } }
    var selectedApproval: RelayApproval? {
        inbox.approvals.first { $0.id == selectedApprovalID }
    }
    var selectedQuestion: RelayQuestion? {
        inbox.questions.first { $0.id == selectedQuestionID }
    }
    var selectedTask: RelayTask? {
        tasks.first { $0.id == selectedTaskID }
    }
    var selectedTaskDetail: RelayTaskDetail? {
        selectedTaskID.flatMap { taskDetails[$0] }
    }

    func beginPairing() {
        pairingPhase = .codeEntry
        screen = .pairing
    }

    func pair() {
        let code = pairingCode.uppercased()
        guard code.range(of: #"^[A-Z0-9]{6}$"#, options: .regularExpression) != nil else {
            error = "Enter the six-character code shown on the Mac."
            return
        }
        pairingTask?.cancel()
        discoveredMac = nil
        error = nil
        connection = .pairing
        pairingPhase = .submitting
        pairingTask = Task {
            do {
                let device = WKInterfaceDevice.current()
                let metadata = RelayDeviceMetadata(
                    model: device.model,
                    osVersion: device.systemVersion,
                    appVersion: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "0"
                )
                try await pairing.submit(code: code, metadata: metadata)
                await syncPairing()
            } catch is CancellationError {
                await pairing.cancel()
                connection = .unpaired
                await syncPairing()
            } catch {
                connection = .unpaired
                self.error = "Pairing could not be started. Check the code and try again."
                await syncPairing()
            }
        }
    }

    func confirmMac() {
        pairingTask?.cancel()
        pairingTask = Task {
            do {
                try await pairing.confirmMacFingerprint(watchFingerprint: watchFingerprint)
                await syncPairing()
                while !Task.isCancelled {
                    switch try await pairing.pollOnce() {
                    case .pending:
                        try await Task.sleep(for: .seconds(2))
                    case .denied:
                        throw RelayPairingStateError.denied
                    case .approved:
                        pairingPhase = .paired
                        connection = .offline
                        screen = .inbox
                        try await startRemoteSession()
                        return
                    }
                }
            } catch is CancellationError {
                await pairing.cancel()
                connection = .unpaired
                await syncPairing()
            } catch RelayAPIError.incompatible {
                connection = .incompatible
                error = "Update Relay on the Mac and watch."
                await syncPairing()
            } catch {
                connection = .unpaired
                self.error = "Pairing was denied, expired, or unavailable."
                await syncPairing()
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        Task {
            await pairing.cancel()
            await syncPairing()
        }
        connection = .unpaired
        discoveredMac = nil
        screen = .onboarding
    }

    func refresh() async {
        guard deviceStore.load() != nil else {
            connection = .unpaired
            cacheIsStale = true
            return
        }
        do {
            try await feature.refresh()
            await syncFeature()
        } catch {
            connection = .offline
            cacheIsStale = true
        }
    }

    func loadTask(_ id: String) async {
        do {
            try await feature.loadTask(id)
            await syncFeature()
        } catch {
            self.error = "Task details are unavailable."
        }
    }

    func loadCreationOptions() async {
        do {
            try await feature.loadCreationOptions()
            await syncFeature()
        } catch {
            self.error = "Workspaces and models are unavailable."
        }
    }

    func approve(_ id: String, dangerousConfirmation: Bool) async throws {
        try await feature.approve(id, dangerousConfirmation: dangerousConfirmation)
        await syncFeature()
    }

    func deny(_ id: String) async throws {
        try await feature.deny(id)
        await syncFeature()
    }

    func answer(_ id: String, answers: [String: [String]]) async throws {
        try await feature.answer(id, answers: answers)
        await syncFeature()
    }

    func sendText(taskID: String, text: String) async throws {
        try await feature.sendText(taskID: taskID, text: text)
        await syncFeature()
    }

    func stop(_ taskID: String) async throws {
        try await feature.stop(taskID)
        await syncFeature()
    }

    func startTask(cwd: String, modelID: String, effort: String, prompt: String) async throws {
        try await feature.startTask(cwd: cwd, modelID: modelID, effort: effort, prompt: prompt)
        await syncFeature()
    }

    func show(_ destination: RelayWatchScreen) { screen = destination }

    func showApproval(_ id: String) {
        selectedApprovalID = id
        screen = .approval
    }

    func showQuestion(_ id: String) {
        selectedQuestionID = id
        screen = .question
    }

    func showTask(_ id: String, destination: RelayWatchScreen = .activity) {
        selectedTaskID = id
        screen = destination
        Task { await loadTask(id) }
    }

    func reportActionFailure(_ error: Error) {
        self.error = error is RelayUserError
            ? "That action is unavailable. Refresh and try again."
            : "The Mac did not complete that action. Try again."
        WKInterfaceDevice.current().play(.failure)
    }

    func reportActionSuccess() {
        error = nil
        WKInterfaceDevice.current().play(.success)
    }

    func revokeLocally() {
        pairingTask?.cancel()
        transportTask?.cancel()
        Task { await api.eraseSession() }
        discoveredMac = nil
        pairingCode = ""
        inbox = RelayInbox(approvals: [], questions: [])
        tasks = []
        taskDetails = [:]
        cacheIsStale = true
        connection = .revoked
        screen = .revoked
    }

    func pairAgain() {
        connection = .unpaired
        pairingPhase = .codeEntry
        screen = .onboarding
        error = nil
    }

    private func startRemoteSession() async throws {
        let stream = await api.start()
        transportTask?.cancel()
        transportTask = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await self.feature.handle(event)
                await self.syncFeature()
            }
        }
    }

    private func syncPairing() async {
        pairingPhase = await pairing.phase
        if case let .confirmMac(name, fingerprint, _) = pairingPhase {
            discoveredMac = RelayMacIdentity(macName: name, macFingerprint: fingerprint)
        }
    }

    private func syncFeature() async {
        let state = await feature.state
        connection = state.connection
        cacheIsStale = state.cacheIsStale
        inbox = state.inbox
        tasks = state.tasks
        taskDetails = state.taskDetails
        models = state.models
        folders = state.folders
        mutationAttempts = state.attempts
    }
}
