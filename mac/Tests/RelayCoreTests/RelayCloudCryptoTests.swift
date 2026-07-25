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
