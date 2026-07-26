import Combine
import Foundation
import WatchKit

@MainActor
final class RelayWatchModel: ObservableObject {
    @Published var connection: RelayConnectionState = .unpaired
    @Published var screen: RelayWatchScreen = .onboarding
    @Published var pairingCode = ""
    @Published var discoveredMac: RelayMacIdentity?
    @Published var error: String?
    @Published var cachedTaskCount = 0
    @Published var cachedInboxCount = 0
    @Published var cacheIsStale = true

    private let identity = RelayWatchIdentity()
    private let agreementIdentity = RelayWatchAgreementIdentity()
    private let deviceStore = RelayWatchCloudStore()
    private lazy var api = RelayAPIClient(
        identity: identity,
        agreementIdentity: agreementIdentity,
        deviceStore: deviceStore
    )
    private var pairingTask: Task<Void, Never>?

    init() {
        if deviceStore.load() != nil {
            connection = .offline
            screen = .inbox
            Task { await refresh() }
        }
    }

    var watchFingerprint: String {
        (try? identity.fingerprint()) ?? "Unavailable"
    }

    var actionsEnabled: Bool {
        connection == .live && !cacheIsStale
    }

    func beginPairing() {
        screen = .pairing
    }

    func confirmMac() {
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
                let prepared = try await api.submit(
                    code: code,
                    metadata: metadata
                )
                discoveredMac = RelayMacIdentity(
                    macName: "Relay Mac",
                    macFingerprint: prepared.pending.macFingerprint
                )
                while !Task.isCancelled,
                      Int64(Date().timeIntervalSince1970 * 1_000)
                        <= prepared.pending.expiresAt {
                    switch try await api.poll(prepared) {
                    case .pending:
                        try await Task.sleep(for: .seconds(2))
                    case .denied:
                        throw RelayWatchModelError.denied
                    case .approved:
                        connection = .offline
                        screen = .inbox
                        await refresh()
                        return
                    }
                }
                throw RelayWatchModelError.expired
            } catch is CancellationError {
                connection = .unpaired
            } catch RelayAPIError.incompatible {
                connection = .incompatible
                error = "Update Relay on the Mac and watch."
            } catch {
                connection = .unpaired
                self.error = "Pairing was denied, expired, or rate limited."
            }
        }
    }

    func refresh() async {
        guard deviceStore.load() != nil else {
            connection = .unpaired
            cacheIsStale = true
            return
        }
        do {
            let inboxResponse = try await api.request(path: "/v1/inbox")
            let tasksResponse = try await api.request(path: "/v1/tasks")
            guard
                (200..<300).contains(inboxResponse.status),
                (200..<300).contains(tasksResponse.status)
            else {
                throw RelayWatchModelError.rejected
            }
            let inbox = try JSONSerialization.jsonObject(with: inboxResponse.body)
                as? [String: Any]
            let tasks = try JSONSerialization.jsonObject(with: tasksResponse.body)
                as? [String: Any]
            cachedInboxCount =
                ((inbox?["approvals"] as? [Any])?.count ?? 0)
                + ((inbox?["questions"] as? [Any])?.count ?? 0)
            cachedTaskCount = (tasks?["data"] as? [Any])?.count ?? 0
            connection = .live
            cacheIsStale = false
            error = nil
        } catch RelayAPIError.revoked {
            revokeLocally()
        } catch {
            connection = .offline
            cacheIsStale = true
        }
    }

    func show(_ destination: RelayWatchScreen) {
        screen = destination
    }

    func revokeLocally() {
        pairingTask?.cancel()
        Task { await api.close() }
        deviceStore.delete()
        agreementIdentity.delete()
        identity.delete()
        discoveredMac = nil
        pairingCode = ""
        cachedInboxCount = 0
        cachedTaskCount = 0
        cacheIsStale = true
        connection = .revoked
        screen = .revoked
    }

    func pairAgain() {
        connection = .unpaired
        screen = .onboarding
        error = nil
    }
}

enum RelayWatchModelError: Error {
    case denied, expired, incompatible, rejected
}
