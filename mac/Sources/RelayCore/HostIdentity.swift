import CryptoKit
import Foundation
import Security

public enum RelayHostIdentityError: Error, Equatable, Sendable {
    case invalidStoredIdentity
    case randomGenerationFailed(OSStatus)
}

public struct RelayHostIdentity: Equatable, Sendable, CustomStringConvertible {
    private static let byteCount = 32
    private let secret: Data

    private init(secret: Data) {
        self.secret = secret
    }

    public static func loadOrCreate(
        in store: any SecretStoring
    ) throws -> RelayHostIdentity {
        try loadOrCreate(in: store, randomBytes: secureRandomBytes)
    }

    public static func loadOrCreate(
        in store: any SecretStoring,
        randomBytes: @Sendable () throws -> [UInt8]
    ) throws -> RelayHostIdentity {
        if let encoded = try store.value(for: .hostIdentity) {
            guard
                let stored = Data(base64Encoded: encoded),
                stored.count == byteCount
            else {
                throw RelayHostIdentityError.invalidStoredIdentity
            }
            return RelayHostIdentity(secret: stored)
        }

        let bytes = try randomBytes()
        guard bytes.count == byteCount else {
            throw RelayHostIdentityError.invalidStoredIdentity
        }
        let secret = Data(bytes)
        try store.set(secret.base64EncodedString(), for: .hostIdentity)
        return RelayHostIdentity(secret: secret)
    }

    public var fingerprint: String {
        let digest = SHA256.hash(data: secret)
        let prefix = digest.prefix(8).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: prefix.count, by: 4)
            .map { offset in
                let start = prefix.index(prefix.startIndex, offsetBy: offset)
                let end = prefix.index(start, offsetBy: min(4, prefix.count - offset))
                return String(prefix[start..<end])
            }
            .joined(separator: ":")
    }

    public var description: String {
        "RelayHostIdentity(fingerprint: \(fingerprint), secret: [REDACTED])"
    }

    private static func secureRandomBytes() throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw RelayHostIdentityError.randomGenerationFailed(status)
        }
        return bytes
    }
}
