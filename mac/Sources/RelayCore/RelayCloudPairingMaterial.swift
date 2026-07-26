import CryptoKit
import Foundation

public enum RelayCloudPairingMaterialError: Error, Equatable, Sendable {
    case invalidApproval
}

public enum RelayCloudPairingMaterial {
    public static func registration(
        hostID: String,
        request: RelayCloudPairingRequest,
        approved: RelayCloudApprovedDevice,
        hostKeys: RelayCloudHostKeys
    ) throws -> AdminCloudDeviceRegistration {
        guard
            approved.hostId == hostID,
            let publicKeyData = Data(relayBase64: request.agreementPublicKey),
            let watchPublicKey = try? P256.KeyAgreement.PublicKey(
                x963Representation: publicKeyData
            ),
            let nonce = Data(relayBase64: approved.sessionNonce),
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
        return AdminCloudDeviceRegistration(
            hostId: hostID,
            deviceId: approved.id,
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
