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
    private lazy var api = RelayAPIClient(identity: identity)
    private let discovery = RelayPairingDiscovery()
    private let preferences = UserDefaults.standard
    private var pairingRecord: RelayPairingRecord?
    private var pairingTask: Task<Void, Never>?

    init() {
        discovery.onRecord = { [weak self] record in
            Task { @MainActor in
                await self?.accept(record)
            }
        }
        discovery.onFailure = { [weak self] in
            Task { @MainActor in
                self?.error = "Keep the Mac and watch on the same Wi-Fi."
            }
        }
        if deviceID != nil, origin != nil {
            connection = .offline
            screen = .inbox
            Task { await refresh() }
        } else {
            discovery.start()
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
        discovery.start()
    }

    func confirmMac() {
        screen = .pairing
    }

    func pair() {
        guard let pairingRecord, pairingCode.count == 6 else {
            error = "Enter the six-character code shown on the Mac."
            return
        }
        pairingTask?.cancel()
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
                let pending = try await api.submit(
                    pairingRecord,
                    code: pairingCode,
                    metadata: metadata
                )
                while !Task.isCancelled,
                      Int64(Date().timeIntervalSince1970 * 1_000) <= pending.expiresAt {
                    let status = try await api.poll(
                        pairingRecord,
                        token: pending.pollToken
                    )
                    switch status.state {
                    case "pending":
                        try await Task.sleep(for: .seconds(2))
                    case "denied":
                        throw RelayWatchModelError.denied
                    case "approved":
                        guard
                            status.apiVersion == 1,
                            let deviceID = status.deviceId,
                            let origin = status.origin
                        else {
                            throw RelayWatchModelError.incompatible
                        }
                        preferences.set(deviceID, forKey: "device-id")
                        preferences.set(origin.absoluteString, forKey: "origin")
                        discovery.stop()
                        connection = .offline
                        screen = .inbox
                        await refresh()
                        return
                    default:
                        throw RelayWatchModelError.incompatible
                    }
                }
                throw RelayWatchModelError.expired
            } catch is CancellationError {
                connection = .unpaired
            } catch RelayWatchModelError.incompatible {
                connection = .incompatible
                error = "Update Relay on the Mac and watch."
            } catch {
                connection = .unpaired
                self.error = "Pairing was denied or expired."
            }
        }
    }

    func refresh() async {
        guard let origin, let deviceID else {
            connection = .unpaired
            cacheIsStale = true
            return
        }
        do {
            async let inboxData = api.request(
                origin: origin,
                deviceID: deviceID,
                path: "/v1/inbox"
            )
            async let tasksData = api.request(
                origin: origin,
                deviceID: deviceID,
                path: "/v1/tasks"
            )
            let (inboxResponse, tasksResponse) = try await (inboxData, tasksData)
            let inbox = try JSONSerialization.jsonObject(with: inboxResponse)
                as? [String: Any]
            let tasks = try JSONSerialization.jsonObject(with: tasksResponse)
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
        preferences.removeObject(forKey: "device-id")
        preferences.removeObject(forKey: "origin")
        preferences.removeObject(forKey: "cached-response")
        identity.delete()
        discoveredMac = nil
        pairingRecord = nil
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
        discovery.start()
    }

    private var deviceID: String? {
        preferences.string(forKey: "device-id")
    }

    private var origin: URL? {
        preferences.string(forKey: "origin").flatMap(URL.init(string:))
    }

    private func accept(_ record: RelayPairingRecord) async {
        guard pairingRecord == nil else {
            return
        }
        do {
            let mac = try await api.discover(record)
            guard mac.apiVersion == 1 else {
                throw RelayWatchModelError.incompatible
            }
            pairingRecord = record
            discoveredMac = mac
            discovery.stop()
            screen = .pairing
        } catch {
            self.error = "The pairing session is no longer available."
        }
    }
}

enum RelayWatchModelError: Error {
    case denied
    case expired
    case incompatible
}
