import CryptoKit
import Foundation

public enum RelayCloudCryptoError: Error, Equatable, Sendable {
    case invalidEnvelope
    case authenticationFailed
    case replay
}

public struct RelayTunnelRouting: Codable, Equatable, Sendable {
    public var version = 1
    public var messageID: String
    public var accountID: String
    public var hostID: String
    public var senderID: String
    public var recipientID: String
    public var sentAt: Int64
    public var sequence: Int64

    public init(
        messageID: String,
        accountID: String,
        hostID: String,
        senderID: String,
        recipientID: String,
        sentAt: Int64,
        sequence: Int64
    ) {
        self.messageID = messageID
        self.accountID = accountID
        self.hostID = hostID
        self.senderID = senderID
        self.recipientID = recipientID
        self.sentAt = sentAt
        self.sequence = sequence
    }

    enum CodingKeys: String, CodingKey {
        case version
        case messageID = "messageId"
        case accountID = "accountId"
        case hostID = "hostId"
        case senderID = "senderId"
        case recipientID = "recipientId"
        case sentAt
        case sequence
    }
}

public struct RelayTunnelEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var messageID: String
    public var accountID: String
    public var hostID: String
    public var senderID: String
    public var recipientID: String
    public var sentAt: Int64
    public var sequence: Int64
    public var nonce: String
    public var ciphertext: String

    public var routing: RelayTunnelRouting {
        RelayTunnelRouting(
            messageID: messageID,
            accountID: accountID,
            hostID: hostID,
            senderID: senderID,
            recipientID: recipientID,
            sentAt: sentAt,
            sequence: sequence
        )
    }

    enum CodingKeys: String, CodingKey {
        case version
        case messageID = "messageId"
        case accountID = "accountId"
        case hostID = "hostId"
        case senderID = "senderId"
        case recipientID = "recipientId"
        case sentAt
        case sequence
        case nonce
        case ciphertext
    }
}

public enum RelayCloudCrypto {
    public static func deriveRootKey(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: P256.KeyAgreement.PublicKey,
        pairingSessionNonce: Data
    ) throws -> SymmetricKey {
        guard pairingSessionNonce.count >= 16 else {
            throw RelayCloudCryptoError.invalidEnvelope
        }
        let secret = try privateKey.sharedSecretFromKeyAgreement(
            with: peerPublicKey
        )
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pairingSessionNonce,
            sharedInfo: Data("relay-e2ee-v1".utf8),
            outputByteCount: 32
        )
    }

    public static func encrypt(
        _ plaintext: Data,
        routing: RelayTunnelRouting,
        rootKey: SymmetricKey,
        nonce: Data
    ) throws -> RelayTunnelEnvelope {
        guard nonce.count == 12 else {
            throw RelayCloudCryptoError.invalidEnvelope
        }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: rootKey,
            nonce: try AES.GCM.Nonce(data: nonce),
            authenticating: canonicalAAD(routing)
        )
        return RelayTunnelEnvelope(
            version: routing.version,
            messageID: routing.messageID,
            accountID: routing.accountID,
            hostID: routing.hostID,
            senderID: routing.senderID,
            recipientID: routing.recipientID,
            sentAt: routing.sentAt,
            sequence: routing.sequence,
            nonce: base64URL(nonce),
            ciphertext: base64URL(sealed.ciphertext + sealed.tag)
        )
    }

    public static func decrypt(
        _ envelope: RelayTunnelEnvelope,
        rootKey: SymmetricKey
    ) throws -> Data {
        do {
            guard
                envelope.version == 1,
                envelope.sequence > 0,
                let nonce = Data(base64URL: envelope.nonce),
                let combined = Data(base64URL: envelope.ciphertext),
                combined.count >= 16
            else {
                throw RelayCloudCryptoError.invalidEnvelope
            }
            let ciphertext = combined.dropLast(16)
            let tag = combined.suffix(16)
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(
                box,
                using: rootKey,
                authenticating: canonicalAAD(envelope.routing)
            )
        } catch {
            throw RelayCloudCryptoError.authenticationFailed
        }
    }

    public static func canonicalAAD(_ routing: RelayTunnelRouting) -> Data {
        let json = """
        {"version":\(routing.version),"messageId":\(jsonString(routing.messageID)),"accountId":\(jsonString(routing.accountID)),"hostId":\(jsonString(routing.hostID)),"senderId":\(jsonString(routing.senderID)),"recipientId":\(jsonString(routing.recipientID)),"sentAt":\(routing.sentAt),"sequence":\(routing.sequence)}
        """
        return Data(json.utf8)
    }

    private static func jsonString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct RelayCloudReplayWindow: Equatable, Sendable {
    public private(set) var highestSequences: [String: Int64]

    public init(highestSequences: [String: Int64] = [:]) {
        self.highestSequences = highestSequences
    }

    public mutating func accept(senderID: String, sequence: Int64) throws {
        guard sequence > (highestSequences[senderID] ?? 0) else {
            throw RelayCloudCryptoError.replay
        }
        highestSequences[senderID] = sequence
    }
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
