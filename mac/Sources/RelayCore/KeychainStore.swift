import Foundation
import Security

public enum RelaySecret: String, CaseIterable, Sendable {
    case adminToken = "admin-token"
    case hostIdentity = "host-identity"
    case openAIAPIKey = "openai-api-key"
    case cloudRefreshToken = "cloud-refresh-token"
    case cloudAgreementPrivateKey = "cloud-agreement-private-key"
    case cloudRootKeys = "cloud-root-keys"
}

public enum KeychainStoreError: Error, Equatable, Sendable {
    case operationFailed(OSStatus)
    case invalidText
}

public protocol SecretStoring: Sendable {
    func value(for secret: RelaySecret) throws -> String?
    func set(_ value: String, for secret: RelaySecret) throws
    func remove(_ secret: RelaySecret) throws
}

public protocol KeychainBackend: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public struct KeychainStore: SecretStoring, Sendable, CustomStringConvertible {
    private let service: String
    private let backend: any KeychainBackend

    public init(
        service: String = "com.relayforcodex.mac",
        backend: any KeychainBackend = SecurityKeychainBackend()
    ) {
        self.service = service
        self.backend = backend
    }

    public func value(for secret: RelaySecret) throws -> String? {
        guard let data = try backend.read(service: service, account: secret.rawValue) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidText
        }
        return value
    }

    public func set(_ value: String, for secret: RelaySecret) throws {
        try backend.write(
            Data(value.utf8),
            service: service,
            account: secret.rawValue
        )
    }

    public func remove(_ secret: RelaySecret) throws {
        try backend.delete(service: service, account: secret.rawValue)
    }

    public var description: String {
        "KeychainStore(service: \(service), values: [REDACTED])"
    }
}

public struct SecurityKeychainBackend: KeychainBackend {
    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ] as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError.operationFailed(status)
        }
        return data
    }

    public func write(_ data: Data, service: String, account: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        let updated = SecItemUpdate(
            query,
            [kSecValueData: data] as CFDictionary
        )
        if updated == errSecSuccess {
            return
        }
        guard updated == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(updated)
        }
        let added = SecItemAdd(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData: data,
            ] as CFDictionary,
            nil
        )
        guard added == errSecSuccess else {
            throw KeychainStoreError.operationFailed(added)
        }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ] as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(status)
        }
    }
}
