import Foundation
import Testing
@testable import RelayCore

@Test
func keychainStoreReadsWritesAndDeletesThroughItsSecureBackend() throws {
    let backend = MemoryKeychainBackend()
    let store = KeychainStore(
        service: "dev.ungaaaabungaaa.relay.tests",
        backend: backend
    )

    try store.set("admin-secret", for: .adminToken)
    try store.set("voice-secret", for: .openAIAPIKey)
    #expect(try store.value(for: .adminToken) == "admin-secret")
    #expect(try store.value(for: .openAIAPIKey) == "voice-secret")

    try store.remove(.openAIAPIKey)
    #expect(try store.value(for: .openAIAPIKey) == nil)
    #expect(!String(describing: store).contains("admin-secret"))
}

@Test
func keychainErrorsNeverIncludeTheSecretValue() {
    let backend = FailingKeychainBackend()
    let store = KeychainStore(service: "dev.ungaaaabungaaa.relay.tests", backend: backend)

    #expect(throws: KeychainStoreError.self) {
        try store.set("must-never-appear", for: .adminToken)
    }
    do {
        try store.set("must-never-appear", for: .adminToken)
    } catch {
        #expect(!String(describing: error).contains("must-never-appear"))
    }
}

private final class MemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(service: String, account: String) throws -> Data? {
        lock.withLock { values["\(service):\(account)"] }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock {
            values["\(service):\(account)"] = data
        }
    }

    func delete(service: String, account: String) throws {
        _ = lock.withLock {
            values.removeValue(forKey: "\(service):\(account)")
        }
    }
}

private struct FailingKeychainBackend: KeychainBackend {
    func read(service: String, account: String) throws -> Data? {
        throw KeychainStoreError.operationFailed(-1)
    }

    func write(_ data: Data, service: String, account: String) throws {
        throw KeychainStoreError.operationFailed(-1)
    }

    func delete(service: String, account: String) throws {
        throw KeychainStoreError.operationFailed(-1)
    }
}
