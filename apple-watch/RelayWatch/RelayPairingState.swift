import Foundation

enum RelayPairingPhase: Equatable, Sendable {
    case codeEntry
    case submitting
    case confirmMac(name: String, fingerprint: String, expiresAt: Int64)
    case awaitingMacApproval(watchFingerprint: String)
    case paired
    case failed(RelayFailureCategory)
}

enum RelayPairingStateError: Error, Equatable, Sendable {
    case confirmationRequired
    case expired
    case denied
}

actor RelayPairingState {
    private let service: any RelayPairingServicing
    private let now: @Sendable () -> Int64
    private var prepared: RelayCloudPreparedPairing?
    private(set) var phase: RelayPairingPhase = .codeEntry

    init(
        service: any RelayPairingServicing,
        now: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.service = service
        self.now = now
    }

    func submit(code: String, metadata: RelayDeviceMetadata) async throws {
        prepared = nil
        phase = .submitting
        do {
            let prepared = try await service.submit(code: code, metadata: metadata)
            guard prepared.pending.expiresAt > now() else {
                clear(.failed(.offline))
                throw RelayPairingStateError.expired
            }
            self.prepared = prepared
            phase = .confirmMac(
                name: "Relay Mac",
                fingerprint: prepared.pending.macFingerprint,
                expiresAt: prepared.pending.expiresAt
            )
        } catch {
            if error is RelayPairingStateError { throw error }
            if prepared == nil { phase = .failed(failureCategory(error)) }
            throw error
        }
    }

    func confirmMacFingerprint(watchFingerprint: String) throws {
        guard
            case .confirmMac = phase,
            prepared != nil,
            !watchFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            watchFingerprint != "Unavailable"
        else {
            throw RelayPairingStateError.confirmationRequired
        }
        phase = .awaitingMacApproval(watchFingerprint: watchFingerprint)
    }

    func pollOnce() async throws -> RelayCloudPairingResult {
        guard
            case .awaitingMacApproval = phase,
            let prepared
        else {
            throw RelayPairingStateError.confirmationRequired
        }
        guard prepared.pending.expiresAt > now() else {
            clear(.failed(.offline))
            throw RelayPairingStateError.expired
        }
        do {
            let result = try await service.poll(prepared)
            switch result {
            case .pending:
                break
            case .denied:
                clear(.failed(.rejected))
                throw RelayPairingStateError.denied
            case .approved:
                self.prepared = nil
                phase = .paired
            }
            return result
        } catch {
            if error is RelayPairingStateError { throw error }
            clear(.failed(failureCategory(error)))
            throw error
        }
    }

    func cancel() {
        clear(.codeEntry)
    }

    private func clear(_ phase: RelayPairingPhase) {
        prepared = nil
        self.phase = phase
    }

    private func failureCategory(_ error: Error) -> RelayFailureCategory {
        switch error as? RelayAPIError {
        case .invalidEnvelope, .invalidResponse:
            return .invalidEnvelope
        case .incompatible:
            return .incompatible
        case .revoked:
            return .revoked
        case .offline:
            return .offline
        default:
            return .network
        }
    }
}
