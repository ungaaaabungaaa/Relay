import CryptoKit
import Foundation
import Testing
@testable import RelayWatchCore

@Test
func pairingPollsOnlyAfterWatchConfirmationAndThenStoresApproval() async throws {
    let service = PairingServiceFake(result: .approved(pairingConfig))
    let state = RelayPairingState(service: service, now: { 1_000 })
    try await state.submit(code: "ABC123", metadata: pairingMetadata)

    await #expect(throws: RelayPairingStateError.confirmationRequired) {
        try await state.pollOnce()
    }
    #expect(await service.pollCount == 0)
    #expect(await service.approvalDeliveryCount == 0)

    try await state.confirmMacFingerprint(watchFingerprint: "watch:fingerprint")
    _ = try await state.pollOnce()
    #expect(await service.pollCount == 1)
    #expect(await service.approvalDeliveryCount == 1)
    #expect(await state.phase == .paired)
}

@Test
func pairingCancelExpiryDenialAndMismatchDiscardPreparedMaterial() async throws {
    let cancelledService = PairingServiceFake(result: .pending)
    let cancelled = RelayPairingState(service: cancelledService, now: { 1_000 })
    try await cancelled.submit(code: "ABC123", metadata: pairingMetadata)
    await cancelled.cancel()
    await #expect(throws: RelayPairingStateError.confirmationRequired) {
        try await cancelled.pollOnce()
    }

    let expiredService = PairingServiceFake(result: .pending, expiresAt: 900)
    let expired = RelayPairingState(service: expiredService, now: { 1_000 })
    await #expect(throws: RelayPairingStateError.expired) {
        try await expired.submit(code: "ABC123", metadata: pairingMetadata)
    }
    #expect(await expired.phase == .failed(.offline))

    let deniedService = PairingServiceFake(result: .denied)
    let denied = RelayPairingState(service: deniedService, now: { 1_000 })
    try await denied.submit(code: "ABC123", metadata: pairingMetadata)
    try await denied.confirmMacFingerprint(watchFingerprint: "watch:fingerprint")
    await #expect(throws: RelayPairingStateError.denied) { try await denied.pollOnce() }
    await #expect(throws: RelayPairingStateError.confirmationRequired) {
        try await denied.pollOnce()
    }

    let mismatchService = PairingServiceFake(result: .failure(.incompatible))
    let mismatch = RelayPairingState(service: mismatchService, now: { 1_000 })
    try await mismatch.submit(code: "ABC123", metadata: pairingMetadata)
    try await mismatch.confirmMacFingerprint(watchFingerprint: "watch:fingerprint")
    await #expect(throws: RelayAPIError.incompatible) { try await mismatch.pollOnce() }
    #expect(await mismatch.phase == .failed(.incompatible))
}

private let pairingMetadata = RelayDeviceMetadata(
    model: "Apple Watch",
    osVersion: "10",
    appVersion: "0.2.0"
)

private let pairingConfig = RelayCloudDeviceConfig(
    accountId: "account-1",
    hostId: "host-1",
    deviceId: "watch-1",
    credential: "credential",
    rootKey: Data(repeating: 1, count: 32),
    apiVersion: 1
)

private actor PairingServiceFake: RelayPairingServicing {
    enum Result {
        case pending
        case denied
        case approved(RelayCloudDeviceConfig)
        case failure(RelayAPIError)
    }

    private let result: Result
    private let expiresAt: Int64
    private(set) var pollCount = 0
    private(set) var approvalDeliveryCount = 0

    init(result: Result, expiresAt: Int64 = 10_000) {
        self.result = result
        self.expiresAt = expiresAt
    }

    func submit(code: String, metadata: RelayDeviceMetadata) async throws -> RelayCloudPreparedPairing {
        RelayCloudPreparedPairing(
            pending: RelayCloudPendingPairing(
                id: "pair-1",
                pollToken: "poll-token",
                accountId: "account-1",
                hostId: "host-1",
                sessionNonce: Data(repeating: 2, count: 16).relayBase64URL,
                macFingerprint: "mac:fingerprint",
                macAgreementPublicKey: "public-key",
                expiresAt: expiresAt
            ),
            rootKey: SymmetricKey(data: Data(repeating: 1, count: 32))
        )
    }

    func poll(_ prepared: RelayCloudPreparedPairing) async throws -> RelayCloudPairingResult {
        pollCount += 1
        switch result {
        case .pending:
            return .pending
        case .denied:
            return .denied
        case let .approved(config):
            approvalDeliveryCount += 1
            return .approved(config)
        case let .failure(error):
            throw error
        }
    }
}
