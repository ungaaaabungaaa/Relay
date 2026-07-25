import CryptoKit
import Foundation
import Security

enum RelayWatchIdentityError: Error {
    case keyCreationFailed
    case publicKeyUnavailable
    case signingFailed
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

final class RelayWatchIdentity: @unchecked Sendable {
    private let tag = Data("dev.ungaaaabungaaa.relay.watch.identity".utf8)

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

private extension String {
    func chunked(into size: Int) -> [String] {
        stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: min(size, count - offset))
            return String(self[start..<end])
        }
    }
}
