import CryptoKit
import Foundation

let relayCloudAPIOrigin = URL(string: "https://api.relayforcodex.com")!
let relayVoiceChunkBytes = 128 * 1024
let relayVoiceMaximumBytes = 2 * 1024 * 1024
let relayVoiceMaximumDurationMs = 30_000
let relayVoiceMaximumChunks = 16

enum RelayConnectionState: Equatable, Sendable {
    case unpaired, pairing, live, offline, revoked, incompatible
}

struct RelayMacIdentity: Equatable {
    let macName: String
    let macFingerprint: String
}

struct RelayCloudPendingPairing: Decodable, Sendable {
    let id: String
    let pollToken: String
    let accountId: String
    let hostId: String
    let sessionNonce: String
    let macFingerprint: String
    let macAgreementPublicKey: String
    let expiresAt: Int64
}

struct RelayCloudPairingPayloadEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let nonce: String
    let ciphertext: String
}

struct RelayCloudPairingStatus: Decodable, Sendable {
    let status: String
    let payload: RelayCloudPairingPayloadEnvelope?
}

struct RelayCloudPairingCredential: Codable, Equatable, Sendable {
    let accountId: String
    let hostId: String
    let deviceId: String
    let credential: String
    let apiVersion: Int
    let minimumApiVersion: Int
    let maximumApiVersion: Int
}

struct RelayCloudDeviceConfig: Codable, Equatable, Sendable {
    let accountId: String
    let hostId: String
    let deviceId: String
    let credential: String
    let rootKey: Data
    let apiVersion: Int
}

struct RelayDeviceMetadata: Encodable, Sendable {
    let platform = "watch-os"
    let manufacturer = "Apple"
    let model: String
    let osVersion: String
    let appVersion: String
    let screenShape = "rounded-rect"
}

struct RelayTunnelRouting: Codable, Equatable, Sendable {
    var version = 1
    var messageID: String
    var accountID: String
    var hostID: String
    var senderID: String
    var recipientID: String
    var sentAt: Int64
    var sequence: Int64

    enum CodingKeys: String, CodingKey {
        case version
        case messageID = "messageId"
        case accountID = "accountId"
        case hostID = "hostId"
        case senderID = "senderId"
        case recipientID = "recipientId"
        case sentAt, sequence
    }
}

struct RelayTunnelEnvelope: Codable, Equatable, Sendable {
    var version: Int
    var messageID: String
    var accountID: String
    var hostID: String
    var senderID: String
    var recipientID: String
    var sentAt: Int64
    var sequence: Int64
    var nonce: String
    var ciphertext: String

    var routing: RelayTunnelRouting {
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
        case sentAt, sequence, nonce, ciphertext
    }
}

enum RelayCloudCryptoError: Error, Equatable {
    case invalidEnvelope, authenticationFailed, replay
}

func relayDeriveRootKey(
    privateKey: P256.KeyAgreement.PrivateKey,
    peerPublicKey: P256.KeyAgreement.PublicKey,
    pairingSessionNonce: Data
) throws -> SymmetricKey {
    guard pairingSessionNonce.count >= 16 else {
        throw RelayCloudCryptoError.invalidEnvelope
    }
    let secret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
    return secret.hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: pairingSessionNonce,
        sharedInfo: Data("relay-e2ee-v1".utf8),
        outputByteCount: 32
    )
}

func relayEncrypt(
    _ plaintext: Data,
    routing: RelayTunnelRouting,
    rootKey: SymmetricKey,
    nonce: Data
) throws -> RelayTunnelEnvelope {
    guard routing.version == 1, routing.sequence > 0, nonce.count == 12 else {
        throw RelayCloudCryptoError.invalidEnvelope
    }
    let sealed = try AES.GCM.seal(
        plaintext,
        using: rootKey,
        nonce: try AES.GCM.Nonce(data: nonce),
        authenticating: relayCanonicalAAD(routing)
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
        nonce: nonce.relayBase64URL,
        ciphertext: (sealed.ciphertext + sealed.tag).relayBase64URL
    )
}

func relayDecrypt(
    _ envelope: RelayTunnelEnvelope,
    rootKey: SymmetricKey
) throws -> Data {
    do {
        guard
            envelope.version == 1,
            envelope.sequence > 0,
            let nonce = Data(relayBase64URL: envelope.nonce),
            nonce.count == 12,
            let combined = Data(relayBase64URL: envelope.ciphertext),
            combined.count >= 16
        else {
            throw RelayCloudCryptoError.invalidEnvelope
        }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: combined.dropLast(16),
            tag: combined.suffix(16)
        )
        return try AES.GCM.open(
            box,
            using: rootKey,
            authenticating: relayCanonicalAAD(envelope.routing)
        )
    } catch {
        throw RelayCloudCryptoError.authenticationFailed
    }
}

func relayOpenPairingPayload(
    _ envelope: RelayCloudPairingPayloadEnvelope,
    requestID: String,
    hostID: String,
    rootKey: SymmetricKey
) throws -> RelayCloudPairingCredential {
    do {
        guard
            envelope.version == 1,
            let nonce = Data(relayBase64URL: envelope.nonce),
            nonce.count == 12,
            let combined = Data(relayBase64URL: envelope.ciphertext),
            combined.count >= 16
        else {
            throw RelayCloudCryptoError.invalidEnvelope
        }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: combined.dropLast(16),
            tag: combined.suffix(16)
        )
        let request = String(decoding: try JSONEncoder().encode(requestID), as: UTF8.self)
        let host = String(decoding: try JSONEncoder().encode(hostID), as: UTF8.self)
        let aad = Data("{\"version\":1,\"requestId\":\(request),\"hostId\":\(host)}".utf8)
        return try JSONDecoder().decode(
            RelayCloudPairingCredential.self,
            from: AES.GCM.open(box, using: rootKey, authenticating: aad)
        )
    } catch {
        throw RelayCloudCryptoError.authenticationFailed
    }
}

struct RelayCloudReplayWindow: Sendable {
    private(set) var highestSequences: [String: Int64]

    init(highestSequences: [String: Int64] = [:]) {
        self.highestSequences = highestSequences
    }

    mutating func accept(senderID: String, sequence: Int64) throws {
        guard sequence > (highestSequences[senderID] ?? 0) else {
            throw RelayCloudCryptoError.replay
        }
        highestSequences[senderID] = sequence
    }
}

func relayCanonicalRequest(
    deviceID: String,
    method: String,
    path: String,
    body: Data,
    timestamp: Int64,
    nonce: String
) -> Data {
    let digest = SHA256.hash(data: body)
        .map { String(format: "%02x", $0) }
        .joined()
    return Data(
        [deviceID, method.uppercased(), path, digest, String(timestamp), nonce]
            .joined(separator: "\n").utf8
    )
}

private func relayCanonicalAAD(_ routing: RelayTunnelRouting) -> Data {
    func json(_ value: String) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }
    return Data(
        "{\"version\":\(routing.version),\"messageId\":\(json(routing.messageID)),\"accountId\":\(json(routing.accountID)),\"hostId\":\(json(routing.hostID)),\"senderId\":\(json(routing.senderID)),\"recipientId\":\(json(routing.recipientID)),\"sentAt\":\(routing.sentAt),\"sequence\":\(routing.sequence)}".utf8
    )
}

extension Data {
    init?(relayBase64URL: String) {
        var value = relayBase64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }

    var relayBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
