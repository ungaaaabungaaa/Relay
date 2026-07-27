import CryptoKit
import Foundation
import Security

enum RelayWatchIdentityError: Error {
    case keyCreationFailed
    case publicKeyUnavailable
    case signingFailed
}

protocol RelayWatchSigningIdentity: Sendable {
    func publicKeyPEM() throws -> String
    func fingerprint() throws -> String
    func sign(_ canonical: Data) throws -> String
    func delete()
}

protocol RelayWatchAgreementIdentityProtocol: Sendable {
    func publicKeyBase64URL() throws -> String
    func deriveRootKey(
        peerPublicKey: String,
        pairingSessionNonce: String
    ) throws -> SymmetricKey
    func delete()
}

protocol RelayWatchCloudStoring: Sendable {
    func load() -> RelayCloudDeviceConfig?
    func save(_ config: RelayCloudDeviceConfig) throws
    var outgoingSequence: Int64 { get set }
    var hostSequence: Int64 { get set }
    func delete()
}

func relaySubjectPublicKeyInfo(_ rawPoint: Data) throws -> Data {
    guard rawPoint.count == 65, rawPoint.first == 0x04 else {
        throw RelayWatchIdentityError.publicKeyUnavailable
    }
    let p256SubjectPublicKeyInfoPrefix = Data([
        0x30, 0x59,
        0x30, 0x13,
        0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
        0x03, 0x42, 0x00,
    ])
    return p256SubjectPublicKeyInfoPrefix + rawPoint
}

final class RelayWatchIdentity: RelayWatchSigningIdentity, @unchecked Sendable {
    private let tag = Data("com.relayforcodex.watch.signing".utf8)

    func publicKeyPEM() throws -> String {
        let privateKey = try loadOrCreate()
        guard
            let publicKey = SecKeyCopyPublicKey(privateKey),
            let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else {
            throw RelayWatchIdentityError.publicKeyUnavailable
        }
        let base64 = try relaySubjectPublicKeyInfo(data).base64EncodedString()
        return "-----BEGIN PUBLIC KEY-----\n"
            + base64.chunked(into: 64).joined(separator: "\n")
            + "\n-----END PUBLIC KEY-----\n"
    }

    func fingerprint() throws -> String {
        let digest = SHA256.hash(data: Data(try publicKeyPEM().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return digest.chunked(into: 4).prefix(8).joined(separator: ":")
    }

    func sign(_ canonical: Data) throws -> String {
        let key = try loadOrCreate()
        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                key,
                .ecdsaSignatureMessageX962SHA256,
                canonical as CFData,
                &error
            ) as Data?
        else {
            if let error {
                throw error.takeRetainedValue()
            }
            throw RelayWatchIdentityError.signingFailed
        }
        return signature.base64EncodedString()
    }

    func delete() {
        SecItemDelete(
            [
                kSecClass: kSecClassKey,
                kSecAttrApplicationTag: tag,
                kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            ] as CFDictionary
        )
    }

    private func loadOrCreate() throws -> SecKey {
        let query = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: tag,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef: true,
        ] as CFDictionary
        var existing: CFTypeRef?
        if SecItemCopyMatching(query, &existing) == errSecSuccess,
           let existing,
           CFGetTypeID(existing) == SecKeyGetTypeID() {
            return (existing as! SecKey)
        }
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage,
            nil
        )
        let attributes = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: tag,
                kSecAttrAccessControl: access as Any,
            ],
        ] as CFDictionary
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes, &error) else {
            if let error {
                throw error.takeRetainedValue()
            }
            throw RelayWatchIdentityError.keyCreationFailed
        }
        return key
    }
}

final class RelayWatchAgreementIdentity: RelayWatchAgreementIdentityProtocol, @unchecked Sendable {
    private let keychain = RelayWatchKeychain()
    private let account = "agreement-private-key"

    func publicKeyBase64URL() throws -> String {
        try loadOrCreate().publicKey.x963Representation.relayBase64URL
    }

    func deriveRootKey(
        peerPublicKey: String,
        pairingSessionNonce: String
    ) throws -> SymmetricKey {
        guard
            let peerData = Data(relayBase64URL: peerPublicKey),
            let nonce = Data(relayBase64URL: pairingSessionNonce)
        else {
            throw RelayCloudCryptoError.invalidEnvelope
        }
        return try relayDeriveRootKey(
            privateKey: loadOrCreate(),
            peerPublicKey: P256.KeyAgreement.PublicKey(
                x963Representation: peerData
            ),
            pairingSessionNonce: nonce
        )
    }

    func delete() {
        keychain.delete(account: account)
    }

    private func loadOrCreate() throws -> P256.KeyAgreement.PrivateKey {
        if let stored = keychain.read(account: account) {
            return try P256.KeyAgreement.PrivateKey(rawRepresentation: stored)
        }
        let created = P256.KeyAgreement.PrivateKey()
        try keychain.write(created.rawRepresentation, account: account)
        return created
    }
}

final class RelayWatchCloudStore: RelayWatchCloudStoring, @unchecked Sendable {
    private let keychain = RelayWatchKeychain()
    private let account = "cloud-device-config"
    private let preferences = UserDefaults.standard

    func load() -> RelayCloudDeviceConfig? {
        guard let data = keychain.read(account: account) else { return nil }
        return try? JSONDecoder().decode(RelayCloudDeviceConfig.self, from: data)
    }

    func save(_ config: RelayCloudDeviceConfig) throws {
        try keychain.write(JSONEncoder().encode(config), account: account)
        preferences.set(Int64(0), forKey: "cloud-outgoing-sequence")
        preferences.set(Int64(0), forKey: "cloud-host-sequence")
    }

    var outgoingSequence: Int64 {
        get { Int64(preferences.integer(forKey: "cloud-outgoing-sequence")) }
        set { preferences.set(newValue, forKey: "cloud-outgoing-sequence") }
    }

    var hostSequence: Int64 {
        get { Int64(preferences.integer(forKey: "cloud-host-sequence")) }
        set { preferences.set(newValue, forKey: "cloud-host-sequence") }
    }

    func delete() {
        keychain.delete(account: account)
        preferences.removeObject(forKey: "cloud-outgoing-sequence")
        preferences.removeObject(forKey: "cloud-host-sequence")
    }
}

private final class RelayWatchKeychain: @unchecked Sendable {
    private let service = "com.relayforcodex.watch"

    func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    func write(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updated == errSecItemNotFound {
            var insertion = query
            insertion.merge(attributes) { _, new in new }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw RelayWatchIdentityError.keyCreationFailed
            }
        } else if updated != errSecSuccess {
            throw RelayWatchIdentityError.keyCreationFailed
        }
    }

    func delete(account: String) {
        SecItemDelete(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ] as CFDictionary
        )
    }
}

private extension String {
    func chunked(into size: Int) -> [String] {
        stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: min(size, count - offset))
            return String(self[start..<end])
        }
    }
}
