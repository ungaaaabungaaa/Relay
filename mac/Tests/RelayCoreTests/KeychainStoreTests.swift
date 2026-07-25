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

@Test
func hostIdentityIsStableAndExposesOnlyAShortFingerprint() throws {
    let store = KeychainStore(
        service: "dev.ungaaaabungaaa.relay.host-tests",
        backend: MemoryKeychainBackend()
    )
    let bytes = Array(0..<32).map(UInt8.init)

    let first = try RelayHostIdentity.loadOrCreate(
        in: store,
        randomBytes: { bytes }
    )
    let second = try RelayHostIdentity.loadOrCreate(
        in: store,
        randomBytes: { Array(repeating: 255, count: 32) }
    )

    #expect(first == second)
    #expect(first.fingerprint == "630D:CD29:66C4:3366")
    #expect(!String(describing: first).contains(Data(bytes).base64EncodedString()))
    #expect(try store.value(for: .hostIdentity) == Data(bytes).base64EncodedString())
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
