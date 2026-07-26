import CryptoKit
import Foundation
import Testing
@testable import RelayCore

@Test
func cloudCryptoDerivesMatchingPerWatchRootKeys() throws {
    let mac = P256.KeyAgreement.PrivateKey()
    let watch = P256.KeyAgreement.PrivateKey()
    let nonce = Data(repeating: 7, count: 32)

    let macRoot = try RelayCloudCrypto.deriveRootKey(
        privateKey: mac,
        peerPublicKey: watch.publicKey,
        pairingSessionNonce: nonce
    )
    let watchRoot = try RelayCloudCrypto.deriveRootKey(
        privateKey: watch,
        peerPublicKey: mac.publicKey,
        pairingSessionNonce: nonce
    )
    #expect(
        macRoot.withUnsafeBytes { Array($0) }
            == watchRoot.withUnsafeBytes { Array($0) }
    )
}

@Test
func cloudCryptoAuthenticatesEveryRoutingField() throws {
    let root = SymmetricKey(data: Data(repeating: 4, count: 32))
    let routing = RelayTunnelRouting(
        messageID: "message-1",
        accountID: "account-1",
        hostID: "host-1",
        senderID: "watch-1",
        recipientID: "host-1",
        sentAt: 1_000,
        sequence: 1
    )
    let envelope = try RelayCloudCrypto.encrypt(
        Data(#"{"kind":"request"}"#.utf8),
        routing: routing,
        rootKey: root,
        nonce: Data(repeating: 2, count: 12)
    )
    #expect(
        try RelayCloudCrypto.decrypt(envelope, rootKey: root)
            == Data(#"{"kind":"request"}"#.utf8)
    )

    var modified = envelope
    modified.recipientID = "attacker"
    #expect(throws: RelayCloudCryptoError.authenticationFailed) {
        try RelayCloudCrypto.decrypt(modified, rootKey: root)
    }
}

@Test
func cloudReplayWindowRestoresTheLastSequence() throws {
    var first = RelayCloudReplayWindow(highestSequences: ["watch-1": 8])
    try first.accept(senderID: "watch-1", sequence: 9)
    var restored = RelayCloudReplayWindow(highestSequences: first.highestSequences)

    #expect(throws: RelayCloudCryptoError.replay) {
        try restored.accept(senderID: "watch-1", sequence: 9)
    }
}

@Test
func approvedCloudPairingEncryptsWatchCredentialForWatchOnly() throws {
    let host = RelayCloudHostKeys(
        signingPrivateKey: P256.Signing.PrivateKey(),
        agreementPrivateKey: P256.KeyAgreement.PrivateKey()
    )
    let watchAgreement = P256.KeyAgreement.PrivateKey()
    let nonce = Data(repeating: 6, count: 32)
    let request = RelayCloudPairingRequest(
        id: "request-1",
        fingerprint: "WATCH FP",
        signingPublicKey: "watch-signing-pem",
        agreementPublicKey: watchAgreement.publicKey.x963Representation
            .base64EncodedString(),
        expiresAt: 120_000,
        metadata: RelayCloudDeviceMetadata(
            platform: "watch-os",
            manufacturer: "Apple",
            model: "Apple Watch",
            osVersion: "10",
            appVersion: "0.2.0",
            screenShape: "rounded-rect"
        )
    )
    let prepared = try RelayCloudPairingMaterial.prepare(
        accountID: "account-1",
        hostID: "host-1",
        request: request,
        sessionNonce: nonce.base64EncodedString(),
        hostKeys: host
    )
    let expected = try RelayCloudCrypto.deriveRootKey(
        privateKey: watchAgreement,
        peerPublicKey: host.agreementPrivateKey.publicKey,
        pairingSessionNonce: nonce
    )
    let expectedData = expected.withUnsafeBytes { Data($0) }

    let credential = try RelayCloudPairingMaterial.open(
        prepared.payload,
        requestID: request.id,
        hostID: "host-1",
        rootKey: expected
    )

    #expect(prepared.registration.deviceId == prepared.device.id)
    #expect(prepared.registration.accountId == "account-1")
    #expect(prepared.registration.signingPublicKey == "watch-signing-pem")
    #expect(Data(base64URL: prepared.registration.rootKey) == expectedData)
    #expect(credential.accountId == "account-1")
    #expect(credential.hostId == "host-1")
    #expect(credential.deviceId == prepared.device.id)
    #expect(credential.credential == prepared.rawCredential)
    #expect(credential.apiVersion == 1)
    #expect(prepared.credentialHash != prepared.rawCredential)
    #expect(!prepared.payload.ciphertext.contains(prepared.rawCredential))
}

@Test
func pairingCompletionOpensTheSharedCrossPlatformVector() throws {
    let credential = try RelayCloudPairingMaterial.open(
        RelayCloudPairingPayloadEnvelope(
            version: 1,
            nonce: "BwcHBwcHBwcHBwcH",
            ciphertext: "Ipns_AseincDozOvrOAShV5XcyT0IcNnsqx5_4ACyn1hheZdO2yVENqvqHewusDboJLNJrXksCO4QF2L4ULZIrO0xtPQeZir4ejLnlNgyks06MUKP96sllHjC0kg-fTFUR69DnmQGHBd2uOniuIBj7C4Tu6AvsVnfqTYcO6xXJx855wfqzOAhKkTq1GUsQywQ5spui_x5IOsMHC3maU24urmS2n5eMw"
        ),
        requestID: "request-1",
        hostID: "host-1",
        rootKey: SymmetricKey(data: Data(repeating: 9, count: 32))
    )

    #expect(credential.deviceId == "watch-1")
    #expect(credential.credential == "watch-secret")
}

private extension Data {
    init?(base64URL: String) {
        var value = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}
