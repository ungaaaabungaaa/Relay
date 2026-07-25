import CryptoKit
import Foundation

public enum RelayCloudHostKeysError: Error, Equatable, Sendable {
    case invalidStoredKey
}

public struct RelayCloudHostKeys: Sendable {
    public let signingPrivateKey: P256.Signing.PrivateKey
    public let agreementPrivateKey: P256.KeyAgreement.PrivateKey

    public var signingPublicKey: String {
        signingPrivateKey.publicKey.x963Representation.base64EncodedString()
    }

    public var agreementPublicKey: String {
        agreementPrivateKey.publicKey.x963Representation.base64EncodedString()
    }

    public var fingerprint: String {
        let publicMaterial =
            signingPrivateKey.publicKey.x963Representation
            + agreementPrivateKey.publicKey.x963Representation
        let prefix = SHA256.hash(data: publicMaterial)
            .prefix(8)
            .map { String(format: "%02X", $0) }
            .joined()
        return stride(from: 0, to: prefix.count, by: 4)
            .map { offset in
                let start = prefix.index(prefix.startIndex, offsetBy: offset)
                let end = prefix.index(start, offsetBy: 4)
                return String(prefix[start..<end])
            }
            .joined(separator: ":")
    }

    public static func loadOrCreate(
        in store: any SecretStoring
    ) throws -> RelayCloudHostKeys {
        let signing: P256.Signing.PrivateKey
        if let encoded = try store.value(for: .cloudSigningPrivateKey) {
            guard
                let raw = Data(base64Encoded: encoded),
                let stored = try? P256.Signing.PrivateKey(rawRepresentation: raw)
            else {
                throw RelayCloudHostKeysError.invalidStoredKey
            }
            signing = stored
        } else {
            signing = P256.Signing.PrivateKey()
            try store.set(
                signing.rawRepresentation.base64EncodedString(),
                for: .cloudSigningPrivateKey
            )
        }

        let agreement: P256.KeyAgreement.PrivateKey
        if let encoded = try store.value(for: .cloudAgreementPrivateKey) {
            guard
                let raw = Data(base64Encoded: encoded),
                let stored = try? P256.KeyAgreement.PrivateKey(
                    rawRepresentation: raw
                )
            else {
                throw RelayCloudHostKeysError.invalidStoredKey
            }
            agreement = stored
        } else {
            agreement = P256.KeyAgreement.PrivateKey()
            try store.set(
                agreement.rawRepresentation.base64EncodedString(),
                for: .cloudAgreementPrivateKey
            )
        }
        return RelayCloudHostKeys(
            signingPrivateKey: signing,
            agreementPrivateKey: agreement
        )
    }
}
