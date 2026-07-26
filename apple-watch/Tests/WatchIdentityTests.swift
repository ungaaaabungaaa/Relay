import CryptoKit
import Foundation
import Testing
@testable import RelayWatchCore

@Test
func p256PublicKeyUsesSubjectPublicKeyInfoEncoding() throws {
    let rawPoint = Data([0x04] + Array(repeating: 0x11, count: 64))

    let encoded = try relaySubjectPublicKeyInfo(rawPoint)

    #expect(encoded.count == 91)
    #expect(
        encoded.prefix(26) == Data([
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00,
        ])
    )
    #expect(encoded.suffix(65) == rawPoint)
}

@Test
func p256PublicKeyRejectsMalformedRawPoint() {
    #expect(throws: RelayWatchIdentityError.publicKeyUnavailable) {
        try relaySubjectPublicKeyInfo(Data(repeating: 0x00, count: 65))
    }
}

@Test
func cloudCryptoMatchesP256PeersAndAuthenticatesRouting() throws {
    let watch = try P256.KeyAgreement.PrivateKey(
        rawRepresentation: Data(repeating: 0x11, count: 32)
    )
    let mac = try P256.KeyAgreement.PrivateKey(
        rawRepresentation: Data(repeating: 0x22, count: 32)
    )
    let nonce = Data(repeating: 0x33, count: 32)
    let watchRoot = try relayDeriveRootKey(
        privateKey: watch,
        peerPublicKey: mac.publicKey,
        pairingSessionNonce: nonce
    )
    let macRoot = try relayDeriveRootKey(
        privateKey: mac,
        peerPublicKey: watch.publicKey,
        pairingSessionNonce: nonce
    )
    #expect(watchRoot.withUnsafeBytes { Data($0) } == macRoot.withUnsafeBytes { Data($0) })

    let routing = RelayTunnelRouting(
        messageID: "message-1",
        accountID: "account-1",
        hostID: "host-1",
        senderID: "watch-1",
        recipientID: "host-1",
        sentAt: 1_000,
        sequence: 1
    )
    let envelope = try relayEncrypt(
        Data("opaque".utf8),
        routing: routing,
        rootKey: watchRoot,
        nonce: Data(repeating: 0x44, count: 12)
    )
    #expect(try relayDecrypt(envelope, rootKey: macRoot) == Data("opaque".utf8))

    var modified = envelope
    modified.recipientID = "other-host"
    #expect(throws: RelayCloudCryptoError.authenticationFailed) {
        try relayDecrypt(modified, rootKey: macRoot)
    }
}

@Test
func cloudPairingPayloadOpensOnlyForTheExpectedRequestAndHost() throws {
    let rootKey = SymmetricKey(data: Data(repeating: 0x55, count: 32))
    let credential = RelayCloudPairingCredential(
        accountId: "account-1",
        hostId: "host-1",
        deviceId: "watch-1",
        credential: "scoped-device-token",
        apiVersion: 1,
        minimumApiVersion: 1,
        maximumApiVersion: 1
    )
    let nonce = Data(repeating: 0x66, count: 12)
    let aad = Data(
        #"{"version":1,"requestId":"request-1","hostId":"host-1"}"#.utf8
    )
    let sealed = try AES.GCM.seal(
        JSONEncoder().encode(credential),
        using: rootKey,
        nonce: try AES.GCM.Nonce(data: nonce),
        authenticating: aad
    )
    let payload = RelayCloudPairingPayloadEnvelope(
        version: 1,
        nonce: nonce.relayBase64URL,
        ciphertext: (sealed.ciphertext + sealed.tag).relayBase64URL
    )

    #expect(
        try relayOpenPairingPayload(
            payload,
            requestID: "request-1",
            hostID: "host-1",
            rootKey: rootKey
        ) == credential
    )
    #expect(throws: RelayCloudCryptoError.authenticationFailed) {
        try relayOpenPairingPayload(
            payload,
            requestID: "other-request",
            hostID: "host-1",
            rootKey: rootKey
        )
    }
}

@Test
func watchMetadataUsesWatchOSAndRoundedRectangle() throws {
    let data = try JSONEncoder().encode(
        RelayDeviceMetadata(
            model: "Apple Watch",
            osVersion: "10",
            appVersion: "0.2.0"
        )
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: String]
    )

    #expect(object["platform"] == "watch-os")
    #expect(object["manufacturer"] == "Apple")
    #expect(object["model"] == "Apple Watch")
    #expect(object["screenShape"] == "rounded-rect")
}

@Test
func pairingCompletionOpensTheSharedEncryptedFixture() throws {
    let payload = RelayCloudPairingPayloadEnvelope(
        version: 1,
        nonce: "BwcHBwcHBwcHBwcH",
        ciphertext: "Ipns_AseincDozOvrOAShV5XcyT0IcNnsqx5_4ACyn1hheZdO2yVENqvqHewusDboJLNJrXksCO4QF2L4ULZIrO0xtPQeZir4ejLnlNgyks06MUKP96sllHjC0kg-fTFUR69DnmQGHBd2uOniuIBj7C4Tu6AvsVnfqTYcO6xXJx855wfqzOAhKkTq1GUsQywQ5spui_x5IOsMHC3maU24urmS2n5eMw"
    )
    let credential = try relayOpenPairingPayload(
        payload,
        requestID: "request-1",
        hostID: "host-1",
        rootKey: SymmetricKey(data: Data(repeating: 9, count: 32))
    )

    #expect(credential.deviceId == "watch-1")
    #expect(credential.credential == "watch-secret")
}

@Test
func cloudReplayWindowRejectsSequencesAcrossRestarts() throws {
    var restored = RelayCloudReplayWindow(
        highestSequences: ["host-1": 7]
    )
    #expect(throws: RelayCloudCryptoError.replay) {
        try restored.accept(senderID: "host-1", sequence: 7)
    }
    try restored.accept(senderID: "host-1", sequence: 8)
    #expect(restored.highestSequences["host-1"] == 8)
}
