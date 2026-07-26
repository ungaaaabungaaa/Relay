import CryptoKit
import Foundation
import Security

public enum RelayCloudPairingMaterialError: Error, Equatable, Sendable {
    case invalidApproval
}

public struct RelayCloudPairingPayloadEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var nonce: String
    public var ciphertext: String

    public init(version: Int, nonce: String, ciphertext: String) {
        self.version = version
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}

public struct RelayCloudPairingCredential: Codable, Equatable, Sendable {
    public var accountId: String
    public var hostId: String
    public var deviceId: String
    public var credential: String
    public var apiVersion: Int
    public var minimumApiVersion: Int
    public var maximumApiVersion: Int
}

public struct RelayCloudPreparedPairing: Sendable {
    public var device: RelayCloudApprovedDevice
    public var registration: AdminCloudDeviceRegistration
    public var credentialHash: String
    public var payload: RelayCloudPairingPayloadEnvelope
    public var rawCredential: String
}

public enum RelayCloudPairingMaterial {
    public static func prepare(
        accountID: String,
        hostID: String,
        request: RelayCloudPairingRequest,
        sessionNonce: String,
        hostKeys: RelayCloudHostKeys
    ) throws -> RelayCloudPreparedPairing {
        guard
            !accountID.isEmpty,
            !hostID.isEmpty,
            let publicKeyData = Data(relayBase64: request.agreementPublicKey),
            let watchPublicKey = try? P256.KeyAgreement.PublicKey(
                x963Representation: publicKeyData
            ),
            let nonce = Data(relayBase64: sessionNonce),
            nonce.count >= 16
        else {
            throw RelayCloudPairingMaterialError.invalidApproval
        }
        let rootKey = try RelayCloudCrypto.deriveRootKey(
            privateKey: hostKeys.agreementPrivateKey,
            peerPublicKey: watchPublicKey,
            pairingSessionNonce: nonce
        )
        let rootKeyData = rootKey.withUnsafeBytes { Data($0) }
        let deviceID = UUID().uuidString.lowercased()
        let rawCredential = "\(UUID().uuidString.lowercased()).\(randomData(count: 32).relayBase64URL)"
        let credential = RelayCloudPairingCredential(
            accountId: accountID,
            hostId: hostID,
            deviceId: deviceID,
            credential: rawCredential,
            apiVersion: 1,
            minimumApiVersion: 1,
            maximumApiVersion: 1
        )
        let payload = try seal(
            credential,
            requestID: request.id,
            hostID: hostID,
            rootKey: rootKey
        )
        let registration = AdminCloudDeviceRegistration(
            accountId: accountID,
            hostId: hostID,
            deviceId: deviceID,
            name: request.metadata.model.isEmpty
                ? "Relay Watch"
                : request.metadata.model,
            signingPublicKey: request.signingPublicKey,
            rootKey: rootKeyData.relayBase64URL,
            metadata: AdminDeviceMetadata(
                platform: request.metadata.platform,
                manufacturer: request.metadata.manufacturer,
                model: request.metadata.model,
                osVersion: request.metadata.osVersion,
                appVersion: request.metadata.appVersion,
                screenShape: request.metadata.screenShape
            )
        )
        return RelayCloudPreparedPairing(
            device: RelayCloudApprovedDevice(
                id: deviceID,
                hostId: hostID,
                sessionNonce: sessionNonce
            ),
            registration: registration,
            credentialHash: Data(SHA256.hash(data: Data(rawCredential.utf8)))
                .relayBase64URL,
            payload: payload,
            rawCredential: rawCredential
        )
    }

    public static func open(
        _ envelope: RelayCloudPairingPayloadEnvelope,
        requestID: String,
        hostID: String,
        rootKey: SymmetricKey
    ) throws -> RelayCloudPairingCredential {
        do {
            guard
                envelope.version == 1,
                let nonce = Data(relayBase64: envelope.nonce),
                nonce.count == 12,
                let combined = Data(relayBase64: envelope.ciphertext),
                combined.count >= 16
            else {
                throw RelayCloudPairingMaterialError.invalidApproval
            }
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: combined.dropLast(16),
                tag: combined.suffix(16)
            )
            let plaintext = try AES.GCM.open(
                box,
                using: rootKey,
                authenticating: pairingAAD(requestID: requestID, hostID: hostID)
            )
            return try JSONDecoder().decode(
                RelayCloudPairingCredential.self,
                from: plaintext
            )
        } catch {
            throw RelayCloudPairingMaterialError.invalidApproval
        }
    }

    private static func seal(
        _ credential: RelayCloudPairingCredential,
        requestID: String,
        hostID: String,
        rootKey: SymmetricKey
    ) throws -> RelayCloudPairingPayloadEnvelope {
        let nonceData = randomData(count: 12)
        let sealed = try AES.GCM.seal(
            JSONEncoder().encode(credential),
            using: rootKey,
            nonce: try AES.GCM.Nonce(data: nonceData),
            authenticating: pairingAAD(requestID: requestID, hostID: hostID)
        )
        return RelayCloudPairingPayloadEnvelope(
            version: 1,
            nonce: nonceData.relayBase64URL,
            ciphertext: (sealed.ciphertext + sealed.tag).relayBase64URL
        )
    }

    private static func pairingAAD(requestID: String, hostID: String) -> Data {
        let request = String(data: try! JSONEncoder().encode(requestID), encoding: .utf8)!
        let host = String(data: try! JSONEncoder().encode(hostID), encoding: .utf8)!
        return Data("{\"version\":1,\"requestId\":\(request),\"hostId\":\(host)}".utf8)
    }

    private static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes)
    }
}

private extension Data {
    init?(relayBase64: String) {
        var value = relayBase64
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
